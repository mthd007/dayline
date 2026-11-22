import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../models/event.dart';
import '../services/format.dart';
import '../services/ics.dart';
import '../theme.dart';

class _ImportChoice {
  const _ImportChoice(this.color, this.reminder);
  final int color;

  /// Reminder added to imported events that have no alarm of their own, or null for none.
  final Reminder? reminder;
}

/// Pick an .ics file, preview what is inside, then add it to the calendar.
Future<void> importIcsFlow(BuildContext context) async {
  final scope = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);

  void say(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

  List<PlatformFile> files;
  try {
    files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ics', 'ical', 'icalendar', 'ifb'],
    );
  } catch (e) {
    say('Could not open the file picker: $e');
    return;
  }
  if (files.isEmpty) return; // cancelled

  String text;
  try {
    final bytes = await files.first.readAsBytes();
    text = utf8.decode(bytes, allowMalformed: true);
  } catch (e) {
    say('Could not read that file: $e');
    return;
  }

  if (!IcsParser.looksLikeIcs(text)) {
    say('That does not look like a calendar (.ics) file.');
    return;
  }

  final IcsResult result;
  try {
    result = IcsParser.parse(text);
  } catch (e) {
    say('This calendar file could not be understood: $e');
    return;
  }

  if (result.events.isEmpty) {
    say('No events found in ${files.first.name}.');
    return;
  }
  if (!context.mounted) return;

  final choice = await showModalBottomSheet<_ImportChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ImportSheet(fileName: files.first.name, result: result),
  );
  if (choice == null) return;

  final prepared = <CalEvent>[
    for (final e in result.events)
      e.copyWith(
        color: choice.color,
        reminders: e.reminders.isNotEmpty || choice.reminder == null ? null : [choice.reminder!],
      ),
  ];

  final summary = scope.store.importEvents(prepared);

  // Jump to the first event that is still ahead of us, so the import is visible right away.
  final now = DateTime.now();
  DateTime? target;
  for (final e in prepared) {
    if (e.recurrence != null || !e.start.isBefore(now)) {
      if (target == null || e.start.isBefore(target)) {
        target = e.recurrence != null && e.start.isBefore(now) ? now : e.start;
      }
    }
  }
  if (target != null) scope.store.select(target);

  final parts = <String>['Imported ${Fmt.plural(summary.added, 'event')}'];
  if (summary.updated > 0) parts.add('${summary.updated} updated');
  say(parts.join(' · '));
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.fileName, required this.result});

  final String fileName;
  final IcsResult result;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  int _color = 0;
  int _reminderChoice = 0;

  static const _options = <(String, Reminder?)>[
    ('None', null),
    ('10 min before', Reminder.before(10)),
    ('30 min before', Reminder.before(30)),
    ('1 hour before', Reminder.before(60)),
    ('Day before, 18:00', Reminder.onDay(1, 18 * 60)),
  ];

  String _range() {
    final evs = widget.result.events;
    var first = evs.first.start;
    var last = evs.first.end;
    var open = false;
    for (final e in evs) {
      if (e.start.isBefore(first)) first = e.start;
      if (e.end.isAfter(last)) last = e.end;
      if (e.recurrence != null && e.recurrence!.until == null && e.recurrence!.count == null) open = true;
    }
    final tail = open ? 'and onwards' : Fmt.dateMedium(last);
    return '${Fmt.dateMedium(first)} – $tail';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final noAlarms = r.events.length - r.withAlarms;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Import calendar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            r.calendarName ?? widget.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.muted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.plural(r.events.length, 'event'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(_range(), style: TextStyle(color: context.muted, fontSize: 13.5)),
                if (r.recurringCount > 0)
                  Text('${r.recurringCount} repeating', style: TextStyle(color: context.muted, fontSize: 13.5)),
                if (r.skipped > 0)
                  Text(
                    '${r.skipped} skipped (cancelled or without a date)',
                    style: TextStyle(color: context.muted, fontSize: 13.5),
                  ),
                if (r.simplified > 0)
                  Text(
                    '${r.simplified} repeat rules were simplified',
                    style: TextStyle(color: context.muted, fontSize: 13.5),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Events with the same ID in the file replace the earlier copy, so importing an updated file will not duplicate them.',
                  style: TextStyle(color: context.muted, fontSize: 12.5, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'COLOUR',
            style: TextStyle(color: context.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < Pal.eventColors.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _color = i),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Pal.eventColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == i ? context.text : Colors.transparent, width: 2.5),
                    ),
                    child: _color == i ? const Icon(Icons.check_rounded, size: 17, color: Color(0xFF0B0D12)) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            noAlarms == 0 ? 'REMINDER' : 'REMINDER FOR ${Fmt.plural(noAlarms, 'EVENT')} WITHOUT ONE'.toUpperCase(),
            style: TextStyle(color: context.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _options.length; i++)
                ChoiceChip(
                  label: Text(_options[i].$1),
                  selected: _reminderChoice == i,
                  onSelected: (_) => setState(() => _reminderChoice = i),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_ImportChoice(_color, _options[_reminderChoice].$2)),
                  child: Text('Import ${r.events.length}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
