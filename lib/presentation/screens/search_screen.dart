import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/voice_search_controller.dart';
import '../../data/models/search_models.dart';
import '../../data/models/home_models.dart';
import '../../data/models/song_model.dart';
import '../../data/repositories/music_repository.dart' show AudioQuality;
import '../../providers/downloads_providers.dart';
import '../../providers/explore_providers.dart';
import '../../providers/followed_artists_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart'
    hide searchSongsProvider, searchAlbumsProvider, searchArtistsProvider;
import '../../providers/navigation_providers.dart';
import '../../providers/network_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/search_providers.dart';
import '../../providers/settings_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/home_cards.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/search_empty_state.dart';
import '../widgets/search_filter_sheet.dart';
import '../widgets/search_panels.dart';
import '../widgets/song_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    'Todo',
    'Canciones',
    'Álbumes',
    'Artistas',
    'Playlists',
  ];

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scroll = ScrollController();
  late final TabController _tabController;
  late final VoiceSearchController _voice;
  Timer? _debounce;
  String _query = '';
  String _input = '';
  String _voiceBaseText = '';
  int _tab = 0;
  bool _showSuggestions = true;
  bool _voiceUnsupported = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _voice = VoiceSearchController()..addListener(_onVoiceChanged);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tab == _tabController.index) return;
      setState(() {
        _tab = _tabController.index;
        _showSuggestions = false;
      });
    });
    _scroll.addListener(_onScroll);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && mounted) {
        setState(() => _showSuggestions = true);
      }
    });
    _query = ref.read(searchQueryProvider);
    _input = _query;
    _controller.text = _query;
    _controller.selection = TextSelection.collapsed(offset: _query.length);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _focusNode.dispose();
    _controller.dispose();
    _voice
      ..removeListener(_onVoiceChanged)
      ..dispose();
    super.dispose();
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 480) return;
    _loadMoreForTab();
  }

  void _loadMoreForTab() {
    if (_query.trim().length < 2) return;
    if (ref.read(searchFiltersProvider).scope != SearchScope.catalog) return;
    if (ref.read(effectiveOfflineProvider)) return;
    switch (_tab) {
      case 1:
        final state = ref.read(searchSongsProvider(_query));
        if (state.hasMore && !state.loadingMore && !state.loading) {
          ref.read(searchSongsProvider(_query).notifier).loadMore();
        }
      case 2:
        final state = ref.read(searchAlbumsProvider(_query));
        if (state.hasMore && !state.loadingMore && !state.loading) {
          ref.read(searchAlbumsProvider(_query).notifier).loadMore();
        }
      case 3:
        final state = ref.read(searchArtistsProvider(_query));
        if (state.hasMore && !state.loadingMore && !state.loading) {
          ref.read(searchArtistsProvider(_query).notifier).loadMore();
        }
      case 4:
        final state = ref.read(searchPlaylistsProvider(_query));
        if (state.hasMore && !state.loadingMore && !state.loading) {
          ref.read(searchPlaylistsProvider(_query).notifier).loadMore();
        }
    }
  }

  void _onChanged(String value) {
    if (value.trim().isEmpty && _voice.isListening) {
      unawaited(_voice.cancel());
    }
    setState(() {
      _input = value;
      _showSuggestions = true;
    });
    _debounce?.cancel();
    final normalized = value.trim();
    if (normalized.isEmpty) {
      if (_query.isNotEmpty) {
        setState(() => _query = '');
        ref.read(searchQueryProvider.notifier).state = '';
        ref.read(ignoreSpellingProvider.notifier).state = false;
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || normalized == _query) return;
      ref.read(ignoreSpellingProvider.notifier).state = false;
      ref.read(searchQueryProvider.notifier).state = normalized;
      setState(() => _query = normalized);
    });
  }

  void _commit(String value, {bool remember = true}) {
    final normalized = value.trim();
    if (_voice.isListening) unawaited(_voice.stop());
    _debounce?.cancel();
    ref.read(ignoreSpellingProvider.notifier).state = false;
    _controller.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    ref.read(searchQueryProvider.notifier).state = normalized;
    setState(() {
      _query = normalized;
      _input = normalized;
      _showSuggestions = false;
    });
    if (remember && normalized.length >= 2) {
      ref.read(searchHistoryNotifierProvider.notifier).add(normalized);
    }
    _focusNode.unfocus();
  }

  Future<void> _applyFilters() async {
    setState(() => _showSuggestions = false);
    await showSearchFilterSheet(
      context,
      ref,
      lyricsScopeEnabled: ref.read(downloadedSongsProvider).isNotEmpty,
    );
  }

  void _setScope(SearchScope scope) {
    final filters = ref.read(searchFiltersProvider);
    if (filters.scope == scope) return;
    ref.read(searchFiltersProvider.notifier).state = filters.copyWith(
      scope: scope,
    );
    ref.read(searchSelectionProvider.notifier).exit();
    setState(() => _showSuggestions = false);
  }

  void _clearFilters() {
    ref.read(searchFiltersProvider.notifier).state = const SearchFilters();
    setState(() => _showSuggestions = false);
  }

  List<String> _emptyGenres() =>
      ref.watch(genresProvider).take(6).map((genre) => genre.title).toList();

  Future<void> _toggleVoiceSearch() async {
    if (_voiceUnsupported) return;
    if (_voice.isListening) {
      await _voice.stop();
      if (mounted && _input.trim().length >= 2) _commit(_input);
      return;
    }
    if (_voice.status == VoiceSearchStatus.processing) return;

    final permission = await Permission.microphone.request();
    if (!mounted) return;
    if (!permission.isGranted) {
      _voice.markDenied();
      _showSnack(
        'Activa el permiso de micrófono en Ajustes para buscar por voz.',
        action: SnackBarAction(
          label: 'Abrir Ajustes',
          onPressed: () {
            openAppSettings();
          },
        ),
      );
      return;
    }

    if (!_voice.isAvailable) {
      final available = await _voice.initialize();
      if (!mounted) return;
      if (!available) {
        setState(() => _voiceUnsupported = true);
        _showSnack(
          'El reconocimiento de voz no está disponible en este dispositivo.',
        );
        return;
      }
    }

    _voiceBaseText = _input.trim();
    final started = await _voice.start(
      onResult: (words, isFinal) {
        if (!mounted) return;
        final combined = _voiceBaseText.isEmpty
            ? words
            : '$_voiceBaseText $words';
        _controller.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );
        _onChanged(combined);
        if (isFinal) _commit(combined);
      },
      onError: (message) {
        if (!mounted) return;
        final lower = message.toLowerCase();
        _showSnack(
          lower.contains('network')
              ? 'El reconocimiento de voz necesita conexión. Puedes seguir escribiendo la búsqueda.'
              : 'No se pudo reconocer la voz. Inténtalo de nuevo o escribe la búsqueda.',
        );
      },
    );
    if (!mounted) return;
    if (!started && _voice.status == VoiceSearchStatus.unavailable) {
      setState(() => _voiceUnsupported = true);
    }
  }

  void _showSnack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  List<SearchEmptyAction> _catalogActions({bool includeClearFilters = false}) {
    return [
      if (includeClearFilters)
        SearchEmptyAction(
          label: 'Quitar filtros',
          icon: Icons.filter_alt_off_rounded,
          onTap: _clearFilters,
        ),
      SearchEmptyAction(
        label: 'Buscar en mi biblioteca',
        icon: Icons.folder_special_rounded,
        onTap: () => _setScope(SearchScope.library),
      ),
      SearchEmptyAction(
        label: 'Ver descargas',
        icon: Icons.download_rounded,
        onTap: () => context.push('/downloads'),
      ),
      SearchEmptyAction(
        label: 'Ver favoritos',
        icon: Icons.favorite_rounded,
        onTap: () => context.push('/library/favorites'),
      ),
    ];
  }

  List<SearchEmptyAction> _libraryActions({bool includeClearFilters = false}) {
    return [
      if (includeClearFilters)
        SearchEmptyAction(
          label: 'Quitar filtros',
          icon: Icons.filter_alt_off_rounded,
          onTap: _clearFilters,
        ),
      SearchEmptyAction(
        label: 'Ver descargas',
        icon: Icons.download_rounded,
        onTap: () => context.push('/downloads'),
      ),
      SearchEmptyAction(
        label: 'Ver favoritos',
        icon: Icons.favorite_rounded,
        onTap: () => context.push('/library/favorites'),
      ),
      if (ref.read(manualOfflineProvider))
        SearchEmptyAction(
          label: 'Desactivar modo offline',
          icon: Icons.cloud_queue_rounded,
          onTap: () => ref.read(offlineModeProvider.notifier).state = false,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(selectedTabProvider, (previous, next) {
      if (next != 1 &&
          (_voice.isListening ||
              _voice.status == VoiceSearchStatus.processing)) {
        unawaited(_voice.cancel());
      }
    });
    // La pantalla vive dentro de un IndexedStack. Si no está visible no
    // construimos su árbol; los providers autoDispose se liberan y la caché
    // persistente hace que volver sea casi instantáneo.
    if (ref.watch(selectedTabProvider) != 1) return const SizedBox.shrink();

    ref.listen<String>(searchQueryProvider, (previous, next) {
      if (next == _query) return;
      _query = next;
      _input = next;
      if (_controller.text != next) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
      ref.read(ignoreSpellingProvider.notifier).state = false;
      if (mounted) {
        setState(() => _showSuggestions = next.isEmpty);
      }
    });

    final filters = ref.watch(searchFiltersProvider);
    final offline = ref.watch(effectiveOfflineProvider);
    final manualOffline = ref.watch(manualOfflineProvider);
    final selection = ref.watch(searchSelectionProvider);
    final history = ref.watch(searchHistoryNotifierProvider);
    final genres = ref
        .watch(genresProvider)
        .map((genre) => genre.title)
        .toList();
    final suggestions = ref.watch(searchSuggestionsProvider(_query));
    final showSuggestions =
        filters.scope != SearchScope.lyrics &&
        (_showSuggestions || _query.isEmpty);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: SearchBarWidget(
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: _onChanged,
                      onSubmitted: _commit,
                      onTap: () => setState(() => _showSuggestions = true),
                      onVoiceSearch: _voiceUnsupported
                          ? null
                          : _toggleVoiceSearch,
                      isListening: _voice.isListening,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Badge(
                    isLabelVisible:
                        filters.hasResultFilters ||
                        filters.sort != SearchSort.relevance,
                    label: Text('${filters.activeCount}'),
                    child: IconButton.filledTonal(
                      tooltip: 'Filtros',
                      onPressed: _applyFilters,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ),
                ],
              ),
            ),
            if (_voice.isListening ||
                _voice.status == VoiceSearchStatus.processing)
              _VoiceListeningBanner(
                processing: _voice.status == VoiceSearchStatus.processing,
                onStop: _toggleVoiceSearch,
              ),
            _ScopeSelector(
              scope: filters.scope,
              lyricsAvailable: true,
              onSelected: _setScope,
            ),
            if (!filters.isEmpty)
              _ActiveFilters(
                filters: filters,
                onClear: _clearFilters,
                onChanged: (value) =>
                    ref.read(searchFiltersProvider.notifier).state = value,
              ),
            if (offline)
              _OfflineBanner(
                manual: manualOffline,
                onDisable: manualOffline
                    ? () => ref.read(offlineModeProvider.notifier).state = false
                    : null,
              ),
            if (filters.scope != SearchScope.lyrics &&
                !showSuggestions &&
                ref.watch(spellingSuggestionProvider(_query)) != null &&
                !ref.watch(ignoreSpellingProvider) &&
                !offline)
              _SpellingBanner(
                suggestion: ref.watch(spellingSuggestionProvider(_query))!,
                onAccept: (value) => _commit(value),
                onSearchAnyway: () {
                  ref.read(ignoreSpellingProvider.notifier).state = true;
                  ref.invalidate(searchSuggestionsProvider(_query));
                },
              ),
            if (filters.scope != SearchScope.lyrics) ...[
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final tab in _tabs) Tab(text: tab)],
              ),
              const Divider(height: 1),
            ],
            Expanded(
              child: showSuggestions
                  ? SearchSuggestionsPanel(
                      query: _input,
                      history: history,
                      suggestions: suggestions,
                      genres: genres,
                      onGenreSelected: _commit,
                      onSelected: _commit,
                      onDeleteHistory: _deleteHistory,
                      onClearHistory: _clearHistory,
                    )
                  : filters.scope == SearchScope.lyrics
                  ? _lyricsBody()
                  : filters.scope == SearchScope.library || offline
                  ? _localBody()
                  : _catalogBody(),
            ),
            if (selection.selecting)
              SearchSelectionBar(
                count: selection.songIds.length,
                onClose: () =>
                    ref.read(searchSelectionProvider.notifier).exit(),
                onSelectAll: () {
                  final songs = _currentSongs();
                  ref
                      .read(searchSelectionProvider.notifier)
                      .selectAll(songs.map((song) => song.id));
                },
                onDownload: () => _downloadSelected(),
                onQueue: () => _queueSelected(),
                onFavorite: () => _favoriteSelected(),
                onDeleteHistory: () => _deleteHistorySelected(),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Historial de búsquedas
  // ---------------------------------------------------------------------------

  void _deleteHistory(String item) {
    final history = ref.read(searchHistoryNotifierProvider);
    final index = history.indexOf(item);
    ref.read(searchHistoryNotifierProvider.notifier).remove(item);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('“$item” eliminada del historial'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => ref
              .read(searchHistoryNotifierProvider.notifier)
              .insertAt(index, item),
        ),
      ),
    );
  }

  void _clearHistory() {
    final previous = ref.read(searchHistoryNotifierProvider);
    if (previous.isEmpty) return;
    ref.read(searchHistoryNotifierProvider.notifier).clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Historial de búsquedas borrado'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => ref
              .read(searchHistoryNotifierProvider.notifier)
              .restore(previous),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Catálogo
  // ---------------------------------------------------------------------------

  Widget _catalogBody() {
    if (_query.trim().length < 2) {
      return const EmptyState(
        icon: Icons.manage_search_rounded,
        title: 'Escribe al menos 2 letras',
        message: 'Así encontramos canciones, álbumes, artistas y playlists.',
      );
    }
    switch (_tab) {
      case 0:
        return _allResults();
      case 1:
        return _songsResults();
      case 2:
        return _albumsResults();
      case 3:
        return _artistsResults();
      case 4:
        return _playlistsResults();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _allResults() {
    final async = ref.watch(searchAllProvider(_query));
    final result = ref.watch(filteredSearchAllProvider(_query));
    if (async.isLoading && result.total == 0) {
      return const Center(child: CircularProgressIndicator());
    }
    if (async.hasError && result.total == 0) {
      return SearchEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo buscar',
        message: '${async.error}',
        actions: _catalogActions(),
        onRetry: () => ref.invalidate(searchAllProvider(_query)),
      );
    }
    if (async.isLoading && result.total == 0) {
      return const Center(child: CircularProgressIndicator());
    }
    if (result.isEmpty) {
      final filters = ref.read(searchFiltersProvider);
      final hasFilters = filters.hasResultFilters;
      final hidden = (async.valueOrNull?.total ?? 0) - result.total;
      return SearchEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Sin resultados',
        message: hasFilters
            ? 'Ningún resultado coincide con “$_query” y los filtros activos.'
            : 'No encontramos nada para “$_query”. Prueba con otras palabras o busca en tu biblioteca.',
        actions: _catalogActions(includeClearFilters: hasFilters),
        genres: _emptyGenres(),
        onGenreTap: _commit,
        hiddenCount: hidden > 0 ? hidden : 0,
      );
    }

    final selection = ref.watch(searchSelectionProvider);
    Widget songTile(SongModel song, int index) => SongTile(
      song,
      playQueue: result.songs,
      startIndex: index,
      selectionMode: selection.selecting,
      selected: selection.songIds.contains(song.id),
      onSelect: () =>
          ref.read(searchSelectionProvider.notifier).toggle(song.id),
      onLongPress: () =>
          ref.read(searchSelectionProvider.notifier).enter(song.id),
    );

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(searchAllProvider(_query)),
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          if (result.best != null)
            _BestResult(hit: result.best!, onTap: () => _openHit(result.best!)),
          if (result.songs.isNotEmpty) ...[
            _Section(
              title: 'Canciones',
              action: 'Ver todas',
              onAction: () => _tabController.animateTo(1),
            ),
            for (
              var index = 0;
              index < result.songs.length && index < 4;
              index++
            )
              songTile(result.songs[index], index),
            if (result.songs.length > 4)
              _SeeMoreRow(
                label: 'Ver las ${result.songs.length} canciones',
                onTap: () => _tabController.animateTo(1),
              ),
          ],
          if (result.albums.isNotEmpty) ...[
            _Section(
              title: 'Álbumes',
              action: 'Ver todos',
              onAction: () => _tabController.animateTo(2),
            ),
            SizedBox(
              height: 208,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: result.albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final album = result.albums[index];
                  return HomeAlbumCard(
                    title: album.title,
                    subtitle: album.artists.join(', '),
                    imageUrl: album.thumbnailUrl,
                    onTap: () => context.push('/album/${album.id}'),
                  );
                },
              ),
            ),
          ],
          if (result.artists.isNotEmpty) ...[
            _Section(
              title: 'Artistas',
              action: 'Ver todos',
              onAction: () => _tabController.animateTo(3),
            ),
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: result.artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final artist = result.artists[index];
                  return HomeAlbumCard(
                    title: artist.name,
                    subtitle: artist.subscribers,
                    imageUrl: artist.thumbnailUrl,
                    circular: true,
                    onTap: () => context.push('/artist/${artist.id}'),
                  );
                },
              ),
            ),
          ],
          if (result.playlists.isNotEmpty) ...[
            _Section(
              title: 'Playlists',
              action: 'Ver todas',
              onAction: () => _tabController.animateTo(4),
            ),
            SizedBox(
              height: 208,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: result.playlists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final playlist = result.playlists[index];
                  return HomeAlbumCard(
                    title: playlist.title,
                    subtitle: playlist.author,
                    imageUrl: playlist.thumbnailUrl,
                    onTap: () =>
                        context.push('/public-playlist/${playlist.id}'),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _songsResults() {
    final state = ref.watch(searchSongsProvider(_query));
    final songs = ref.watch(filteredSongsProvider(_query));
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return SearchEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudieron cargar las canciones',
        message: '${state.error}',
        actions: _catalogActions(),
        onRetry: () => ref.read(searchSongsProvider(_query).notifier).retry(),
      );
    }
    if (songs.isEmpty) {
      final hidden = state.items.length - songs.length;
      return SearchEmptyState(
        icon: Icons.music_off_rounded,
        title: state.items.isEmpty ? 'Sin canciones' : 'Sin coincidencias',
        message: state.items.isEmpty
            ? 'No encontramos canciones para “$_query”.'
            : 'Los filtros ocultaron todas las canciones.',
        actions: _catalogActions(includeClearFilters: state.items.isNotEmpty),
        genres: _emptyGenres(),
        onGenreTap: _commit,
        hiddenCount: hidden > 0 ? hidden : 0,
      );
    }
    final selection = ref.watch(searchSelectionProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(searchSongsProvider(_query).notifier).retry(),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(top: 6, bottom: 110),
        itemCount: songs.length + 1,
        itemBuilder: (context, index) {
          if (index == songs.length) {
            return SearchLoadMore(
              loading: state.loadingMore,
              hasMore: state.hasMore,
              error: state.error,
              onLoadMore: () =>
                  ref.read(searchSongsProvider(_query).notifier).loadMore(),
              onRetry: () =>
                  ref.read(searchSongsProvider(_query).notifier).loadMore(),
            );
          }
          final song = songs[index];
          return SongTile(
            song,
            playQueue: songs,
            startIndex: index,
            selectionMode: selection.selecting,
            selected: selection.songIds.contains(song.id),
            onSelect: () =>
                ref.read(searchSelectionProvider.notifier).toggle(song.id),
            onLongPress: () =>
                ref.read(searchSelectionProvider.notifier).enter(song.id),
          );
        },
      ),
    );
  }

  Widget _albumsResults() {
    final state = ref.watch(searchAlbumsProvider(_query));
    final albums = ref.watch(filteredAlbumsProvider(_query));
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return SearchEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudieron cargar los álbumes',
        message: '${state.error}',
        actions: _catalogActions(),
        onRetry: () => ref.read(searchAlbumsProvider(_query).notifier).retry(),
      );
    }
    if (albums.isEmpty) {
      final hidden = state.items.length - albums.length;
      return SearchEmptyState(
        icon: Icons.album_rounded,
        title: state.items.isEmpty ? 'Sin álbumes' : 'Sin coincidencias',
        message: state.items.isEmpty
            ? 'No encontramos álbumes para “$_query”.'
            : 'Los filtros ocultaron todos los álbumes.',
        actions: _catalogActions(includeClearFilters: state.items.isNotEmpty),
        genres: _emptyGenres(),
        onGenreTap: _commit,
        hiddenCount: hidden > 0 ? hidden : 0,
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(searchAlbumsProvider(_query).notifier).retry(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 170).floor().clamp(2, 5);
          final cellWidth =
              (constraints.maxWidth - 32 - (columns - 1) * 14) / columns;
          return GridView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: .72,
            ),
            itemCount: albums.length + 1,
            itemBuilder: (context, index) {
              if (index == albums.length) {
                return SearchLoadMore(
                  loading: state.loadingMore,
                  hasMore: state.hasMore,
                  error: state.error,
                  onLoadMore: () => ref
                      .read(searchAlbumsProvider(_query).notifier)
                      .loadMore(),
                  onRetry: () => ref
                      .read(searchAlbumsProvider(_query).notifier)
                      .loadMore(),
                );
              }
              final album = albums[index];
              return HomeAlbumCard(
                title: album.title,
                subtitle: album.artists.join(', '),
                imageUrl: album.thumbnailUrl,
                width: cellWidth,
                onTap: () => context.push('/album/${album.id}'),
              );
            },
          );
        },
      ),
    );
  }

  Widget _artistsResults() {
    final state = ref.watch(searchArtistsProvider(_query));
    final artists = ref.watch(filteredArtistsProvider(_query));
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return SearchEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudieron cargar los artistas',
        message: '${state.error}',
        actions: _catalogActions(),
        onRetry: () => ref.read(searchArtistsProvider(_query).notifier).retry(),
      );
    }
    if (artists.isEmpty) {
      final hidden = state.items.length - artists.length;
      return SearchEmptyState(
        icon: Icons.people_alt_rounded,
        title: state.items.isEmpty ? 'Sin artistas' : 'Sin coincidencias',
        message: state.items.isEmpty
            ? 'No encontramos artistas para “$_query”.'
            : 'Los filtros ocultaron todos los artistas.',
        actions: _catalogActions(includeClearFilters: state.items.isNotEmpty),
        genres: _emptyGenres(),
        onGenreTap: _commit,
        hiddenCount: hidden > 0 ? hidden : 0,
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(searchArtistsProvider(_query).notifier).retry(),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(top: 8, bottom: 110),
        itemCount: artists.length + 1,
        itemBuilder: (context, index) {
          if (index == artists.length) {
            return SearchLoadMore(
              loading: state.loadingMore,
              hasMore: state.hasMore,
              error: state.error,
              onLoadMore: () =>
                  ref.read(searchArtistsProvider(_query).notifier).loadMore(),
              onRetry: () =>
                  ref.read(searchArtistsProvider(_query).notifier).loadMore(),
            );
          }
          final artist = artists[index];
          return ListTile(
            leading: AlbumArt(url: artist.thumbnailUrl, size: 52, radius: 26),
            title: Text(artist.name, maxLines: 1),
            subtitle: artist.subscribers == null
                ? null
                : Text(artist.subscribers!),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ArtistFollowButton(
                  id: artist.id,
                  name: artist.name,
                  thumbnailUrl: artist.thumbnailUrl,
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () => context.push('/artist/${artist.id}'),
          );
        },
      ),
    );
  }

  Widget _playlistsResults() {
    final state = ref.watch(searchPlaylistsProvider(_query));
    final playlists = ref.watch(filteredPlaylistsProvider(_query));
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return SearchEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudieron cargar las playlists',
        message: '${state.error}',
        actions: _catalogActions(),
        onRetry: () =>
            ref.read(searchPlaylistsProvider(_query).notifier).retry(),
      );
    }
    if (playlists.isEmpty) {
      final hidden = state.items.length - playlists.length;
      return SearchEmptyState(
        icon: Icons.queue_music_rounded,
        title: state.items.isEmpty ? 'Sin playlists' : 'Sin coincidencias',
        message: state.items.isEmpty
            ? 'No encontramos playlists públicas para “$_query”.'
            : 'Los filtros ocultaron todas las playlists.',
        actions: _catalogActions(includeClearFilters: state.items.isNotEmpty),
        genres: _emptyGenres(),
        onGenreTap: _commit,
        hiddenCount: hidden > 0 ? hidden : 0,
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(searchPlaylistsProvider(_query).notifier).retry(),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(top: 8, bottom: 110),
        itemCount: playlists.length + 1,
        itemBuilder: (context, index) {
          if (index == playlists.length) {
            return SearchLoadMore(
              loading: state.loadingMore,
              hasMore: state.hasMore,
              error: state.error,
              onLoadMore: () =>
                  ref.read(searchPlaylistsProvider(_query).notifier).loadMore(),
              onRetry: () =>
                  ref.read(searchPlaylistsProvider(_query).notifier).loadMore(),
            );
          }
          final playlist = playlists[index];
          return ListTile(
            leading: AlbumArt(url: playlist.thumbnailUrl, size: 56, radius: 10),
            title: Text(playlist.title, maxLines: 1),
            subtitle: Text(
              [
                if (playlist.author != null) playlist.author!,
                if (playlist.itemCount != null)
                  '${playlist.itemCount} canciones',
              ].join(' · '),
              maxLines: 1,
            ),
            trailing: IconButton(
              tooltip: 'Reproducir',
              icon: const Icon(Icons.play_circle_fill_rounded),
              onPressed: () => context.push('/public-playlist/${playlist.id}'),
            ),
            onTap: () => context.push('/public-playlist/${playlist.id}'),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Biblioteca / offline
  // ---------------------------------------------------------------------------

  Widget _localBody() {
    if (_query.trim().isEmpty) {
      return EmptyState(
        icon: Icons.folder_special_rounded,
        title: 'Busca en tu biblioteca',
        message: 'Aquí se incluyen descargas, favoritos, historial y playlists locales.',
        onRetry: ref.read(effectiveOfflineProvider)
            ? null
            : () => _setScope(SearchScope.catalog),
        retryLabel: 'Buscar en el catálogo',
      );
    }
    final result = ref.watch(offlineSearchProvider(_query));
    final filters = ref.watch(searchFiltersProvider);
    final downloadedSongs = ref.watch(downloadedSongIdsProvider);
    final downloadedAlbums = ref.watch(downloadedAlbumIdsProvider);
    final downloadedArtists = ref.watch(downloadedArtistIdsProvider);
    final qualities = ref.watch(downloadQualityByIdProvider);
    final songs = result.songs
        .where(
          (entry) => filters.matchesSong(
            entry.song,
            downloadedSongIds: downloadedSongs,
            downloadQualityById: qualities,
          ),
        )
        .map((entry) => entry.song)
        .toList();
    final albums = result.albums
        .where(
          (album) =>
              !filters.onlyDownloaded || downloadedAlbums.contains(album.id),
        )
        .where(
          (album) =>
              filters.year == null ||
              filters.year!.label == 'Cualquiera' ||
              filters.year!.matches(album.year),
        )
        .toList();
    final artists = result.artists
        .where(
          (artist) =>
              !filters.onlyDownloaded || downloadedArtists.contains(artist.id),
        )
        .toList();
    final playlists = result.playlists;

    if (songs.isEmpty &&
        albums.isEmpty &&
        artists.isEmpty &&
        playlists.isEmpty) {
      final rawTotal =
          result.songs.length +
          result.albums.length +
          result.artists.length +
          result.playlists.length;
      final hidden = rawTotal;
      return SearchEmptyState(
        icon: filters.hasResultFilters
            ? Icons.filter_alt_off_rounded
            : Icons.search_off_rounded,
        title: filters.hasResultFilters
            ? 'Sin resultados con estos filtros'
            : 'Sin resultados en tu biblioteca',
        message: filters.hasResultFilters
            ? 'Ningún elemento de tu biblioteca coincide con “$_query” y los filtros activos.'
            : 'No encontramos nada para “$_query” en descargas, favoritos, historial ni playlists locales.',
        actions: _libraryActions(includeClearFilters: filters.hasResultFilters),
        genres: _emptyGenres(),
        onGenreTap: _commit,
        hiddenCount: filters.hasResultFilters && hidden > 0 ? hidden : 0,
      );
    }

    final selection = ref.watch(searchSelectionProvider);
    final widgets = <Widget>[];

    if (songs.isNotEmpty) {
      if (_tab == 0) {
        widgets.add(const _Section(title: 'Canciones'));
      }
      for (var index = 0; index < songs.length; index++) {
        if (_tab != 0 && _tab != 1) break;
        widgets.add(
          SongTile(
            songs[index],
            playQueue: songs,
            startIndex: index,
            selectionMode: selection.selecting,
            selected: selection.songIds.contains(songs[index].id),
            onSelect: () => ref
                .read(searchSelectionProvider.notifier)
                .toggle(songs[index].id),
            onLongPress: () => ref
                .read(searchSelectionProvider.notifier)
                .enter(songs[index].id),
          ),
        );
      }
    }
    if ((_tab == 0 || _tab == 2) && albums.isNotEmpty) {
      widgets.add(const _Section(title: 'Álbumes'));
      for (final album in albums) {
        widgets.add(
          ListTile(
            leading: AlbumArt(url: album.coverUrl, size: 52),
            title: Text(album.title, maxLines: 1),
            subtitle: Text(album.artist, maxLines: 1),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/album/${album.id}'),
          ),
        );
      }
    }
    if ((_tab == 0 || _tab == 3) && artists.isNotEmpty) {
      widgets.add(const _Section(title: 'Artistas'));
      for (final artist in artists) {
        widgets.add(
          ListTile(
            leading: AlbumArt(url: artist.imageUrl, size: 52, radius: 26),
            title: Text(artist.name),
            subtitle: Text('${artist.songs.length} canciones'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/artist/${artist.id}'),
          ),
        );
      }
    }
    if ((_tab == 0 || _tab == 4) && playlists.isNotEmpty) {
      widgets.add(const _Section(title: 'Playlists'));
      for (final playlist in playlists) {
        widgets.add(
          ListTile(
            leading: AlbumArt(
              url: playlist.playlist.coverUrl,
              size: 52,
              radius: 10,
            ),
            title: Text(playlist.playlist.name, maxLines: 1),
            subtitle: Text('${playlist.playlist.songs.length} canciones'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/playlist/${playlist.playlist.id}'),
          ),
        );
      }
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 8, bottom: 110),
      children: widgets,
    );
  }

  // ---------------------------------------------------------------------------
  // Letras
  // ---------------------------------------------------------------------------

  Widget _lyricsBody() {
    final progress = ref.watch(lyricsIndexControllerProvider);
    final downloads = ref.watch(downloadedSongsProvider);
    final serviceLength = ref.watch(lyricsIndexServiceProvider).length;

    if (_query.trim().isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            Icons.lyrics_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Buscar en letras',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Solo se busca en letras que ya están en tu dispositivo. '
            'Puedes indexar las letras de tus descargas ahora.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          if (progress.running) ...[
            LinearProgressIndicator(
              value: progress.total == 0 ? null : progress.fraction,
            ),
            const SizedBox(height: 8),
            Text(
              'Indexando ${progress.done} de ${progress.total}…',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () =>
                  ref.read(lyricsIndexControllerProvider.notifier).cancel(),
              child: const Text('Cancelar'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: downloads.isEmpty
                  ? null
                  : () async {
                      await ref
                          .read(lyricsIndexControllerProvider.notifier)
                          .indexDownloads(downloads);
                      if (mounted) {
                        ref.invalidate(lyricsSearchProvider);
                      }
                    },
              icon: const Icon(Icons.download_done_rounded),
              label: Text(
                downloads.isEmpty
                    ? 'No hay descargas para indexar'
                    : 'Indexar ${downloads.length} descargas',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              serviceLength == 0
                  ? 'Aún no hay letras indexadas.'
                  : '$serviceLength letras listas.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    }

    final async = ref.watch(lyricsSearchProvider(_query));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => SearchEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo buscar en letras',
        message: '$error',
        actions: [
          SearchEmptyAction(
            label: 'Ver descargas',
            icon: Icons.download_rounded,
            onTap: () => context.push('/downloads'),
          ),
        ],
        onRetry: () => ref.invalidate(lyricsSearchProvider(_query)),
      ),
      data: (hits) => hits.isEmpty
          ? SearchEmptyState(
              icon: Icons.lyrics_outlined,
              title: 'Sin coincidencias en letras',
              message: serviceLength == 0
                  ? 'Todavía no hay letras indexadas. Indexa tus descargas para poder buscar dentro de ellas.'
                  : 'Ninguna letra indexada contiene “$_query”.',
              actions: [
                if (serviceLength == 0 && downloads.isNotEmpty)
                  SearchEmptyAction(
                    label: 'Indexar ${downloads.length} descargas',
                    icon: Icons.download_done_rounded,
                    onTap: () async {
                      await ref
                          .read(lyricsIndexControllerProvider.notifier)
                          .indexDownloads(downloads);
                      if (mounted) {
                        ref.invalidate(lyricsSearchProvider);
                      }
                    },
                  )
                else
                  SearchEmptyAction(
                    label: 'Ver descargas',
                    icon: Icons.download_rounded,
                    onTap: () => context.push('/downloads'),
                  ),
                SearchEmptyAction(
                  label: 'Buscar en mi biblioteca',
                  icon: Icons.folder_special_rounded,
                  onTap: () => _setScope(SearchScope.library),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 110),
              itemCount: hits.length,
              itemBuilder: (context, index) {
                final hit = hits[index];
                return ListTile(
                  leading: AlbumArt(url: hit.song.artworkUrl, size: 52),
                  title: Text(hit.song.title, maxLines: 1),
                  subtitle: Text(
                    hit.snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Reproducir',
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: () => ref
                        .read(audioHandlerProvider)
                        .playSongs(
                          hits.map((item) => item.song).toList(),
                          startIndex: index,
                          shuffle: false,
                        ),
                  ),
                  onTap: () => ref
                      .read(audioHandlerProvider)
                      .playSongs(
                        hits.map((item) => item.song).toList(),
                        startIndex: index,
                        shuffle: false,
                      ),
                );
              },
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Selección y acciones masivas
  // ---------------------------------------------------------------------------

  List<SongModel> _currentSongs() {
    final filters = ref.read(searchFiltersProvider);
    if (filters.scope == SearchScope.lyrics) {
      return ref
              .read(lyricsSearchProvider(_query))
              .valueOrNull
              ?.map((hit) => hit.song)
              .toList() ??
          const [];
    }
    if (filters.scope == SearchScope.library ||
        ref.read(effectiveOfflineProvider)) {
      return ref
          .read(offlineSearchProvider(_query))
          .songs
          .map((entry) => entry.song)
          .toList();
    }
    switch (_tab) {
      case 0:
        return ref.read(filteredSearchAllProvider(_query)).songs;
      case 1:
        return ref.read(filteredSongsProvider(_query));
      default:
        return const [];
    }
  }

  List<SongModel> _selectedSongs() {
    final ids = ref.read(searchSelectionProvider).songIds;
    return _currentSongs().where((song) => ids.contains(song.id)).toList();
  }

  Future<void> _downloadSelected() async {
    final songs = _selectedSongs();
    if (songs.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(downloadServiceProvider)
        .downloadMany(songs, quality: AudioQuality.high);
    ref.read(searchSelectionProvider.notifier).exit();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.failed == 0
              ? '${result.completed} canciones descargadas'
              : '${result.completed} descargadas, ${result.failed} fallidas',
        ),
      ),
    );
  }

  Future<void> _queueSelected() async {
    final songs = _selectedSongs();
    if (songs.isEmpty) return;
    await ref.read(audioHandlerProvider).addSongsToQueue(songs);
    ref.read(searchSelectionProvider.notifier).exit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${songs.length} canciones añadidas a la cola')),
    );
  }

  Future<void> _favoriteSelected() async {
    final songs = _selectedSongs();
    if (songs.isEmpty) return;
    final favorites = ref
        .read(favoritesProvider)
        .map((song) => song.id)
        .toSet();
    final repository = ref.read(localRepositoryProvider);
    var added = 0;
    for (final song in songs) {
      if (favorites.contains(song.id)) continue;
      await repository.toggleFavorite(song);
      added++;
    }
    ref.invalidate(favoritesProvider);
    ref.read(searchSelectionProvider.notifier).exit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? 'Las canciones seleccionadas ya eran favoritas'
              : '$added canciones añadidas a favoritos',
        ),
      ),
    );
  }

  Future<void> _deleteHistorySelected() async {
    final songs = _selectedSongs();
    if (songs.isEmpty) return;
    await ref
        .read(localRepositoryProvider)
        .removeHistory(songs.map((song) => song.id));
    ref.read(searchSelectionProvider.notifier).exit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${songs.length} canciones eliminadas del historial de reproducción',
        ),
      ),
    );
  }

  void _openHit(SearchHit hit) {
    switch (hit.type) {
      case SearchHitType.album:
        context.push('/album/${hit.album!.id}');
      case SearchHitType.artist:
        context.push('/artist/${hit.artist!.id}');
      case SearchHitType.playlist:
        context.push('/public-playlist/${hit.playlist!.id}');
      case SearchHitType.song:
        final song = hit.song!;
        ref.read(audioHandlerProvider).playSongs([song], shuffle: false);
    }
  }
}

// -----------------------------------------------------------------------------
// Widgets auxiliares
// -----------------------------------------------------------------------------

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({
    required this.scope,
    required this.onSelected,
    required this.lyricsAvailable,
  });

  final SearchScope scope;
  final ValueChanged<SearchScope> onSelected;
  final bool lyricsAvailable;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
    child: Row(
      children: [
        for (final item in SearchScope.values) ...[
          ChoiceChip(
            label: Text(item.shortLabel),
            selected: scope == item,
            onSelected: item == SearchScope.lyrics && !lyricsAvailable
                ? null
                : (_) => onSelected(item),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.filters,
    required this.onChanged,
    required this.onClear,
  });

  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (filters.onlyDownloaded) {
      chips.add(
        _chip(
          context,
          'Descargadas',
          () => onChanged(filters.copyWith(onlyDownloaded: false)),
        ),
      );
    }
    if (filters.duration != null && filters.duration!.label != 'Cualquiera') {
      chips.add(
        _chip(
          context,
          filters.duration!.label,
          () => onChanged(filters.copyWith(clearDuration: true)),
        ),
      );
    }
    if (filters.year != null && filters.year!.label != 'Cualquiera') {
      chips.add(
        _chip(
          context,
          filters.year!.label,
          () => onChanged(filters.copyWith(clearYear: true)),
        ),
      );
    }
    if (filters.quality != null) {
      chips.add(
        _chip(
          context,
          'Calidad ${filters.quality!.label}',
          () => onChanged(filters.copyWith(clearQuality: true)),
        ),
      );
    }
    for (final genre in filters.genres) {
      chips.add(
        _chip(
          context,
          genre,
          () => onChanged(
            filters.copyWith(genres: {...filters.genres}..remove(genre)),
          ),
        ),
      );
    }
    if (filters.sort != SearchSort.relevance) {
      chips.add(
        _chip(
          context,
          filters.sort.label,
          () => onChanged(filters.copyWith(sort: SearchSort.relevance)),
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...chips,
          TextButton(onPressed: onClear, child: const Text('Limpiar')),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, VoidCallback onDeleted) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InputChip(
          label: Text(label),
          onDeleted: onDeleted,
          visualDensity: VisualDensity.compact,
        ),
      );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.manual, this.onDisable});

  final bool manual;
  final VoidCallback? onDisable;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.tertiaryContainer
        .withValues(alpha: .5),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              manual
                  ? 'Modo offline activo: mostrando tu biblioteca.'
                  : 'Sin conexión: mostrando resultados de tu biblioteca.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (onDisable != null)
            TextButton(onPressed: onDisable, child: const Text('Desactivar')),
        ],
      ),
    ),
  );
}

