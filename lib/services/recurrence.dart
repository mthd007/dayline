import '../models/event.dart';
import 'format.dart';

/// All occurrences of [e] that overlap the half-open window [from, to).
List<Occurrence> expandEvent(CalEvent e, DateTime from, DateTime to) {
  final result = <Occurrence>[];
  final excluded = e.exdates.map((d) => d.millisecondsSinceEpoch).toSet();

  final timedDuration = e.end.isAfter(e.start) ? e.end.difference(e.start) : Duration.zero;
  final allDayLength = Fmt.daysBetween(e.start, e.end);

  for (final s in _starts(e, to)) {
    if (!s.isBefore(to)) break;
    if (excluded.contains(s.millisecondsSinceEpoch)) continue;
    final end = e.allDay
        ? DateTime(s.year, s.month, s.day + (allDayLength < 1 ? 1 : allDayLength))
        : s.add(timedDuration);
    final overlaps = end.isAfter(from) || (end == s && !s.isBefore(from));
    if (overlaps) result.add(Occurrence(e, s, end));
  }
  return result;
}

/// Start times of the series in ascending order, stopping before [horizon].
Iterable<DateTime> _starts(CalEvent e, DateTime horizon) sync* {
  final r = e.recurrence;
  final s = e.start;
  if (r == null) {
    yield s;
    return;
  }

  final h = s.hour;
  final mi = s.minute;
  final until = r.until;
  final count = r.count;
  final step = r.interval < 1 ? 1 : r.interval;
  var produced = 0;

  if (r.freq == RepeatFreq.daily) {
    for (var k = 0; k < 100000; k++) {
      final d = DateTime(s.year, s.month, s.day + k * step, h, mi);
      if (until != null && d.isAfter(until)) return;
      if (!d.isBefore(horizon)) return;
      yield d;
      produced++;
      if (count != null && produced >= count) return;
    }
    return;
  }

  if (r.freq == RepeatFreq.weekly) {
    final days = r.byDays.isEmpty ? <int>[s.weekday] : (List<int>.from(r.byDays)..sort());
    final monday = DateTime(s.year, s.month, s.day - (s.weekday - 1));
    for (var w = 0; w < 20000; w++) {
      for (final wd in days) {
        final d = DateTime(monday.year, monday.month, monday.day + w * 7 * step + (wd - 1), h, mi);
        if (d.isBefore(s)) continue;
        if (until != null && d.isAfter(until)) return;
        if (!d.isBefore(horizon)) return;
        yield d;
        produced++;
        if (count != null && produced >= count) return;
      }
    }
    return;
  }

  if (r.freq == RepeatFreq.monthly) {
    for (var k = 0; k < 5000; k++) {
      final total = s.month - 1 + k * step;
      final y = s.year + total ~/ 12;
      final m = total % 12 + 1;
      if (s.day > Fmt.daysInMonth(y, m)) continue; // e.g. the 31st in a 30-day month
      final d = DateTime(y, m, s.day, h, mi);
      if (until != null && d.isAfter(until)) return;
      if (!d.isBefore(horizon)) return;
      yield d;
      produced++;
      if (count != null && produced >= count) return;
    }
    return;
  }

  // yearly
  for (var k = 0; k < 2000; k++) {
    final y = s.year + k * step;
    if (s.month == 2 && s.day == 29 && Fmt.daysInMonth(y, 2) != 29) continue;
    final d = DateTime(y, s.month, s.day, h, mi);
    if (until != null && d.isAfter(until)) return;
    if (!d.isBefore(horizon)) return;
    yield d;
    produced++;
    if (count != null && produced >= count) return;
  }
}
