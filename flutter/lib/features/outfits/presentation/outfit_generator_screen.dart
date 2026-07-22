import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/cached_wardrobe_image.dart';
import '../../../core/widgets/glass_date_picker_dialog.dart';
import '../../../core/widgets/glass_time_picker.dart';
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
      backgroundColor: Colors.transparent,
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
    final date = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => GlassDatePickerDialog(
        initialDate: _wearAt.isBefore(now) ? now : _wearAt,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: now.add(const Duration(days: 15)),
      ),
    );
    if (date == null || !mounted) return;
    
    final time = await showGlassTimePicker(
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
          _occasion.clear();
          _notes.clear();
          _location = null;
          _wearAt = DateTime.now();
          _weatherState = _WeatherState.idle;
          _weatherContext = null;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: PopScope(
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
        extendBody: true,
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverAppBar(
              title: const Text('Create an outfit'),
              automaticallyImplyLeading: !busy,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[900]!.withOpacity(0.50)
                        : Colors.white.withOpacity(0.50),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.5),
                          ),
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stylist preferences',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Describe your mood and occasion. Suggestions use items saved in your wardrobe.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Occasion (optional)', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                                ListenableBuilder(
                                  listenable: _occasion,
                                  builder: (context, _) => Text(
                                    '${_occasion.text.length}/50',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _occasion,
                              enabled: !busy,
                              maxLength: 50,
                              decoration: InputDecoration(
                                hintText: 'College, dinner, gym...',
                                hintStyle: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                ),
                                counterText: '',
                                filled: true,
                                fillColor: isDark ? Colors.grey[900]!.withOpacity(0.4) : Colors.white.withOpacity(0.5),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Mood / vibe (optional)', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                                ListenableBuilder(
                                  listenable: _notes,
                                  builder: (context, _) => Text(
                                    '${_notes.text.length}/240',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _notes,
                              enabled: !busy,
                              maxLength: 240,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: 'Comfortable, minimal, colourful...',
                                hintStyle: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                ),
                                counterText: '',
                                filled: true,
                                fillColor: isDark ? Colors.grey[900]!.withOpacity(0.4) : Colors.white.withOpacity(0.5),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.5),
                          ),
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'When & Where?',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'When will you wear it?',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: busy ? null : _pickWearAt,
                                style: FilledButton.styleFrom(
                                  backgroundColor: isDark ? Colors.grey[800]!.withOpacity(0.5) : Colors.white.withOpacity(0.7),
                                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.calendar_month_outlined),
                                label: Text(
                                  _wearAtLabel(context),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Where will you be?',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            if (_location != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey[900]!.withOpacity(0.4) : Colors.white.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.place_outlined, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _isCurrentLocation ? 'Current location' : _location!.name,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Used for weather checks',
                                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Clear location',
                                      onPressed: busy ? null : () {
                                        setState(() {
                                          _location = null;
                                          _isCurrentLocation = false;
                                        });
                                        _weatherInputsChanged();
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: busy || _gettingLocation ? null : _useCurrentLocation,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: isDark ? Colors.grey[800]!.withOpacity(0.5) : Colors.white.withOpacity(0.7),
                                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: const Icon(Icons.my_location_outlined),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _gettingLocation ? 'Finding...' : 'My location',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: busy ? null : _chooseCity,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: isDark ? Colors.grey[800]!.withOpacity(0.5) : Colors.white.withOpacity(0.7),
                                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: const Icon(Icons.search),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Choose a city',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _WeatherCard(
                      key: ValueKey('$_weatherState-${_weatherContext?.condition}'),
                      state: _weatherState,
                      weather: _weatherContext,
                      location: _location,
                      wearAtLabel: _wearAtLabel(context),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withOpacity(0.1),
                            border: Border.all(color: Colors.deepOrange.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.deepOrange[400]),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_error!, style: TextStyle(color: Colors.deepOrange[400]))),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_preview!.rationale),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children:
                          _preview!.items
                              .map(
                                (item) => SizedBox(
                                  width: 150,
                                  height: 190,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.4),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.5),
                                          ),
                                        ),
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
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFC2185B).withOpacity(isDark ? 0.6 : 0.85),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: busy ? null : _save,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.bookmark_add_outlined, color: Colors.white),
                                            const SizedBox(width: 8),
                                            Text(_saving ? 'Saving...' : 'Save outfit', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFC2185B).withOpacity(isDark ? 0.6 : 0.85),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: busy
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
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.palette_outlined, color: Colors.white),
                                            const SizedBox(width: 8),
                                            const Text('Style on canvas', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 32),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFC2185B).withOpacity(isDark ? 0.6 : 0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: canGenerate ? _generate : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_generating)
                                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  else
                                    const Icon(Icons.auto_awesome_outlined, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    _generating
                                        ? 'Creating outfit...'
                                        : _weatherState == _WeatherState.loading
                                            ? 'Checking weather...'
                                            : _preview != null
                                                ? 'Generate again'
                                                : 'Generate outfit',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    super.key,
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
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.white.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.white.withOpacity(0.5),
              ),
            ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.3)
                : Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.5),
            ),
          ),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Weather data by Open-Meteo',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withOpacity(0.3)
              : Colors.white.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.5),
          ),
        ),
        child: Text(message),
      ),
    ),
  );
}
