import 'dart:async';

import '../../core/utils/text_utils.dart';
import '../models/song_model.dart';
import 'app_cache.dart';
import 'yt_service.dart';

class LyricsIndexEntry {
  const LyricsIndexEntry({
    required this.song,
    required this.normalizedLyrics,
    required this.lines,
  });

  final SongModel song;
  final String normalizedLyrics;
  final List<String> lines;
}

class LyricsHit {
  const LyricsHit({
    required this.song,
    required this.line,
    required this.snippet,
    required this.score,
  });

  final SongModel song;
  final String line;
  final String snippet;
  final int score;
}

class LyricsIndexProgress {
  const LyricsIndexProgress({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.cancelled = false,
    this.error,
  });

  final bool running;
  final int done;
  final int total;
  final bool cancelled;
  final Object? error;

  double get fraction => total <= 0 ? 0 : done / total;
}

/// Índice en memoria de letras ya cacheadas y de las descargas indexadas bajo
/// demanda. No hay búsqueda global de letras: solo se busca lo que ya está en
/// el dispositivo o en la caché persistente.
class LyricsIndexService {
  LyricsIndexService({required this.yt, required this.cache});

  final YtService yt;
  final AppCache cache;
  final Map<String, LyricsIndexEntry> _entries = {};

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  List<SongModel> get indexedSongs =>
      _entries.values.map((entry) => entry.song).toList();

  /// Reconstruye el índice con las letras que ya están en caché para las
  /// canciones conocidas (descargas, favoritos, historial y playlists).
  Future<void> warmUp(Iterable<SongModel> songs) async {
    for (final song in songs) {
      if (song.id.isEmpty || _entries.containsKey(song.id)) continue;
      final stored = cache.getStale<Map>('lyrics:${song.id}');
      if (stored == null) continue;
      final entry = _entryFromMap(song, stored);
      if (entry != null) _entries[song.id] = entry;
    }
  }

  List<LyricsHit> search(String query, {int limit = 20}) {
    final normalized = normalize(query);
    if (normalized.isEmpty) return const [];
    final tokens = tokenize(query);
    final andHits = <LyricsHit>[];
    final orHits = <LyricsHit>[];

    for (final entry in _entries.values) {
      final matches = tokens
          .where(entry.normalizedLyrics.contains)
          .length;
      if (matches == 0) continue;
      final line = _bestLine(entry, normalized, tokens);
      final hit = LyricsHit(
        song: entry.song,
        line: line,
        snippet: snippetAround(line, query),
        score: matches * 10 + (entry.normalizedLyrics.contains(normalized) ? 8 : 0),
      );
      if (matches == tokens.length) {
        andHits.add(hit);
      } else {
        orHits.add(hit);
      }
    }

    final result = andHits.isNotEmpty ? andHits : orHits;
    result.sort((a, b) => b.score.compareTo(a.score));
    return result.take(limit).toList();
  }

  /// Indexa las letras de las descargas con concurrencia limitada.
  Future<LyricsIndexProgress> indexSongs(
    List<SongModel> songs, {
    void Function(LyricsIndexProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final pending = songs
        .where((song) => song.id.isNotEmpty && !_entries.containsKey(song.id))
        .toList();
    final total = pending.length;
    if (total == 0) {
      final done = LyricsIndexProgress(running: false, total: total);
      onProgress?.call(done);
      return done;
    }

    var done = 0;
    var cancelled = false;
    Object? firstError;
    onProgress?.call(
      LyricsIndexProgress(running: true, done: 0, total: total),
    );

    // Tres trabajadores como máximo: suficiente para avanzar sin saturar la red
    // ni la caché.
    const concurrency = 3;
    var index = 0;
    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) {
          cancelled = true;
          return;
        }
        final current = index++;
        if (current >= pending.length) return;
        final song = pending[current];
        try {
          final map = cache.getStale<Map>('lyrics:${song.id}') ??
              await yt.getLyricsForSong(song.id);
          if (map != null) {
            final entry = _entryFromMap(song, map);
            if (entry != null) _entries[song.id] = entry;
          }
        } catch (error) {
          firstError ??= error;
        }
        done++;
        onProgress?.call(
          LyricsIndexProgress(
            running: true,
            done: done,
            total: total,
          ),
        );
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    final result = LyricsIndexProgress(
      running: false,
      done: done,
      total: total,
      cancelled: cancelled,
      error: firstError,
    );
    onProgress?.call(result);
    return result;
  }

  void clear() => _entries.clear();

  LyricsIndexEntry? _entryFromMap(SongModel song, Map map) {
    final lines = <String>[];
    final rawLines = map['lines'];
    if (rawLines is List) {
      for (final item in rawLines) {
        if (item is Map) {
          final text = '${item['text'] ?? ''}'.trim();
          if (text.isNotEmpty) lines.add(text);
        } else if (item is String && item.trim().isNotEmpty) {
          lines.add(item.trim());
        }
      }
    }
    if (lines.isEmpty) {
      final text = '${map['lyrics'] ?? map['text'] ?? ''}'.trim();
      if (text.isNotEmpty) {
        lines.addAll(
          text
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty),
        );
      }
    }
    if (lines.isEmpty) return null;
    return LyricsIndexEntry(
      song: song,
      normalizedLyrics: normalize(lines.join(' ')),
      lines: lines,
    );
  }

  String _bestLine(
    LyricsIndexEntry entry,
    String normalized,
    List<String> tokens,
  ) {
    var best = entry.lines.first;
    var bestScore = -1;
    for (final line in entry.lines) {
      final normalizedLine = normalize(line);
      var score = 0;
      if (normalizedLine.contains(normalized)) score += 10;
      for (final token in tokens) {
        if (normalizedLine.contains(token)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = line;
      }
    }
    return best;
  }
}
