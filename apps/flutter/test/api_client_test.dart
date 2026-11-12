import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/api_client.dart';

void main() {
  test('backend URL must be an origin with no credentials or query', () {
    expect(AgentApi.validateEndpoint('https://example.org/').host, 'example.org');
    expect(() => AgentApi.validateEndpoint('https://user:pass@example.org'), throwsA(isA<ApiException>()));
    expect(() => AgentApi.validateEndpoint('https://example.org/api'), throwsA(isA<ApiException>()));
    expect(() => AgentApi.validateEndpoint('https://example.org/?token=x'), throwsA(isA<ApiException>()));
    expect(() => AgentApi.validateEndpoint('ftp://example.org'), throwsA(isA<ApiException>()));
    expect(() => AgentApi.validateEndpoint('http://example.org'), throwsA(isA<ApiException>()));
  });

  test('emulator and simulator origins are allowed during debug only', () {
    expect(AgentApi.validateEndpoint('http://10.0.2.2:8787').host, '10.0.2.2');
    expect(AgentApi.validateEndpoint('http://127.0.0.1:8787').host, '127.0.0.1');
  });

  test('idempotency keys have enough entropy and do not repeat', () {
    final ids = List.generate(30, (_) => AgentApi.createIdempotencyKey());
    expect(ids.toSet().length, ids.length);
    expect(ids.every((id) => id.length == 32), isTrue);
  });

  test('operator token must not be too short', () {
    expect(() => AgentApi('https://example.org', 'bad'), throwsA(isA<ApiException>()));
  });
}
