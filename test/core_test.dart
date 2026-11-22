import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:dayline/models/event.dart';
import 'package:dayline/services/format.dart';
import 'package:dayline/services/ics.dart';
import 'package:dayline/services/jalali.dart';
import 'package:dayline/services/recurrence.dart';

void main() {
  // Must run before the groups below, which call tz.getLocation while main() is still executing.
  tzdata.initializeTimeZones();
  setUpAll(() {
    Fmt.use24h = true;
  });

  group('Iranian calendar', () {
    test('1 January 2026 is 11 Dey 1404', () {
      final j = Jalali.fromGregorian(DateTime(2026, 1, 1));
      expect(j, const JalaliDate(1404, 10, 11));
      expect(j.format(withYear: false), '11 Dey');
      expect(j.format(), '11 Dey 1404');
    });

    test('20 November 2026 is 29 Aban 1405', () {
      expect(Jalali.fromGregorian(DateTime(2026, 11, 20)), const JalaliDate(1405, 8, 29));
    });

    test('Nowruz falls on the right Gregorian day', () {
      const nowruz = {
        1399: [2020, 3, 20],
        1400: [2021, 3, 21],
        1403: [2024, 3, 20],
        1404: [2025, 3, 21],
        1405: [2026, 3, 21],
        1407: [2028, 3, 20],
      };
      nowruz.forEach((jy, g) {
        expect(Jalali.toGregorian(jy, 1, 1), DateTime(g[0], g[1], g[2]), reason: 'Nowruz $jy');
      });
    });

    test('leap years and Esfand length', () {
      final leaps = [for (var y = 1395; y <= 1412; y++) if (Jalali.isLeap(y)) y];
      expect(leaps, [1395, 1399, 1403, 1408, 1412]);
      expect(Jalali.monthLength(1403, 12), 30);
      expect(Jalali.monthLength(1404, 12), 29);
    });

    test('every day from 1900 to 2300 round-trips and months are valid', () {
      var d = DateTime(1900, 1, 1);
      final end = DateTime(2300, 12, 31);
      while (!d.isAfter(end)) {
        final j = Jalali.fromGregorian(d);
        expect(Jalali.isValid(j.year, j.month, j.day), isTrue, reason: '$d -> $j');
        expect(Jalali.toGregorian(j.year, j.month, j.day), d, reason: '$d -> $j');
        d = DateTime(d.year, d.month, d.day + 1);
      }
    });
  });

  group('Dates and weeks', () {
    test('ISO week numbers', () {
      expect(Fmt.isoWeek(DateTime(2026, 1, 1)), 1);
      expect(Fmt.isoWeek(DateTime(2026, 11, 20)), 47);
      expect(Fmt.isoWeek(DateTime(2027, 1, 3)), 53);
      expect(Fmt.isoWeek(DateTime(2027, 1, 4)), 1);
    });

    test('weeks start on Monday', () {
      expect(Fmt.mondayOf(DateTime(2026, 11, 22)), DateTime(2026, 11, 16)); // a Sunday
      expect(Fmt.mondayOf(DateTime(2026, 11, 16)), DateTime(2026, 11, 16)); // a Monday
    });
  });

  group('Reminders', () {
    final doctor = DateTime(2026, 7, 23, 15, 30);

    test('an hour before the appointment', () {
      expect(const Reminder.before(60).fireTime(doctor), DateTime(2026, 7, 23, 14, 30));
      expect(const Reminder.before(60).label, '1 hour before');
    });

    test('the day before at 18:00', () {
      const r = Reminder.onDay(1, 18 * 60);
      expect(r.fireTime(doctor), DateTime(2026, 7, 22, 18, 0));
      expect(r.label, 'Day before at 18:00');
    });

    test('JSON round trip', () {
      for (final r in const [Reminder.before(15), Reminder.onDay(2, 540)]) {
        expect(Reminder.fromJson(r.toJson()), r);
      }
    });

    test('earliest reminder sorts first', () {
      final list = [const Reminder.before(60), const Reminder.onDay(1, 18 * 60), const Reminder.before(5)]
        ..sort(Reminder.compare);
      expect(list.first, const Reminder.onDay(1, 18 * 60));
      expect(list.last, const Reminder.before(5));
    });
  });

  group('Repeating events', () {
    CalEvent make(DateTime start, Recurrence r) => CalEvent(
          id: 'x',
          title: 'x',
          start: start,
          end: start.add(const Duration(hours: 1)),
          recurrence: r,
        );

    test('weekly on Monday and Wednesday', () {
      final e = make(DateTime(2026, 9, 14, 10, 15), const Recurrence(freq: RepeatFreq.weekly, byDays: [1, 3]));
      final occ = expandEvent(e, DateTime(2026, 9, 14), DateTime(2026, 9, 28));
      expect(occ.map((o) => o.start.day).toList(), [14, 16, 21, 23]);
    });

    test('monthly on the 31st skips short months', () {
      final e = make(DateTime(2026, 1, 31, 9), const Recurrence(freq: RepeatFreq.monthly));
      final occ = expandEvent(e, DateTime(2026, 1, 1), DateTime(2026, 6, 1));
      expect(occ.map((o) => o.start.month).toList(), [1, 3, 5]);
    });

    test('count and exdates are respected', () {
      final e = make(DateTime(2026, 9, 14, 8), const Recurrence(freq: RepeatFreq.daily, count: 5));
      e.exdates.add(DateTime(2026, 9, 16, 8));
      final occ = expandEvent(e, DateTime(2026, 9, 1), DateTime(2027, 1, 1));
      expect(occ.map((o) => o.start.day).toList(), [14, 15, 17, 18]);
    });
  });

  group('.ics import', () {
    final berlin = tz.getLocation('Europe/Berlin');
    DateTime berlinTime(int y, int mo, int d, int h, int mi) =>
        DateTime.fromMillisecondsSinceEpoch(tz.TZDateTime(berlin, y, mo, d, h, mi).millisecondsSinceEpoch);

    final sample = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'X-WR-CALNAME:Winter term',
      'BEGIN:VEVENT',
      'UID:lecture-1@uni.example',
      'SUMMARY:Algorithms\\, Lecture',
      'LOCATION:Hall 3',
      'DESCRIPTION:Bring laptop and',
      '  charger',
      'DTSTART;TZID=Europe/Berlin:20260914T101500',
      'DTEND;TZID=Europe/Berlin:20260914T114500',
      'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T000000Z',
      'BEGIN:VALARM',
      'TRIGGER:-PT15M',
      'ACTION:DISPLAY',
      'END:VALARM',
      'END:VEVENT',
      'BEGIN:VEVENT',
      'UID:holiday@uni.example',
      'SUMMARY:Christmas break',
      'DTSTART;VALUE=DATE:20261224',
      'END:VEVENT',
      'BEGIN:VEVENT',
      'UID:cancelled@uni.example',
      'SUMMARY:Cancelled seminar',
      'STATUS:CANCELLED',
      'DTSTART:20261001T080000Z',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n');

    test('reads timed, repeating and all-day events', () {
      expect(IcsParser.looksLikeIcs(sample), isTrue);
      final r = IcsParser.parse(sample);

      expect(r.calendarName, 'Winter term');
      expect(r.events.length, 2);
      expect(r.skipped, 1);

      final lecture = r.events.firstWhere((e) => e.uid == 'lecture-1@uni.example');
      expect(lecture.title, 'Algorithms, Lecture');
      expect(lecture.location, 'Hall 3');
      expect(lecture.notes, 'Bring laptop and charger');
      expect(lecture.start, berlinTime(2026, 9, 14, 10, 15));
      expect(lecture.end, berlinTime(2026, 9, 14, 11, 45));
      expect(lecture.recurrence?.freq, RepeatFreq.weekly);
      expect(lecture.recurrence?.byDays, [1, 3]);
      expect(lecture.reminders, [const Reminder.before(15)]);

      final holiday = r.events.firstWhere((e) => e.uid == 'holiday@uni.example');
      expect(holiday.allDay, isTrue);
      expect(holiday.start, DateTime(2026, 12, 24));
      expect(holiday.end, DateTime(2026, 12, 25));
    });

    test('rejects files that are not calendars', () {
      expect(IcsParser.looksLikeIcs('hello world'), isFalse);
    });
  });
}
