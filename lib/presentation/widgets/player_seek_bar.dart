import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/extensions.dart';
import '../../providers/player_providers.dart';

/// Barra de progreso elegante con arrastre fluido.
///
/// Mientras se arrastra solo se actualiza el valor local; la búsqueda real se
/// hace al soltar, evitando decenas de seeks seguidos. A la derecha se muestra
/// el tiempo restante, como en Apple Music y Spotify.
class PlayerSeekBar extends ConsumerStatefulWidget {
  const PlayerSeekBar({super.key, this.fallbackDuration, this.foregroundColor});

  final Duration? fallbackDuration;
  final Color? foregroundColor;

  @override
  ConsumerState<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends ConsumerState<PlayerSeekBar> {
  double? _dragValue;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = widget.foregroundColor ?? colors.onSurface;
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(durationProvider).valueOrNull ??
        widget.fallbackDuration ??
        Duration.zero;
    final hasDuration = duration > Duration.zero;
    final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final playbackValue = position.inMilliseconds.toDouble().clamp(0.0, max);
    final value = (_dragValue ?? playbackValue).clamp(0.0, max);
    final displayed = Duration(milliseconds: value.round());
    final remaining = hasDuration
        ? Duration(milliseconds: (max - value).round())
        : Duration.zero;
    final handler = ref.read(audioHandlerProvider);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 5,
            activeTrackColor: foreground,
            inactiveTrackColor: foreground.withValues(alpha: .18),
            thumbColor: foreground,
            overlayColor: foreground.withValues(alpha: .10),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            trackShape: const RoundedRectSliderTrackShape(),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: value,
            max: max,
            onChanged: hasDuration
                ? (next) {
                    _resetTimer?.cancel();
                    setState(() => _dragValue = next);
                  }
                : null,
            onChangeEnd: hasDuration
                ? (next) {
                    final target = Duration(milliseconds: next.round());
                    unawaited(handler.seek(target));
                    _resetTimer?.cancel();
                    _resetTimer = Timer(const Duration(milliseconds: 320), () {
                      if (mounted) setState(() => _dragValue = null);
                    });
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                displayed.mmss,
                style: _timeStyle(
                  context,
                  foreground,
                  active: _dragValue != null,
                ),
              ),
              Text(
                hasDuration ? '-${remaining.mmss}' : '--:--',
                style: _timeStyle(context, foreground),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle? _timeStyle(
    BuildContext context,
    Color foreground, {
    bool active = false,
  }) {
    return Theme.of(context).textTheme.labelSmall?.copyWith(
      color: foreground.withValues(alpha: active ? .95 : .62),
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
      letterSpacing: .2,
    );
  }
}
