import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/search_models.dart';

class SearchSuggestionsPanel extends StatelessWidget {
  const SearchSuggestionsPanel({
    super.key,
    required this.query,
    required this.history,
    required this.suggestions,
    required this.onSelected,
    required this.onDeleteHistory,
    required this.onClearHistory,
    this.genres = const [],
    this.onGenreSelected,
  });

  final String query;
  final List<String> history;
  final AsyncValue<List<SearchSuggestion>> suggestions;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onDeleteHistory;
  final VoidCallback onClearHistory;
  final List<String> genres;
  final ValueChanged<String>? onGenreSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (history.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Búsquedas recientes',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onClearHistory,
                  child: const Text('Borrar todo'),
                ),
              ],
            ),
            for (final item in history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_rounded),
                title: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Eliminar',
                  onPressed: () => onDeleteHistory(item),
                  icon: const Icon(Icons.close_rounded),
                ),
                onTap: () => onSelected(item),
              ),
            const SizedBox(height: 12),
          ],
          if (genres.isNotEmpty) ...[
            Text(
              'Explora por género',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in genres.take(16))
                  ActionChip(
                    label: Text(genre),
                    onPressed: onGenreSelected == null
                        ? null
                        : () => onGenreSelected!(genre),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  Icon(
                    Icons.manage_search_rounded,
                    size: 54,
                    color: theme.colorScheme.primary.withValues(alpha: .7),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Busca canciones, álbumes, artistas, playlists o letras.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return suggestions.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.search_rounded),
            title: Text('Buscar “$trimmed”'),
            onTap: () => onSelected(trimmed),
          ),
        ],
      ),
      data: (items) => ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.search_rounded),
            title: Text('Buscar “$trimmed”'),
            trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
            onTap: () => onSelected(trimmed),
          ),
          const Divider(height: 1),
          for (final suggestion in items)
            ListTile(
              leading: Icon(
                suggestion.fromHistory
                    ? Icons.history_rounded
                    : Icons.north_west_rounded,
                size: 20,
              ),
              title: _highlighted(context, suggestion),
              onTap: () => onSelected(suggestion.text),
            ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Sin sugerencias. Pulsa Enter para buscar igualmente.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _highlighted(BuildContext context, SearchSuggestion suggestion) {
    final theme = Theme.of(context);
    final runs = suggestion.runs;
    if (runs.isEmpty) return Text(suggestion.text, maxLines: 1);
    return Text.rich(
      TextSpan(
        children: [
          for (final run in runs)
            TextSpan(
              text: run.text,
              style: run.bold
                  ? const TextStyle(fontWeight: FontWeight.w800)
                  : null,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyLarge,
    );
  }
}

class SearchSelectionBar extends StatelessWidget {
  const SearchSelectionBar({
    super.key,
    required this.count,
    required this.onClose,
    this.onSelectAll,
    this.onDownload,
    this.onQueue,
    this.onFavorite,
    this.onDeleteHistory,
  });

  final int count;
  final VoidCallback onClose;
  final VoidCallback? onSelectAll;
  final VoidCallback? onDownload;
  final VoidCallback? onQueue;
  final VoidCallback? onFavorite;
  final VoidCallback? onDeleteHistory;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 12,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Salir de la selección',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
            Expanded(
              child: Text(
                count == 1 ? '1 seleccionada' : '$count seleccionadas',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Seleccionar todo',
              onPressed: onSelectAll,
              icon: const Icon(Icons.select_all_rounded),
            ),
            IconButton(
              tooltip: 'Descargar',
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded),
            ),
            IconButton(
              tooltip: 'Añadir a la cola',
              onPressed: onQueue,
              icon: const Icon(Icons.queue_music_rounded),
            ),
            IconButton(
              tooltip: 'Favoritos',
              onPressed: onFavorite,
              icon: const Icon(Icons.favorite_rounded),
            ),
            IconButton(
              tooltip: 'Eliminar del historial',
              onPressed: onDeleteHistory,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
          ],
        ),
      ),
    ),
  );
}

class SearchLoadMore extends StatelessWidget {
  const SearchLoadMore({
    super.key,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    this.error,
    this.onRetry,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ),
      );
    }
    if (!hasMore) return const SizedBox(height: 24);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: OutlinedButton(
          onPressed: onLoadMore,
          child: const Text('Cargar más'),
        ),
      ),
    );
  }
}
