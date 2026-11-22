import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/event.dart';
import '../services/format.dart';
import '../services/jalali.dart';
import '../services/store.dart';
import '../theme.dart';
import 'converter_page.dart';
import 'day_ring.dart';
import 'event_details.dart';
import 'event_editor.dart';
import 'import_flow.dart';
import 'month_sheet.dart';
import 'settings_page.dart';
import 'widgets.dart';

class _RingCenter {
  const _RingCenter(this.label, this.title, this.sub);
  final String label;
  final String title;
  final String sub;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _mid = 5000;

  late final Store _store;
  late final PageController _pages;
  late final DateTime _anchor; // Monday of the week that is page _mid
  Timer? _clock;
  DateTime _now = DateTime.now();
  bool _programmatic = false;
  int _animToken = 0;

  @override
  void initState() {
    super.initState();
    _store = AppScope.of(context).store;
    _anchor = Fmt.mondayOf(_store.selected);
    _pages = PageController(initialPage: _mid);
    _store.addListener(_onStore);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _store.removeListener(_onStore);
    _pages.dispose();
    super.dispose();
  }

  int _pageFor(DateTime d) => _mid + Fmt.daysBetween(_anchor, Fmt.mondayOf(d)) ~/ 7;

  DateTime _mondayFor(int page) => Fmt.addDays(_anchor, (page - _mid) * 7);

  /// The selected day changed from somewhere else (month sheet, notification, today button).
  void _onStore() {
    if (!_pages.hasClients) return;
    final target = _pageFor(_store.selected);
    final current = _pages.page?.round() ?? _mid;
    if (current == target) return;
    if ((current - target).abs() > 2) {
      _pages.jumpToPage(target);
    } else {
      final token = ++_animToken; // only the latest animation may clear the flag
      _programmatic = true;
      _pages
          .animateToPage(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic)
          .whenComplete(() {
        if (token == _animToken) _programmatic = false;
      });
    }
  }

  void _onPageChanged(int page) {
    if (_programmatic) return;
    final delta = Fmt.daysBetween(Fmt.mondayOf(_store.selected), _mondayFor(page));
    if (delta != 0) _store.select(Fmt.addDays(_store.selected, delta));
  }

  void _goToday() => _store.select(DateTime.now());

