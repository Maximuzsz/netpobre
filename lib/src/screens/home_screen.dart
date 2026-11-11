import 'package:flutter/material.dart';

import '../models/jellyfin_session.dart';
import '../models/media_item.dart';
import '../services/jellyfin_api.dart';
import '../theme.dart';
import '../widgets/app_update_dialog.dart';
import '../widgets/tv_navigation.dart';
import 'media_details_screen.dart';
import 'downloads_screen.dart';
import 'my_list_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
    required this.onSwitchProfile,
    this.isTelevision = false,
  });

  final JellyfinApi api;
  final JellyfinSession session;
  final VoidCallback onLogout;
  final VoidCallback onSwitchProfile;
  final bool isTelevision;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _content;
  final _myListKey = GlobalKey<MyListScreenState>();
  final _downloadsKey = GlobalKey<DownloadsScreenState>();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  Future<_HomeData> _load() async {
    final results = await Future.wait<dynamic>([
      widget.api.resume(),
      widget.api.nextUp(),
      widget.api.recommendations(),
    ]);
    final resume = results[0] as List<MediaItem>;
    final nextUp = results[1] as List<MediaItem>;
    final recommendations = results[2] as List<RecommendationShelf>;
    final views = await widget.api.views();
    final shelves = <_Shelf>[];
    for (final view in views) {
      final items = await widget.api.latest(view.id);
      if (items.isNotEmpty) shelves.add(_Shelf(view.name, items));
    }
    shelves.addAll(
      recommendations.map((group) => _Shelf(group.title, group.items)),
    );
    return _HomeData(resume: resume, nextUp: nextUp, shelves: shelves);
  }

  void _refresh() => setState(() => _content = _load());

  Future<void> _open(MediaItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailsScreen(api: widget.api, item: item),
      ),
    );
    _refresh();
  }

  Future<void> _refreshPortugueseTitles() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.refreshPortugueseMetadata();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Atualização iniciada. Os títulos em português aparecerão aos poucos.',
          ),
        ),
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is JellyfinException
                ? error.toString()
                : 'Não foi possível atualizar os títulos.',
          ),
        ),
      );
    }
  }

  Future<void> _prepareServerMedia() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tasks = await widget.api.runMediaPreparationTasks();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tasks.isEmpty
                ? 'Os recursos de mídia já estão sendo preparados.'
                : 'Preparação iniciada: ${tasks.join(', ')}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Use uma conta administradora para preparar o servidor.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      index: _tab,
      children: [
        _buildHome(),
        SearchScreen(api: widget.api),
        MyListScreen(key: _myListKey, api: widget.api),
        DownloadsScreen(key: _downloadsKey),
      ],
    );
    if (widget.isTelevision) {
      return Scaffold(
        body: SafeArea(
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Row(
              children: [
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 196,
                  selectedIndex: _tab,
                  onDestinationSelected: _selectTab,
                  leading: const Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 28),
                    child: CasaFlixMark(size: 30, showName: false),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: Text('Início'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.search_rounded),
                      label: Text('Buscar'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.bookmark_border_rounded),
                      selectedIcon: Icon(Icons.bookmark_rounded),
                      label: Text('Minha Lista'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.download_outlined),
                      selectedIcon: Icon(Icons.download_rounded),
                      label: Text('Downloads'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: pages,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Buscar',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded),
            label: 'Minha Lista',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_rounded),
            label: 'Downloads',
          ),
        ],
      ),
    );
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    if (index == 2) _myListKey.currentState?.refresh();
    if (index == 3) _downloadsKey.currentState?.refresh();
  }

  Widget _buildHome() {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<_HomeData>(
        future: _content,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint('NetPobre: falha ao carregar: ${snapshot.error}');
            return _HomeError(
              onRetry: _refresh,
              onLogout: widget.onLogout,
              message: snapshot.error is JellyfinException
                  ? snapshot.error.toString()
                  : 'Não foi possível carregar o catálogo.',
            );
          }
          final data = snapshot.data ?? const _HomeData();
          final shelves = data.shelves;
          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              await _content;
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    session: widget.session,
                    onLogout: widget.onLogout,
                    onSwitchProfile: widget.onSwitchProfile,
                    onPrepareServer: _prepareServerMedia,
                    onRefreshTitles: _refreshPortugueseTitles,
                  ),
                ),
                if (shelves.isEmpty &&
                    data.resume.isEmpty &&
                    data.nextUp.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text('Sua biblioteca ainda está vazia.'),
                    ),
                  )
                else ...[
                  if (shelves.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _HeroFeature(
                        api: widget.api,
                        item: shelves.first.items.first,
                        onTap: _open,
                      ),
                    ),
                  if (data.resume.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _ContinueWatchingShelf(
                        api: widget.api,
                        items: data.resume,
                        onTap: _open,
                      ),
                    ),
                  if (data.nextUp.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _MediaShelf(
                        api: widget.api,
                        shelf: _Shelf('A seguir', data.nextUp),
                        onTap: _open,
                      ),
                    ),
                  for (final shelf in shelves)
                    SliverToBoxAdapter(
                      child: _MediaShelf(
                        api: widget.api,
                        shelf: shelf,
                        onTap: _open,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 48)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.onLogout,
    required this.onRefreshTitles,
    required this.onSwitchProfile,
    required this.onPrepareServer,
  });
  final JellyfinSession session;
  final VoidCallback onLogout;
  final Future<void> Function() onRefreshTitles;
  final VoidCallback onSwitchProfile;
  final Future<void> Function() onPrepareServer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 12),
      child: Row(
        children: [
          const CasaFlixMark(size: 32),
          const Spacer(),
          Text(
            session.userName,
            style: const TextStyle(color: CasaFlixColors.muted),
          ),
          PopupMenuButton<String>(
            tooltip: 'Conta',
            onSelected: (value) {
              if (value == 'logout') onLogout();
              if (value == 'refresh_titles') onRefreshTitles();
              if (value == 'switch_profile') onSwitchProfile();
              if (value == 'prepare_server') onPrepareServer();
              if (value == 'check_updates') AppUpdateDialog.show(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'switch_profile',
                child: ListTile(
                  leading: Icon(Icons.switch_account_rounded),
                  title: Text('Trocar perfil'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'prepare_server',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_motion_rounded),
                  title: Text('Preparar aberturas e miniaturas'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'refresh_titles',
                child: ListTile(
                  leading: Icon(Icons.translate_rounded),
                  title: Text('Atualizar títulos em português'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'check_updates',
                child: ListTile(
                  leading: Icon(Icons.system_update_alt_rounded),
                  title: Text('Verificar atualizações'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Sair'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
    );
  }
}

class _HeroFeature extends StatelessWidget {
  const _HeroFeature({
    required this.api,
    required this.item,
    required this.onTap,
  });
  final JellyfinApi api;
  final MediaItem item;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusCard(
      autofocus: true,
      borderRadius: BorderRadius.circular(24),
      onPressed: () => onTap(item),
      child: Container(
        height: 340,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 26),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CasaFlixColors.deepSea,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              api.imageUrl(item, backdrop: true, width: 1200),
              headers: api.authHeaders,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: CasaFlixColors.deepSea),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xEE08111D)],
                  stops: [.25, 1],
                ),
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 22,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.seriesName ?? item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                              ),
                        ),
                        if (item.seriesName != null)
                          Text(
                            item.name,
                            style: const TextStyle(color: CasaFlixColors.muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const CircleAvatar(
                    radius: 27,
                    backgroundColor: CasaFlixColors.amber,
                    foregroundColor: CasaFlixColors.night,
                    child: Icon(Icons.play_arrow_rounded, size: 34),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaShelf extends StatelessWidget {
  const _MediaShelf({
    required this.api,
    required this.shelf,
    required this.onTap,
  });
  final JellyfinApi api;
  final _Shelf shelf;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              shelf.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 242,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: shelf.items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = shelf.items[index];
                return SizedBox(
                  width: 132,
                  child: TvFocusCard(
                    borderRadius: BorderRadius.circular(14),
                    onPressed: () => onTap(item),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(
                              api.imageUrl(item, width: 400),
                              headers: api.authHeaders,
                              width: 132,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: CasaFlixColors.deepSea,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.movie_outlined,
                                      size: 36,
                                      color: CasaFlixColors.muted,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          item.seriesName ?? item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({
    required this.onRetry,
    required this.onLogout,
    required this.message,
  });
  final VoidCallback onRetry;
  final VoidCallback onLogout;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: CasaFlixColors.muted,
            ),
            const SizedBox(height: 18),
            Text(
              'Servidor fora de alcance',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CasaFlixColors.muted),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
            TextButton(
              onPressed: onLogout,
              child: const Text('Trocar servidor'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueWatchingShelf extends StatelessWidget {
  const _ContinueWatchingShelf({
    required this.api,
    required this.items,
    required this.onTap,
  });

  final JellyfinApi api;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Continuar assistindo',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = items[index];
                return SizedBox(
                  width: 240,
                  child: TvFocusCard(
                    borderRadius: BorderRadius.circular(16),
                    onPressed: () => onTap(item),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  api.imageUrl(
                                    item,
                                    backdrop: true,
                                    width: 620,
                                  ),
                                  headers: api.authHeaders,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const ColoredBox(
                                    color: CasaFlixColors.deepSea,
                                  ),
                                ),
                              ),
                              const Center(
                                child: CircleAvatar(
                                  backgroundColor: Color(0xDDF4B860),
                                  foregroundColor: CasaFlixColors.night,
                                  child: Icon(Icons.play_arrow_rounded),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: LinearProgressIndicator(
                                  value: item.progress,
                                  minHeight: 4,
                                  backgroundColor: Colors.white24,
                                  color: CasaFlixColors.sky,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.seriesName ?? item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Shelf {
  const _Shelf(this.title, this.items);
  final String title;
  final List<MediaItem> items;
}

class _HomeData {
  const _HomeData({
    this.resume = const [],
    this.nextUp = const [],
    this.shelves = const [],
  });
  final List<MediaItem> resume;
  final List<MediaItem> nextUp;
  final List<_Shelf> shelves;
}
