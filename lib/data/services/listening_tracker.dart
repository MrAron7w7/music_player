import 'dart:async';

import '../models/song_model.dart';
import 'listening_stats_service.dart';

/// Registra reproducciones y tiempo escuchado sin involucrar al handler.
class ListeningTracker {
  ListeningTracker(this._stats);

  final ListeningStatsService? _stats;
  int _lastPlayedSeconds = -1;
  int _pendingSeconds = 0;
  bool _recordedPlay = false;

  bool get recordedPlay => _recordedPlay;

  void beginSong() {
    _lastPlayedSeconds = -1;
    _pendingSeconds = 0;
    _recordedPlay = false;
  }

  void resetPosition() {
    _lastPlayedSeconds = -1;
    _pendingSeconds = 0;
  }

  void recordPlay(SongModel song) {
    if (_recordedPlay) return;
    _recordedPlay = true;
    final stats = _stats;
    if (stats != null) unawaited(stats.recordPlay(song).catchError((_) {}));
  }

  void tick(SongModel? song, int seconds) {
    if (song == null) return;
    if (_lastPlayedSeconds >= 0 && seconds > _lastPlayedSeconds) {
      final delta = seconds - _lastPlayedSeconds;
      if (delta <= 3) _pendingSeconds += delta;
    }
    _lastPlayedSeconds = seconds;
    if (_pendingSeconds >= 10) unawaited(flush(song));
  }

  Future<void> flush(SongModel? song) async {
    final seconds = _pendingSeconds;
    if (seconds <= 0) return;
    _pendingSeconds = 0;
    if (song == null) return;
    try {
      await _stats?.addListening(song, seconds);
    } catch (_) {
      // Las estadísticas nunca deben interrumpir la reproducción.
    }
  }
}
