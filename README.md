# Dayline

A calm, dark-first calendar for **Android and Windows**, written in Flutter (one codebase).

## What is in it

| You asked for | What Dayline does |
|---|---|
| Not a wall of grids | The home screen is a **24-hour day ring**: your day as coloured arcs, a dot for "now", and the next thing in the middle. Under it a one-line **week ribbon** and the day's agenda. The month grid is one tap away (calendar icon) in a bottom sheet. |
| Several reminders per event | In the event editor, **Add reminder** as many times as you like: *1 hour before*, *day before at 18:00*, *2 days before at 09:00*, or fully custom. Doctor's appointment on 23 July = "Day before at 18:00" + "1 hour before". |
| `.ics` import | Menu → **Import .ics file**. Handles repeating lectures (`RRULE`), time zones (`TZID`), all-day events, cancelled entries, deleted single occurrences and the file's own alarms. Re-importing an updated file replaces events instead of duplicating them. You can colour the import and add a default reminder in one step. |
| Dark theme | Dark by default (near-black, OLED friendly). Light and "follow system" are in Settings. |
| Android widgets | **Today** (3×2: date, what is on now / next) and **Upcoming** (4×3: next five events). They keep updating while the app is closed. |
| Iranian calendar, on demand | The **IR** pill (top right of the home screen and the month view) switches it on and off. Off by default. When on, the selected day shows e.g. *11 Dey 1404*, the month grid shows Iranian day numbers, and the editor shows Iranian dates under each date. |
| Converter | Menu → **Date converter**: Gregorian → Iranian and Iranian → Gregorian, with weekday, copy, and "Show in calendar". |
| Monday start, English only, week numbers | Weeks start Monday everywhere (including the date picker). Week numbers (ISO) are **off by default**: Settings → Week numbers. |

Extras: tomorrow preview under today's agenda, swipe left/right to change day, undo after deleting, 12/24-hour switch.

## Build it

You need [Flutter](https://docs.flutter.dev/get-started/install) (3.38 or newer). For Android: Android Studio / the Android SDK. For Windows: Visual Studio with "Desktop development with C++".

```
cd dayline
dart tool/setup.dart          # one time: creates android/ + windows/, adds widgets/manifest/icons
flutter run                   # Android phone or emulator
flutter run -d windows        # Windows
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
flutter build windows --release   # build/windows/x64/runner/Release/  (zip that folder to share it)
```

`dart tool/setup.dart` only needs to be run once. The native Android and Windows files that Dayline adds live in `platform/`; the script copies them over the folders Flutter generates.

If the script cannot patch Gradle on your Flutter version, set these in `android/app/build.gradle.kts` by hand: `isCoreLibraryDesugaringEnabled = true` inside `compileOptions`, `multiDexEnabled = true` inside `defaultConfig`, `minSdk` at least 24, `compileSdk` at least 36, and add `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }`.

## How reminders work

* **Android**: scheduled with the system alarm manager, so they arrive with the app closed and survive a reboot. The next ~45 days are scheduled and refreshed whenever you open the app or change an event. On first launch Android asks for notification permission (Android 13+). If reminders come late, allow the app to ignore battery optimisation.
* **Windows**: desktop apps cannot schedule a notification for a closed app, so Dayline checks its reminders every 20 seconds **while it is running** (minimised is fine) and shows a Windows notification. Reminders that came due in the last 30 minutes while it was closed are shown when you start it.

## Project layout

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

Run the tests with `flutter test`.

Data is stored only on the device (no account, no cloud).
