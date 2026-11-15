import 'dart:io';

/// Run after 'flutter create --platforms=android,ios .'.
/// Keeps HTTP exceptions limited to local development and enables INTERNET.
void main() {
  final mainManifest = File('android/app/src/main/AndroidManifest.xml');
  if (!mainManifest.existsSync()) {
    stderr.writeln('Run flutter create --platforms=android,ios . first.');
    exitCode = 1;
    return;
  }
  var android = mainManifest.readAsStringSync();
  if (!android.contains('android.permission.INTERNET')) {
    android = android.replaceFirst(
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
          '    <uses-permission android:name="android.permission.INTERNET" />',
    );
  }
  // Android 13+ requires an explicit runtime permission for FCM alerts.
  // The app asks only after the user selects Enable notifications.
  if (!android.contains('android.permission.POST_NOTIFICATIONS')) {
    android = android.replaceFirst(
      '<application',
      '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n'
          '    <application',
    );
  }
  // Exclude app data from Android cloud backups: encrypted session state
  // cannot be restored with a different Android Keystore key.
  if (!android.contains('android:allowBackup=')) {
    android = android.replaceFirst(
      '<application',
      '<application android:allowBackup="false"',
    );
  }
  mainManifest.writeAsStringSync(android);

  // The AppAuth PKCE callback returns from the system sign-in window to Flutter.
  final gradleKts = File('android/app/build.gradle.kts');
  if (gradleKts.existsSync()) {
    var kotlin = gradleKts.readAsStringSync();
    if (!kotlin.contains('appAuthRedirectScheme')) {
      kotlin = kotlin.replaceFirst('defaultConfig {',
        'defaultConfig {\n'
        '        manifestPlaceholders.putAll(mapOf("appAuthRedirectScheme" to "com.omiiii.oagent"))');
      gradleKts.writeAsStringSync(kotlin);
    }
  }

  final debugManifest = File('android/app/src/debug/AndroidManifest.xml');
  debugManifest.createSync(recursive: true);
  debugManifest.writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
  <application android:usesCleartextTraffic="true"
      tools:replace="android:usesCleartextTraffic" />
</manifest>
''');

  final plist = File('ios/Runner/Info.plist');
  if (plist.existsSync()) {
    var ios = plist.readAsStringSync();
    if (!ios.contains('<key>CFBundleURLTypes</key>')) {
      ios = ios.replaceFirst(
        '</dict>\n</plist>',
        '  <key>CFBundleURLTypes</key>\n'
            '  <array><dict><key>CFBundleURLSchemes</key>\n'
            '  <array><string>com.omiiii.oagent</string></array>\n'
            '  </dict></array>\n'
            '</dict>\n</plist>',
      );
    }
    if (!ios.contains('<key>NSAppTransportSecurity</key>')) {
      ios = ios.replaceFirst(
        '</dict>\n</plist>',
        '  <key>NSAppTransportSecurity</key>\n'
            '  <dict><key>NSAllowsLocalNetworking</key><true/></dict>\n'
            '</dict>\n</plist>',
      );
    }
    plist.writeAsStringSync(ios);
  }

  stdout.writeln('Platform configuration prepared: Android INTERNET + debug-local HTTP + no backup, iOS local-network exception.');
}
