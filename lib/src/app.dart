import 'package:flutter/material.dart';

import 'models/jellyfin_session.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    var session = await _store.read();
    if (session != null && session.baseUrl != JellyfinApi.publicBaseUrl) {
      session = JellyfinSession(
        baseUrl: JellyfinApi.publicBaseUrl,
        token: session.token,
        userId: session.userId,
        userName: session.userName,
        serverName: session.serverName,
      );
      await _store.write(session);
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  Future<void> _connected(JellyfinSession session) async {
    await _store.write(session);
    if (!mounted) return;
    setState(() => _session = session);
  }

  Future<void> _logout() async {
    await _store.clear();
    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NetPobre',
      theme: CasaFlixTheme.dark,
      home: _loading
          ? const _BootScreen()
          : _session == null
          ? ConnectScreen(api: JellyfinApi(), onConnected: _connected)
          : HomeScreen(
              api: JellyfinApi(session: _session),
              session: _session!,
              onLogout: _logout,
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
