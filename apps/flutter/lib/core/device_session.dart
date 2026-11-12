import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores an explicitly opted-in development operator token using Android
/// Keystore or Apple Keychain. No AI provider key is ever saved on the phone.
class SavedDeviceSession {
  const SavedDeviceSession({required this.endpoint, required this.token});
  final String endpoint;
  final String token;
}

abstract class SessionStore {
  Future<SavedDeviceSession?> read();
  Future<void> save(SavedDeviceSession session);
  Future<void> clear();
}

class DeviceSessionStore implements SessionStore {
  const DeviceSessionStore();

  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'oagent.session.v1';

  @override
  Future<SavedDeviceSession?> read() async {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null || encoded.isEmpty) return null;
    final json = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    final endpoint = json['endpoint']?.toString() ?? '';
    final token = json['token']?.toString() ?? '';
    if (endpoint.isEmpty || token.isEmpty) return null;
    return SavedDeviceSession(endpoint: endpoint, token: token);
  }

  @override
  Future<void> save(SavedDeviceSession session) async {
    // A single encrypted value avoids partially updated origin/token pairs.
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({'endpoint': session.endpoint, 'token': session.token}),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);
}
