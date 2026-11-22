// One-time project setup for Dayline.
//
// Run from the project folder (needs Flutter installed and on your PATH):
//
//     dart tool/setup.dart
//
// It (1) lets Flutter generate the android/ and windows/ runner folders,
// (2) copies Dayline's own native files on top (manifest, widgets, icons),
// (3) patches the Android Gradle file for scheduled notifications,
// (4) runs `flutter pub get`.
//
// Uses only dart:io, so it works the same on Windows, macOS and Linux.
import 'dart:io';

Future<void> main(List<String> args) async {
  final root = Directory.current;
  if (!File(_p(root.path, 'pubspec.yaml')).existsSync() ||
      !File(_p(root.path, 'platform', 'android', 'app', 'src', 'main', 'AndroidManifest.xml')).existsSync()) {
    stderr.writeln('Run this from the dayline project folder (the one that contains pubspec.yaml and platform/).');
    exit(2);
  }

  stdout.writeln('1/4  Generating Android and Windows runners with Flutter ...');
  final tmp = Directory.systemTemp.createTempSync('dayline_create_');
  try {
    final code = await _run(
      'flutter',
      ['create', '--platforms=android,windows', '--org', 'com.dayline', '--project-name', 'dayline', '.'],
      workingDirectory: tmp.path,
    );
    if (code != 0) {
      stderr.writeln('flutter create failed. Is Flutter installed? Run `flutter doctor`.');
      exit(code);
    }
    for (final name in ['android', 'windows']) {
      final target = Directory(_p(root.path, name));
      if (target.existsSync()) {
        stdout.writeln('     $name/ already exists, keeping it.');
      } else {
        _copy(Directory(_p(tmp.path, name)), target);
      }
    }
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }

  stdout.writeln('2/4  Adding Dayline native files (manifest, widgets, icons) ...');
  _copy(Directory(_p(root.path, 'platform', 'android')), Directory(_p(root.path, 'android')));
  _copy(Directory(_p(root.path, 'platform', 'windows')), Directory(_p(root.path, 'windows')));

  stdout.writeln('3/4  Patching Gradle and the Windows window ...');
  _patchGradle(root);
  _patchWindowsMain(root);

  stdout.writeln('4/4  flutter pub get ...');
  final code = await _run('flutter', ['pub', 'get'], workingDirectory: root.path);
  if (code != 0) exit(code);

  stdout.writeln('''

Done. Next:
  flutter run                      run on a connected Android phone / emulator
  flutter run -d windows           run the Windows version
  flutter build apk --release      Android install file (build/app/outputs/flutter-apk/)
  flutter build windows --release  Windows app (build/windows/x64/runner/Release/)
''');
}

String _p(String a, [String? b, String? c, String? d, String? e, String? f, String? g]) {
  return [a, b, c, d, e, f, g].whereType<String>().join(Platform.pathSeparator);
}

Future<int> _run(String exe, List<String> args, {required String workingDirectory}) async {
  final p = await Process.start(
    exe,
    args,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true, // lets Windows find flutter.bat
  );
  return p.exitCode;
}

void _copy(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: false, followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final dest = _p(to.path, name);
    if (entity is Directory) {
      _copy(entity, Directory(dest));
    } else if (entity is File) {
      entity.copySync(dest);
    }
  }
}

void _patchGradle(Directory root) {
  final kts = File(_p(root.path, 'android', 'app', 'build.gradle.kts'));
  final groovy = File(_p(root.path, 'android', 'app', 'build.gradle'));

  if (kts.existsSync()) {
    var s = kts.readAsStringSync();
    final before = s;

    // Java 8+ APIs (java.time) used by the notifications plugin.
    if (!s.contains('isCoreLibraryDesugaringEnabled')) {
      s = s.replaceFirstMapped(
        RegExp(r'compileOptions\s*\{'),
        (m) => '${m[0]}\n        isCoreLibraryDesugaringEnabled = true',
      );
    }
    if (!s.contains('coreLibraryDesugaring(')) {
      s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n';
    }
    if (!s.contains('multiDexEnabled')) {
      s = s.replaceFirstMapped(
        RegExp(r'defaultConfig\s*\{'),
        (m) => '${m[0]}\n        multiDexEnabled = true',
      );
    }
    // The plugins used here need Android 7.0+ and a recent compile SDK.
    s = s.replaceFirst('minSdk = flutter.minSdkVersion', 'minSdk = maxOf(flutter.minSdkVersion, 24)');
    s = s.replaceFirst('compileSdk = flutter.compileSdkVersion', 'compileSdk = maxOf(flutter.compileSdkVersion, 36)');

    if (s != before) kts.writeAsStringSync(s);
    stdout.writeln('     patched android/app/build.gradle.kts');
    return;
  }

  if (groovy.existsSync()) {
    var s = groovy.readAsStringSync();
    final before = s;
    if (!s.contains('coreLibraryDesugaringEnabled')) {
      s = s.replaceFirstMapped(
        RegExp(r'compileOptions\s*\{'),
        (m) => '${m[0]}\n        coreLibraryDesugaringEnabled true',
      );
    }
    if (!s.contains('coreLibraryDesugaring ')) {
      s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n";
    }
    if (!s.contains('multiDexEnabled')) {
      s = s.replaceFirstMapped(
        RegExp(r'defaultConfig\s*\{'),
        (m) => '${m[0]}\n        multiDexEnabled true',
      );
    }
    s = s.replaceFirst('minSdkVersion flutter.minSdkVersion', 'minSdkVersion Math.max(flutter.minSdkVersion, 24)');
    s = s.replaceFirst('compileSdkVersion flutter.compileSdkVersion', 'compileSdkVersion Math.max(flutter.compileSdkVersion, 36)');
    if (s != before) groovy.writeAsStringSync(s);
    stdout.writeln('     patched android/app/build.gradle');
    return;
  }

  stderr.writeln('     WARNING: no android/app/build.gradle(.kts) found, skipped. '
      'See README.md, "Android Gradle settings".');
}

void _patchWindowsMain(Directory root) {
  final f = File(_p(root.path, 'windows', 'runner', 'main.cpp'));
  if (!f.existsSync()) return;
  var s = f.readAsStringSync();
  final before = s;
  s = s.replaceFirst('L"dayline"', 'L"Dayline"');
  // A phone-like window suits the layout; it can still be resized freely.
  s = s.replaceFirst(RegExp(r'Win32Window::Size size\(\s*1280\s*,\s*720\s*\)'), 'Win32Window::Size size(480, 880)');
  if (s != before) f.writeAsStringSync(s);
}
