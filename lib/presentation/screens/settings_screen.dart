import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/notification_permissions.dart';
import '../../data/repositories/music_repository.dart';
import '../../data/services/update_service.dart';
import '../../providers/cache_providers.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/update_providers.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Sistema',
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Oscuro',
  };

  Future<void> _selectTheme(BuildContext context, WidgetRef ref) async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Apariencia'),
              ),
            ),
            for (final mode in ThemeMode.values)
              ListTile(
                leading: Icon(switch (mode) {
                  ThemeMode.system => Icons.brightness_auto_rounded,
                  ThemeMode.light => Icons.light_mode_rounded,
                  ThemeMode.dark => Icons.dark_mode_rounded,
                }),
                title: Text(_themeLabel(mode)),
                trailing: AppTheme.themeMode.value == mode
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, mode),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    AppTheme.themeMode.value = selected;
    await ref
        .read(localRepositoryProvider)
        .settings
        .put('themeMode', selected.name);
  }

  Future<void> _selectQuality(
    BuildContext context,
    WidgetRef ref,
    AudioQuality quality,
  ) async {
    final selected = await showModalBottomSheet<AudioQuality>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Calidad de audio')),
            for (final option in AudioQuality.values)
              ListTile(
                leading: Icon(
                  option == AudioQuality.high
                      ? Icons.high_quality_rounded
                      : Icons.graphic_eq_rounded,
                ),
                title: Text(switch (option) {
                  AudioQuality.high => 'Alta',
                  AudioQuality.medium => 'Media',
                  AudioQuality.low => 'Baja',
                }),
                subtitle: Text(switch (option) {
                  AudioQuality.high => 'Mayor calidad de sonido',
                  AudioQuality.medium => 'Equilibrio entre calidad y datos',
                  AudioQuality.low => 'Ahorra datos móviles',
                }),
                trailing: quality == option
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    ref.read(audioQualityProvider.notifier).state = selected;
    await ref
        .read(localRepositoryProvider)
        .settings
        .put('audioQuality', selected.name);
    ref.read(musicRepositoryProvider).quality = selected;
  }

  Future<void> _notificationPermission(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final granted = await requestNotificationPermission();
    ref.invalidate(notificationPermissionProvider);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (granted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Notificaciones activadas')),
      );
      return;
    }
    final status = await notificationPermissionStatus();
    if (status.isPermanentlyDenied || status.isRestricted) {
      final opened = await openAppSettings();
      if (!opened && context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No se pudieron abrir los ajustes del sistema.'),
          ),
        );
      }
    } else if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Puedes activar las notificaciones más tarde.'),
        ),
      );
    }
  }

  Future<void> _clearSmartCache(BuildContext context, WidgetRef ref) async {
    await ref.read(appCacheProvider).clear();
    await ref.read(audioCacheProvider).clear();
    await DefaultCacheManager().emptyCache();
    clearAlbumColorCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ref.invalidate(cacheUsageProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Caché inteligente limpiada')));
  }

  Future<void> _clearAudioCache(BuildContext context, WidgetRef ref) async {
    await ref.read(audioCacheProvider).clear();
    ref.invalidate(cacheUsageProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Caché de audio eliminada')));
  }

  Future<void> _clearCovers(BuildContext context, WidgetRef ref) async {
    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ref.invalidate(cacheUsageProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Portadas en caché eliminadas')),
    );
  }

  Future<void> _clearMetadata(BuildContext context, WidgetRef ref) async {
    await ref.read(appCacheProvider).clear();
    clearAlbumColorCache();
    ref.invalidate(cacheUsageProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Metadatos en caché eliminados')),
    );
  }

  Future<void> _selectCacheLimit(BuildContext context, WidgetRef ref) async {
    const options = <(String, int)>[
      ('250 MB', 250 * 1024 * 1024),
      ('500 MB', 500 * 1024 * 1024),
      ('1 GB', 1024 * 1024 * 1024),
      ('Ilimitado', 0),
    ];
    final current = ref.read(audioCacheLimitProvider);
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Límite de caché de audio')),
            for (final option in options)
              ListTile(
                title: Text(option.$1),
                trailing: current == option.$2
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option.$2),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    ref.read(audioCacheLimitProvider.notifier).state = selected;
    await ref
        .read(localRepositoryProvider)
        .settings
        .put('audioCacheLimitBytes', selected);
    ref.read(audioCacheProvider).setLimitBytes(selected);
    await ref.read(audioCacheProvider).enforceLimit();
    ref.invalidate(cacheUsageProvider);
  }

  Future<void> _clearDownloads(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar todas las descargas'),
        content: const Text(
          'Las canciones descargadas se eliminarán del dispositivo.',
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
    if (confirmed != true) return;
    await ref.read(downloadServiceProvider).deleteAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Descargas eliminadas')));
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _reportProblem(BuildContext context) async {
    final controller = TextEditingController();
    final report = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar comentarios'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Cuéntanos qué ocurrió o qué podemos mejorar',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Copiar informe'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (report == null || report.isEmpty || !context.mounted) return;
    await Clipboard.setData(
      ClipboardData(text: 'Simple Music · Comentarios\n$report'),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe copiado al portapapeles')),
      );
    }
  }

  Future<void> _selectCrossfadeSeconds(
    BuildContext context,
    WidgetRef ref,
  ) async {
    const options = [1, 2, 3, 5, 8, 10, 12];
    final current = ref.read(crossfadeSecondsProvider);
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Duración del crossfade')),
            for (final seconds in options)
              ListTile(
                title: Text('$seconds segundos'),
                trailing: current == seconds
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, seconds),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    ref.read(crossfadeSecondsProvider.notifier).state = selected;
    await ref
        .read(localRepositoryProvider)
        .settings
        .put('crossfadeSeconds', selected);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality = ref.watch(audioQualityProvider);
    final crossfadeEnabled = ref.watch(crossfadeEnabledProvider);
    final crossfadeSeconds = ref.watch(crossfadeSecondsProvider);
    final headsetAutoplay = ref.watch(headsetAutoplayProvider);
    final offlineMode = ref.watch(offlineModeProvider);
    final wifiOnly = ref.watch(wifiOnlyDownloadsProvider);
    final downloads = ref.watch(downloadsProvider).valueOrNull ?? const [];
    final downloadBytes = downloads.fold<int>(
      0,
      (total, entry) => total + entry.bytes,
    );
    final cacheLimit = ref.watch(audioCacheLimitProvider);
    final usage = ref.watch(cacheUsageProvider).valueOrNull;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 18),
              child: Text(
                'Ajustes',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.6),
              ),
            ),
            _SettingsSection(
              title: 'APARIENCIA',
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppTheme.themeMode,
                  builder: (context, mode, _) => _SettingsTile(
                    icon: Icons.palette_outlined,
                    title: 'Tema',
                    subtitle: _themeLabel(mode),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _selectTheme(context, ref),
                  ),
                ),
              ],
            ),
            _SettingsSection(
              title: 'REPRODUCCIÓN',
              children: [
                _SettingsTile(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Calidad de audio',
                  subtitle: switch (quality) {
                    AudioQuality.high => 'Alta',
                    AudioQuality.medium => 'Media',
                    AudioQuality.low => 'Baja',
                  },
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _selectQuality(context, ref, quality),
                ),
                _SettingsTile(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Cola inteligente',
                  subtitle: 'Álbum, relacionadas y más del artista',
                  trailing: Switch.adaptive(
                    value: ref.watch(autoPlayRelatedProvider),
                    onChanged: (enabled) async {
                      ref.read(audioHandlerProvider).autoPlayRelated = enabled;
                      ref.read(autoPlayRelatedProvider.notifier).state =
                          enabled;
                      await ref
                          .read(localRepositoryProvider)
                          .settings
                          .put('autoPlayRelated', enabled);
                    },
                  ),
                ),
                _SettingsTile(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Crossfade',
                  subtitle: crossfadeEnabled
                      ? '$crossfadeSeconds s de transición suave'
                      : 'Desactivado',
                  trailing: Switch.adaptive(
                    value: crossfadeEnabled,
                    onChanged: (enabled) async {
                      ref.read(crossfadeEnabledProvider.notifier).state =
                          enabled;
                      await ref
                          .read(localRepositoryProvider)
                          .settings
                          .put('crossfadeEnabled', enabled);
                    },
                  ),
                ),
                if (crossfadeEnabled)
                  _SettingsTile(
                    icon: Icons.timer_outlined,
                    title: 'Duración del crossfade',
                    subtitle: '$crossfadeSeconds segundos',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _selectCrossfadeSeconds(context, ref),
                  ),
              ],
            ),
            _SettingsSection(
              title: 'DESCARGAS OFFLINE',
              children: [
                _SettingsTile(
                  icon: Icons.wifi_rounded,
                  title: 'Descargar solo con WiFi',
                  subtitle: 'Evita usar datos móviles al descargar',
                  trailing: Switch.adaptive(
                    value: wifiOnly,
                    onChanged: (enabled) async {
                      ref.read(wifiOnlyDownloadsProvider.notifier).state =
                          enabled;
                      await ref
                          .read(localRepositoryProvider)
                          .settings
                          .put('wifiOnlyDownloads', enabled);
                    },
                  ),
                ),
                _SettingsTile(
                  icon: Icons.cloud_off_rounded,
                  title: 'Modo offline',
                  subtitle: offlineMode
                      ? 'Solo se reproducirá contenido descargado'
                      : 'Permitir streaming con conexión',
                  trailing: Switch.adaptive(
                    value: offlineMode,
                    onChanged: (enabled) async {
                      ref.read(offlineModeProvider.notifier).state = enabled;
                      await ref
                          .read(localRepositoryProvider)
                          .settings
                          .put('offlineMode', enabled);
                    },
                  ),
                ),
                _SettingsTile(
                  icon: Icons.sd_storage_outlined,
                  title: 'Espacio usado por descargas',
                  subtitle:
                      '${downloads.length} canciones · ${_formatBytes(downloadBytes)}',
                ),
                _SettingsTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Borrar todas las descargas',
                  subtitle: 'Liberar espacio sin afectar a la caché',
                  onTap: () => _clearDownloads(context, ref),
                ),
              ],
            ),
            _SettingsSection(
              title: 'CACHÉ AVANZADA',
              children: [
                _SettingsTile(
                  icon: Icons.storage_rounded,
                  title: 'Límite de caché de audio',
                  subtitle: cacheLimit == 0
                      ? 'Ilimitado'
                      : _formatBytes(cacheLimit),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _selectCacheLimit(context, ref),
                ),
                _SettingsTile(
                  icon: Icons.data_usage_rounded,
                  title: 'Uso actual',
                  subtitle: usage == null
                      ? 'Calculando…'
                      : 'Audio ${_formatBytes(usage.audioBytes)} · '
                            'Portadas ${_formatBytes(usage.coverBytes)} · '
                            'Metadatos ${_formatBytes(usage.metadataBytes)}',
                ),
                _SettingsTile(
                  icon: Icons.audio_file_outlined,
                  title: 'Borrar solo audio',
                  subtitle: usage == null
                      ? 'Archivos de reproducción reciente'
                      : '${_formatBytes(usage.audioBytes)} en '
                            '${usage.audioFiles} archivos',
                  onTap: () => _clearAudioCache(context, ref),
                ),
                _SettingsTile(
                  icon: Icons.image_outlined,
                  title: 'Borrar solo portadas',
                  subtitle: usage == null
                      ? 'Imágenes de álbumes y playlists'
                      : _formatBytes(usage.coverBytes),
                  onTap: () => _clearCovers(context, ref),
                ),
                _SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Borrar solo metadatos',
                  subtitle: usage == null
                      ? 'Búsquedas, letras y colores'
                      : '${_formatBytes(usage.metadataBytes)} en '
                            '${usage.metadataEntries} entradas',
                  onTap: () => _clearMetadata(context, ref),
                ),
                _SettingsTile(
                  icon: Icons.cleaning_services_rounded,
                  title: 'Borrar toda la caché',
                  subtitle: 'No afecta a favoritos, playlists ni descargas',
                  onTap: () => _clearSmartCache(context, ref),
                ),
              ],
            ),
            // _SettingsSection(
            //   title: 'ESTADÍSTICAS',
            //   children: [
            //     _SettingsTile(
            //       icon: Icons.insights_rounded,
            //       title: 'Estadísticas de escucha',
            //       subtitle: 'Top canciones, artistas y minutos escuchados',
            //       trailing: const Icon(Icons.chevron_right_rounded),
            //       onTap: () => context.push('/stats'),
            //     ),
            //     _SettingsTile(
            //       icon: Icons.delete_outline_rounded,
            //       title: 'Borrar estadísticas',
            //       subtitle: 'Eliminar conteos y minutos escuchados',
            //       onTap: () => _clearStats(context, ref),
            //     ),
            //   ],
            // ),
            _SettingsSection(
              title: 'PERMISOS',
              children: [
                _SettingsTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notificaciones',
                  subtitle: ref
                      .watch(notificationPermissionProvider)
                      .when(
                        data: (granted) => granted
                            ? 'Activadas · controles de reproducción'
                            : 'Desactivadas · toca para activarlas',
                        loading: () => 'Comprobando…',
                        error: (_, _) => 'Estado no disponible',
                      ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _notificationPermission(context, ref),
                ),
              ],
            ),
            // _SettingsSection(
            //   title: 'BIBLIOTECA',
            //   children: [
            //     _SettingsTile(
            //       icon: Icons.delete_sweep_outlined,
            //       title: 'Limpiar historial',
            //       subtitle: 'Eliminar canciones escuchadas recientemente',
            //       onTap: () => _clearHistory(context, ref),
            //     ),
            //     _SettingsTile(
            //       icon: Icons.manage_search_rounded,
            //       title: 'Limpiar historial de búsquedas',
            //       subtitle: 'Eliminar las búsquedas recientes guardadas',
            //       onTap: () => _clearSearchHistory(context, ref),
            //     ),
            //     _SettingsTile(
            //       icon: Icons.cleaning_services_outlined,
            //       title: 'Limpiar caché inteligente',
            //       subtitle:
            //           'Metadatos, letras, colores, portadas y audio reciente',
            //       onTap: () => _clearSmartCache(context, ref),
            //     ),
            //   ],
            // ),

            _SettingsSection(
              title: 'COMPORTAMIENTO',
              children: [
                const _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Controles en pantalla de bloqueo',
                  subtitle: 'Activos durante la reproducción',
                ),
                _SettingsTile(
                  icon: Icons.headphones_rounded,
                  title: 'Reproducir al conectar auriculares',
                  subtitle: headsetAutoplay
                      ? 'Se reanuda al conectar auriculares o Bluetooth'
                      : 'Desactivado · pausa al desconectarlos',
                  trailing: Switch.adaptive(
                    value: headsetAutoplay,
                    onChanged: (enabled) async {
                      ref.read(headsetAutoplayProvider.notifier).state =
                          enabled;
                      await ref
                          .read(localRepositoryProvider)
                          .settings
                          .put('headsetAutoplay', enabled);
                    },
                  ),
                ),
              ],
            ),
            const _SettingsSection(
              title: 'ACTUALIZACIONES',
              children: [_UpdateCheckTile()],
            ),
            _SettingsSection(
              title: 'ACERCA DE',
              children: [
                const _SettingsTile(
                  icon: Icons.music_note_rounded,
                  title: AppConfig.appName,
                  subtitle: 'Versión ${AppConfig.displayVersion}',
                ),
                _SettingsTile(
                  icon: Icons.feedback_outlined,
                  title: 'Reportar un problema',
                  subtitle: 'Crear un informe para compartir',
                  onTap: () => _reportProblem(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Hecha para escuchar a tu manera',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateCheckTile extends ConsumerStatefulWidget {
  const _UpdateCheckTile();

  @override
  ConsumerState<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends ConsumerState<_UpdateCheckTile> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final update = await ref.read(updateServiceProvider).checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estás en la última versión (${AppConfig.displayVersion}).',
            ),
          ),
        );
        return;
      }
      await showUpdateDialog(context, update);
    } on UpdateException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo comprobar si hay actualizaciones.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: Icons.system_update_rounded,
      title: 'Buscar actualizaciones',
      subtitle: _checking
          ? 'Comprobando…'
          : 'Instalada ${AppConfig.displayVersion}',
      trailing: _checking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right_rounded),
      onTap: _checking ? null : _check,
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const Divider(height: 1, indent: 58),
                children[index],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: trailing,
    onTap: onTap,
  );
}
