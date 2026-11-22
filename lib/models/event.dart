import 'dart:math' as math;

import '../services/format.dart';

enum RepeatFreq { daily, weekly, monthly, yearly }

/// One notification for an event. Two flavours:
///  * [Reminder.before]: N minutes before the event starts (e.g. 60 = one hour before)
///  * [Reminder.onDay]: N days before the event's date, at a fixed clock time
///    (e.g. 1 day before at 18:00 -> "get the documents ready tonight").
class Reminder {
  const Reminder._(this.minutes, this.daysBefore, this.minuteOfDay);

  const Reminder.before(int minutes) : this._(minutes, null, null);

  const Reminder.onDay(int daysBefore, int minuteOfDay) : this._(null, daysBefore, minuteOfDay);

  final int? minutes;
  final int? daysBefore;
  final int? minuteOfDay;

  bool get isRelative => minutes != null;

  /// When this reminder fires for an occurrence starting at [eventStart].
  DateTime fireTime(DateTime eventStart) {
    if (minutes != null) {
      return eventStart.subtract(Duration(minutes: minutes!));
    }
    final t = minuteOfDay!;
    return DateTime(
      eventStart.year,
      eventStart.month,
      eventStart.day - daysBefore!,
      t ~/ 60,
      t % 60,
    );
  }

  /// "1 hour", "30 minutes", "2 days", "1 week"
  static String span(int minutes) {
    if (minutes % 10080 == 0) return Fmt.plural(minutes ~/ 10080, 'week');
    if (minutes % 1440 == 0) return Fmt.plural(minutes ~/ 1440, 'day');
    if (minutes % 60 == 0) return Fmt.plural(minutes ~/ 60, 'hour');
    return Fmt.plural(minutes, 'minute');
  }

  String get label {
    if (minutes != null) {
      if (minutes == 0) return 'At time of event';
      return '${span(minutes!)} before';
    }
    final t = Fmt.minuteOfDay(minuteOfDay!);
    final d = daysBefore!;
    if (d == 0) return 'Same day at $t';
    if (d == 1) return 'Day before at $t';
    return '$d days before at $t';
  }

  /// Lead-in used in the notification text ("In 1 hour"); empty for [onDay].
  String get leadText {
    if (minutes == null) return '';
    if (minutes == 0) return 'Starting now';
    return 'In ${span(minutes!)}';
  }

  String get key => minutes != null ? 'm$minutes' : 'd${daysBefore}t$minuteOfDay';

  /// Earliest-firing first.
  static int compare(Reminder a, Reminder b) {
    final ref = DateTime(2000, 1, 15, 12);
    return a.fireTime(ref).compareTo(b.fireTime(ref));
  }

  Map<String, dynamic> toJson() =>
      minutes != null ? {'m': minutes} : {'d': daysBefore, 't': minuteOfDay};

  factory Reminder.fromJson(Map<String, dynamic> j) => j.containsKey('m')
      ? Reminder.before(j['m'] as int)
      : Reminder.onDay(j['d'] as int, j['t'] as int);

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.minutes == minutes &&
      other.daysBefore == daysBefore &&
      other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => Object.hash(minutes, daysBefore, minuteOfDay);
}

class Recurrence {
  const Recurrence({
    required this.freq,
    this.interval = 1,
    this.byDays = const [],
    this.count,
    this.until,
  });

  final RepeatFreq freq;
  final int interval;

  /// Weekly only: DateTime.monday..DateTime.sunday (1..7). Empty = weekday of the start.
  final List<int> byDays;

  /// Total number of occurrences (including the first), or null.
  final int? count;

  /// Last allowed occurrence start (inclusive), or null.
  final DateTime? until;

  String describe() {
    var text = '';
    switch (freq) {
      case RepeatFreq.daily:
        text = interval == 1 ? 'Every day' : 'Every $interval days';
      case RepeatFreq.weekly:
        text = interval == 1 ? 'Every week' : 'Every $interval weeks';
        if (byDays.isNotEmpty) {
          final sorted = List<int>.from(byDays)..sort();
          text += ' on ${sorted.map((d) => Fmt.weekdaysShort[d - 1]).join(', ')}';
        }
      case RepeatFreq.monthly:
        text = interval == 1 ? 'Every month' : 'Every $interval months';
      case RepeatFreq.yearly:
        text = interval == 1 ? 'Every year' : 'Every $interval years';
    }
    if (count != null) {
      text += ', $count times';
    } else if (until != null) {
      text += ', until ${Fmt.dateMedium(until!)}';
    }
    return text;
  }

