import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_providers.dart';

/// Controles principales con jerarquía tipo Apple Music: anterior, un botón de
/// reproducción grande y siguiente, con aleatorio/repetición como secundarios.
class PlayerControls extends ConsumerWidget {
  const PlayerControls({super.key, this.foregroundColor});

  /// Permite usar controles claros sobre la portada desenfocada del reproductor.
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final foreground = foregroundColor ?? colors.onSurface;
    final handler = ref.watch(audioHandlerProvider);
    final playing = ref.watch(isPlayingProvider).valueOrNull ?? false;
    final processingState = ref.watch(
      playbackStateProvider.select(
        (state) => state.valueOrNull?.processingState,
      ),
    );
    final shuffle = ref.watch(shuffleModeProvider);
    final repeat = ref.watch(repeatModeProvider);
    final loading =
        handler.isResolvingStream ||
        processingState == AudioProcessingState.loading ||
        processingState == AudioProcessingState.buffering;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: shuffle ? 'Desactivar aleatorio' : 'Activar aleatorio',
          visualDensity: VisualDensity.compact,
          onPressed: () => handler.setShuffleMode(
            shuffle
                ? AudioServiceShuffleMode.none
                : AudioServiceShuffleMode.all,
          ),
          icon: Icon(
            Icons.shuffle_rounded,
            size: 22,
            color: foreground.withValues(alpha: shuffle ? 1 : .7),
          ),
        ),
        IconButton(
          tooltip: 'Anterior',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            HapticFeedback.selectionClick();
            handler.skipToPrevious();
          },
          icon: Icon(
            Icons.skip_previous_rounded,
            size: 44,
            color: foreground.withValues(alpha: .95),
          ),
        ),
        _PlayPauseButton(
          playing: playing,
          loading: loading,
          foreground: foreground,
          onPressed: loading
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  if (playing) {
                    handler.pause();
                  } else {
                    handler.play();
                  }
                },
        ),
        IconButton(
          tooltip: handler.nextUsesSmartQueue
              ? 'Siguiente (radio relacionada)'
              : 'Siguiente',
          visualDensity: VisualDensity.compact,
          onPressed: handler.hasNext
              ? () {
                  HapticFeedback.selectionClick();
                  handler.skipToNext();
                }
              : null,
          icon: Icon(
            Icons.skip_next_rounded,
            size: 44,
            color: foreground.withValues(
              alpha: (handler.hasNext || handler.nextUsesSmartQueue) ? .95 : .25,
            ),
          ),
        ),
        IconButton(
          tooltip: repeat == AudioServiceRepeatMode.one
              ? 'Repetir desactivado'
              : 'Cambiar repetición',
          visualDensity: VisualDensity.compact,
          onPressed: () => handler.setRepeatMode(
            repeat == AudioServiceRepeatMode.one
                ? AudioServiceRepeatMode.none
                : repeat == AudioServiceRepeatMode.all
                ? AudioServiceRepeatMode.one
                : AudioServiceRepeatMode.all,
          ),
          icon: Icon(
            repeat == AudioServiceRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            size: 22,
            color: foreground.withValues(
              alpha: repeat != AudioServiceRepeatMode.none ? 1 : .48,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.playing,
    required this.loading,
    required this.foreground,
    required this.onPressed,
  });

  final bool playing;
  final bool loading;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final iconColor =
        ThemeData.estimateBrightnessForColor(foreground) == Brightness.dark
        ? Colors.white
        : const Color(0xFF111318);
    return AnimatedScale(
      scale: loading ? .95 : 1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: Material(
        color: foreground,
        shape: const CircleBorder(),
        elevation: 14,
        shadowColor: Colors.black.withValues(alpha: .4),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 82,
            height: 82,
            child: loading
                ? Center(
                    child: SizedBox(
                      width: 27,
                      height: 27,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: iconColor,
                      ),
                    ),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(playing),
                      size: 46,
                      color: iconColor,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
