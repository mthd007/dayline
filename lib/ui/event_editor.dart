import 'package:flutter/material.dart';

import '../app.dart';
import '../models/event.dart';
import '../services/format.dart';
import '../services/jalali.dart';
import '../services/store.dart';
import '../theme.dart';
import 'reminder_sheet.dart';
import 'widgets.dart';

class EventEditorPage extends StatefulWidget {
  const EventEditorPage({super.key, this.event, this.initialDay});

  /// The event being edited, or null for a new one.
  final CalEvent? event;

  /// Day pre-selected for a new event.
  final DateTime? initialDay;

  @override
  State<EventEditorPage> createState() => _EventEditorPageState();
}

class _EventEditorPageState extends State<EventEditorPage> {
  late final Store _store;

  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate; // inclusive for all-day events
  late TimeOfDay _endTime;
  bool _allDay = false;
  int _color = 0;
  List<Reminder> _reminders = [];

  RepeatFreq? _freq;
  int _interval = 1;
  final Set<int> _byDays = {};
  int _endsMode = 0; // 0 never, 1 on date, 2 after N times
  DateTime? _until;
  int _count = 10;

  static const _defaultTimedReminder = Reminder.before(15);
  static const _defaultAllDayReminder = Reminder.onDay(0, 9 * 60);

  bool get _editing => widget.event != null;

