import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../core/utils/artwork_url.dart';
import '../models/song_model.dart';

/// Sincroniza el widget nativo de Android con la canción y el estado actual.
///
/// La UI nunca habla directamente con Android: esta clase centraliza el canal,
/// la descarga de la portada y las acciones de los botones del widget.
class HomeWidgetService {
  static const _channel = MethodChannel('simple_music/widget');
  static bool _initialized = false;
  static String? _lastSignature;
  static String? _artworkSentSongId;
  static int _updateId = 0;

  static Future<void> init({
    required Future<void> Function(String action) onAction,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        final action = call.arguments;
        if (action is String && action.isNotEmpty) await onAction(action);
      }
    });
    try {
      await _channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // Plataformas sin widget (iOS, escritorio o web).
    } catch (_) {}
  }

  static Future<void> update({
    required SongModel? song,
    required bool playing,
  }) async {
    if (!_initialized) return;
    if (song == null) {
      if (_lastSignature == 'empty') return;
      _lastSignature = 'empty';
      _artworkSentSongId = null;
      _updateId++;
      try {
        await _channel.invokeMethod<void>('clear');
      } catch (_) {}
      return;
    }

    final signature = '${song.id}|$playing';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    final updateId = ++_updateId;

    final songChanged = _artworkSentSongId != song.id;
    Uint8List? artwork;
    if (songChanged) {
      // El widget es pequeño: una variante de 480 px evita descargar y enviar
      // la portada maxres completa por el canal de plataforma.
      final url = artworkUrlForSize(song.artworkUrl, targetSize: 480);
      if (url != null && url.isNotEmpty) {
        try {
          final file = await DefaultCacheManager().getSingleFile(url);
          if (await file.length() <= 6 * 1024 * 1024) {
            artwork = await file.readAsBytes();
          }
        } catch (error) {
          debugPrint('No se pudo preparar la portada del widget: $error');
        }
      }
    }

    if (updateId != _updateId) return;
    try {
      final arguments = <String, Object?>{
        'title': song.title,
        'artist': song.artists.join(', '),
        'playing': playing,
      };
      // En pausa/reanudación se omite la clave para que el nativo conserve la
      // portada en lugar de volver a leerla y transferirla.
      if (songChanged) arguments['artwork'] = artwork;
      await _channel.invokeMethod<void>('update', arguments);
      if (songChanged) _artworkSentSongId = song.id;
    } on MissingPluginException {
      // Sin widget nativo.
    } catch (error) {
      debugPrint('No se pudo actualizar el widget: $error');
    }
  }

  /// Fuerza la siguiente actualización aunque la firma no haya cambiado.
  static void invalidate() => _lastSignature = null;
}
