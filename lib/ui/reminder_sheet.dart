import 'package:flutter/material.dart';

import '../app.dart';
import '../models/event.dart';
import '../services/format.dart';
import '../theme.dart';
import 'widgets.dart';

/// Bottom sheet that lets the user build one reminder.
/// Returns the chosen [Reminder], or null when dismissed.
Future<Reminder?> showReminderSheet(BuildContext context, {required bool allDay}) {
  return showModalBottomSheet<Reminder>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReminderSheet(allDay: allDay),
  );
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({required this.allDay});
  final bool allDay;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  // 0 = before the event, 1 = on an earlier day at a fixed time
  late int _mode = widget.allDay ? 1 : 0;

  final _amount = TextEditingController(text: '1');
  int _unit = 1; // 0 minutes, 1 hours, 2 days, 3 weeks
  int _daysBefore = 1;
  int _minuteOfDay = 18 * 60;

  static const _unitNames = ['minutes', 'hours', 'days', 'weeks'];
  static const _unitMinutes = [1, 60, 1440, 10080];

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  List<Reminder> get _presets {
    if (widget.allDay) {
      return const [
        Reminder.onDay(0, 9 * 60),
        Reminder.onDay(1, 9 * 60),
        Reminder.onDay(1, 18 * 60),
        Reminder.onDay(2, 9 * 60),
        Reminder.onDay(7, 9 * 60),
      ];
    }
    return const [
      Reminder.before(0),
      Reminder.before(5),
      Reminder.before(10),
      Reminder.before(15),
      Reminder.before(30),
      Reminder.before(60),
      Reminder.before(120),
      Reminder.onDay(0, 8 * 60),
      Reminder.onDay(1, 18 * 60),
      Reminder.before(1440),
      Reminder.before(2880),
      Reminder.before(10080),
    ];
  }

  Reminder? get _custom {
    if (_mode == 1) return Reminder.onDay(_daysBefore, _minuteOfDay);
    final n = int.tryParse(_amount.text.trim());
    if (n == null || n < 0) return null;
    final minutes = n * _unitMinutes[_unit];
    if (minutes > 60 * 24 * 40) return null; // keep within the scheduling window
    return Reminder.before(minutes);
  }

  Future<void> _pickTime() async {
    final use24 = AppScope.of(context).store.settings.use24h;
    final t = await pickTime(
      context,
      TimeOfDay(hour: _minuteOfDay ~/ 60, minute: _minuteOfDay % 60),
      use24h: use24,
    );
    if (t != null) setState(() => _minuteOfDay = t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final custom = _custom;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Add a reminder', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'You can add as many as you like, for example a day before and an hour before.',
            style: TextStyle(color: context.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _presets)
                ActionChip(
                  label: Text(r.label),
                  onPressed: () => Navigator.of(context).pop(r),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'CUSTOM',
            style: TextStyle(color: context.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          if (!widget.allDay)
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Before the event')),
                  ButtonSegment(value: 1, label: Text('On an earlier day')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
          const SizedBox(height: 14),
          if (_mode == 0)
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(14)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _unit,
                        isExpanded: true,
                        dropdownColor: context.surface2,
                        items: [
                          for (var i = 0; i < _unitNames.length; i++)
                            DropdownMenuItem(value: i, child: Text('${_unitNames[i]} before')),
                        ],
                        onChanged: (v) => setState(() => _unit = v ?? 1),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_rounded),
                        onPressed: _daysBefore > 0 ? () => setState(() => _daysBefore--) : null,
                      ),
                      SizedBox(
                        width: 78,
                        child: Text(
                          Fmt.plural(_daysBefore, 'day'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded),
                        onPressed: _daysBefore < 40 ? () => setState(() => _daysBefore++) : null,
                      ),
                    ],
                  ),
                ),
                const Text('before, at'),
                OutlinedButton(
                  onPressed: _pickTime,
                  child: Text(Fmt.minuteOfDay(_minuteOfDay)),
                ),
              ],
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  custom == null ? 'Enter a number up to 40 days' : custom.label,
                  style: TextStyle(color: custom == null ? Theme.of(context).colorScheme.error : context.accent),
                ),
              ),
              FilledButton(
                onPressed: custom == null ? null : () => Navigator.of(context).pop(custom),
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
