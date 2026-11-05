import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/search_models.dart';
import '../../providers/search_providers.dart';

Future<void> showSearchFilterSheet(
  BuildContext context,
  WidgetRef ref, {
  bool lyricsScopeEnabled = true,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => _SearchFilterSheet(
    initial: ref.read(searchFiltersProvider),
    lyricsScopeEnabled: lyricsScopeEnabled,
    onApply: (filters) {
      ref.read(searchFiltersProvider.notifier).state = filters;
      Navigator.pop(context);
    },
  ),
);

class _SearchFilterSheet extends StatefulWidget {
  const _SearchFilterSheet({
    required this.initial,
    required this.onApply,
    required this.lyricsScopeEnabled,
  });

  final SearchFilters initial;
  final ValueChanged<SearchFilters> onApply;
  final bool lyricsScopeEnabled;

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late SearchFilters draft = widget.initial;
  final _genreController = TextEditingController();

  @override
  void dispose() {
    _genreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .82,
      maxChildSize: .95,
      minChildSize: .5,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Filtros de búsqueda',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _genreController.clear();
                    setState(() => draft = const SearchFilters());
                  },
                  child: const Text('Limpiar'),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                _label(context, 'Ámbito'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final scope in SearchScope.values)
                      ChoiceChip(
                        label: Text(scope.label),
                        selected: draft.scope == scope,
                        onSelected: scope == SearchScope.lyrics &&
                                !widget.lyricsScopeEnabled
                            ? null
                            : (_) => setState(
                                () => draft = draft.copyWith(scope: scope),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: draft.onlyDownloaded,
                  title: const Text('Solo descargadas'),
                  subtitle: const Text(
                    'Aplica a canciones, álbumes y artistas presentes en descargas.',
                  ),
                  onChanged: (value) => setState(
                    () => draft = draft.copyWith(onlyDownloaded: value),
                  ),
                ),
                _label(context, 'Calidad de descarga'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Cualquiera'),
                      selected: draft.quality == null,
                      onSelected: (_) => setState(
                        () => draft = draft.copyWith(clearQuality: true),
                      ),
                    ),
                    for (final quality in DownloadQualityFilter.values)
                      ChoiceChip(
                        label: Text(quality.label),
                        selected: draft.quality == quality,
                        onSelected: (_) => setState(
                          () => draft = draft.copyWith(quality: quality),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _label(context, 'Duración'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final range in DurationRange.options)
                      ChoiceChip(
                        label: Text(range.label),
                        selected: draft.duration == range,
                        onSelected: (_) => setState(
                          () => draft = range.label == 'Cualquiera'
                              ? draft.copyWith(clearDuration: true)
                              : draft.copyWith(duration: range),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _label(context, 'Año'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final range in YearRange.options)
                      ChoiceChip(
                        label: Text(range.label),
                        selected: draft.year == range,
                        onSelected: (_) => setState(
                          () => draft = range.label == 'Cualquiera'
                              ? draft.copyWith(clearYear: true)
                              : draft.copyWith(year: range),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _label(context, 'Género'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _genreController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (value) => _addGenre(value),
                        decoration: const InputDecoration(
                          hintText: 'Añadir género (ej. rock)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Añadir género',
                      onPressed: () => _addGenre(_genreController.text),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                if (draft.genres.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final genre in draft.genres)
                        InputChip(
                          label: Text(genre),
                          onDeleted: () {
                            final next = {...draft.genres}..remove(genre);
                            setState(
                              () => draft = draft.copyWith(genres: next),
                            );
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                _label(context, 'Ordenar por'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sort in SearchSort.values)
                      ChoiceChip(
                        label: Text(sort.label),
                        selected: draft.sort == sort,
                        onSelected: (_) =>
                            setState(() => draft = draft.copyWith(sort: sort)),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => widget.onApply(draft),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Aplicar filtros'),
                ),
                const SizedBox(height: 12),
                Text(
                  'El filtro de género en el catálogo refina la consulta. En tu '
                  'biblioteca solo se aplica cuando la canción tiene género '
                  'conocido, así que nunca oculta resultados sin metadatos.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  void _addGenre(String value) {
    final genre = value.trim();
    if (genre.isEmpty) return;
    final genres = {...draft.genres, genre};
    _genreController.clear();
    setState(() => draft = draft.copyWith(genres: genres));
  }
}
