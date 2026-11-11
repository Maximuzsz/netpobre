import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/download_manager.dart';
import '../services/jellyfin_api.dart';
import '../services/download_store.dart';
import '../theme.dart';
import '../widgets/tv_navigation.dart';
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
  bool _downloaded = false;
  bool _queued = false;
  bool _downloading = false;
  final _downloads = DownloadStore();
  final _downloadManager = DownloadManager.instance;
  late final Future<List<MediaItem>>? _episodes = widget.item.type == 'Series'
      ? widget.api.episodes(widget.item.id)
      : null;

  @override
  void initState() {
    super.initState();
    _checkDownload();
  }

  Future<void> _checkDownload() async {
    final legacyDownload = await _downloads.contains(widget.item.id);
    await _downloadManager.refresh();
    final managed = _downloadManager.downloads.value.where(
      (entry) => entry.item.id == widget.item.id,
    );
    if (mounted) {
      setState(() {
        _downloaded = legacyDownload || managed.any((entry) => entry.complete);
        _queued = managed.any((entry) => !entry.complete);
      });
    }
  }

  Future<void> _download(MediaItem item) async {
    if (_downloading || _downloaded || _queued) return;
    setState(() => _downloading = true);
    try {
      final added = await _downloadManager.enqueue(widget.api, item);
      if (!mounted) return;
      setState(() => _queued = added || _queued);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicionado à fila. Você pode fechar o app.'),
        ),
      );
    } on JellyfinException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível concluir o download.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _downloadEpisode(MediaItem episode) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await _downloads.contains(episode.id) ||
        await _downloadManager.contains(episode.id)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Este episódio já está na fila ou nos Downloads.'),
        ),
      );
      return;
    }
    try {
      await _downloadManager.enqueue(widget.api, episode);
      messenger.showSnackBar(
        SnackBar(content: Text('${episode.name} foi adicionado à fila.')),
      );
    } on JellyfinException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível baixar o episódio.')),
      );
    }
  }

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
                if (item.originalTitle != null &&
                    item.originalTitle!.trim().isNotEmpty &&
                    item.originalTitle!.trim().toLowerCase() !=
                        title.trim().toLowerCase()) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Título original: ${item.originalTitle}',
                    style: const TextStyle(color: CasaFlixColors.muted),
                  ),
                ],
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
                    if (item.playable)
                      OutlinedButton.icon(
                        onPressed: _downloading || _downloaded || _queued
                            ? null
                            : () => _download(item),
                        icon: _downloading
                            ? SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _downloaded
                                    ? Icons.download_done_rounded
                                    : _queued
                                    ? Icons.schedule_rounded
                                    : Icons.download_rounded,
                              ),
                        label: Text(
                          _downloaded
                              ? 'Baixado'
                              : _queued
                              ? 'Na fila'
                              : _downloading
                              ? 'Adicionando…'
                              : 'Baixar',
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
                                onDownload: () => _downloadEpisode(episode),
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
    required this.onDownload,
  });

  final JellyfinApi api;
  final MediaItem episode;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final season = episode.parentIndexNumber ?? 0;
    final number = episode.indexNumber ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TvFocusCard(
        borderRadius: BorderRadius.circular(18),
        onPressed: onPlay,
        child: ColoredBox(
          color: CasaFlixColors.deepSea,
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Baixar episódio',
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.play_circle_fill_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
