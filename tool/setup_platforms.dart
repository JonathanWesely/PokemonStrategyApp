/// One-time platform patcher — run AFTER `flutter create .`:
///
///   dart run tool/setup_platforms.dart
///
/// Idempotent (safe to run again anytime). It:
///  1. Adds CAMERA + INTERNET permissions to AndroidManifest.xml
///     (snapshot recognition needs both; INTERNET is required in release
///     builds for the cloud vision API).
///  2. Adds NSCameraUsageDescription + NSPhotoLibraryUsageDescription to
///     the iOS Info.plist.
///  3. Deletes the stock counter-app test/widget_test.dart that
///     `flutter create` drops next to the real suite.
library;

import 'dart:io';

void main() {
  _patchAndroidManifest();
  _patchIosPlist();
  _removeTemplateTest();
  stdout.writeln('setup_platforms: DONE');
}

void _patchAndroidManifest() {
  final file = File('android/app/src/main/AndroidManifest.xml');
  if (!file.existsSync()) {
    stdout.writeln('AndroidManifest.xml not found — run `flutter create .` '
        'first (skipping)');
    return;
  }
  var content = file.readAsStringSync();
  const permissions = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.CAMERA"/>',
  ];
  var changed = false;
  for (final permission in permissions) {
    if (!content.contains(permission)) {
      content = content.replaceFirst(
          '<application', '$permission\n    <application');
      changed = true;
    }
  }
  if (changed) {
    file.writeAsStringSync(content);
    stdout.writeln('AndroidManifest.xml: permissions added — DONE');
  } else {
    stdout.writeln('AndroidManifest.xml: already patched — DONE');
  }
}

void _patchIosPlist() {
  final file = File('ios/Runner/Info.plist');
  if (!file.existsSync()) {
    stdout.writeln('ios/Runner/Info.plist not found (skipping — Android-only '
        'setup is fine on Windows)');
    return;
  }
  var content = file.readAsStringSync();
  const entries = {
    'NSCameraUsageDescription':
        'Takes snapshots of your Pokemon Champions battle screen to '
            'identify the Pokemon on the field.',
    'NSPhotoLibraryUsageDescription':
        'Lets you pick a battle screenshot for recognition.',
  };
  var changed = false;
  entries.forEach((key, description) {
    if (!content.contains(key)) {
      content = content.replaceFirst(
        '</dict>\n</plist>',
        '\t<key>$key</key>\n\t<string>$description</string>\n</dict>\n</plist>',
      );
      changed = true;
    }
  });
  if (changed) {
    file.writeAsStringSync(content);
    stdout.writeln('Info.plist: usage descriptions added — DONE');
  } else {
    stdout.writeln('Info.plist: already patched — DONE');
  }
}

void _removeTemplateTest() {
  final file = File('test/widget_test.dart');
  if (file.existsSync() &&
      file.readAsStringSync().contains('Counter increments smoke test')) {
    file.deleteSync();
    stdout.writeln('Removed template test/widget_test.dart — DONE');
  } else {
    stdout.writeln('No template widget_test.dart to remove — DONE');
  }
}
