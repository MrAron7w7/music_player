# Plan de mejoras — Simple Music (music_app)

> **Documento de trabajo para una IA de código.**
> La app está 100% funcional. Este plan la hace más rápida, más robusta y más completa
> mediante cambios **quirúrgicos**: la regla número uno es **no romper nada que ya funcione**.
> Los números de línea son orientativos (pueden haber cambiado): **lee siempre el archivo real
> antes de editar** y adapta la solución al código que encuentres.

---

## 0. Contexto del proyecto

- **App**: reproductor de música en streaming desde YouTube Music, UI 100% en español.
- **Stack**: Flutter (Dart 3.13), Riverpod **con providers manuales** (sin codegen),
  just_audio + audio_service + audio_session, Hive para persistencia, go_router,
  ytmusicapi_dart 2.4.1 (API de YouTube Music) y youtube_explode_dart (fork, extracción de audio).
- **Arquitectura**:
  - `lib/data/services/` — servicios de infraestructura (yt_service, audio_handler, download_service,
    audio_cache_service, listening_stats_service, app_cache, update_service).
  - `lib/data/repositories/` — music_repository (orquesta yt + explode + caché de audio),
    local_repository (favoritos, playlists, historial, settings en Hive).
  - `lib/providers/` — providers de Riverpod agrupados por dominio.
  - `lib/presentation/` — screens y widgets.
- **Datos importantes**:
  - Los servicios globales se construyen en `main.dart` e inyectan por `overrideWithValue` en `ProviderScope`.
  - La caché de respuestas de la API vive en `yt_service._cached` (TTL memoria + persistencia en Hive).
  - Home, Biblioteca y Descargas viven en un `IndexedStack` siempre montado (`main_scaffold.dart`).
  - Idioma de UI: español, strings hardcoded (no hay l10n y no hay que introducirla).

**Dato verificado sobre el paquete**: `ytmusicapi_dart` **ya pagina internamente** hasta el
`limit` indicado (dentro de `search()` usa `getContinuations`). El tope de 20 resultados es
decisión del propio `yt_service.dart`, no del paquete.

---

## 1. Reglas obligatorias para la IA ejecutora

1. **Lee el archivo completo antes de editarlo.** Los números de línea de este plan son aproximados.
2. **Cambios quirúrgicos.** No refactors más allá del alcance de cada tarea; no reordenar código ajeno.
3. **Sin dependencias nuevas.** Ninguna tarea de este plan requiere agregar paquetes.
   No introducir riverpod codegen ni l10n.
4. **Strings de UI en español**, estilo y convenciones del código circundante.
5. **Verificación tras cada tarea**: `flutter analyze` sin errores/warnings nuevos.
   **Tras cada fase**: `flutter test` en verde + build de release (`flutter build apk --release`) que compile.
6. **Un commit por tarea** (mensajes en español, ej. `Fase 1.1: no cachear resultados vacíos en yt_service`).
7. **Si algo del plan resulta inviable o el código real contradice el plan**, detente, documenta
   el hallazgo y propone alternativa antes de improvisar.
8. Los cambios de audio/crossfade/velocidad deben dejarse anotados para **prueba manual en dispositivo real**.

---

## FASE 1 — Calidad y robustez

### 1.1 No cachear resultados vacíos producidos por fallos

**Problema**: `getRelatedSongs` y `getSmartQueue` devuelven `[]` cuando falla la red/API y ese vacío
se guarda en `_cached` (TTL 10 min en memoria + 6 h persistido). Un solo blip de conexión "envenena"
la radio y las canciones relacionadas por horas.

**Archivos**: `lib/data/services/yt_service.dart` (método `_cached`, `getRelatedSongs` ~línea 154,
`getSmartQueue` ~línea 233).

**Qué hacer**:

- Añadir a `_cached` un parámetro tipo `cacheIf` (o `allowEmptyCache = false` por defecto para listas):
  si el resultado es una lista vacía, no se guarda en caché de memoria ni en disco (solo se devuelve).
