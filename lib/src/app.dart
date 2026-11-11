import 'package:flutter/material.dart';

import 'models/jellyfin_session.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/jellyfin_api.dart';
import 'services/device_capabilities.dart';
import 'services/session_store.dart';
import 'theme.dart';
import 'widgets/tv_navigation.dart';

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
  bool _isTelevision = false;
  String? _televisionConnectionMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    final minimumSplash = Future<void>.delayed(
      const Duration(milliseconds: 2300),
    );
    final isTelevision = await DeviceCapabilities.isTelevision();
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
    } else if (isTelevision) {
      try {
        session = await JellyfinApi().authenticateLocalTelevision();
        await _store.write(session);
      } catch (_) {
        _televisionConnectionMessage =
            'A TV não encontrou o servidor na rede de casa.';
      }
    }
    await minimumSplash;
    if (!mounted) return;
    setState(() {
      _session = session;
      _isTelevision = isTelevision;
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
      home: TvMode(
        enabled: _isTelevision,
        child: _loading
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
            ? ConnectScreen(
                api: JellyfinApi(),
                onConnected: _connected,
                isTelevision: _isTelevision,
                initialMessage: _televisionConnectionMessage,
              )
            : HomeScreen(
                api: JellyfinApi(session: _session),
                session: _session!,
                onLogout: _logout,
                onSwitchProfile: () => setState(() => _choosingProfile = true),
                isTelevision: _isTelevision,
              ),
      ),
    );
  }
}

class _BootScreen extends StatefulWidget {
  const _BootScreen();

  @override
  State<_BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<_BootScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _idle;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _intro.forward().whenComplete(() {
      if (mounted && !_reduceMotion) _idle.repeat(reverse: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _intro.value = 1;
      _idle.stop();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CasaFlixColors.night,
      body: AnimatedBuilder(
        animation: Listenable.merge([_intro, _idle]),
        builder: (context, _) {
          final intro = _intro.value;
          final mascotOpacity = Curves.easeOut.transform(
            const Interval(0, .24).transform(intro),
          );
          final mascotScale = TweenSequence<double>([
            TweenSequenceItem(
              tween: Tween(
                begin: .62,
                end: 1.08,
              ).chain(CurveTween(curve: Curves.easeOutBack)),
              weight: 68,
            ),
            TweenSequenceItem(tween: Tween(begin: 1.08, end: 1), weight: 32),
          ]).transform(const Interval(0, .62).transform(intro));
          final nameProgress = Curves.easeOutCubic.transform(
            const Interval(.38, .72).transform(intro),
          );
          final loadingProgress = Curves.easeOut.transform(
            const Interval(.68, 1).transform(intro),
          );
          final breathing = 1 + (_idle.value * .018);

          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 230,
                      height: 230,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: mascotOpacity * .46,
                            child: Transform.scale(
                              scale: .72 + (_idle.value * .08),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Color(0xAAF4B860),
                                      Color(0x0058C7F3),
                                    ],
                                  ),
                                ),
                                child: SizedBox.square(dimension: 218),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: mascotOpacity,
                            child: Transform.rotate(
                              angle:
                                  (1 - intro).clamp(0.0, 1.0).toDouble() *
                                  -.045,
                              child: Transform.scale(
                                scale: mascotScale * breathing,
                                child: Image.asset(
                                  'assets/branding/netpobre-mascot-splash.png',
                                  width: 205,
                                  height: 205,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, 18 * (1 - nameProgress)),
                      child: Opacity(
                        opacity: nameProgress,
                        child: const Text(
                          'NetPobre',
                          style: TextStyle(
                            color: CasaFlixColors.ivory,
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    Opacity(
                      opacity: loadingProgress,
                      child: SizedBox(
                        width: 132,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            backgroundColor: CasaFlixColors.ink,
                            color: CasaFlixColors.amber,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Opacity(
                      opacity: loadingProgress,
                      child: const Text(
                        'Ligando a TV de casa…',
                        style: TextStyle(
                          color: CasaFlixColors.muted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 34,
                child: Opacity(
                  opacity: loadingProgress * .7,
                  child: const Text(
                    'Filme bom. Orçamento honesto.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: CasaFlixColors.muted, fontSize: 12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
