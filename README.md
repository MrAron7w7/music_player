# music_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Actualizaciones de Simple Music

La app comprueba `version.json` al arrancar y también desde
**Ajustes → Actualizaciones → Buscar actualizaciones**.

### Archivos que deben ir sincronizados

- `pubspec.yaml`: `version: X.Y.Z+N`
- `lib/core/constants/app_config.dart`: `version = 'X.Y.Z'` y
  `buildNumber = N`

El `build` (`N`) debe aumentar siempre. Android lo usa para aceptar el APK
como una actualización.

### Publicar una versión nueva

1. Cambia la versión en `pubspec.yaml` y en `app_config.dart`. Por ejemplo,
   de `2.0.0+2` a `2.0.1+3`.
2. Compila el APK de release:

   ```bash
   flutter build apk --release
   ```

3. En GitHub, crea un release con el tag de la versión (por ejemplo
   `v2.0.1`) y adjunta el APK generado en
   `build/app/outputs/flutter-apk/app-release.apk`.
4. Actualiza `version.json` en la raíz del repositorio:

   ```json
   {
     "version": "2.0.1",
     "build": 3,
     "download_url": "https://github.com/MrAron7w7/music_player/releases/latest",
     "notes": "Mejoras de rendimiento y corrección de errores"
   }
   ```

5. Haz commit y push de `version.json` a la rama `main`.

La app compara `version` y `build`. Si el build remoto es mayor, muestra el
diálogo de actualización. El botón **Actualizar** abre `download_url` en el
navegador.

> Importante: todos los APK deben estar firmados con la misma clave. El
> proyecto usa actualmente la firma de debug para release; si algún día
> cambias la firma, Android no permitirá instalar el APK encima de la versión
> anterior.
# music_player
