import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayline/app.dart';
import 'package:dayline/services/notifier.dart';
import 'package:dayline/services/store.dart';

void main() {
  testWidgets('home screen shows today and the new-event button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.load();
    final notifier = Notifier(store);

    await tester.pumpWidget(DaylineApp(store: store, notifier: notifier));
    await tester.pump();

    expect(find.text('Today'), findsWidgets);
    expect(find.text('New event'), findsOneWidget);
    expect(find.text('Free day'), findsOneWidget);

    // Switching the Iranian calendar on adds the Iranian date under the header.
    expect(store.settings.showIranian, isFalse);
    await tester.tap(find.text('IR'));
    await tester.pump();
    expect(store.settings.showIranian, isTrue);

    await tester.pumpWidget(const SizedBox()); // dispose the tree so timers are cancelled
  });
}