- En `getRelatedSongs`: el fallback `catchError((_) => [])` debe propagar "fallo" y no cachear;
  si la API responde exitosamente con 0 elementos reales, eso sí puede cachearse (con TTL corto solo en memoria).
- En `getSmartQueue`: no tragar los sub-errores silenciosamente; ante fallo devolver sin cachear.

**Criterio de aceptación**: con avión activado, abrir canciones relacionadas (falla), reconectar,
reabrir → debe reintentar la petición y cargar datos, no mostrar el vacío cacheado de 6 h.

### 1.2 Errores visibles con botón de reintentar (Home y búsqueda)

**Problema**: los providers de recomendaciones de Home tragan todos los errores y devuelven `[]`
(`home_providers.dart` ~120-137, 216-219, 259-268), por lo que Home muestra "no hay nada" ante un
fallo de red. Las 3 pestañas de búsqueda muestran el error crudo sin botón de reintento
(`search_screen.dart` ~138-238).

**Archivos**: `lib/providers/home_providers.dart`, `lib/presentation/screens/home_screen.dart`
(sección "Hecho para ti" ~193-205), `lib/presentation/screens/search_screen.dart`.

**Qué hacer**:

- Que los providers de recomendaciones propaguen el error (`AsyncValue.error`) en lugar de convertirlo en lista vacía.
- En Home: cuando la sección "Hecho para ti" esté en error, renderizar una tarjeta de error con
  botón **"Reintentar"** que haga `ref.invalidate` del provider.
- En búsqueda: en las 3 pestañas (canciones/álbumes/artistas) reemplazar el estado de error por una
  tarjeta con mensaje y botón **"Reintentar"** que invalide el provider family de esa query/tab.
- Usar el widget `EmptyState` existente (`lib/presentation/widgets/empty_state.dart`) como referencia
  de estilo; añade la variante de error que haga falta.

**Criterio de aceptación**: sin red, Home y búsqueda muestran error visible con botón; al pulsar con
red disponible, cargan. Con datos, la UI es idéntica a la actual.

### 1.3 Mensaje específico según por qué no está disponible una canción

**Problema**: todas las causas (age-restricted, restringida por región, eliminada, API caída)
colapsan en el catch-all de `music_repository.dart` (~líneas 84 y 120) que devuelve `null`, y
`audio_handler.dart` (~498-500) muestra siempre el mismo mensaje genérico
"No se pudo obtener el audio...".

**Archivos**: `lib/data/repositories/music_repository.dart`, `lib/data/services/audio_handler.dart`
(resolución de fuente ~461-500 y tarjeta de error ~974-1022), `lib/presentation/widgets/mini_player.dart` (~190-202).

**Qué hacer**:

- Crear `lib/core/utils/song_unavailable_exception.dart` (o similar) con un enum de causa:
  `ageRestricted, regionRestricted, unavailable, purchaseRequired, streamError, apiError`.
- En `music_repository.getAudioStreamUrl` / `_manifest`, inspeccionar las excepciones de
  `youtube_explode_dart` (`VideoUnavailableException`, `VideoRequiresPurchaseException`,
  excepciones de age/region) y lanzar la excepción tipada con su causa en lugar de devolver `null` silenciosamente.
- En `audio_handler`, capturar la excepción tipada y elegir el mensaje por causa
  (ej.: "Esta canción está restringida por edad", "No disponible en tu región", "Esta canción ya no está disponible").
- El flujo de fallback existente (`fallbackChain`) debe seguir funcionando igual.

**Criterio de aceptación**: reproducir un video no disponible muestra un mensaje que refleja la causa
aproximada; la reproducción normal y los fallbacks no cambian de comportamiento.

---

## FASE 2 — Optimización

### 2.1 Arranque diferido: mostrar UI antes

**Problema**: `main.dart` (35-148) espera en cadena 7 cajas Hive, `getTemporaryDirectory`,
`audioCache.init()` (escaneo de directorio), `downloadService.init()` (un `existsSync` por entrada),
`statsService.init()` y `audioHandler.restoreSession()` antes de `runApp`. En frío hay pantalla en blanco visible.

