import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../models/song_model.dart';

class RestoredSession {
  const RestoredSession({
    required this.songs,
    required this.index,
    required this.position,
    required this.smartStartIndex,
    required this.legacy,
  });

  final List<SongModel> songs;
  final int index;
  final Duration position;
  final int? smartStartIndex;
  final bool legacy;
}

/// Persistencia de la cola y la posición de reproducción.
class SessionStore {
  SessionStore(this._settings);

  final Box _settings;
  List<Map<String, dynamic>>? _queueJson;
  bool _queueDirty = true;
  int? _lastIndex;
  int? _lastPositionMs;
  int _writeId = 0;
  Future<void> _write = Future<void>.value();

  void markQueueDirty() => _queueDirty = true;

  Future<void> persist({
    required List<SongModel> songs,
    required int index,
    required Duration position,
    required int? smartStartIndex,
    bool force = false,
  }) {
    final next = _write.then(
      (_) => _persistNow(
        songs: songs,
        index: index,
        position: position,
        smartStartIndex: smartStartIndex,
        force: force,
      ),
    );
    _write = next.catchError((_) {});
    return next;
  }

  Future<void> _persistNow({
    required List<SongModel> songs,
    required int index,
    required Duration position,
    required int? smartStartIndex,
    required bool force,
  }) async {
    if (songs.isEmpty || index < 0) return;
    final positionMs = position.inMilliseconds;
    if (!force &&
        !_queueDirty &&
        _lastIndex == index &&
        _lastPositionMs == positionMs) {
      return;
    }
    final writeId = _writeId;
    try {
      if (_queueDirty || _queueJson == null) {
        final queueJson = songs
            .map((song) => song.toJson())
            .toList(growable: false);
        _queueJson = queueJson;
        _queueDirty = false;
        if (writeId != _writeId) return;
        await _settings.put('playbackSessionQueue', {
          'queue': queueJson,
          'smartStartIndex': smartStartIndex,
        });
      }
      if (writeId != _writeId) return;
      await _settings.put('playbackSessionState', {
        'index': index,
        'positionMs': positionMs,
        'savedAt': DateTime.now().toIso8601String(),
      });
      _lastIndex = index;
      _lastPositionMs = positionMs;
      if (_settings.containsKey(AppConstants.sessionKey)) {
        await _settings.delete(AppConstants.sessionKey);
      }
    } catch (_) {
      _queueDirty = true;
      _lastIndex = null;
      _lastPositionMs = null;
    }
  }

  Future<void> clear() {
    final next = _write.then((_) async {
      _writeId++;
      _queueJson = null;
      _queueDirty = true;
      _lastIndex = null;
      _lastPositionMs = null;
      try {
        await _settings.delete('playbackSessionQueue');
        await _settings.delete('playbackSessionState');
        await _settings.delete(AppConstants.sessionKey);
      } catch (_) {}
    });
    _write = next.catchError((_) {});
    return next;
  }

  RestoredSession? restore() {
    List? rawQueue;
    var index = 0;
    var positionMs = 0;
    var legacy = false;
    int? smartStartIndex;
    final queueRaw = _settings.get('playbackSessionQueue');
    final stateRaw = _settings.get('playbackSessionState');
    if (queueRaw is Map && queueRaw['queue'] is List) {
      rawQueue = queueRaw['queue'] as List;
      smartStartIndex = (queueRaw['smartStartIndex'] as num?)?.toInt();
      if (stateRaw is Map) {
        index = (stateRaw['index'] as num?)?.toInt() ?? 0;
        positionMs = (stateRaw['positionMs'] as num?)?.toInt() ?? 0;
      }
    } else {
      final raw = _settings.get(AppConstants.sessionKey);
      if (raw is! Map || raw['queue'] is! List) return null;
      rawQueue = raw['queue'] as List;
      index = (raw['index'] as num?)?.toInt() ?? 0;
      positionMs = (raw['positionMs'] as num?)?.toInt() ?? 0;
      legacy = true;
    }

    final songs = rawQueue
        .whereType<Map>()
        .map((entry) {
          try {
            return SongModel.fromJson(Map<String, dynamic>.from(entry));
          } catch (_) {
            return null;
          }
        })
        .whereType<SongModel>()
        .toList();
    if (songs.isEmpty) return null;
    index = index.clamp(0, songs.length - 1);
    if (smartStartIndex == null ||
        smartStartIndex < 0 ||
        smartStartIndex >= songs.length) {
      smartStartIndex = null;
    }
    _queueJson = songs.map((song) => song.toJson()).toList(growable: false);
    _queueDirty = legacy;
    _lastIndex = index;
    _lastPositionMs = positionMs;
    return RestoredSession(
      songs: songs,
      index: index,
      position: Duration(milliseconds: positionMs),
      smartStartIndex: smartStartIndex,
      legacy: legacy,
    );
  }
}
