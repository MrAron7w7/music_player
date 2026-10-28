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

  bool get _autoScrollPaused =>
      _pauseAutoScrollUntil != null &&
      DateTime.now().isBefore(_pauseAutoScrollUntil!);

  static int _startMs(Map<String, dynamic> line) {
    final start = line['startMs'];
    return start is num ? start.toInt() : int.tryParse('$start') ?? 0;
  }

  /// Calcula el índice activo partiendo del índice previo, avanzando o
  /// retrocediendo hasta encontrar la línea correcta, en lugar de escanear
  /// todas las líneas en cada tick.
  int _activeLineIncremental(
    List<Map<String, dynamic>> lines,
    int positionMs,
    int previous,
  ) {
    if (lines.isEmpty) return -1;
    var i = previous.clamp(-1, lines.length - 1);
    while (i + 1 < lines.length && _startMs(lines[i + 1]) <= positionMs) {
      i++;
    }
    while (i >= 0 && _startMs(lines[i]) > positionMs) {
      i--;
    }
    return i;
  }

  void _scheduleScroll() {
    _scrollScheduled = true;
  }

  bool _scrollScheduled = false;

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
      final index = _activeLineIncremental(_timedLines, positionMs, _activeIndex);
      if (index != _activeIndex) {
        _activeIndex = index;
        _lastScrolledLine = index;
        if (mounted) setState(() {});
        if (!_autoScrollPaused) _scheduleScroll();
      }
    });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      minChildSize: .55,
      maxChildSize: .97,
      builder: (context, sheetController) {
        if (_scrollScheduled && _activeIndex >= 0) {
          _scrollScheduled = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scrollToLine(_activeIndex, sheetController);
          });
        }
        return ClipRRect(
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
                          ? _activeLineIncremental(lines, positionMs, -1)
                          : -1;
                      _timed = timed;
                      _timedLines = lines;
                      _activeIndex = active;
                      final hasSource = data['source'] != null &&
                          '${data['source']}'.trim().isNotEmpty;

                      if (timed &&
                          active >= 0 &&
                          active != _lastScrolledLine &&
                          !_autoScrollPaused) {
                        _lastScrolledLine = active;
                        _scheduleScroll();
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
                          child: ListView.builder(
                            controller: sheetController,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(28, 26, 28, 120),
                            itemCount:
                                (timed ? 1 : 0) +
                                lines.length +
                                (hasSource ? 2 : 1),
                            itemBuilder: (context, index) {
                              if (timed && index == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 22),
                                  child: Row(
                                    children: [_SyncBadge(accent: accent)],
                                  ),
                                );
                              }
                              var lineIndex = index - (timed ? 1 : 0);
                              if (lineIndex < lines.length) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (lineIndex > 0)
                                      const SizedBox(height: 18),
                                    _LyricLine(
                                      text:
                                          '${lines[lineIndex]['text'] ?? ''}',
                                      timed: timed,
                                      active: lineIndex == active,
                                      distance:
                                          timed ? (lineIndex - active).abs() : 0,
                                      accent: accent,
                                      onTap: timed
                                          ? () {
                                              final start =
                                                  lines[lineIndex]['startMs'];
                                              final startMs = start is num
                                                  ? start.toInt()
                                                  : int.tryParse('$start');
                                              if (startMs == null) return;
                                              _pauseAutoScrollUntil =
                                                  DateTime.now()
                                                      .add(const Duration(
                                                          seconds: 3));
                                              ref
                                                  .read(audioHandlerProvider)
                                                  .seek(
                                                    Duration(
                                                        milliseconds:
                                                            startMs),
                                                  );
                                            }
                                          : null,
                                    ),
                                  ],
                                );
                              }
                              lineIndex -= lines.length;
                              if (lineIndex == 0) {
                                return const SizedBox(height: 18);
                              }
                              if (hasSource && lineIndex == 1) {
                                return Center(
                                  child: Text(
                                    'Letra de ${data['source']}',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color: colors.onSurfaceVariant
                                          .withValues(alpha: .6),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
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
      );
    },
  );
  }

  void _scrollToLine(int index, ScrollController controller) {
    if (index < 0) return;
    const itemHeight = 56.0;
    final viewport = controller.position.viewportDimension;
    final maxExtent = controller.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    var target = (index * itemHeight).toDouble();
    target = (target - viewport * 0.35).clamp(0.0, maxExtent);
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
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