**Archivos**: `lib/main.dart`.

**Qué hacer**:

- Mantener **antes** de `runApp` solo lo barato y lo imprescindible para construir los servicios:
  apertura de cajas Hive, creación de servicios, `AudioService.init`, lectura de settings (tema, calidad).
- Mover **detrás del primer frame** (p. ej. `WidgetsBinding.instance.addPostFrameCallback` en el
  root widget o una init-task encadenada): `audioCache.init()`, `downloadService.init()`,
  `statsService.init()` y `audioHandler.restoreSession()`.
- Cuidado con carreras: si el usuario toca reproducir antes de que termine `restoreSession`,
  mantener las guardas ya existentes en `audio_handler` (no iniciar dos sesiones a la vez).
- `YTMusic.create()` es local (sin red) — puede quedarse antes de `runApp`.

**Criterio de aceptación**: primer frame visiblemente más rápido en arranque en frío; la sesión se
restaura igual (cola, posición); la pestaña de descargas lista todo al abrirla; sin duplicación de restauración.

### 2.2 Paginación de búsqueda (más de 20 resultados)

**Problema**: `_search` y `searchSongs` fijan `limit: 20` (`yt_service.dart` 86-128) y la pantalla
renderiza una lista finita. **El paquete ya pagina internamente hasta el `limit`**, así que basta
con pedir más resultados por páginas desde la app.

**Archivos**: `lib/data/services/yt_service.dart`, `lib/providers/music_providers.dart` (o donde
residan los providers de búsqueda), `lib/presentation/screens/search_screen.dart` (131-136).

**Qué hacer (opción A, recomendada)**:

- Provider de búsqueda con estado de página acumulado (ej. `Notifier` con `page` y lista acumulada).
- "Cargar más" (botón al final de la lista o scroll infinito con `ScrollController`): llama
  `searchSongs(query, limit: (page + 1) * 20)` y **deduplica por `song.id`** al anexar
  (los resultados pueden variar levemente entre peticiones). La key de caché ya incluye el `limit`,
  así que cada profundidad queda cacheada 10 min.
- Replicar para álbumes y artistas (los 3 tabs). Para álbumes/artistas los sets son más pequeños:
  basta con subir su `limit` a 40-60 en una sola llamada si no se paginará.

**Criterio de aceptación**: una búsqueda popular permite ver 40+ canciones sin duplicados;
el cacheo actual sigue funcionando; los otros tabs no se rompen.

### 2.3 Pantalla de álbum: no reconstruir la lista 10 veces por segundo

**Problema**: `album_detail_screen.dart` (~41-44) observa el mapa completo
`downloadProgressProvider` para calcular un booleano; el progreso se emite cada 100 ms, así que
toda la lista (con todos los `SongTile`) se reconstruye ~10 veces/seg durante cualquier descarga.

**Archivos**: `lib/presentation/screens/album_detail_screen.dart` (41-44 y 136-142).

**Qué hacer**:

- Sustituir por `ref.watch(downloadProgressProvider.select((m) => <booleano derivado>))`
  (¿alguna de las canciones de este álbum está en progreso?) o por un provider derivado
  `family` que exponga el booleano.
- De paso: añadir `key: ValueKey(song.id)` a los `SongTile` generados con `.map` (136-142).

**Criterio de aceptación**: con una descarga activa en otra pantalla, el build de la pantalla de
álbum no se dispara (verificar con `debugPrint` temporal o DevTools); el badge de progreso local sigue actualizándose.

### 2.4 Estadísticas: computar solo cuando alguien mira

**Problema**: `listening_stats_service.dart` (~183-255) recalcula el snapshot completo (escaneo de
todas las claves `song:` del box, deserialización, orden) en cada flush de escucha (~10 s de playback)
y lo emite por un broadcast aunque nadie escuche. Además `statsProvider` no es autoDispose
(`downloads_providers.dart` ~70-76), así que abrir Stats una vez mantiene reconstrucciones toda la sesión.

