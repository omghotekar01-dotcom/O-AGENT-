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
  static const _urlKey = 'oagent.backend.origin.v1';
  static const _tokenKey = 'oagent.operator.token.v1';

  @override
  Future<SavedDeviceSession?> read() async {
    final origin = await _storage.read(key: _urlKey);
    final token = await _storage.read(key: _tokenKey);
    if (origin == null || origin.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return SavedDeviceSession(endpoint: origin, token: token);
  }

  @override
  Future<void> save(SavedDeviceSession session) async {
    // Write token first so incomplete writes cannot yield an old token tied
    // to a new backend. Both fields are device-protected, not app preferences.
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(key: _urlKey, value: session.endpoint);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _tokenKey);
  }
}