  @override
  void initState() {
    super.initState();
    _store = AppScope.of(context).store;

    final e = widget.event;
    if (e != null) {
      _title.text = e.title;
      _location.text = e.location;
      _notes.text = e.notes;
      _allDay = e.allDay;
      _color = e.color;
      _reminders = List<Reminder>.from(e.reminders);
      _startDate = Fmt.dateOnly(e.start);
      _startTime = TimeOfDay(hour: e.start.hour, minute: e.start.minute);
      if (e.allDay) {
        _endDate = Fmt.addDays(Fmt.dateOnly(e.end), -1);
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
        _endTime = const TimeOfDay(hour: 10, minute: 0);
      } else {
        _endDate = Fmt.dateOnly(e.end);
        _endTime = TimeOfDay(hour: e.end.hour, minute: e.end.minute);
      }
      final r = e.recurrence;
      if (r != null) {
        _freq = r.freq;
        _interval = r.interval;
        _byDays.addAll(r.byDays);
        if (r.until != null) {
          _endsMode = 1;
          _until = Fmt.dateOnly(r.until!);
        } else if (r.count != null) {
          _endsMode = 2;
          _count = r.count!;
        }
      }
    } else {
      final day = Fmt.dateOnly(widget.initialDay ?? DateTime.now());
      final now = DateTime.now();
      final isToday = Fmt.sameDay(day, now);
      final int startHour = isToday ? (now.hour + 1).clamp(0, 22).toInt() : 9;
      _startDate = day;
      _startTime = TimeOfDay(hour: startHour, minute: 0);
      _endDate = day;
      _endTime = TimeOfDay(hour: startHour + 1, minute: 0);
      _reminders = [_defaultTimedReminder];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  // ---- helpers -----------------------------------------------------------

  DateTime _compose(DateTime date, TimeOfDay t) => DateTime(date.year, date.month, date.day, t.hour, t.minute);

  DateTime get _startDt => _allDay ? _startDate : _compose(_startDate, _startTime);

  bool get _use24h => _store.settings.use24h;

  String _timeText(TimeOfDay t) => Fmt.minuteOfDay(t.hour * 60 + t.minute);

  /// Moving the start keeps the length of the event, like most calendars do.
  void _moveStart({DateTime? date, TimeOfDay? time}) {
    final oldStart = _compose(_startDate, _startTime);
    final oldEnd = _compose(_endDate, _endTime);
    final length = oldEnd.difference(oldStart);
    final dayGap = Fmt.daysBetween(_startDate, _endDate);

    setState(() {
      if (date != null) _startDate = date;
      if (time != null) _startTime = time;
      if (_allDay) {
        _endDate = Fmt.addDays(_startDate, dayGap < 0 ? 0 : dayGap);
      } else {
        final newEnd = _compose(_startDate, _startTime).add(length.isNegative ? Duration.zero : length);
        _endDate = Fmt.dateOnly(newEnd);
        _endTime = TimeOfDay(hour: newEnd.hour, minute: newEnd.minute);
      }
      // The repeat-until date can never be before the (new) start.
      if (_until != null && _until!.isBefore(_startDate)) _until = _startDate;
    });
  }

  DateTime _clampPickerDate(DateTime d) =>
      d.isBefore(DateTime(2000)) ? DateTime(2000) : (d.isAfter(DateTime(2100)) ? DateTime(2100) : d);

  Future<void> _pickDate({required bool start}) async {
    final initial = _clampPickerDate(start ? _startDate : _endDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    if (start) {
      _moveStart(date: Fmt.dateOnly(picked));
    } else {
      setState(() {
        _endDate = Fmt.dateOnly(picked);
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      });
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await pickTime(context, start ? _startTime : _endTime, use24h: _use24h);
    if (picked == null) return;
    if (start) {
      _moveStart(time: picked);
    } else {
      setState(() => _endTime = picked);
    }
  }

  void _toggleAllDay(bool v) {
    setState(() {
      _allDay = v;
      if (v) {
        if (_reminders.length == 1 && _reminders.first == _defaultTimedReminder) {
          _reminders = [_defaultAllDayReminder];
        }
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        if (_reminders.length == 1 && _reminders.first == _defaultAllDayReminder) {
          _reminders = [_defaultTimedReminder];
        }
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      }
    });
  }

  Future<void> _addReminder() async {
    final r = await showReminderSheet(context, allDay: _allDay);
    if (r == null || !mounted) return;
    if (_reminders.contains(r)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That reminder is already added')));
      return;
    }
    setState(() {
      _reminders.add(r);
      _reminders.sort(Reminder.compare);
    });
  }

  Future<void> _pickUntil() async {
    final initial = (_until != null && !_until!.isBefore(_startDate)) ? _until! : Fmt.addDays(_startDate, 30);
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampPickerDate(initial),
      firstDate: _clampPickerDate(_startDate),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _until = Fmt.dateOnly(picked));
  }

  void _setFreq(RepeatFreq? f) {
    setState(() {
      _freq = f;
      if (f == RepeatFreq.weekly && _byDays.isEmpty) _byDays.add(_startDate.weekday);
    });
  }

  // ---- save / delete ---------------------------------------------------------

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the event a title first')));
      return;
    }

    late DateTime start;
    late DateTime end;
    if (_allDay) {
      start = _startDate;
      final last = _endDate.isBefore(_startDate) ? _startDate : _endDate;
      end = Fmt.addDays(last, 1);
    } else {
      start = _compose(_startDate, _startTime);
      end = _compose(_endDate, _endTime);
      if (end.isBefore(start)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The event cannot end before it starts')),
        );
        return;
      }
    }

    Recurrence? rec;
    if (_freq != null) {
      DateTime? until;
      if (_endsMode == 1 && _until != null) {
        until = DateTime(_until!.year, _until!.month, _until!.day, 23, 59, 59);
      }
      rec = Recurrence(
        freq: _freq!,
        interval: _interval < 1 ? 1 : _interval,
        // The weekday of the start date always counts, even if the date was moved after picking days.
        byDays: _freq == RepeatFreq.weekly
            ? ((Set<int>.of(_byDays)..add(_startDate.weekday)).toList()..sort())
            : const [],
        count: _endsMode == 2 ? _count : null,
        until: until,
      );
    }

    final old = widget.event;
    final ev = CalEvent(
      id: old?.id ?? CalEvent.newId(),
      title: title,
      start: start,
      end: end,
      allDay: _allDay,
      location: _location.text.trim(),
      notes: _notes.text.trim(),
      color: _color,
      reminders: List<Reminder>.from(_reminders)..sort(Reminder.compare),
      recurrence: rec,
      // Deleted occurrences are matched by start time, so follow the series if its time of day moved.
      exdates: old == null
          ? <DateTime>[]
          : old.exdates.map((d) => DateTime(d.year, d.month, d.day, start.hour, start.minute)).toList(),
      uid: old?.uid,
    );

    _store.upsert(ev);
    _store.select(Fmt.dateOnly(start));
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.event!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(e.recurrence != null
            ? '"${e.title}" and all of its repeats will be removed.'
            : '"${e.title}" will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _store.remove(e.id);
    Navigator.of(context).pop();
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
        title: Text(_editing ? 'Edit event' : 'New event'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          TextField(
            controller: _title,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(hintText: 'What is it?'),
          ),
          const SizedBox(height: 18),
          _whenSection(context),
          _reminderSection(context),
          _repeatSection(context),
          Section(
            title: 'Details',
            child: Column(
              children: [
                TextField(
                  controller: _location,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Location',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Notes, e.g. documents to bring',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ],
            ),
          ),
          Section(
            title: 'Colour',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < Pal.eventColors.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: Tooltip(
                      message: Pal.eventColorNames[i],
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Pal.eventColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == i ? context.text : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: _color == i
                            ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF0B0D12))
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _whenSection(BuildContext context) {
    final showIran = _store.settings.showIranian;

    Widget row(String label, DateTime date, TimeOfDay time, bool start) {
      final j = showIran ? Jalali.tryFromGregorian(date) : null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 54, child: Text(label, style: TextStyle(color: context.muted))),
            Expanded(
              child: TextButton(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: context.text),
                onPressed: () => _pickDate(start: start),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.dateMedium(date), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    if (j != null)
                      Text(j.format(), style: TextStyle(fontSize: 12, color: context.accent)),
                  ],
                ),
              ),
            ),
            if (!_allDay)
              OutlinedButton(
                onPressed: () => _pickTime(start: start),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                child: Text(_timeText(time), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      );
    }

    return Section(
      title: 'When',
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Text('All day', style: TextStyle(fontSize: 15))),
              Switch(value: _allDay, onChanged: _toggleAllDay),
            ],
          ),
          Divider(color: context.line),
          row('Starts', _startDate, _startTime, true),
          row('Ends', _endDate, _endTime, false),
        ],
      ),
    );
  }

  Widget _reminderSection(BuildContext context) {
    final start = _startDt;
    return Section(
      title: 'Reminders',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_reminders.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('No reminders', style: TextStyle(color: context.muted)),
            ),
          for (final r in _reminders)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined, size: 20, color: context.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Builder(builder: (context) {
                          final fire = r.fireTime(start);
                          return Text(
                            '${Fmt.dateShort(fire)} · ${Fmt.time(fire)}',
                            style: TextStyle(color: context.muted, fontSize: 12.5),
                          );
                        }),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: Icon(Icons.close_rounded, size: 20, color: context.muted),
                    onPressed: () => setState(() => _reminders.remove(r)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _addReminder,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add reminder'),
          ),
        ],
      ),
    );
  }

  Widget _repeatSection(BuildContext context) {
    Widget chip(String label, RepeatFreq? f) => ChoiceChip(
          label: Text(label),
          selected: _freq == f,
          onSelected: (_) => _setFreq(f),
        );

    final unit = switch (_freq) {
      RepeatFreq.daily => 'day',
      RepeatFreq.weekly => 'week',
      RepeatFreq.monthly => 'month',
      RepeatFreq.yearly => 'year',
      null => '',
    };

    return Section(
      title: 'Repeat',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('Never', null),
              chip('Daily', RepeatFreq.daily),
              chip('Weekly', RepeatFreq.weekly),
              chip('Monthly', RepeatFreq.monthly),
              chip('Yearly', RepeatFreq.yearly),
            ],
          ),
          if (_freq != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Every'),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: _interval > 1 ? () => setState(() => _interval--) : null,
                ),
                Text('$_interval', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _interval < 99 ? () => setState(() => _interval++) : null,
                ),
                Text(_interval == 1 ? unit : '${unit}s'),
              ],
            ),
          ],
          if (_freq == RepeatFreq.weekly) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(Fmt.weekdaysShort[d - 1]),
                    selected: _byDays.contains(d),
                    showCheckmark: false,
                    onSelected: (on) => setState(() {
                      if (on) {
                        _byDays.add(d);
                      } else if (_byDays.length > 1) {
                        _byDays.remove(d);
                      }
                    }),
                  ),
              ],
            ),
          ],
          if (_freq != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Forever'),
                  selected: _endsMode == 0,
                  onSelected: (_) => setState(() => _endsMode = 0),
                ),
                ChoiceChip(
                  label: Text(_endsMode == 1 && _until != null ? 'Until ${Fmt.dateMedium(_until!)}' : 'Until a date'),
                  selected: _endsMode == 1,
                  onSelected: (_) async {
                    setState(() => _endsMode = 1);
                    await _pickUntil();
                    if (_until == null && mounted) setState(() => _endsMode = 0);
                  },
                ),
                ChoiceChip(
                  label: Text(_endsMode == 2 ? '$_count times' : 'Number of times'),
                  selected: _endsMode == 2,
                  onSelected: (_) => setState(() => _endsMode = 2),
                ),
              ],
            ),
            if (_endsMode == 2)
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: _count > 1 ? () => setState(() => _count--) : null,
                  ),
                  Text('$_count', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: _count < 500 ? () => setState(() => _count++) : null,
                  ),
                  const Text('occurrences in total'),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