class _SpellingBanner extends StatelessWidget {
  const _SpellingBanner({
    required this.suggestion,
    required this.onAccept,
    required this.onSearchAnyway,
  });

  final String suggestion;
  final ValueChanged<String> onAccept;
  final VoidCallback onSearchAnyway;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer
        .withValues(alpha: .45),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            'Quizá quisiste decir:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ActionChip(
            label: Text(suggestion),
            onPressed: () => onAccept(suggestion),
          ),
          TextButton(
            onPressed: onSearchAnyway,
            child: const Text('Buscar de todos modos'),
          ),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class _SeeMoreRow extends StatelessWidget {
  const _SeeMoreRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: OutlinedButton(onPressed: onTap, child: Text(label)),
  );
}

class _BestResult extends StatelessWidget {
  const _BestResult({required this.hit, required this.onTap});
  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: .45),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              AlbumArt(
                url: hit.artworkUrl,
                size: 76,
                radius: hit.type == SearchHitType.artist ? 38 : 14,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MEJOR RESULTADO · ${hit.typeLabel.toUpperCase()}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hit.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (hit.subtitle.isNotEmpty)
                      Text(
                        hit.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ArtistFollowButton extends ConsumerWidget {
  const _ArtistFollowButton({
    required this.id,
    required this.name,
    this.thumbnailUrl,
  });

  final String id;
  final String name;
  final String? thumbnailUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (id.isEmpty) return const SizedBox.shrink();
    final following = ref.watch(isFollowingArtistProvider(id));
    return IconButton(
      tooltip: following ? 'Dejar de seguir' : 'Seguir artista',
      onPressed: () async {
        final nowFollowing = await ref
            .read(followedArtistsProvider.notifier)
            .toggle(
              FollowedArtist(
                id: id,
                name: name,
                thumbnailUrl: thumbnailUrl,
                followedAt: DateTime.now(),
              ),
            );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nowFollowing
                  ? 'Ahora sigues a $name'
                  : 'Has dejado de seguir a $name',
            ),
            duration: const Duration(milliseconds: 1400),
          ),
        );
      },
      icon: Icon(
        following
            ? Icons.person_remove_alt_1_rounded
            : Icons.person_add_alt_1_rounded,
        size: 20,
      ),
    );
  }
}

class _VoiceListeningBanner extends StatelessWidget {
  const _VoiceListeningBanner({required this.processing, required this.onStop});

  final bool processing;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            processing ? Icons.graphic_eq_rounded : Icons.mic_rounded,
            color: colors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              processing
                  ? 'Procesando el texto reconocido…'
                  : 'Escuchando… Habla ahora para buscar.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!processing)
            IconButton(
              tooltip: 'Detener dictado',
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 22),
            ),
        ],
      ),
    );
  }
}
