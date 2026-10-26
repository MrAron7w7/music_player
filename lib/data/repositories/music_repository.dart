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
    bool requireWatchPage = false,
  }) async {
    final key = '$id:${quality.name}:${requireWatchPage ? 'watch' : 'fast'}';
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
      requireWatchPage: requireWatchPage,
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

  Future<StreamManifest?> _manifest(
    String id, {
    required bool requireWatchPage,
  }) async {
    try {
      final manifest = await explode.videos.streams
          .getManifest(id, requireWatchPage: requireWatchPage)
          .timeout(const Duration(seconds: 11));
      return manifest.audioOnly.isEmpty ? null : manifest;
    } catch (_) {
      return null;
    }
  }

  Future<Uri?> _resolveAudioStreamUrl(
    String id,
    AudioQuality quality, {
    bool requireWatchPage = false,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // El cliente VisionOS no necesita la watch page para resolver el
        // manifiesto, y saltarla ahorra una petición (~300 ms). Si falla, se
        // reintenta con la watch page, que es la ruta más compatible.
        var manifest = await _manifest(id, requireWatchPage: requireWatchPage);
        if (manifest == null && !requireWatchPage) {
          manifest = await _manifest(id, requireWatchPage: true);
        }
        if (manifest == null) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 450));
          }
          continue;
        }
        final streams = manifest.audioOnly.toList()
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
    final prefix = quality == null ? '$id:' : '$id:${quality.name}';
    _streamCache.removeWhere((key, _) => key.startsWith(prefix));
    _inFlight.removeWhere((key, _) => key.startsWith(prefix));
  }

  Future<List<SongModel>> searchSongs(String q, {int limit = 20}) =>
      yt.searchSongs(q, limit: limit);
  void dispose() {
    _streamCache.clear();
    explode.close();
  }
}