  Map<String, dynamic> toJson() => {
        'f': freq.name,
        'i': interval,
        'b': byDays,
        if (count != null) 'c': count,
        if (until != null) 'u': until!.toIso8601String(),
      };

  factory Recurrence.fromJson(Map<String, dynamic> j) => Recurrence(
        freq: RepeatFreq.values.byName(j['f'] as String),
        interval: (j['i'] as int?) ?? 1,
        byDays: ((j['b'] as List?) ?? const []).map((e) => e as int).toList(),
        count: j['c'] as int?,
        until: j['u'] == null ? null : DateTime.parse(j['u'] as String),
      );
}

/// A calendar entry. Times are local wall-clock times.
/// All-day events start at 00:00 and have an *exclusive* end (00:00 of the day after the last day).
class CalEvent {
  CalEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location = '',
    this.notes = '',
    this.color = 0,
    List<Reminder>? reminders,
    this.recurrence,
    List<DateTime>? exdates,
    this.uid,
  })  : reminders = reminders ?? <Reminder>[],
        exdates = exdates ?? <DateTime>[];

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String location;
  final String notes;

  /// Index into the event colour palette.
  final int color;
  final List<Reminder> reminders;
  final Recurrence? recurrence;

  /// Start times of occurrences that were deleted from a repeating series.
  final List<DateTime> exdates;

  /// UID from an imported .ics file, so re-importing updates instead of duplicating.
  final String? uid;

  /// Copy with a different colour and/or reminder list (used when importing).
  CalEvent copyWith({int? color, List<Reminder>? reminders}) => CalEvent(
        id: id,
        title: title,
        start: start,
        end: end,
        allDay: allDay,
        location: location,
        notes: notes,
        color: color ?? this.color,
        reminders: reminders ?? List<Reminder>.from(this.reminders),
        recurrence: recurrence,
        exdates: List<DateTime>.from(exdates),
        uid: uid,
      );

  static final math.Random _rng = math.Random();

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_rng.nextInt(1 << 30).toRadixString(36)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'allDay': allDay,
        'location': location,
        'notes': notes,
        'color': color,
        'reminders': reminders.map((r) => r.toJson()).toList(),
        if (recurrence != null) 'rec': recurrence!.toJson(),
        if (exdates.isNotEmpty) 'ex': exdates.map((d) => d.toIso8601String()).toList(),
        if (uid != null) 'uid': uid,
      };

  factory CalEvent.fromJson(Map<String, dynamic> j) => CalEvent(
        id: j['id'] as String,
        title: j['title'] as String,
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        allDay: (j['allDay'] as bool?) ?? false,
        location: (j['location'] as String?) ?? '',
        notes: (j['notes'] as String?) ?? '',
        color: (j['color'] as int?) ?? 0,
        reminders: ((j['reminders'] as List?) ?? const [])
            .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        recurrence: j['rec'] == null
            ? null
            : Recurrence.fromJson(Map<String, dynamic>.from(j['rec'] as Map)),
        exdates:
            ((j['ex'] as List?) ?? const []).map((e) => DateTime.parse(e as String)).toList(),
        uid: j['uid'] as String?,
      );
}

/// One concrete instance of an event on the calendar (a repeating event has many).
class Occurrence {
  const Occurrence(this.event, this.start, this.end);

  final CalEvent event;
  final DateTime start;
  final DateTime end;

  bool get allDay => event.allDay;

  String get key => '${event.id}@${start.millisecondsSinceEpoch}';

  /// The last calendar day this occurrence touches.
  DateTime get lastDay {
    if (allDay) return Fmt.addDays(end, -1);
    if (end.isAfter(start) && end.hour == 0 && end.minute == 0) {
      return Fmt.addDays(end, -1);
    }
    return Fmt.dateOnly(end);
  }
}
