import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../../creative/presentation/creative_space_screen.dart';
import '../../wardrobe/presentation/wardrobe_change_notifier.dart';
import '../data/outfit_repository.dart';
import '../domain/outfit_preview.dart';
import '../domain/outfit_weather.dart';
import 'city_picker_sheet.dart';

enum _WeatherState { idle, loading, available, unavailable }

class OutfitGeneratorScreen extends ConsumerStatefulWidget {
  const OutfitGeneratorScreen({required this.token, super.key});

  final String token;

  @override
  ConsumerState<OutfitGeneratorScreen> createState() => _OutfitGeneratorScreenState();
}

class _LocationMessage implements Exception {
  const _LocationMessage(this.message);

  final String message;
}

class _OutfitGeneratorScreenState extends ConsumerState<OutfitGeneratorScreen> {
  final _repository = OutfitRepository(ApiClient());
  final _occasion = TextEditingController();
  final _notes = TextEditingController();
  DateTime _wearAt = DateTime.now();
  OutfitLocation? _location;
  bool _isCurrentLocation = false;
  OutfitWeatherContext? _weatherContext;
  _WeatherState _weatherState = _WeatherState.idle;
  CancelToken? _weatherCancelToken;
  int _weatherVersion = 0;
  OutfitPreview? _preview;
  String? _error;
  bool _generating = false;
  bool _saving = false;
  bool _gettingLocation = false;
  String? _saveIdempotencyKey;
  Timer? _retryTimer;
  DateTime? _retryAvailableAt;

