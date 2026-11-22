/// Small helpers for dates, clock times and English labels.
/// The app is English-only, so everything is formatted by hand (no intl needed).
class Fmt {
  Fmt._();

  /// Mirrors the "24-hour time" setting. Set by the Store.
  static bool use24h = true;

  static const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const weekdaysLong = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const monthsLong = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String two(int n) => n.toString().padLeft(2, '0');

  // ---- dates -------------------------------------------------------------

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Date (midnight) [n] days after [d]'s date. Safe across DST changes.
  static DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Monday of the week containing [d] (weeks start on Monday).
  static DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// Whole calendar days from [a] to [b] (ignores time of day and DST).
  static int daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;

  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// ISO-8601 week number (weeks start Monday, week 1 contains the first Thursday).
  static int isoWeek(DateTime d) {
    final date = DateTime.utc(d.year, d.month, d.day);
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstJan = DateTime.utc(thursday.year, 1, 1);
    return thursday.difference(firstJan).inDays ~/ 7 + 1;
  }

  // ---- clock -------------------------------------------------------------

  static String time(DateTime d) => _clock(d.hour, d.minute);

  static String minuteOfDay(int minutes) => _clock(minutes ~/ 60, minutes % 60);

  static String _clock(int h, int m) {
    if (use24h) return '${two(h)}:${two(m)}';
    final suffix = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${two(m)} $suffix';
  }

  // ---- labels ------------------------------------------------------------

  /// "Friday, 20 November 2026"
  static String dateLong(DateTime d) =>
      '${weekdaysLong[d.weekday - 1]}, ${d.day} ${monthsLong[d.month - 1]} ${d.year}';

  /// "Fri 20 Nov 2026"
  static String dateMedium(DateTime d) =>
      '${weekdaysShort[d.weekday - 1]} ${d.day} ${monthsShort[d.month - 1]} ${d.year}';

  /// "Fri 20 Nov"
  static String dateShort(DateTime d) =>
      '${weekdaysShort[d.weekday - 1]} ${d.day} ${monthsShort[d.month - 1]}';

  /// "Today", "Tomorrow", "Yesterday" or "Mon 23 Nov", relative to [reference].
  static String dayLabel(DateTime day, DateTime reference) {
    final diff = daysBetween(reference, day);
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return dateShort(day);
  }

  /// "45 min", "2 h 15 min", "3 days".
  static String span(Duration d) {
    final m = d.inMinutes;
    if (m < 1) return 'under a minute';
    if (m < 60) return '$m min';
    if (m < 60 * 24) {
      final h = m ~/ 60;
      final r = m % 60;
      return r == 0 ? '$h h' : '$h h $r min';
    }
    final days = m ~/ (60 * 24);
    return days == 1 ? '1 day' : '$days days';
  }

  static String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
}
