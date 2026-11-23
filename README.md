# dayline

calendar for **Android and Windows**, written in Flutter (one codebase) for those who don't like the cluttered UI of google/samsung calendar


## how reminders work

* **Android**: scheduled with the system alarm manager, so they arrive with the app closed and survive a reboot. The next ~45 days are scheduled and refreshed whenever you open the app or change an event. On first launch Android asks for notification permission (Android 13+). If reminders come late, allow the app to ignore battery optimisation.
* **Windows**: desktop apps cannot schedule a notification for a closed app, so Dayline checks its reminders every 20 seconds **while it is running** (minimised is fine) and shows a Windows notification. Reminders that came due in the last 30 minutes while it was closed are shown when you start it.

## project layout

```
lib/
  main.dart, app.dart, theme.dart
  models/event.dart            event, reminder, repeat rule
  services/
    jalali.dart                Iranian calendar conversion
    ics.dart                   .ics (iCalendar) reader
    recurrence.dart            expands repeating events
    store.dart                 events + settings, saved on the device
    notifier.dart              reminders (Android scheduled, Windows live)
    widget_sync.dart           feeds the Android widgets
  ui/                          home, month sheet, editor, reminder picker, converter, settings, import
platform/                      native Android (manifest, widgets, icons) and Windows (icon) files
tool/setup.dart                one-time project setup
test/                          unit tests (dart / flutter test)
```



data is stored only on the device (no account, no cloud).