**Archivos**: `lib/data/services/listening_stats_service.dart`, `lib/providers/downloads_providers.dart`, `lib/presentation/screens/stats_screen.dart`.

**Qué hacer**:

- En el servicio: solo emitir snapshot si `_changes.hasListener`; mantener el último snapshot
  cacheado y recalcular solo con un dirty flag cuando cambien datos.
- En el provider: hacerlo `autoDispose` para que muera al cerrar la pantalla.

**Criterio de aceptación**: reproduciendo con Stats cerrada no hay recomputes (verificar con log
temporal); abrir Stats muestra datos correctos y actualizados.

### 2.5 Home dividido en secciones independientes

**Problema**: `home_screen.dart` (55-83) observa `downloadsProvider`, `historyProvider`,
`favoritesProvider` y `playlistsProvider` en la raíz del `CustomScrollView`. `historyProvider`
re-emite tras cada canción y Home vive en un `IndexedStack` siempre montado → Home entero se
reconstruye en cada cambio de canción incluso en otra pestaña.

**Archivos**: `lib/presentation/screens/home_screen.dart`, `lib/presentation/navigation/main_scaffold.dart`.

**Qué hacer**:

- Extraer cada sección a su propio `ConsumerWidget`: Seguir escuchando, Hecho para ti, Spotlight de
  artista, Álbumes recientes, Tus playlists, Favoritos, banner offline, saludo.
- Cada sección observa solo sus datos (con `.select` donde aporte). El scaffold contenedor queda casi sin watches.
- Mantener el layout visual exactamente igual (mismos slivers, mismos paddings).

**Criterio de aceptación**: con un `debugPrint` temporal en cada sección, un cambio de canción solo
reconstruye "Seguir escuchando"; visualmente no cambia nada.

### 2.6 Spotlight de artista por `family`

**Problema**: `home_providers.dart` (~197-226) `artistSpotlightProvider` observa
`currentSongProvider`: cada cambio de canción re-ejecuta la cadena artista+página+canciones+radio.

**Archivos**: `lib/providers/home_providers.dart`, `lib/presentation/screens/home_screen.dart` (sección spotlight).

**Qué hacer**:

- Convertirlo a `autoDispose.family` keyed por `artistId`; el widget resuelve el artistId de la
  canción actual y solo cambia el parámetro cuando cambia el artista (no la canción).

**Criterio de aceptación**: avanzar entre canciones del mismo artista no dispara refetch;
al cambiar a un artista distinto, carga el nuevo spotlight.

### 2.7 Timer de 750 ms solo mientras suena música

**Problema**: `audio_handler.dart` (68-71) arranca `Timer.periodic(750ms)` en el constructor y solo
lo cancela en `dispose`; cada tick lee Hive dos veces para crossfade (`_crossfadeEnabled` /
`_crossfadeDuration`, 906-938).

**Archivos**: `lib/data/services/audio_handler.dart`.

**Qué hacer**:

- Arrancar el timer al pasar a playing; cancelarlo en pausa / cola vacía (y recrearlo al reanudar).
- Cachear los valores de crossfade: leerlos una vez por carga de canción (o suscribirse a cambios
  del box de settings) en lugar de leer Hive en cada tick.

**Criterio de aceptación**: en pausa no corre el timer; el crossfade sigue funcionando y refleja
cambios hechos en Ajustes sin reiniciar la app.

### 2.8 Letras virtualizadas

**Problema**: `lyrics_sheet.dart` (247-308) construye TODAS las líneas de golpe con
`ListView(children:)` y un `GlobalKey` por línea; cada cambio de línea activa hace `setState` que
reconstruye la columna completa, y el índice activo se recalcula escaneando todas las líneas en cada
evento de posición.

**Archivos**: `lib/presentation/widgets/lyrics_sheet.dart`.

**Qué hacer**:

- Migrar a `ListView.builder` (con el controller existente).
- Calcular el índice activo **incrementalmente** partiendo del índice anterior (avanzar/retroceder
  hasta encontrar la línea correcta) en vez de escanear todo.
