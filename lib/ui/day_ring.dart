import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/event.dart';
import '../services/format.dart';
import '../theme.dart';

class _Seg {
  _Seg(this.startMin, this.endMin, this.color);
  final int startMin;
  final int endMin;
  final Color color;
  int lane = 0;
}

/// The signature element of Dayline: the whole day as a 24-hour ring.
/// Midnight is at the top; events are coloured arcs; a bright dot shows "now".
class DayRing extends StatelessWidget {
  const DayRing({
    super.key,
    required this.size,
    required this.day,
    required this.occurrences,
    required this.now,
    required this.center,
  });

  final double size;
  final DateTime day;
  final List<Occurrence> occurrences;
  final DateTime now;
  final Widget center;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(
              segments: _segments(),
              showNow: Fmt.sameDay(day, now),
              nowMinute: now.hour * 60 + now.minute,
              track: context.surface2,
              tick: context.line,
              tickText: context.muted,
              accent: context.accent,
              halo: context.bg,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(size * 0.24),
            child: center,
          ),
        ],
      ),
    );
  }

  List<_Seg> _segments() {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    final segs = <_Seg>[];

    for (final o in occurrences) {
      if (o.allDay) continue;
      final s = o.start.isBefore(dayStart) ? dayStart : o.start;
      final e = o.end.isAfter(dayEnd) ? dayEnd : o.end;
      final startMin = s.isAtSameMomentAs(dayStart) ? 0 : s.hour * 60 + s.minute;
      var endMin = e.isAtSameMomentAs(dayEnd) ? 1440 : e.hour * 60 + e.minute;
      if (endMin < startMin + 20) endMin = math.min(1440, startMin + 20); // keep tiny events visible
      if (startMin >= 1440) continue;
      segs.add(_Seg(startMin, endMin, Pal.event(o.event.color)));
    }

    // Overlapping events go to inner lanes.
    segs.sort((a, b) => a.startMin.compareTo(b.startMin));
    final laneEnds = <int>[];
    for (final s in segs) {
      var placed = false;
      for (var i = 0; i < laneEnds.length; i++) {
        if (laneEnds[i] <= s.startMin) {
          s.lane = i;
          laneEnds[i] = s.endMin;
          placed = true;
          break;
        }
      }
      if (!placed) {
        if (laneEnds.length < 3) {
          s.lane = laneEnds.length;
          laneEnds.add(s.endMin);
        } else {
          s.lane = segs.indexOf(s) % 3;
        }
      }
    }
    return segs;
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.segments,
    required this.showNow,
    required this.nowMinute,
    required this.track,
    required this.tick,
    required this.tickText,
    required this.accent,
    required this.halo,
  });

  final List<_Seg> segments;
  final bool showNow;
  final int nowMinute;
  final Color track;
  final Color tick;
  final Color tickText;
  final Color accent;
  final Color halo;

  static const double _margin = 32;
  static const double _lane = 11;
  static const double _gap = 4;

  double _angle(num minute) => -math.pi / 2 + 2 * math.pi * (minute / 1440);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - _margin;

    final lanesUsed = segments.isEmpty ? 1 : segments.map((s) => s.lane).reduce(math.max) + 1;

    // Tracks.
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lane
      ..color = track;
    for (var i = 0; i < lanesUsed; i++) {
      canvas.drawCircle(c, outerR - i * (_lane + _gap), trackPaint);
    }

    // Hour ticks and labels outside the ring.
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = tick;
    for (var h = 0; h < 24; h++) {
      final a = _angle(h * 60);
      final major = h % 6 == 0;
      tickPaint.strokeWidth = major ? 2 : 1.4;
      final r1 = outerR + _lane / 2 + 6;
      final r2 = r1 + (major ? 7 : 3.5);
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * r1,
        c + Offset(math.cos(a), math.sin(a)) * r2,
        tickPaint,
      );
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: Fmt.two(h),
            style: TextStyle(color: tickText, fontSize: 10, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final lp = c + Offset(math.cos(a), math.sin(a)) * (r2 + 9);
        tp.paint(canvas, lp - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // Event arcs.
    for (final s in segments) {
      final r = outerR - s.lane * (_lane + _gap);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _lane
        ..color = s.color;
      // Pull the ends in a touch so round caps do not bleed into neighbours.
      final capPad = (_lane / 2) / r;
      var start = _angle(s.startMin) + capPad;
      var sweep = 2 * math.pi * ((s.endMin - s.startMin) / 1440) - capPad * 2;
      if (sweep < 0.02) {
        start = _angle((s.startMin + s.endMin) / 2) - 0.01;
        sweep = 0.02;
      }
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, false, p);
    }

    // "Now" marker.
    if (showNow) {
      final a = _angle(nowMinute);
      final pos = c + Offset(math.cos(a), math.sin(a)) * outerR;
      canvas.drawCircle(pos, 9, Paint()..color = halo);
      canvas.drawCircle(pos, 6, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}
