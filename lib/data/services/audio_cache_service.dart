import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Caché de audio de las canciones escuchadas recientemente.
///
/// Descarga en segundo plano y guarda un archivo local por canción. La
/// reproducción usa el archivo solo cuando la descarga terminó correctamente;
/// en caso contrario sigue usando el stream de red de siempre.
class AudioCacheService {
  AudioCacheService(
    this._directory, {
    int maxBytes = defaultMaxBytes,
    int maxFiles = defaultMaxFiles,
    // ignore: prefer_initializing_formals
  }) : _maxBytes = maxBytes,
       // ignore: prefer_initializing_formals
       _maxFiles = maxFiles;

  final Directory _directory;

  static const int defaultMaxBytes = 250 * 1024 * 1024;
  static const int defaultMaxFiles = 60;
  static const int unlimitedBytes = 1024 * 1024 * 1024 * 1024;
  static const int _minValidBytes = 48 * 1024;
  static const int _maxFileBytes = 30 * 1024 * 1024;

  int _maxBytes;
  int _maxFiles;

  int get maxBytes => _maxBytes;
  int get maxFiles => _maxFiles;

  /// Un valor de 0 significa sin límite de tamaño.
  void setLimitBytes(int bytes) {
    _maxBytes = bytes <= 0 ? unlimitedBytes : bytes;
    _maxFiles = bytes <= 0
        ? 100000
        : (_maxBytes ~/ (4 * 1024 * 1024)).clamp(40, 2000);
  }

  final Set<String> _inFlight = <String>{};

  Future<void> init() async {
    try {
      if (!await _directory.exists()) {
        await _directory.create(recursive: true);
      }
      final now = DateTime.now();
      await for (final entity in _directory.list()) {
        if (entity is! File || !entity.path.endsWith('.part')) continue;
        try {
          final modified = await entity.lastModified();
          if (now.difference(modified) > const Duration(minutes: 5)) {
            await entity.delete();
          }
        } catch (_) {
          // Un archivo temporal bloqueado no debe impedir el arranque.
        }
      }
      await _evict();
    } catch (error) {
      debugPrint('No se pudo preparar la caché de audio: $error');
    }
  }

  File _fileFor(String id) =>
      File('${_directory.path}${Platform.pathSeparator}$id.audio');

  /// Archivo completo disponible para reproducir sin conexión.
  File? cachedFile(String id) {
    if (id.isEmpty) return null;
    final file = _fileFor(id);
    try {
      if (file.existsSync() && file.lengthSync() >= _minValidBytes) {
        return file;
      }
    } catch (_) {
      // Si no se puede leer, se usa el stream de red.
    }
    return null;
  }

  /// Descarga una canción en segundo plano. Los errores son silenciosos.
  Future<void> prefetch(String id, Uri uri) async {
    if (id.isEmpty || cachedFile(id) != null) return;
    if (!_inFlight.add(id)) return;

    final target = _fileFor(id);
    final temp = File('${target.path}.part');
    HttpClient? client;
    IOSink? sink;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12)
        ..idleTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'com.google.android.exoplayer:exoplayer:2.19.1',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return;
      final mimeType = response.headers.contentType?.mimeType;
      if (mimeType != null && mimeType.startsWith('text/')) return;

      sink = temp.openWrite();
      final output = sink;
      var written = 0;
      await for (final chunk in response) {
        written += chunk.length;
        if (written > _maxFileBytes) {
          await output.close();
          sink = null;
          await _delete(temp);
          return;
        }
        output.add(chunk);
      }
      await output.flush();
      await output.close();
      sink = null;

      if (written < _minValidBytes) {
        await _delete(temp);
        return;
      }
      if (response.contentLength > 0 && written != response.contentLength) {
        await _delete(temp);
        return;
      }
      if (target.existsSync()) await target.delete();
      await temp.rename(target.path);
      await _evict();
    } catch (error) {
      debugPrint('Caché de audio omitida para $id: $error');
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      await _delete(temp);
    } finally {
      client?.close(force: true);
      _inFlight.remove(id);
    }
  }

  Future<int> sizeBytes() async {
    var total = 0;
    try {
      await for (final entity in _directory.list()) {
        if (entity is File && !entity.path.endsWith('.part')) {
          total += await entity.length();
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> clear() async {
    try {
      await for (final entity in _directory.list()) {
        if (entity is File) await entity.delete();
      }
    } catch (error) {
      debugPrint('No se pudo limpiar la caché de audio: $error');
    }
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _evict() async {
    final stats = <({File file, DateTime modified, int size})>[];
    try {
      await for (final entity in _directory.list()) {
        if (entity is! File || entity.path.endsWith('.part')) continue;
        try {
          stats.add((
            file: entity,
            modified: await entity.lastModified(),
            size: await entity.length(),
          ));
        } catch (_) {}
      }
    } catch (_) {
      return;
    }
    // Conserva primero las canciones usadas más recientemente.
    stats.sort((a, b) => b.modified.compareTo(a.modified));
    var total = 0;
    for (var i = 0; i < stats.length; i++) {
      total += stats[i].size;
      if (i >= _maxFiles || total > _maxBytes) {
        await _delete(stats[i].file);
      }
    }
  }

  Future<int> fileCount() async {
    var total = 0;
    try {
      await for (final entity in _directory.list()) {
        if (entity is File && !entity.path.endsWith('.part')) total++;
      }
    } catch (_) {}
    return total;
  }

  /// Aplica inmediatamente el límite actual (por ejemplo al reducirlo).
  Future<void> enforceLimit() => _evict();
}
