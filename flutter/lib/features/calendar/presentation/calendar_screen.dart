import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dateText(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await _client.dio.get<List<dynamic>>(
        '/api/v1/calendar',
        queryParameters: {
          'start': _date.toIso8601String().substring(0, 10),
          'end': _date.toIso8601String().substring(0, 10),
        },
        options: Options(headers: {'Authorization': 'Bearer ${widget.token}'}),
      );
      if (mounted) {
        setState(
          () =>
              _entries =
                  (response.data ?? const [])
                      .whereType<Map<String, dynamic>>()
                      .toList(),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _schedule(String slot) async {
    List<SavedOutfit> outfits;
    try {
      outfits = await _outfits.list(token: widget.token);
    } on DioException {
      return;
    }
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
        'entry_date': _date.toIso8601String().substring(0, 10),
        'slot': slot,
        'outfit_id': result.outfit.id,
        if (result.notes.isNotEmpty) 'notes': result.notes,
      },
      options: Options(headers: {'Authorization': 'Bearer ${widget.token}'}),
    );
    await _load();
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
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                initialDate: _date,
              );
              if (date != null) {
                setState(() => _date = date);
                _load();
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
                                leading: const Icon(Icons.schedule),
                                title: Text(_slotLabel(slot)),
                                subtitle: Text(
                                  entry?['outfit_name'] as String? ??
                                      'No outfit scheduled',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => _schedule(slot),
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
          decoration: const InputDecoration(labelText: 'Outfit'),
          items:
              widget.outfits
                  .map(
                    (outfit) => DropdownMenuItem(
                      value: outfit,
                      child: Text(outfit.name ?? 'Untitled outfit'),
                    ),
                  )
                  .toList(),
          onChanged: (value) => setState(() => _selected = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
