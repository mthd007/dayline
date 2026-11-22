import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../services/format.dart';
import '../services/jalali.dart';
import '../theme.dart';

/// Gregorian <-> Iranian (Solar Hijri) date converter.
class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _Result {
  const _Result({required this.big, required this.small, required this.gregorian});
  final String big;
  final String small;
  final DateTime gregorian; // the same day as a Gregorian date
}

class _ConverterPageState extends State<ConverterPage> {
  int _mode = 0; // 0: Gregorian -> Iranian, 1: Iranian -> Gregorian
  final _day = TextEditingController();
  final _year = TextEditingController();
  int _month = 1;

  @override
  void initState() {
    super.initState();
    _fillToday();
  }

  @override
  void dispose() {
    _day.dispose();
    _year.dispose();
    super.dispose();
  }

  void _fillToday() {
    final now = DateTime.now();
    if (_mode == 0) {
      _day.text = '${now.day}';
      _month = now.month;
      _year.text = '${now.year}';
    } else {
      final j = Jalali.fromGregorian(now);
      _day.text = '${j.day}';
      _month = j.month;
      _year.text = '${j.year}';
    }
  }

  void _setMode(int mode) {
    if (mode == _mode) return;
    final r = _compute().$1;
    setState(() {
      _mode = mode;
      if (r != null) {
        // Carry the converted date over, so you can flip back and forth.
        final g = r.gregorian;
        if (_mode == 0) {
          _day.text = '${g.day}';
          _month = g.month;
          _year.text = '${g.year}';
        } else {
          final j = Jalali.fromGregorian(g);
          _day.text = '${j.day}';
          _month = j.month;
          _year.text = '${j.year}';
        }
      } else {
        _fillToday();
      }
    });
  }

  /// Returns (result, errorMessage).
  (_Result?, String?) _compute() {
    final d = int.tryParse(_day.text.trim());
    final y = int.tryParse(_year.text.trim());
    if (d == null || y == null) return (null, 'Enter a day and a year');

    try {
      if (_mode == 0) {
        if (y < 622 || y > 3700) return (null, 'Year must be between 622 and 3700');
        if (d < 1 || d > Fmt.daysInMonth(y, _month)) {
          return (null, '${Fmt.monthsLong[_month - 1]} $y has ${Fmt.daysInMonth(y, _month)} days');
        }
        final g = DateTime(y, _month, d);
        if (g.isBefore(DateTime(622, 3, 22))) {
          return (null, 'The Iranian calendar starts on 22 March 622');
        }
        final j = Jalali.fromGregorian(g);
        return (
          _Result(
            big: j.format(),
            small: Fmt.weekdaysLong[g.weekday - 1],
            gregorian: g,
          ),
          null,
        );
      }

      if (y < Jalali.minYear || y > 3000) return (null, 'Year must be between ${Jalali.minYear} and 3000');
      if (d < 1 || d > Jalali.monthLength(y, _month)) {
        return (null, '${Jalali.monthNames[_month - 1]} $y has ${Jalali.monthLength(y, _month)} days');
      }
      final g = Jalali.toGregorian(y, _month, d);
      return (
        _Result(
          big: '${g.day} ${Fmt.monthsLong[g.month - 1]} ${g.year}',
          small: Fmt.weekdaysLong[g.weekday - 1],
          gregorian: g,
        ),
        null,
      );
    } on RangeError {
      return (null, 'That date is outside the supported range');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (result, error) = _compute();
    final months = _mode == 0 ? Fmt.monthsLong : Jalali.monthNames;

    return Scaffold(
      appBar: AppBar(title: const Text('Date converter')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Gregorian → Iranian')),
                ButtonSegment(value: 1, label: Text('Iranian → Gregorian')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _setMode(s.first),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _mode == 0 ? 'GREGORIAN DATE' : 'IRANIAN DATE',
            style: TextStyle(color: context.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                child: TextField(
                  controller: _day,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'Day'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Month'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _month,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: context.surface2,
                      items: [
                        for (var i = 0; i < 12; i++)
                          DropdownMenuItem(value: i + 1, child: Text(months[i])),
                      ],
                      onChanged: (v) => setState(() => _month = v ?? 1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'Year'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(_fillToday),
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('Use today'),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: result != null
                ? _resultCard(context, result)
                : Container(
                    key: const ValueKey('error'),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(error ?? '', style: TextStyle(color: context.muted, fontSize: 15)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context, _Result r) {
    final scope = AppScope.of(context);
    return Container(
      key: ValueKey('${r.big}|$_mode'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 12, 16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _mode == 0 ? 'IRANIAN DATE' : 'GREGORIAN DATE',
            style: TextStyle(color: context.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  r.big,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: context.accent, letterSpacing: -0.5),
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: r.big));
                  messenger.showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
            ],
          ),
          Text(r.small, style: TextStyle(color: context.muted, fontSize: 15)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined, size: 18),
                label: const Text('Show in calendar'),
                onPressed: () {
                  scope.store.select(r.gregorian);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
