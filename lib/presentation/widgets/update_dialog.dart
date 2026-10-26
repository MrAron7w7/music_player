import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_config.dart';
import '../../data/models/app_update_info.dart';

Future<void> showUpdateDialog(BuildContext context, AppUpdateInfo update) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpdateDialog(update: update),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});

  final AppUpdateInfo update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _opening = false;

  Future<void> _openDownload() async {
    if (_opening) return;
    setState(() => _opening = true);
    final uri = Uri.tryParse(widget.update.downloadUrl);
    var launched = false;
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (!mounted) return;
    if (launched) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _opening = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('No se pudo abrir el navegador. Inténtalo de nuevo.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final update = widget.update;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 430),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.surface, colors.surfaceContainerHigh],
          ),
          border: Border.all(color: colors.onSurface.withValues(alpha: .07)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .38),
              blurRadius: 48,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors.primary, colors.secondary],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: .28),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      color: colors.onPrimary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nueva actualización disponible',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.5,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Hay una versión más reciente de ${AppConfig.appName}.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colors.onSurface.withValues(alpha: .06),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _VersionColumn(
                        label: 'INSTALADA',
                        value: AppConfig.displayVersion,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: _VersionColumn(
                        label: 'DISPONIBLE',
                        value: update.displayVersion,
                        highlight: true,
                      ),
                    ),
                  ],
                ),
              ),
              if (update.notes.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Novedades',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.onSurface.withValues(alpha: .06),
                    ),
                  ),
                  child: Text(
                    update.notes,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _opening
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Más tarde'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _opening ? null : _openDownload,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _opening
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_new_rounded, size: 19),
                      label: Text(_opening ? 'Abriendo…' : 'Actualizar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Se abrirá el navegador para descargar el APK.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant.withValues(alpha: .85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionColumn extends StatelessWidget {
  const _VersionColumn({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: style.labelSmall?.copyWith(
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
            color: highlight ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: highlight ? colors.primary : colors.onSurface,
          ),
        ),
      ],
    );
  }
}
