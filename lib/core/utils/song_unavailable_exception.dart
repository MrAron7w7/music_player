/// Motivo aproximado por el que una canción no puede reproducirse en
/// YouTube Music.
enum SongUnavailableReason {
  /// El video está restringido por edad.
  ageRestricted,
  /// El video no está disponible en el país/región del usuario.
  regionRestricted,
  /// El video fue eliminado, está privado o no existe.
  unavailable,
  /// El video requiere compra o alquiler.
  purchaseRequired,
  /// Error al obtener o descifrar el stream de audio.
  streamError,
  /// Error de la API de YouTube o de red al resolver el manifiesto.
  apiError,
}

/// Una canción de YouTube Music no tiene un stream de audio disponible.
///
/// La causa ([reason]) permite mostrar al usuario un mensaje específico en
/// lugar del genérico "no se pudo reproducir".
final class SongUnavailableException implements Exception {
  /// Crea una excepción con la causa dada y, opcionalmente, la excepción
  /// original que la motivó.
  const SongUnavailableException(this.reason, [this.cause]);

  final SongUnavailableReason reason;
  final Object? cause;

  @override
  String toString() => 'SongUnavailable ($reason): $cause';
}
