import 'package:flutter/material.dart';

import '../app.dart';
import '../services/format.dart';
import '../services/jalali.dart';
import '../services/store.dart';
import '../theme.dart';
import 'widgets.dart';

/// The full month grid lives here, one tap away, instead of filling the home screen.
Future<void> showMonthSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _MonthSheet(),
  );
}

class _MonthSheet extends StatefulWidget {
  const _MonthSheet();

  @override
  State<_MonthSheet> createState() => _MonthSheetState();
}

class _MonthSheetState extends State<_MonthSheet> {
  late final Store _store;
  late DateTime _month; // first day of the shown month

  @override
  void initState() {
    super.initState();
    _store = AppScope.of(context).store;
    _month = DateTime(_store.selected.year, _store.selected.month, 1);
  }

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months, 1));

  String _iranSpan() {
    final a = Jalali.tryFromGregorian(_month);
    final b = Jalali.tryFromGregorian(DateTime(_month.year, _month.month + 1, 0));
    if (a == null || b == null) return '';
    if (a.year == b.year && a.month == b.month) return '${a.monthName} ${a.year}';
    if (a.year == b.year) return '${a.monthName} – ${b.monthName} ${a.year}';
    return '${a.monthName} ${a.year} – ${b.monthName} ${b.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final s = _store.settings;
        final selected = _store.selected;
        final today = Fmt.dateOnly(DateTime.now());

        final gridStart = Fmt.mondayOf(_month);
        final lastDay = DateTime(_month.year, _month.month + 1, 0);
        final rows = Fmt.daysBetween(gridStart, lastDay) ~/ 7 + 1;

        return GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -300) _shift(1);
            if (v > 300) _shift(-1);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => _shift(-1),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${Fmt.monthsLong[_month.month - 1]} ${_month.year}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          if (s.showIranian)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _iranSpan(),
                                style: TextStyle(color: context.accent, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => _shift(1),
                    ),
                    IranToggle(
                      on: s.showIranian,
                      onTap: () => _store.updateSettings((x) => x.showIranian = !x.showIranian),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (s.showWeekNumbers) const SizedBox(width: 30),
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Center(
                          child: Text(
                            Fmt.weekdaysShort[i].toUpperCase(),
                            style: TextStyle(
                              color: context.muted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                for (var r = 0; r < rows; r++)
                  Row(
                    children: [
                      if (s.showWeekNumbers)
                        SizedBox(
                          width: 30,
                          child: Center(
                            child: Text(
                              '${Fmt.isoWeek(Fmt.addDays(gridStart, r * 7))}',
                              style: TextStyle(color: context.muted, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      for (var c = 0; c < 7; c++)
                        Expanded(child: _cell(context, Fmt.addDays(gridStart, r * 7 + c), selected, today)),
                    ],
                  ),
                const SizedBox(height: 14),
                _footer(context, selected),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cell(BuildContext context, DateTime d, DateTime selected, DateTime today) {
    final inMonth = d.month == _month.month;
    final isSel = Fmt.sameDay(d, selected);
    final isToday = Fmt.sameDay(d, today);
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final occs = _store.occurrencesForDay(d);

    final colors = <int>[];
    for (final o in occs) {
      if (!colors.contains(o.event.color)) colors.add(o.event.color);
      if (colors.length == 3) break;
    }

    String? iran;
    if (_store.settings.showIranian) {
      final j = Jalali.tryFromGregorian(d);
      if (j != null) iran = j.day == 1 ? j.monthShort : '${j.day}';
    }

    final numColor = isSel
        ? onPrimary
        : isToday
            ? context.accent
            : (inMonth ? context.text : context.muted.withValues(alpha: 0.45));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _store.select(d);
        if (!inMonth) setState(() => _month = DateTime(d.year, d.month, 1));
      },
      child: Container(
        height: 54,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSel ? context.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: (isToday && !isSel) ? Border.all(color: context.accent.withValues(alpha: 0.6)) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${d.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: numColor)),
            if (iran != null)
              Text(
                iran,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.1,
                  color: isSel ? onPrimary.withValues(alpha: 0.8) : context.muted.withValues(alpha: inMonth ? 1 : 0.5),
                ),
              ),
            const SizedBox(height: 3),
            SizedBox(
              height: 5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in colors)
                    Container(
                      width: 4.5,
                      height: 4.5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.2),
                      decoration: BoxDecoration(
                        color: isSel ? onPrimary : Pal.event(c),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, DateTime selected) {
    final s = _store.settings;
    final occs = _store.occurrencesForDay(selected);
    final jalali = s.showIranian ? Jalali.tryFromGregorian(selected) : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.dateLong(selected),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                if (jalali != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    jalali.format(),
                    style: TextStyle(color: context.accent, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  occs.isEmpty ? 'Nothing planned' : Fmt.plural(occs.length, 'event'),
                  style: TextStyle(color: context.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Open day'),
          ),
        ],
      ),
    );
  }
}
