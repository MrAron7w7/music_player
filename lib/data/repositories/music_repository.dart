import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song_model.dart';
import '../services/audio_cache_service.dart';
import '../services/yt_service.dart';
import '../../core/utils/song_unavailable_exception.dart';

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

  /// Resuelve el manifiesto sin lanzar: devuelve también el motivo del fallo.
  ///
  /// Un fallo de un cliente de YouTube no debe abortar la resolución completa:
  /// el llamador reintenta con la watch page y con otras calidades antes de
  /// dar la canción por no disponible. Ese era el motivo por el que todas las
  /// canciones mostraban "restringida por edad" tras la primera petición
  /// fallida.
  Future<({StreamManifest? manifest, SongUnavailableException? error})>
  _manifest(String id, {required bool requireWatchPage}) async {
    try {
      final manifest = await explode.videos.streams
          .getManifest(id, requireWatchPage: requireWatchPage)
          .timeout(const Duration(seconds: 11));
      if (manifest.audioOnly.isEmpty) {
        return (
          manifest: null,
          error: const SongUnavailableException(SongUnavailableReason.streamError),
        );
      }
      return (manifest: manifest, error: null);
    } on VideoRequiresPurchaseException catch (e) {
      return (
        manifest: null,
        error: SongUnavailableException(
          SongUnavailableReason.purchaseRequired,
          e,
        ),
      );
    } on VideoUnavailableException catch (e) {
      return (
        manifest: null,
        error: SongUnavailableException(_classifyUnavailable(e.toString()), e),
      );
    } on VideoUnplayableException catch (e) {
      return (
        manifest: null,
        error: SongUnavailableException(_classifyUnavailable(e.toString()), e),
      );
    } catch (e) {
      return (
        manifest: null,
        error: SongUnavailableException(SongUnavailableReason.apiError, e),
      );
    }
  }

  /// Clasifica el motivo de un `VideoUnavailableException` a partir de su
  /// mensaje. YouTube no expone un código de error estable, así que es una
  /// aproximación basada en el texto del error.
  ///
  /// Importante: no buscamos la subcadena `age` a secas, porque aparece dentro
  /// de palabras como `message` o `page` y marcaba como restringidas canciones
  /// que sí podían reproducirse.
  static SongUnavailableReason _classifyUnavailable(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('age-restricted') ||
        lower.contains('age restricted') ||
        lower.contains('inappropriate for some users')) {
      return SongUnavailableReason.ageRestricted;
    }
    if (lower.contains('country') ||
        lower.contains('region') ||
        lower.contains('región') ||
        lower.contains('not available in your')) {
      return SongUnavailableReason.regionRestricted;
    }
    // Muros de verificación de YouTube ("Sign in to confirm you're not a bot"
    // o "Sign in to confirm your age"): no son un fallo definitivo de la
    // canción, se reintentan y se muestra un mensaje distinto.
    if (lower.contains('sign in') ||
        lower.contains('login') ||
        lower.contains('not a bot') ||
        lower.contains('confirm your age')) {
      return SongUnavailableReason.signInRequired;
    }
    return SongUnavailableReason.unavailable;
  }

  /// Prioridad para elegir el mensaje final cuando fallan varias rutas.
  static int reasonPriority(SongUnavailableReason reason) => switch (reason) {
    SongUnavailableReason.purchaseRequired => 5,
    SongUnavailableReason.ageRestricted => 4,
    SongUnavailableReason.regionRestricted => 3,
    SongUnavailableReason.unavailable => 2,
    SongUnavailableReason.signInRequired => 1,
    SongUnavailableReason.streamError => 1,
    SongUnavailableReason.apiError => 0,
  };

  Future<Uri?> _resolveAudioStreamUrl(
    String id,
    AudioQuality quality, {
    bool requireWatchPage = false,
  }) async {
    SongUnavailableException? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      // El cliente VisionOS no necesita la watch page para resolver el
      // manifiesto, y saltarla ahorra una petición (~300 ms). Si falla, se
      // reintenta con la watch page, que es la ruta más compatible.
      var result = await _manifest(id, requireWatchPage: requireWatchPage);
      var manifest = result.manifest;
      if (result.error != null &&
          (lastError == null ||
              reasonPriority(result.error!.reason) >
                  reasonPriority(lastError.reason))) {
        lastError = result.error;
      }
      if (manifest == null && !requireWatchPage) {
        result = await _manifest(id, requireWatchPage: true);
        manifest = result.manifest;
        if (result.error != null &&
            (lastError == null ||
                reasonPriority(result.error!.reason) >
                    reasonPriority(lastError.reason))) {
          lastError = result.error;
        }
      }
      if (manifest != null) {
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
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
    if (lastError != null) throw lastError;
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
