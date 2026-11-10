import 'package:flutter/material.dart';

import 'models/jellyfin_session.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/jellyfin_api.dart';
import 'services/session_store.dart';
import 'theme.dart';

class CasaFlixApp extends StatefulWidget {
  const CasaFlixApp({super.key});

  @override
  State<CasaFlixApp> createState() => _CasaFlixAppState();
}

class _CasaFlixAppState extends State<CasaFlixApp> {
  final _store = SessionStore();
  JellyfinSession? _session;
  bool _loading = true;
  bool _choosingProfile = false;
  List<JellyfinSession> _profiles = const [];

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    var session = await _store.read();
    final profiles = await _store.readAll();
    if (session != null) {
      try {
        final preferredBaseUrl = await JellyfinApi().preferredBaseUrl();
        session = JellyfinSession(
          baseUrl: preferredBaseUrl,
          token: session.token,
          userId: session.userId,
          userName: session.userName,
          serverName: session.serverName,
        );
      } catch (_) {
        // The home screen provides retry and server switching when offline.
      }
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _profiles = profiles;
      _loading = false;
    });
  }

  Future<void> _connected(JellyfinSession session) async {
    await _store.write(session);
    if (!mounted) return;
    final profiles = await _store.readAll();
    setState(() {
      _session = session;
      _profiles = profiles;
      _choosingProfile = false;
    });
  }

  Future<void> _logout() async {
    final session = _session;
    if (session != null) await _store.remove(session);
    final profiles = await _store.readAll();
    if (!mounted) return;
    setState(() {
      _session = null;
      _profiles = profiles;
      _choosingProfile = profiles.isNotEmpty;
    });
  }

  Future<void> _selectProfile(JellyfinSession session) async {
    await _store.setActive(session);
    if (!mounted) return;
    setState(() {
      _session = session;
      _choosingProfile = false;
    });
  }

  Future<void> _removeProfile(JellyfinSession session) async {
    await _store.remove(session);
    final profiles = await _store.readAll();
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NetPobre',
      theme: CasaFlixTheme.dark,
      home: _loading
          ? const _BootScreen()
          : _choosingProfile
          ? ProfileScreen(
              profiles: _profiles,
              onSelected: _selectProfile,
              onAdd: () => setState(() {
                _session = null;
                _choosingProfile = false;
              }),
              onRemove: _removeProfile,
            )
          : _session == null
          ? ConnectScreen(api: JellyfinApi(), onConnected: _connected)
          : HomeScreen(
              api: JellyfinApi(session: _session),
              session: _session!,
              onLogout: _logout,
              onSwitchProfile: () => setState(() => _choosingProfile = true),
            ),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CasaFlixMark(size: 58),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
