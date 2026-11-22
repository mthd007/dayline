import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../services/store.dart';
import '../theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.settings;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Section(
                title: 'Calendar',
                child: Column(
                  children: [
                    _switch(
                      context,
                      title: 'Iranian calendar',
                      subtitle: 'Show Iranian dates next to the day you select. Same as the IR button.',
                      value: s.showIranian,
                      onChanged: (v) => store.updateSettings((x) => x.showIranian = v),
                    ),
                    _switch(
                      context,
                      title: 'Week numbers',
                      subtitle: 'Show ISO week numbers in the week strip and the month view.',
                      value: s.showWeekNumbers,
                      onChanged: (v) => store.updateSettings((x) => x.showWeekNumbers = v),
                    ),
                    _switch(
                      context,
                      title: '24-hour time',
                      subtitle: 'Turn off for AM / PM.',
                      value: s.use24h,
                      onChanged: (v) => store.updateSettings((x) => x.use24h = v),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Weeks start on Monday.', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
              Section(
                title: 'Theme',
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                      ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => store.updateSettings((x) => x.themeMode = v.first),
                  ),
                ),
              ),
              Section(
                title: 'Notifications',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Platform.isWindows
                          ? 'On Windows, reminders appear as system notifications while Dayline is running. '
                              'You can minimise it, but do not quit it. Windows does not let desktop apps '
                              'schedule notifications for a closed app.'
                          : Platform.isAndroid
                              ? 'Reminders are scheduled with the system, so they arrive even when the app is closed. '
                                  'If they come late, allow Dayline to ignore battery optimisation and allow '
                                  '"Alarms & reminders" for the app in system settings.'
                              : 'Reminders are not available on this platform.',
                      style: TextStyle(color: context.muted, fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Send a test notification'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await scope.notifier.showTest();
                        messenger.showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Sent. If you did not see it, check the system notification settings.'
                              : 'Notifications are not available right now.'),
                        ));
                      },
                    ),
                  ],
                ),
              ),
              if (Platform.isAndroid)
                Section(
                  title: 'Widgets',
                  child: Text(
                    'Long-press the home screen, choose Widgets, then Dayline. '
                    'There is a small "Today" widget and a wider "Upcoming" list.',
                    style: TextStyle(color: context.muted, fontSize: 13.5, height: 1.4),
                  ),
                ),
              Section(
                title: 'Data',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${store.events.length} events stored on this device. Nothing is sent anywhere.',
                      style: TextStyle(color: context.muted, fontSize: 13.5),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: Icon(Icons.delete_sweep_outlined, color: Theme.of(context).colorScheme.error),
                      label: Text('Delete all events', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      onPressed: store.events.isEmpty ? null : () => _confirmWipe(context, store),
                    ),
                  ],
                ),
              ),
              Center(
                child: Text('Dayline 1.0', style: TextStyle(color: context.muted, fontSize: 12.5)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _switch(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: context.muted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context, Store store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all events?'),
        content: const Text('Every event and reminder will be removed from this device. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete all', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) store.removeAll();
  }
}
