import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/home_models.dart';
import '../../data/models/song_model.dart';
import '../../data/repositories/music_repository.dart' show AudioQuality;
import '../../providers/downloads_providers.dart';
import '../../providers/home_feed_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/home_cards.dart';
import '../widgets/song_tile.dart';

class MixDetailScreen extends ConsumerWidget {
  const MixDetailScreen({super.key, required this.mixId});

  final String mixId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dailyMixesProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SafeArea(
          child: Stack(
            children: [
              EmptyState(
                icon: Icons.auto_awesome_rounded,
                title: 'No se pudo abrir la mezcla',
                message: '$error',
                onRetry: () => ref.invalidate(dailyMixesProvider),
              ),
              const Positioned(left: 4, top: 4, child: BackButton()),
            ],
          ),
        ),
        data: (mixes) {
          final mix = mixes.where((item) => item.id == mixId).firstOrNull;
          if (mix == null) {
            return const SafeArea(
              child: Stack(
                children: [
                  EmptyState(
                    icon: Icons.auto_awesome_rounded,
                    title: 'La mezcla ya no está disponible',
                    message: 'Los mixes cambian cada día.',
                  ),
                  Positioned(left: 4, top: 4, child: BackButton()),
                ],
              ),
            );
          }
          return _MixContent(mix: mix);
        },
      ),
    );
  }
}

class _MixContent extends ConsumerWidget {
  const _MixContent({required this.mix});

  final DailyMix mix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final songs = mix.songs;
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          leading: const BackButton(),
          flexibleSpace: FlexibleSpaceBar(
            background: Padding(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: MixArtwork(urls: mix.coverUrls, size: 160, radius: 22),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mix.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mix.isOffline ? '${mix.subtitle} · Sin conexión' : mix.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(audioHandlerProvider)
                          .playSongs(songs, shuffle: false),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Reproducir'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(audioHandlerProvider)
                          .playSongs(songs, shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Aleatorio'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _download(context, ref, songs),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Descargar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(audioHandlerProvider)
                            .addSongsToQueue(songs);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${songs.length} canciones añadidas a la cola',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.queue_music_rounded),
                      label: const Text('A la cola'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _savePlaylist(context, ref, songs),
                      icon: const Icon(Icons.library_add_rounded),
                      label: const Text('Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) =>
              SongTile(songs[index], playQueue: songs, startIndex: index),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    List<SongModel> songs,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(downloadServiceProvider)
        .downloadMany(songs, quality: AudioQuality.high);
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

  Future<void> _savePlaylist(
    BuildContext context,
    WidgetRef ref,
    List<SongModel> songs,
  ) async {
    final created = await ref
        .read(localRepositoryProvider)
        .createPlaylist(
          '${mix.title} · ${DateTime.now().day}/${DateTime.now().month}',
          description: 'Mezcla diaria guardada desde Inicio',
          songs: songs,
        );
    ref.invalidate(playlistsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('“${created.name}” guardada'),
        action: SnackBarAction(
          label: 'Ver',
          onPressed: () => context.push('/playlist/${created.id}'),
        ),
      ),
    );
  }
}
