import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/jellyfin_api.dart';
import '../theme.dart';
import 'tv_navigation.dart';

class CatalogGrid extends StatelessWidget {
  const CatalogGrid({
    super.key,
    required this.api,
    required this.items,
    required this.onOpen,
    required this.emptyMessage,
  });

  final JellyfinApi api;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CasaFlixColors.muted, height: 1.45),
          ),
        ),
      );
    }
    final television = TvMode.of(context);
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        television ? 28 : 18,
        18,
        television ? 28 : 18,
        television ? 48 : 120,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: television ? 5 : 2,
        childAspectRatio: .62,
        crossAxisSpacing: television ? 20 : 14,
        mainAxisSpacing: television ? 24 : 20,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return TvFocusCard(
          borderRadius: BorderRadius.circular(16),
          onPressed: () => onOpen(item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    api.imageUrl(item, width: 520),
                    headers: api.authHeaders,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: CasaFlixColors.deepSea,
                      alignment: Alignment.center,
                      child: const Icon(Icons.movie_outlined, size: 40),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                item.seriesName ?? item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );
      },
    );
  }
}
