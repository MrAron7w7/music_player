import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/music_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/settings_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_shimmer.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/song_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final controller = TextEditingController();
  Timer? debounce;
  int tab = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void changed(String query) {
    debounce?.cancel();
    if (query.trim().isEmpty) {
      if (ref.read(searchQueryProvider).isNotEmpty) {
        ref.read(searchQueryProvider.notifier).state = '';
      }
      return;
    }
    debounce = Timer(const Duration(milliseconds: 250), () {
      final normalized = query.trim();
      if (normalized == ref.read(searchQueryProvider)) return;
      ref.read(searchQueryProvider.notifier).state = normalized;
      _rememberSearch(normalized);
    });
  }

  void _submitSearch(String query) {
    debounce?.cancel();
    final normalized = query.trim();
    ref.read(searchQueryProvider.notifier).state = normalized;
    _rememberSearch(normalized);
  }

  void _rememberSearch(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;
    final updated = [
      value,
      ...ref
          .read(searchHistoryProvider)
          .where((item) => item.toLowerCase() != value.toLowerCase()),
    ].take(12).toList();
    ref.read(searchHistoryProvider.notifier).state = updated;
    ref.read(localRepositoryProvider).settings.put('searchHistory', updated);
  }

  void _runPreviousSearch(String value) {
    debounce?.cancel();
    controller.text = value;
    ref.read(searchQueryProvider.notifier).state = value;
    _rememberSearch(value);
  }

  Future<void> _clearSearchHistory() async {
    await ref.read(localRepositoryProvider).settings.delete('searchHistory');
    ref.read(searchHistoryProvider.notifier).state = [];
  }

  @override
  Widget build(BuildContext context) {
    // La pantalla vive dentro de un IndexedStack. Si no está visible no
    // necesitamos construir su árbol ni mantener vivos los proveedores de
    // búsqueda; al volver, el controlador conserva el texto y la caché hace
    // que el resultado reaparezca casi al instante.
    if (ref.watch(selectedTabProvider) != 1) return const SizedBox.shrink();
    final offline = ref.watch(offlineModeProvider);
    final query = ref.watch(searchQueryProvider).trim();
    // Only request the active tab. The service caches each query, so returning
    // to another tab is still fast without three simultaneous network calls.
    final songs = !offline && tab == 0
        ? ref.watch(searchResultsProvider)
        : null;
    final albums = !offline && tab == 1
        ? ref.watch(searchAlbumsProvider)
        : null;
    final artists = !offline && tab == 2
        ? ref.watch(searchArtistsProvider)
        : null;
    final searchHistory = ref.watch(searchHistoryProvider);

    Widget content;
    if (offline) {
      content = const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Modo offline activo',
        message: 'Desactiva el modo offline en Ajustes para buscar en línea, o escucha tu música desde Biblioteca → Descargas.',
      );
    } else if (query.isEmpty) {
      content = const EmptyState(
        icon: Icons.search_rounded,
        title: '¿Qué quieres escuchar?',
        message: 'Busca canciones, artistas o álbumes para encontrar tu próximo favorito.',
      );
    } else if (tab == 0) {
      content = songs!.when(
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.music_off_rounded,
                title: 'No encontramos canciones',
                message: 'Prueba con otro nombre o con el artista.',
              )
            : ListView.builder(
                itemCount: items.length,
                // La cola se construye de forma inteligente a partir de la
                // canción elegida; no encadenamos todos los resultados.
                itemBuilder: (_, index) => SongTile(items[index]),
              ),
        loading: () => const LoadingShimmer(),
        error: (_, _) => EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'No se pudo completar la búsqueda',
          message: 'Comprueba tu conexión e inténtalo de nuevo.',
          onRetry: () => ref.invalidate(searchResultsProvider),
          retryLabel: 'Reintentar',
        ),
      );
    } else if (tab == 1) {
      content = albums!.when(
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.album_rounded,
                title: 'No encontramos álbumes',
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final album = items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(10),
                        leading: AlbumArt(url: album.thumbnailUrl, size: 54),
                        title: Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          album.artists.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: album.id.isEmpty
                            ? null
                            : () => context.push('/album/${album.id}'),
                      ),
                    ),
                  );
                },
              ),
        loading: () => const LoadingShimmer(),
        error: (_, _) => EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'No se pudieron cargar álbumes',
          onRetry: () => ref.invalidate(searchAlbumsProvider),
          retryLabel: 'Reintentar',
        ),
      );
    } else {
      content = artists!.when(
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.person_search_rounded,
                title: 'No encontramos artistas',
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final artist = items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          radius: 27,
                          backgroundColor: Theme.of(context).colorScheme.primary
                              .withValues(alpha: .12),
                          child: Icon(
                            Icons.person_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          artist.subscribers ?? 'Artista',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                },
              ),
        loading: () => const LoadingShimmer(),
        error: (_, _) => EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'No se pudieron cargar artistas',
          onRetry: () => ref.invalidate(searchArtistsProvider),
          retryLabel: 'Reintentar',
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
              child: Text(
                'Buscar',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.6),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SearchBarWidget(
                controller: controller,
                onChanged: changed,
                onSubmitted: _submitSearch,
              ),
            ),
            if (query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    for (final entry in const [
                      (0, 'Canciones'),
                      (1, 'Álbumes'),
                      (2, 'Artistas'),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: tab == entry.$1
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => setState(() => tab = entry.$1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                                child: Center(
                                  child: Text(
                                    entry.$2,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: tab == entry.$1
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .onPrimary
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: query.isEmpty && searchHistory.isNotEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Búsquedas recientes',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton(
                              onPressed: _clearSearchHistory,
                              child: const Text('Borrar'),
                            ),
                          ],
                        ),
                        ...searchHistory.map(
                          (value) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history_rounded),
                            title: Text(value),
                            trailing: IconButton(
                              tooltip: 'Buscar de nuevo',
                              icon: const Icon(
                                Icons.north_west_rounded,
                                size: 20,
                              ),
                              onPressed: () => _runPreviousSearch(value),
                            ),
                            onTap: () => _runPreviousSearch(value),
                          ),
                        ),
                      ],
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: content,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
