import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/glass_date_picker_dialog.dart';
import '../../../core/widgets/hanger_loading_indicator.dart';
import '../../outfits/data/outfit_repository.dart';
import '../../outfits/domain/saved_outfit.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({ super.key});
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

  String _formattedFullDate(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dayName = days[date.weekday - 1];
    final monthName = months[date.month - 1];
    return '$dayName, ${date.day} $monthName ${date.year}';
  }

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

  Future<void> _selectDate() async {
    final date = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => GlassDatePickerDialog(initialDate: _date),
    );
    if (date != null) {
      setState(() => _date = DateUtils.dateOnly(date));
      await _load();
    }
  }

  Future<void> _schedule(String slot) async {
    if (_actionInProgress) return;
    final entryDate = _date;
    setState(() => _actionInProgress = true);
    try {
      final outfits = await _outfits.list();
      if (!mounted) return;
      final result = await showDialog<_ScheduleValues>(
        context: context,
        barrierColor: Colors.black26,
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
      barrierColor: Colors.black26,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[900]!.withOpacity(0.60)
                  : Colors.white.withOpacity(0.60),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clear schedule?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This removes the outfit from this time slot.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.onSurface,
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _actionInProgress = true);
    try {
      await _client.dio.delete(
        '/api/v1/calendar/${entry['id']}',
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

  String _slotLabel(String slot) => switch (slot) {
    'morning_college' => 'Morning',
    'afternoon' => 'Afternoon',
    'evening' => 'Evening',
    'night' => 'Night',
    _ => slot,
  };

  IconData _slotIcon(String slot) => switch (slot) {
    'morning_college' => Icons.wb_sunny_outlined,
    'afternoon' => Icons.wb_twilight,
    'evening' => Icons.nights_stay_outlined,
    'night' => Icons.bedtime_outlined,
    _ => Icons.schedule,
  };

  Widget _buildDatePill() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.2)
                  : Colors.white.withOpacity(0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.white.withOpacity(0.5),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _actionInProgress ? null : _selectDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formattedFullDate(_date),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_drop_down,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.white.withOpacity(0.5),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Material(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.2)
                  : Colors.white.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverAppBar(
          title: const Text('Calendar'),
          pinned: true,
          floating: true,
          backgroundColor: Colors.transparent,
          flexibleSpace: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.white.withOpacity(0.3),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              _buildDatePill(),
              const SizedBox(height: 8),
            ],
          ),
        ),
        if (_loading)
          const SliverFillRemaining(child: Center(child: HangerLoadingIndicator()))
        else if (_error != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              children: [
                const SizedBox(height: 100),
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
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final slots = ['morning_college', 'afternoon', 'evening', 'night'];
                  final slot = slots[index];
                  final entry = _entries
                      .cast<Map<String, dynamic>?>()
                      .firstWhere(
                        (entry) => entry?['slot'] == slot,
                        orElse: () => null,
                      );
                  return _buildGlassCard(
                    onTap: entry?['outfit_id'] == null
                        ? null
                        : () => context.push(
                              '/outfits/${entry!['outfit_id']}',
                              
                            ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _slotIcon(slot),
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _slotLabel(slot),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                entry?['outfit_name'] as String? ?? 'No outfit scheduled',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(
                                    entry?['outfit_name'] == null ? 0.5 : 0.8,
                                  ),
                                  fontWeight: entry?['outfit_name'] == null ? FontWeight.normal : FontWeight.w500,
                                ),
                              ),
                              if (entry?['notes'] != null && (entry!['notes'] as String).isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Notes: ${entry['notes']}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            entry == null ? Icons.add_circle_outline : Icons.remove_circle_outline,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: _actionInProgress
                              ? null
                              : () => entry == null ? _schedule(slot) : _clear(entry),
                        ),
                      ],
                    ),
                  );
                },
                childCount: 4,
              ),
            ),
          ),
      ],
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
  void initState() {
    super.initState();
    _notes.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceFill = isDark ? Colors.grey[850]! : Colors.grey[100]!;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: isDark ? Colors.grey[900]!.withOpacity(0.60) : Colors.white.withOpacity(0.60),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Select Outfit',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<SavedOutfit>(
                    key: ValueKey(_selected?.id),
                    initialValue: _selected,
                    isExpanded: true,
                    menuMaxHeight: 360,
                    dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: surfaceFill,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: widget.outfits
                        .map(
                          (outfit) => DropdownMenuItem(
                            value: outfit,
                            child: Text(
                              outfit.name ?? 'Untitled outfit',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _selected = value),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Notes (optional)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notes,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: surfaceFill,
                      hintText: 'Add notes for this occasion...',
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_notes.text.length}/1000',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.onSurface,
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : const Color(0xFF5C0024),
                        ),
                        onPressed: _selected == null
                            ? null
                            : () => Navigator.pop(
                                  context,
                                  _ScheduleValues(
                                    outfit: _selected!,
                                    notes: _notes.text.trim(),
                                  ),
                                ),
                        child: const Text('Save schedule'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


