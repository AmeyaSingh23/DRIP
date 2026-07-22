import 'dart:ui';
import 'package:flutter/material.dart';

class GlassDatePickerDialog extends StatefulWidget {
  const GlassDatePickerDialog({
    required this.initialDate,
    this.firstDate,
    this.lastDate,
    super.key,
  });

  final DateTime initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<GlassDatePickerDialog> createState() => _GlassDatePickerDialogState();
}

class _GlassDatePickerDialogState extends State<GlassDatePickerDialog> {
  late DateTime _selectedDate;
  bool _manualMode = false;
  late final TextEditingController _dateController;
  String? _manualError;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _dateController = TextEditingController(
      text: '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
    );
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  void _parseManualDate(String val) {
    final parts = val.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      
      final first = widget.firstDate ?? DateTime(2020);
      final last = widget.lastDate ?? DateTime(2035);

      if (day != null && month != null && year != null && day >= 1 && day <= 31 && month >= 1 && month <= 12 && year >= first.year && year <= last.year) {
        try {
          final dt = DateTime(year, month, day);
          if (dt.isBefore(first) || dt.isAfter(last)) {
             setState(() => _manualError = 'Date out of range');
             return;
          }
          setState(() {
            _selectedDate = DateUtils.dateOnly(dt);
            _manualError = null;
          });
          return;
        } catch (_) {}
      }
    }
    setState(() => _manualError = 'Enter valid DD/MM/YYYY date');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceFill = isDark ? Colors.grey[850]! : Colors.grey[100]!;
    
    final first = widget.firstDate ?? DateTime(2020);
    final last = widget.lastDate ?? DateTime(2035);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: isDark ? Colors.grey[900]!.withOpacity(0.60) : Colors.white.withOpacity(0.60),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Date',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      IconButton(
                        tooltip: _manualMode ? 'Switch to calendar' : 'Type date manually',
                        icon: Icon(
                          _manualMode ? Icons.calendar_month : Icons.edit_calendar,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: () => setState(() => _manualMode = !_manualMode),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_manualMode) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Date (DD/MM/YYYY)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _dateController,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        hintText: 'e.g. 22/07/2026',
                        errorText: _manualError,
                        filled: true,
                        fillColor: surfaceFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: _parseManualDate,
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    SizedBox(
                      height: 320,
                      width: 320,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: isDark
                              ? Theme.of(context).colorScheme
                              : Theme.of(context).colorScheme.copyWith(
                                    primary: const Color(0xFFC2185B),
                                    onPrimary: Colors.white,
                                  ),
                        ),
                        child: CalendarDatePicker(
                          initialDate: _selectedDate.isBefore(first) ? first : (_selectedDate.isAfter(last) ? last : _selectedDate),
                          firstDate: first,
                          lastDate: last,
                          onDateChanged: (date) {
                            setState(() {
                              _selectedDate = DateUtils.dateOnly(date);
                              _dateController.text =
                                  '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}';
                            });
                          },
                        ),
                      ),
                    ),
                  ],
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
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          if (_manualMode && _manualError != null) return;
                          Navigator.pop(context, _selectedDate);
                        },
                        style: FilledButton.styleFrom(
                           backgroundColor: Theme.of(context).colorScheme.onSurface,
                           foregroundColor: isDark ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onPrimary,
                        ),
                        child: const Text('OK'),
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