- Eliminar el `GlobalKey` por línea: hacer el autoscroll por índice con el controller
  (mantener el comportamiento actual: resaltar línea activa, fade por distancia, tap-línea = seek,
  pausa de 4 s del autoscroll cuando el usuario arrastra).

**Criterio de aceptación**: canción con 100+ líneas sin jank al scrollear el resaltado; tap-línea
hace seek; el pause-on-drag funciona igual.

---

## FASE 3 — Features de usuario

### 3.1 Velocidad de reproducción

**Archivos**: `lib/data/services/audio_handler.dart` (el speed interno está en ~374/396),
`lib/presentation/screens/now_playing_screen.dart`, settings box para persistir.

**Qué hacer**:

- Botón en now playing (icono de velocidad, ej. `1x`) que abre un bottom sheet con
  `0.5x / 0.75x / 1x / 1.25x / 1.5x / 2x`.
- Aplicar con `setSpeed` sobre el player activo (y considerar el player de crossfade).
- Reaplicar la velocidad guardada al cargar cada canción y al iniciar la app (persistir en settingsBox).
- **Revisar**: que la barra de progreso y los tiempos muestren posiciones correctas con velocidad
  distinta de 1x, y que la lógica de crossfade (que usa duraciones) siga siendo coherente.

**Criterio de aceptación**: cambiar la velocidad afecta la reproducción, persiste entre canciones y
sesiones; seek bar correcto; nota para prueba manual con crossfade activado.

### 3.2 Páginas de artista (quitar el callejón sin salida en búsqueda)

**Problema**: los resultados de artista en búsqueda no tienen `onTap` (`search_screen.dart` 203-229)
y no existe ruta de artista, aunque `yt_service` ya tiene `_artistPage` / `getArtistSongs`
(~420-434) y el paquete expone `api.getArtist(channelId)` y `api.getArtistAlbums(...)`.

**Archivos**: nuevo `lib/presentation/screens/artist_screen.dart`; `lib/router/app_router.dart`
(ruta `/artist/:id`); `lib/data/services/yt_service.dart`; `lib/providers/music_providers.dart`;
`lib/presentation/screens/search_screen.dart`.

**Qué hacer**:

- Servicio: método público `getArtistPage(id)` que devuelva un modelo simple
  `{nombre, thumb, cancionesTop, álbumes}` usando `api.getArtist` + `getArtistSongs`; cachear con `_cached`.
- Pantalla: header con imagen y nombre, botones Reproducir/Shuffle, lista de top canciones
  (reutilizar `SongTile`), grid de álbumes que navega a `/album/:id`. Estados de carga con el
  shimmer existente y error con reintento (patrón de la fase 1.2).
- Búsqueda: `onTap` del ListTile de artista → `context.push('/artist/<browseId>')` (el browseId ya
  viene en el `ArtistModel`).
- Reutilizar la ruta como destino del Spotlight de Home si aplica.

**Criterio de aceptación**: desde búsqueda se abre la página del artista, se reproducen sus canciones
y se navega a un álbum; caché evita refetch al reabrir.

### 3.3 Botón "siguiente" nunca muerto al final de la cola

**Problema**: `player_controls.dart` (79-93) deshabilita next cuando `!hasNext`, en vez de recurrir
a la cola inteligente (que ya existe: `_ensureSmartQueue` en `audio_handler.dart` ~675-682, pero
solo se dispara al final natural de la canción).

**Archivos**: `lib/presentation/widgets/player_controls.dart`, `lib/data/services/audio_handler.dart`.

**Qué hacer**:

- Al pulsar next en el último elemento con `autoPlayRelated` activo: invocar la lógica de smart
  queue (añadir related) y avanzar. El botón se habilita si `hasNext || (autoPlayRelated && hay fuente de radio)`.
- Con `autoPlayRelated` desactivado, mantener el comportamiento actual (deshabilitado).

**Criterio de aceptación**: al llegar al final de la cola manualmente, sigue reproduciendo música
relacionada; con la opción desactivada, el botón se deshabilita como hoy.