  @override
  void dispose() {
    _weatherCancelToken?.cancel();
    _retryTimer?.cancel();
    _occasion.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _retrySeconds {
    final availableAt = _retryAvailableAt;
    if (availableAt == null) return 0;
    final milliseconds = availableAt.difference(DateTime.now()).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  void _startRetryCooldown(int seconds) {
    _retryTimer?.cancel();
    _retryAvailableAt = DateTime.now().add(
      Duration(seconds: seconds.clamp(1, 300)),
    );
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retrySeconds == 0) {
        setState(() => _retryAvailableAt = null);
        timer.cancel();
        return;
      }
      setState(() {});
    });
  }

  Future<void> _useCurrentLocation() async {
    if (_gettingLocation) return;
    setState(() {
      _gettingLocation = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationMessage(
          'Turn on location services to use your current location.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const _LocationMessage(
          'Location was not shared. Choose a city or continue without weather.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationMessage(
          'Location is blocked. Choose a city or enable it in Settings.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      String locationName = 'Current location';
      try {
        final placemarks = await geocoding.Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [p.locality, p.administrativeArea]
              .where((s) => s != null && s.isNotEmpty)
              .toList();
          if (parts.isNotEmpty) {
            locationName = parts.join(', ');
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _isCurrentLocation = true;
        _location = OutfitLocation(
          name: locationName,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      });
      _weatherInputsChanged();
    } on _LocationMessage catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'Could not get your location. Choose a city or try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _chooseCity() async {
    final location = await showModalBottomSheet<OutfitLocation>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => CityPickerSheet(token: widget.token, repository: _repository),
    );
    if (location == null || !mounted) return;
    setState(() {
      _isCurrentLocation = false;
      _location = location;
    });
    _weatherInputsChanged();
  }

  Future<void> _pickWearAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _wearAt.isBefore(now) ? now : _wearAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 15)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _wearAt.isBefore(now) ? now : _wearAt,
      ),
    );
    if (time == null || !mounted) return;
    setState(
      () =>
          _wearAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          ),
    );
    _weatherInputsChanged();
  }

  void _useNow() {
    setState(() => _wearAt = DateTime.now());
    _weatherInputsChanged();
  }

  void _weatherInputsChanged() {
    _weatherVersion += 1;
    _weatherCancelToken?.cancel();
    _weatherCancelToken = null;
    final location = _location;
    setState(() {
      _preview = null;
      _saveIdempotencyKey = null;
      _weatherContext = null;
      _weatherState =
          location == null ? _WeatherState.idle : _WeatherState.loading;
    });
    if (location != null) _refreshWeather(location, _weatherVersion);
  }

  Future<void> _refreshWeather(OutfitLocation location, int version) async {
    final cancelToken = CancelToken();
    _weatherCancelToken = cancelToken;
    try {
      final result = await _repository.weatherContext(
        token: widget.token,
        location: location,
        wearAt: _wearAt,
        cancelToken: cancelToken,
      );
      if (!mounted || version != _weatherVersion) return;
      setState(() {
        _weatherState =
            result.status == 'available' && result.weatherContext != null
                ? _WeatherState.available
                : _WeatherState.unavailable;
        _weatherContext = result.weatherContext;
      });
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) ||
          !mounted ||
          version != _weatherVersion) {
        return;
      }
      setState(() => _weatherState = _WeatherState.unavailable);
    }
  }

  String _wearAtLabel(BuildContext context) {
    final now = DateTime.now();
    final localizations = MaterialLocalizations.of(context);
    final sameDay =
        _wearAt.year == now.year &&
        _wearAt.month == now.month &&
        _wearAt.day == now.day;
    final date = sameDay ? 'Today' : localizations.formatMediumDate(_wearAt);
    return '$date, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(_wearAt))}';
  }

  String _messageFor(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (error.type == DioExceptionType.receiveTimeout) {
      return 'Outfit generation is taking longer than expected. Please try again.';
    }
    return 'Could not generate an outfit. Please try again.';
  }

  Future<void> _generate() async {
    if (_generating || _retrySeconds > 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _generating = true;
      _error = null;
      _preview = null;
      _saveIdempotencyKey = null;
    });
    try {
      final preview = await _repository.generate(
        token: widget.token,
        occasion: _occasion.text,
        styleNotes: _notes.text,
        location: _location,
        wearAt: _location == null ? null : _wearAt,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _saveIdempotencyKey = const Uuid().v4();
        });
        if (preview.isQuickPick) {
          _startRetryCooldown(preview.retryAfterSeconds ?? 2);
        } else {
          _retryTimer?.cancel();
          _retryAvailableAt = null;
        }
      }
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _save() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _saving = true);
    try {
      await _repository.save(
        token: widget.token,
        preview: preview,
        itemLayout: const [],
        idempotencyKey: _saveIdempotencyKey ??= const Uuid().v4(),
      );
      ref.read(outfitRevisionProvider.notifier).notifyChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Outfit saved to your wardrobe history.'),
          ),
        );
        setState(() {
          _preview = null;
          _saveIdempotencyKey = null;
        });
      }
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _generating || _saving;
    final canGenerate = !busy && _weatherState != _WeatherState.loading;
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && busy && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your outfit is still being processed. Please wait.',
              ),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create an outfit'),
          automaticallyImplyLeading: !busy,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Use your wardrobe',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Suggestions use your saved items only. Generation is a preview until you choose Save.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _occasion,
              enabled: !busy,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: 'Occasion (optional)',
                hintText: 'College, dinner, gym...',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              enabled: !busy,
              maxLength: 240,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Mood / vibe (optional)',
                hintText: 'Comfortable, minimal, colourful...',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When will you wear it?',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : _useNow,
                  icon: const Icon(Icons.schedule),
                  label: const Text('Now'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : _pickWearAt,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_wearAtLabel(context)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Where will you be?',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (_location != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(
                  _isCurrentLocation ? 'Current location' : _location!.name,
                ),
                subtitle: const Text(
                  'Used only to check weather for this outfit',
                ),
                trailing: IconButton(
                  tooltip: 'Clear location',
                  onPressed:
                      busy
                          ? null
                          : () {
                            setState(() {
                              _location = null;
                              _isCurrentLocation = false;
                            });
                            _weatherInputsChanged();
                          },
                  icon: const Icon(Icons.close),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      busy || _gettingLocation ? null : _useCurrentLocation,
                  icon: const Icon(Icons.my_location_outlined),
                  label: Text(
                    _gettingLocation
                        ? 'Finding location...'
                        : 'Use my location',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : _chooseCity,
                  icon: const Icon(Icons.search),
                  label: const Text('Choose a city'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _WeatherCard(
              state: _weatherState,
              weather: _weatherContext,
              location: _location,
              wearAtLabel: _wearAtLabel(context),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canGenerate ? _generate : null,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _generating
                    ? 'Creating outfit...'
                    : _weatherState == _WeatherState.loading
                    ? 'Checking weather...'
                    : 'Generate outfit',
              ),
            ),
            if (_generating) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 28),
              if (_preview!.isQuickPick) ...[
                const _InfoBanner(
                  message:
                      'Couldn’t create a personalised outfit right now. Here’s a simple combination from your wardrobe.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy || _retrySeconds > 0 ? null : _generate,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    _retrySeconds > 0
                        ? 'Try again in ${_retrySeconds}s'
                        : 'Try again',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                _preview!.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_preview!.rationale),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    _preview!.items
                        .map(
                          (item) => SizedBox(
                            width: 150,
                            height: 190,
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: CachedWardrobeImage(
                                        url: item.cloudinaryUrl,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      item.itemName ?? item.category,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : _save,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save outfit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          busy
                              ? null
                              : () => context.push(
                                '/creative',
                                extra: CreativeRouteArgs(
                                  token: widget.token,
                                  initialItems: _preview!.items,
                                  initialName: _preview!.name,
                                  initialOccasion: _preview!.occasion,
                                  startCollapsed: true,
                                ),
                              ),
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('Style on canvas'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.state,
    required this.weather,
    required this.location,
    required this.wearAtLabel,
  });

  final _WeatherState state;
  final OutfitWeatherContext? weather;
  final OutfitLocation? location;
  final String wearAtLabel;

  @override
  Widget build(BuildContext context) {
    if (location == null) {
      return const _InfoBanner(
        message:
            'Location is optional. Add it to include weather in your outfit suggestion.',
      );
    }
    if (state == _WeatherState.loading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${location!.name} · $wearAtLabel'),
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Checking weather...'),
            ],
          ),
        ),
      );
    }
    if (state == _WeatherState.unavailable || weather == null) {
      return const _InfoBanner(
        message:
            'Weather unavailable — your outfit will be based on mood, occasion and wardrobe only.',
      );
    }
    final details = <String>[
      '${weather!.temperatureC.round()}°C',
      'Feels like ${weather!.apparentTemperatureC.round()}°C',
      weather!.condition,
      if (weather!.precipitationProbability != null)
        '${weather!.precipitationProbability}% rain',
      if (weather!.windSpeedKmh != null)
        '${weather!.windSpeedKmh!.round()} km/h wind',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${weather!.locationName} · ${weather!.timeOfDay}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(details.join(' · ')),
            if (weather!.considerations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                weather!.considerations.first,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Weather data by Open-Meteo',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message),
  );
}
