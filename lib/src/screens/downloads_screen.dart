import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

import '../services/download_manager.dart';
import '../services/download_store.dart';
import '../theme.dart';
import 'offline_player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => DownloadsScreenState();
}

class DownloadsScreenState extends State<DownloadsScreen> {
  final _manager = DownloadManager.instance;
  final _legacyStore = DownloadStore();
  late Future<List<DownloadedMedia>> _legacyDownloads = _legacyStore.list();

  void refresh() {
    _manager.refresh();
    setState(() => _legacyDownloads = _legacyStore.list());
  }

  Future<void> _removeLegacy(DownloadedMedia media) async {
    await _legacyStore.remove(media);
    refresh();
  }

  Future<void> _pause(ManagedDownload entry) async {
    final paused = await _manager.pause(entry);
    if (!paused && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O servidor ainda não liberou a pausa deste arquivo.'),
        ),
      );
    }
  }

  Future<void> _resume(ManagedDownload entry) async {
    final resumed = await _manager.resume(entry);
    if (!resumed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível continuar o download.')),
      );
    }
  }

  Future<void> _retry(ManagedDownload entry) async {
    final accepted = await _manager.retry(entry);
    if (!accepted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível repetir o download.')),
      );
    }
  }

  Future<void> _removeManaged(ManagedDownload entry) async {
    await _manager.remove(entry);
  }

  void _play(DownloadedMedia media) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OfflinePlayerScreen(media: media)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<List<ManagedDownload>>(
        valueListenable: _manager.downloads,
        builder: (context, managed, _) {
          return FutureBuilder<List<DownloadedMedia>>(
            future: _legacyDownloads,
            builder: (context, snapshot) {
              final active = managed.where((entry) => !entry.complete).toList();
              final completed = managed
                  .where((entry) => entry.complete)
                  .toList();
              final managedIds = completed
                  .map((entry) => entry.item.id)
                  .toSet();
              final legacy = (snapshot.data ?? const [])
                  .where((entry) => !managedIds.contains(entry.item.id))
                  .toList();
              final loading =
                  snapshot.connectionState != ConnectionState.done &&
                  managed.isEmpty;
              final empty =
                  active.isEmpty && completed.isEmpty && legacy.isEmpty;

              return RefreshIndicator(
                onRefresh: () async {
                  await _manager.refresh();
                  setState(() => _legacyDownloads = _legacyStore.list());
                  await _legacyDownloads;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                      sliver: SliverToBoxAdapter(
                        child: _DownloadsHeader(
                          active: active,
                          onPauseAll: _manager.pauseAll,
                          onResumeAll: _manager.resumeAll,
                        ),
                      ),
                    ),
                    if (loading)
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (empty)
                      const SliverFillRemaining(child: _EmptyDownloads())
                    else ...[
                      if (active.isNotEmpty) ...[
                        const _SectionTitle(title: 'Em andamento'),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                          sliver: SliverList.separated(
                            itemCount: active.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final entry = active[index];
                              return _QueueCard(
                                entry: entry,
                                onPause: () => _pause(entry),
                                onResume: () => _resume(entry),
                                onRetry: () => _retry(entry),
                                onRemove: () => _removeManaged(entry),
                              );
                            },
                          ),
                        ),
                      ],
                      if (completed.isNotEmpty || legacy.isNotEmpty) ...[
                        const _SectionTitle(title: 'Prontos para assistir'),
                        SliverList.builder(
                          itemCount: completed.length + legacy.length,
                          itemBuilder: (context, index) {
                            if (index < completed.length) {
                              final entry = completed[index];
                              final media = DownloadedMedia(
                                item: entry.item,
                                path: entry.path!,
                              );
                              return _CompletedTile(
                                media: media,
                                size: entry.record.expectedFileSize,
                                onPlay: () => _play(media),
                                onRemove: () => _removeManaged(entry),
                              );
                            }
                            final media = legacy[index - completed.length];
                            return _CompletedTile(
                              media: media,
                              onPlay: () => _play(media),
                              onRemove: () => _removeLegacy(media),
                            );
                          },
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 34)),
                      ],
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DownloadsHeader extends StatelessWidget {
  const _DownloadsHeader({
    required this.active,
    required this.onPauseAll,
    required this.onResumeAll,
  });

  final List<ManagedDownload> active;
  final VoidCallback onPauseAll;
  final VoidCallback onResumeAll;

  @override
  Widget build(BuildContext context) {
    final allPaused =
        active.isNotEmpty &&
        active.every((entry) => entry.status == TaskStatus.paused);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Downloads',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                active.isEmpty
                    ? 'Sua estante que funciona sem internet.'
                    : '${active.length} ${active.length == 1 ? 'título na fila' : 'títulos na fila'}',
                style: const TextStyle(color: CasaFlixColors.muted),
              ),
            ],
          ),
        ),
        if (active.isNotEmpty)
          IconButton.filledTonal(
            tooltip: allPaused ? 'Continuar todos' : 'Pausar todos',
            onPressed: allPaused ? onResumeAll : onPauseAll,
            icon: Icon(
              allPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
    sliver: SliverToBoxAdapter(
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
    ),
  );
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.entry,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onRemove,
  });

  final ManagedDownload entry;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final failed =
        entry.status == TaskStatus.failed ||
        entry.status == TaskStatus.notFound ||
        entry.status == TaskStatus.canceled;
    final paused = entry.status == TaskStatus.paused;
    final determinate =
        entry.record.progress >= 0 && entry.record.progress <= 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CasaFlixColors.ink,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: failed
              ? Theme.of(context).colorScheme.error.withValues(alpha: .55)
              : CasaFlixColors.sky.withValues(alpha: .2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: CasaFlixColors.night,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    failed
                        ? Icons.wifi_off_rounded
                        : paused
                        ? Icons.pause_rounded
                        : Icons.downloading_rounded,
                    color: failed
                        ? Theme.of(context).colorScheme.error
                        : CasaFlixColors.amber,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.item.seriesName ?? entry.item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _statusText(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: failed
                              ? Theme.of(context).colorScheme.error
                              : CasaFlixColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (failed)
                  IconButton(
                    tooltip: 'Tentar novamente',
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                  )
                else if (paused)
                  IconButton(
                    tooltip: 'Continuar',
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow_rounded),
                  )
                else
                  IconButton(
                    tooltip: 'Pausar',
                    onPressed: onPause,
                    icon: const Icon(Icons.pause_rounded),
                  ),
                IconButton(
                  tooltip: 'Cancelar',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (!failed) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 5,
                  value: determinate ? entry.progress : null,
                  backgroundColor: CasaFlixColors.night,
                  color: paused ? CasaFlixColors.muted : CasaFlixColors.amber,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusText(ManagedDownload entry) => switch (entry.status) {
    TaskStatus.enqueued => 'Na fila',
    TaskStatus.running =>
      entry.record.progress >= 0
          ? '${(entry.progress * 100).round()}% baixado'
          : 'Baixando…',
    TaskStatus.waitingToRetry => 'Conexão instável · tentando novamente',
    TaskStatus.paused => 'Pausado · toque em continuar',
    TaskStatus.notFound => 'O arquivo não foi encontrado no servidor',
    TaskStatus.failed =>
      entry.record.exception?.description.isNotEmpty == true
          ? entry.record.exception!.description
          : 'O download foi interrompido',
    TaskStatus.canceled => 'Cancelado',
    TaskStatus.complete => 'Concluído',
  };
}

class _CompletedTile extends StatelessWidget {
  const _CompletedTile({
    required this.media,
    required this.onPlay,
    required this.onRemove,
    this.size = -1,
  });

  final DownloadedMedia media;
  final VoidCallback onPlay;
  final VoidCallback onRemove;
  final int size;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    leading: const CircleAvatar(
      backgroundColor: CasaFlixColors.ink,
      child: Icon(Icons.play_arrow_rounded, color: CasaFlixColors.sky),
    ),
    title: Text(
      media.item.seriesName ?? media.item.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text(_subtitle(media, size)),
    onTap: onPlay,
    trailing: IconButton(
      tooltip: 'Remover download',
      onPressed: onRemove,
      icon: const Icon(Icons.delete_outline_rounded),
    ),
  );

  String _subtitle(DownloadedMedia media, int size) {
    final episode = media.item.seriesName == null
        ? 'Disponível offline'
        : 'T${media.item.parentIndexNumber ?? '-'} E${media.item.indexNumber ?? '-'} · ${media.item.name}';
    if (size <= 0) return episode;
    final megabytes = size / (1024 * 1024);
    final label = megabytes >= 1024
        ? '${(megabytes / 1024).toStringAsFixed(1)} GB'
        : '${megabytes.round()} MB';
    return '$episode · $label';
  }
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(34, 0, 34, 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/netpobre-mascot-splash.png',
            width: 118,
            height: 118,
          ),
          const SizedBox(height: 18),
          Text(
            'A TV ainda está vazia',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Abra um filme ou episódio e toque em Baixar. A fila continua mesmo com o app em segundo plano.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CasaFlixColors.muted, height: 1.45),
          ),
        ],
      ),
    ),
  );
}
