import 'package:flutter_test/flutter_test.dart';
import '../tool/prepare_platforms.dart';

void main() {
  test('generated Android manifest removes AppAuth-breaking empty task affinity', () {
    const generated = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application>
    <activity android:name=".MainActivity"
      android:exported="true"
      android:launchMode="singleTop"
      android:taskAffinity=""
      android:theme="@style/LaunchTheme">
    </activity>
  </application>
</manifest>
''';
    final prepared = nativeOAuthAndroidManifest(generated);
    expect(prepared, isNot(contains('android:taskAffinity=""')));
    expect(prepared, contains('android:launchMode="singleTop"'));
    expect(prepared, contains('android:exported="true"'));
    expect(prepared, contains('android:theme="@style/LaunchTheme"'));
    expect(nativeOAuthAndroidManifest(prepared), prepared);
  });

  test('do not modify custom task affinity or unrelated manifest fields', () {
    const existing = '<activity android:taskAffinity="com.example.private" '
      'android:exported="true" />';
    expect(nativeOAuthAndroidManifest(existing), existing);
  });
}
