import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/data/models/app_update_info.dart';
import 'package:music_app/presentation/widgets/update_dialog.dart';

void main() {
  testWidgets('muestra la versión nueva, las notas y las acciones', (
    tester,
  ) async {
    const update = AppUpdateInfo(
      version: '2.0.1',
      build: 3,
      downloadUrl: 'https://example.com/app.apk',
      notes: 'Mejoras de rendimiento',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUpdateDialog(context, update),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Nueva actualización disponible'), findsOneWidget);
    expect(find.text('2.0.1 (build 3)'), findsOneWidget);
    expect(find.text('Mejoras de rendimiento'), findsOneWidget);
    expect(find.text('Actualizar'), findsOneWidget);
    expect(find.text('Más tarde'), findsOneWidget);

    await tester.tap(find.text('Más tarde'));
    await tester.pumpAndSettle();

    expect(find.text('Nueva actualización disponible'), findsNothing);
  });
}
