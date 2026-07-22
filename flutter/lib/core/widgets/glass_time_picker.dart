import 'dart:ui';
import 'package:flutter/material.dart';

Future<TimeOfDay?> showGlassTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => GlassTimePickerDialog(initialTime: initialTime),
  );
}

class GlassTimePickerDialog extends StatefulWidget {
  const GlassTimePickerDialog({super.key, required this.initialTime});
  final TimeOfDay initialTime;

  @override
  State<GlassTimePickerDialog> createState() => _GlassTimePickerDialogState();
}

class _GlassTimePickerDialogState extends State<GlassTimePickerDialog> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late bool _isAm;
  late int _selectedHourIndex;
  late int _selectedMinuteIndex;

  @override
  void initState() {
    super.initState();
    int hour = widget.initialTime.hour;
    _isAm = hour < 12;
    if (hour == 0) hour = 12;
    if (hour > 12) hour -= 12;
    
    _selectedHourIndex = hour - 1;
    _selectedMinuteIndex = widget.initialTime.minute;

    _hourController = FixedExtentScrollController(initialItem: _selectedHourIndex);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinuteIndex);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Select Time',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Segmented control for AM/PM
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey[300]!.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isAm = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _isAm ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'AM',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isAm = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !_isAm ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'PM',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Scrolling Wheels
                SizedBox(
                  height: 150,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Highlight bar
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 80,
                            child: ListWheelScrollView.useDelegate(
                              controller: _hourController,
                              itemExtent: 50,
                              physics: const FixedExtentScrollPhysics(),
                              overAndUnderCenterOpacity: 0.5,
                              onSelectedItemChanged: (i) => _selectedHourIndex = i,
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: 12,
                                builder: (context, index) {
                                  return Center(
                                    child: Text(
                                      (index + 1).toString().padLeft(2, '0'),
                                      style: TextStyle(
                                        fontSize: 32, 
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          Text(
                            ':', 
                            style: TextStyle(
                              fontSize: 32, 
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: ListWheelScrollView.useDelegate(
                              controller: _minuteController,
                              itemExtent: 50,
                              physics: const FixedExtentScrollPhysics(),
                              overAndUnderCenterOpacity: 0.5,
                              onSelectedItemChanged: (i) => _selectedMinuteIndex = i,
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: 60,
                                builder: (context, index) {
                                  return Center(
                                    child: Text(
                                      index.toString().padLeft(2, '0'),
                                      style: TextStyle(
                                        fontSize: 32, 
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
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
                        int hour = _selectedHourIndex + 1;
                        if (_isAm && hour == 12) hour = 0;
                        if (!_isAm && hour < 12) hour += 12;
                        
                        Navigator.pop(
                          context,
                          TimeOfDay(
                            hour: hour,
                            minute: _selectedMinuteIndex,
                          ),
                        );
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
    );
  }
}
