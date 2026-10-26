/// Información de una versión publicada en `version.json`.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.downloadUrl,
    this.notes = '',
  });

  final String version;
  final int build;
  final String downloadUrl;
  final String notes;

  String get displayVersion => build > 0 ? '$version (build $build)' : version;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final version = json['version']?.toString().trim() ?? '';
    if (version.isEmpty) {
      throw const FormatException('El manifiesto no incluye una versión.');
    }

    final downloadUrl = json['download_url']?.toString().trim() ?? '';
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'El manifiesto no incluye una URL de descarga válida.',
      );
    }

    final rawBuild = json['build'];
    final build = switch (rawBuild) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };

    final rawNotes = json['notes'];
    final notes = switch (rawNotes) {
      String value => value.trim(),
      List value =>
        value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .join('\n'),
      _ => '',
    };

    return AppUpdateInfo(
      version: version,
      build: build,
      downloadUrl: downloadUrl,
      notes: notes,
    );
  }
}
