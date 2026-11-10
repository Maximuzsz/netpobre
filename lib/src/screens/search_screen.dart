import 'dart:async';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/jellyfin_api.dart';
import '../theme.dart';
import '../widgets/catalog_grid.dart';
import 'media_details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.api});
  final JellyfinApi api;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.api.search(query);
      if (!mounted || query != _controller.text.trim()) return;
      setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _error = 'A busca não pôde ser concluída.');
    } finally {
      if (mounted && query == _controller.text.trim()) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(MediaItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailsScreen(api: widget.api, item: item),
      ),
    );
    if (_controller.text.trim().isNotEmpty) await _search(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: Text(
              'Buscar',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              controller: _controller,
              autofocus: false,
              onChanged: _changed,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Filmes, séries e episódios',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          _changed('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _error!,
                style: const TextStyle(color: CasaFlixColors.muted),
              ),
            ),
          Expanded(
            child: CatalogGrid(
              api: widget.api,
              items: _results,
              onOpen: _open,
              emptyMessage: _controller.text.trim().isEmpty
                  ? 'Digite um título para procurar em todo o catálogo.'
                  : 'Nenhum título encontrado.',
            ),
          ),
        ],
      ),
    );
  }
}
