import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import 'format.dart';
import 'recurrence.dart';

class Settings {
  bool showIranian = false;
  bool showWeekNumbers = false;
  bool use24h = true;
  ThemeMode themeMode = ThemeMode.dark;

  Map<String, dynamic> toJson() => {
        'iran': showIranian,
        'weeks': showWeekNumbers,
        'h24': use24h,
        'theme': themeMode.name,
      };

  void applyJson(Map<String, dynamic> j) {
    showIranian = (j['iran'] as bool?) ?? false;
    showWeekNumbers = (j['weeks'] as bool?) ?? false;
    use24h = (j['h24'] as bool?) ?? true;
    final t = j['theme'] as String?;
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == t,
      orElse: () => ThemeMode.dark,
    );
  }
}

class ImportSummary {
  const ImportSummary(this.added, this.updated);
  final int added;
  final int updated;
}

/// Holds all events and settings, persists them locally and answers
/// "what is on this day?" questions.
class Store extends ChangeNotifier {
  static const _kEvents = 'dayline.events.v1';
  static const _kSettings = 'dayline.settings.v1';

  final Settings settings = Settings();

  /// Bumps whenever events (or settings that change reminder/widget text) change.
  /// Selecting a different day does not bump it.
  final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);

  final List<CalEvent> _events = [];
  final Map<int, List<Occurrence>> _dayCache = {};
  late SharedPreferences _prefs;
  DateTime _selected = Fmt.dateOnly(DateTime.now());

  List<CalEvent> get events => List.unmodifiable(_events);
  DateTime get selected => _selected;

  // ---- loading / saving --------------------------------------------------

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    try {
      final s = _prefs.getString(_kSettings);
      if (s != null) settings.applyJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (e) {
      debugPrint('Could not read settings: $e');
    }
    Fmt.use24h = settings.use24h;

    try {
      final raw = _prefs.getString(_kEvents);
      if (raw != null) {
        for (final item in jsonDecode(raw) as List) {
          _events.add(CalEvent.fromJson(Map<String, dynamic>.from(item as Map)));
        }
      }
    } catch (e) {
      debugPrint('Could not read events: $e');
    }
  }

  Future<void> _persistEvents() async {
    try {
      await _prefs.setString(_kEvents, jsonEncode(_events.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('Could not save events: $e');
    }
  }

  Future<void> _persistSettings() async {
    try {
      await _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Could not save settings: $e');
    }
  }

  void _dataChanged() {
    _dayCache.clear();
    dataRevision.value++;
    notifyListeners();
    unawaited(_persistEvents());
  }

  // ---- selection ---------------------------------------------------------

  void select(DateTime day) {
    final d = Fmt.dateOnly(day);
    if (Fmt.sameDay(d, _selected)) return;
    _selected = d;
    notifyListeners();
  }

  // ---- settings ----------------------------------------------------------

  void updateSettings(void Function(Settings s) change) {
    change(settings);
    Fmt.use24h = settings.use24h;
    dataRevision.value++;
    notifyListeners();
    unawaited(_persistSettings());
  }

  // ---- events ------------------------------------------------------------

  void upsert(CalEvent e) {
    final i = _events.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      _events[i] = e;
    } else {
      _events.add(e);
    }
    _dataChanged();
  }

  void remove(String id) {
    _events.removeWhere((e) => e.id == id);
    _dataChanged();
  }

  /// Delete one occurrence of a repeating event.
  void skipOccurrence(CalEvent e, DateTime start) {
    e.exdates.add(start);
    _dataChanged();
  }

  void removeAll() {
    _events.clear();
    _dataChanged();
  }

  /// Adds imported events. Events whose UID is already known replace the old copy.
  ImportSummary importEvents(List<CalEvent> incoming) {
    var added = 0;
    var updated = 0;
    for (final ev in incoming) {
      final i = ev.uid == null ? -1 : _events.indexWhere((x) => x.uid == ev.uid);
      if (i >= 0) {
        _events[i] = ev;
        updated++;
      } else {
        _events.add(ev);
        added++;
      }
    }
    _dataChanged();
    return ImportSummary(added, updated);
  }

  // ---- queries -----------------------------------------------------------

  /// Everything happening on [day], all-day items first, then by start time.
  List<Occurrence> occurrencesForDay(DateTime day) {
    final key = day.year * 10000 + day.month * 100 + day.day;
    final cached = _dayCache[key];
    if (cached != null) return cached;

    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    final list = occurrencesBetween(from, to);
    list.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.event.title.compareTo(b.event.title);
    });
    _dayCache[key] = list;
    return list;
  }

  /// All occurrences overlapping [from, to), sorted by start.
  List<Occurrence> occurrencesBetween(DateTime from, DateTime to) {
    final out = <Occurrence>[];
    for (final e in _events) {
      out.addAll(expandEvent(e, from, to));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }
}
