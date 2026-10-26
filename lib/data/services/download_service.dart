import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/song_model.dart';
import '../repositories/music_repository.dart' show AudioQuality;

/// Una canción descargada de forma explícita por el usuario.
@immutable
class DownloadEntry {
  const DownloadEntry({
    required this.song,
    required this.bytes,
    required this.createdAt,
    this.quality = 'high',
  });

  final SongModel song;
  final int bytes;
  final DateTime createdAt;
  final String quality;

  factory DownloadEntry.fromJson(Map<String, dynamic> json) => DownloadEntry(
    song: SongModel.fromJson(
      Map<String, dynamic>.from(json['song'] as Map? ?? const {}),
    ),
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
    quality: '${json['quality'] ?? 'high'}',
  );

  Map<String, dynamic> toJson() => {
    'song': song.toJson(),
    'bytes': bytes,
    'createdAt': createdAt.toIso8601String(),
    'quality': quality,
  };
}

class DownloadException implements Exception {
  const DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DownloadBatchResult {
  const DownloadBatchResult({required this.completed, required this.failed});
  final int completed;
  final int failed;
  int get total => completed + failed;
}

/// Descargas offline persistentes y elegidas por el usuario.
///
/// Vive en un directorio propio (no en la caché temporal) para que el sistema
/// no las borre y para que la limpieza de caché nunca elimine una descarga.
class DownloadService {
  DownloadService({
    required this.directory,
    required this.box,
    required this.resolveStream,
    required this.wifiOnly,
  });

  final Directory directory;
  final Box box;
  final Future<Uri?> Function(String id, AudioQuality quality) resolveStream;
  final bool Function() wifiOnly;

  static const int minValidBytes = 32 * 1024;
  static const int maxFileBytes = 80 * 1024 * 1024;

  final Map<String, DownloadEntry> _entries = {};
  final Map<String, double> _progress = {};
  final Map<String, Future<DownloadEntry>> _inFlight = {};
  final Set<String> _cancelled = {};
  final _changes = StreamController<List<DownloadEntry>>.broadcast();
  final _progressChanges = StreamController<Map<String, double>>.broadcast();

  Stream<List<DownloadEntry>> get stream => _changes.stream;
  Stream<Map<String, double>> get progressStream => _progressChanges.stream;

  List<DownloadEntry> get entries {
    final list = _entries.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(list);
  }

  Map<String, double> get progress => Map.unmodifiable(_progress);
  int get totalBytes =>
      _entries.values.fold(0, (total, entry) => total + entry.bytes);

  bool isDownloaded(String songId) => _entries.containsKey(songId);

  bool isDownloading(String songId) => _inFlight.containsKey(songId);

  File _fileFor(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id.audio');

  File? fileFor(String id) {
    if (id.isEmpty) return null;
    final entry = _entries[id];
    if (entry == null) return null;
    final file = _fileFor(id);
    try {
      if (file.existsSync() && file.lengthSync() >= minValidBytes) return file;
    } catch (_) {}
    return null;
  }

  Future<void> init() async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.part')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (error) {
      debugPrint('No se pudo preparar el directorio de descargas: $error');
    }

    final loaded = <String, DownloadEntry>{};
    for (final value in box.values) {
      if (value is! Map) continue;
      try {
        final entry = DownloadEntry.fromJson(Map<String, dynamic>.from(value));
        final file = _fileFor(entry.song.id);
        if (file.existsSync() && file.lengthSync() >= minValidBytes) {
          loaded[entry.song.id] = entry;
        } else {
          await box.delete(entry.song.id);
        }
      } catch (_) {
        // Una entrada antigua incompatible se ignora.
      }
    }
    _entries
      ..clear()
      ..addAll(loaded);
    _emit();
  }

