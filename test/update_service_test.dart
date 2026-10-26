import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_app/data/models/app_update_info.dart';
import 'package:music_app/data/services/update_service.dart';

void main() {
  group('compareAppVersions', () {
    test('compara versiones numéricas', () {
      expect(compareAppVersions('2.0.1', '2.0.0'), greaterThan(0));
      expect(compareAppVersions('2.0.0', '2.0.0'), 0);
      expect(compareAppVersions('1.9.9', '2.0.0'), lessThan(0));
      expect(compareAppVersions('v2.1.0', '2.0.9'), greaterThan(0));
    });

    test('ignora segmentos ausentes', () {
      expect(compareAppVersions('2.0', '2.0.0'), 0);
      expect(compareAppVersions('2.1', '2.0.9'), greaterThan(0));
    });
  });

  group('AppUpdateInfo', () {
    test('lee el manifiesto y normaliza las notas', () {
      final info = AppUpdateInfo.fromJson({
        'version': '2.0.1',
        'build': 3,
        'download_url': 'https://example.com/app.apk',
        'notes': ['Mejoras', 'Correcciones'],
      });

      expect(info.version, '2.0.1');
      expect(info.build, 3);
      expect(info.displayVersion, '2.0.1 (build 3)');
      expect(info.notes, 'Mejoras\nCorrecciones');
    });

    test('rechaza URLs que no son http o https', () {
      expect(
        () => AppUpdateInfo.fromJson({
          'version': '2.0.1',
          'build': 3,
          'download_url': 'archivo-local.apk',
        }),
        throwsFormatException,
      );
    });
  });

  group('UpdateService', () {
    test('devuelve la actualización cuando el build remoto es mayor', () async {
      final service = UpdateService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'version': '2.0.1',
              'build': 3,
              'download_url': 'https://example.com/app.apk',
              'notes': 'Mejoras',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
        manifestUrl: 'https://example.com/version.json',
        currentVersion: '2.0.0',
        currentBuild: 2,
      );
      addTearDown(service.dispose);

      final update = await service.checkForUpdate();

      expect(update, isNotNull);
      expect(update!.version, '2.0.1');
      expect(update.build, 3);
    });

    test(
      'no devuelve actualización si la versión y build son iguales',
      () async {
        final service = UpdateService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'version': '2.0.0',
                'build': 2,
                'download_url': 'https://example.com/app.apk',
              }),
              200,
            ),
          ),
          manifestUrl: 'https://example.com/version.json',
          currentVersion: '2.0.0',
          currentBuild: 2,
        );
        addTearDown(service.dispose);

        expect(await service.checkForUpdate(), isNull);
      },
    );

    test('convierte un error HTTP en UpdateException', () async {
      final service = UpdateService(
        client: MockClient((_) async => http.Response('No encontrado', 404)),
        manifestUrl: 'https://example.com/version.json',
        currentVersion: '2.0.0',
        currentBuild: 2,
      );
      addTearDown(service.dispose);

      expect(service.checkForUpdate(), throwsA(isA<UpdateException>()));
    });
  });
}
