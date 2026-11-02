import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/listening_stats_service.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/player_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
        actions: [
          IconButton(
            tooltip: 'Borrar estadísticas',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Borrar estadísticas'),
                  content: const Text(
                    'Se eliminarán los conteos y los minutos escuchados.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Borrar'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(statsServiceProvider).clear();
                ref.invalidate(statsProvider);
              }
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text('No se pudieron cargar las estadísticas: $error'),
          ),
        ),
        data: (snapshot) {
          final empty = snapshot.totalPlays == 0 && snapshot.recent.isEmpty;
          if (empty) {
            return const EmptyState(
              icon: Icons.insights_rounded,
              title: 'Aún no hay estadísticas',
              message: 'Escucha algunas canciones y aquí verás tus artistas, canciones y minutos favoritos.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.primaryContainer,
                      colors.secondaryContainer.withValues(alpha: .55),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded, color: colors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'TU TIEMPO ESCUCHANDO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      snapshot.totalLabel,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.4,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      '${snapshot.totalPlays} reproducciones · '
                      '${snapshot.topSongs.length} canciones diferentes',
                      style: TextStyle(
                        color: colors.onPrimaryContainer.withValues(alpha: .75),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _PeriodCard(
                            label: 'Hoy',
                            value: snapshot.todayLabel,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PeriodCard(
                            label: 'Semana',
                            value: snapshot.weekLabel,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PeriodCard(
                            label: 'Mes',
                            value: snapshot.monthLabel,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (snapshot.topSongs.isNotEmpty) ...[
                const _SectionTitle('Tus canciones más escuchadas'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < snapshot.topSongs.take(10).length;
                        index++
                      ) ...[
                        if (index > 0) const Divider(height: 1, indent: 68),
                        _SongStatTile(
                          rank: index + 1,
                          stat: snapshot.topSongs[index],
                          onTap: () async {
                            await ref
                                .read(audioHandlerProvider)
                                .playSongs(
                                  snapshot.topSongs
                                      .map((stat) => stat.song)
                                      .toList(),
                                  startIndex: index,
                                  shuffle: false,
                                );
                            if (!context.mounted) return;
                            context.push('/now-playing');
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (snapshot.topArtists.isNotEmpty) ...[
                const _SectionTitle('Artistas que más escuchas'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < snapshot.topArtists.take(6).length;
                        index++
                      ) ...[
                        if (index > 0) const Divider(height: 1, indent: 68),
                        _ArtistStatTile(
                          rank: index + 1,
                          stat: snapshot.topArtists[index],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (snapshot.recent.isNotEmpty) ...[
                const _SectionTitle('Escuchado recientemente'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < snapshot.recent.take(20).length;
                        index++
                      ) ...[
                        if (index > 0) const Divider(height: 1, indent: 68),
                        _RecentTile(
                          entry: snapshot.recent[index],
                          onTap: () async {
                            await ref
                                .read(audioHandlerProvider)
                                .playSongs(
                                  snapshot.recent
                                      .map((entry) => entry.song)
                                      .toList(),
                                  startIndex: index,
                                  shuffle: false,
                                );
                            if (!context.mounted) return;
                            context.push('/now-playing');
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _SongStatTile extends StatelessWidget {
  const _SongStatTile({
    required this.rank,
    required this.stat,
    required this.onTap,
  });
  final int rank;
  final SongStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final minutes = stat.seconds ~/ 60;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: rank <= 3 ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          AlbumArt(
            url: stat.song.artworkUrl,
            fallbackUrl: stat.song.thumbnailUrl,
            size: 46,
            radius: 10,
          ),
        ],
      ),
      title: Text(
        stat.song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        stat.song.artists.join(', '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${stat.plays} ${stat.plays == 1 ? 'vez' : 'veces'}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          Text(
            minutes > 0 ? '${minutes}min' : '${stat.seconds}s',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ArtistStatTile extends StatelessWidget {
  const _ArtistStatTile({required this.rank, required this.stat});
  final int rank;
  final ArtistStat stat;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final minutes = stat.seconds ~/ 60;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: rank <= 3 ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 23,
            backgroundColor: colors.primaryContainer,
            child: Text(
              stat.name.isEmpty ? '?' : stat.name[0].toUpperCase(),
              style: TextStyle(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      title: Text(
        stat.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text('${stat.plays} reproducciones'),
      trailing: Text(
        minutes > 0 ? '${minutes}min' : '${stat.seconds}s',
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.entry, required this.onTap});
  final RecentPlay entry;
  final VoidCallback onTap;

  String _relative(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inMinutes < 1) return 'Ahora mismo';
    if (difference.inMinutes < 60) return 'Hace ${difference.inMinutes} min';
    if (difference.inHours < 24 && now.day == time.day) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return 'Hoy · $hour:$minute';
    }
    if (difference.inDays < 2) return 'Ayer';
    if (difference.inDays < 7) return 'Hace ${difference.inDays} días';
    return '${time.day}/${time.month}/${time.year}';
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    leading: AlbumArt(
      url: entry.song.artworkUrl,
      fallbackUrl: entry.song.thumbnailUrl,
      size: 46,
      radius: 10,
    ),
    title: Text(
      entry.song.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${entry.song.artists.join(', ')} · ${_relative(entry.playedAt)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: onTap,
  );
}
