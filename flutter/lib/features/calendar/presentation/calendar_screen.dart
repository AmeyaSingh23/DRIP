import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../outfits/data/outfit_repository.dart';
import '../../outfits/domain/saved_outfit.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({required this.token, super.key});
  final String token;
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _client = ApiClient();
  final _outfits = OutfitRepository(ApiClient());
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  List<Map<String, dynamic>> _entries = const [];
  bool _loading = true;
  bool _actionInProgress = false;
  String? _error;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dateText(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _load() async {
    final requestEpoch = ++_loadEpoch;
    final requestedDate = _date;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _client.dio.get<List<dynamic>>(
        '/api/v1/calendar',
        queryParameters: {
          'start': requestedDate.toIso8601String().substring(0, 10),
          'end': requestedDate.toIso8601String().substring(0, 10),
        },
        options: Options(headers: {'Authorization': 'Bearer ${widget.token}'}),
      );
      if (mounted && requestEpoch == _loadEpoch && _date == requestedDate) {
        setState(
          () =>
              _entries =
                  (response.data ?? const [])
                      .whereType<Map<String, dynamic>>()
                      .toList(),
        );
      }
    } on DioException catch (error) {
      if (mounted && requestEpoch == _loadEpoch && _date == requestedDate) {
        setState(
          () => _error = _messageFor(error, 'Could not load the calendar.'),
        );
      }
    } finally {
      if (mounted && requestEpoch == _loadEpoch && _date == requestedDate) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _schedule(String slot) async {
    if (_actionInProgress) return;
    final entryDate = _date;
    setState(() => _actionInProgress = true);
    try {
      final outfits = await _outfits.list(token: widget.token);
      if (!mounted) return;
      final result = await showDialog<_ScheduleValues>(
        context: context,
        builder:
            (context) => _ScheduleDialog(
              title: 'Schedule ${_slotLabel(slot)}',
              outfits: outfits,
            ),
      );
      if (result == null) return;
      await _client.dio.put(
        '/api/v1/calendar',
        data: {
          'entry_date': entryDate.toIso8601String().substring(0, 10),
          'slot': slot,
          'outfit_id': result.outfit.id,
          if (result.notes.isNotEmpty) 'notes': result.notes,
        },
        options: Options(headers: {'Authorization': 'Bearer ${widget.token}'}),
      );
      if (mounted && _date == entryDate) await _load();
    } on DioException catch (error) {
      _showFailure(error, 'Could not save this schedule. Please try again.');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _clear(Map<String, dynamic> entry) async {
    if (_actionInProgress) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear schedule?'),
            content: const Text('This removes the outfit from this time slot.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _actionInProgress = true);
    try {
      await _client.dio.delete(
        '/api/v1/calendar/${entry['id']}',
        options: Options(headers: {'Authorization': 'Bearer ${widget.token}'}),
      );
      await _load();
    } on DioException catch (error) {
      _showFailure(error, 'Could not clear this schedule. Please try again.');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  String _messageFor(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map && data['detail'] is String
        ? data['detail'] as String
        : fallback;
  }

  void _showFailure(DioException error, String fallback) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_messageFor(error, fallback))));
  }

  String _slotLabel(String slot) =>
      {
        'morning_college': 'Morning / college',
        'afternoon': 'Afternoon',
        'evening': 'Evening',
        'night': 'Night',
      }[slot]!;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calendar')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          OutlinedButton.icon(
            onPressed:
                _actionInProgress
                    ? null
                    : () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                        initialDate: _date,
                      );
                      if (date != null) {
                        setState(() => _date = DateUtils.dateOnly(date));
                        await _load();
                      }
                    },
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(_dateText(_date)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text(_error!)),
                        const SizedBox(height: 12),
                        Center(
                          child: FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ),
                      ],
                    )
                    : ListView(
                      children:
                          [
                            'morning_college',
                            'afternoon',
                            'evening',
                            'night',
                          ].map((slot) {
                            final entry = _entries
                                .cast<Map<String, dynamic>?>()
                                .firstWhere(
                                  (entry) => entry?['slot'] == slot,
                                  orElse: () => null,
                                );
                            return Card(
                              child: ListTile(
                                onTap:
                                    entry?['outfit_id'] == null
                                        ? null
                                        : () => context.push(
                                          '/outfits/${entry!['outfit_id']}',
                                        ),
                                leading: const Icon(Icons.schedule),
                                title: Text(_slotLabel(slot)),
                                subtitle: Text(
                                  entry?['outfit_name'] as String? ??
                                      'No outfit scheduled',
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    entry == null
                                        ? Icons.add_circle_outline
                                        : Icons.remove_circle_outline,
                                  ),
                                  onPressed:
                                      _actionInProgress
                                          ? null
                                          : () =>
                                              entry == null
                                                  ? _schedule(slot)
                                                  : _clear(entry),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
          ),
        ],
      ),
    ),
  );
}

class _ScheduleValues {
  const _ScheduleValues({required this.outfit, required this.notes});
  final SavedOutfit outfit;
  final String notes;
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.title, required this.outfits});
  final String title;
  final List<SavedOutfit> outfits;
  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _notes = TextEditingController();
  SavedOutfit? _selected;
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<SavedOutfit>(
          key: ValueKey(_selected?.id),
          initialValue: _selected,
          isExpanded: true,
          menuMaxHeight: 360,
          borderRadius: BorderRadius.circular(12),
          decoration: const InputDecoration(labelText: 'Outfit'),
          items:
              widget.outfits
                  .map(
                    (outfit) => DropdownMenuItem(
                      value: outfit,
                      child: Text(
                        outfit.name ?? 'Untitled outfit',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (value) => setState(() => _selected = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            counterText: '',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            _selected == null
                ? null
                : () => Navigator.pop(
                  context,
                  _ScheduleValues(
                    outfit: _selected!,
                    notes: _notes.text.trim(),
                  ),
                ),
        child: const Text('Save'),
      ),
    ],
  );
}
