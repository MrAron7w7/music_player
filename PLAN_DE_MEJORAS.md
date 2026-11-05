# PLAN DE MEJORAS — Buscador e Inicio

**Proyecto:** Simple Music (Flutter)  
**Versión de referencia:** 2.0.6+6  
**Fecha:** Noviembre de 2026  
**Tipo de documento:** plan técnico y de producto, listo para implementar por fases.  
**Alcance:** mejoras del punto **2. Buscador** y del punto **4. Inicio** solicitadas para la aplicación.

> Este documento **no implementa código**. Define qué se va a construir, cómo se integra con la arquitectura actual, qué archivos se tocan, qué se cachea, cómo se pagina, qué se prueba y cuáles son los criterios para considerar cada mejora terminada.

---

## Índice

1. [Resumen ejecutivo](#1-resumen-ejecutivo)
2. [Alcance, principios y no objetivos](#2-alcance-principios-y-no-objetivos)
3. [Punto de partida: qué existe hoy](#3-punto-de-partida-qué-existe-hoy)
4. [Matriz de cobertura de las mejoras](#4-matriz-de-cobertura-de-las-mejoras)
5. [Buscador: plan detallado](#5-buscador-plan-detallado)
6. [Inicio: plan detallado](#6-inicio-plan-detallado)
7. [Arquitectura técnica propuesta](#7-arquitectura-técnica-propuesta)
8. [Caché, datos y rendimiento](#8-caché-datos-y-rendimiento)
9. [Fases de implementación](#9-fases-de-implementación)
10. [Plan de pruebas y QA](#10-plan-de-pruebas-y-qa)
11. [Criterios de aceptación globales](#11-criterios-de-aceptación-globales)
12. [Riesgos y mitigaciones](#12-riesgos-y-mitigaciones)
13. [Checklist de implementación](#13-checklist-de-implementación)
14. [Anexos](#14-anexos)

---

## 1. Resumen ejecutivo

La aplicación ya tiene una base sólida: reproducción, cola, descargas, favoritos, historial, playlists locales, letras, estadísticas, búsqueda por canciones/álbumes/artistas y una pantalla de Inicio con recomendaciones. Las mejoras de este plan no reemplazan esa base: la amplían, la ordenan y la optimizan.

El trabajo se divide en dos grandes bloques:

### Buscador

Se convertirá en un buscador completo y rápido:

- Una pestaña **Todo** que combina el mejor resultado con canciones, álbumes, artistas y playlists.
- Búsqueda de **playlists públicas** de YouTube Music, con pantalla de detalle, reproducción, descarga y guardado local.
- **Filtros** reales: solo descargados, duración, año, género y calidad (con un comportamiento honesto para los metadatos que la API no expone).
- **Búsqueda offline real** de la biblioteca descargada, sin bloquear la pantalla cuando el modo offline está activo.
- **Orden** por relevancia, popularidad, duración, recientes y A-Z.
- **Autocompletado** con sugerencias en vivo.
- **Tendencias y géneros** para explorar desde la búsqueda.
- Búsqueda dentro de **playlists, cola y descargas**.
- Búsqueda por **letra** en el contenido local/cacheado.
- **Paginación** también para álbumes, artistas y playlists.
- **Acciones masivas** sobre resultados.
- Borrado de búsquedas **individuales**.
- **Búsqueda por voz**.
- **Corrección de erratas** (“quizás quisiste decir”).
- Estado **sin resultados** con sugerencias y acciones útiles.

### Inicio

Se convertirá en un feed musical personalizado, modular y con carga progresiva:

- **Daily Mix**, **Novedades**, **Tendencias/Charts**, **Géneros**, **Porque escuchaste…**, **Redescubre**, **Top artistas** y **Nuevo de artistas que sigues**.
- **“Ver todo”** en cada sección.
- **Mezclas por estado de ánimo/actividad**: enfocado, gym, chill, etc.
- **Chips de reproducción reciente**.

### Decisiones técnicas clave

1. **Una sola llamada para “Todo”**: la búsqueda combinada usa la búsqueda mixta de YouTube Music y agrupa los resultados por tipo. Las pestañas específicas solo piden datos cuando hacen falta.
2. **Caché primero (stale-while-revalidate)**: se muestra lo cacheado al instante y se actualiza en segundo plano. Esto aplica a búsqueda, playlists públicas, Explore, Charts y secciones de Inicio.
3. **Inicio perezoso**: cada sección es independiente y solo se construye/carga cuando se acerca al viewport. Un fallo en una sección no rompe las demás.
4. **Offline local-first**: la búsqueda offline usa un índice local de descargas, favoritos, historial y playlists; no hace llamadas de red y no bloquea la pantalla.
5. **Una llamada de Explore para tres secciones**: `getExplore()` entrega Novedades, Tendencias y Géneros en una sola respuesta; se cachea y se comparte entre Buscador e Inicio.
6. **Reutilizar lo que ya existe**: búsqueda dentro de playlist, búsqueda en descargas, multiselección de biblioteca, descarga masiva, cola, letras y estadísticas ya están implementadas. Se extienden, no se duplican.
7. **Limitaciones transparentes**: YouTube Music no expone calidad de audio, género ni popularidad por cada resultado de búsqueda. El plan define qué se puede hacer de verdad y cómo mostrarlo sin engañar al usuario.
8. **Sin restricciones por edad**: no se reintroduce ningún filtro de contenido por edad. El campo `isExplicit` se mantiene solo como información visual, nunca como bloqueo.

---

## 2. Alcance, principios y no objetivos

### 2.1 Objetivos

- Implementar todas las mejoras de **Buscador** e **Inicio** listadas en el punto 2 y el punto 4 de la solicitud.
- Mantener la reproducción, la cola, las descargas, los favoritos, el historial, las playlists locales y las estadísticas sin regresiones.
- Reducir llamadas de red y evitar bloqueos de UI.
- Dar una experiencia consistente en modo online y offline.
- Dejar el código preparado para crecer: modelos tipados, servicios con responsabilidades claras, providers independientes y pruebas.
- Medir el resultado con criterios de aceptación verificables.

### 2.2 Principios de diseño

| Principio | Aplicación concreta |
|---|---|
| **Rendimiento percibido** | Mostrar caché primero; esqueletos con la misma altura que el contenido; evitar saltos de layout. |
| **Menos red, más caché** | Deduplicar requests, cachear por consulta/límite, reutilizar `getExplore()` y `getRelatedSongs()`. |
| **Paginación eficiente** | Fetch inicial pequeño, “Cargar más” por bloques, deduplicación por ID y límite máximo. |
| **Local-first en offline** | Índice local de la biblioteca; cero llamadas cuando el modo offline está activo. |
| **UI modular** | Secciones y tarjetas reutilizables; un provider por sección; un widget por tipo de resultado. |
| **Errores aislados** | Un fallo de red en una sección no tumba la pantalla; se muestra error/retry solo en esa sección. |
| **Honestidad de datos** | No inventar filtros que la API no soporta; explicar el comportamiento en la propia UI. |
| **Accesibilidad** | Etiquetas semánticas, tooltips, objetivos táctiles de 48 dp, soporte de texto grande. |
| **Compatibilidad** | Cambios aditivos en modelos/providers; conservar nombres y comportamientos existentes cuando sea posible. |

### 2.3 No objetivos de este plan

- No se implementa un backend propio.
- No se añade sincronización con la cuenta de YouTube Music (seguir artistas será local).
- No se implementa búsqueda global de letras en Internet; la búsqueda por letra será local/cacheada.
- No se implementa descarga de audio de playlists públicas más allá de lo que ya permite el sistema de descargas actual.
- No se cambia el sistema de reproducción ni el motor de audio.
- No se reintroducen restricciones por edad ni filtros de contenido explícito.
- No se rediseña la identidad visual completa; se mantiene el lenguaje visual actual (glass, tarjetas, gradientes, tipografía).

---

## 3. Punto de partida: qué existe hoy

### 3.1 Buscador actual

| Elemento | Estado actual | Archivo principal |
|---|---|---|
| Pantalla de búsqueda | Pestañas **Canciones**, **Álbumes**, **Artistas**. Historial de búsquedas. | `lib/presentation/screens/search_screen.dart` |
| Query global | `searchQueryProvider` (StateProvider). | `lib/providers/music_providers.dart` |
| Canciones | `SearchSongsNotifier` con paginación por `limit` creciente y refetch. | `lib/providers/music_providers.dart` |
| Álbumes y artistas | `FutureProvider` sin paginación; solo se piden al abrir la pestaña. | `lib/providers/music_providers.dart` |
| Playlists públicas | No existen en la búsqueda. `PlaylistModel` es local (Hive). | `lib/data/models/playlist_model.dart` |
| Modo offline | Bloquea la búsqueda con un `EmptyState`; no busca en la biblioteca. | `search_screen.dart` |
| Filtros | No existen. | — |
| Orden | No existe; se usa el orden de la API. | — |
| Autocompletado | No existe. El paquete soporta `getSearchSuggestions`. | `ytmusicapi_dart` |
| Tendencias/géneros | No existen en la búsqueda. | — |
| Buscar dentro de playlist | Ya existe un campo `_searchQuery` en el detalle de playlist. | `lib/presentation/screens/playlist_detail_screen.dart` |
| Buscar dentro de descargas | Ya existe `downloadsSearchQueryProvider` y filtro por título/artista. | `lib/presentation/screens/downloads_screen.dart` |
| Buscar dentro de la cola | No existe. | `lib/presentation/screens/now_playing_screen.dart` |
| Buscar por letra | Existe `songLyricsProvider` para ver letras, pero no búsqueda por letra. | `lib/providers/music_providers.dart` |
| Acciones masivas | La biblioteca ya tiene multiselección; la búsqueda no. | `lib/presentation/screens/library_collection_screen.dart` |
| Borrar historial | Solo “Borrar” todo. | `search_screen.dart` |
| Voz | No existe. | — |
| Corrección de erratas | No se muestra; la API autocorrige por defecto. | `ytmusicapi_dart` |
| Sin resultados | `EmptyState` simple, sin sugerencias ni acciones. | `search_screen.dart` |
| Caché | `YtService` cachea en memoria y `AppCache` en disco por consulta/tipo/límite. | `lib/data/services/yt_service.dart`, `app_cache.dart` |

### 3.2 Inicio actual

| Elemento | Estado actual | Archivo principal |
|---|---|---|
| Estructura | `ListView` con secciones fijas. | `lib/presentation/screens/home_screen.dart` |
| Saludo y avatar | Existe. | `home_screen.dart` |
| Seguir escuchando | Historial, filtrado por descargas si está offline. | `home_screen.dart` |
| Para ti | Recomendaciones remotas con caché diaria. | `lib/providers/home_providers.dart` |
| Spotlight del artista | Sección contextual cuando suena una canción. | `home_providers.dart` |
| Álbumes recientes | Derivados del historial, sin red. | `home_providers.dart` |
| Playlists locales | Sección con playlists de Hive. | `home_screen.dart` |
| Favoritos | Sección con favoritos. | `home_screen.dart` |
| Estadísticas | `ListeningStatsService` con top songs, top artists, recientes y tiempos. | `lib/data/services/listening_stats_service.dart` |
| Daily Mix, Novedades, Charts, Géneros, Porque escuchaste, Redescubre, Top artistas, Seguidos | No existen. | — |
| “Ver todo” | No existe. | — |
| Mezclas de ánimo/actividad | No existen. | — |
| Chips de reproducción reciente | No existen. | — |
| Modo offline | Muestra banner y filtra algunas secciones, pero no hay estrategia de caché local-first completa. | `home_screen.dart` |

### 3.3 Capacidades reales de la API y del paquete

El paquete `ytmusicapi_dart` 2.4.1 ya ofrece lo necesario para casi todo:

| Capacidad | Método / dato | Uso en el plan |
|---|---|---|
| Búsqueda mixta | `api.search(query, limit: n)` | Pestaña “Todo”; una sola llamada. |
| Búsqueda filtrada | `api.search(query, filter: SearchFilterType.x, limit: n, ignoreSpelling: bool)` | Canciones, álbumes, artistas, playlists. |
| Filtros de playlist | `SearchFilterType.playlists`, `community_playlists`, `featured_playlists` | Playlists públicas. |
| Sugerencias | `api.getSearchSuggestions(query, detailedRuns: true)` | Autocompletado y “quizás quisiste decir”. |
| Borrar sugerencias del historial de YT | `api.removeSearchSuggestions(...)` | Opcional; no imprescindible. |
| Playlist pública | `api.getPlaylist(id, limit: 100)` | Pantalla de playlist pública. |
| Explore | `api.getExplore()` | Novedades, Tendencias y Géneros en una llamada. |
| Moods & Genres | `api.getMoodCategories()`, `api.getMoodPlaylists(params)` | Explorador de géneros y mezclas de ánimo. |
| Charts | `api.getCharts(country: 'ZZ')` | Tendencias/Charts. |
| Artista | `api.getArtist(id)`, `api.getArtistAlbums(...)` | Nuevo de artistas seguidos. |
| Relacionados | `api.getWatchPlaylist(...)`, `api.getSongRelated(...)` | Daily Mix y “Porque escuchaste”. |
| Letras | `api.getLyrics(videoId)` (a través de `YtService.getLyricsForSong`) | Búsqueda por letra local/cacheada. |

### 3.4 Limitaciones reales que el plan resuelve con decisiones explícitas

| Limitación | Qué significa | Decisión del plan |
|---|---|---|
| **Calidad por resultado** | YouTube Music no devuelve la calidad de audio de cada canción en la búsqueda. | En el catálogo, “Calidad” no filtra resultados: abre/ajusta la calidad de reproducción. En “Mi biblioteca”, sí filtra descargas por `DownloadEntry.quality` (ya existe el campo). |
| **Género por resultado** | La búsqueda no devuelve género por canción/álbum. | En el catálogo, “Género” refina la búsqueda/abre Moods & Genres; en la biblioteca, filtra si el contenido tiene género guardado. Se muestra como “Género (aprox.)” cuando aplica. |
| **Popularidad** | La búsqueda no devuelve reproducciones por canción. | Se usa el orden de relevancia de la API; en Charts se usa `rank`; en local se usan las reproducciones de estadísticas. La opción se deshabilita con explicación donde no hay métrica. |
| **Año en canciones** | Muchas canciones no traen año; los álbumes sí suelen traerlo. | El filtro de año se aplica a álbumes siempre y a canciones solo cuando el año existe. Se indica “N resultados sin año ocultos”. |
| **Paginación sin token** | El paquete maneja continuaciones internamente, pero no expone un token de continuación. | Estrategia por `limit` creciente + caché + deduplicación. Si en el futuro se necesita paginación incremental pura, se valora un fork del paquete. |
| **Playlists públicas** | El modelo `PlaylistModel` es local y no sirve para playlists de YouTube Music. | Nuevo `PublicPlaylistModel` + `PublicPlaylistPage` + pantalla/ruta propias. |
| **Letras globales** | No hay API de búsqueda por letra; obtener letras de todos los resultados sería costoso. | Índice local de letras cacheadas/descargadas; no se hacen N llamadas por búsqueda. |
| **Voz** | Requiere dependencia y permiso de micrófono. | `speech_to_text` + `RECORD_AUDIO`; botón oculto o deshabilitado si no está disponible. |
| **Seguir artistas** | No existe en la app y el paquete no expone `subscribeArtist`. | Seguimiento local en Hive; no se sincroniza con la cuenta de YouTube Music. |
| **API de “recientes”** | No hay fecha de lanzamiento fiable en todos los resultados. | Para “Recientes” se usa año cuando existe y, si no, historial local/orden de la API. |
| **Género local** | La app no guarda género por canción. | Se añade un campo opcional `genre` a los modelos, poblado solo cuando la fuente lo aporta (moods/géneros); el filtro se muestra cuando hay datos. |

---

## 4. Matriz de cobertura de las mejoras

### 4.1 Buscador

| # | Mejora solicitada | Prioridad | Sección del plan | Fase |
|---|---|---|---|---|
| 1 | Pestaña “Todo” con mejores resultados combinados | Alta | 5.1 | 1A |
| 2 | Buscar playlists públicas | Alta | 5.2 | 1A |
| 3 | Filtros: solo descargados/offline, duración, año, género, calidad | Alta | 5.3 | 1B |
| 4 | Búsqueda offline real de la biblioteca descargada | Alta | 5.4 | 1B |
| 5 | Ordenar por relevancia, popularidad, duración, recientes, A-Z | Media | 5.5 | 2 |
| 6 | Autocompletado/sugerencias en vivo | Media | 5.6 | 1A |
| 7 | Tendencias y géneros para explorar | Media | 5.7 | 2 |
| 8 | Buscar dentro de playlists, cola y descargas | Media | 5.8 | 2 |
| 9 | Buscar por letra | Media | 5.9 | 2 |
| 10 | Paginación también para álbumes y artistas | Media | 5.10 | 1A |
| 11 | Acciones masivas sobre resultados | Media | 5.11 | 2 |
| 12 | Borrar búsquedas individuales | Baja | 5.12 | 1A |
| 13 | Búsqueda por voz | Baja | 5.13 | 5 |
| 14 | Corrección de erratas (“quizás quisiste decir”) | Baja | 5.14 | 2 |
| 15 | Estado “sin resultados” con sugerencias | Baja | 5.15 | 1A |

> **Nota de fases:** “1A” y “1B” son subfases del Buscador. La fase 1A entrega el núcleo visible; la 1B añade filtros y offline real. La fase 2 completa las mejoras medias/bajas del Buscador. La fase 5 incluye la voz y los últimos detalles.

### 4.2 Inicio

| # | Mejora solicitada | Prioridad | Sección del plan | Fase |
|---|---|---|---|---|
| 1 | Daily Mix | Alta | 6.1 | 4 |
| 2 | Novedades | Alta | 6.2 | 4 |
| 3 | Tendencias/Charts | Alta | 6.3 | 4 |
| 4 | Géneros | Alta | 6.4 | 4 |
| 5 | “Porque escuchaste…” | Alta | 6.5 | 4 |
| 6 | “Redescubre” | Alta | 6.6 | 4 |
| 7 | Top artistas | Alta | 6.7 | 4 |
| 8 | Nuevo de artistas que sigues | Alta | 6.8 | 5 |
| 9 | “Ver todo” en cada sección | Media | 6.9 | 3 |
| 10 | Mezclas por estado de ánimo/actividad | Media | 6.10 | 5 |
| 11 | Chips de reproducción reciente | Baja | 6.11 | 5 |

> **Nota:** la fase 3 prepara la estructura de Inicio (slivers, secciones independientes, “Ver todo”, offline/caché). La fase 4 añade el contenido de prioridad alta. La fase 5 añade seguidos, mezclas de ánimo, chips recientes, voz y pulido.

---

## 5. Buscador: plan detallado

### 5.0 Experiencia general del Buscador

La pantalla de búsqueda se reorganiza en cuatro zonas:

1. **Cabecera**: título “Buscar”, barra de búsqueda con micrófono, botón de limpiar y botón de filtros con contador.
2. **Sugerencias**: panel desplegable debajo de la barra cuando el campo tiene foco, hay texto y existen sugerencias.
3. **Navegación**: si la consulta está vacía se muestra **Explorar** (historial, tendencias, géneros y accesos a la biblioteca). Si hay consulta se muestran las pestañas **Todo · Canciones · Álbumes · Artistas · Playlists** en una fila horizontal desplazable.
4. **Resultados**: contenido de la pestaña activa, con chips de filtros activos, contador de resultados y estados de carga/error/vacío.

Estados que debe cubrir la pantalla:

| Estado | Qué se muestra |
|---|---|
| **Inicial** | Explorar: búsquedas recientes, tendencias, géneros, accesos a Descargas/Favoritos/Playlists. |
| **Escribiendo** | Sugerencias en vivo; la búsqueda remota se dispara tras el debounce. |
| **Cargando** | Esqueletos con la altura del contenido; no un spinner de pantalla completa. |
| **Con resultados** | Pestaña activa + chips de filtros + “Cargar más” si aplica. |
| **Sin resultados** | Mensaje claro, sugerencia de ortografía, acciones (quitar filtros, buscar en biblioteca, ver descargas, explorar géneros). |
| **Sin conexión** | Resultados locales de la biblioteca + banner informativo; nunca un bloqueo. |
| **Error de red** | Error solo en la sección afectada, con “Reintentar” y opción de buscar en la biblioteca. |
| **Selección múltiple** | Barra contextual con acciones masivas y contador. |

Componentes nuevos o extraídos:

- `SearchHeader` (título + barra + filtros).
- `SearchSuggestionsPanel`.
- `SearchTabs` (horizontal, con `TabBar` o chips).
- `SearchDiscovery` (historial, tendencias, géneros).
- `SearchResultsView`.
- `SearchFilterSheet`.
- `SearchActiveFilters`.
- `SearchEmptyState`.
- `SearchSelectionBar`.
- `SearchLoadMore` (reutilizable para canciones, álbumes, artistas y playlists).
- `SectionHeader` (reutilizado por Buscador e Inicio, con “Ver todo” opcional).

#### Comportamiento de la consulta

- **Debounce**: 250 ms para la búsqueda; 200 ms para sugerencias.
- **Longitud mínima**: 2 caracteres para búsqueda remota; 1 carácter para búsqueda local.
- **Cancelación**: cada cambio de consulta invalida la respuesta anterior. El notifier comprueba un `requestId` antes de aplicar resultados.
- **Historial**: se guarda al enviar (Enter) y al elegir una sugerencia o un resultado de tendencia; no en cada pulsación. La consulta se normaliza (trim, espacios colapsados) y se deduplica sin distinguir mayúsculas.
- **Persistencia de pestaña**: al cambiar de pestaña se conserva la consulta, los filtros y el scroll de cada pestaña mediante `PageStorageKey`.
- **Teclado**: `textInputAction: search`; al enviar se cierra el teclado y se guarda el historial.
- **Accesibilidad**: la barra tiene `Semantics(label: 'Buscar canciones, álbumes, artistas o playlists')`; los iconos tienen tooltip; los chips son navegables por teclado/lector de pantalla.

---

### 5.1 Pestaña “Todo” con mejores resultados combinados

**Prioridad:** Alta · **Fase:** 1A

#### Objetivo

Que el usuario escriba una consulta y vea en una sola pantalla el mejor resultado y un resumen de canciones, álbumes, artistas y playlists, sin tener que cambiar de pestaña ni esperar cuatro llamadas.

#### Experiencia de usuario

- La pestaña “Todo” es la pestaña inicial cuando hay consulta.
- Orden visual:
  1. **Mejor resultado** (tarjeta grande con portada, título, tipo y acción de reproducir/abrir).
  2. **Canciones** (hasta 5, con “Ver todo”).
  3. **Álbumes** (hasta 6, en carrusel horizontal o grid compacto, con “Ver todo”).
  4. **Artistas** (hasta 6, en carrusel circular, con “Ver todo”).
  5. **Playlists** (hasta 6, en carrusel, con “Ver todo”).
- Si una categoría no tiene resultados, se oculta.
- “Ver todo” no abre una pantalla nueva: cambia a la pestaña correspondiente y conserva la consulta y los filtros. Si la pestaña aún no tiene datos, los solicita en ese momento.
- Si hay filtros activos, se aplican a cada grupo; los grupos que quedan vacíos se ocultan. Si todos quedan vacíos, se muestra el estado “Sin resultados con estos filtros”.

#### Implementación

1. **`YtService.searchAll(query, {limit = 20, ignoreSpelling = false})`**
   - Usa `api.search(query, limit: limit, ignoreSpelling: ignoreSpelling)` **sin filtro**.
   - La respuesta mixta incluye un `musicCardShelfRenderer` (mejor resultado) y secciones (`musicShelfRenderer` / `itemSectionRenderer`) con `resultType`.
   - Agrupa por `resultType`:
     - `song` y `video` → canciones (`SongModel`).
     - `album` → álbumes (`AlbumModel`).
     - `artist` → artistas (`ArtistModel`).
     - `playlist` → playlists públicas (`PublicPlaylistModel`).
     - `profile`, `podcast`, `episode` → se ignoran en esta versión.
   - Deduplica por ID dentro de cada grupo.
   - Extrae el mejor resultado a `SearchTopResult` (tipo + modelo + ruta).
   - Cachea el resultado completo.
2. **`SearchAllResult`** (modelo nuevo):
   ```dart
   class SearchAllResult {
     final SearchTopResult? topResult;
     final List<SongModel> songs;
     final List<AlbumModel> albums;
     final List<ArtistModel> artists;
     final List<PublicPlaylistModel> playlists;
     final String query;
     final DateTime fetchedAt;
   }
   ```
3. **Provider `searchAllProvider`**
   - `FutureProvider.autoDispose.family<SearchAllResult, String>`.
   - Solo se activa cuando la pestaña “Todo” está visible y la consulta tiene ≥ 2 caracteres.
   - Aplica `ref.keepAlive()` durante 2 minutos para evitar refetch al cambiar de pestaña.
4. **Vista filtrada**
   - Un `Provider` derivado combina `searchAllProvider` + `searchFiltersProvider` y devuelve `SearchAllResult` filtrado/ordenado.
   - No vuelve a pedir red cuando cambian los filtros.
5. **Mejor resultado**
   - Se muestra como tarjeta destacada; el botón principal depende del tipo:
     - Canción: reproducir y abrir “Reproduciendo”.
     - Álbum: abrir detalle.
     - Artista: abrir artista.
     - Playlist: abrir playlist pública.
6. **“Ver todo”**
   - `SearchTabsController.select(tab)`; si el tab ya tiene datos, se muestran; si no, se dispara su provider.
   - No se navega a una ruta nueva para evitar perder el estado de búsqueda.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/services/yt_service.dart` | Añadir `searchAll`, `searchPlaylists`, `getSearchSuggestions` y el parámetro `ignoreSpelling`. |
| `lib/data/models/search_models.dart` (nuevo) | `SearchAllResult`, `SearchTopResult`, `SearchSuggestion`, `SearchFilters`, `SearchSort`. |
| `lib/providers/search_providers.dart` (nuevo) | `searchAllProvider`, `searchFiltersProvider`, `searchTabProvider`, providers derivados. |
| `lib/presentation/screens/search_screen.dart` | Reestructurar la pantalla y añadir la pestaña “Todo”. |
| `lib/presentation/widgets/search_results_view.dart` (nuevo) | Secciones de “Todo”. |
| `lib/presentation/widgets/section_header.dart` (nuevo) | Título + “Ver todo”. |

#### Caché y rendimiento

- Una sola llamada de red para “Todo” (frente a 4 llamadas si se pidieran canciones, álbumes, artistas y playlists por separado).
- Clave: `search:all:<queryNormalizada>:<limit>:<ignoreSpelling>`.
- TTL memoria: 10 minutos; disco: 6 horas; máximo 120 entradas de búsqueda.
- Si la consulta ya está cacheada, se muestra al instante y se refresca en segundo plano solo si el TTL expiró.
- No se piden las pestañas hijas hasta que el usuario las abre.

#### Limitaciones y decisiones

- La búsqueda mixta puede devolver menos elementos de una categoría que la búsqueda filtrada. Por eso, al abrir una pestaña específica se hace la llamada filtrada si hace falta.
- El “mejor resultado” depende de lo que devuelve YouTube Music; no se recalcula con heurísticas propias para no contradecir la relevancia de la API.
- Los videos se incluyen como canciones porque el motor de reproducción ya trabaja con `SongModel`; los podcasts y episodios se excluyen en esta fase.

#### Criterios de aceptación

- [ ] Al buscar una consulta con resultados mixtos, “Todo” muestra el mejor resultado y al menos dos categorías con datos.
- [ ] La primera carga hace **una sola** petición de red para “Todo”.
- [ ] “Ver todo” cambia a la pestaña correcta sin perder la consulta ni los filtros.
- [ ] Si una categoría está vacía, no se muestra un encabezado vacío.
- [ ] Con caché caliente, el contenido aparece en menos de 300 ms.
- [ ] Los filtros activos se reflejan en todos los grupos y el estado vacío permite quitarlos.

---

### 5.2 Buscar playlists públicas

**Prioridad:** Alta · **Fase:** 1A

#### Objetivo

Permitir buscar, abrir y usar playlists públicas de YouTube Music, no solo playlists locales.

#### Experiencia de usuario

- Nueva pestaña **Playlists** en la búsqueda.
- Cada resultado muestra portada, título, autor, cantidad de canciones y un botón de reproducción rápida.
- Al tocar una playlist se abre una pantalla con:
  - Cabecera con portada, título, autor, cantidad de canciones y duración total (si está disponible).
  - Botones: **Reproducir**, **Aleatorio**, **Descargar**, **Guardar en mi biblioteca**, **Añadir a la cola**.
  - Buscador interno de canciones de la playlist (reutiliza el buscador local).
  - Lista de canciones con `SongTile`.
  - Estados de carga, error, playlist vacía o no disponible.
- “Guardar en mi biblioteca” crea una `PlaylistModel` local con las canciones y la portada; si ya existe una playlist local con el mismo nombre, se permite crear otra o añadir a la existente (se pregunta).
- “Descargar” usa la descarga masiva existente (`DownloadService.downloadMany`) y muestra progreso/resultado.
- “Añadir a la cola” usa `AudioHandler.addSongsToQueue`.

#### Implementación

1. **Modelo `PublicPlaylistModel`** (nuevo):
   ```dart
   class PublicPlaylistModel {
     final String id;            // sin prefijo VL, para rutas
     final String title;
     final String? author;
     final String? description;
     final String? thumbnailUrl;
     final int? itemCount;
     final String? year;
     final int? durationSeconds;
     final bool isOfficial;
   }
   ```
   - `fromJson` robusto:
     - `id`: `browseId` o `playlistId`; quitar `VL` inicial.
     - `author`: puede ser String, Map (`name`) o List de Maps.
     - `itemCount`: `itemCount`, `count` o `trackCount`.
     - `thumbnailUrl`: última miniatura de `thumbnails`.
2. **`YtService.searchPlaylists(query, {limit = 20, ignoreSpelling = false})`**
   - Usa `api.search(query, filter: SearchFilterType.playlists, limit: limit, ignoreSpelling: ignoreSpelling)`.
   - Mapea con `PublicPlaylistModel.fromJson`.
   - Cachea con la misma política que las otras búsquedas.
3. **`YtService.getPublicPlaylist(id, {limit = 100})`**
   - Usa `api.getPlaylist(id, limit: limit)`.
   - Devuelve `PublicPlaylistPage`:
     ```dart
     class PublicPlaylistPage {
       final PublicPlaylistModel playlist;
       final List<SongModel> songs;
     }
     ```
   - Parsea la cabecera (`title`, `author`, `thumbnails`, `description`, `trackCount`, `duration`, `year`) y `tracks`.
   - Filtra entradas sin `videoId` o con IDs que no sean reproducibles (`MPRE`, `MPLA`, etc.).
   - Maneja playlists tipo `OLA`/`VLOLA` (el paquete ya lo hace).
4. **Provider `publicPlaylistProvider`**
   - `FutureProvider.autoDispose.family<PublicPlaylistPage, String>`.
   - Cachea la página en `AppCache` para poder abrirla rápido y, si está disponible, en offline.
5. **Pantalla `PublicPlaylistScreen`**
   - Ruta `/public-playlist/:id`.
   - Cabecera con `Hero` consistente (`public-playlist-<id>`).
   - Buscador interno con `LocalSearchField`.
   - Multiselección de canciones (reutiliza el patrón de la biblioteca) y acciones masivas.
6. **Búsqueda**
   - Pestaña **Playlists** con paginación (ver 5.10).
   - Sección **Playlists** en “Todo”.
7. **Reutilización**
   - La misma pantalla se usa para playlists de Charts, Moods & Genres y Mood Mixes. No se crea una pantalla por origen.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/models/public_playlist_model.dart` (nuevo) | `PublicPlaylistModel`, `PublicPlaylistPage`. |
| `lib/data/services/yt_service.dart` | `searchPlaylists`, `getPublicPlaylist`. |
| `lib/providers/search_providers.dart` | `searchPlaylistsProvider`, `publicPlaylistProvider`. |
| `lib/presentation/screens/public_playlist_screen.dart` (nuevo) | Pantalla de detalle. |
| `lib/router/app_router.dart` | Ruta `/public-playlist/:id`. |
| `lib/presentation/widgets/playlist_card.dart` (nuevo o reutilizado) | Tarjeta de playlist. |

#### Caché y rendimiento

- Búsqueda de playlists: `search:playlists:<query>:<limit>`, 10 min memoria / 6 h disco.
- Detalle: `publicPlaylist:<id>:<limit>`, 30 min memoria / 6 h disco.
- No se descargan todas las canciones de una playlist para mostrar la tarjeta; solo el detalle hace la llamada completa.
- La pantalla de detalle muestra primero la cabecera y las canciones cacheadas; si no hay caché, esqueleto y luego datos.

#### Limitaciones y decisiones

- `PlaylistModel` se mantiene intacto para playlists locales. No se fuerza a las playlists públicas a ese modelo porque tienen campos y ciclo de vida distintos.
- No se implementa “me gusta” ni suscripción a la playlist en YouTube Music; “Guardar en mi biblioteca” es una copia local.
- Las playlists privadas no se pueden abrir sin autenticación; se muestra un error claro.
- El número de canciones y la duración pueden faltar; se muestran solo si existen.

#### Criterios de aceptación

- [ ] Se pueden buscar playlists públicas desde la pestaña Playlists y desde “Todo”.
- [ ] Una playlist pública se abre, muestra sus canciones y se reproduce.
- [ ] “Guardar en mi biblioteca” crea una playlist local visible en Biblioteca.
- [ ] “Descargar” descarga las canciones y respeta la configuración de solo Wi-Fi.
- [ ] La playlist se puede abrir desde Charts y Moods & Genres con la misma pantalla.
- [ ] Si la playlist no está disponible, se muestra un error con reintento y opción de volver.

---

### 5.3 Filtros: solo descargados/offline, duración, año, género y calidad

**Prioridad:** Alta · **Fase:** 1B

#### Objetivo

Que el usuario pueda reducir los resultados sin perder el contexto de la búsqueda, con filtros claros y sin falsas promesas sobre metadatos que la API no entrega.

#### Experiencia de usuario

- Botón de filtros (icono de ajustes) a la derecha de la barra de búsqueda, con un badge que indica cuántos filtros están activos.
- Al pulsarlo se abre un **bottom sheet** con secciones:
  1. **Ámbito**: “Todo el catálogo” / “Mi biblioteca”.
  2. **Solo descargados**: interruptor. Si está activo, solo se muestran canciones/álbumes/artistas con al menos una descarga.
  3. **Duración** (solo canciones): Cualquiera, &lt; 2 min, 2–5 min, 5–10 min, &gt; 10 min.
  4. **Año** (álbumes y canciones con año): Cualquiera, 2020s, 2010s, 2000s, 1990s, 1980s, antes de 1980, rango personalizado.
  5. **Género**: chips de géneros disponibles. En catálogo funciona como refinamiento/exploración; en biblioteca filtra por género guardado.
  6. **Calidad**: en “Mi biblioteca”, Alta/Media/Baja (filtra descargas por `DownloadEntry.quality`). En catálogo, muestra un acceso a la calidad de reproducción y una nota explicativa.
  7. **Orden**: relevancia, popularidad, duración, recientes, A-Z (ver 5.5).
- Botones: **Limpiar** y **Aplicar**.
- Debajo de las pestañas se muestran **chips de filtros activos** con una “X” para quitarlos individualmente.
- Contador: “Mostrando X de Y resultados” cuando hay filtros.
- Si los filtros ocultan todos los resultados pero la búsqueda tiene datos, se muestra:
  - “No hay resultados con estos filtros”.
  - Botón “Quitar filtros”.
  - Texto “X resultados ocultos”.

#### Implementación

1. **Modelo `SearchFilters`**:
   ```dart
   class SearchFilters {
     final SearchScope scope;          // catalog | library
     final bool onlyDownloaded;
     final DurationRange? duration;
     final YearRange? year;
     final Set<String> genres;
     final DownloadQualityFilter? quality;
     final SearchSort sort;
   }
   ```
   - `copyWith`, `isEmpty`, `activeCount`, `toCacheKey`.
   - `matchesSong(SongModel, {required Set<String> downloadedIds, required Map<String, String> downloadQuality})`.
   - `matchesAlbum(AlbumModel, {required Set<String> downloadedAlbumIds})`.
   - `matchesArtist(ArtistModel, {required Set<String> downloadedArtistIds})`.
   - `matchesPublicPlaylist` solo aplica `onlyDownloaded` si se conoce el contenido; si no, se muestra la playlist y se indica que la comprobación se hará al abrirla (o se oculta con una nota).
2. **Provider `searchFiltersProvider`**
   - `StateProvider<SearchFilters>` o `StateNotifier`.
   - Se mantiene durante la sesión; no se persiste por defecto para evitar que el usuario quede atrapado en filtros antiguos. Se puede añadir “Recordar filtros” como ajuste futuro.
3. **Provider derivado de resultados**
   - `searchSongsFilteredProvider`, `searchAlbumsFilteredProvider`, etc., o un `searchViewProvider` que recibe la lista y los filtros.
   - Se calcula en memoria; no hay red al cambiar filtros.
4. **Cálculo de IDs de descargas**
   - `downloadsProvider` ya expone `List<DownloadEntry>`.
   - Derivar:
     - `downloadedSongIdsProvider` (`Set<String>`).
     - `downloadedAlbumIdsProvider` (a partir de `entry.song.albumId`).
     - `downloadedArtistIdsProvider` (a partir de `entry.song.artistIds`).
     - `downloadQualityByIdProvider` (`Map<String, String>`).
   - Estos providers usan `select` para no reconstruir toda la UI cuando cambia el progreso.
5. **Filtros de duración y año**
   - Canción: `SongModel.duration` y `SongModel.year`.
   - Álbum: `AlbumModel.year`.
   - Si el campo es `null`, el elemento no coincide cuando el filtro está activo. Se muestra el aviso “N resultados sin año/duración ocultos”.
   - Para álbumes, la duración no aplica; el control se deshabilita con tooltip.
6. **Género**
   - El catálogo no devuelve género por resultado. El filtro funciona así:
     - **Catálogo**: al elegir un género se añade un chip “Género: Pop (aprox.)” y se refina la consulta con el nombre del género; además se ofrece “Explorar Pop” que abre la página de Moods & Genres. Es un refinamiento, no un filtro estricto.
     - **Biblioteca**: si el contenido tiene `genre` guardado (por ejemplo, canciones guardadas desde una playlist de género), se filtra estrictamente.
   - Si no hay géneros disponibles, la sección muestra “Género no disponible en estos resultados” y un botón “Explorar géneros”.
   - Se añade un campo opcional `genre` a `SongModel` y `AlbumModel` para el contenido que sí lo aporte. No se inventa para los resultados de búsqueda.
7. **Calidad**
   - `DownloadEntry.quality` ya existe (`high`, `medium`, `low`).
   - **Mi biblioteca**: filtro real por calidad de descarga.
   - **Catálogo**: no se filtra por calidad porque la API no la expone; se muestra un acceso a “Calidad de reproducción” en Ajustes y una nota.
   - No se cambia la calidad global de reproducción desde el filtro de búsqueda para no sorprender al usuario.
8. **UI del sheet**
   - `SearchFilterSheet` con `showModalBottomSheet(isScrollControlled: true, useSafeArea: true, showDragHandle: true)`.
   - Secciones con `Wrap` de `FilterChip`/`ChoiceChip`.
   - El botón “Aplicar” solo actualiza el provider; no lanza red.
   - “Limpiar” deja los filtros por defecto.
9. **Persistencia**
   - No se persisten los filtros transitorios. La calidad de reproducción y el modo offline siguen en Ajustes como hoy.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/models/search_models.dart` | `SearchFilters`, `SearchScope`, `DurationRange`, `YearRange`, `DownloadQualityFilter`, `SearchSort`. |
| `lib/providers/search_providers.dart` | `searchFiltersProvider`, providers derivados de descargas y resultados filtrados. |
| `lib/providers/downloads_providers.dart` | Providers derivados de IDs/categorías/calidad de descargas. |
| `lib/presentation/widgets/search_filter_sheet.dart` (nuevo) | UI de filtros. |
| `lib/presentation/screens/search_screen.dart` | Botón, badge, chips activos y estados vacíos por filtros. |
| `lib/data/models/song_model.dart` / `album_model.dart` | Campo opcional `genre` (si se decide persistir el género). |

#### Caché y rendimiento

- Los filtros se aplican en memoria; no generan peticiones.
- Los providers derivados usan `select` y se recalculan solo cuando cambian los resultados o los filtros.
- Si un filtro deja pocos resultados visibles, “Cargar más” sigue disponible para traer más resultados remotos y volver a filtrar.
- Para evitar listas vacías engañosas, si hay filtros activos y la página visible queda vacía pero `hasMore` es true, se puede cargar automáticamente una página adicional (máximo 2 intentos) mostrando “Buscando más resultados…”.

#### Limitaciones y decisiones

- **Calidad** no es un filtro de catálogo; es una preferencia de reproducción/descarga. Se implementa de forma real en la biblioteca.
- **Género** no es un metadato de la búsqueda; se implementa como refinamiento/exploración y como filtro estricto en local cuando hay datos.
- **Año** puede faltar en canciones; se avisa y no se inventa.
- **Duración** no aplica a álbumes/artistas/playlists; el control se deshabilita según la pestaña.
- **Solo descargados** en playlists públicas requiere abrir la playlist para saber qué canciones están descargadas; se indica en la UI.

#### Criterios de aceptación

- [ ] El botón de filtros muestra el número de filtros activos.
- [ ] “Solo descargados” reduce canciones, álbumes y artistas a los que tienen descargas.
- [ ] Duración y año filtran correctamente y avisan de los elementos sin metadato.
- [ ] “Mi biblioteca” + calidad filtra descargas por calidad real.
- [ ] Los chips activos se pueden quitar individualmente y “Limpiar” restaura todo.
- [ ] Si no hay resultados con filtros, se puede quitar el filtro desde el estado vacío.
- [ ] Cambiar filtros no dispara nuevas peticiones de red.

---

### 5.4 Búsqueda offline real de la biblioteca

**Prioridad:** Alta · **Fase:** 1B

#### Objetivo

Que el modo offline deje de bloquear la búsqueda y permita encontrar y reproducir contenido descargado, favorito, del historial y de playlists locales.

#### Experiencia de usuario

- Con el modo offline activo:
  - La barra de búsqueda sigue disponible.
  - Se muestra un banner: “Modo offline · Buscando en tu biblioteca”.
  - La pestaña “Todo” agrupa resultados locales.
  - Las pestañas Canciones, Álbumes, Artistas y Playlists muestran resultados derivados de la biblioteca.
  - Cada canción puede mostrar badges: **Descargada**, **Favorita**, **En playlist**, **Historial**.
  - Si no hay coincidencias: “No encontramos nada en tu biblioteca para ‘X’” + botones “Ver descargas”, “Ver favoritos”, “Desactivar modo offline”.
- Si no hay conexión pero el modo offline manual está desactivado:
  - La búsqueda remota falla; en lugar de un error seco, se muestran los resultados locales con el banner “Sin conexión · resultados de tu biblioteca”.
  - Se ofrece “Reintentar” para volver a intentar la búsqueda remota.
- Abrir un álbum o artista desde un resultado offline:
  - Se usa la versión local del detalle (canciones descargadas/favoritas/historial), no una pantalla que intente cargar de red y falle.
  - Si no hay datos locales suficientes, se muestra un estado vacío con “Este álbum no está descargado”.

#### Implementación

1. **`effectiveOfflineProvider`**
   - `true` si `offlineModeProvider` es true.
   - Además, se puede combinar con `connectivity_plus` (ya está en el proyecto) para detectar `ConnectivityResult.none`, con un pequeño debounce para evitar falsos positivos.
   - El modo offline manual tiene prioridad y es el comportamiento principal.
2. **`LocalSearchService`** (nuevo)
   - Construye un índice a partir de:
     - `downloadsProvider` (prioridad máxima).
     - `favoritesProvider`.
     - `historyProvider`.
     - `playlistsProvider` (canciones y nombres de playlists).
   - Estructura:
     ```dart
     class LocalSearchIndex {
       final List<IndexedSong> songs;
       final List<IndexedAlbum> albums;
       final List<IndexedArtist> artists;
       final List<IndexedPlaylist> playlists;
     }
     ```
   - `IndexedSong` guarda el `SongModel`, fuentes (`downloaded`, `favorite`, `history`, `playlists`) y campos normalizados.
   - Deduplica por `song.id` y fusiona fuentes.
   - Álbumes y artistas se derivan de las canciones; se agrupan por `albumId` / `artistIds` (o nombre si no hay ID).
   - Playlists locales se indexan por nombre y por canciones.
3. **Normalización y ranking**
   - `normalize(text)`: minúsculas, sin tildes, puntuación → espacios, espacios colapsados.
   - `tokenize(query)`: tokens de 1+ caracteres.
   - Puntuación:
     - Título exacto: 100.
     - Título empieza por la consulta: 80.
     - Título contiene: 60.
     - Artista contiene: 40.
     - Álbum contiene: 30.
     - Playlist contiene: 20.
     - Todos los tokens presentes: +10.
     - Bonus por fuente: descargada +15, favorita +8, historial +4.
   - Orden final: puntuación, luego prioridad de fuente, luego título.
4. **Providers**
   - `localSearchIndexProvider`: se construye cuando cambian descargas/favoritos/historial/playlists. Para bibliotecas grandes (> 3000 canciones), se puede construir en un `Isolate` o usar `compute` con datos serializables; para el tamaño típico, es síncrono y rápido.
   - `offlineSearchProvider(query)`: `FutureProvider.autoDispose.family<LocalSearchResult, String>` o `Provider` derivado; devuelve canciones, álbumes, artistas, playlists y el mejor resultado local.
   - `localAlbumProvider(albumId)` y `localArtistProvider(artistId)` para los detalles offline.
5. **UI**
   - `SearchScreen` deja de devolver el `EmptyState` bloqueante.
   - `SearchDiscovery` offline muestra accesos a Descargas, Favoritos, Historial y Playlists.
   - `SearchResultsView` usa `LocalSearchResult` cuando `effectiveOffline` es true.
   - `AlbumDetailScreen` y `ArtistScreen` consultan el modo offline y usan datos locales con banner; si no hay, muestran un estado vacío específico.
6. **Búsqueda dentro de la biblioteca estando online**
   - El filtro “Mi biblioteca” permite usar el mismo índice sin activar el modo offline.
   - Esto también sirve para “buscar dentro de playlists, cola y descargas” (ver 5.8).
7. **Persistencia**
   - No se persiste el índice; se reconstruye en memoria. Es rápido y evita datos obsoletos.
   - Se invalida automáticamente al cambiar descargas, favoritos, historial o playlists.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/services/local_search_service.dart` (nuevo) | Índice local, normalización, ranking y búsqueda. |
| `lib/core/utils/text_utils.dart` (nuevo) | `normalize`, `tokenize`, `levenshtein`, `similarity`. |
| `lib/providers/search_providers.dart` | `localSearchIndexProvider`, `offlineSearchProvider`, `localAlbumProvider`, `localArtistProvider`. |
| `lib/providers/settings_providers.dart` o `network_providers.dart` | `effectiveOfflineProvider` y conectividad. |
| `lib/presentation/screens/search_screen.dart` | Quitar bloqueo offline, banner y resultados locales. |
| `lib/presentation/screens/album_detail_screen.dart` | Fallback local offline. |
| `lib/presentation/screens/artist_screen.dart` | Fallback local offline. |

#### Caché y rendimiento

- Cero llamadas de red en modo offline.
- Índice en memoria; reconstrucción bajo demanda.
- Debounce local de 150 ms (o filtrado directo, porque es barato).
- Para bibliotecas muy grandes, construir el índice en un isolate y devolver listas serializables; no bloquear el hilo de UI.
- Los providers usan `select` para que un cambio en el progreso de descarga no reconstruya toda la lista.

#### Limitaciones y decisiones

- La búsqueda offline solo encuentra contenido **local**: descargas, favoritos, historial y playlists locales. No busca en el catálogo remoto.
- Las letras offline dependen de la caché local (ver 5.9).
- Las playlists públicas guardadas en local se pueden buscar; las no guardadas no.
- La detección automática de conectividad es opcional; el modo offline manual es la fuente de verdad para la experiencia “offline”.

#### Criterios de aceptación

- [ ] Con modo offline activo, la búsqueda no muestra el mensaje bloqueante y devuelve resultados locales.
- [ ] Se encuentran canciones descargadas, favoritas, del historial y de playlists locales.
- [ ] Los badges indican por qué aparece cada canción.
- [ ] Abrir un álbum/artista desde offline no genera un error de red; muestra datos locales o un vacío claro.
- [ ] Al desactivar offline, la búsqueda remota vuelve a funcionar.
- [ ] Si no hay conexión sin modo offline, se muestran resultados locales y un aviso, no un error seco.

---

### 5.5 Orden: relevancia, popularidad, duración, recientes, A-Z

**Prioridad:** Media · **Fase:** 2

#### Objetivo

Permitir reorganizar los resultados según lo que el usuario necesita, sin alterar la consulta ni volver a pedir datos.

#### Experiencia de usuario

- Selector de orden en la fila de filtros o en el sheet de filtros.
- Opciones:
  - **Relevancia** (predeterminado, orden de la API).
  - **Popularidad**.
  - **Duración: menor a mayor** / **mayor a menor**.
  - **Recientes**.
  - **A-Z**.
- Cada pestaña muestra solo las opciones que aplican:
  - Canciones: todas.
  - Álbumes: relevancia, recientes (año), A-Z.
  - Artistas: relevancia, A-Z.
  - Playlists: relevancia, A-Z.
- Si una opción no tiene métrica real, se muestra deshabilitada con un tooltip explicativo.

#### Implementación

1. **`SearchSort` enum**:
   ```dart
   enum SearchSort { relevance, popularity, durationAsc, durationDesc, recent, titleAsc }
   ```
2. **Funciones puras de orden** en `lib/core/utils/search_sort.dart`:
   - `sortSongs(List<SongModel>, SearchSort, {Map<String, int> localPlays})`.
   - `sortAlbums(List<AlbumModel>, SearchSort)`.
   - `sortArtists(List<ArtistModel>, SearchSort)`.
   - `sortPublicPlaylists(List<PublicPlaylistModel>, SearchSort)`.
3. **Comportamiento por tipo**:
   - **Relevancia**: mantener el orden de la API. Es el único orden que garantiza la intención de búsqueda.
   - **Popularidad**:
     - Local: `plays` de `ListeningStatsService`.
     - Charts: `rank` (menor es mejor).
     - Catálogo: la API no expone reproducciones; se usa relevancia y se muestra un aviso “YouTube Music no expone reproducciones en la búsqueda”.
   - **Duración**:
     - Canciones: `SongModel.duration`; las que no tienen duración van al final.
     - Álbumes/artistas/playlists: no aplica; opción deshabilitada.
   - **Recientes**:
     - Álbumes: `year` descendente; los sin año al final.
     - Canciones: `year` descendente si existe; si no, se usa el orden de la API. En resultados locales se usa `lastPlayed` del historial/estadísticas.
     - Playlists: no hay fecha fiable; se usa relevancia y se indica.
   - **A-Z**:
     - Canciones por título; álbumes por título; artistas por nombre; playlists por título.
     - Usar `normalize` para comparar sin tildes/mayúsculas y `compareTo` con locale español.
4. **UI**
   - `SearchSortSelector` en el sheet o como `PopupMenuButton`.
   - El orden se guarda en `SearchFilters.sort`.
   - Se aplica en el provider derivado, no en la API.
5. **Persistencia**
   - El orden es parte de los filtros de sesión; no se persiste por defecto.
   - En la biblioteca, el orden existente (`sortOrderProvider`) se mantiene y no se toca.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/core/utils/search_sort.dart` (nuevo) | Funciones de orden. |
| `lib/data/models/search_models.dart` | `SearchSort`. |
| `lib/providers/search_providers.dart` | Orden aplicado en los providers derivados. |
| `lib/presentation/widgets/search_filter_sheet.dart` | Selector de orden. |

#### Caché y rendimiento

- Ordenar es una operación en memoria; no hay red.
- Para listas grandes, ordenar una vez por cambio de orden/filtros y memoizar el resultado.
- No se reordena en cada `build`; se hace en un `Provider` derivado.

#### Limitaciones y decisiones

- “Popularidad” en el catálogo no puede ser real; se evita fingir. Se usa relevancia y se informa.
- “Recientes” en canciones sin año no puede ser exacto; se usa el historial local o el orden de la API.
- La duración de playlists públicas puede faltar; no se ordena por duración en playlists.

#### Criterios de aceptación

- [ ] El selector de orden está disponible y se aplica sin red.
- [ ] Duración y A-Z funcionan en canciones.
- [ ] Recientes ordena álbumes por año y canciones por año cuando existe.
- [ ] Las opciones no aplicables se ven deshabilitadas con explicación.
- [ ] Cambiar de orden no pierde la selección múltiple ni la consulta.

---

### 5.6 Autocompletado y sugerencias en vivo

**Prioridad:** Media · **Fase:** 1A

#### Objetivo

Ayudar a escribir consultas y descubrir resultados antes de enviar, con sugerencias rápidas y relevantes.

#### Experiencia de usuario

- Al enfocar la barra y escribir ≥ 2 caracteres, aparece un panel debajo con hasta 8 sugerencias.
- Las sugerencias del historial local aparecen primero, marcadas con un icono de historial.
- Las sugerencias remotas muestran el texto con las coincidencias resaltadas (usando los `runs` de la API).
- Al tocar una sugerencia:
  - Se rellena la barra.
  - Se guarda en el historial.
  - Se ejecuta la búsqueda.
  - Se cierra el teclado y el panel.
- Si no hay sugerencias, el panel no se muestra; no se bloquea la búsqueda normal.
- El panel se cierra al tocar fuera, al enviar o al limpiar.
- La navegación con teclado (flechas/enter) es opcional; en móvil no es imprescindible.

#### Implementación

1. **Modelo `SearchSuggestion`**:
   ```dart
   class SearchSuggestion {
     final String text;
     final List<SuggestionRun> runs; // texto + negrita
     final bool fromHistory;
     final String? feedbackToken;
   }
   ```
2. **`YtService.getSearchSuggestions(query, {detailedRuns = true})`**
   - Llama a `api.getSearchSuggestions(query, detailedRuns: true)`.
   - Normaliza la respuesta (List de Map) a `SearchSuggestion`.
   - Cachea por consulta.
3. **Provider `searchSuggestionsProvider`**
   - `FutureProvider.autoDispose.family<List<SearchSuggestion>, String>`.
   - El widget debouncea 200 ms y actualiza `suggestionsQueryProvider`.
   - Se combina con el historial local: se anteponen las coincidencias del historial que no estén ya en la respuesta remota.
   - Límite: 8.
   - Si la consulta tiene menos de 2 caracteres, devuelve solo historial local (o vacío).
4. **UI**
   - `SearchBarWidget` acepta un `FocusNode` opcional y un `onFocusChanged`.
   - `SearchSuggestionsPanel` se renderiza en un `Stack`/`Column` debajo de la barra, con `Material` y elevación.
   - Cada fila: icono (historial/búsqueda), texto con `RichText`/`TextSpan` (negrita en los `runs`), y acción de rellenar.
   - Si la API falla, se muestran solo las sugerencias locales; no se muestra error.
5. **Historial**
   - `SearchHistoryNotifier` (nuevo) con `add`, `remove`, `clear`, `list`.
   - Persiste en `settings` con la clave `searchHistory` (compatible con lo existente).
   - Deduplica por texto normalizado; máximo 12.
   - Se usa tanto en el panel como en la pantalla de Explorar.
6. **Rendimiento**
   - No se piden sugerencias si la consulta no cambió.
   - Se cancelan/ignoran respuestas obsoletas con `autoDispose` y un `requestId`.
   - No se piden sugerencias si el modo offline está activo (solo historial).

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/models/search_models.dart` | `SearchSuggestion`, `SuggestionRun`. |
| `lib/data/services/yt_service.dart` | `getSearchSuggestions`. |
| `lib/providers/search_providers.dart` | `searchSuggestionsProvider`, `SearchHistoryNotifier`. |
| `lib/presentation/widgets/search_bar_widget.dart` | `FocusNode`, `onFocusChanged`, botón de voz opcional. |
| `lib/presentation/widgets/search_suggestions_panel.dart` (nuevo) | Panel de sugerencias. |
| `lib/presentation/screens/search_screen.dart` | Integración del panel y debounce. |

#### Caché y rendimiento

- Clave: `search:suggestions:<queryNormalizada>`.
- TTL: 15 minutos en memoria / 1 día en disco.
- Máximo 100 entradas de sugerencias.
- No se cachean sugerencias de menos de 2 caracteres.
- El historial local se lee de memoria/Hive; no hay red.

#### Limitaciones y decisiones

- Las sugerencias de YouTube Music pueden incluir términos que no tengan resultados; se manejan con el estado vacío.
- No se implementa eliminación de sugerencias del historial de YouTube Music (`removeSearchSuggestions`) en esta fase; el borrado individual es del historial local (ver 5.12).
- El resaltado usa los `runs` de la API cuando están disponibles; si no, se resalta la coincidencia por texto.

#### Criterios de aceptación

- [ ] Al escribir 2+ caracteres aparece el panel con sugerencias en menos de 300 ms (con red normal).
- [ ] Las sugerencias del historial aparecen primero.
- [ ] Tocar una sugerencia ejecuta la búsqueda y guarda el historial.
- [ ] Si la API falla, la búsqueda normal sigue funcionando.
- [ ] En offline solo se muestran sugerencias del historial.
- [ ] No se lanzan peticiones duplicadas al escribir rápido.

---

### 5.7 Tendencias y géneros para explorar

**Prioridad:** Media · **Fase:** 2

#### Objetivo

Convertir el estado vacío de la búsqueda en un lugar de descubrimiento, con tendencias y géneros que permitan empezar a escuchar sin escribir.

#### Experiencia de usuario

- Cuando la consulta está vacía, la pantalla muestra **Explorar**:
  - **Búsquedas recientes** (con borrado individual).
  - **Tendencias**: canciones/playlists populares del momento.
  - **Géneros**: chips o tarjetas (Pop, Rock, Hip-Hop, R&B, Latina, Electrónica, Chill, Enfoque, Gym, etc.).
  - **Accesos rápidos**: Descargas, Favoritos, Historial, Playlists.
- Al tocar una tendencia:
  - Si es una canción, se reproduce y se añade a la cola.
  - Si es una playlist, se abre la pantalla de playlist pública.
- Al tocar un género:
  - Se abre `GenreScreen` con las playlists de ese género.
  - Si el género tiene una sola playlist, se puede abrir directamente.
- “Ver todo” en tendencias y géneros abre una pantalla de lista completa.

#### Implementación

1. **`ExploreService`** (nuevo)
   - `getExploreBundle()`: una llamada a `api.getExplore()`.
   - Devuelve un `ExploreBundle` tipado:
     ```dart
     class ExploreBundle {
       final List<AlbumModel> newReleases;
       final List<SongModel> trending;
       final List<GenreCategory> genres;
       final String? topSongsPlaylistId;
     }
     ```
   - `getMoodCategories()`: llamada a `api.getMoodCategories()` para la lista completa de géneros.
   - `getMoodPlaylists(params)`: llamada a `api.getMoodPlaylists(params)`.
   - `getCharts(country)`: llamada a `api.getCharts(...)` (se usa en Inicio).
2. **Providers**
   - `exploreBundleProvider`: `FutureProvider<ExploreBundle>` (no `autoDispose`, para compartir entre Buscador e Inicio).
   - `trendingProvider`: deriva `exploreBundle.trending`.
   - `genresProvider`: deriva `exploreBundle.genres` o `getMoodCategories`.
   - `genrePlaylistsProvider(params)`: `FutureProvider.autoDispose.family<List<PublicPlaylistModel>, String>`.
3. **UI**
   - `SearchDiscovery` (nuevo widget) con secciones.
   - `TrendingCarousel` con tarjetas compactas.
   - `GenreChips` con `Wrap`.
   - `GenreScreen`:
     - Ruta `/explore/genre?title=...&params=...`.
     - Grid de playlists públicas.
     - `Hero` y estado vacío.
4. **Caché**
   - Explore bundle: 12 h memoria / 24 h disco.
   - Mood categories: 7 días.
   - Mood playlists: 24 h.
   - Tendencias: incluidas en el bundle.
5. **Reutilización**
   - El mismo `exploreBundleProvider` alimenta Novedades, Tendencias y Géneros en Inicio. Esto evita llamadas duplicadas.
   - La misma `GenreScreen` se usa desde Buscador, Inicio y Mezclas de ánimo.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/services/explore_service.dart` (nuevo) | Explore, moods, genres, charts. |
| `lib/data/models/explore_models.dart` (nuevo) | `ExploreBundle`, `GenreCategory`, `ChartPlaylist`, `ChartArtist`, `ChartsSnapshot`. |
| `lib/providers/explore_providers.dart` (nuevo) | `exploreBundleProvider`, `trendingProvider`, `genresProvider`, `genrePlaylistsProvider`, `chartsProvider`. |
| `lib/presentation/widgets/search_discovery.dart` (nuevo) | Explorar. |
| `lib/presentation/screens/genre_screen.dart` (nuevo) | Playlists por género. |
| `lib/router/app_router.dart` | Ruta de género. |

#### Limitaciones y decisiones

- La respuesta de Explore puede variar por país/cuenta y no siempre incluir top songs (por ejemplo, sin Premium). Se manejan listas vacías y se muestran las secciones disponibles.
- Los géneros son los que devuelve YouTube Music; no se inventa una taxonomía propia.
- Los `params` de Moods & Genres son opacos y largos; se pasan por query string codificada y se validan.
- Si Explore falla, el estado vacío muestra el historial y accesos locales; no se bloquea la búsqueda.

#### Criterios de aceptación

- [ ] Con la consulta vacía se ven tendencias y géneros (si hay red/caché).
- [ ] Tocar una tendencia reproduce o abre la playlist correcta.
- [ ] Tocar un género abre sus playlists.
- [ ] “Ver todo” muestra la lista completa.
- [ ] Si Explore falla, la pantalla sigue mostrando historial y accesos locales.
- [ ] Los datos se comparten con Inicio sin duplicar llamadas.

---

### 5.8 Buscar dentro de playlists, cola y descargas

**Prioridad:** Media · **Fase:** 2

#### Objetivo

Unificar la búsqueda local dentro de las colecciones que el usuario ya tiene abiertas, sin alterar el orden ni la reproducción.

#### Experiencia de usuario

- **Playlists**: ya existe un campo de búsqueda en el detalle. Se mejora para que:
  - Ignore tildes y mayúsculas.
  - Busque por título, artista y álbum.
  - Muestre “X de Y canciones”.
  - Tenga botón de limpiar.
  - La selección múltiple siga funcionando sobre la lista filtrada.
- **Descargas**: ya existe búsqueda. Se reutiliza el mismo motor y se añade:
  - Búsqueda por artista/álbum además de título.
  - Botón de limpiar visible.
  - Compatibilidad con el orden y la selección existentes.
- **Cola**: nuevo campo de búsqueda en el bottom sheet de la cola:
  - Filtra por título/artista.
  - Mientras hay búsqueda, la lista no es reordenable (para evitar inconsistencias); se muestra una lista plana.
  - “Reproducir ahora” y “Quitar de la cola” usan el índice original de la canción, no el índice filtrado.
  - Al limpiar, se recupera la cola completa y el modo reordenable.
  - Muestra “X de Y canciones”.

#### Implementación

1. **`LocalSearchField`** (widget reutilizable)
   - `controller`, `hintText`, `onChanged`, `onClear`.
   - Icono de búsqueda y botón de limpiar.
   - Estilo consistente con la barra principal.
2. **`LocalSearchService.searchInSongs(Iterable<SongModel>, String query)`**
   - Devuelve una lista filtrada y ordenada por relevancia local.
   - Reutiliza `normalize`/`scoreSong`.
3. **Playlist detail**
   - Reemplazar el filtro actual por `LocalSearchService.searchInSongs`.
   - Calcular `filteredSongs` una vez por cambio de query (memoizar).
   - Mantener `_selected` por ID; al filtrar, las selecciones ocultas se conservan.
   - Mostrar contador y limpiar.
4. **Downloads**
   - Reutilizar `downloadsSearchQueryProvider` o migrarlo a un `StateProvider<String>` común.
   - Filtrar con el mismo servicio.
   - Mantener el orden (`sortOrderProvider('downloads')`) y la selección.
5. **Queue**
   - Convertir el contenido del sheet en un `ConsumerStatefulWidget` o usar un `StatefulBuilder` con un `TextEditingController`.
   - `filteredQueue = songs.asMap().entries.where(...)` para conservar el índice original.
   - Si `query.isEmpty`: `ReorderableListView` como hoy.
   - Si `query.isNotEmpty`: `ListView.builder` con `QueueSearchTile(index, song)`.
   - Acciones:
     - `handler.skipToQueueItem(originalIndex)`.
     - `handler.removeSongFromQueue(originalIndex)`.
   - No permitir reordenar mientras se filtra; mostrar una nota “Limpia la búsqueda para reordenar”.
6. **Rendimiento**
   - Las colas y playlists suelen tener < 500 elementos; el filtrado es barato.
   - Debounce de 150 ms si la lista es grande (> 500).
   - No reconstruir toda la lista con cada tecla: usar un `ValueListenableBuilder`/`setState` local del campo y memoizar el resultado.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/presentation/widgets/local_search_field.dart` (nuevo) | Campo reutilizable. |
| `lib/data/services/local_search_service.dart` | `searchInSongs`. |
| `lib/presentation/screens/playlist_detail_screen.dart` | Mejorar filtro existente. |
| `lib/presentation/screens/downloads_screen.dart` | Reutilizar motor y mejorar filtro. |
| `lib/presentation/screens/now_playing_screen.dart` | Búsqueda en la cola. |

#### Limitaciones y decisiones

- No se busca en la cola futura que aún no se ha resuelto (la cola lógica ya está en `queueSongsProvider`; se usa esa).
- La búsqueda en playlists públicas se hace sobre las canciones ya cargadas; si la playlist tiene más de las cargadas, se puede ampliar el límite al abrir (100 por defecto).
- No se reordena una lista filtrada; es una decisión de seguridad para no corromper la cola.

#### Criterios de aceptación

- [ ] La búsqueda en playlist/descargas ignora tildes y mayúsculas.
- [ ] La búsqueda en cola no altera el orden real.
- [ ] “Reproducir ahora” y “Quitar” en la cola filtrada afectan a la canción correcta.
- [ ] Al limpiar la búsqueda se recupera la lista completa y el reordenamiento.
- [ ] Las selecciones múltiples se conservan al filtrar.

---

### 5.9 Buscar por letra

**Prioridad:** Media · **Fase:** 2

#### Objetivo

Permitir encontrar una canción recordando un fragmento de su letra, sin hacer una petición de letras por cada resultado de búsqueda.

#### Experiencia de usuario

- En el selector de ámbito de la búsqueda se añade **Letras** (junto a Catálogo y Mi biblioteca).
- Al elegir “Letras”, el placeholder cambia a “Buscar en tus letras guardadas”.
- Los resultados muestran:
  - Portada, título y artista.
  - Un fragmento de la línea donde coincide la búsqueda, con el término resaltado.
  - Acción para reproducir.
- Estado vacío:
  - “Todavía no hay letras indexadas” + botón **Indexar letras de mis descargas**.
  - “Solo se buscan letras ya guardadas o descargadas”.
- Indexación:
  - Se ejecuta en segundo plano, con progreso (“Indexando 12 de 40…”).
  - No bloquea la búsqueda.
  - Se puede cancelar.
- La búsqueda es local e instantánea una vez indexada.

#### Implementación

1. **`LyricsIndexService`** (nuevo)
   - Fuente 1: claves `lyrics:*` de `AppCache` (las letras ya visitadas).
   - Fuente 2: letras de canciones descargadas que se indexan bajo demanda.
   - Estructura:
     ```dart
     class LyricsIndexEntry {
       final SongModel song;
       final String normalizedLyrics;
       final List<String> lines;
     }
     ```
   - Índice invertido opcional: `Map<String, Set<String>> tokenToSongIds` para búsquedas rápidas.
   - `search(query, {limit = 20})`:
     - Normaliza la consulta.
     - Busca canciones que contengan todos los tokens (AND); si no hay, prueba OR y ordena por número de coincidencias.
     - Devuelve `LyricsHit(song, line, snippet, score)`.
   - `indexDownloadedLyrics({onProgress, cancelToken})`:
     - Obtiene las canciones descargadas.
     - Para cada una sin letra cacheada, llama a `YtService.getLyricsForSong`.
     - Concurrencia máxima: 3.
     - Guarda en `AppCache` (el servicio ya lo hace).
     - Actualiza el índice en memoria.
2. **Parsing de letras**
   - `getLyricsForSong` devuelve un `Map<String, dynamic>`; el texto puede estar en `lyrics`, `text` o en una lista de líneas.
   - Extraer texto plano, normalizar y conservar las líneas originales para el snippet.
3. **Providers**
   - `lyricsIndexProvider`: `FutureProvider<LyricsIndexService>` o `Provider` con inicialización perezosa.
   - `lyricsSearchProvider`: `FutureProvider.autoDispose.family<List<LyricsHit>, String>`.
   - `lyricsIndexProgressProvider`: `StateNotifier<LyricsIndexProgress>` para la UI de indexación.
4. **UI**
   - `SearchScopeSelector` con `catalog`, `library`, `lyrics`.
   - `LyricsSearchResults` (nuevo widget).
   - `LyricsIndexButton`/`LyricsIndexSheet`.
5. **Integración con la búsqueda normal**
   - No se mezclan letras con canciones en “Todo” para no confundir.
   - “Letras” es un ámbito explícito.
   - Si el usuario busca una frase entre comillas en “Todo”, se puede ofrecer un botón “Buscar esta frase en letras” (opcional, fase 5).

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/services/lyrics_index_service.dart` (nuevo) | Índice, búsqueda, indexación. |
| `lib/providers/search_providers.dart` | `lyricsIndexProvider`, `lyricsSearchProvider`, progreso. |
| `lib/presentation/widgets/lyrics_search_results.dart` (nuevo) | Resultados con snippet. |
| `lib/presentation/screens/search_screen.dart` | Ámbito “Letras”. |

#### Caché y rendimiento

- No se hace ninguna llamada de red durante la búsqueda por letra.
- Índice en memoria; se reconstruye al abrir la app o al indexar nuevas letras.
- La indexación es explícita y con concurrencia limitada; no se ejecuta automáticamente para toda la biblioteca.
- Las letras ya cacheadas por `AppCache` se reutilizan; no se vuelven a pedir.
- TTL de letras: el existente en `YtService`/`AppCache` (7 días por defecto). No se cambia.

#### Limitaciones y decisiones

- **No hay búsqueda global de letras** en YouTube Music. El plan implementa búsqueda en la biblioteca local/cacheada, que es lo viable sin un backend/terceros.
- No se indexan automáticamente cientos de canciones al instante; el usuario decide indexar sus descargas.
- Las letras sincronizadas y la vista de letras existentes no se modifican; solo se añade el índice de búsqueda.
- Si una letra no está disponible, no se indexa y no se muestra error.

#### Criterios de aceptación

- [ ] Se puede buscar una frase y obtener canciones cuya letra cacheada la contiene.
- [ ] El fragmento coincidente se muestra resaltado.
- [ ] La búsqueda por letra no genera llamadas de red.
- [ ] “Indexar letras de mis descargas” muestra progreso y respeta la cancelación.
- [ ] Si no hay letras indexadas, se explica cómo indexarlas.
- [ ] La vista de letras existente sigue funcionando igual.

---

### 5.10 Paginación también para álbumes y artistas (y playlists)

**Prioridad:** Media · **Fase:** 1A

#### Objetivo

Que álbumes, artistas y playlists tengan “Cargar más” como las canciones, con una estrategia eficiente y sin duplicados.

#### Experiencia de usuario

- Al final de cada lista aparece **Cargar más** si hay más resultados.
- Mientras carga: spinner y botón deshabilitado.
- Si no hay más: no se muestra el botón (o un texto discreto “No hay más resultados”).
- Si falla: mensaje “No se pudieron cargar más resultados” + “Reintentar”.
- La lista mantiene el scroll y los elementos ya cargados.
- La paginación funciona con filtros y orden activos.

#### Implementación

1. **Estado genérico `SearchPageState<T>`**:
   ```dart
   class SearchPageState<T> {
     final List<T> items;
     final int page;
     final bool loading;
     final bool loadingMore;
     final Object? error;
     final bool hasMore;
     final int requestId;
   }
   ```
2. **`SearchPageNotifier<T>`** (genérico)
   - Constructor con:
     - `Future<List<T>> Function(int limit) loadPage`.
     - `String Function(T) idOf`.
     - `int pageSize = 20`.
     - `int maxLimit = 100`.
   - `loadInitial()`: pide `pageSize`.
   - `loadMore()`:
     - Si ya está cargando o no hay más, no hace nada.
     - Calcula `nextLimit = min((page + 2) * pageSize, maxLimit)`.
     - Pide y fusiona por ID.
     - `hasMore = newItems.isNotEmpty && fetched.length >= nextLimit`.
     - Si `fetched.length < nextLimit`, `hasMore = false`.
     - Si `newItems.isEmpty`, `hasMore = false`.
   - `retry()`.
   - `requestId` para descartar respuestas viejas.
3. **Providers**
   - `searchSongsProvider` (refactor del actual) → `SearchPageNotifier<SongModel>`.
   - `searchAlbumsProvider` → `SearchPageNotifier<AlbumModel>`.
   - `searchArtistsProvider` → `SearchPageNotifier<ArtistModel>`.
   - `searchPlaylistsProvider` → `SearchPageNotifier<PublicPlaylistModel>`.
   - `autoDispose.family` por consulta; `keepAlive` temporal de 2 minutos para no perder la página al cambiar de pestaña.
4. **Servicios**
   - `searchAlbums(query, {limit})`, `searchArtists(query, {limit})`, `searchPlaylists(query, {limit})`.
   - Cambiar el límite inicial de álbumes/artistas de 40 a 20 para que “Cargar más” tenga sentido; el límite máximo es 100.
5. **UI**
   - `SearchLoadMore` reutilizable.
   - Para álbumes/artistas/playlists, usar `ListView.builder` con un ítem extra para el botón.
   - Evitar `ListView` anidados; si se usa un grid, `CustomScrollView` + `SliverGrid` + `SliverToBoxAdapter` para el botón.
6. **Filtros**
   - La paginación opera sobre resultados crudos; el provider derivado filtra/ordena.
   - Si la página visible queda vacía por filtros y `hasMore` es true, se puede auto-cargar una página extra (máximo 2) para evitar un falso “sin resultados”.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/models/search_models.dart` | `SearchPageState<T>`. |
| `lib/providers/search_providers.dart` | `SearchPageNotifier<T>`, providers de álbumes/artistas/playlists. |
| `lib/data/services/yt_service.dart` | Límites parametrizables en álbumes/artistas/playlists. |
| `lib/presentation/widgets/search_load_more.dart` (nuevo o movido) | Botón reutilizable. |
| `lib/presentation/screens/search_screen.dart` | Integración en todas las pestañas. |

#### Caché y rendimiento

- Claves con `limit`: `search:songs:<q>:<limit>`, etc.
- La caché evita repetir la misma página; cada aumento de límite es una petición nueva (limitación del paquete).
- Límite máximo 100 para evitar respuestas enormes.
- Deduplicación por ID para que un cambio de orden de la API no duplique filas.
- No se pagina “Todo”; allí solo se muestran los mejores resultados y “Ver todo”.

#### Limitaciones y decisiones

- El paquete no expone un token de continuación público; la estrategia es `limit` creciente + fusión + caché. Es la opción más segura sin fork.
- Si en el futuro se necesita paginación incremental pura (por ejemplo, listas de miles de elementos), se puede evaluar un fork de `ytmusicapi_dart` que exponga continuaciones. No es necesario para esta app.
- `hasMore` puede requerir una petición extra para confirmar el final; se acepta a cambio de simplicidad.

#### Criterios de aceptación

- [ ] Canciones, álbumes, artistas y playlists muestran “Cargar más” cuando hay más resultados.
- [ ] No hay IDs duplicados tras cargar más.
- [ ] El botón se deshabilita mientras carga y desaparece al llegar al final.
- [ ] Un error en “Cargar más” no borra lo ya cargado.
- [ ] Los filtros y el orden se aplican a los nuevos elementos.
- [ ] Cambiar de pestaña y volver conserva la página cargada (o la recupera de caché).

---

### 5.11 Acciones masivas sobre resultados

**Prioridad:** Media · **Fase:** 2

#### Objetivo

Permitir seleccionar varios resultados y ejecutar acciones en lote: reproducir, añadir a la cola, añadir a playlist, descargar, favoritear o eliminar descargas.

#### Experiencia de usuario

- Mantener pulsada una canción entra en **modo selección**.
- Un toque selecciona/deselecciona.
- La cabecera se transforma en barra contextual:
  - “X seleccionadas”.
  - Acciones: reproducir, cola, playlist, descargar, favorito, eliminar descarga, cerrar.
- “Seleccionar todo lo visible” y “Limpiar selección”.
- Al cambiar de página o cargar más, las selecciones se conservan por ID.
- Las acciones muestran confirmación cuando son destructivas o masivas (> 10 descargas).
- Resultado:
  - Reproducir: reproduce en el orden de la lista.
  - Cola: añade al final de la cola.
  - Playlist: abre un selector de playlists locales + “Nueva playlist”.
  - Descargar: descarga las que no estén descargadas; muestra progreso y resumen.
  - Favorito: añade/quita según el estado; muestra resumen.
  - Eliminar descarga: pide confirmación y elimina los archivos.

#### Implementación

1. **Estado de selección**
   - `SearchSelectionNotifier` (StateNotifier) con:
     ```dart
     class SearchSelectionState {
       final bool selecting;
       final Set<String> songIds;
     }
     ```
   - Se reinicia al cambiar de consulta o de pestaña (o se conserva por pestaña si se decide; recomendado reiniciar para evitar acciones inesperadas).
2. **`SongTile`**
   - Añadir parámetros opcionales:
     - `selectionMode`
     - `selected`
     - `onSelectionChanged`
     - `onLongPress`
   - Sin cambios en el comportamiento por defecto.
   - En modo selección: checkbox a la izquierda, sin menú contextual, tap para alternar.
3. **Barra contextual**
   - `SearchSelectionBar` con `SafeArea`, estilo glass consistente.
   - Botones con tooltips y labels accesibles.
4. **Acciones**
   - Reproducir: `AudioHandler.playSongs(selectedSongs)`; navegar a `/now-playing`; pedir permiso de notificación (helper existente).
   - Cola: `AudioHandler.addSongsToQueue(selectedSongs)`.
   - Playlist: extraer/reutilizar `PlaylistPickerSheet`; `LocalRepository.createPlaylist`/`updatePlaylist`.
   - Descargar: `DownloadService.downloadMany`; respeta `wifiOnlyDownloadsProvider`; muestra `downloadProgressProvider`.
   - Favorito: `LocalRepository.toggleFavorite` por canción; o un método batch `setFavorite`.
   - Eliminar descarga: `DownloadService.delete` por ID; confirmación.
5. **Selección en otras pestañas**
   - Fase 2: canciones.
   - Fase 5 (opcional): álbumes/playlists públicas con acciones “Descargar todo”, “Añadir a la cola”, “Guardar en biblioteca”.
   - Artistas: “Seguir/Dejar de seguir” (fase 5).
6. **Rendimiento**
   - `Set<String>` para selección; cada fila consulta `selected.contains(id)`.
   - Evitar reconstruir toda la lista al seleccionar: usar `select` por fila o `ValueListenableBuilder` del set.
   - Descargas en lote con concurrencia controlada por el servicio existente.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/providers/search_providers.dart` | `SearchSelectionNotifier`. |
| `lib/presentation/widgets/song_tile.dart` | Soporte de selección. |
| `lib/presentation/widgets/search_selection_bar.dart` (nuevo) | Barra de acciones. |
| `lib/presentation/widgets/playlist_picker_sheet.dart` (nuevo o extraído) | Selector de playlist. |
| `lib/presentation/screens/search_screen.dart` | Integración de selección. |
| `lib/data/services/download_service.dart` | Reutilizar `downloadMany` (sin cambios funcionales). |
| `lib/data/services/audio_handler.dart` | Reutilizar `addSongsToQueue`/`playSongs`. |

#### Caché y rendimiento

- No hay red adicional para seleccionar.
- Las acciones usan servicios existentes y cachean portadas/imágenes.
- La descarga masiva muestra progreso sin bloquear la UI.
- No se seleccionan canciones que no estén cargadas; el usuario puede cargar más y seleccionar.

#### Limitaciones y decisiones

- No se implementa selección de resultados de artistas para “reproducir todos sus álbumes” en esta fase; se prioriza canciones.
- Las playlists públicas se pueden guardar/descargar desde su pantalla de detalle, que es el lugar natural.
- Las acciones masivas no cambian el orden de la cola existente; solo añaden al final.

#### Criterios de aceptación

- [ ] Long-press entra en selección y un toque alterna.
- [ ] La barra muestra el número correcto y se puede cerrar.
- [ ] Reproducir, cola, playlist y descargar funcionan con varios elementos.
- [ ] Las selecciones se conservan al cargar más páginas.
- [ ] Una descarga masiva muestra progreso y resumen.
- [ ] Las acciones destructivas piden confirmación.
- [ ] `SongTile` sigue funcionando igual fuera del modo selección.

---

### 5.12 Borrar búsquedas individuales

**Prioridad:** Baja · **Fase:** 1A

#### Objetivo

Poder eliminar una búsqueda concreta del historial, no solo todas.

#### Experiencia de usuario

- Cada fila de “Búsquedas recientes” tiene un icono **X** para eliminarla.
- Al borrar:
  - La fila desaparece con una animación suave.
  - Se muestra un SnackBar “Búsqueda eliminada” con opción **Deshacer**.
- “Borrar todo” sigue existiendo, con diálogo de confirmación.
- El cambio persiste tras reiniciar la app.
- No se borra nada del historial de YouTube Music; solo el historial local de la app.

#### Implementación

1. **`SearchHistoryNotifier`**
   - Estado: `List<String>`.
   - `add(String)`, `remove(String)`, `clear()`, `undoRemove()`.
   - Persiste en `settings` (`searchHistory`).
   - Deduplica por texto normalizado.
   - Máximo 12.
2. **UI**
   - `ListTile` con `trailing: IconButton(Icons.close_rounded)`.
   - `Dismissible` opcional (swipe) con confirmación/undo; no es obligatorio.
   - SnackBar con `SnackBarAction(label: 'Deshacer')`.
3. **Migración**
   - Compatible con el formato actual (`List<String>` en settings). No requiere migración.
4. **“Borrar todo”**
   - Diálogo: “¿Borrar todas las búsquedas recientes?”.
   - Confirmar → `clear()` + persistir.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/providers/search_providers.dart` | `SearchHistoryNotifier`. |
| `lib/presentation/screens/search_screen.dart` | Botón por fila, undo y confirmación. |

#### Caché y rendimiento

- Operación local, sin red.
- Persistencia inmediata (Hive settings).
- No se cachean imágenes ni datos adicionales.

#### Limitaciones y decisiones

- No se elimina la sugerencia del historial de YouTube Music; eso requeriría `removeSearchSuggestions` y tokens de feedback. Se puede añadir en una fase futura, pero no es necesario para el requisito.
- El historial es local y no se sincroniza entre dispositivos.

#### Criterios de aceptación

- [ ] Se puede borrar una búsqueda individual.
- [ ] El borrado persiste tras cerrar y abrir la app.
- [ ] “Deshacer” restaura la búsqueda en la misma posición.
- [ ] “Borrar todo” pide confirmación.
- [ ] No se afecta el historial de reproducción ni el de YouTube Music.

---

### 5.13 Búsqueda por voz

**Prioridad:** Baja · **Fase:** 5

#### Objetivo

Permitir iniciar una búsqueda hablando, con una integración nativa y un fallback claro cuando no esté disponible.

#### Experiencia de usuario

- Icono de micrófono dentro de la barra de búsqueda.
- Al pulsarlo:
  - Se solicita permiso de micrófono si es la primera vez.
  - Se muestra un estado “Escuchando…” con animación.
  - El texto reconocido se escribe en la barra en tiempo real (resultados parciales).
  - Al terminar, se ejecuta la búsqueda.
- Si se deniega el permiso: SnackBar “Activa el permiso de micrófono en Ajustes para buscar por voz”.
- Si el dispositivo no soporta reconocimiento: el botón se oculta o se muestra deshabilitado con tooltip.
- Si no hay conexión y el reconocimiento requiere red: se informa y se mantiene la búsqueda escrita.
- El audio no se guarda; solo se usa el texto reconocido.

#### Implementación

1. **Dependencia**: `speech_to_text` (última versión estable compatible con el SDK actual). Añadir con `flutter pub add speech_to_text`.
2. **Permisos Android**:
   - `<uses-permission android:name="android.permission.RECORD_AUDIO" />` en `android/app/src/main/AndroidManifest.xml`.
   - Seguir la documentación del plugin para `<queries>` de `RecognitionService` si es necesario en Android 11+.
   - `permission_handler` ya está en el proyecto para solicitar el permiso en runtime.
3. **`VoiceSearchController`** (nuevo)
   - Encapsula `SpeechToText`.
   - `initialize()`, `start(localeId)`, `stop()`, `cancel()`.
   - `onResult`, `onError`, `onDone`.
   - Estado: `idle | listening | processing | unavailable | denied`.
4. **UI**
   - `SearchBarWidget` acepta `onVoiceSearch` y `isListening`.
   - Botón de micrófono con `AnimatedContainer`/pulso cuando escucha.
   - Tooltip “Buscar por voz”.
5. **Idioma**
   - Usar el locale del dispositivo (`Platform.localeName` o `Intl.getCurrentLocale()`), con fallback `es_ES`.
   - Si el locale no está disponible, se usa el predeterminado del motor.
6. **Integración**
   - Al recibir texto parcial: actualizar el controlador y la query local (sin disparar la búsqueda remota en cada sílaba; debounce).
   - Al recibir resultado final: ejecutar `_submitSearch`.
   - Detener el reconocimiento al enviar, al limpiar o al salir de la pantalla.
7. **Permisos**
   - `Permission.microphone.request()`; si `denied`/`permanentlyDenied`, mostrar SnackBar con acción “Abrir Ajustes”.
   - No pedir el permiso al abrir la app; solo al pulsar el micrófono.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `pubspec.yaml` | Dependencia `speech_to_text`. |
| `android/app/src/main/AndroidManifest.xml` | Permiso `RECORD_AUDIO` (y queries si aplica). |
| `lib/core/services/voice_search_controller.dart` (nuevo) | Lógica de voz. |
| `lib/presentation/widgets/search_bar_widget.dart` | Botón de micrófono. |
| `lib/presentation/screens/search_screen.dart` | Integración y ciclo de vida. |

#### Caché y rendimiento

- No hay caché de audio.
- Se detiene el micrófono al salir de la pantalla para no consumir batería.
- No se hacen búsquedas por cada resultado parcial; solo al final o con debounce amplio.

#### Limitaciones y decisiones

- Solo Android (el proyecto no tiene carpeta iOS).
- El reconocimiento depende del dispositivo y de los servicios de Google; puede requerir red.
- No se implementa “siempre escuchando”; es una acción explícita.
- La voz es una mejora de baja prioridad; si el plugin da problemas en algún dispositivo, el botón se oculta y la búsqueda escrita sigue funcionando.

#### Criterios de aceptación

- [ ] El botón de micrófono aparece cuando el reconocimiento está disponible.
- [ ] Al conceder permiso, el texto se escribe y se busca.
- [ ] Al denegar permiso, se muestra un mensaje claro y la app no se bloquea.
- [ ] El micrófono se detiene al salir de la pantalla.
- [ ] Sin soporte de voz, la búsqueda normal funciona igual.

---

### 5.14 Corrección de erratas (“quizás quisiste decir”)

**Prioridad:** Baja · **Fase:** 2

#### Objetivo

Ayudar cuando el usuario escribe mal una palabra, ofreciendo una sugerencia sin impedir la búsqueda original.

#### Experiencia de usuario

- Si la búsqueda no devuelve resultados y hay una sugerencia cercana, se muestra:
  - “Quizás quisiste decir: **<sugerencia>**”.
  - Botón para buscar la sugerencia.
  - Botón “Buscar de todos modos” para usar la consulta original sin autocorrección.
- Si hay resultados, no se muestra una corrección no confirmada para no confundir.
- La sugerencia se puede mostrar también cuando la API autocorrige y devuelve resultados, solo si la diferencia es clara y hay una sugerencia de alta similitud (opcional; se prioriza no molestar).

#### Implementación

1. **Sugerencias**: reutilizar `searchSuggestionsProvider` / `YtService.getSearchSuggestions`.
2. **Similitud**:
   - `TextUtils.levenshtein(a, b)`.
   - `similarity = 1 - distance / max(a.length, b.length)`.
   - Umbral: ≥ 0.72 para consultas cortas, ≥ 0.60 para largas; además, la sugerencia debe ser diferente a la consulta.
   - Se elige la sugerencia con mayor similitud; si hay empate, la primera.
3. **Flujo**:
   - Búsqueda normal (`ignoreSpelling: false`, comportamiento actual de la API).
   - Si `results.isEmpty`, pedir sugerencias (si no se tienen) y calcular.
   - Si hay sugerencia: mostrar banner.
   - “Buscar de todos modos”: llamar a `YtService.searchAll/searchSongs(..., ignoreSpelling: true)` y cachear con una clave que incluya `ignoreSpelling`.
4. **UI**
   - `SpellingSuggestionBanner` (nuevo widget) dentro del estado vacío.
   - No bloquear el campo de búsqueda; el usuario puede seguir editando.
5. **Cache**
   - Incluir `ignoreSpelling` en las claves de búsqueda para no mezclar resultados.
   - Sugerencias con su TTL existente.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/core/utils/text_utils.dart` | `levenshtein`, `similarity`. |
| `lib/data/services/yt_service.dart` | `ignoreSpelling` en búsquedas. |
| `lib/providers/search_providers.dart` | Lógica de sugerencia de ortografía. |
| `lib/presentation/widgets/spelling_suggestion_banner.dart` (nuevo) | Banner. |
| `lib/presentation/screens/search_screen.dart` | Integración en el estado vacío. |

#### Limitaciones y decisiones

- La API autocorrige por defecto; no siempre se puede saber qué término corrigió. Por eso la sugerencia se basa en `getSearchSuggestions` y en la similitud, no en un campo de “corrected query” que el paquete no expone.
- No se aplica corrección automática silenciosa; el usuario decide.
- No se corrige mientras se escribe para no cambiar la consulta sin permiso.

#### Criterios de aceptación

- [ ] Una consulta con error y sin resultados muestra una sugerencia cercana.
- [ ] “Buscar de todos modos” usa la consulta original.
- [ ] La sugerencia no aparece si no hay una alternativa suficientemente parecida.
- [ ] No se muestra una corrección cuando ya hay resultados, salvo que sea muy clara.
- [ ] La búsqueda normal sigue funcionando igual.

---

### 5.15 Estado “sin resultados” con sugerencias

**Prioridad:** Baja · **Fase:** 1A

#### Objetivo

Que el usuario nunca se quede en una pantalla vacía sin saber qué hacer.

#### Experiencia de usuario

El estado vacío debe ser contextual:

| Caso | Contenido |
|---|---|
| **Consulta vacía** | Explorar: historial, tendencias, géneros, accesos a Descargas/Favoritos/Playlists. |
| **Sin resultados remotos** | “No encontramos resultados para ‘X’” + sugerencia de ortografía (si hay) + “Buscar en mi biblioteca” + “Ver descargas” + chips de géneros. |
| **Sin resultados por filtros** | “No hay resultados con estos filtros” + “Quitar filtros” + “X resultados ocultos” + “Ver sin filtros”. |
| **Sin resultados offline** | “No encontramos nada en tu biblioteca” + “Ver descargas” + “Ver favoritos” + “Desactivar modo offline” (si es manual). |
| **Error de red** | “No se pudo completar la búsqueda” + “Reintentar” + “Buscar en mi biblioteca”. |
| **Letras sin indexar** | “Todavía no hay letras indexadas” + “Indexar letras de mis descargas”. |

#### Implementación

1. **`SearchEmptyState`** (widget reutilizable)
   - Props: icono, título, mensaje, acciones (lista de botones), sugerencia de ortografía, chips de géneros.
   - Estilo consistente con `EmptyState` existente, pero con acciones.
2. **Lógica de estado**
   - `SearchScreen` decide el caso según:
     - `query.isEmpty`
     - `effectiveOffline`
     - `filters.activeCount > 0`
     - `results.isEmpty`
     - `error != null`
     - `scope == lyrics`
3. **Acciones**
   - “Buscar en mi biblioteca”: cambia `scope` a library y ejecuta la misma query en local.
   - “Ver descargas”: navega a `/downloads`.
   - “Ver favoritos”: navega a `/library/favorites`.
   - “Desactivar modo offline”: actualiza `offlineModeProvider` y persiste; solo si el modo es manual.
   - “Quitar filtros”: resetea `searchFiltersProvider`.
   - “Explorar géneros”: abre la sección de géneros o navega a `GenreScreen`.
   - “Buscar de todos modos”: solo si hay sugerencia de ortografía.
4. **Sugerencias de búsqueda**
   - Si la consulta vacía no tiene historial, mostrar chips de tendencias/géneros (si están disponibles).
   - Si no hay red ni caché, mostrar un mensaje neutro y accesos locales.
5. **Accesibilidad**
   - El estado vacío debe ser anunciado por lectores de pantalla (`Semantics(liveRegion: true)`).
   - Botones con labels claros.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/presentation/widgets/search_empty_state.dart` (nuevo) | Estado vacío con acciones. |
| `lib/presentation/screens/search_screen.dart` | Selección del caso y acciones. |
| `lib/providers/search_providers.dart` | Helpers para “quitar filtros”, cambiar ámbito, etc. |

#### Caché y rendimiento

- No hay red adicional; las acciones usan datos ya cargados o navegación local.
- Las tendencias/géneros salen de `exploreBundleProvider` (cacheado).
- No se muestran sugerencias si no hay datos; no se fuerza una llamada solo para llenar el estado vacío.

#### Limitaciones y decisiones

- No se implementa un motor de búsqueda semántica ni “búsqueda difusa” global; la sugerencia de ortografía es la ayuda principal.
- En offline no se ofrecen tendencias remotas; solo locales/cacheadas.
- El estado vacío no debe convertirse en una pantalla de carga; si los datos están cargando, se muestra esqueleto.

#### Criterios de aceptación

- [ ] Cada caso de vacío muestra acciones útiles y coherentes.
- [ ] “Buscar en mi biblioteca” funciona desde el vacío remoto.
- [ ] “Quitar filtros” restaura los resultados si existen.
- [ ] En offline se ofrecen descargas/favoritos y no se muestra un error de red.
- [ ] El estado vacío no parpadea mientras carga.

---

## 6. Inicio: plan detallado

### 6.0 Nueva estructura de Inicio

#### Objetivo

Convertir Inicio en un feed modular, rápido y personalizado, donde cada sección se carga de forma independiente y solo cuando hace falta.

#### Estructura propuesta

Orden recomendado (las secciones vacías se ocultan):

1. **Saludo + chips de reproducción reciente** (baja prioridad, local).
2. **Seguir escuchando** (historial local).
3. **Daily Mix** (generado, cacheado por día).
4. **Porque escuchaste…** (basado en el último artista).
5. **Para ti** (recomendaciones existentes, mejoradas).
6. **Novedades** (Explore: nuevos lanzamientos).
7. **Tendencias & Charts** (Explore trending + Charts).
8. **Géneros** (Moods & Genres).
9. **Redescubre** (local: canciones que hace tiempo no suenan).
10. **Top artistas** (local: estadísticas).
11. **Nuevo de artistas que sigues** (local follow + artista).
12. **Álbumes recientes** (historial).
13. **Tus playlists** (local).
14. **Favoritos** (local).

> El orden puede ajustarse según datos disponibles y prioridad de producto. Lo importante es que cada sección sea independiente y que las primeras 4–5 estén por encima del pliegue.

#### Implementación de la pantalla

- Migrar de `ListView` con hijos construidos de golpe a `CustomScrollView` + `SliverList.builder`:
  - `SliverToBoxAdapter` para el saludo/banner/chips.
  - `SliverList.builder` con una lista de `HomeSectionDescriptor` (id, título, subtítulo, builder, `SeeAllSection?`).
  - Cada sección se construye cuando entra en el viewport; los providers se activan en ese momento.
  - `addAutomaticKeepAlives: false` para no retener secciones fuera de pantalla; la caché evita refetch costoso.
  - `addRepaintBoundaries: true`.
- `HomeSectionShell` (nuevo widget):
  - Recibe un `AsyncValue<T>` y un builder.
  - Muestra esqueleto con la altura del contenido.
  - Muestra error con retry solo en esa sección.
  - Si está vacío, retorna `SizedBox.shrink()`.
  - Si está offline y no hay caché, muestra un estado compacto o se oculta.
- `SectionHeader`:
  - Título, subtítulo y “Ver todo” opcional.
  - Se reutiliza en Buscador e Inicio.
- **Caché primero**: cada provider intenta leer `AppCache` y mostrar datos inmediatamente; luego refresca en segundo plano si el TTL expiró.
- **Refresco**:
  - `RefreshIndicator` sobre el `CustomScrollView`.
  - Al refrescar, invalidar solo providers remotos con datos obsoletos; las secciones locales no se tocan.
  - Evitar invalidar todo al cambiar de pestaña (comportamiento actual que genera llamadas innecesarias).
- **Offline**:
  - `effectiveOfflineProvider` decide.
  - Se muestran secciones locales (continuar, daily mix offline, redescubre, top artistas, chips recientes, álbumes recientes, playlists, favoritos).
  - Se muestran secciones remotas cacheadas con badge “Guardado”.
  - Las secciones sin caché se ocultan; banner con “Ver descargas”.
  - No se muestran tarjetas de error de red para fallos esperados en offline.
- **Animaciones**:
  - Mantener `flutter_animate`/reveal para las primeras secciones, animando una sola vez.
  - Respetar `MediaQuery.disableAnimations`.
  - No animar secciones fuera de pantalla.
- **Hero**:
  - Tags consistentes para portadas: `album-<id>`, `artist-<id>`, `playlist-<id>`, `mix-<id>`.
  - Evitar tags duplicados en la misma pantalla.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/presentation/screens/home_screen.dart` | Migrar a slivers y secciones modulares. |
| `lib/presentation/widgets/home_section_shell.dart` (nuevo) | Carga/error/vacío por sección. |
| `lib/presentation/widgets/section_header.dart` (nuevo) | Título + “Ver todo”. |
| `lib/presentation/widgets/home_carousels.dart` (nuevo) | Carruseles de canciones/álbumes/artistas/playlists/mixes. |
| `lib/providers/home_feed_providers.dart` (nuevo) | Providers de las nuevas secciones. |

#### Rendimiento

- Las secciones inferiores no se cargan hasta que el usuario hace scroll.
- `exploreBundleProvider` se comparte entre Novedades, Tendencias y Géneros: una sola llamada.
- `chartsProvider` se carga solo cuando la sección de Charts entra en viewport (o se comparte si ya está cacheado).
- Las secciones locales son instantáneas.
- No se invalida todo al volver a Inicio; se usa TTL + refresco manual.
- Límite de elementos por carrusel: 10–12; “Ver todo” para el resto.

#### Criterios de aceptación

- [ ] Inicio usa slivers y no construye todas las secciones de golpe.
- [ ] Cada sección muestra su propio esqueleto/error sin romper las demás.
- [ ] Las secciones locales aparecen de inmediato.
- [ ] En offline no hay errores de red visibles; se muestran datos locales/cacheados.
- [ ] El scroll es fluido con todas las secciones cargadas.
- [ ] Cambiar de pestaña y volver no dispara todas las llamadas de nuevo.

---

### 6.1 Daily Mix

**Prioridad:** Alta · **Fase:** 4

#### Objetivo

Ofrecer 3 mezclas diarias personalizadas, con canciones conocidas y nuevas, generadas una vez al día y cacheadas.

#### Experiencia de usuario

- Sección “Daily Mix” con 3 tarjetas horizontales:
  - Portada compuesta con hasta 4 carátulas.
  - Título: “Mix 1”, “Mix 2”, “Mix 3” o “Mix de <artista>”.
  - Subtítulo: “Hecho para ti · 25 canciones” o “Porque te gusta <artista>”.
  - Botón de reproducción rápida.
- Al tocar una tarjeta se abre `MixDetailScreen`:
  - Cabecera con portada compuesta, título, subtítulo y cantidad.
  - Reproducir, Aleatorio, Guardar como playlist, Descargar todo.
  - Lista de canciones.
- Las mezclas cambian una vez al día (o al regenerar manualmente).
- En offline se generan con contenido local y se marcan como “Offline”.

#### Implementación

1. **Modelo `DailyMix`**:
   ```dart
   class DailyMix {
     final String id;              // mix-YYYYMMDD-1
     final String title;
     final String subtitle;
     final List<String> coverUrls; // hasta 4
     final List<SongModel> songs;
     final DateTime generatedAt;
     final bool isOffline;
   }
   ```
2. **`DailyMixService`** (nuevo)
   - Entradas:
     - `ListeningStatsService.snapshot()` (top songs, top artists, recientes).
     - `favoritesProvider`, `historyProvider`, `downloadsProvider`.
     - `YtService.getRelatedSongs`, `getArtistRadioSongs`/`getArtistRecommendations`.
   - Semillas:
     - Top 3 artistas.
     - Top 2 canciones.
     - 1–2 favoritos/recientes.
     - Si no hay datos, devolver `[]`.
   - Generación:
     - Para cada una de las 3 mezclas, elegir una semilla distinta.
     - Si la semilla es canción: `getRelatedSongs(song.id)`.
     - Si es artista: `getArtistRadioSongs(artistId, limit: 30)` o `getArtistRecommendations`.
     - `Future.wait` con manejo de errores individual; máximo 3 llamadas.
     - Intercalar resultados, deduplicar, excluir la canción semilla exacta.
     - Equilibrar: máximo 2 canciones por artista y 2 por álbum.
     - Rellenar hasta 25 con favoritos/descargas/top songs (especialmente en offline).
     - Evitar canciones repetidas entre las 3 mezclas usando un `Set<String>` global.
   - Determinismo:
     - Semilla `yyyyMMdd` + índice; `math.Random(seed)`.
     - El mismo día produce las mismas mezclas.
   - Offline:
     - No hace red.
     - Agrupa descargas/favoritos/historial por artista y crea 3 mezclas con shuffle determinista.
     - Si no hay suficientes canciones, completa con lo que haya (mínimo 5 por mezcla); si no, devuelve `[]`.
3. **Cache**
   - Clave: `home:dailyMix:v1:<yyyy-mm-dd>` (una entrada con la lista de 3 mezclas).
   - TTL: hasta el final del día + 1 h.
   - Al leer, si la fecha coincide, se devuelve.
   - `dailyMixesProvider`: `FutureProvider.autoDispose<List<DailyMix>>`; intenta caché primero, luego genera.
   - `mixByIdProvider`: `Provider.family<DailyMix?, String>` que busca en `dailyMixesProvider`; si no existe, la pantalla de detalle puede regenerar.
4. **UI**
   - `MixCard` con `Stack` de hasta 4 `AlbumArt`, rotaciones/offsets suaves, gradiente y botón de play.
   - `MixDetailScreen` con ruta `/mix/:id`.
   - Guardar como playlist: `LocalRepository.createPlaylist(name, songs: mix.songs)`.
   - Descargar: `DownloadService.downloadMany(mix.songs)`.
5. **Reutilización**
   - Extraer de `homeRecommendationsProvider` los helpers de intercalado, deduplicación y equilibrio a `lib/core/utils/mix_utils.dart`.
   - No duplicar lógica entre Daily Mix, Porque escuchaste y Para ti.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/models/home_models.dart` (nuevo) | `DailyMix`, `MoodMix`, `TopArtist`, `FollowedArtist`. |
| `lib/data/services/daily_mix_service.dart` (nuevo) | Generación y cache. |
| `lib/core/utils/mix_utils.dart` (nuevo) | Deduplicación, intercalado, equilibrio, shuffle determinista. |
| `lib/providers/home_feed_providers.dart` | `dailyMixesProvider`, `mixByIdProvider`. |
| `lib/presentation/widgets/mix_card.dart` (nuevo) | Tarjeta. |
| `lib/presentation/screens/mix_detail_screen.dart` (nuevo) | Detalle. |
| `lib/router/app_router.dart` | Ruta `/mix/:id`. |

#### Caché y rendimiento

- Generación una vez al día; 3 llamadas de red como máximo (más reintentos controlados).
- Segunda apertura: instantánea desde caché.
- No se regenera al cambiar de canción ni al volver de otra pestaña.
- Offline: cero red.
- Las portadas usan la caché de imágenes existente.

#### Limitaciones y decisiones

- No es un Daily Mix oficial de YouTube Music; es una mezcla propia basada en el historial/estadísticas locales y recomendaciones de la API.
- Si el usuario es nuevo y no hay datos, la sección se oculta.
- No se garantiza que las canciones sean todas “nuevas”; se busca variedad y familiaridad.
- No se sincroniza entre dispositivos.

#### Criterios de aceptación

- [ ] Se generan 3 mezclas con 20–25 canciones cada una (o el mínimo disponible).
- [ ] No hay canciones duplicadas dentro de una mezcla ni entre mezclas.
- [ ] El mismo día devuelve las mismas mezclas (determinismo).
- [ ] La segunda apertura no hace red y es instantánea.
- [ ] En offline se generan mezclas locales.
- [ ] Se puede reproducir, abrir el detalle, guardar como playlist y descargar.

---

### 6.2 Novedades

**Prioridad:** Alta · **Fase:** 4

#### Objetivo

Mostrar lanzamientos nuevos de YouTube Music de forma rápida, usando una sola llamada de Explore y caché.

#### Experiencia de usuario

- Sección “Novedades” con carrusel de álbumes nuevos.
- Cada tarjeta: portada, título, artista, año/tipo si está disponible.
- “Ver todo” abre una cuadrícula con todos los lanzamientos.
- Si no hay datos, la sección se oculta (o muestra un estado compacto con retry si hubo error).

#### Implementación

1. **`ExploreService.getExploreBundle()`**:
   - Llama a `api.getExplore()`.
   - Extrae `new_releases`, `trending`, `moods_and_genres`, `top_songs` (si existe).
   - Mapea `new_releases` a `AlbumModel`.
2. **`newReleasesProvider`**
   - Deriva de `exploreBundleProvider`.
   - No hace una llamada propia.
   - Orden: el que devuelve Explore; si hay año, se puede ordenar por año descendente.
3. **UI**
   - `AlbumCarousel` reutilizable.
   - `SeeAllScreen` sección `newReleases` con `SliverGrid`.
4. **Fallback**
   - Si `getExplore()` falla, se puede intentar `getHome()` y extraer álbumes; si también falla, ocultar la sección y registrar el error.
   - No bloquear el resto de Inicio.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/services/explore_service.dart` | Parseo de `new_releases`. |
| `lib/providers/explore_providers.dart` | `exploreBundleProvider`, `newReleasesProvider`. |
| `lib/presentation/screens/home_screen.dart` | Sección Novedades. |
| `lib/presentation/widgets/home_carousels.dart` | `AlbumCarousel`. |
| `lib/presentation/screens/see_all_screen.dart` | Sección de novedades. |

#### Caché y rendimiento

- Compartida con Tendencias y Géneros: una sola llamada a Explore cada 12–24 h.
- TTL: 12 h memoria / 24 h disco.
- Si está cacheada, se muestra al instante y se refresca en segundo plano.
- No se piden detalles de cada álbum; solo la tarjeta.

#### Limitaciones y decisiones

- “Novedades” depende de lo que YouTube Music considere nuevo para la región/cuenta.
- No se puede garantizar que todos los álbumes tengan año; se muestra si existe.
- No se descargan portadas en alta resolución para la lista; se usa el tamaño adecuado.

#### Criterios de aceptación

- [ ] La sección muestra álbumes nuevos con portada/título/artista.
- [ ] “Ver todo” abre la cuadrícula completa.
- [ ] No se hace una llamada adicional a Explore por estar en Inicio.
- [ ] Si Explore falla, Inicio sigue funcionando y la sección se oculta o muestra retry.
- [ ] La segunda visita usa caché.

---

### 6.3 Tendencias / Charts

**Prioridad:** Alta · **Fase:** 4

#### Objetivo

Mostrar lo que está sonando y los rankings, con datos de Explore/Charts y manejo de las limitaciones de cuentas sin Premium.

#### Experiencia de usuario

- Sección “Tendencias & Charts” con dos subfilas:
  - **Tendencias**: canciones/playlists en tendencia (Explore).
  - **Top artistas / Charts**: artistas y playlists del ranking (Charts).
- Cada tarjeta se abre en su destino:
  - Canción → reproduce.
  - Artista → `ArtistScreen`.
  - Playlist → `PublicPlaylistScreen`.
- “Ver todo” abre una pantalla con:
  - Selector de país (si el usuario quiere).
  - Listas de charts disponibles.
  - Estados de “no disponible sin Premium” cuando aplique.

#### Implementación

1. **`ExploreService.getCharts(country)`**
   - Llama a `api.getCharts(country: country)`.
   - Mapea:
     - `videos`/`daily`/`weekly`/`genres` → `ChartPlaylist` (id, título, portada).
     - `artists` → `ChartArtist` (id, nombre, portada, rank, trend).
     - `countries` → opciones para el selector.
   - Cachea por país.
2. **`chartsProvider`**
   - `FutureProvider.autoDispose.family<ChartsSnapshot, String>` o provider único con país seleccionado.
   - País inicial: `Platform.localeName`/`Intl.getCurrentLocale()` si está en las opciones; si no, `ZZ`.
   - No se carga hasta que la sección entra en viewport.
3. **Tendencias**
   - `trendingProvider` deriva de `exploreBundleProvider`.
   - Si `trending` está vacío, se usa `top_songs` o se oculta la subfila.
4. **UI**
   - `TrendingSongsRow` con tarjetas compactas.
   - `ChartArtistsRow` con artistas circulares y rank.
   - `ChartPlaylistsRow`.
   - `ChartsScreen`/`SeeAllScreen` con selector de país.
5. **Premium**
   - Si `top_songs` no está disponible (cuenta sin Premium), no se muestra error; se usan tendencias/playlists/artistas.
   - Se puede mostrar un texto discreto “Top canciones no disponible en esta cuenta”.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/services/explore_service.dart` | `getCharts` y parseo. |
| `lib/data/models/explore_models.dart` | `ChartsSnapshot`, `ChartPlaylist`, `ChartArtist`. |
| `lib/providers/explore_providers.dart` | `chartsProvider`, país seleccionado. |
| `lib/presentation/screens/home_screen.dart` | Sección Tendencias & Charts. |
| `lib/presentation/screens/charts_screen.dart` o `see_all_screen.dart` | Pantalla completa. |

#### Caché y rendimiento

- Charts: 12 h memoria / 24 h disco por país.
- Tendencias: incluidas en el bundle de Explore.
- No se cargan charts si la sección no es visible.
- No se piden canciones de cada playlist del chart hasta que el usuario abre una.

#### Limitaciones y decisiones

- Los charts varían por país y pueden requerir autenticación para algunas listas.
- No se garantiza “Top canciones” sin Premium.
- No se implementa un ranking propio; se usa el de YouTube Music.
- El selector de país es opcional; por defecto se usa el locale o global.

#### Criterios de aceptación

- [ ] La sección muestra tendencias y al menos una lista de charts cuando hay datos.
- [ ] Tocar un artista/playlist/canción abre el destino correcto.
- [ ] “Ver todo” muestra las listas y el selector de país.
- [ ] Si no hay Premium, la sección no falla; muestra lo disponible.
- [ ] No se hace una llamada extra si la sección no se ve.

---

### 6.4 Géneros

**Prioridad:** Alta · **Fase:** 4

#### Objetivo

Dar acceso rápido a Moods & Genres desde Inicio, con una sola llamada compartida y sin cargar todas las playlists por adelantado.

#### Experiencia de usuario

- Sección “Géneros” con chips/tarjetas de categorías: Pop, Rock, Hip-Hop, R&B, Latina, Electrónica, Chill, Enfoque, Gym, etc.
- Al tocar un género se abre `GenreScreen` con sus playlists.
- “Ver todo” abre la lista completa de categorías.
- Las tarjetas usan gradientes/iconos, no imágenes que requieran llamadas adicionales.

#### Implementación

1. **`genresProvider`**
   - Deriva de `exploreBundleProvider` (`moods_and_genres`).
   - Para la lista completa, `getMoodCategories()` (cache 7 días).
2. **`GenreCategory`**:
   ```dart
   class GenreCategory {
     final String title;
     final String params;
     final String? group; // Moods, Genres, etc.
   }
   ```
3. **`GenreScreen`**
   - Ruta `/explore/genre?title=...&params=...`.
   - `genrePlaylistsProvider(params)` → `getMoodPlaylists(params)`.
   - Grid de `PublicPlaylistModel`.
   - Tap → `PublicPlaylistScreen`.
4. **UI**
   - `GenreChips`/`GenreCards` en Inicio.
   - `GenresScreen` (opcional) para “Ver todo”.
   - Iconos/gradientes por categoría (mapeo local; fallback genérico).
5. **Reutilización**
   - La misma sección/pantalla se usa en Buscador (5.7) y Mezclas de ánimo (6.10).

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/services/explore_service.dart` | `getMoodCategories`, `getMoodPlaylists`. |
| `lib/providers/explore_providers.dart` | `genresProvider`, `genrePlaylistsProvider`. |
| `lib/presentation/widgets/genre_chips.dart` (nuevo) | Chips/tarjetas. |
| `lib/presentation/screens/genre_screen.dart` (nuevo) | Playlists por género. |
| `lib/presentation/screens/genres_screen.dart` (opcional) | Todas las categorías. |
| `lib/router/app_router.dart` | Rutas de géneros. |

#### Caché y rendimiento

- Categorías: incluidas en Explore (12–24 h) o `getMoodCategories` (7 días).
- Playlists por género: 24 h.
- No se cargan las playlists de todos los géneros al abrir Inicio; solo al tocar uno.
- Las tarjetas no requieren imágenes remotas.

#### Limitaciones y decisiones

- La taxonomía y disponibilidad de géneros depende de YouTube Music/región.
- Los `params` son opacos; se codifican en la URL y se validan.
- Si un género no tiene playlists, se muestra un vacío claro.
- No se inventan géneros que la API no devuelve.

#### Criterios de aceptación

- [ ] Inicio muestra al menos 6 géneros cuando hay datos.
- [ ] Tocar un género abre sus playlists.
- [ ] “Ver todo” muestra todas las categorías.
- [ ] No se cargan playlists hasta abrir un género.
- [ ] Si Moods & Genres falla, la sección se oculta sin romper Inicio.

---

### 6.5 “Porque escuchaste…”

**Prioridad:** Alta · **Fase:** 4

#### Objetivo

Ofrecer recomendaciones contextuales basadas en el último artista escuchado, con un título claro y sin cambiar la sección con cada canción.

#### Experiencia de usuario

- Sección “Porque escuchaste <artista>”.
- Subtítulo: “Recomendaciones basadas en tu historial”.
- Carrusel de 10–12 canciones.
- “Ver todo” abre la lista completa.
- Si no hay historial suficiente, se usa el artista más escuchado o se oculta.

#### Implementación

1. **Semilla**
   - `stats.recent.first` o `history.first`.
   - Preferir el **artista** de la última canción para estabilidad.
   - Si no hay `artistId`, usar la canción y `getRelatedSongs`.
2. **`becauseYouListenedProvider`**
   - `FutureProvider.autoDispose<BecauseYouListened?>`.
   - Clave de caché: `home:because:v1:<artistId|songId>:<yyyy-mm-dd>`.
   - Llamadas:
     - `getArtistRecommendations(artistId, limit: 20)` si hay artista.
     - `getRelatedSongs(songId)` como complemento si hay canción.
   - Excluir el historial reciente y la canción semilla.
   - Equilibrar (máx. 2 por artista/álbum), intercalar y limitar a 12.
   - Si una llamada falla, usar la otra; si ambas fallan, devolver null.
3. **Estabilidad**
   - No se recalcula con cada canción reproducida; se usa `stats.recent.first` (que cambia al cambiar de canción, pero el provider se recrea al volver a Inicio).
   - Para evitar recargas constantes, usar una ventana de 30–60 minutos y cachear por artista/día.
4. **UI**
   - `SongCarousel` reutilizable.
   - Título dinámico: “Porque escuchaste <artista>”.
   - “Ver todo” → `SeeAllScreen` sección `becauseYouListened`.
5. **Offline**
   - Si no hay caché, ocultar; si hay, mostrar con badge “Guardado”.
   - No se intenta red en offline.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/providers/home_feed_providers.dart` | `becauseYouListenedProvider`, semilla. |
| `lib/data/models/home_models.dart` | `BecauseYouListened`. |
| `lib/presentation/screens/home_screen.dart` | Sección. |
| `lib/presentation/widgets/home_carousels.dart` | `SongCarousel`. |

#### Caché y rendimiento

- 1–2 llamadas de red por semilla/día.
- TTL: 6 h memoria / 24 h disco.
- Reutiliza la caché de `getArtistRecommendations`/`getRelatedSongs`.
- No se recalcula al cambiar de canción si el artista no cambió.

#### Limitaciones y decisiones

- No se usa un modelo de recomendación propio; se usan las recomendaciones de YouTube Music.
- Si el usuario no tiene historial, la sección se oculta (o se usa “Top artistas”).
- El título puede ser “Porque escuchaste <artista>” en lugar de una canción; es más estable y igual de claro.

#### Criterios de aceptación

- [ ] La sección aparece cuando hay historial/estadísticas.
- [ ] El título incluye el artista semilla.
- [ ] No se repiten canciones del historial reciente.
- [ ] La sección no cambia de contenido con cada canción.
- [ ] “Ver todo” abre la lista completa.
- [ ] Si la red falla, no rompe Inicio.

---

### 6.6 “Redescubre”

**Prioridad:** Alta · **Fase:** 4

#### Objetivo

Recuperar canciones que el usuario escuchaba antes pero que hace tiempo no suenan, sin llamadas de red.

#### Experiencia de usuario

- Sección “Redescubre”.
- Subtítulo: “Canciones que hace tiempo que no escuchas”.
- Carrusel de 10–12 canciones.
- Cada tarjeta muestra portada, título, artista y, si es posible, “Hace X días”.
- “Ver todo” abre la lista completa.
- Si no hay datos suficientes, la sección se oculta.

#### Implementación

1. **`rediscoverProvider`** (local)
   - Usa `ListeningStatsService.snapshot().topSongs`.
   - Filtra:
     - `lastPlayed == null` o `now.difference(lastPlayed) > 30 días`.
     - `plays > 0`.
   - Ordena por `seconds`/`plays` descendente y toma 12.
   - Fallback:
     - Favoritos que no estén en `history.take(30)`.
     - Canciones descargadas que no estén en el historial reciente.
   - Si no hay datos, devuelve `[]`.
2. **UI**
   - `SongCarousel` con subtítulo personalizado.
   - `SeeAllScreen` sección `rediscover`.
3. **Rendimiento**
   - Solo local; se calcula en memoria.
   - Se puede cachear en un `Provider` hasta que cambien las estadísticas.
4. **Privacidad**
   - No se envía nada a la red.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/providers/home_feed_providers.dart` | `rediscoverProvider`. |
| `lib/presentation/screens/home_screen.dart` | Sección. |
| `lib/presentation/screens/see_all_screen.dart` | Sección. |

#### Caché y rendimiento

- Sin red.
- Recalcula solo cuando cambia `statsProvider`/historial/favoritos.
- Instantáneo.

#### Limitaciones y decisiones

- Depende de que existan estadísticas de escucha. Para usuarios nuevos, se usa el fallback de favoritos.
- “Hace X días” se calcula con `lastPlayed`; si no existe, no se muestra.
- No se mezclan canciones nunca escuchadas; para eso está “Para ti”.

#### Criterios de aceptación

- [ ] La sección muestra canciones no escuchadas en los últimos 30 días.
- [ ] No hace llamadas de red.
- [ ] “Ver todo” muestra la lista completa.
- [ ] Si no hay datos, se oculta sin error.
- [ ] La sección se actualiza al cambiar el historial/estadísticas.

---

### 6.7 Top artistas

**Prioridad:** Alta · **Fase:** 4

#### Objetivo

Mostrar los artistas más escuchados por el usuario, con acceso a su página, usando datos locales y enriquecimiento opcional.

#### Experiencia de usuario

- Sección “Top artistas”.
- Carrusel circular con foto, nombre y tiempo/reproducciones.
- Al tocar un artista:
  - Si tiene ID, abre `ArtistScreen`.
  - Si no, abre la búsqueda con el nombre precargado o el mejor resultado.
- “Ver todo” abre la lista completa (top 10–20).

#### Implementación

1. **Modelo `TopArtist`**:
   ```dart
   class TopArtist {
     final String name;
     final String? id;
     final String? imageUrl;
     final int plays;
     final int seconds;
   }
   ```
2. **`topArtistsProvider`** (local)
   - Usa `stats.snapshot().topArtists` (nombre, plays, seconds).
   - Construye un mapa de nombres a IDs/imágenes a partir de canciones locales:
     - `favorites`, `history`, `downloads`, `playlists`.
     - Para cada canción, asociar `song.artists[i]` con `song.artistIds?[i]`.
     - Imagen: `song.artworkUrl` (mejor que nada) o `highResThumbnailUrl`.
   - Si no hay ID:
     - Mostrar avatar genérico.
     - Enriquecimiento opcional en segundo plano: `searchArtists(name)` para los top 5, con caché 7 días y concurrencia 2; no bloquear la UI.
3. **UI**
   - `ArtistCarousel` con `CircleAvatar`/`AlbumArt` circular.
   - Subtítulo con `plays` o tiempo.
   - Tap → artista o búsqueda.
   - `SeeAllScreen` sección `topArtists`.
4. **Caché**
   - Local; sin red para lo básico.
   - Enriquecimiento cacheado por nombre.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/models/home_models.dart` | `TopArtist`. |
| `lib/providers/home_feed_providers.dart` | `topArtistsProvider`. |
| `lib/presentation/widgets/home_carousels.dart` | `ArtistCarousel`. |
| `lib/presentation/screens/home_screen.dart` | Sección. |
| `lib/presentation/screens/see_all_screen.dart` | Sección. |

#### Caché y rendimiento

- Cálculo local rápido.
- El enriquecimiento es opcional y no bloquea; si falla, se usa el avatar genérico.
- No se hace una búsqueda por cada artista de la lista completa; solo para los visibles/top 5.

#### Limitaciones y decisiones

- `ArtistStat` solo tiene nombre, no ID; se resuelve con las canciones locales.
- Si un artista no tiene ID ni canción con ID, no se puede abrir su página; se abre la búsqueda.
- La imagen puede ser la portada de una canción, no una foto oficial del artista; se acepta como fallback.

#### Criterios de aceptación

- [ ] La sección muestra los artistas más escuchados con su tiempo/reproducciones.
- [ ] Tocar un artista con ID abre su página.
- [ ] Tocar un artista sin ID abre una búsqueda útil.
- [ ] No se bloquea la sección por el enriquecimiento.
- [ ] “Ver todo” muestra la lista completa.

---

### 6.8 Nuevo de artistas que sigues

**Prioridad:** Alta · **Fase:** 5

#### Objetivo

Permitir seguir artistas localmente y mostrar sus lanzamientos recientes en Inicio.

#### Experiencia de usuario

- En `ArtistScreen` aparece un botón **Seguir** / **Siguiendo**.
- En los resultados de búsqueda de artistas, un icono de seguimiento.
- Sección “Nuevo de artistas que sigues”:
  - Carrusel de álbumes/singles recientes.
  - Cada tarjeta muestra portada, título, artista y año/tipo.
  - “Ver todo” abre una cuadrícula.
- Si no hay artistas seguidos:
  - La sección se oculta, o muestra una tarjeta CTA “Sigue artistas para ver sus novedades” con botón “Buscar artistas”.
- Si un artista no tiene novedades, no se muestra.
- El seguimiento persiste tras reiniciar.
- No se sincroniza con la cuenta de YouTube Music (limitación documentada).

#### Implementación

1. **Persistencia**
   - Nueva caja Hive `followedArtists` (añadir a `AppConstants` y abrir en `main.dart`).
   - Modelo `FollowedArtist`:
     ```dart
     class FollowedArtist {
       final String id;
       final String name;
       final String? thumbnailUrl;
       final DateTime followedAt;
     }
     ```
   - `FollowedArtistsRepository` (nuevo) con `list`, `toggle`, `isFollowing`, `stream`.
   - `FollowedArtistsNotifier`/`followedArtistsProvider` y `isFollowingArtistProvider(id)`.
2. **UI de seguimiento**
   - `ArtistScreen`: botón junto a Reproducir/Aleatorio.
   - `SearchScreen` (pestaña Artistas): icono de seguimiento.
   - SnackBar al seguir/dejar de seguir.
   - No se requiere autenticación.
3. **`followedReleasesProvider`**
   - Para cada artista seguido (máximo 10):
     - `getArtistPage(id)` (ya existe, cacheado).
     - Extraer `albumes` (álbumes/singles) con `year`.
     - Filtrar:
       - `year >= currentYear - 1`.
       - Si no hay año, incluir los primeros 3 por orden del artista.
     - Tomar hasta 3 por artista.
   - Concurrencia máxima: 2.
   - Errores aislados: si un artista falla, se omite.
   - Ordenar por año descendente y luego por título.
   - Deduplicar por `album.id`.
   - Cachear por artista: `home:followedReleases:<artistId>` (24 h).
4. **UI**
   - `AlbumCarousel` con tarjetas.
   - `SeeAllScreen` sección `followedReleases`.
   - CTA si no hay seguidos.
5. **Offline**
   - Usar releases cacheadas; si no hay, ocultar.
   - El botón de seguir funciona offline (local).
6. **Límites**
   - Máximo 10 artistas para no disparar llamadas.
   - Si el usuario sigue más, se muestran los 10 primeros por `followedAt` y “Ver todos” puede cargar el resto de forma perezosa.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/models/home_models.dart` | `FollowedArtist`. |
| `lib/data/repositories/followed_artists_repository.dart` (nuevo) | CRUD en Hive. |
| `lib/providers/followed_artists_providers.dart` (nuevo) | Providers/notifier. |
| `lib/providers/home_feed_providers.dart` | `followedReleasesProvider`. |
| `lib/presentation/screens/artist_screen.dart` | Botón Seguir/Siguiendo. |
| `lib/presentation/screens/search_screen.dart` | Icono de seguimiento en artistas. |
| `lib/presentation/screens/home_screen.dart` | Sección. |
| `lib/core/constants/app_constants.dart` | Nombre de la caja. |
| `lib/main.dart` | Abrir la caja. |

#### Caché y rendimiento

- Seguir/dejar de seguir: local, instantáneo.
- Releases: una llamada por artista, como máximo 10, con concurrencia 2 y caché 24 h.
- Sección cargada de forma perezosa (está baja en el feed).
- No se refresca al cambiar de canción.

#### Limitaciones y decisiones

- El paquete no expone `subscribeArtist`; el seguimiento es local, no una suscripción de YouTube Music.
- `getArtistPage` devuelve los álbumes/singles principales; no se garantiza que incluya todos los lanzamientos.
- La fecha de lanzamiento puede faltar; se usa el orden del artista.
- No se muestran notificaciones push de nuevos lanzamientos; solo la sección de Inicio.

#### Criterios de aceptación

- [ ] Se puede seguir/dejar de seguir un artista desde su página y desde la búsqueda.
- [ ] El estado persiste tras reiniciar.
- [ ] La sección muestra lanzamientos recientes de los artistas seguidos.
- [ ] Si un artista falla, los demás siguen mostrándose.
- [ ] “Ver todo” muestra la cuadrícula completa.
- [ ] En offline se usa la caché y no se rompe.

---

### 6.9 “Ver todo” en cada sección

**Prioridad:** Media · **Fase:** 3

#### Objetivo

Permitir ver la lista completa de cualquier sección de Inicio sin duplicar pantallas ni lógica.

#### Experiencia de usuario

- Cada encabezado de sección tiene un botón **Ver todo** (solo si hay más elementos o una vista completa con sentido).
- Al pulsarlo se abre una pantalla con:
  - Título y subtítulo de la sección.
  - Lista/cuadrícula completa.
  - Mismo estilo visual y acciones que la sección.
  - Paginación si el provider la soporta.
- Para secciones que ya tienen pantalla propia, se reutiliza:
  - Favoritos → `/library/favorites`.
  - Playlists → `/library/playlists`.
  - Historial/Seguir escuchando → `/library/history`.
  - Descargas → `/downloads`.
- Para las nuevas secciones se usa `SeeAllScreen`.

#### Implementación

1. **`SeeAllSection` enum**
   - `dailyMixes`, `continueListening`, `forYou`, `newReleases`, `trending`, `charts`, `genres`, `becauseYouListened`, `rediscover`, `topArtists`, `followedReleases`, `recentAlbums`, `playlists`, `favorites`.
2. **Ruta `/see-all/:section`**
   - Parsear el enum; si es inválido, mostrar estado vacío.
   - `SeeAllScreen` con `AppBar` y contenido.
3. **Renderizado por tipo**
   - Canciones: `SongListView` (reutilizable) con `SongTile`.
   - Álbumes: `AlbumGridView`.
   - Artistas: `ArtistListView`/`ArtistGrid`.
   - Playlists: `PlaylistGridView`.
   - Mixes: `MixListView` con `MixCard`.
4. **Providers**
   - Cada sección busca su provider correspondiente.
   - Si el provider tiene paginación, `SeeAllScreen` muestra “Cargar más”.
   - Si es local, muestra todo.
5. **Reutilización**
   - Extraer `SongListView`, `AlbumGridView`, `ArtistListView`, `PlaylistGridView` de la biblioteca/Inicio.
   - No duplicar `SongTile` ni las tarjetas.
6. **Condición de “Ver todo”**
   - Mostrarlo si `items.length > sectionLimit` o si la sección tiene una vista completa aunque tenga pocos elementos (p. ej., Daily Mix).
   - No mostrarlo en secciones que ya son un acceso directo (Descargas).

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/presentation/screens/see_all_screen.dart` (nuevo) | Pantalla genérica. |
| `lib/presentation/widgets/section_header.dart` | Botón “Ver todo”. |
| `lib/presentation/widgets/song_list_view.dart` (nuevo) | Lista reutilizable. |
| `lib/presentation/widgets/album_grid_view.dart` (nuevo) | Grid reutilizable. |
| `lib/router/app_router.dart` | Ruta `/see-all/:section`. |
| `lib/presentation/screens/home_screen.dart` | Encabezados con “Ver todo”. |

#### Caché y rendimiento

- Usa los mismos providers/cachés de la sección; no duplica llamadas.
- La pantalla se carga al abrir; las secciones de Inicio no se ven afectadas.
- Para listas grandes, paginación o lazy loading.

#### Limitaciones y decisiones

- No se crea una pantalla distinta por sección; un switch controlado evita duplicación.
- Las secciones locales muestran todo de una vez; no necesitan paginación.
- “Ver todo” no debe aparecer si no aporta nada (por ejemplo, una sección con 3 elementos y sin más).

#### Criterios de aceptación

- [ ] Cada sección con más elementos muestra “Ver todo”.
- [ ] La pantalla muestra el título/subtítulo correctos y el contenido completo.
- [ ] Se reutilizan las pantallas existentes cuando existen.
- [ ] No se duplican llamadas de red.
- [ ] Volver atrás conserva el scroll de Inicio.

---

### 6.10 Mezclas por estado de ánimo/actividad

**Prioridad:** Media · **Fase:** 5

#### Objetivo

Ofrecer accesos rápidos a mezclas de “Enfoque”, “Gym”, “Chill”, “Dormir” y “Fiesta” usando Moods & Genres, sin cargar playlists por adelantado.

#### Experiencia de usuario

- Sección “Mezclas para tu momento” con tarjetas horizontales:
  - **Enfocado** (icono de concentración).
  - **Gym** (icono de fitness).
  - **Chill** (icono de relax).
  - **Dormir** (icono de luna).
  - **Fiesta** (icono de fiesta).
- Cada tarjeta tiene gradiente/icono, no una imagen remota.
- Al tocar:
  - Si hay una categoría de Moods & Genres compatible, se abre `GenreScreen` con sus playlists.
  - Si no, se abre una mezcla generada a partir de una consulta curada (fallback).
- “Ver todo” abre todas las mezclas disponibles.

#### Implementación

1. **`MoodMixConfig`** (local)
   - Lista de configuraciones:
     ```dart
     const moodMixes = [
       MoodMixConfig(id: 'focus', title: 'Enfocado', keywords: ['focus', 'enfoque', 'concentración', 'study'], fallbackQuery: 'focus music'),
       MoodMixConfig(id: 'gym', title: 'Gym', keywords: ['gym', 'workout', 'entrenamiento', 'fitness'], fallbackQuery: 'workout music'),
       MoodMixConfig(id: 'chill', title: 'Chill', keywords: ['chill', 'relax', 'relajación', 'calma'], fallbackQuery: 'chill music'),
       MoodMixConfig(id: 'sleep', title: 'Dormir', keywords: ['sleep', 'dormir', 'descanso'], fallbackQuery: 'sleep music'),
       MoodMixConfig(id: 'party', title: 'Fiesta', keywords: ['party', 'fiesta', 'dance'], fallbackQuery: 'party music'),
     ];
     ```
2. **`moodMixesProvider`**
   - Usa `genresProvider` (Explore) y, si hace falta, `getMoodCategories`.
   - Normaliza los títulos y busca coincidencias con `keywords`.
   - Para cada coincidencia, crea un `MoodMix` con `genreParams` (para abrir `GenreScreen`) y un gradiente/icono.
   - Si no hay coincidencia, crea un `MoodMix` con `fallbackQuery` (para generar búsqueda/mezcla al tocar).
   - No carga playlists de todos los moods; solo resuelve el mapeo.
3. **Fallback**
   - Al tocar una tarjeta sin `genreParams`:
     - Buscar `fallbackQuery` con `SearchService.searchSongs` (cacheado).
     - Mezclar con favoritos/descargas del mismo “estado” si es posible.
     - Abrir `MixDetailScreen` con los resultados.
   - Si no hay resultados, mostrar un vacío con “Explorar géneros”.
4. **UI**
   - `MoodMixCard` con gradiente/icono.
   - `SeeAllScreen` sección `moodMixes` (opcional).
5. **Caché**
   - Mapeo de moods: se deriva de Explore (cacheado).
   - Playlists del género: 24 h.
   - Fallback de búsqueda: caché de búsqueda existente.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/data/models/home_models.dart` | `MoodMix`, `MoodMixConfig`. |
| `lib/providers/home_feed_providers.dart` | `moodMixesProvider`. |
| `lib/presentation/widgets/mood_mix_card.dart` (nuevo) | Tarjeta. |
| `lib/presentation/screens/home_screen.dart` | Sección. |
| `lib/presentation/screens/genre_screen.dart` | Reutilizada para moods. |

#### Caché y rendimiento

- No se cargan playlists de moods al abrir Inicio.
- Las tarjetas usan gradientes/iconos locales.
- El fallback solo se ejecuta al tocar y se cachea como una búsqueda normal.
- Sin llamadas adicionales si el mood está mapeado a un género.

#### Limitaciones y decisiones

- La disponibilidad de moods varía por país; el fallback cubre los que falten.
- No se usan datos de tempo/energía porque la API no los expone por canción.
- Las mezclas de fallback son aproximadas; se etiquetan como “Mezcla” no como “Mood oficial”.

#### Criterios de aceptación

- [ ] Se muestran al menos 3 tarjetas de estado de ánimo/actividad.
- [ ] Las tarjetas mapeadas abren un género con playlists.
- [ ] Las no mapeadas abren una mezcla de fallback con resultados.
- [ ] No se cargan playlists hasta tocar una tarjeta.
- [ ] Si no hay datos, la sección se oculta sin romper Inicio.

---

### 6.11 Chips de reproducción reciente

**Prioridad:** Baja · **Fase:** 5

#### Objetivo

Dar acceso rápido a lo último reproducido con chips compactos y sin ocupar demasiado espacio.

#### Experiencia de usuario

- Debajo del saludo, una fila horizontal de chips:
  - Miniatura de portada.
  - Título de la canción (truncado).
  - Opcional: artista.
- Al tocar un chip:
  - Reproduce esa canción y usa la lista de recientes como cola, empezando por ese índice.
- Al mantener pulsado (opcional): menú “Reproducir”, “Ir al artista”, “Añadir a la cola”.
- Si no hay historial, no se muestra la fila.
- Máximo 8 chips.

#### Implementación

1. **`recentChipsProvider`**
   - `stats.recent.take(8)`; si está vacío, `history.take(8)`.
   - Devuelve `List<SongModel>`.
2. **UI**
   - `RecentChipsRow` con `ListView.separated(scrollDirection: Axis.horizontal)`.
   - `ActionChip`/`InputChip` personalizado con `AlbumArt` de 24–28 px.
   - Tap: `audioHandler.playSongs(recentSongs, startIndex: index)`.
   - No navegar automáticamente a “Reproduciendo” si el usuario está en Inicio; se puede mostrar el mini player. Si se desea, navegar después de un toque en el chip (decisión de UX: mantener Inicio y usar el mini player).
3. **Rendimiento**
   - Local, sin red.
   - Solo se reconstruye cuando cambia el historial/estadísticas.
   - `ListView.builder` horizontal.

#### Archivos implicados

| Archivo | Cambio |
|---|---|
| `lib/providers/home_feed_providers.dart` | `recentChipsProvider`. |
| `lib/presentation/widgets/recent_chips_row.dart` (nuevo) | Fila de chips. |
| `lib/presentation/screens/home_screen.dart` | Integración debajo del saludo. |

#### Caché y rendimiento

- Sin red.
- Datos locales actualizados por `statsProvider`/historial.
- No se cachean imágenes adicionales; usan la caché existente.

#### Limitaciones y decisiones

- Es una mejora de baja prioridad; si el espacio superior queda muy cargado, se puede mostrar solo en pantallas anchas o colapsar.
- No se muestran artistas/álbumes recientes como chips en esta fase; solo canciones.
- No se guarda un historial separado; se usa el existente.

#### Criterios de aceptación

- [ ] Se muestran hasta 8 chips de canciones recientes.
- [ ] Tocar un chip reproduce esa canción con la cola de recientes.
- [ ] No hay llamadas de red.
- [ ] Si no hay historial, la fila no aparece.
- [ ] No interfiere con el saludo ni con el banner offline.

---

## 7. Arquitectura técnica propuesta

### 7.1 Capas y flujo de datos

```
┌─────────────────────────────────────────────────────────────┐
│ UI (screens / widgets)                                      │
│  SearchScreen · HomeScreen · PublicPlaylistScreen · ...     │
└──────────────────────────────┬──────────────────────────────┘
                               │ ref.watch / ref.read
┌──────────────────────────────▼──────────────────────────────┐
│ Providers (Riverpod)                                        │
│  query, filtros, paginación, secciones, selección, seguidos │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│ Servicios de dominio                                        │
│  SearchService · LocalSearchService · ExploreService        │
│  DailyMixService · LyricsIndexService · MixUtils             │
└───────────────┬──────────────────────────────┬──────────────┘
                │                              │
┌───────────────▼──────────────┐  ┌────────────▼──────────────┐
│ YtService (API + caché)      │  │ Repositorios locales       │
│  ytmusicapi_dart             │  │  Hive: favoritos, playlists│
│  AppCache                    │  │  historial, descargas,     │
│                              │  │  ajustes, artistas seguidos│
└──────────────────────────────┘  └────────────────────────────┘
```

Reglas:

- **La UI no llama a `YtService` directamente** para las nuevas funciones; usa providers.
- **Los servicios no conocen widgets ni `BuildContext`**.
- **Los providers no contienen lógica de red compleja**; orquestan servicios y cache.
- **Los modelos son inmutables** (`final`, `const` cuando se pueda) y tienen `fromJson`/`toJson` cuando se persisten.
- **Los errores de red se capturan en el provider o servicio** y se exponen como `AsyncValue.error` o estados tipados.

### 7.2 Modelos nuevos y cambios

#### Modelos nuevos

| Modelo | Campos principales | Persistencia |
|---|---|---|
| `SearchFilters` | `scope`, `onlyDownloaded`, `duration`, `year`, `genres`, `quality`, `sort` | No (sesión) |
| `SearchScope` (enum) | `catalog`, `library`, `lyrics` | No |
| `DurationRange` | `min`, `max` | No |
| `YearRange` | `from`, `to` | No |
| `DownloadQualityFilter` (enum) | `high`, `medium`, `low` | No |
| `SearchSort` (enum) | `relevance`, `popularity`, `durationAsc`, `durationDesc`, `recent`, `titleAsc` | No |
| `SearchAllResult` | `topResult`, `songs`, `albums`, `artists`, `playlists`, `query`, `fetchedAt` | No (caché JSON) |
| `SearchTopResult` | `type`, `song`, `album`, `artist`, `playlist` | No |
| `SearchSuggestion` | `text`, `runs`, `fromHistory`, `feedbackToken` | No |
| `SearchPageState<T>` | `items`, `page`, `loading`, `loadingMore`, `error`, `hasMore`, `requestId` | No |
| `PublicPlaylistModel` | `id`, `title`, `author`, `description`, `thumbnailUrl`, `itemCount`, `year`, `durationSeconds`, `isOfficial` | Caché JSON |
| `PublicPlaylistPage` | `playlist`, `songs` | Caché JSON |
| `LocalSearchResult` | `topResult`, `songs`, `albums`, `artists`, `playlists` | No |
| `LocalSongHit` | `song`, `sources`, `playlistNames`, `score` | No |
| `DailyMix` | `id`, `title`, `subtitle`, `coverUrls`, `songs`, `generatedAt`, `isOffline` | Caché JSON |
| `BecauseYouListened` | `seedArtist`, `seedSong`, `songs` | Caché JSON |
| `TopArtist` | `name`, `id`, `imageUrl`, `plays`, `seconds` | No |
| `FollowedArtist` | `id`, `name`, `thumbnailUrl`, `followedAt` | Hive JSON |
| `MoodMix` | `id`, `title`, `subtitle`, `icon`, `gradient`, `genreParams`, `fallbackQuery` | No |
| `GenreCategory` | `title`, `params`, `group` | Caché JSON |
| `ExploreBundle` | `newReleases`, `trending`, `genres`, `topSongsPlaylistId` | Caché JSON |
| `ChartsSnapshot` | `country`, `countries`, `playlists`, `artists`, `fetchedAt` | Caché JSON |
| `ChartPlaylist` | `id`, `title`, `thumbnailUrl`, `category` | Caché JSON |
| `ChartArtist` | `id`, `name`, `thumbnailUrl`, `rank`, `trend` | Caché JSON |
| `LyricsHit` | `song`, `line`, `snippet`, `score` | No |
| `LyricsIndexProgress` | `indexed`, `total`, `running`, `error` | No |
| `SeeAllSection` (enum) | secciones de Inicio | No |

#### Cambios en modelos existentes

- `SongModel`: añadir `String? genre` (opcional, por defecto `null`). No cambia la reproducción ni la serialización existente; `toJson` lo incluye si no es null.
- `AlbumModel`: añadir `String? genre` (opcional). Se usa para el filtro local y para contenido de Moods & Genres.
- `PlaylistModel`: **no se toca**. Sigue siendo el modelo de playlists locales.
- `DownloadEntry`: se mantiene igual; ya tiene `quality`.

### 7.3 Servicios nuevos

| Servicio | Responsabilidad | Dependencias |
|---|---|---|
| `SearchService` | Búsqueda mixta/filtrada, sugerencias, playlists públicas, normalización de consultas, `ignoreSpelling`. | `YtService`, `AppCache`. |
| `LocalSearchService` | Índice local, búsqueda en biblioteca, búsqueda dentro de canciones, ranking. | `LocalRepository`/listas, `TextUtils`. |
| `ExploreService` | Explore, moods, genres, charts, parseo a modelos. | `YtService`, `AppCache`. |
| `DailyMixService` | Generación de Daily Mix online/offline, determinismo, caché diaria. | `YtService`, `ListeningStatsService`, `MixUtils`. |
| `LyricsIndexService` | Índice de letras cacheadas/descargadas y búsqueda por letra. | `AppCache`, `YtService`, `DownloadService`. |
| `FollowedArtistsRepository` | CRUD de artistas seguidos en Hive. | Hive box `followedArtists`. |
| `VoiceSearchController` | Envolver `speech_to_text`, permisos y estados. | `speech_to_text`, `permission_handler`. |
| `TextUtils` | Normalización, tokens, Levenshtein, similitud. | Dart puro. |
| `SearchSort` | Funciones de orden por tipo. | Dart puro. |
| `MixUtils` | Deduplicación, intercalado, equilibrio, shuffle determinista. | Dart puro. |

#### Interfaces para testabilidad

Para no depender de `YTMusic` en pruebas, se propone:

- `abstract class SearchDataSource` con los métodos que usa `SearchService`.
- `abstract class ExploreDataSource` con los métodos que usa `ExploreService`.
- `YtService implements SearchDataSource, ExploreDataSource`.
- Los providers dependen de las interfaces; en tests se inyecta un fake.

Esto permite probar paginación, filtros, secciones y estados de error sin red.

### 7.4 Providers

| Provider | Tipo | Propósito |
|---|---|---|
| `searchQueryProvider` | `StateProvider<String>` | Consulta actual (se conserva). |
| `searchTabProvider` | `StateProvider<SearchTab>` | Pestaña activa. |
| `searchScopeProvider` | `StateProvider<SearchScope>` | Catálogo / biblioteca / letras. |
| `searchFiltersProvider` | `StateNotifierProvider<SearchFiltersNotifier, SearchFilters>` | Filtros y orden. |
| `searchHistoryProvider` | `StateNotifierProvider<SearchHistoryNotifier, List<String>>` | Historial local con borrado individual. |
| `searchSuggestionsQueryProvider` | `StateProvider<String>` | Query debounced para sugerencias. |
| `searchSuggestionsProvider` | `FutureProvider.autoDispose.family<List<SearchSuggestion>, String>` | Sugerencias. |
| `searchAllProvider` | `FutureProvider.autoDispose.family<SearchAllResult, String>` | Pestaña Todo. |
| `searchSongsProvider` | `StateNotifierProvider.autoDispose.family<SearchPageNotifier<SongModel>, String>` | Canciones paginadas. |
| `searchAlbumsProvider` | `StateNotifierProvider.autoDispose.family<SearchPageNotifier<AlbumModel>, String>` | Álbumes paginados. |
| `searchArtistsProvider` | `StateNotifierProvider.autoDispose.family<SearchPageNotifier<ArtistModel>, String>` | Artistas paginados. |
| `searchPlaylistsProvider` | `StateNotifierProvider.autoDispose.family<SearchPageNotifier<PublicPlaylistModel>, String>` | Playlists paginadas. |
| `searchViewProvider` | `Provider` derivado | Resultados filtrados/ordenados. |
| `searchSelectionProvider` | `StateNotifierProvider<SearchSelectionNotifier, SearchSelectionState>` | Selección múltiple. |
| `downloadedSongIdsProvider` | `Provider<Set<String>>` | IDs descargados. |
| `downloadedAlbumIdsProvider` | `Provider<Set<String>>` | Álbumes con descargas. |
| `downloadedArtistIdsProvider` | `Provider<Set<String>>` | Artistas con descargas. |
| `downloadQualityByIdProvider` | `Provider<Map<String, String>>` | Calidad por descarga. |
| `effectiveOfflineProvider` | `Provider<bool>` | Offline manual o sin conexión. |
| `localSearchIndexProvider` | `Provider<LocalSearchIndex>` | Índice local. |
| `offlineSearchProvider` | `Provider.family<LocalSearchResult, String>` | Búsqueda local. |
| `localAlbumProvider` | `Provider.family<AlbumModel?, String>` | Detalle de álbum offline. |
| `localArtistProvider` | `Provider.family<ArtistModel?, String>` | Detalle de artista offline. |
| `publicPlaylistProvider` | `FutureProvider.autoDispose.family<PublicPlaylistPage, String>` | Playlist pública. |
| `exploreBundleProvider` | `FutureProvider<ExploreBundle>` | Explore compartido. |
| `trendingProvider` | `Provider<List<SongModel>>` | Tendencias. |
| `newReleasesProvider` | `Provider<List<AlbumModel>>` | Novedades. |
| `genresProvider` | `Provider<List<GenreCategory>>` | Géneros. |
| `genrePlaylistsProvider` | `FutureProvider.autoDispose.family<List<PublicPlaylistModel>, String>` | Playlists de un género. |
| `chartsProvider` | `FutureProvider.autoDispose.family<ChartsSnapshot, String>` | Charts por país. |
| `dailyMixesProvider` | `FutureProvider.autoDispose<List<DailyMix>>` | Daily Mix. |
| `mixByIdProvider` | `Provider.family<DailyMix?, String>` | Detalle de mix. |
| `becauseYouListenedProvider` | `FutureProvider.autoDispose<BecauseYouListened?>` | Porque escuchaste. |
| `rediscoverProvider` | `Provider<List<SongModel>>` | Redescubre. |
| `topArtistsProvider` | `Provider<List<TopArtist>>` | Top artistas. |
| `followedArtistsProvider` | `StateNotifierProvider<FollowedArtistsNotifier, List<FollowedArtist>>` | Artistas seguidos. |
| `isFollowingArtistProvider` | `Provider.family<bool, String>` | Estado de seguimiento. |
| `followedReleasesProvider` | `FutureProvider.autoDispose<List<AlbumModel>>` | Novedades de seguidos. |
| `moodMixesProvider` | `Provider<List<MoodMix>>` | Mezclas de ánimo. |
| `recentChipsProvider` | `Provider<List<SongModel>>` | Chips recientes. |
| `lyricsIndexProvider` | `Provider<LyricsIndexService>` | Índice de letras. |
| `lyricsSearchProvider` | `FutureProvider.autoDispose.family<List<LyricsHit>, String>` | Búsqueda por letra. |
| `seeAllProvider` | `Provider.family<SeeAllData, SeeAllSection>` | Datos para “Ver todo”. |

> **Nota:** algunos providers existentes se mantienen (`homeRecommendationsProvider`, `homeRecentAlbumsProvider`, `artistSpotlightProvider`, `statsProvider`, etc.). No se renombran para no romper la UI existente.

### 7.5 Pantallas y widgets

#### Pantallas nuevas

| Pantalla | Ruta | Propósito |
|---|---|---|
| `PublicPlaylistScreen` | `/public-playlist/:id` | Detalle de playlist pública. |
| `SeeAllScreen` | `/see-all/:section` | “Ver todo” genérico. |
| `MixDetailScreen` | `/mix/:id` | Detalle de Daily Mix/mezcla. |
| `GenreScreen` | `/explore/genre?title=...&params=...` | Playlists de un género/mood. |
| `GenresScreen` (opcional) | `/explore/genres` | Todas las categorías. |
| `ChartsScreen` (opcional) | `/explore/charts` | Charts con selector de país. |

#### Pantallas modificadas

- `SearchScreen`: reescritura modular.
- `HomeScreen`: slivers y secciones nuevas.
- `ArtistScreen`: botón Seguir/Siguiendo; fallback local offline.
- `AlbumDetailScreen`: fallback local offline.
- `NowPlayingScreen`: búsqueda en la cola.
- `PlaylistDetailScreen`: búsqueda mejorada.
- `DownloadsScreen`: búsqueda mejorada/reutilizada.

#### Widgets nuevos

| Widget | Uso |
|---|---|
| `SearchHeader` | Título, barra, filtros. |
| `SearchTabs` | Pestañas horizontales. |
| `SearchSuggestionsPanel` | Autocompletado. |
| `SearchDiscovery` | Explorar (historial, tendencias, géneros). |
| `SearchFilterSheet` | Filtros y orden. |
| `SearchActiveFilters` | Chips de filtros activos. |
| `SearchEmptyState` | Estados vacíos contextuales. |
| `SearchSelectionBar` | Acciones masivas. |
| `SearchLoadMore` | Paginación reutilizable. |
| `SpellingSuggestionBanner` | “Quizás quisiste decir”. |
| `LyricsSearchResults` | Resultados de letras. |
| `LocalSearchField` | Buscar dentro de playlist/cola/descargas. |
| `SectionHeader` | Título + “Ver todo”. |
| `HomeSectionShell` | Carga/error/vacío por sección. |
| `SongCarousel` / `AlbumCarousel` / `ArtistCarousel` / `PlaylistCarousel` | Carruseles de Inicio. |
| `MixCard` | Tarjeta de Daily Mix. |
| `MoodMixCard` | Tarjeta de estado de ánimo. |
| `GenreChips` | Géneros. |
| `RecentChipsRow` | Chips de reproducción reciente. |
| `PlaylistPickerSheet` | Selector de playlist para acciones masivas. |
| `SongListView` / `AlbumGridView` / `ArtistListView` / `PlaylistGridView` | Vistas reutilizables para “Ver todo”. |

### 7.6 Rutas nuevas

| Ruta | Pantalla | Transición |
|---|---|---|
| `/public-playlist/:id` | `PublicPlaylistScreen` | `_slideUp` |
| `/see-all/:section` | `SeeAllScreen` | `_fadeThrough` |
| `/mix/:id` | `MixDetailScreen` | `_slideUp` |
| `/explore/genre` | `GenreScreen` | `_slideUp` |
| `/explore/genres` (opcional) | `GenresScreen` | `_slideUp` |
| `/explore/charts` (opcional) | `ChartsScreen` | `_slideUp` |

Consideraciones:

- `/explore/genre` usa `state.uri.queryParameters['title']` y `['params']`; validar que no estén vacíos.
- Los `params` pueden ser largos; usar `Uri.encodeComponent` al construir la URL.
- `/see-all/:section` debe validar el enum; si es inválido, mostrar un `EmptyState`.
- Mantener las rutas existentes sin cambios.

### 7.7 Hive y persistencia

| Caja | Uso | Cambio |
|---|---|---|
| `favorites` | Favoritos | Sin cambios. |
| `playlists` | Playlists locales | Sin cambios. |
| `history` | Historial de reproducción | Sin cambios. |
| `settings` | Ajustes, historial de búsqueda, offline, calidad | Se sigue usando `searchHistory`. |
| `cache` | `AppCache` (búsquedas, playlists públicas, explore, charts, mixes) | Nuevas claves; misma caja. |
| `downloads` | Descargas + calidad | Sin cambios. |
| `stats` | Estadísticas | Sin cambios. |
| `followedArtists` | Artistas seguidos | **Nueva caja**. |

- Abrir `followedArtists` en `main.dart` y pasarla al repositorio.
- No se necesita migración de datos: Hive es schemaless y las cajas nuevas empiezan vacías.
- El campo opcional `genre` en `SongModel`/`AlbumModel` es compatible con los JSON existentes (si falta, queda `null`).

### 7.8 Dependencias y permisos

| Elemento | Acción |
|---|---|
| `speech_to_text` | Añadir a `pubspec.yaml` (`flutter pub add speech_to_text`). |
| `RECORD_AUDIO` | Añadir permiso en `AndroidManifest.xml`. |
| `queries` de reconocimiento | Añadir si el plugin lo requiere para Android 11+. |
| `connectivity_plus` | Ya existe; se usa para `effectiveOfflineProvider` (opcional). |
| `permission_handler` | Ya existe; se usa para el micrófono. |
| Sin nuevas dependencias de red/backend | No se añaden. |

### 7.9 Archivos a crear/modificar

#### Nuevos

```
lib/core/utils/text_utils.dart
lib/core/utils/search_sort.dart
lib/core/utils/mix_utils.dart
lib/core/services/voice_search_controller.dart
lib/data/models/search_models.dart
lib/data/models/public_playlist_model.dart
lib/data/models/explore_models.dart
lib/data/models/home_models.dart
lib/data/services/search_service.dart
lib/data/services/local_search_service.dart
lib/data/services/explore_service.dart
lib/data/services/daily_mix_service.dart
lib/data/services/lyrics_index_service.dart
lib/data/repositories/followed_artists_repository.dart
lib/providers/search_providers.dart
lib/providers/explore_providers.dart
lib/providers/home_feed_providers.dart
lib/providers/followed_artists_providers.dart
lib/presentation/screens/public_playlist_screen.dart
lib/presentation/screens/see_all_screen.dart
lib/presentation/screens/mix_detail_screen.dart
lib/presentation/screens/genre_screen.dart
lib/presentation/screens/genres_screen.dart          (opcional)
lib/presentation/screens/charts_screen.dart          (opcional)
lib/presentation/widgets/search_header.dart
lib/presentation/widgets/search_tabs.dart
lib/presentation/widgets/search_suggestions_panel.dart
lib/presentation/widgets/search_discovery.dart
lib/presentation/widgets/search_filter_sheet.dart
lib/presentation/widgets/search_active_filters.dart
lib/presentation/widgets/search_empty_state.dart
lib/presentation/widgets/search_selection_bar.dart
lib/presentation/widgets/search_load_more.dart
lib/presentation/widgets/spelling_suggestion_banner.dart
lib/presentation/widgets/lyrics_search_results.dart
lib/presentation/widgets/local_search_field.dart
lib/presentation/widgets/section_header.dart
lib/presentation/widgets/home_section_shell.dart
lib/presentation/widgets/home_carousels.dart
lib/presentation/widgets/mix_card.dart
lib/presentation/widgets/mood_mix_card.dart
lib/presentation/widgets/genre_chips.dart
lib/presentation/widgets/recent_chips_row.dart
lib/presentation/widgets/playlist_picker_sheet.dart
lib/presentation/widgets/song_list_view.dart
lib/presentation/widgets/album_grid_view.dart
lib/presentation/widgets/artist_list_view.dart
lib/presentation/widgets/playlist_grid_view.dart
```

#### Modificados

```
lib/data/services/yt_service.dart
lib/data/services/app_cache.dart
lib/data/models/song_model.dart
lib/data/models/album_model.dart
lib/providers/music_providers.dart
lib/providers/library_providers.dart          (si se añaden derivados)
lib/providers/downloads_providers.dart        (derivados de descargas)
lib/providers/settings_providers.dart         (effectiveOffline)
lib/providers/home_providers.dart             (reutilizar helpers)
lib/presentation/screens/search_screen.dart
lib/presentation/screens/home_screen.dart
lib/presentation/screens/artist_screen.dart
lib/presentation/screens/album_detail_screen.dart
lib/presentation/screens/now_playing_screen.dart
lib/presentation/screens/playlist_detail_screen.dart
lib/presentation/screens/downloads_screen.dart
lib/presentation/widgets/search_bar_widget.dart
lib/presentation/widgets/song_tile.dart
lib/router/app_router.dart
lib/main.dart
lib/core/constants/app_constants.dart
pubspec.yaml
android/app/src/main/AndroidManifest.xml
```

> No se eliminan archivos existentes. Las pantallas/widgets que se extraen se mantienen como wrappers o se reemplazan de forma controlada para no romper imports.

---

## 8. Caché, datos y rendimiento

### 8.1 Capas de caché

El plan usa cuatro capas, de la más rápida a la más lenta:

| Capa | Qué guarda | Dónde | Vida | Uso |
|---|---|---|---|---|
| **L0 · Memoria de servicio** | Respuestas crudas recientes de `YtService` | `Map` en memoria | 3–10 min | Evitar repetir la misma llamada en una sesión. |
| **L1 · Caché persistente** | JSON de búsquedas, playlists públicas, Explore, Charts, mixes | `AppCache` (Hive) | Minutos/días según categoría | Mostrar datos al instante tras reiniciar. |
| **L2 · Datos locales** | Favoritos, playlists, historial, descargas, estadísticas, artistas seguidos | Cajas Hive | Hasta que el usuario borre | Búsqueda offline, Inicio local, seguidos. |
| **L3 · Caché de imágenes** | Portadas/avatares | Caché de Flutter/`AlbumArt` | LRU del framework | Evitar descargas repetidas de imágenes. |
| **L4 · Estado de UI** | Página actual, filtros, selección, scroll | Providers/`PageStorage` | Sesión | Respuesta inmediata sin refetch. |

Reglas:

- **Nunca** se cachean datos sensibles (tokens, contraseñas, audio).
- La caché **nunca** debe romper la app: si el JSON está corrupto, se ignora y se vuelve a pedir.
- Los datos locales del usuario (L2) **no** se eliminan al limpiar la caché de red (L1).
- La caché de red se puede limpiar desde Ajustes sin afectar favoritos, descargas, historial ni playlists.

### 8.2 Claves, TTL y límites

Convención de claves:

```
<categoría>:<versión>:<parámetros normalizados>
```

- `query` normalizada: `trim`, minúsculas, espacios colapsados. Se conservan tildes para la API, pero se usa una versión normalizada para la clave.
- `limit` siempre incluido cuando afecta la respuesta.
- `ignoreSpelling` incluido como `1/0`.
- `country` incluido en Charts/Explore cuando aplica.
- `params` largos de Moods & Genres: hash estable FNV-1a de 64 bits (no `hashCode` de Dart) para evitar claves gigantes.
- Prefijo de versión (`v1`) para poder invalidar todo un grupo si cambia el formato.

| Clave | Contenido | TTL memoria | TTL disco | Máx. entradas |
|---|---|---|---|---|
| `search:all:v1:<q>:<limit>:<ignore>` | Resultado mixto “Todo” | 10 min | 6 h | 120 |
| `search:songs:v1:<q>:<limit>:<ignore>` | Canciones | 10 min | 6 h | 120 |
| `search:albums:v1:<q>:<limit>:<ignore>` | Álbumes | 30 min | 12 h | 80 |
| `search:artists:v1:<q>:<limit>:<ignore>` | Artistas | 30 min | 12 h | 80 |
| `search:playlists:v1:<q>:<limit>:<ignore>` | Playlists públicas | 30 min | 12 h | 80 |
| `search:suggestions:v1:<q>` | Sugerencias | 15 min | 1 día | 100 |
| `publicPlaylist:v1:<id>:<limit>` | Playlist pública + canciones | 30 min | 6 h | 60 |
| `explore:bundle:v1:<country>` | Novedades + Tendencias + Géneros | 12 h | 24 h | 20 |
| `explore:moods:v1` | Categorías completas de Moods & Genres | 7 días | 7 días | 10 |
| `explore:moodPlaylists:v1:<hash>` | Playlists de un género/mood | 24 h | 7 días | 40 |
| `charts:v1:<country>` | Charts por país | 12 h | 24 h | 20 |
| `home:dailyMix:v1:<yyyy-mm-dd>` | 3 Daily Mixes del día | Hasta fin del día | 1 día | 5 |
| `home:because:v1:<seed>:<yyyy-mm-dd>` | “Porque escuchaste…” | 6 h | 24 h | 20 |
| `home:followedReleases:v1:<artistId>` | Releases de un artista seguido | 24 h | 7 días | 50 |
| `lyrics:v1:<videoId>` | Letra de una canción | Según `YtService` | 7 días | Existente |
| `search:history` | Historial de búsquedas local | — | Persistente | 12 |
| `followedArtists` | Artistas seguidos | — | Persistente | Sin límite práctico |

Ajustes recomendados en `AppCache`:

- Subir el máximo global de entradas de 700 a **1000** (o mantener 700 y añadir límites por categoría; la decisión final se valida con el tamaño real).
- Añadir un límite por categoría (tabla anterior) para que una búsqueda grande no expulse datos de Inicio.
- Evicción LRU por `createdAt` cuando se supera el límite.
- Tamaño máximo por entrada: si una playlist pública supera un umbral (por ejemplo, 1 MB de JSON), no se persiste completa; se cachean las primeras 100 canciones y se marca `truncated`.
- No cachear respuestas vacías durante mucho tiempo: TTL corto (5 min) o no cachear, para no fijar un “sin resultados” temporal.

### 8.3 Stale-while-revalidate (SWR)

Comportamiento deseado:

1. El provider intenta leer la entrada de `AppCache`.
2. Si existe y **no** está expirada: se devuelve al instante; opcionalmente se refresca en segundo plano si es una sección de Inicio.
3. Si existe y **está expirada**: se devuelve igualmente (datos “stale”) y se lanza una actualización en segundo plano.
4. Si no existe: se muestra esqueleto y se espera la red.
5. Si la actualización falla: se conservan los datos stale y se muestra un indicador discreto (“Sin actualizar”); no se borra el contenido.
6. En modo offline: no se lanza la actualización; los datos stale son la verdad hasta que vuelva la conexión.

Implementación sugerida:

- Añadir a `AppCache`:
  ```dart
  T? getStale<T>(String key);
  bool isExpired(String key);
  Future<T> getOrLoad<T>(String key, Future<T> Function() load, {Duration ttl});
  void invalidatePrefix(String prefix);
  ```
- `get` actual se mantiene para no romper lo existente.
- Los providers de Inicio usan `getStale` + `getOrLoad`; los de búsqueda pueden usar `get` (si está expirado, es preferible pedir de nuevo por relevancia).
- Un `AsyncValue` con `isRefreshing` permite mostrar un `LinearProgressIndicator` fino sin tapar el contenido.
- **Deduplicación**: si ya hay una actualización en curso para la misma clave, no se lanza otra; se comparte el `Future`.

### 8.4 Paginación y deduplicación

- Tamaño inicial: **20**.
- Incremento: **+20**.
- Límite máximo: **100** por tipo y consulta.
- `hasMore`:
  - Si la respuesta trae menos de `limit` → `false`.
  - Si no hay elementos nuevos tras deduplicar → `false`.
  - Si trae exactamente `limit` → `true` (puede requerir una llamada extra para confirmar el final).
- Deduplicación por ID estable:
  - Canciones: `song.id`.
  - Álbumes: `album.id`.
  - Artistas: `artist.id`.
  - Playlists: `publicPlaylist.id`.
- Orden: se conserva el orden de la API; la deduplicación no reordena.
- Si el usuario cambia de pestaña, el notifier se conserva 2 minutos (`keepAlive`) para no perder la página; luego se libera y la caché evita la latencia.
- Si cambia la consulta, se crea un nuevo notifier y se descarta el anterior; el `requestId` evita aplicar respuestas viejas.
- **Filtros + paginación**: se pagina sobre resultados crudos; la vista filtrada se calcula después. Si la vista queda vacía y `hasMore` es true, se puede auto-cargar una página adicional (máximo 2 intentos) para evitar un falso “sin resultados”.
- **“Todo”** no pagina: muestra los mejores resultados y delega en las pestañas.

### 8.5 Datos locales y offline

- El índice local se construye a partir de:
  - Descargas (`DownloadEntry.song`).
  - Favoritos.
  - Historial.
  - Playlists locales.
- Se deduplica por `song.id`; se conservan las fuentes para los badges.
- Tamaño típico:
  - 500 canciones → índice < 2 MB en memoria.
  - 3.000 canciones → puede llegar a 10–15 MB; construir en isolate si se supera el umbral.
- Invalidación:
  - Al cambiar descargas, favoritos, historial o playlists, el provider del índice se invalida.
  - Para evitar reconstrucciones excesivas durante una descarga en progreso, el índice de descargas se actualiza cuando la descarga termina (no en cada tick de progreso).
- No se persiste el índice; se reconstruye al iniciar. Es más simple y evita datos obsoletos.
- La búsqueda local no hace red y no depende de conectividad.
- Los detalles offline (`localAlbumProvider`, `localArtistProvider`) se derivan del índice; si no hay datos, estado vacío claro.

### 8.6 Orquestación de peticiones

| Escenario | Límite de concurrencia | Estrategia |
|---|---|---|
| “Todo” | 1 | Una sola llamada; las pestañas se piden solo al abrirse. |
| Sugerencias | 1 | Debounce 200 ms; se ignora la respuesta vieja. |
| Pestaña específica | 1 | Una llamada por tipo/consulta/límite. |
| Inicio (secciones remotas) | 3 | Secciones perezosas; como máximo 3 peticiones simultáneas. |
| Daily Mix | 3 | Una semilla por mix; errores aislados. |
| Artistas seguidos | 2 | Chunks de 2; caché por artista. |
| Descargas masivas | La que ya define `DownloadService` | No se cambia. |
| Charts/Explore | 1 cada uno | Se cachean y se comparten. |

Otras reglas:

- **Deduplicación**: mapa de peticiones en vuelo por clave; si llega otra igual, se reutiliza el `Future`.
- **Cancelación lógica**: no se puede cancelar el HTTP del paquete, pero se ignora la respuesta si el `requestId`/consulta ya no es el actual.
- **Reintentos**: 1 reintento para timeout/socket con espera de 500 ms; no reintentar 4xx, autenticación ni “no encontrado”.
- **Timeouts**: búsqueda 12 s; playlist 20 s; Explore/Charts 15 s. Si el paquete ya tiene timeout, se respeta el existente y se envuelve con `timeout` para no colgar la UI.
- **Backoff**: si varias llamadas fallan seguidas, se evita reintentar en bucle; se muestra error y se espera acción del usuario o TTL.
- **Sin polling**: no se refresca Inicio en un temporizador. Solo TTL, pull-to-refresh o cambios locales.

### 8.7 Rendimiento de UI

- **Slivers** en Inicio; no `ListView` con 14 hijos construidos de golpe.
- **Carruseles horizontales** con `ListView.builder`, `itemExtent`/ancho fijo y `cacheExtent` moderado.
- **`RepaintBoundary`** en tarjetas con sombras/gradientes.
- **`const`** en widgets estáticos; `select` de Riverpod para evitar rebuilds globales.
- **Imágenes**:
  - Usar `memCacheWidth`/`cacheWidth` según el tamaño real (tarjeta, carrusel, cabecera).
  - No cargar la imagen de alta resolución en miniaturas.
  - Placeholder y error widget consistentes.
- **Listas**:
  - Evitar `shrinkWrap: true` salvo en listas pequeñas dentro de un `Column`.
  - Evitar anidar scrolls del mismo eje.
  - Para grids dentro de slivers, usar `SliverGrid`.
- **Selección múltiple**:
  - `Set<String>` y `select` por fila; no reconstruir toda la lista al marcar una canción.
- **Animaciones**:
  - Animar solo la primera aparición de una sección; no reanimar en cada rebuild.
  - Respetar `MediaQuery.disableAnimations`.
- **Teclado/scroll**:
  - `resizeToAvoidBottomInset` y `Scrollable.ensureVisible` para el campo de búsqueda.
  - No perder el foco al cambiar de pestaña.
- **Text scaling**: probar con escala 1.3–2.0; usar `maxLines`/`overflow` en títulos de tarjetas.

### 8.8 Presupuestos y métricas

| Métrica | Objetivo |
|---|---|
| Primera pintura de Inicio con caché | < 500 ms |
| Primera pintura de Inicio sin caché | < 2 s (esqueletos inmediatos) |
| “Todo” con caché caliente | < 300 ms |
| “Todo” con red normal | < 1.5 s para el primer contenido |
| Sugerencias | < 300 ms tras el debounce, con red normal |
| Cambio de pestaña de búsqueda | < 100 ms si hay caché |
| Scroll | 60 fps en dispositivo de gama media; sin jank visible |
| Peticiones al abrir Inicio | ≤ 8 en el primer arranque; ≤ 3 en visitas con caché |
| Peticiones de “Todo” | Exactamente 1 |
| Concurrencia máxima | 3 en Inicio; 1 en búsqueda |
| Uso de memoria del índice local | < 20 MB para 3.000 canciones |
| Caché de aciertos en búsquedas repetidas | > 70 % |
| Crashes/errores no controlados | 0 en flujos principales |

Medición:

- `flutter run --profile` + DevTools (Performance, Memory, Network).
- Contar peticiones con logs temporales en `YtService` (modo debug).
- Pruebas en un dispositivo de gama baja si es posible; como mínimo, emulador con perfil.
- No se aceptan optimizaciones que rompan la legibilidad o la arquitectura.

### 8.9 Casos límite y comportamiento definido

| Caso | Comportamiento |
|---|---|
| Consulta vacía o solo espacios | No se busca; se muestra Explorar. |
| Consulta de 1 carácter | Búsqueda local/sugerencias; remota solo desde 2 caracteres. |
| Consulta muy larga | Truncar a 100 caracteres para la API y la caché; mostrar aviso si se recorta. |
| Tildes/emoji/símbolos | Normalización para local; la API recibe la consulta original codificada. |
| Cambio de consulta durante una petición | Se ignora la respuesta anterior (`requestId`). |
| Cambio a offline durante una petición | Se ignora la respuesta remota y se muestran resultados locales. |
| Sin conexión sin modo offline | Fallback local + banner + reintento. |
| Playlist privada/eliminada | Error claro, sin crash; opción de volver. |
| Playlist con IDs `VL`/`OLA` | Normalizar; el paquete maneja OLA; no duplicar prefijos. |
| Resultado duplicado entre top y lista | Deduplicar por ID; el top conserva la prioridad visual. |
| Canción sin artista/portada/año/duración | Mostrar placeholders; filtros de año/duración la excluyen si están activos. |
| Álbum sin año | Se muestra; “Recientes” lo pone al final. |
| Descarga en progreso | El índice local se actualiza al completar; no en cada tick. |
| Calidad desconocida | No coincide con el filtro de calidad; se muestra sin badge. |
| Letra malformada | Se ignora esa entrada; no rompe el índice. |
| Voz denegada o no disponible | Mensaje claro; botón oculto/deshabilitado; búsqueda escrita intacta. |
| Artista seguido sin página | Se omite en releases; no rompe la sección. |
| Más de 10 artistas seguidos | Se muestran 10; “Ver todo” carga el resto de forma perezosa. |
| Cambio de día con la app abierta | Daily Mix se regenera al detectar nueva fecha (o al reabrir Inicio). |
| Caché corrupta | Se ignora la entrada y se vuelve a pedir; se registra en debug. |
| Caché llena | Evicción LRU por categoría; nunca se borran datos locales. |
| Deep link a mix inexistente | Estado “Mezcla no disponible” + volver a Inicio/regenerar. |
| Deep link a playlist pública inexistente | Error + reintento + volver. |
| Pantalla pequeña/landscape | Carruseles y grids adaptativos; sin overflow. |
| Texto grande | Títulos con `maxLines`/`ellipsis`; botones con altura mínima. |
| Contenido explícito | Solo badge informativo; **ninguna** restricción por edad. |

---

## 9. Fases de implementación

### 9.1 Enfoque

La implementación se divide en fases pequeñas y verificables. Cada fase debe dejar la app **funcionando y desplegable**, sin dependender de que la siguiente esté terminada. Las fases de Buscador y de Inicio comparten la fase 0, pero después pueden ejecutarse en paralelo si hay más de una persona.

Principios de entrega:

- No hacer un “big bang” de toda la pantalla de búsqueda en un solo cambio.
- Mantener las funcionalidades existentes mientras se construyen las nuevas.
- Añadir pruebas en la misma fase que la funcionalidad.
- Medir rendimiento antes/después en los flujos principales.
- Usar `FeatureFlags` solo para lo riesgoso (voz, letras, artistas seguidos), no para todo.

### 9.2 Tabla de fases

| Fase | Nombre | Alcance principal | Depende de | Esfuerzo orientativo | Salida |
|---|---|---|---|---|---|
| **0** | Fundaciones | Modelos, utilidades, interfaces, caché SWR, fixtures de test | — | S/M (2–4 días) | Base técnica sin cambios visibles. |
| **1A** | Buscador núcleo | “Todo”, playlists públicas, paginación, sugerencias, borrado individual, estado vacío | 0 | L (6–9 días) | Buscador nuevo usable. |
| **1B** | Buscador offline + filtros | Filtros, índice local, offline real, fallback de álbum/artista | 1A | L (5–8 días) | Búsqueda offline y filtros completos. |
| **2** | Buscador avanzado | Orden, tendencias/géneros, búsqueda en cola, letras, acciones masivas, erratas | 1B | L (6–9 días) | Buscador completo según la solicitud. |
| **3** | Inicio base | Slivers, secciones independientes, “Ver todo”, offline/caché, refresco | 0 | M (3–5 días) | Estructura nueva de Inicio. |
| **4** | Inicio contenido alto | Daily Mix, Novedades, Charts, Géneros, Porque escuchaste, Redescubre, Top artistas | 1A (playlists públicas), 3 | L (7–10 días) | Inicio personalizado y completo. |
| **5** | Inicio medio/bajo + voz | Seguir artistas, mezclas de ánimo, chips recientes, búsqueda por voz, pulido | 2, 4 | L (5–8 días) | Todas las mejoras solicitadas. |
| **6** | QA y release | Pruebas completas, rendimiento, accesibilidad, build, documentación | Todas | M (3–5 días) | Versión lista para publicar. |

> Los tiempos son orientativos para una persona; no incluyen diseño visual detallado ni revisión de tienda. La fase 6 puede solaparse con las anteriores si se prueba de forma continua.

### 9.3 Fase 0 — Fundaciones

**Objetivo:** dejar listas las piezas compartidas para que las fases de UI no dupliquen lógica.

Tareas:

- [ ] Crear `lib/core/utils/text_utils.dart` con `normalize`, `tokenize`, `levenshtein`, `similarity`, `stableHash`.
- [ ] Crear `lib/core/utils/search_sort.dart` con las funciones de orden.
- [ ] Crear `lib/core/utils/mix_utils.dart` con deduplicación, intercalado, equilibrio y shuffle determinista.
- [ ] Crear `lib/data/models/search_models.dart` con `SearchFilters`, `SearchScope`, `DurationRange`, `YearRange`, `DownloadQualityFilter`, `SearchSort`, `SearchAllResult`, `SearchTopResult`, `SearchSuggestion`, `SearchPageState`.
- [ ] Crear `lib/data/models/public_playlist_model.dart`.
- [ ] Crear `lib/data/models/explore_models.dart`.
- [ ] Crear `lib/data/models/home_models.dart`.
- [ ] Añadir `String? genre` opcional a `SongModel` y `AlbumModel` (compatible con JSON existente).
- [ ] Extender `AppCache` con `getStale`, `isExpired`, `getOrLoad`, `invalidatePrefix` y límites por categoría.
- [ ] Definir `SearchDataSource` y `ExploreDataSource`; hacer que `YtService` las implemente.
- [ ] Crear fixtures JSON de respuestas de búsqueda mixta, playlist pública, Explore, Charts, moods y letras.
- [ ] Añadir pruebas unitarias de utilidades y modelos.
- [ ] Verificar `flutter analyze` y `flutter test`.

**Salida:** sin cambios visibles en la UI; base técnica estable.

### 9.4 Fase 1A — Buscador núcleo

**Objetivo:** que el usuario pueda buscar con “Todo”, playlists públicas, paginación, sugerencias y un estado vacío útil.

Tareas:

- [ ] `YtService.searchAll` + `SearchAllResult.fromRaw`.
- [ ] `YtService.searchPlaylists` + `YtService.getPublicPlaylist`.
- [ ] `SearchService` con búsqueda mixta/filtrada, normalización y `ignoreSpelling`.
- [ ] Providers `searchAllProvider`, `searchPlaylistsProvider`, `publicPlaylistProvider`.
- [ ] `SearchPageNotifier<T>` y providers paginados para canciones, álbumes, artistas y playlists.
- [ ] `SearchHistoryNotifier` con borrado individual y “Deshacer”.
- [ ] `YtService.getSearchSuggestions` + `SearchSuggestionsPanel`.
- [ ] Reestructurar `SearchScreen` en header, tabs, descubrimiento, resultados y estados vacíos.
- [ ] Nueva pestaña “Todo” con mejor resultado y secciones.
- [ ] Nueva pestaña “Playlists” y pantalla `PublicPlaylistScreen`.
- [ ] Ruta `/public-playlist/:id`.
- [ ] Estado vacío contextual base (sin ortografía todavía).
- [ ] Pruebas unitarias de parseo y paginación.
- [ ] Pruebas de widget de “Todo”, playlists, sugerencias y vacío.

**Salida:** buscador nuevo usable; filtros y offline aún no.

### 9.5 Fase 1B — Buscador offline + filtros

**Objetivo:** completar los requisitos de alta prioridad que faltan: filtros y búsqueda offline real.

Tareas:

- [ ] `SearchFilters` + `SearchFiltersNotifier`.
- [ ] Providers derivados de descargas (`downloadedSongIds`, `downloadedAlbumIds`, `downloadedArtistIds`, `downloadQualityById`).
- [ ] `SearchFilterSheet` con ámbito, solo descargados, duración, año, género y calidad.
- [ ] Chips de filtros activos y contador de resultados.
- [ ] Aplicación de filtros en memoria + auto-carga de páginas si la vista queda vacía.
- [ ] `effectiveOfflineProvider` (modo manual + conectividad opcional).
- [ ] `LocalSearchService` + `LocalSearchIndex`.
- [ ] `offlineSearchProvider`, `localAlbumProvider`, `localArtistProvider`.
- [ ] `SearchScreen` sin bloqueo offline; banner y resultados locales.
- [ ] Fallback offline en `AlbumDetailScreen` y `ArtistScreen`.
- [ ] Pruebas unitarias de filtros, ranking local y normalización.
- [ ] Pruebas de widget de filtros y offline.

**Salida:** búsqueda offline real y filtros completos.

### 9.6 Fase 2 — Buscador avanzado

**Objetivo:** completar las mejoras medias y bajas del Buscador (excepto voz).

Tareas:

- [ ] `SearchSort` + selector de orden en el sheet/filtros.
- [ ] Orden aplicado en providers derivados.
- [ ] `ExploreService` + `ExploreBundle`.
- [ ] `SearchDiscovery` con tendencias y géneros.
- [ ] `GenreScreen` y ruta `/explore/genre`.
- [ ] Búsqueda dentro de playlist y descargas mejorada con `LocalSearchField`.
- [ ] Búsqueda dentro de la cola (`NowPlayingScreen`), con índices originales.
- [ ] `LyricsIndexService`, ámbito “Letras”, indexación de descargas y resultados con snippet.
- [ ] `SearchSelectionNotifier` + `SongTile` con selección + `SearchSelectionBar`.
- [ ] Acciones masivas: reproducir, cola, playlist, descargar, favorito, eliminar descarga.
- [ ] Corrección de erratas: `levenshtein`, banner y `ignoreSpelling`.
- [ ] Pruebas unitarias de orden, Explore, letras, selección y erratas.
- [ ] Pruebas de widget de acciones masivas y búsqueda en cola.

**Salida:** Buscador completo salvo voz, con todas las mejoras medias/bajas.

### 9.7 Fase 3 — Inicio base

**Objetivo:** preparar la estructura de Inicio para que las secciones nuevas se integren sin romper el rendimiento.

Tareas:

- [ ] Migrar `HomeScreen` a `CustomScrollView` + `SliverList.builder`.
- [ ] Crear `HomeSectionDescriptor`, `HomeSectionShell`, `SectionHeader`.
- [ ] Lista de secciones con builders perezosos.
- [ ] Integrar las secciones existentes (continuar, para ti, spotlight, álbumes recientes, playlists, favoritos) en la nueva estructura.
- [ ] `SectionHeader` con “Ver todo” condicional.
- [ ] `SeeAllScreen` + ruta `/see-all/:section` + enum.
- [ ] Extraer/reutilizar `SongListView`, `AlbumGridView`, `ArtistListView`, `PlaylistGridView`.
- [ ] Estrategia de refresco: `RefreshIndicator`, invalidación selectiva, sin invalidar todo al cambiar de pestaña.
- [ ] Caché primero: `getStale` + refresco en segundo plano en secciones remotas.
- [ ] Manejo offline: banner, secciones locales, ocultar remotas sin caché.
- [ ] Pruebas de widget de secciones independientes, error aislado y offline.
- [ ] Medir scroll y peticiones antes/después.

**Salida:** Inicio modular y rápido, listo para nuevas secciones.

### 9.8 Fase 4 — Inicio contenido de prioridad alta

**Objetivo:** añadir las secciones que el usuario pidió como altas.

Tareas:

- [ ] `DailyMixService` + `DailyMix` + `MixCard` + `MixDetailScreen` + ruta `/mix/:id`.
- [ ] `exploreBundleProvider` + `newReleasesProvider` + sección Novedades.
- [ ] `chartsProvider` + sección Tendencias & Charts.
- [ ] `genresProvider` + `GenreScreen` + sección Géneros.
- [ ] `becauseYouListenedProvider` + sección “Porque escuchaste…”.
- [ ] `rediscoverProvider` + sección Redescubre.
- [ ] `topArtistsProvider` + sección Top artistas.
- [ ] “Ver todo” para todas las secciones nuevas.
- [ ] Pruebas unitarias de Daily Mix (determinismo, duplicados, offline).
- [ ] Pruebas de widget de cada sección y de “Ver todo”.
- [ ] Pruebas de caché compartida de Explore.

**Salida:** Inicio con todas las secciones altas.

### 9.9 Fase 5 — Inicio medio/bajo + voz

**Objetivo:** completar seguidos, mezclas de ánimo, chips recientes y búsqueda por voz.

Tareas:

- [ ] Caja Hive `followedArtists` + `FollowedArtist` + repository + providers.
- [ ] Botón Seguir/Siguiendo en `ArtistScreen` y en resultados de artistas.
- [ ] `followedReleasesProvider` + sección “Nuevo de artistas que sigues” + “Ver todo”.
- [ ] `moodMixesProvider` + `MoodMixCard` + sección de mezclas de ánimo/actividad.
- [ ] `recentChipsProvider` + `RecentChipsRow` en Inicio.
- [ ] Dependencia `speech_to_text` + permiso `RECORD_AUDIO`.
- [ ] `VoiceSearchController` + botón de micrófono + estados/errores.
- [ ] Pulido de accesibilidad, textos, tooltips y estados vacíos.
- [ ] Pruebas de seguidos, mood mixes, chips y voz (con fake).
- [ ] Pruebas manuales de permisos de micrófono.

**Salida:** todas las mejoras solicitadas implementadas.

### 9.10 Fase 6 — QA y release

**Objetivo:** validar que todo funciona junto y que no hay regresiones.

Tareas:

- [ ] Ejecutar la matriz de pruebas completa (sección 10).
- [ ] Revisar rendimiento en perfil: scroll, búsqueda, caché, memoria.
- [ ] Revisar accesibilidad con text scaling y lector de pantalla.
- [ ] Revisar modo offline en todas las pantallas nuevas.
- [ ] Verificar que no se reintrodujeron restricciones por edad.
- [ ] Revisar logs de errores y peticiones duplicadas.
- [ ] Actualizar documentación interna y este plan con desviaciones.
- [ ] `flutter analyze`, `flutter test`, `flutter build apk --release`.
- [ ] Prueba de instalación limpia y actualización desde la versión anterior.
- [ ] Prueba en dispositivo de gama baja/media.
- [ ] Tag/versión y notas de release.

**Salida:** versión lista para publicar.

### 9.11 Dependencias y paralelización

```text
Fase 0
  ├── Fase 1A ── Fase 1B ── Fase 2 ──────────────┐
  │                                                ├── Fase 5 ── Fase 6
  └── Fase 3 ── Fase 4 ────────────────────────────┘
```

- La fase 3 puede empezar en paralelo con 1B si hay dos desarrolladores.
- La fase 4 depende de la fase 1A por `PublicPlaylistScreen`/`PublicPlaylistModel` y de la fase 3 por la estructura.
- La fase 5 depende de 2 (voz/acciones) y 4 (Inicio).
- La fase 6 depende de todas.
- Si solo hay una persona, el orden recomendado es **0 → 1A → 1B → 2 → 3 → 4 → 5 → 6**. Si se quiere entregar valor antes, se puede hacer **0 → 1A → 1B → 3 → 4 → 2 → 5 → 6**, dejando las mejoras medias del Buscador para después de las altas de Inicio.

### 9.12 Feature flags recomendados

Para reducir riesgo, usar constantes en `app_constants.dart`:

```dart
const bool kEnableSearchV2 = true;
const bool kEnableHomeV2 = true;
const bool kEnableVoiceSearch = true;
const bool kEnableLyricsSearch = true;
const bool kEnableFollowedArtists = true;
```

- Si una función falla en producción, se puede desactivar sin revertir toda la app.
- Los flags deben evaluarse en el punto de entrada de la sección/pantalla, no dentro de cada widget.
- No se usan para esconder código incompleto de forma permanente; se eliminan o se consolidan al final.

---

## 10. Plan de pruebas y QA

### 10.1 Estrategia

Se combinan tres niveles:

1. **Unitarias**: lógica pura (filtros, orden, ranking, parseo, paginación, mixes, normalización, similitud).
2. **Widget**: pantallas y estados (carga, error, vacío, offline, selección, filtros, secciones de Inicio).
3. **Integración/manual**: flujos completos en dispositivo/emulador, permisos, red real, modo avión, rendimiento.

Reglas:

- Cada fase añade pruebas de lo que implementa.
- Las pruebas no dependen de red; se inyectan fakes.
- Los fixtures JSON se guardan en `test/fixtures/` y se reutilizan.
- Las pruebas de rendimiento son manuales con DevTools, no en CI.
- Ninguna prueba debe requerir una cuenta real de YouTube Music para lo básico.

### 10.2 Pruebas unitarias

| Módulo | Casos mínimos |
|---|---|
| `TextUtils.normalize` | Mayúsculas, tildes, `ñ`, puntuación, espacios múltiples, emojis, cadena vacía. |
| `TextUtils.tokenize` | Varios tokens, tokens de 1 carácter, signos, duplicados. |
| `TextUtils.levenshtein/similarity` | Palabras iguales, una letra de diferencia, palabras largas, umbral. |
| `SearchFilters` | `onlyDownloaded`, duración (bordes), año (bordes), calidad, combinaciones, `activeCount`, `isEmpty`. |
| `SearchFilters.matchesSong` | Canción sin duración/año, descargada, favorita, con género. |
| `SearchFilters.matchesAlbum/Artist` | IDs de descargas, año ausente, artista con múltiples IDs. |
| `SearchSort` | Relevancia, duración asc/desc con nulos al final, A-Z con tildes, recientes con año nulo, popularidad local/charts. |
| `SearchPageNotifier` | Carga inicial, loadMore, deduplicación, `hasMore` con menos/igual/más, error conserva items, requestId descarta respuesta vieja, límite máximo. |
| `SearchAllResult.fromRaw` | Agrupación por `resultType`, top result duplicado, tipos ignorados, listas vacías, thumbnails ausentes. |
| `PublicPlaylistModel.fromJson` | `author` String/Map/List, `itemCount`/`count`, `browseId` con VL, `playlistId`, thumbnails, campos nulos. |
| `PublicPlaylistPage` | Tracks válidos, tracks sin videoId, tracks no reproducibles, header vacío. |
| `LocalSearchService` | Búsqueda por título/artista/álbum, tildes, tokens AND, ranking, deduplicación por ID, fuentes múltiples, playlists. |
| `LocalSearchIndex` | Construcción desde descargas/favoritos/historial/playlists, invalidación, artista/álbum derivados. |
| `ExploreService` | Parseo de `new_releases`, `trending`, `moods_and_genres`, `top_songs` ausente, charts con países. |
| `DailyMixService` | 3 mixes, 20–25 canciones, sin duplicados, determinismo por día, offline, seeds insuficientes, error de una semilla. |
| `MixUtils` | Intercalado, límite por artista/álbum, deduplicación, shuffle determinista. |
| `BecauseYouListened` | Selección de artista vs canción, exclusión de historial, fallback si una llamada falla. |
| `Rediscover` | Filtro > 30 días, `lastPlayed` nulo, orden por plays/seconds, fallback favoritos. |
| `TopArtist` | Mapeo nombre→ID/imagen, artistas sin ID, enriquecimiento opcional. |
| `FollowedArtistsRepository` | Toggle, persistencia, `isFollowing`, lista vacía, duplicados. |
| `FollowedReleases` | Filtro por año, sin año, deduplicación, error aislado, límite 10. |
| `LyricsIndexService` | Parseo de letras, normalización, búsqueda AND/OR, snippet, letra malformada, índice vacío. |
| `Cache` | `getStale`, `isExpired`, `getOrLoad`, corrupción, evicción, claves largas/hash. |
| `VoiceSearchController` | Fake de `SpeechToText`: disponible, denegado, error, resultado parcial/final, stop. |

### 10.3 Pruebas de widget

| Pantalla/Widget | Casos |
|---|---|
| `SearchScreen` | Estado inicial con historial; query con “Todo”; cambio de pestaña; loading; error; sin resultados; offline; filtros activos; borrar historial individual; undo. |
| `SearchAllView` | Secciones visibles/ocultas según datos; top result; “Ver todo” cambia de pestaña. |
| `SearchSuggestionsPanel` | Sugerencias remotas + historial; tap rellena/busca; error no rompe; offline solo historial. |
| `SearchFilterSheet` | Abrir/cerrar; seleccionar filtros; aplicar; limpiar; badge; opciones deshabilitadas por pestaña. |
| `SearchEmptyState` | Cada variante (remoto, filtros, offline, error, letras). |
| `SearchSelectionBar` | Entrar/salir de selección; contador; acciones llamadas con los IDs correctos. |
| `SongTile` | Comportamiento normal intacto; modo selección; long-press; menú. |
| `PublicPlaylistScreen` | Loading/error/data; play all; guardar en biblioteca; descargar; buscador interno. |
| `HomeScreen` | Secciones independientes; una falla y las demás siguen; offline; “Ver todo”; refresco. |
| `DailyMix` | Tarjetas, play, detalle, guardar, descargar. |
| `NewReleases/Charts/Genres` | Render con datos, vacío y error; navegación. |
| `BecauseYouListened/Rediscover/TopArtists` | Render, títulos, “Ver todo”, tap. |
| `FollowedReleases` | CTA sin seguidos, lista con seguidos, seguimiento desde artista. |
| `MoodMixes` | Tarjetas, tap a género/fallback. |
| `RecentChips` | Tap reproduce, vacío oculta. |
| `SeeAllScreen` | Cada sección; título correcto; paginación; ruta inválida. |
| `QueueSearch` | Filtrar, reproducir, quitar, limpiar, no reordenar filtrado. |
| `LyricsSearch` | Vacío/indexando/resultados; snippet. |
| `LocalSearchField` | Escribir/limpiar; no pierde foco. |

### 10.4 Pruebas de integración y manuales

Matriz mínima:

| Escenario | Pasos | Resultado esperado |
|---|---|---|
| Búsqueda “Todo” | Buscar un artista conocido | Una llamada, top result + secciones; “Ver todo” funciona. |
| Playlist pública | Buscar playlist, abrir, reproducir, guardar, descargar | Todo funciona; playlist local creada. |
| Filtros | Activar solo descargados + duración + año | Resultados coherentes; chips; quitar filtros. |
| Offline manual | Activar offline, buscar | Resultados locales, sin bloqueo, sin red. |
| Modo avión sin offline | Buscar | Fallback local + banner + reintento. |
| Album/artista offline | Abrir desde resultado local | Detalle local o vacío claro; sin error de red. |
| Paginación | Cargar más en canciones/álbumes/artistas/playlists | Sin duplicados, sin pérdida de scroll. |
| Autocompletado | Escribir rápido | Sin parpadeos; respuesta final correcta. |
| Borrar búsqueda | Borrar una, deshacer, borrar todo | Persistencia correcta. |
| Voz | Permitir/denegar micrófono | Texto o mensaje claro; sin crash. |
| Erratas | Buscar palabra mal escrita sin resultados | “Quizás quisiste decir” + “Buscar de todos modos”. |
| Acciones masivas | Seleccionar varias, cola/playlist/descargar | Acciones correctas; progreso; sin romper la cola. |
| Buscar en cola | Filtrar y quitar/reproducir | Índices originales correctos. |
| Letras | Indexar descargas, buscar frase | Resultados con snippet; sin red durante búsqueda. |
| Inicio Daily Mix | Abrir Inicio dos veces el mismo día | Mismas mezclas; segunda vez sin red. |
| Inicio secciones | Scroll hasta abajo | Secciones cargan al acercarse; sin jank. |
| Inicio offline | Activar offline | Secciones locales/cacheadas; sin errores. |
| Seguir artista | Seguir, reiniciar, ver novedades | Persistencia; releases; “Ver todo”. |
| Mood mixes | Abrir Enfoque/Gym/Chill | Género o fallback con resultados. |
| Chips recientes | Tocar chip | Reproduce con cola de recientes. |
| Pantalla pequeña | Texto grande/landscape | Sin overflow; botones accesibles. |
| Regresión | Reproducir, cola, favoritos, descargas, playlists, letras | Sin cambios negativos. |
| Edad | Revisar contenido explícito | Solo badge; ninguna restricción. |

### 10.5 Infraestructura de pruebas

- **Fakes**:
  - `FakeSearchDataSource`: devuelve fixtures y permite simular delays/errores.
  - `FakeExploreDataSource`.
  - `FakeYtService` para letras/relacionados.
  - `FakeSpeechToText` para voz.
  - `FakeAppCache` o una instancia en memoria.
- **Fixtures**:
  - `search_all_basic.json`.
  - `search_songs_page.json`.
  - `search_albums_page.json`.
  - `search_artists_page.json`.
  - `search_playlists_page.json`.
  - `public_playlist_community.json`, `public_playlist_ola.json`, `public_playlist_featured.json`.
  - `explore_basic.json`, `explore_no_premium.json`.
  - `charts_us.json`, `charts_zz.json`.
  - `mood_categories.json`, `mood_playlists.json`.
  - `lyrics_basic.json`, `lyrics_malformed.json`.
  - `artist_page_with_releases.json`, `artist_page_error.json`.
- **Sembrados**:
  - Descargas: 5 canciones de 2 álbumes/artistas, calidades high/medium/low.
  - Favoritos: 10 canciones.
  - Historial: 20 canciones con `lastPlayed` variados.
  - Playlists: 3 locales con nombres y canciones.
  - Estadísticas: top songs/artists con plays/seconds.
- **Aislamiento**:
  - Cada test usa un `ProviderContainer`/`ProviderScope` con overrides.
  - No usar Hive real en unit/widget; usar repositorios fake o `Hive.init` con temp dir si es necesario.
  - Limpiar timers/debounces con `tester.pump` y `fakeAsync` cuando aplique.

### 10.6 Comandos

```bash
flutter pub get
flutter analyze
flutter test
flutter test test/unit
flutter test test/widget
flutter test --coverage
flutter build apk --release
```

Pruebas manuales:

```bash
flutter run --profile
flutter run --release
```

### 10.7 Checklist de regresión

- [ ] La reproducción de una canción desde búsqueda, Inicio, playlist, descargas y favoritos sigue funcionando.
- [ ] La cola se puede abrir, reordenar (sin búsqueda), saltar y eliminar.
- [ ] Las descargas individuales y masivas siguen funcionando, con progreso y cancelación.
- [ ] Los favoritos se añaden/quitan y persisten.
- [ ] Las playlists locales se crean, renombran, actualizan y eliminan.
- [ ] El historial se registra y se muestra.
- [ ] Las letras existentes se abren y se sincronizan como antes.
- [ ] El modo offline existente sigue afectando a las pantallas que ya lo usaban.
- [ ] La configuración de calidad de audio no cambia inesperadamente.
- [ ] El tema claro/oscuro y el diseño no se rompen.
- [ ] No se reintroducen restricciones por edad.
- [ ] No hay nuevas excepciones no capturadas en los flujos principales.

<!-- CONTINUAR: PARTE 10 -->








