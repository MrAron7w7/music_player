import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/song_model.dart';

@immutable
class SongStat {
  const SongStat({
    required this.song,
    required this.plays,
    required this.seconds,
    required this.lastPlayed,
  });

  final SongModel song;
  final int plays;
  final int seconds;
  final DateTime? lastPlayed;
}

@immutable
class ArtistStat {
  const ArtistStat({
    required this.name,
    required this.plays,
    required this.seconds,
  });

  final String name;
  final int plays;
  final int seconds;
}

@immutable
class RecentPlay {
  const RecentPlay({required this.song, required this.playedAt});
  final SongModel song;
  final DateTime playedAt;

  Map<String, dynamic> toJson() => {
    'song': song.toJson(),
    'playedAt': playedAt.toIso8601String(),
  };

  factory RecentPlay.fromJson(Map<String, dynamic> json) => RecentPlay(
    song: SongModel.fromJson(
      Map<String, dynamic>.from(json['song'] as Map? ?? const {}),
    ),
    playedAt: DateTime.tryParse('${json['playedAt']}') ?? DateTime.now(),
  );
}

@immutable
class StatsSnapshot {
  const StatsSnapshot({
    required this.topSongs,
    required this.topArtists,
    required this.recent,
    required this.totalSeconds,
    required this.todaySeconds,
    required this.weekSeconds,
    required this.monthSeconds,
    required this.totalPlays,
  });

  final List<SongStat> topSongs;
  final List<ArtistStat> topArtists;
  final List<RecentPlay> recent;
  final int totalSeconds;
  final int todaySeconds;
  final int weekSeconds;
  final int monthSeconds;
  final int totalPlays;

  String get totalLabel => _label(totalSeconds);
  String get todayLabel => _label(todaySeconds);
  String get weekLabel => _label(weekSeconds);
  String get monthLabel => _label(monthSeconds);

  static String _label(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}min';
  }
}

/// Estadísticas locales de escucha. No requiere red ni servicios externos.
class ListeningStatsService {
  ListeningStatsService(this.box);

  final Box box;
  final _changes = StreamController<StatsSnapshot>.broadcast();
  List<RecentPlay> _recent = [];
  Timer? _emitTimer;

  static const _recentKey = 'recentPlays';
  static const _maxRecent = 150;

  Stream<StatsSnapshot> get stream => _changes.stream;

  Future<void> init() async {
    final stored = box.get(_recentKey);
    if (stored is List) {
      _recent = stored
          .whereType<Map>()
          .map((e) {
            try {
              return RecentPlay.fromJson(Map<String, dynamic>.from(e));
            } catch (_) {
              return null;
            }
          })
          .whereType<RecentPlay>()
          .toList();
    }
    _changes.add(snapshot());
  }

