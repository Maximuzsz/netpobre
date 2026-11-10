import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/jellyfin_api.dart';
import '../theme.dart';
import 'player_screen.dart';

class MediaDetailsScreen extends StatefulWidget {
  const MediaDetailsScreen({super.key, required this.api, required this.item});

  final JellyfinApi api;
  final MediaItem item;

  @override
  State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  late MediaItem _item = widget.item;
  bool _favoriteBusy = false;
  late final Future<List<MediaItem>>? _episodes = widget.item.type == 'Series'
      ? widget.api.episodes(widget.item.id)
      : null;

  Future<void> _play(BuildContext context, MediaItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(api: widget.api, item: item),
      ),
    );
    if (!mounted) return;
    try {
      final updated = await widget.api.item(_item.id);
      if (mounted) setState(() => _item = updated);
    } catch (_) {
      // A reprodução não deve parecer ter falhado se apenas a atualização
      // dos metadados estiver temporariamente indisponível.
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final next = !_item.isFavorite;
    setState(() => _favoriteBusy = true);
    try {
      await widget.api.setFavorite(_item.id, next);
      if (mounted) setState(() => _item = _item.copyWith(isFavorite: next));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar sua lista.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final title = item.seriesName ?? item.name;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 330,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    widget.api.imageUrl(item, backdrop: true, width: 1200),
                    headers: widget.api.authHeaders,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(color: CasaFlixColors.deepSea),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, CasaFlixColors.night],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 42),
            sliver: SliverList.list(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                if (item.seriesName != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'T${item.parentIndexNumber ?? '-'} · E${item.indexNumber ?? '-'}  ${item.name}',
                    style: const TextStyle(
                      color: CasaFlixColors.muted,
                      fontSize: 16,
                    ),
                  ),
                ],
                if (item.year != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${item.year}',
                    style: const TextStyle(color: CasaFlixColors.muted),
                  ),
                ],
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (item.playable)
                      FilledButton.icon(
                        onPressed: () => _play(context, item),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          item.resumePosition > const Duration(seconds: 30)
                              ? 'Continuar'
                              : 'Assistir agora',
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _favoriteBusy ? null : _toggleFavorite,
                      icon: _favoriteBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              item.isFavorite
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                            ),
                      label: Text(
                        item.isFavorite ? 'Na minha lista' : 'Minha lista',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  item.overview?.trim().isNotEmpty == true
                      ? item.overview!
                      : 'Sem sinopse disponível.',
                  style: const TextStyle(
                    color: CasaFlixColors.ivory,
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
                if (_episodes != null) ...[
                  const SizedBox(height: 34),
                  Text(
                    'Episódios',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FutureBuilder<List<MediaItem>>(
                    future: _episodes,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return const Text(
                          'Não foi possível carregar os episódios.',
                          style: TextStyle(color: CasaFlixColors.muted),
                        );
                      }
                      final episodes = snapshot.data ?? const [];
                      if (episodes.isEmpty) {
                        return const Text(
                          'Nenhum episódio encontrado.',
                          style: TextStyle(color: CasaFlixColors.muted),
                        );
                      }
                      return Column(
                        children: episodes
                            .map(
                              (episode) => _EpisodeTile(
                                api: widget.api,
                                episode: episode,
                                onPlay: () => _play(context, episode),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.api,
    required this.episode,
    required this.onPlay,
  });

  final JellyfinApi api;
  final MediaItem episode;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final season = episode.parentIndexNumber ?? 0;
    final number = episode.indexNumber ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: CasaFlixColors.deepSea,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          child: Row(
            children: [
              SizedBox(
                width: 132,
                height: 82,
                child: Image.network(
                  api.imageUrl(episode, width: 420),
                  headers: api.authHeaders,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(
                        color: CasaFlixColors.night,
                        child: Icon(Icons.movie_outlined),
                      ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'T$season · E$number',
                        style: const TextStyle(
                          color: CasaFlixColors.sky,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.play_circle_fill_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
