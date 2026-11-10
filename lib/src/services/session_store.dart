import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/jellyfin_session.dart';

class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'casaflix.session.v1';
  static const _profilesKey = 'netpobre.profiles.v1';
  final FlutterSecureStorage _storage;

  Future<JellyfinSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return JellyfinSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      await clear();
      return null;
    }
  }

  Future<void> write(JellyfinSession session) => _writeSession(session);

  Future<void> _writeSession(JellyfinSession session) async {
    final profiles = await readAll();
    final updated = [
      session,
      ...profiles.where(
        (profile) =>
            profile.userId != session.userId ||
            profile.baseUrl != session.baseUrl,
      ),
    ];
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
    await _storage.write(
      key: _profilesKey,
      value: jsonEncode(updated.map((profile) => profile.toJson()).toList()),
    );
  }

  Future<List<JellyfinSession>> readAll() async {
    final raw = await _storage.read(key: _profilesKey);
    if (raw == null || raw.isEmpty) {
      final active = await _readActive();
      return active == null ? const [] : [active];
    }
    try {
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(JellyfinSession.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<JellyfinSession?> _readActive() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    return JellyfinSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setActive(JellyfinSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<void> remove(JellyfinSession session) async {
    final profiles = await readAll();
    final updated = profiles
        .where(
          (profile) =>
              profile.userId != session.userId ||
              profile.baseUrl != session.baseUrl,
        )
        .toList();
    await _storage.write(
      key: _profilesKey,
      value: jsonEncode(updated.map((profile) => profile.toJson()).toList()),
    );
    await _storage.delete(key: _key);
  }

  Future<void> clear() => _storage.delete(key: _key);
}
