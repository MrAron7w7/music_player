/// Configuración de la aplicación y del sistema de actualizaciones.
///
/// Mantén [version] y [buildNumber] sincronizados con `version` en
/// `pubspec.yaml`. El build debe aumentar en cada APK que publiques para que
/// Android permita instalarlo como actualización.
class AppConfig {
  AppConfig._();

  static const appName = 'Simple Music';
  static const version = '2.0.0';
  static const buildNumber = 2;

  /// Versión en formato `version+build`, igual que en `pubspec.yaml`.
  static const versionLabel = '$version+$buildNumber';

  /// Versión legible para mostrar en Ajustes y en el diálogo.
  static const displayVersion = '$version (build $buildNumber)';

  /// Manifiesto público con la última versión disponible.
  ///
  /// Debe ser una URL raw accesible sin autenticación. El archivo se llama
  /// `version.json` y vive en la raíz del repositorio.
  static const updatesManifestUrl =
      'https://raw.githubusercontent.com/MrAron7w7/music_player/main/version.json';

  /// Página que se abre al pulsar «Actualizar» si el manifiesto no trae una
  /// URL de descarga válida.
  static const releasesUrl =
      'https://github.com/MrAron7w7/music_player/releases/latest';
}
