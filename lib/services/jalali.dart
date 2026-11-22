/// Iranian (Jalali / Solar Hijri) calendar conversion.
///
/// This is a Dart port of the well-known `jalaali-js` algorithm (33-year
/// arithmetic cycle with a table of break years). Verified against known
/// Nowruz dates and by round-tripping every day from 1900 to 2300.
class JalaliDate {
  const JalaliDate(this.year, this.month, this.day);

  final int year;
  final int month; // 1..12
  final int day;

  String get monthName => Jalali.monthNames[month - 1];
  String get monthShort => Jalali.monthShort[month - 1];

  /// "11 Dey 1404", or "11 Dey" with [withYear] false.
  String format({bool withYear = true}) =>
      withYear ? '$day $monthName $year' : '$day $monthName';

  @override
  bool operator ==(Object other) =>
      other is JalaliDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => format();
}

class _JalCal {
  const _JalCal(this.leap, this.gy, this.march);
  final int leap;
  final int gy;
  final int march;
}

class Jalali {
  Jalali._();

  /// Years the converter and UI accept.
  static const int minYear = 1;
  static const int maxYear = 3000;

  static const monthNames = [
    'Farvardin',
    'Ordibehesht',
    'Khordad',
    'Tir',
    'Mordad',
    'Shahrivar',
    'Mehr',
    'Aban',
    'Azar',
    'Dey',
    'Bahman',
    'Esfand',
  ];

  static const monthShort = [
    'Far',
    'Ord',
    'Kho',
    'Tir',
    'Mor',
    'Sha',
    'Meh',
    'Aba',
    'Aza',
    'Dey',
    'Bah',
    'Esf',
  ];

  static const _breaks = <int>[
    -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, //
    1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
  ];

  // Truncating division and matching modulo (same semantics as the JS original).
  static int _div(int a, int b) => a ~/ b;
  static int _mod(int a, int b) => a - (a ~/ b) * b;

  static _JalCal _jalCal(int jy, {required bool withLeap}) {
    final bl = _breaks.length;
    final gy = jy + 621;
    var leapJ = -14;
    var jp = _breaks[0];
    if (jy < jp || jy >= _breaks[bl - 1]) {
      throw RangeError('Invalid Jalali year $jy');
    }

    var jump = 0;
    for (var i = 1; i < bl; i++) {
      final jm = _breaks[i];
      jump = jm - jp;
      if (jy < jm) break;
      leapJ = leapJ + _div(jump, 33) * 8 + _div(_mod(jump, 33), 4);
      jp = jm;
    }
    var n = jy - jp;

    leapJ = leapJ + _div(n, 33) * 8 + _div(_mod(n, 33) + 3, 4);
    if (_mod(jump, 33) == 4 && jump - n == 4) leapJ += 1;

    final leapG = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150;
    final march = 20 + leapJ - leapG;

    if (!withLeap) return _JalCal(0, gy, march);

    if (jump - n < 6) n = n - jump + _div(jump + 4, 33) * 33;
    var leap = _mod(_mod(n + 1, 33) - 1, 4);
    if (leap == -1) leap = 4;
    return _JalCal(leap, gy, march);
  }

  static int _g2d(int gy, int gm, int gd) {
    var d = _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4) +
        _div(153 * _mod(gm + 9, 12) + 2, 5) +
        gd -
        34840408;
    d = d - _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) + 752;
    return d;
  }

  static List<int> _d2g(int jdn) {
    var j = 4 * jdn + 139361631;
    j = j + _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908;
    final i = _div(_mod(j, 1461), 4) * 5 + 308;
    final gd = _div(_mod(i, 153), 5) + 1;
    final gm = _mod(_div(i, 153), 12) + 1;
    final gy = _div(j, 1461) - 100100 + _div(8 - gm, 6);
    return [gy, gm, gd];
  }

  static int _j2d(int jy, int jm, int jd) {
    final r = _jalCal(jy, withLeap: false);
    return _g2d(r.gy, 3, r.march) + (jm - 1) * 31 - _div(jm, 7) * (jm - 7) + jd - 1;
  }

  static List<int> _d2j(int jdn) {
    final gy = _d2g(jdn)[0];
    var jy = gy - 621;
    final r = _jalCal(jy, withLeap: true);
    final jdn1f = _g2d(gy, 3, r.march);
    var k = jdn - jdn1f;
    if (k >= 0) {
      if (k <= 185) {
        return [jy, 1 + _div(k, 31), _mod(k, 31) + 1];
      }
      k -= 186;
    } else {
      jy -= 1;
      k += 179;
      if (r.leap == 1) k += 1;
    }
    return [jy, 7 + _div(k, 30), _mod(k, 30) + 1];
  }

  // ---- public API --------------------------------------------------------

  /// A Jalali year is leap when the next Farvardin 1 is 366 days away.
  static bool isLeap(int jy) => _j2d(jy + 1, 1, 1) - _j2d(jy, 1, 1) == 366;

  static int monthLength(int jy, int jm) {
    if (jm <= 6) return 31;
    if (jm <= 11) return 30;
    return isLeap(jy) ? 30 : 29;
  }

  static bool isValid(int jy, int jm, int jd) =>
      jy >= minYear &&
      jy <= maxYear &&
      jm >= 1 &&
      jm <= 12 &&
      jd >= 1 &&
      jd <= monthLength(jy, jm);

  /// Gregorian date (only year/month/day are used) -> Jalali date.
  /// Throws [RangeError] for dates outside the supported range.
  static JalaliDate fromGregorian(DateTime d) {
    final j = _d2j(_g2d(d.year, d.month, d.day));
    return JalaliDate(j[0], j[1], j[2]);
  }

  static JalaliDate? tryFromGregorian(DateTime d) {
    try {
      return fromGregorian(d);
    } on RangeError {
      return null;
    }
  }

  /// Jalali date -> Gregorian date (local midnight). Throws [RangeError] when
  /// the year is outside the supported range; use [isValid] first for days.
  static DateTime toGregorian(int jy, int jm, int jd) {
    final g = _d2g(_j2d(jy, jm, jd));
    return DateTime(g[0], g[1], g[2]);
  }
}