  SongStat? _songStat(String id) {
    final value = box.get('song:$id');
    if (value is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(value);
      return SongStat(
        song: SongModel.fromJson(
          Map<String, dynamic>.from(map['song'] as Map? ?? const {}),
        ),
        plays: (map['plays'] as num?)?.toInt() ?? 0,
        seconds: (map['seconds'] as num?)?.toInt() ?? 0,
        lastPlayed: DateTime.tryParse('${map['lastPlayed']}'),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> recordPlay(SongModel song, {DateTime? at}) async {
    if (song.id.isEmpty) return;
    final time = at ?? DateTime.now();
    final current = _songStat(song.id);
    final plays = (current?.plays ?? 0) + 1;
    final seconds = current?.seconds ?? 0;
    await box.put('song:${song.id}', {
      'song': song.toJson(),
      'plays': plays,
      'seconds': seconds,
      'lastPlayed': time.toIso8601String(),
    });
    _recent.removeWhere((entry) => entry.song.id == song.id);
    _recent.insert(0, RecentPlay(song: song, playedAt: time));
    if (_recent.length > _maxRecent) {
      _recent = _recent.take(_maxRecent).toList();
    }
    await box.put(_recentKey, _recent.map((e) => e.toJson()).toList());
    _scheduleEmit();
  }

  Future<void> addListening(SongModel song, int seconds) async {
    if (seconds <= 0 || song.id.isEmpty) return;
    final current = _songStat(song.id);
    if (current == null) {
      // Nunca se contabiliza escucha sin una reproducción registrada.
      return;
    }
    final total = current.seconds + seconds;
    await box.put('song:${song.id}', {
      'song': song.toJson(),
      'plays': current.plays,
      'seconds': total,
      'lastPlayed': current.lastPlayed?.toIso8601String(),
    });
    final key = 'day:${_dateKey(DateTime.now())}';
    final daySeconds = (box.get(key) as num?)?.toInt() ?? 0;
    await box.put(key, daySeconds + seconds);
    _scheduleEmit();
  }

  /// Emite como máximo cada 2 segundos para no reconstruir la UI en cada tick.
  void _scheduleEmit() {
    if (_emitTimer?.isActive ?? false) return;
    _emitTimer = Timer(const Duration(seconds: 2), () {
      _changes.add(snapshot());
    });
  }

  StatsSnapshot snapshot([DateTime? now]) {
    final moment = now ?? DateTime.now();
    final songs = <SongStat>[];
    for (final key in box.keys) {
      if (key is String && key.startsWith('song:')) {
        final stat = _songStat(key.substring(5));
        if (stat != null) songs.add(stat);
      }
    }
    final topSongs = [...songs]
      ..sort((a, b) {
        final bySeconds = b.seconds.compareTo(a.seconds);
        return bySeconds != 0 ? bySeconds : b.plays.compareTo(a.plays);
      });
    final artistMap = <String, ({int plays, int seconds})>{};
    for (final stat in songs) {
      final names = stat.song.artists.isEmpty
          ? const ['Artista desconocido']
          : stat.song.artists;
      for (final name in names.take(2)) {
        final current = artistMap[name] ?? (plays: 0, seconds: 0);
        artistMap[name] = (
          plays: current.plays + stat.plays,
          seconds: current.seconds + stat.seconds,
        );
      }
    }
    final topArtists =
        artistMap.entries
            .map(
              (entry) => ArtistStat(
                name: entry.key,
                plays: entry.value.plays,
                seconds: entry.value.seconds,
              ),
            )
            .toList()
          ..sort((a, b) => b.seconds.compareTo(a.seconds));

    int dayTotal(DateTime day) =>
        (box.get('day:${_dateKey(day)}') as num?)?.toInt() ?? 0;
    final startOfWeek = DateTime(
      moment.year,
      moment.month,
      moment.day,
    ).subtract(Duration(days: moment.weekday - 1));
    var weekSeconds = 0;
    for (var i = 0; i < 7; i++) {
      weekSeconds += dayTotal(startOfWeek.add(Duration(days: i)));
    }
    var monthSeconds = 0;
    for (var day = 1; day <= moment.day; day++) {
      monthSeconds += dayTotal(DateTime(moment.year, moment.month, day));
    }

    return StatsSnapshot(
      topSongs: topSongs.take(20).toList(),
      topArtists: topArtists.take(10).toList(),
      recent: List.unmodifiable(_recent),
      totalSeconds: songs.fold(0, (total, stat) => total + stat.seconds),
      todaySeconds: dayTotal(moment),
      weekSeconds: weekSeconds,
      monthSeconds: monthSeconds,
      totalPlays: songs.fold(0, (total, stat) => total + stat.plays),
    );
  }

  Future<void> clear() async {
    final keys = box.keys
        .where(
          (key) =>
              key is String &&
              (key.startsWith('song:') || key.startsWith('day:')),
        )
        .toList();
    await box.deleteAll(keys);
    await box.delete(_recentKey);
    _recent = [];
    _changes.add(snapshot());
  }

  Future<void> dispose() async {
    _emitTimer?.cancel();
    await _changes.close();
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
