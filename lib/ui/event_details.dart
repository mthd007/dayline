import 'package:flutter/material.dart';

import '../app.dart';
import '../models/event.dart';
import '../services/format.dart';
import '../services/jalali.dart';
import '../theme.dart';
import 'event_editor.dart';

Future<void> showEventDetails(BuildContext context, Occurrence o) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _Details(occurrence: o, hostContext: context),
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.occurrence, required this.hostContext});

  final Occurrence occurrence;
  final BuildContext hostContext;

  static String _when(Occurrence o) {
    final e = o.event;
    if (e.allDay) {
      final last = o.lastDay;
      final first = Fmt.dateOnly(o.start);
      if (Fmt.sameDay(first, last)) return '${Fmt.dateMedium(first)} · All day';
      return '${Fmt.dateMedium(first)} – ${Fmt.dateMedium(last)}';
    }
    if (Fmt.sameDay(o.start, o.end) || o.end == o.start) {
      if (o.end == o.start) return '${Fmt.dateMedium(o.start)} · ${Fmt.time(o.start)}';
      return '${Fmt.dateMedium(o.start)} · ${Fmt.time(o.start)} – ${Fmt.time(o.end)}';
    }
    return '${Fmt.dateShort(o.start)} ${Fmt.time(o.start)}  →  ${Fmt.dateShort(o.end)} ${Fmt.time(o.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final o = occurrence;
    final e = o.event;
    final color = Pal.event(e.color);
    final jalali = store.settings.showIranian ? Jalali.tryFromGregorian(o.start) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 54,
                margin: const EdgeInsets.only(right: 14, top: 4),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.15)),
                    const SizedBox(height: 6),
                    Text(_when(o), style: TextStyle(color: context.muted, fontSize: 15)),
                    if (jalali != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          jalali.format(),
                          style: TextStyle(color: context.accent, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (e.location.isNotEmpty) _row(context, Icons.place_outlined, e.location),
          if (e.recurrence != null) _row(context, Icons.repeat_rounded, e.recurrence!.describe()),
          if (e.notes.isNotEmpty) _row(context, Icons.notes_rounded, e.notes),
          if (e.reminders.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'REMINDERS',
              style: TextStyle(color: context.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1),
            ),
            const SizedBox(height: 8),
            for (final r in e.reminders)
              Builder(builder: (context) {
                final fire = r.fireTime(o.start);
                final past = fire.isBefore(DateTime.now());
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active_outlined,
                        size: 19,
                        color: past ? context.muted : context.accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${r.label}  ·  ${Fmt.dateShort(fire)} ${Fmt.time(fire)}',
                          style: TextStyle(color: past ? context.muted : context.text, fontSize: 14.5),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                  onPressed: () => _delete(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (hostContext.mounted) {
                      Navigator.of(hostContext).push(
                        MaterialPageRoute<void>(builder: (_) => EventEditorPage(event: e)),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.35))),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final store = AppScope.of(context).store;
    final e = occurrence.event;
    final messenger = ScaffoldMessenger.of(hostContext);

    if (e.recurrence == null) {
      Navigator.of(context).pop();
      store.remove(e.id);
      messenger.showSnackBar(SnackBar(
        content: Text('Deleted "${e.title}"'),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.upsert(e)),
      ));
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete repeating event'),
        content: Text('"${e.title}" repeats. What should be deleted?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'one'), child: const Text('Only this one')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: Text('All of them', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    Navigator.of(context).pop();
    if (choice == 'one') {
      final start = occurrence.start;
      store.skipOccurrence(e, start);
      messenger.showSnackBar(SnackBar(
        content: const Text('Deleted this occurrence'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            e.exdates.remove(start);
            store.upsert(e);
          },
        ),
      ));
    } else {
      store.remove(e.id);
      messenger.showSnackBar(SnackBar(
        content: Text('Deleted "${e.title}"'),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.upsert(e)),
      ));
    }
  }
}