### 3.4 Ordenar Favoritos, Historial y Descargas

**Problema**: ninguna colección tiene orden/filter; solo el orden de inserción.

**Archivos**: `lib/presentation/screens/library_collection_screen.dart` (favoritos e historial),
`lib/presentation/screens/downloads_screen.dart`, settings box para persistir.

**Qué hacer**:

- Icono de orden (AppBar) que abre un bottom sheet con opciones: **Por defecto (recientes)**,
  **Título A-Z**, **Artista**, **Duración**.
- Persistir la elección por colección en settingsBox (keys separadas, ej. `sort_favorites`,
  `sort_downloads`) y aplicar al reconstruir.
- No romper multi-select, swipe ni confirmaciones existentes.

**Criterio de aceptación**: el orden elegido persiste entre sesiones por colección; todas las
funciones existentes de cada pantalla siguen operativas.

---

## FASE 4 — Pulido de UI

### 4.1 Pull-to-refresh en Home

**Archivos**: `lib/presentation/screens/home_screen.dart` (CustomScrollView).

**Qué hacer**:

- `RefreshIndicator.adaptive` envolviendo el scroll (con slivers, cuidando que funcione desde el top).
- Al refrescar: invalidar recomendaciones, álbumes recientes y spotlight (los proveedores remotos).

**Criterio de aceptación**: tirar hacia abajo recarga las secciones remotas con sus shimmers; sin
errores de física con el CustomScrollView.

### 4.2 Navegación consistente al reproductor + shuffle en álbum

**Problema**: reproducir desde álbum (`album_detail_screen.dart` ~78-91), playlist
(`playlist_detail_screen.dart` ~555-560) y stats (`stats_screen.dart` ~162-170, 212-220) inicia
audio sin abrir el player, mientras que los `SongTile` sí hacen push a `/now-playing`. El álbum
además no tiene botón de shuffle.

**Qué hacer**:

- Regla única: **toda acción reproducir/shuffle abre el reproductor** (push `/now-playing` tras
  iniciar playback), igual que los tiles.
- Añadir botón shuffle junto a "Reproducir" en la pantalla de álbum.

**Criterio de aceptación**: reproducir desde álbum, playlist o stats abre el player; el shuffle de
álbum funciona y abre el player.

### 4.3 Confirmaciones y deshacer

**Problema**: limpiar caché (4 acciones en `settings_screen.dart` ~150-192) no pide confirmación
mientras borrar descargas sí; quitar de playlist con swipe es instantáneo e irreversible
(`playlist_detail_screen.dart` ~486-506); la key del Dismissible (`ValueKey('${song.id}-$index')`)
puede des-indexar contra un snapshot viejo.

**Qué hacer**:

- Diálogo de confirmación para las 4 limpiezas de caché (mismo patrón que "Borrar todas las descargas").
- Swipe para quitar de playlist → `SnackBar` con acción **"Deshacer"** que reinserta la canción en
  su índice original. Corregir la key del `Dismissible` a una key estable (solo `song.id`).
- Opcional (barato): Deshacer también al quitar de favoritos/historial.

**Criterio de aceptación**: caché pide confirmación; el swipe-remove puede deshacerse durante la
vida del snackbar; no quedan estados inconsistentes tras deshacer.

### 4.4 Eliminar elementos muertos de UI

**Archivos**: `lib/presentation/navigation/main_scaffold.dart` (46-48),
`lib/presentation/screens/settings_screen.dart` (~621-625), `lib/presentation/screens/home_screen.dart` (~100-115).

**Qué hacer**:

- Tab "Buscar": añadir `selectedIcon` coherente con las demás pestañas.
- Fila "Controles en pantalla de bloqueo" en Ajustes: es texto estático que parece botón —
  convertirla en fila informativa no interactiva (sin ripple, subtítulo "Siempre activada") o eliminarla.
- Avatar decorativo de Home: conectarlo a algo real (sugerencia: abrir Ajustes) o eliminarlo.

