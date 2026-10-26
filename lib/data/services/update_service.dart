import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_config.dart';
import '../models/app_update_info.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Comprueba la última versión publicada en el manifiesto JSON del proyecto.
class UpdateService {
  UpdateService({
    http.Client? client,
    String? manifestUrl,
    String? currentVersion,
    int? currentBuild,
  }) : _client = client ?? http.Client(),
       _manifestUrl = manifestUrl ?? AppConfig.updatesManifestUrl,
       _currentVersion = currentVersion ?? AppConfig.version,
       _currentBuild = currentBuild ?? AppConfig.buildNumber;

  final http.Client _client;
  final String _manifestUrl;
  final String _currentVersion;
  final int _currentBuild;

  Future<AppUpdateInfo?> checkForUpdate() async {
    final manifest = Uri.tryParse(_manifestUrl);
    if (manifest == null || manifest.host.isEmpty) {
      throw const UpdateException(
        'La URL del manifiesto de actualizaciones no es válida.',
      );
    }

    // Evita que GitHub Raw o un proxy entreguen una copia antigua del JSON.
    final uri = manifest.replace(
      queryParameters: {
        ...manifest.queryParameters,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const UpdateException(
        'La comprobación tardó demasiado. Revisa tu conexión e inténtalo de nuevo.',
      );
    } catch (_) {
      throw const UpdateException(
        'No se pudo conectar con el servidor de actualizaciones.',
      );
    }

    if (response.statusCode != 200) {
      throw UpdateException(
        'El servidor de actualizaciones respondió ${response.statusCode}.',
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const FormatException('El manifiesto debe ser un objeto JSON.');
      }
      final update = AppUpdateInfo.fromJson(Map<String, dynamic>.from(decoded));
      return _isNewer(update) ? update : null;
    } catch (_) {
      throw const UpdateException(
        'El archivo de actualizaciones no tiene un formato válido.',
      );
    }
  }

  bool _isNewer(AppUpdateInfo update) {
    final versionComparison = compareAppVersions(
      update.version,
      _currentVersion,
    );
    if (versionComparison != 0) return versionComparison > 0;
    return update.build > _currentBuild;
  }

  void dispose() => _client.close();
}

/// Compara versiones numéricas como `2.0.0` o `v2.1.3`.
///
/// Devuelve un valor negativo si [left] es menor, cero si son iguales y un
/// valor positivo si [left] es mayor. Los sufijos de pre-release se ignoran
/// para mantener el sistema simple y predecible.
int compareAppVersions(String left, String right) {
  final a = _versionSegments(left);
  final b = _versionSegments(right);
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final valueA = i < a.length ? a[i] : 0;
    final valueB = i < b.length ? b[i] : 0;
    if (valueA != valueB) return valueA.compareTo(valueB);
  }
  return 0;
}

List<int> _versionSegments(String version) {
  final withoutPrefix = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final core = withoutPrefix.split('+').first.split('-').first;
  return core.split('.').map((part) {
    final match = RegExp(r'^\d+').firstMatch(part);
    return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
  }).toList();
}
