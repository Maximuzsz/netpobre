import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/jellyfin_api.dart';
import '../widgets/catalog_grid.dart';
import 'media_details_screen.dart';

class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key, required this.api});
  final JellyfinApi api;

  @override
  State<MyListScreen> createState() => MyListScreenState();
}

class MyListScreenState extends State<MyListScreen> {
  late Future<List<MediaItem>> _items = widget.api.favorites();

  void refresh() => setState(() => _items = widget.api.favorites());

  Future<void> _open(MediaItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailsScreen(api: widget.api, item: item),
      ),
    );
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Text(
              'Minha Lista',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MediaItem>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: FilledButton(
                      onPressed: refresh,
                      child: const Text('Tentar novamente'),
                    ),
                  );
                }
                return CatalogGrid(
                  api: widget.api,
                  items: snapshot.data ?? const [],
                  onOpen: _open,
                  emptyMessage:
                      'Adicione títulos à sua lista para encontrá-los aqui.',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
