import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/event.dart';
import 'format.dart';
import 'store.dart';
import 'widget_sync.dart';

class _Due {
  const _Due(this.fire, this.occ, this.reminder);
  final DateTime fire;
  final Occurrence occ;
  final Reminder reminder;

  String get key => '${occ.key}|${reminder.key}';
}

/// Turns every event's reminders into real notifications.
///
///  * Android: scheduled with the system alarm manager, so they fire even when
///    the app is closed. The next ~45 days are scheduled and refreshed every
///    time the app opens or events change.
///  * Windows: the OS toast API has no scheduling for desktop apps, so Dayline
///    checks its reminder list every 20 seconds while it is running (it can be
///    minimised) and shows a toast when one is due.
class Notifier with WidgetsBindingObserver {
  Notifier(this._store);

  final Store _store;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// Called when the user taps a notification; receives the occurrence's day.
  void Function(DateTime day)? onOpenDay;

  static const _kFired = 'dayline.fired.v1';
  static const int _androidLimit = 400;

  // `final`, not `const`: the Windows details class is not guaranteed to have a const constructor.
  static final NotificationDetails _details = NotificationDetails(
    android: const AndroidNotificationDetails(
      'event_reminders',
      'Event reminders',
      channelDescription: 'Reminders for your calendar events',
      importance: Importance.high,
      priority: Priority.high,
    ),
    windows: WindowsNotificationDetails(),
  );

  bool _ready = false;
  String? _initError;
  String? _lastError;
  bool _busy = false;
  bool _again = false;
  Timer? _debounce;
  Timer? _winTimer;
  List<_Due> _due = [];
  final Map<String, int> _fired = {};
  int _winId = 1000000;

  static bool get supported => Platform.isAndroid || Platform.isWindows;

