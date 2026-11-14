import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/ui/studio.dart';

void main() {
  test('Secure OIDC command center never accepts an HTTP or credential URL', () {
    expect(secureSaasOrigin('http://127.0.0.1:8791'), isNull);
    expect(secureSaasOrigin('https://user:password@example.com'), isNull);
    expect(secureSaasOrigin('javascript:alert(1)'), isNull);
    expect(secureSaasOrigin(''), isNull);
    final target = secureSaasOrigin(
      'https://laptop.tailnet.ts.net/agent?token=must-not-share#session');
    expect(target.toString(), 'https://laptop.tailnet.ts.net/');
    expect(target!.query, isEmpty);
    expect(target.fragment, isEmpty);
    expect(target.userInfo, isEmpty);
  });
}
