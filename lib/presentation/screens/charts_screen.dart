import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/explore_models.dart';
import '../../providers/explore_providers.dart';
import '../../providers/network_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';

const _countries = <({String code, String label})>[
  (code: 'ZZ', label: 'Global'),
  (code: 'US', label: 'Estados Unidos'),
  (code: 'ES', label: 'España'),
  (code: 'MX', label: 'México'),
  (code: 'AR', label: 'Argentina'),
  (code: 'CO', label: 'Colombia'),
  (code: 'CL', label: 'Chile'),
  (code: 'PE', label: 'Perú'),
  (code: 'BR', label: 'Brasil'),
  (code: 'GB', label: 'Reino Unido'),
  (code: 'FR', label: 'Francia'),
  (code: 'DE', label: 'Alemania'),
  (code: 'IT', label: 'Italia'),
  (code: 'JP', label: 'Japón'),
  (code: 'KR', label: 'Corea del Sur'),
];

class ChartsScreen extends ConsumerWidget {
  const ChartsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final country = ref.watch(chartCountryProvider);
    final async = ref.watch(chartsProvider);
    final selectedLabel =
        _countries
            .where((item) => item.code == country)
            .map((item) => item.label)
            .firstOrNull ??
        'Global';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Charts'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'País',
            initialValue: country,
            onSelected: (value) =>
                ref.read(chartCountryProvider.notifier).state = value,
            itemBuilder: (context) => [
              for (final item in _countries)
                PopupMenuItem(value: item.code, child: Text(item.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(selectedLabel),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: ref.watch(effectiveOfflineProvider)
              ? Icons.cloud_off_rounded
              : Icons.bar_chart_rounded,
          title: ref.watch(effectiveOfflineProvider)
              ? 'Sin conexión'
              : 'No se pudieron cargar los charts',
          message: ref.watch(effectiveOfflineProvider)
              ? 'Los charts necesitan conexión. Prueba con tus descargas.'
              : '$error',
          onRetry: () => ref.invalidate(chartsProvider),
        ),
        data: (charts) => charts.isEmpty
            ? const EmptyState(
                icon: Icons.bar_chart_rounded,
                title: 'Sin datos para este país',
              )
            : _ChartsBody(charts: charts),
      ),
    );
  }
}

class _ChartsBody extends StatelessWidget {
  const _ChartsBody({required this.charts});

  final ChartsSnapshot charts;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 100),
    children: [
      if (charts.playlists.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text(
            'Listas destacadas',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        for (final playlist in charts.playlists)
          ListTile(
            leading: AlbumArt(url: playlist.thumbnailUrl, size: 52),
            title: Text(playlist.title, maxLines: 1),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/public-playlist/${playlist.id}'),
          ),
      ],
      if (charts.artists.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            'Artistas en tendencia',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        for (final artist in charts.artists)
          ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (artist.rank != null)
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${artist.rank}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                AlbumArt(url: artist.thumbnailUrl, size: 48, radius: 24),
              ],
            ),
            title: Text(artist.name, maxLines: 1),
            subtitle: artist.subscribers == null
                ? null
                : Text(artist.subscribers!),
            onTap: () => context.push('/artist/${artist.id}'),
          ),
      ],
    ],
  );
}
