import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/jellyfin_api.dart';
import '../theme.dart';

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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: .62,
        crossAxisSpacing: 14,
        mainAxisSpacing: 20,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onOpen(item),
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
