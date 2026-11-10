import 'package:flutter/material.dart';

import '../models/jellyfin_session.dart';
import '../models/media_item.dart';
import '../services/jellyfin_api.dart';
import '../theme.dart';
import 'media_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
  });

  final JellyfinApi api;
  final JellyfinSession session;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<_Shelf>> _content;

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  Future<List<_Shelf>> _load() async {
    final views = await widget.api.views();
    final shelves = <_Shelf>[];
    for (final view in views) {
      final items = await widget.api.latest(view.id);
      if (items.isNotEmpty) shelves.add(_Shelf(view.name, items));
    }
    return shelves;
  }

  void _refresh() => setState(() => _content = _load());

  void _open(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailsScreen(api: widget.api, item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<_Shelf>>(
          future: _content,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              debugPrint('CasaFlix: falha ao carregar: ${snapshot.error}');
              return _HomeError(
                onRetry: _refresh,
                onLogout: widget.onLogout,
                message: snapshot.error is JellyfinException
                    ? snapshot.error.toString()
                    : 'Não foi possível carregar o catálogo.',
              );
            }
            final shelves = snapshot.data ?? const [];
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
                    ),
                  ),
                  if (shelves.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text('Sua biblioteca ainda está vazia.'),
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: _HeroFeature(
                        api: widget.api,
                        item: shelves.first.items.first,
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.session, required this.onLogout});
  final JellyfinSession session;
  final VoidCallback onLogout;

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
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Sair')),
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
    return GestureDetector(
      onTap: () => onTap(item),
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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onTap(item),
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

class _Shelf {
  const _Shelf(this.title, this.items);
  final String title;
  final List<MediaItem> items;
}
