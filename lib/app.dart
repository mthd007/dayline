import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/notifier.dart';
import 'services/store.dart';
import 'theme.dart';
import 'ui/home_page.dart';

/// Gives every screen access to the store and the notifier.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.store,
    required this.notifier,
    required super.child,
  });

  final Store store;
  final Notifier notifier;

  static AppScope of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

class DaylineApp extends StatefulWidget {
  const DaylineApp({super.key, required this.store, required this.notifier});

  final Store store;
  final Notifier notifier;

  @override
  State<DaylineApp> createState() => _DaylineAppState();
}

class _DaylineAppState extends State<DaylineApp> {
  @override
  void initState() {
    super.initState();
    // Tapping a reminder jumps to that day.
    widget.notifier.onOpenDay = (day) => widget.store.select(day);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: widget.store,
      notifier: widget.notifier,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => MaterialApp(
          title: 'Dayline',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: widget.store.settings.themeMode,
          // en_GB: English with Monday as the first day of the week in the date picker.
          locale: const Locale('en', 'GB'),
          supportedLocales: const [Locale('en', 'GB')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            // On wide windows (Windows desktop) keep the app a comfortable column.
            return ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: child,
                ),
              ),
            );
          },
          home: const HomePage(),
        ),
      ),
    );
  }
}
