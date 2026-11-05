import 'package:flutter/material.dart';

/// Acción contextual mostrada en un estado vacío del buscador.
class SearchEmptyAction {
  const SearchEmptyAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// Estado vacío del buscador con salidas concretas: buscar en la biblioteca,
/// abrir descargas/favoritos, quitar filtros o desactivar el modo offline.
class SearchEmptyState extends StatelessWidget {
  const SearchEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actions = const <SearchEmptyAction>[],
    this.genres = const <String>[],
    this.onGenreTap,
    this.hiddenCount = 0,
    this.onRetry,
    this.retryLabel = 'Reintentar',
  });

  final IconData icon;
  final String title;
  final String? message;
  final List<SearchEmptyAction> actions;
  final List<String> genres;
  final ValueChanged<String>? onGenreTap;
  final int hiddenCount;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: .1),
              ),
              child: Icon(icon, size: 34, color: colors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant.withValues(alpha: .9),
                  height: 1.35,
                ),
              ),
            ],
            if (hiddenCount > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hiddenCount == 1
                      ? '1 resultado oculto por los filtros'
                      : '$hiddenCount resultados ocultos por los filtros',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var index = 0; index < actions.length; index++)
                    if (index == 0)
                      FilledButton.tonalIcon(
                        onPressed: actions[index].onTap,
                        icon: Icon(actions[index].icon, size: 19),
                        label: Text(actions[index].label),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: actions[index].onTap,
                        icon: Icon(actions[index].icon, size: 19),
                        label: Text(actions[index].label),
                      ),
                ],
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: Text(retryLabel),
              ),
            ],
            if (genres.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                'Prueba con un género',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final genre in genres.take(6))
                    ActionChip(
                      label: Text(genre),
                      onPressed: onGenreTap == null
                          ? null
                          : () => onGenreTap!(genre),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
