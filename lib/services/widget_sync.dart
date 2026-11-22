import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'format.dart';
import 'jalali.dart';
import 'store.dart';

/// Sends the next two weeks of events to the Android home-screen widgets.
/// The native widgets keep the data and re-render themselves (also while the
/// app is closed), so "today" and "next up" stay correct without opening the app.
class WidgetSync {
  WidgetSync._();

  static const _channel = MethodChannel('dayline/widgets');

  static String dayKey(DateTime d) => '${d.year}-${Fmt.two(d.month)}-${Fmt.two(d.day)}';

  static Future<void> push(Store store) async {
    if (!Platform.isAndroid) return;
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final to = DateTime(now.year, now.month, now.day + 14);

      final occs = store.occurrencesBetween(from, to).take(250);
      final events = occs
          .map((o) => {
                't': o.event.title,
                's': o.start.millisecondsSinceEpoch,
                'e': o.end.millisecondsSinceEpoch,
                'a': o.allDay,
                'c': Pal.event(o.event.color).toARGB32(),
                'l': o.event.location,
              })
          .toList();

      final iran = <String, String>{};
      if (store.settings.showIranian) {
        for (var i = 0; i < 14; i++) {
          final d = DateTime(from.year, from.month, from.day + i);
          final j = Jalali.tryFromGregorian(d);
          if (j != null) iran[dayKey(d)] = j.format(withYear: false);
        }
      }

      await _channel.invokeMethod<void>('update', {
        'events': jsonEncode(events),
        'use24h': store.settings.use24h,
        'iran': jsonEncode(iran),
      });
    } on MissingPluginException {
      // Native side not present (e.g. running in a test).
    } catch (e) {
      debugPrint('Widget sync failed: $e');
    }
  }
}
