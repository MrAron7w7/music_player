import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/song_model.dart';
import '../../data/services/home_widget_service.dart';
import '../../providers/player_providers.dart';

/// Mantiene el widget de Android sincronizado con la reproducción.
class HomeWidgetSync extends ConsumerStatefulWidget {
  const HomeWidgetSync({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends ConsumerState<HomeWidgetSync> {
  @override
  void initState() {
    super.initState();
    unawaited(
      HomeWidgetService.init(
        onAction: (action) async {
          final handler = ref.read(audioHandlerProvider);
          switch (action) {
            case 'toggle':
              if (ref.read(isPlayingProvider).valueOrNull ?? false) {
                await handler.pause();
              } else {
                await handler.play();
              }
              break;
            case 'next':
              await handler.skipToNext();
              break;
            case 'previous':
              await handler.skipToPrevious();
              break;
          }
        },
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync(
        ref.read(currentSongProvider).valueOrNull,
        ref.read(isPlayingProvider).valueOrNull ?? false,
      );
    });
  }

  void _sync(SongModel? song, bool playing) {
    unawaited(HomeWidgetService.update(song: song, playing: playing));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SongModel?>>(currentSongProvider, (_, next) {
      _sync(next.valueOrNull, ref.read(isPlayingProvider).valueOrNull ?? false);
    });
    ref.listen<AsyncValue<bool>>(isPlayingProvider, (_, next) {
      _sync(
        ref.read(currentSongProvider).valueOrNull,
        next.valueOrNull ?? false,
      );
    });
    return widget.child;
  }
}
