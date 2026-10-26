import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/music_providers.dart';
import '../../providers/player_providers.dart';
import 'album_art.dart';

/// Letras a pantalla completa con resaltado sincronizado, auto-scroll suave y
/// una estética inspirada en Apple Music.
class LyricsSheet extends ConsumerStatefulWidget {
  const LyricsSheet({
    super.key,
    required this.songId,
    required this.title,
    this.artist = '',
    this.artworkUrl,
    this.fallbackArtworkUrl,
  });

  final String songId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? fallbackArtworkUrl;

  @override
  ConsumerState<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends ConsumerState<LyricsSheet> {
  int _lastScrolledLine = -1;
  int _activeIndex = -1;
  bool _timed = false;
  List<Map<String, dynamic>> _timedLines = const [];
  DateTime? _pauseAutoScrollUntil;
  final Map<int, GlobalKey> _lineKeys = {};

  bool get _autoScrollPaused =>
      _pauseAutoScrollUntil != null &&
      DateTime.now().isBefore(_pauseAutoScrollUntil!);

  int _activeLine(List<Map<String, dynamic>> lines, int positionMs) {
    var active = -1;
    for (var i = 0; i < lines.length; i++) {
      final start = lines[i]['startMs'];
      final startMs = start is num ? start.toInt() : int.tryParse('$start');
      if (startMs != null && startMs <= positionMs) active = i;
    }
    return active;
  }

  void _onUserScroll(ScrollNotification notification) {
    final isUserDrag =
        (notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null);
    if (isUserDrag) {
      _pauseAutoScrollUntil = DateTime.now().add(const Duration(seconds: 4));
    }
  }

  void _retry() {
    _lastScrolledLine = -1;
    ref.invalidate(songLyricsProvider(widget.songId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent =
        ref.watch(albumArtColorProvider.select((state) => state.valueOrNull)) ??
        colors.primary;
    final lyrics = ref.watch(songLyricsProvider(widget.songId));

    // Solo se reconstruye cuando cambia la línea activa, no en cada tick de
    // posición. Mantiene el desplazamiento fluido incluso con letras largas.
    ref.listen<AsyncValue<Duration>>(positionProvider, (previous, next) {
      final positionMs = next.valueOrNull?.inMilliseconds;
      if (positionMs == null || !_timed || _timedLines.isEmpty) return;
      final index = _activeLine(_timedLines, positionMs);
      if (index != _activeIndex) {
        _activeIndex = index;
        if (mounted) setState(() {});
      }
    });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      minChildSize: .55,
      maxChildSize: .97,
      builder: (context, sheetController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(colors.surface, accent, .18)!,
                  colors.surface.withValues(alpha: .98),
                ],
              ),
              border: Border(
                top: BorderSide(color: colors.onSurface.withValues(alpha: .09)),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
                  child: Row(
                    children: [
                      AlbumArt(
                        url: widget.artworkUrl,
                        fallbackUrl: widget.fallbackArtworkUrl,
                        size: 44,
                        radius: 10,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LETRAS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.5,
                                color: accent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.2,
                              ),
                            ),
                            if (widget.artist.isNotEmpty)
                              Text(
                                widget.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar letras',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: lyrics.when(
                    loading: () => const _LyricsLoading(),
                    error: (_, _) => _LyricsUnavailable(onRetry: _retry),
                    data: (data) {
                      if (data == null || data['lines'] is! List) {
                        return _LyricsUnavailable(onRetry: _retry);
                      }
                      final lines = (data['lines'] as List)
                          .whereType<Map>()
                          .map((line) => Map<String, dynamic>.from(line))
                          .toList();
                      if (lines.isEmpty) {
                        return _LyricsUnavailable(onRetry: _retry);
                      }
                      final timed = data['timed'] == true;
                      final positionMs =
                          ref
                              .read(positionProvider)
                              .valueOrNull
                              ?.inMilliseconds ??
                          0;
                      final active = timed
                          ? _activeLine(lines, positionMs)
                          : -1;
                      _timed = timed;
                      _timedLines = lines;
                      _activeIndex = active;

                      if (timed &&
                          active >= 0 &&
                          active != _lastScrolledLine &&
                          !_autoScrollPaused) {
                        _lastScrolledLine = active;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          final lineContext = _lineKeys[active]?.currentContext;
                          if (lineContext != null) {
                            Scrollable.ensureVisible(
                              lineContext,
                              alignment: .42,
                              duration: const Duration(milliseconds: 620),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        });
                      }

                      return NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          _onUserScroll(notification);
                          return false;
                        },
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0, .07, .88, 1],
                          ).createShader(rect),
                          child: ListView(
                            controller: sheetController,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(28, 26, 28, 120),
                            children: [
                              if (timed)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 22),
                                  child: Row(
                                    children: [_SyncBadge(accent: accent)],
                                  ),
                                ),
                              for (
                                var index = 0;
                                index < lines.length;
                                index++
                              ) ...[
                                if (index > 0) const SizedBox(height: 18),
                                _LyricLine(
                                  key: _lineKeys.putIfAbsent(
                                    index,
                                    GlobalKey.new,
                                  ),
                                  text: '${lines[index]['text'] ?? ''}',
                                  timed: timed,
                                  active: index == active,
                                  distance: timed ? (index - active).abs() : 0,
                                  accent: accent,
                                  onTap: timed
                                      ? () {
                                          final start = lines[index]['startMs'];
                                          final startMs = start is num
                                              ? start.toInt()
                                              : int.tryParse('$start');
                                          if (startMs == null) return;
                                          _pauseAutoScrollUntil = DateTime.now()
                                              .add(const Duration(seconds: 3));
                                          ref
                                              .read(audioHandlerProvider)
                                              .seek(
                                                Duration(milliseconds: startMs),
                                              );
                                        }
                                      : null,
                                ),
                              ],
                              const SizedBox(height: 18),
                              if (data['source'] != null &&
                                  '${data['source']}'.trim().isNotEmpty)
                                Center(
                                  child: Text(
                                    'Letra de ${data['source']}',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant.withValues(
                                        alpha: .6,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: .24)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.graphic_eq_rounded, size: 13, color: accent),
        const SizedBox(width: 5),
        Text(
          'SINCRONIZADA',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
            fontSize: 9,
          ),
        ),
      ],
    ),
  );
}

class _LyricLine extends StatelessWidget {
  const _LyricLine({
    super.key,
    required this.text,
    required this.timed,
    required this.active,
    required this.distance,
    required this.accent,
    this.onTap,
  });

  final String text;
  final bool timed;
  final bool active;
  final int distance;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final alpha = !timed
        ? .84
        : active
        ? 1.0
        : distance == 1
        ? .52
        : distance <= 3
        ? .30
        : .18;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall!.copyWith(
          height: 1.3,
          fontSize: active ? 29 : 23,
          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: active ? -.5 : -.1,
          color: colors.onSurface.withValues(alpha: alpha),
          shadows: active
              ? [Shadow(color: accent.withValues(alpha: .38), blurRadius: 22)]
              : null,
        ),
        child: Text(text),
      ),
    );
  }
}

class _LyricsLoading extends StatelessWidget {
  const _LyricsLoading();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        const SizedBox(height: 16),
        Text(
          'Buscando letras…',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _LyricsUnavailable extends StatelessWidget {
  const _LyricsUnavailable({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: .1),
              ),
              child: Icon(
                Icons.lyrics_outlined,
                size: 34,
                color: colors.primary.withValues(alpha: .8),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Aún no hay letras para esta canción',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Puede que todavía no estén disponibles. Vuelve a intentarlo en un momento.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Volver a intentar'),
            ),
          ],
        ),
      ),
    );
  }
}
