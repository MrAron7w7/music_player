import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/public_playlist_model.dart';
import '../../providers/explore_providers.dart';
import '../../providers/network_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/home_cards.dart';

class GenreScreen extends ConsumerWidget {
  const GenreScreen({super.key, required this.params, required this.title});

  final String params;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(effectiveOfflineProvider);
    final request = (params: params, title: title);
    final async = ref.watch(genrePlaylistsProvider(request));
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => EmptyState(
          icon: offline ? Icons.cloud_off_rounded : Icons.category_rounded,
          title: offline ? 'Sin conexión' : 'No se pudo cargar el género',
          message: offline
              ? 'Este género necesita conexión. Tus descargas siguen disponibles.'
              : 'No pudimos cargar las playlists de este género. Revisa tu conexión e inténtalo de nuevo.',
          onRetry: () => ref.invalidate(genrePlaylistsProvider(request)),
          retryLabel: 'Reintentar',
        ),
        data: (playlists) => playlists.isEmpty
            ? EmptyState(
                icon: Icons.queue_music_rounded,
                title: 'Sin playlists en este género',
                message: 'No encontramos playlists para este género. Prueba con otro o vuelve a intentarlo.',
                onRetry: () => ref.invalidate(genrePlaylistsProvider(request)),
                retryLabel: 'Reintentar',
              )
            : _PlaylistGrid(playlists: playlists),
      ),
    );
  }
}

class _PlaylistGrid extends StatelessWidget {
  const _PlaylistGrid({required this.playlists});

  final List<PublicPlaylistModel> playlists;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / 180).floor().clamp(2, 5);
      final cellWidth =
          (constraints.maxWidth - 32 - (columns - 1) * 14) / columns;
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: .74,
        ),
        itemCount: playlists.length,
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          return HomeAlbumCard(
            title: playlist.title,
            subtitle: playlist.author,
            imageUrl: playlist.thumbnailUrl,
            width: cellWidth,
            onTap: () => context.push('/public-playlist/${playlist.id}'),
          );
        },
      );
    },
  );
}