  void _newEvent() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EventEditorPage(initialDay: _store.selected)),
    );
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final day = _store.selected;
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _newEvent,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New event', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          body: SafeArea(
            child: Column(
              children: [
                _header(context, day),
                _ribbon(context, day),
                const SizedBox(height: 4),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -350) _store.select(Fmt.addDays(day, 1));
                      if (v > 350) _store.select(Fmt.addDays(day, -1));
                    },
                    child: _body(context, day),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- header ------------------------------------------------------------

  String _title(DateTime day) {
    final diff = Fmt.daysBetween(_now, day);
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return Fmt.weekdaysLong[day.weekday - 1];
  }

  Widget _header(BuildContext context, DateTime day) {
    final s = _store.settings;
    final isToday = Fmt.sameDay(day, _now);

    var sub = '${day.day} ${Fmt.monthsLong[day.month - 1]} ${day.year}';
    if (s.showWeekNumbers) sub += ' · Week ${Fmt.isoWeek(day)}';
    final jalali = s.showIranian ? Jalali.tryFromGregorian(day) : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _title(day),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1),
                      ),
                    ),
                    if (!isToday) ...[
                      const SizedBox(width: 10),
                      ActionChip(
                        label: const Text('Today'),
                        onPressed: _goToday,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: context.accent.withValues(alpha: 0.5)),
                        labelStyle: TextStyle(color: context.accent, fontWeight: FontWeight.w600, fontSize: 12),
                        backgroundColor: Colors.transparent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: context.muted, fontSize: 14)),
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
          IranToggle(
            on: s.showIranian,
            onTap: () => _store.updateSettings((x) => x.showIranian = !x.showIranian),
          ),
          IconButton(
            tooltip: 'Month',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => showMonthSheet(context),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            color: context.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (v) {
              switch (v) {
                case 'import':
                  importIcsFlow(context);
                case 'convert':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ConverterPage()),
                  );
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
                  );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Import .ics file')),
              PopupMenuItem(value: 'convert', child: Text('Date converter')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
    );
  }

  // ---- week ribbon ---------------------------------------------------------

  Widget _ribbon(BuildContext context, DateTime day) {
    final weeks = _store.settings.showWeekNumbers;
    return SizedBox(
      height: 82,
      child: Row(
        children: [
          if (weeks)
            SizedBox(
              width: 44,
              child: Center(
                child: Text(
                  'W${Fmt.isoWeek(day)}',
                  style: TextStyle(color: context.muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            // Mouse and trackpad dragging is off by default on desktop; allow it for Windows.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: PageView.builder(
                controller: _pages,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, page) => _weekRow(context, _mondayFor(page)),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _weekRow(BuildContext context, DateTime monday) {
    return Row(
      children: [
        for (var i = 0; i < 7; i++) Expanded(child: _dayCell(context, Fmt.addDays(monday, i))),
      ],
    );
  }

  Widget _dayCell(BuildContext context, DateTime d) {
    final selected = Fmt.sameDay(d, _store.selected);
    final today = Fmt.sameDay(d, _now);
    final occs = _store.occurrencesForDay(d);

    final colors = <int>[];
    for (final o in occs) {
      if (!colors.contains(o.event.color)) colors.add(o.event.color);
      if (colors.length == 3) break;
    }

    final fg = selected ? Theme.of(context).colorScheme.onPrimary : (today ? context.accent : context.text);
    final sub = selected ? fg.withValues(alpha: 0.75) : context.muted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _store.select(d),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? context.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: (today && !selected) ? Border.all(color: context.accent.withValues(alpha: 0.6)) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                Fmt.weekdaysShort[d.weekday - 1].toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: sub),
              ),
              const SizedBox(height: 3),
              Text(
                '${d.day}',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: fg),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in colors)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: selected ? fg : Pal.event(c),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- body ----------------------------------------------------------------

  _RingCenter _center(DateTime day, List<Occurrence> occs) {
    final timed = occs.where((o) => !o.allDay).toList();
    final isToday = Fmt.sameDay(day, _now);

    if (isToday) {
      Occurrence? current;
      Occurrence? next;
      for (final o in timed) {
        if (!o.start.isAfter(_now) && o.end.isAfter(_now)) {
          current ??= o;
        } else if (o.start.isAfter(_now)) {
          next ??= o;
        }
      }
      if (current != null) {
        return _RingCenter('NOW', current.event.title, 'until ${Fmt.time(current.end)}');
      }
      if (next != null) {
        final diff = next.start.difference(_now);
        final sub = diff.inHours < 12 ? 'in ${Fmt.span(diff)}' : 'at ${Fmt.time(next.start)}';
        return _RingCenter('NEXT', next.event.title, sub);
      }
      if (occs.isEmpty) return const _RingCenter('', 'Free day', 'Nothing planned');
      if (timed.isEmpty) {
        return _RingCenter('', Fmt.plural(occs.length, 'all-day item'), 'on today');
      }
      return const _RingCenter('', 'All done', 'for today');
    }

    if (occs.isEmpty) return const _RingCenter('', 'Free day', 'Nothing planned');
    if (timed.isEmpty) {
      return _RingCenter('', Fmt.plural(occs.length, 'all-day item'), '');
    }
    return _RingCenter(
      '',
      Fmt.plural(occs.length, 'event'),
      'first at ${Fmt.time(timed.first.start.isBefore(day) ? day : timed.first.start)}',
    );
  }

  Widget _body(BuildContext context, DateTime day) {
    final occs = _store.occurrencesForDay(day);
    final allDay = occs.where((o) => o.allDay).toList();
    final timed = occs.where((o) => !o.allDay).toList();
    final isToday = Fmt.sameDay(day, _now);
    final c = _center(day, occs);

    return LayoutBuilder(
      builder: (context, box) {
        final ring = math.min(math.min(box.maxWidth - 40, 300.0), math.max(190.0, box.maxHeight * 0.5));
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 110),
          children: [
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: DayRing(
                  key: ValueKey('${day.year}-${day.month}-${day.day}'),
                  size: ring,
                  day: day,
                  occurrences: occs,
                  now: _now,
                  center: _ringCenterWidget(context, c),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (allDay.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final o in allDay) _allDayChip(context, o)],
                ),
              ),
            if (timed.isEmpty && allDay.isEmpty) _empty(context, day),
            for (final o in timed) _agendaTile(context, o, day),
            if (isToday) _tomorrowLine(context, day),
          ],
        );
      },
    );
  }

  Widget _ringCenterWidget(BuildContext context, _RingCenter c) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (c.label.isNotEmpty)
          Text(
            c.label,
            style: TextStyle(
              color: context.accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        if (c.label.isNotEmpty) const SizedBox(height: 4),
        Flexible(
          child: Text(
            c.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.15),
          ),
        ),
        if (c.sub.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(c.sub, style: TextStyle(color: context.muted, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _allDayChip(BuildContext context, Occurrence o) {
    final color = Pal.event(o.event.color);
    return GestureDetector(
      onTap: () => showEventDetails(context, o),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                o.event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _agendaTile(BuildContext context, Occurrence o, DateTime day) {
    final color = Pal.event(o.event.color);
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    final startsEarlier = o.start.isBefore(dayStart);
    final endsLater = o.end.isAfter(dayEnd);
    final isToday = Fmt.sameDay(day, _now);
    final over = isToday && o.end.isBefore(_now);
    final live = isToday && !o.start.isAfter(_now) && o.end.isAfter(_now);
    final remCount = o.event.reminders.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: over ? 0.5 : 1,
        child: Material(
          color: context.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showEventDetails(context, o),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: live ? Border.all(color: context.accent.withValues(alpha: 0.7), width: 1.4) : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: Fmt.use24h ? 52 : 72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          startsEarlier ? '…' : Fmt.time(o.start),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          endsLater ? '…' : Fmt.time(o.end),
                          style: TextStyle(color: context.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 4,
                    height: 38,
                    margin: const EdgeInsets.only(right: 14),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        if (o.event.location.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.place_outlined, size: 14, color: context.muted),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  o.event.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.muted, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (remCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none_rounded, size: 18, color: context.muted),
                          if (remCount > 1)
                            Text('$remCount', style: TextStyle(color: context.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  if (o.event.recurrence != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.repeat_rounded, size: 16, color: context.muted),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, DateTime day) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Text('A clear day.', style: TextStyle(color: context.muted, fontSize: 16)),
          const SizedBox(height: 10),
          TextButton(onPressed: _newEvent, child: const Text('Plan something')),
        ],
      ),
    );
  }

  /// Under today's list: a gentle look at how tomorrow starts.
  Widget _tomorrowLine(BuildContext context, DateTime day) {
    final tomorrow = Fmt.addDays(day, 1);
    final occs = _store.occurrencesForDay(tomorrow);
    if (occs.isEmpty) return const SizedBox.shrink();
    final first = occs.firstWhere((o) => !o.allDay, orElse: () => occs.first);
    final when = first.allDay ? 'all day' : 'at ${Fmt.time(first.start)}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => _store.select(tomorrow),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.line),
          ),
          child: Row(
            children: [
              Icon(Icons.wb_twilight_rounded, size: 18, color: context.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tomorrow: ${first.event.title} $when'
                  '${occs.length > 1 ? '  ·  +${occs.length - 1} more' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.muted, fontSize: 13),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: context.muted),
            ],
          ),
        ),
      ),
    );
  }
}
