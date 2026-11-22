import 'package:timezone/timezone.dart' as tz;

import '../models/event.dart';

/// What came out of an .ics file.
class IcsResult {
  const IcsResult({
    required this.events,
    required this.skipped,
    required this.simplified,
    this.calendarName,
  });

  final List<CalEvent> events;

  /// Entries that could not be imported (cancelled, no start date, ...).
  final int skipped;

  /// Repeat rules that were too exotic to copy exactly (e.g. "2nd Tuesday of the month").
  final int simplified;
  final String? calendarName;

  int get recurringCount => events.where((e) => e.recurrence != null).length;
  int get withAlarms => events.where((e) => e.reminders.isNotEmpty).length;
}

class _Line {
  const _Line(this.name, this.params, this.value);
  final String name;
  final Map<String, String> params;
  final String value;
}

class _Dt {
  const _Dt(this.value, this.dateOnly);
  final DateTime value;
  final bool dateOnly;
}

class _RuleResult {
  const _RuleResult(this.rule, this.simplified);
  final Recurrence? rule;
  final bool simplified;
}

class _Built {
  const _Built(this.event, this.simplified, this.recurrenceId, this.rawUid);
  final CalEvent event;
  final bool simplified;
  final DateTime? recurrenceId;
  final String? rawUid;
}

/// A small, forgiving iCalendar (RFC 5545) reader aimed at university / work
/// timetables: VEVENT with DTSTART/DTEND/DURATION, RRULE (daily, weekly,
/// monthly, yearly with INTERVAL/COUNT/UNTIL/BYDAY), EXDATE, RECURRENCE-ID
/// overrides, VALARM triggers and TZID time zones.
class IcsParser {
  IcsParser._();

  static const _windowsZones = <String, String>{
    'W. Europe Standard Time': 'Europe/Berlin',
    'Central Europe Standard Time': 'Europe/Budapest',
    'Central European Standard Time': 'Europe/Warsaw',
    'Romance Standard Time': 'Europe/Paris',
    'GMT Standard Time': 'Europe/London',
    'E. Europe Standard Time': 'Europe/Chisinau',
    'FLE Standard Time': 'Europe/Kiev',
    'Turkey Standard Time': 'Europe/Istanbul',
    'Russian Standard Time': 'Europe/Moscow',
    'Iran Standard Time': 'Asia/Tehran',
    'Eastern Standard Time': 'America/New_York',
    'Central Standard Time': 'America/Chicago',
    'Mountain Standard Time': 'America/Denver',
    'Pacific Standard Time': 'America/Los_Angeles',
    'UTC': 'UTC',
  };

  static const _weekdayIndex = <String, int>{
    'MO': 1,
    'TU': 2,
    'WE': 3,
    'TH': 4,
    'FR': 5,
    'SA': 6,
    'SU': 7,
  };

  /// Parses the text of an .ics file. Never throws on bad entries; they are counted in [IcsResult.skipped].
  static IcsResult parse(String input) {
    final text = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final lines = _unfold(text);

    final events = <CalEvent>[];
    final overrides = <_Built>[];
    var skipped = 0;
    var simplified = 0;
    String? calName;

    List<_Line>? cur;
    var alarms = <Reminder>[];
    var inAlarm = false;

    for (final raw in lines) {
      final l = _parseLine(raw);
      if (l == null) continue;

      if (l.name == 'BEGIN') {
        final v = l.value.trim().toUpperCase();
        if (v == 'VEVENT') {
          cur = <_Line>[];
          alarms = <Reminder>[];
          inAlarm = false;
        } else if (v == 'VALARM' && cur != null) {
          inAlarm = true;
        }
        continue;
      }

      if (l.name == 'END') {
        final v = l.value.trim().toUpperCase();
        if (v == 'VALARM') {
          inAlarm = false;
        } else if (v == 'VEVENT' && cur != null) {
          final built = _buildEvent(cur, alarms);
          if (built == null) {
            skipped++;
          } else {
            if (built.simplified) simplified++;
            events.add(built.event);
            if (built.recurrenceId != null) overrides.add(built);
          }
          cur = null;
        }
        continue;
      }

      if (cur == null) {
        if (l.name == 'X-WR-CALNAME') calName = _unescape(l.value).trim();
        continue;
      }

      if (inAlarm) {
        if (l.name == 'TRIGGER') {
          final r = _parseTrigger(l);
          if (r != null && !alarms.contains(r)) alarms.add(r);
        }
        continue;
      }

      cur.add(l);
    }

    // A modified single occurrence (RECURRENCE-ID) replaces that date of its series.
    for (final o in overrides) {
      for (final master in events) {
        if (master.uid == o.rawUid && master.recurrence != null) {
          master.exdates.add(o.recurrenceId!);
        }
      }
    }

    events.sort((a, b) => a.start.compareTo(b.start));
    return IcsResult(
      events: events,
      skipped: skipped,
      simplified: simplified,
      calendarName: (calName == null || calName.isEmpty) ? null : calName,
    );
  }

