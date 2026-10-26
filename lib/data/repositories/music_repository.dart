import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song_model.dart';
import '../services/audio_cache_service.dart';
import '../services/yt_service.dart';

enum AudioQuality { high, medium, low }

class MusicRepository {
  MusicRepository(this.yt, this.explode, {this.audioCache});
  final YtService yt;
  final YoutubeExplode explode;

  /// Caché opcional de audio reciente; si falla, el streaming sigue igual.
  final AudioCacheService? audioCache;
  AudioQuality quality = AudioQuality.high;
  final Map<String, ({Uri uri, DateTime expiresAt})> _streamCache = {};
  final Map<String, Future<Uri?>> _inFlight = {};
  Future<Uri?> getAudioStreamUrl(
    String id, {
    AudioQuality quality = AudioQuality.high,
    bool forceRefresh = false,
  }) async {
    final key = '$id:${quality.name}';
    if (forceRefresh) {
      _streamCache.remove(key);
      _inFlight.remove(key);
    }
    final cached = _streamCache[key];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      // Keep frequently used entries recent while bounding memory use.
      _streamCache.remove(key);
      _streamCache[key] = cached;
      return cached.uri;
    }
    if (cached != null) _streamCache.remove(key);
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final request = _resolveAudioStreamUrl(
      id,
      quality,
    ).timeout(const Duration(seconds: 24), onTimeout: () => null);
    _inFlight[key] = request;
    try {
      final uri = await request;
      if (uri != null) {
        _streamCache[key] = (
          uri: uri,
          expiresAt: DateTime.now().add(const Duration(minutes: 20)),
        );
        while (_streamCache.length > 40) {
          _streamCache.remove(_streamCache.keys.first);
        }
      }
      return uri;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Devuelve la cadena de calidad a probar: la elegida y las inferiores.
  static List<AudioQuality> fallbackChain(AudioQuality preferred) {
    switch (preferred) {
      case AudioQuality.high:
        return const [AudioQuality.high, AudioQuality.medium, AudioQuality.low];
      case AudioQuality.medium:
        return const [AudioQuality.medium, AudioQuality.low];
      case AudioQuality.low:
        return const [AudioQuality.low];
    }
  }

  Future<Uri?> _resolveAudioStreamUrl(String id, AudioQuality quality) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // VisionOS client in the pinned youtube_explode_dart fix is currently
        // the reliable anonymous client for regular YouTube audio streams.
        final m = await explode.videos.streams
            .getManifest(id, requireWatchPage: true)
            .timeout(const Duration(seconds: 11));
        final audio = m.audioOnly;
        if (audio.isEmpty) return null;
        final streams = audio.toList()
          ..sort(
            (a, b) =>
                b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
          );
        final index = switch (quality) {
          AudioQuality.high => 0,
          AudioQuality.medium => streams.length ~/ 2,
          AudioQuality.low => streams.length - 1,
        };
        return streams[index.clamp(0, streams.length - 1)].url;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
        }
      }
    }
    return null;
  }

  void invalidateStream(String id, {AudioQuality? quality}) {
    if (quality == null) {
      _streamCache.removeWhere((key, _) => key.startsWith('$id:'));
    } else {
      _streamCache.remove('$id:${quality.name}');
    }
  }

  Future<List<SongModel>> searchSongs(String q, {int limit = 20}) =>
      yt.searchSongs(q, limit: limit);
  void dispose() {
    _streamCache.clear();
    explode.close();
  }
}
