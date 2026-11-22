import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'app.dart';
import 'services/notifier.dart';
import 'services/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  final store = Store();
  await store.load();

  final notifier = Notifier(store);
  await notifier.init();

  runApp(DaylineApp(store: store, notifier: notifier));

  // Permissions + scheduling run after the first frame so the app opens instantly.
  unawaited(notifier.start());
}