  /// True when the text looks like an iCalendar file.
  static bool looksLikeIcs(String text) => text.toUpperCase().contains('BEGIN:VCALENDAR');

  // ---- lines -------------------------------------------------------------

  static List<String> _unfold(String text) {
    final raw = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final out = <String>[];
    for (final l in raw) {
      if ((l.startsWith(' ') || l.startsWith('\t')) && out.isNotEmpty) {
        out[out.length - 1] = out.last + l.substring(1);
      } else {
        out.add(l);
      }
    }
    return out;
  }

  static _Line? _parseLine(String line) {
    if (line.trim().isEmpty) return null;

    var inQuote = false;
    var colon = -1;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuote = !inQuote;
      } else if (c == ':' && !inQuote) {
        colon = i;
        break;
      }
    }
    if (colon < 0) return null;

    final head = line.substring(0, colon);
    final value = line.substring(colon + 1);

    final parts = <String>[];
    var buf = StringBuffer();
    inQuote = false;
    for (var i = 0; i < head.length; i++) {
      final ch = head[i];
      if (ch == '"') {
        inQuote = !inQuote;
        buf.write(ch);
      } else if (ch == ';' && !inQuote) {
        parts.add(buf.toString());
        buf = StringBuffer();
      } else {
        buf.write(ch);
      }
    }
    parts.add(buf.toString());

    var name = parts.first.trim().toUpperCase();
    final dot = name.lastIndexOf('.'); // property group prefix, e.g. "item1.X-FOO"
    if (dot >= 0) name = name.substring(dot + 1);

    final params = <String, String>{};
    for (final p in parts.skip(1)) {
      final eq = p.indexOf('=');
      if (eq > 0) {
        params[p.substring(0, eq).trim().toUpperCase()] = p.substring(eq + 1).replaceAll('"', '');
      }
    }
    return _Line(name, params, value);
  }

  static String _unescape(String s) => s.replaceAllMapped(RegExp(r'\\(.)'), (m) {
        final c = m.group(1)!;
        return (c == 'n' || c == 'N') ? '\n' : c;
      });

  // ---- values ------------------------------------------------------------

  static tz.Location? _location(String tzid) {
    final candidates = <String>[
      _windowsZones[tzid] ?? tzid,
    ];
    final segs = tzid.split('/');
    if (segs.length >= 2) {
      candidates.add('${segs[segs.length - 2]}/${segs.last}');
    }
    for (final name in candidates) {
      try {
        return tz.getLocation(name);
      } catch (_) {
        // try the next candidate
      }
    }
    return null;
  }

  static _Dt? _parseDt(String raw, Map<String, String> params) {
    final v = raw.trim().toUpperCase();
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?)?(Z)?$').firstMatch(v);
    if (m == null) return null;

    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);

    if (m.group(4) == null) {
      return _Dt(DateTime(y, mo, d), true);
    }

    final h = int.parse(m.group(4)!);
    final mi = int.parse(m.group(5)!);
    final s = int.tryParse(m.group(6) ?? '0') ?? 0;

    if (m.group(7) != null) {
      return _Dt(DateTime.utc(y, mo, d, h, mi, s).toLocal(), false);
    }

    final tzid = params['TZID'];
    if (tzid != null) {
      final loc = _location(tzid);
      if (loc != null) {
        final t = tz.TZDateTime(loc, y, mo, d, h, mi, s);
        return _Dt(DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch), false);
      }
    }
    // Floating time (or an unknown zone): treat as the device's local time.
    return _Dt(DateTime(y, mo, d, h, mi, s), false);
  }

  static Duration? _parseDuration(String v) {
    final m = RegExp(
      r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
    ).firstMatch(v.trim().toUpperCase());
    if (m == null) return null;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    final d = Duration(days: g(2) * 7 + g(3), hours: g(4), minutes: g(5), seconds: g(6));
    return m.group(1) == '-' ? -d : d;
  }

  /// VALARM TRIGGER relative to the start ("-PT15M") -> Reminder.before(15).
  static Reminder? _parseTrigger(_Line l) {
    if ((l.params['VALUE'] ?? '').toUpperCase() == 'DATE-TIME') return null;
    if ((l.params['RELATED'] ?? '').toUpperCase() == 'END') return null;
    final d = _parseDuration(l.value);
    if (d == null) return null;
    if (d > Duration.zero) return null; // fires after the start: not supported
    final minutes = (-d).inMinutes;
    return Reminder.before(minutes > 57600 ? 57600 : minutes);
  }

  // ---- recurrence --------------------------------------------------------

  static _RuleResult _parseRrule(String value, DateTime start) {
    final parts = <String, String>{};
    for (final p in value.split(';')) {
      final i = p.indexOf('=');
      if (i > 0) parts[p.substring(0, i).trim().toUpperCase()] = p.substring(i + 1).trim();
    }

    RepeatFreq? freq;
    switch ((parts['FREQ'] ?? '').toUpperCase()) {
      case 'DAILY':
        freq = RepeatFreq.daily;
      case 'WEEKLY':
        freq = RepeatFreq.weekly;
      case 'MONTHLY':
        freq = RepeatFreq.monthly;
      case 'YEARLY':
        freq = RepeatFreq.yearly;
      default:
        freq = null;
    }
    if (freq == null) return const _RuleResult(null, true); // HOURLY etc.: import as a single event

    var simplified = false;
    final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
    final count = int.tryParse(parts['COUNT'] ?? '');

    DateTime? until;
    final u = parts['UNTIL'];
    if (u != null) {
      final d = _parseDt(u, const <String, String>{});
      if (d != null) {
        until = d.dateOnly
            ? DateTime(d.value.year, d.value.month, d.value.day, 23, 59, 59)
            : d.value;
      }
    }

    final days = <int>[];
    var hasOrdinal = false;
    for (final t in (parts['BYDAY'] ?? '').split(',')) {
      final token = t.trim().toUpperCase();
      if (token.isEmpty) continue;
      final m = RegExp(r'^([+-]?\d{0,2})(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(token);
      if (m == null) {
        simplified = true;
        continue;
      }
      if ((m.group(1) ?? '').isNotEmpty) hasOrdinal = true;
      days.add(_weekdayIndex[m.group(2)!]!);
    }

    var outFreq = freq;
    var byDays = <int>[];
    if (freq == RepeatFreq.weekly) {
      byDays = days;
      if (hasOrdinal) simplified = true;
    } else if (freq == RepeatFreq.daily && days.isNotEmpty) {
      if (interval == 1) {
        outFreq = RepeatFreq.weekly; // "every weekday" style rules
        byDays = days;
      } else {
        simplified = true;
      }
    } else if (days.isNotEmpty) {
      simplified = true; // e.g. "2nd Tuesday of the month"
    }

    if (parts.containsKey('BYSETPOS')) simplified = true;
    final bmd = parts['BYMONTHDAY'];
    if (bmd != null && int.tryParse(bmd) != start.day) simplified = true;
    final bm = parts['BYMONTH'];
    if (bm != null && !(freq == RepeatFreq.yearly && int.tryParse(bm) == start.month)) {
      simplified = true;
    }
    for (final k in const ['BYWEEKNO', 'BYYEARDAY']) {
      if (parts.containsKey(k)) simplified = true;
    }

    return _RuleResult(
      Recurrence(
        freq: outFreq,
        interval: interval < 1 ? 1 : interval,
        byDays: byDays,
        count: count,
        until: until,
      ),
      simplified,
    );
  }

  // ---- events ------------------------------------------------------------

  static _Built? _buildEvent(List<_Line> props, List<Reminder> alarms) {
    _Line? first(String name) {
      for (final p in props) {
        if (p.name == name) return p;
      }
      return null;
    }

    final status = first('STATUS')?.value.trim().toUpperCase();
    if (status == 'CANCELLED') return null;

    final ds = first('DTSTART');
    if (ds == null) return null;
    final startDt = _parseDt(ds.value, ds.params);
    if (startDt == null) return null;

    final allDay = startDt.dateOnly;
    final start = startDt.value;

    DateTime end;
    final de = first('DTEND');
    final dur = first('DURATION');
    if (de != null) {
      end = _parseDt(de.value, de.params)?.value ?? start;
    } else if (dur != null) {
      final d = _parseDuration(dur.value);
      if (d == null) {
        end = start;
      } else {
        end = allDay ? DateTime(start.year, start.month, start.day + d.inDays) : start.add(d);
      }
    } else {
      end = allDay ? DateTime(start.year, start.month, start.day + 1) : start;
    }
    if (end.isBefore(start)) end = start;
    if (allDay && !end.isAfter(start)) {
      end = DateTime(start.year, start.month, start.day + 1);
    }

    DateTime sameSlot(_Dt d) => d.dateOnly && !allDay
        ? DateTime(d.value.year, d.value.month, d.value.day, start.hour, start.minute)
        : d.value;

    final recIdLine = first('RECURRENCE-ID');
    DateTime? recurrenceId;
    if (recIdLine != null) {
      final r = _parseDt(recIdLine.value, recIdLine.params);
      if (r != null) recurrenceId = sameSlot(r);
    }

    var simplified = false;
    Recurrence? rec;
    final rr = first('RRULE');
    if (rr != null && recurrenceId == null) {
      final res = _parseRrule(rr.value, start);
      rec = res.rule;
      simplified = res.simplified;
    }

    final exdates = <DateTime>[];
    for (final p in props) {
      if (p.name != 'EXDATE') continue;
      for (final v in p.value.split(',')) {
        final d = _parseDt(v, p.params);
        if (d != null) exdates.add(sameSlot(d));
      }
    }

    final title = _unescape(first('SUMMARY')?.value ?? '').trim();
    final location = _unescape(first('LOCATION')?.value ?? '').trim();
    var notes = _unescape(first('DESCRIPTION')?.value ?? '').trim();
    if (notes.length > 2000) notes = notes.substring(0, 2000);

    final rawUid = first('UID')?.value.trim();
    String? uid = (rawUid == null || rawUid.isEmpty) ? null : rawUid;
    if (uid != null && recurrenceId != null) {
      uid = '$uid#${recurrenceId.millisecondsSinceEpoch}';
    }

    final event = CalEvent(
      id: CalEvent.newId(),
      title: title.isEmpty ? '(No title)' : title,
      start: start,
      end: end,
      allDay: allDay,
      location: location,
      notes: notes,
      color: 0,
      reminders: List<Reminder>.from(alarms),
      recurrence: rec,
      exdates: exdates,
      uid: uid,
    );
    return _Built(event, simplified, recurrenceId, (rawUid == null || rawUid.isEmpty) ? null : rawUid);
  }
}