  Future<void> init() async {
    if (!supported) return;
    final settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_dayline'),
      windows: WindowsInitializationSettings(
        appName: 'Dayline',
        appUserModelId: 'Dayline.Calendar.Reminders',
        guid: '8f4c2b1e-3d6a-4e57-9b0c-5a1d7e2f9c34',
      ),
    );
    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onResponse,
      );
      _ready = true;
    } catch (e) {
      _initError = '$e';
      debugPrint('Notifications unavailable: $e');
    }
  }

  void _onResponse(NotificationResponse response) {
    final ms = int.tryParse(response.payload ?? '');
    if (ms == null) return;
    onOpenDay?.call(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  /// Ask for permission (Android 13+), then keep reminders and widgets in sync with the store.
  Future<void> start() async {
    if (Platform.isAndroid && _ready) {
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      try {
        await android?.requestNotificationsPermission();
      } catch (e) {
        debugPrint('Notification permission request failed: $e');
      }
      try {
        await android?.requestExactAlarmsPermission();
      } catch (e) {
        debugPrint('Exact alarm permission request failed: $e');
      }
    }
    await _loadFired();
    WidgetsBinding.instance.addObserver(this);
    _store.dataRevision.addListener(_scheduleSoon);
    _scheduleSoon();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleSoon();
  }

  void _scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _refresh);
  }

  /// Shows a notification right now. Returns null on success, otherwise the reason it failed.
  Future<String?> showTest() async {
    if (!_ready) return 'Notifications could not start: ${_initError ?? 'unknown reason'}';
    try {
      await _plugin.show(
        id: 999999,
        title: 'Dayline',
        body: 'Reminders are working.',
        notificationDetails: _details,
      );
      return null;
    } catch (e) {
      debugPrint('Test notification failed: $e');
      return '$e';
    }
  }

  /// Schedules a notification through the same alarm path real reminders use.
  /// Returns null on success, otherwise the reason it failed.
  Future<String?> scheduleTest({int seconds = 60}) async {
    if (!_ready) return 'Notifications could not start: ${_initError ?? 'unknown reason'}';
    final u = DateTime.now().toUtc().add(Duration(seconds: seconds));
    final when = tz.TZDateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second);
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id: 999998,
          title: 'Dayline',
          body: 'Scheduled reminders are working.',
          scheduledDate: when,
          notificationDetails: _details,
          androidScheduleMode: mode,
        );
    try {
      try {
        await go(AndroidScheduleMode.exactAllowWhileIdle);
      } on PlatformException {
        await go(AndroidScheduleMode.inexactAllowWhileIdle);
      }
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Plain-language state of the reminder system, for the "Check reminders" screen.
  Future<String> diagnose() async {
    final b = StringBuffer();
    if (!_ready) {
      b.writeln('Notification service: NOT running (${_initError ?? 'unknown reason'})');
    } else {
      b.writeln('Notification service: running');
      if (Platform.isAndroid) {
        final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        try {
          b.writeln('Notifications allowed: ${await a?.areNotificationsEnabled()}');
        } catch (e) {
          b.writeln('Notifications allowed: unknown ($e)');
        }
        try {
          b.writeln('Exact alarms allowed: ${await a?.canScheduleExactNotifications()}');
        } catch (e) {
          b.writeln('Exact alarms allowed: unknown ($e)');
        }
        try {
          final pending = await _plugin.pendingNotificationRequests();
          b.writeln('Reminders waiting to fire: ${pending.where((p) => p.id >= 1000000).length}');
        } catch (e) {
          b.writeln('Reminders waiting to fire: unknown ($e)');
        }
      }
    }
    b.writeln('Events stored: ${_store.events.length}');
    b.writeln('Events with reminders: ${_store.events.where((e) => e.reminders.isNotEmpty).length}');
    if (_lastError != null) b.writeln('Last problem: $_lastError');
    return b.toString().trim();
  }

  // ---- refresh -----------------------------------------------------------

  Future<void> _refresh() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _doRefresh();
      } while (_again);
    } finally {
      _busy = false;
    }
  }

  Future<void> _doRefresh() async {
    await WidgetSync.push(_store);
    if (!_ready) return;

    final now = DateTime.now();
    // On Windows, also catch reminders that came due while the app was closed.
    final lookback = Platform.isWindows ? now.subtract(const Duration(minutes: 30)) : now;
    final horizon = DateTime(now.year, now.month, now.day + 45);

    final occs = _store.occurrencesBetween(
      lookback,
      DateTime(horizon.year, horizon.month, horizon.day + 40),
    );

    final due = <_Due>[];
    for (final o in occs) {
      for (final r in o.event.reminders) {
        final fire = r.fireTime(o.start);
        if (fire.isBefore(lookback) || fire.isAfter(horizon)) continue;
        due.add(_Due(fire, o, r));
      }
    }
    due.sort((a, b) => a.fire.compareTo(b.fire));

    if (Platform.isAndroid) {
      await _scheduleAndroid(due.take(_androidLimit).toList());
    } else if (Platform.isWindows) {
      _armWindows(due);
    }
  }

  // ---- text --------------------------------------------------------------

  (String, String) _text(_Due d) {
    final occ = d.occ;
    final e = occ.event;
    final day = Fmt.dayLabel(Fmt.dateOnly(occ.start), Fmt.dateOnly(d.fire));
    final when = occ.allDay ? 'All day · $day' : '$day at ${Fmt.time(occ.start)}';
    final parts = <String>[
      d.reminder.leadText,
      when,
      e.location,
    ].where((s) => s.trim().isNotEmpty).toList();
    return (e.title, parts.join(' · '));
  }

  // ---- Android -----------------------------------------------------------

  /// Same reminder -> same id on every refresh (FNV-1a hash of event + occurrence + reminder).
  /// That way a refresh replaces pending reminders in place and never touches
  /// notifications that are already sitting in the tray.
  static int _stableId(String key) {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return 1000000 + h % 1000000000;
  }

  Future<void> _scheduleAndroid(List<_Due> due) async {
    var mode = AndroidScheduleMode.exactAllowWhileIdle;

    Future<void> scheduleOne(_Due d, int id) async {
      final text = _text(d);
      final u = d.fire.toUtc();
      final when = tz.TZDateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second);
      Future<void> go() => _plugin.zonedSchedule(
            id: id,
            title: text.$1,
            body: text.$2,
            scheduledDate: when,
            notificationDetails: _details,
            androidScheduleMode: mode,
            payload: '${d.occ.start.millisecondsSinceEpoch}',
          );
      try {
        await go();
      } on PlatformException {
        // Exact alarms not allowed: fall back to inexact ones (may be a few minutes late).
        if (mode != AndroidScheduleMode.exactAllowWhileIdle) rethrow;
        mode = AndroidScheduleMode.inexactAllowWhileIdle;
        await go();
      }
    }

    try {
      final wanted = <int>{};
      for (final d in due) {
        // A reminder that is already due (or due this second) cannot be scheduled.
        if (!d.fire.isAfter(DateTime.now().add(const Duration(seconds: 2)))) continue;
        final id = _stableId(d.key);
        if (!wanted.add(id)) continue; // astronomically unlikely hash clash: skip the twin
        try {
          await scheduleOne(d, id);
        } catch (e) {
          wanted.remove(id);
          _lastError = '$e';
          debugPrint('Skipping one reminder: $e');
        }
      }

      // Drop pending reminders whose event or reminder no longer exists
      // (ids below 1000000 are the test notifications and are left alone).
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= 1000000 && !wanted.contains(p.id)) await _plugin.cancel(id: p.id);
      }
    } catch (e) {
      _lastError = '$e';
      debugPrint('Scheduling reminders failed: $e');
    }
  }

  // ---- Windows -----------------------------------------------------------

  void _armWindows(List<_Due> due) {
    _due = due;
    _winTimer?.cancel();
    _winTimer = Timer.periodic(const Duration(seconds: 20), (_) => _tickWindows());
    _tickWindows();
  }

  Future<void> _tickWindows() async {
    final now = DateTime.now();
    var changed = false;
    for (final d in _due) {
      if (d.fire.isAfter(now)) break;
      if (_fired.containsKey(d.key)) continue;
      _fired[d.key] = d.fire.millisecondsSinceEpoch;
      changed = true;
      if (d.occ.end.isBefore(now)) continue; // event already over: no point nagging
      final text = _text(d);
      try {
        await _plugin.show(
          id: _winId++,
          title: text.$1,
          body: text.$2,
          notificationDetails: _details,
          payload: '${d.occ.start.millisecondsSinceEpoch}',
        );
      } catch (e) {
        debugPrint('Toast failed: $e');
      }
    }
    if (changed) await _saveFired();
  }

  Future<void> _loadFired() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kFired);
      if (raw == null) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      map.forEach((k, v) {
        if (v is int && v > cutoff) _fired[k] = v;
      });
    } catch (e) {
      debugPrint('Could not read fired reminders: $e');
    }
  }

  Future<void> _saveFired() async {
    try {
      final p = await SharedPreferences.getInstance();
      final cutoff = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      _fired.removeWhere((_, v) => v < cutoff);
      await p.setString(_kFired, jsonEncode(_fired));
    } catch (e) {
      debugPrint('Could not save fired reminders: $e');
    }
  }
}
