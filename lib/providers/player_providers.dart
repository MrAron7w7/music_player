// AudioDeviceType es experimental en audio_session, pero es la única API
// multiplataforma para detectar la salida Bluetooth activa.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';

import '../data/services/app_cache.dart';
import '../data/services/audio_handler.dart';
import '../data/models/song_model.dart';
import 'cache_providers.dart';

final Map<String, Color> _albumColorCache = <String, Color>{};
final Map<String, Future<Color?>> _albumColorRequests =
    <String, Future<Color?>>{};

String _paletteArtworkUrl(SongModel song) {
  final uri = Uri.tryParse(song.artworkUrl ?? '');
  if (uri == null) return '';
  if (uri.host == 'i.ytimg.com' && uri.pathSegments.length >= 3) {
    final segments = [...uri.pathSegments]..[2] = 'hqdefault.jpg';
    return uri.replace(pathSegments: segments).toString();
  }
  return uri.toString().replaceFirst(
    RegExp(r'=w\d+-h\d+[^&]*'),
    '=w256-h256-l90-rj',
  );
}

Future<Color?> _extractAlbumColor(SongModel song, AppCache cache) async {
  final cached = _albumColorCache.remove(song.id);
  if (cached != null) {
    _albumColorCache[song.id] = cached;
    return cached;
  }
  final stored = cache.get<int>('color:${song.id}');
  if (stored != null) {
    final color = Color(stored);
    _albumColorCache[song.id] = color;
    return color;
  }
  final pending = _albumColorRequests[song.id];
  if (pending != null) return pending;
  final url = _paletteArtworkUrl(song);
  if (url.isEmpty) return null;
  final request = () async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url, maxWidth: 128, maxHeight: 128),
        size: const Size(64, 64),
        maximumColorCount: 8,
        runInIsolate: true,
      );
      final color =
          palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.mutedColor?.color ??
          palette.dominantColor?.color;
      if (color != null) {
        _albumColorCache[song.id] = color;
        if (_albumColorCache.length > 120) {
          _albumColorCache.remove(_albumColorCache.keys.first);
        }
        unawaited(
          cache.put(
            'color:${song.id}',
            color.toARGB32(),
            ttl: const Duration(days: 30),
            maxEntries: 300,
          ),
        );
      }
      return color;
    } catch (_) {
      return null;
    } finally {
      _albumColorRequests.remove(song.id);
    }
  }();
  _albumColorRequests[song.id] = request;
  return request;
}

/// Borra los colores en memoria y en disco (se reextraen al volver a sonar).
void clearAlbumColorCache() {
  _albumColorCache.clear();
  _albumColorRequests.clear();
}

final audioHandlerProvider = Provider<MusicAudioHandler>(
  (ref) => throw UnimplementedError('AudioHandler no inicializado'),
);
final currentSongProvider = StreamProvider<SongModel?>((ref) {
  return ref.watch(audioHandlerProvider).mediaItem.map((m) {
    if (m == null) return null;
    return SongModel(
      id: m.id,
      title: m.title,
      artists: [m.artist ?? ''],
      album: m.album,
      duration: m.duration,
      thumbnailUrl:
          m.extras?['fallbackArtworkUrl'] as String? ?? m.artUri?.toString(),
      highResThumbnailUrl: m.artUri?.toString(),
    );
  });
});

/// Extracts a small, cached palette from the current high-resolution artwork.
/// Failures are intentionally ignored so playback and the default theme remain
/// independent from image availability.
final albumArtColorProvider = FutureProvider<Color?>((ref) async {
  final song = ref.watch(
    currentSongProvider.select((state) => state.valueOrNull),
  );
  if (song == null) return null;
  return _extractAlbumColor(song, ref.watch(appCacheProvider));
});
final isPlayingProvider = StreamProvider<bool>(
  (ref) => ref.watch(audioHandlerProvider).playingStream,
);
final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);
final positionProvider = StreamProvider.autoDispose<Duration>(
  (ref) => ref.watch(audioHandlerProvider).positionStream,
);
final durationProvider = StreamProvider.autoDispose<Duration?>(
  (ref) => ref.watch(audioHandlerProvider).durationStream,
);
final queueProvider = StreamProvider<List<MediaItem>>(
  (ref) => ref.watch(audioHandlerProvider).queue,
);
final shuffleModeProvider = Provider<bool>(
  (ref) =>
      ref.watch(playbackStateProvider).valueOrNull?.shuffleMode ==
      AudioServiceShuffleMode.all,
);
final repeatModeProvider = Provider<AudioServiceRepeatMode>(
  (ref) =>
      ref.watch(playbackStateProvider).valueOrNull?.repeatMode ??
      AudioServiceRepeatMode.none,
);

/// Cola lógica completa, incluida la parte que todavía no se ha resuelto.
final queueSongsProvider = Provider<List<SongModel>>((ref) {
  ref.watch(queueProvider);
  return ref.watch(audioHandlerProvider).queueSongs;
});

final audioDevicesProvider = StreamProvider<Set<AudioDevice>>(
  (ref) => ref.watch(audioHandlerProvider).devicesStream,
);

/// Salida Bluetooth activa, si existe. Se usa para el indicador del reproductor.
final bluetoothAudioDeviceProvider = Provider<AudioDevice?>((ref) {
  final devices =
      ref.watch(audioDevicesProvider).valueOrNull ?? const <AudioDevice>{};
  for (final device in devices) {
    if (!device.isOutput) continue;
    if (device.type == AudioDeviceType.bluetoothA2dp ||
        device.type == AudioDeviceType.bluetoothSco) {
      return device;
    }
  }
  return null;
});

final playbackErrorProvider = Provider<String?>(
  (ref) => ref.watch(playbackStateProvider).valueOrNull?.errorMessage,
);

final queueIndexProvider = Provider<int?>(
  (ref) => ref.watch(playbackStateProvider).valueOrNull?.queueIndex,
);
