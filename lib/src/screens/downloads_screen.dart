import 'package:flutter/material.dart';

import '../services/download_store.dart';
import '../theme.dart';
import 'offline_player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => DownloadsScreenState();
}

class DownloadsScreenState extends State<DownloadsScreen> {
  final _store = DownloadStore();
  late Future<List<DownloadedMedia>> _downloads = _store.list();

  void refresh() => setState(() => _downloads = _store.list());

  Future<void> _remove(DownloadedMedia media) async {
    await _store.remove(media);
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<DownloadedMedia>>(
        future: _downloads,
        builder: (context, snapshot) {
          final downloads = snapshot.data ?? const [];
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Downloads',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (snapshot.connectionState != ConnectionState.done)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (downloads.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Baixe filmes ou episódios para assistir sem internet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: CasaFlixColors.muted),
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: downloads.length,
                  itemBuilder: (context, index) {
                    final media = downloads[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: const CircleAvatar(
                        backgroundColor: CasaFlixColors.ink,
                        child: Icon(Icons.download_done_rounded),
                      ),
                      title: Text(
                        media.item.seriesName ?? media.item.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: media.item.seriesName == null
                          ? const Text('Disponível offline')
                          : Text(
                              'T${media.item.parentIndexNumber ?? '-'} E${media.item.indexNumber ?? '-'} · ${media.item.name}',
                            ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OfflinePlayerScreen(media: media),
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remover download',
                        onPressed: () => _remove(media),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
