import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Estados posibles del dictado por voz del buscador.
enum VoiceSearchStatus { idle, listening, processing, unavailable, denied }

/// Encapsula `speech_to_text` y expone un ciclo de vida sencillo para la UI.
///
/// No guarda audio: solo entrega el texto reconocido. El permiso de micrófono
/// se solicita desde la pantalla antes de llamar a [start].
class VoiceSearchController extends ChangeNotifier {
  VoiceSearchController({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  VoiceSearchStatus _status = VoiceSearchStatus.idle;
  String? _localeId;
  bool _initialized = false;
  bool _disposed = false;
  void Function(String message)? _onError;

  VoiceSearchStatus get status => _status;
  bool get isListening => _status == VoiceSearchStatus.listening;
  bool get isAvailable => _initialized;
  String? get localeId => _localeId;

  /// Inicializa el motor una sola vez. Devuelve `false` si el dispositivo no
  /// soporta reconocimiento o si el plugin falla.
  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      final available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
      );
      if (!available) {
        _status = VoiceSearchStatus.unavailable;
        _notify();
        return false;
      }
      _initialized = true;
      await _resolveLocale();
      if (_status == VoiceSearchStatus.unavailable) return false;
      _status = VoiceSearchStatus.idle;
      _notify();
      return true;
    } catch (_) {
      _status = VoiceSearchStatus.unavailable;
      _notify();
      return false;
    }
  }

  Future<void> _resolveLocale() async {
    try {
      final locales = await _speech.locales();
      if (locales.isEmpty) return;
      final device = Platform.localeName.replaceAll('-', '_').toLowerCase();
      for (final locale in locales) {
        if (locale.localeId.toLowerCase() == device) {
          _localeId = locale.localeId;
          return;
        }
      }
      final language = device.split('_').first;
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith('${language}_')) {
          _localeId = locale.localeId;
          return;
        }
      }
      // Fallback explícito del plan cuando el idioma del sistema no existe en
      // el motor, pero sí está disponible el español.
      for (final locale in locales) {
        if (locale.localeId.toLowerCase() == 'es_es') {
          _localeId = locale.localeId;
          return;
        }
      }
    } catch (_) {
      // Se usará el locale predeterminado del motor.
    }
  }

  /// Empieza a escuchar. [onResult] recibe texto parcial y final; [onError]
  /// recibe un mensaje legible para mostrar en pantalla.
  Future<bool> start({
    required void Function(String words, bool isFinal) onResult,
    required void Function(String message) onError,
  }) async {
    if (!_initialized && !await initialize()) return false;
    _onError = onError;
    _status = VoiceSearchStatus.listening;
    _notify();
    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          onResult(words, result.finalResult);
          if (result.finalResult) {
            _status = VoiceSearchStatus.processing;
            _notify();
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.search,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 4),
          localeId: _localeId,
          cancelOnError: true,
        ),
      );
      return true;
    } catch (_) {
      _status = VoiceSearchStatus.idle;
      _notify();
      onError('No se pudo iniciar el reconocimiento de voz.');
      return false;
    }
  }

  /// Detiene el dictado conservando el último texto reconocido.
  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _speech.stop();
    } catch (_) {
      _status = VoiceSearchStatus.idle;
      _notify();
    }
  }

  /// Cancela el dictado sin esperar un resultado final.
  Future<void> cancel() async {
    if (!_initialized) {
      _status = VoiceSearchStatus.idle;
      _notify();
      return;
    }
    try {
      await _speech.cancel();
    } catch (_) {
      // Ignorado: el motor ya estaba detenido.
    }
    _status = VoiceSearchStatus.idle;
    _notify();
  }

  void markDenied() {
    _status = VoiceSearchStatus.denied;
    _notify();
  }

  void _handleStatus(String value) {
    switch (value) {
      case SpeechToText.listeningStatus:
        _status = VoiceSearchStatus.listening;
      case SpeechToText.doneStatus:
      case SpeechToText.notListeningStatus:
        if (_status != VoiceSearchStatus.unavailable) {
          _status = VoiceSearchStatus.idle;
        }
      default:
        return;
    }
    _notify();
  }

  void _handleError(SpeechRecognitionError error) {
    _status = VoiceSearchStatus.idle;
    _notify();
    final message = error.errorMsg.trim();
    _onError?.call(message.isEmpty ? 'No se pudo reconocer la voz.' : message);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _onError = null;
    if (_initialized) {
      // No se espera: el widget se está destruyendo.
      _speech.cancel();
    }
    super.dispose();
  }
}