  Future<bool> _networkAllowsDownload() async {
    if (!wifiOnly()) return true;
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  Future<DownloadEntry> download(
    SongModel song, {
    AudioQuality quality = AudioQuality.high,
  }) {
    final existing = _entries[song.id];
    if (existing != null && fileFor(song.id) != null) {
      return Future.value(existing);
    }
    final pending = _inFlight[song.id];
    if (pending != null) return pending;

    final request = _download(song, quality);
    _inFlight[song.id] = request;
    _progress[song.id] = 0;
    _emitProgress();
    return request.whenComplete(() {
      _inFlight.remove(song.id);
      _progress.remove(song.id);
      _cancelled.remove(song.id);
      _emitProgress();
    });
  }

  Future<DownloadEntry> _download(SongModel song, AudioQuality quality) async {
    if (!await _networkAllowsDownload()) {
      throw const DownloadException(
        'Descarga solo con WiFi activado. Conéctate a una red WiFi o desactívalo en Ajustes.',
      );
    }

    final uri = await resolveStream(song.id, quality);
    if (uri == null) {
      throw const DownloadException(
        'No se pudo obtener el audio. Inténtalo de nuevo más tarde.',
      );
    }

    final target = _fileFor(song.id);
    final temp = File('${target.path}.part');
    HttpClient? client;
    IOSink? sink;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 25);
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'com.google.android.exoplayer:exoplayer:2.19.1',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const DownloadException('El servidor no permitió la descarga.');
      }
      final mime = response.headers.contentType?.mimeType;
      if (mime != null && mime.startsWith('text/')) {
        throw const DownloadException('El audio recibido no es válido.');
      }

      final total = response.contentLength;
      var written = 0;
      sink = temp.openWrite();
      final output = sink;
      await for (final chunk in response) {
        if (_cancelled.contains(song.id)) {
          await output.close();
          sink = null;
          await _delete(temp);
          throw const DownloadException('Descarga cancelada.');
        }
        written += chunk.length;
        if (written > maxFileBytes) {
          await output.close();
          sink = null;
          await _delete(temp);
          throw const DownloadException('El archivo es demasiado grande.');
        }
        output.add(chunk);
        if (total > 0) {
          _progress[song.id] = (written / total).clamp(0, .99);
          _emitProgress();
        }
      }
      await output.flush();
      await output.close();
      sink = null;

      if (_cancelled.contains(song.id)) {
        await _delete(temp);
        throw const DownloadException('Descarga cancelada.');
      }
      if (written < minValidBytes) {
        await _delete(temp);
        throw const DownloadException('La descarga quedó incompleta.');
      }
      if (total > 0 && written != total) {
        await _delete(temp);
        throw const DownloadException('La descarga quedó incompleta.');
      }
      if (target.existsSync()) await target.delete();
      await temp.rename(target.path);

      final entry = DownloadEntry(
        song: song,
        bytes: written,
        createdAt: DateTime.now(),
        quality: quality.name,
      );
      _entries[song.id] = entry;
      await box.put(song.id, entry.toJson());
      _progress[song.id] = 1;
      _emit();
      _emitProgress();
      return entry;
    } on DownloadException {
      rethrow;
    } catch (error) {
      await _delete(temp);
      debugPrint('Descarga fallida para ${song.id}: $error');
      throw const DownloadException(
        'No se pudo descargar. Comprueba tu conexión e inténtalo de nuevo.',
      );
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      client?.close(force: true);
    }
  }

  /// Descarga varias canciones con dos trabajos en paralelo como máximo.
  Future<DownloadBatchResult> downloadMany(
    List<SongModel> songs, {
    AudioQuality quality = AudioQuality.high,
    void Function(int completed, int failed)? onProgress,
  }) async {
    final unique = <String, SongModel>{for (final s in songs) s.id: s}.values
        .toList();
    var completed = 0;
    var failed = 0;
    var cursor = 0;

    Future<void> worker() async {
      while (cursor < unique.length) {
        final index = cursor++;
        final song = unique[index];
        try {
          await download(song, quality: quality);
          completed++;
        } catch (_) {
          failed++;
        }
        onProgress?.call(completed, failed);
      }
    }

    await Future.wait([worker(), worker()]);
    return DownloadBatchResult(completed: completed, failed: failed);
  }

  void cancel(String songId) {
    _cancelled.add(songId);
  }

  Future<void> delete(String songId) async {
    _cancelled.add(songId);
    _entries.remove(songId);
    _progress.remove(songId);
    await box.delete(songId);
    await _delete(_fileFor(songId));
    await _delete(File('${_fileFor(songId).path}.part'));
    _emit();
    _emitProgress();
  }

  Future<void> deleteAll() async {
    _cancelled.addAll(_inFlight.keys);
    _progress.clear();
    _entries.clear();
    await box.clear();
    try {
      if (await directory.exists()) {
        await for (final entity in directory.list()) {
          if (entity is File) await entity.delete();
        }
      }
    } catch (error) {
      debugPrint('No se pudieron borrar todas las descargas: $error');
    }
    _emit();
    _emitProgress();
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _emit() => _changes.add(entries);
  void _emitProgress() => _progressChanges.add(progress);

  Future<void> dispose() async {
    await _changes.close();
    await _progressChanges.close();
  }
}