**Criterio de aceptación**: ningún elemento de la UI parece accionable sin tener función.

### 4.5 Accesibilidad básica

**Archivos**: `lib/app.dart` (builder del MaterialApp), `lib/presentation/screens/home_screen.dart`
(overlay play 36x36 en ~366-375, badge 8.5pt ~397), `lib/presentation/screens/playlists_screen.dart`
(iconos popup 21px ~293-297), `lib/presentation/widgets/player_controls.dart` (shuffle al 48% alpha ~48),
`lib/presentation/widgets/song_tile.dart`.

**Qué hacer**:

- Clamp de escala de texto global: en `MaterialApp.builder`, envolver con
  `MediaQuery(textScaler: TextScaler.clamped(max: 1.4))` (o revisar y arreglar los overflows que
  aparezcan con `textScale 1.4`).
- Targets de toque ≥ 48dp: overlay de play de home, iconos de popup de playlists (área táctil, no
  necesariamente el tamaño visual).
- Contraste del estado inactivo de shuffle/repeat (subir alpha o usar color fijo secundario).
- Completar `tooltip`/`Semantics` en los `IconButton` del player y acciones de tiles que no lo tengan.

**Criterio de aceptación**: con textScale 1.4 no hay overflows críticos; TalkBack anuncia las
acciones principales del reproductor; nada con target < 48dp en las zonas mencionadas.

### 4.6 Transiciones uniformes y edge-to-edge

**Archivos**: `lib/router/app_router.dart` (20-42), `lib/main.dart` o `lib/app.dart`,
`lib/presentation/screens/now_playing_screen.dart` (684-688 como referencia).

**Qué hacer**:

- Definir `PageTransitionsTheme` o transiciones por ruta: fade-through para navegación entre tabs,
  slide-up/fade suave para pantallas de detalle (álbum, artista, playlist, descargas, stats), en
  línea con el `CustomTransitionPage` ya existente de `/now-playing`.
- Edge-to-edge unificado: `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` al arrancar
  y `AnnotatedRegion<SystemUiOverlayStyle>` con el estilo derivado del tema en las pantallas raíz,
  para que el color del nav bar no "salte" entre el player y el resto de la app.

**Criterio de aceptación**: la navegación entre pantallas es fluida y consistente; la barra de
navegación del sistema mantiene un estilo coherente en toda la app.

---

## Verificación final (tras completar todo)

1. `flutter analyze` → 0 errores y 0 warnings nuevos respecto al estado inicial.
2. `flutter test` → en verde.
3. `flutter build apk --release` → compila.
4. **Smoke test manual en dispositivo** (checklist):
   - Reproducir, pausar, siguiente/anterior, seek, cola (reordenar, quitar, guardar como playlist).
   - Búsqueda con "Cargar más" en los 3 tabs; navegar a álbum y a artista.
   - Descarga de canción/álbum/playlist con progreso; borrar descarga.
   - Letras sincronizadas en canción larga; tap-línea = seek.
   - Crossfade activado + velocidad ≠ 1x juntos.
   - Modo avión → errores con reintentar; reconectar → todo recarga (sin vacíos cacheados).
   - Background/auriculares: controles de notificación, desconexión de auriculares pausa.
   - Rotación y textScale 1.4 en Home y now playing.

## Cómo ejecutar este plan (recomendación de workflow)

- **Una sesión de IA por fase** (el contexto se agota rápido en refactors de 13k líneas). El prompt
  por sesión: _"Lee PLAN_DE_MEJORAS.md y ejecuta la Fase N completa, tarea por tarea, siguiendo las
  reglas obligatorias de la sección 1. Haz commit al final de cada tarea."_
- No mezclar fases en una misma sesión (la Fase 2 son refactors; la 3 y 4 son features/UI).
- Ejecutar las fases en orden: 1 → 2 → 3 → 4 (la 1 construye los patrones de error/reintento que
  reutilizan la 3.2 y otras).
- Cada tarea termina con commit propio para poder revertir granularmente.
