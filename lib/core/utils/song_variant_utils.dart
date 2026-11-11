import '../../data/models/song_model.dart';
import 'text_utils.dart';

/// Palabras que aparecen en títulos derivados: covers, versiones de guitarra,
/// acústicos, remixes, audios 8D, etc. Se usan para comparar canciones por su
/// tema base y evitar que la cola repita la misma canción con otro intérprete.
const Set<String> _variantSegmentTokens = {
  'acapella',
  'acappella',
  'acoustic',
  'acustica',
  'acustico',
  'audio',
  'aleman',
  'anniversary',
  'aniversario',
  'bass',
  'boosted',
  'bootleg',
  'bonus',
  'cappella',
  'chipmunk',
  'clean',
  'club',
  'coreano',
  'cover',
  'covers',
  'cuarteto',
  'cuerdas',
  'daycore',
  'deluxe',
  'demo',
  'dirty',
  'direct',
  'directo',
  'dub',
  'edit',
  'english',
  'espanol',
  'espanola',
  'especial',
  'explicit',
  'extended',
  'film',
  'frances',
  'french',
  'german',
  'guitar',
  'guitarra',
  'hd',
  'hq',
  'instrumental',
  'italian',
  'italiano',
  'japanese',
  'japones',
  'karaoke',
  'korean',
  'letra',
  'live',
  'lofi',
  'lyric',
  'lyrics',
  'mashup',
  'mix',
  'mixes',
  'mono',
  'movie',
  'nightcore',
  'official',
  'oficial',
  'orchestral',
  'orquesta',
  'orquestal',
  'original',
  'parody',
  'pelicula',
  'piano',
  'pitch',
  'portugues',
  'portuguese',
  'quartet',
  'radio',
  'remaster',
  'remastered',
  'remasterizada',
  'remasterizado',
  'remix',
  'remixes',
  'remixed',
  'reverb',
  'russian',
  'ruso',
  'sax',
  'saxophone',
  'session',
  'sessions',
  'shifted',
  'sinfonico',
  'sonora',
  'soundtrack',
  'spanish',
  'special',
  'speed',
  'sped',
  'spedup',
  'stereo',
  'stripped',
  'strings',
  'subtitulada',
  'subtitulado',
  'symphonic',
  'trailer',
  'traducida',
  'traducido',
  'tribute',
  'unplugged',
  'version',
  'video',
  'violin',
  'vivo',
  'visualiser',
  'visualizer',
  '4k',
  '8d',
};

const Set<String> _featureTokens = {
  'feat',
  'featuring',
  'ft',
  'prod',
  'produced',
};

/// Variantes que se escriben con dos palabras y no se detectan bien mirando
/// solo el último token.
const Set<String> _variantPairs = {
  '8 bit',
  'bass boost',
  'day core',
  'lo fi',
  'night core',
  'pitch shift',
  'speed up',
  'sped up',
};

/// Convierte un título en una clave comparable. Elimina el contenido entre
/// paréntesis/corchetes y los sufijos habituales de versiones para que
/// "Payphone", "Payphone (feat. Wiz Khalifa)" y "Payphone - Guitar Cover"
/// compartan la misma clave.
String songTitleKey(String title) {
  if (title.trim().isEmpty) return '';
  var value = title.replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ');
  final segments = value.split(RegExp(r'\s+[-–—|]\s+'));
  final kept = <String>[];
  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index].trim();
    if (segment.isEmpty) continue;
    // El primer segmento es el título principal; aunque contenga palabras como
    // "live" no se descarta (por ejemplo, "Live and Let Die").
    if (index > 0 && _looksLikeVariantSegment(segment)) continue;
    kept.add(segment);
  }
  if (kept.isEmpty) kept.add(value);

  var tokens = tokenize(kept.join(' '));
  for (var index = 1; index < tokens.length; index++) {
    if (_featureTokens.contains(tokens[index])) {
      tokens = tokens.sublist(0, index);
      break;
    }
  }
  for (var index = tokens.length - 2; index >= 0; index--) {
    if (tokens.length <= 2) break;
    final pair = '${tokens[index]} ${tokens[index + 1]}';
    if (_variantPairs.contains(pair)) {
      tokens.removeRange(index, index + 2);
    }
  }
  while (tokens.length > 1 && _variantSegmentTokens.contains(tokens.last)) {
    tokens.removeLast();
  }
  return tokens.join(' ');
}

bool _looksLikeVariantSegment(String segment) {
  final normalized = normalize(segment);
  if (normalized.contains('lo fi') ||
      normalized.contains('lofi') ||
      normalized.contains('8 bit') ||
      normalized.contains('8bit')) {
    return true;
  }
  return tokenize(normalized).any(_variantSegmentTokens.contains);
}

/// Compara dos títulos usando su tema base, sin importar el artista.
bool isSameSongTitle(String a, String b) {
  final left = songTitleKey(a);
  final right = songTitleKey(b);
  return left.isNotEmpty && left == right;
}

/// Detecta si [candidate] es una versión/cover de [reference].
///
/// Además del título base, cubre casos como "Payphone - Boyce Avenue" cuando
/// el nombre del artista aparece dentro del título.
bool isSameSongVariant(SongModel candidate, SongModel reference) {
  if (candidate.id.isNotEmpty && candidate.id == reference.id) return false;
  final candidateKey = songTitleKey(candidate.title);
  final referenceKey = songTitleKey(reference.title);
  if (candidateKey.isEmpty || referenceKey.isEmpty) return false;
  if (candidateKey == referenceKey) return true;

  final artistKeys = <String>{
    ...candidate.artists.map(normalize),
    ...reference.artists.map(normalize),
  }.where((key) => key.isNotEmpty).toSet();

  for (final artistKey in artistKeys) {
    if (candidateKey == '$referenceKey $artistKey' ||
        candidateKey == '$artistKey $referenceKey') {
      return true;
    }
  }

  // Covers que incluyen al artista original dentro del título:
  // "Payphone - Maroon 5 (Boyce Avenue cover)" termina como
  // "payphone maroon 5" y debe seguir siendo la misma canción.
  bool hasArtistSuffix(String rest) => artistKeys.any(
    (artistKey) =>
        rest == artistKey ||
        rest.startsWith('$artistKey ') ||
        rest.endsWith(' $artistKey') ||
        rest.contains(' $artistKey '),
  );
  if (candidateKey.startsWith('$referenceKey ')) {
    final rest = candidateKey.substring(referenceKey.length + 1);
    if (hasArtistSuffix(rest)) return true;
  }
  if (candidateKey.endsWith(' $referenceKey')) {
    final rest = candidateKey.substring(
      0,
      candidateKey.length - referenceKey.length - 1,
    );
    if (hasArtistSuffix(rest)) return true;
  }
  return false;
}

/// Filtra canciones repetidas por id y por tema base, conservando el orden.
///
/// [reference] permite descartar covers y versiones de la canción actual que
/// hayan llegado con un título ligeramente distinto.
List<SongModel> filterSongVariants(
  Iterable<SongModel> songs, {
  Set<String> excludeIds = const {},
  Set<String> excludeTitleKeys = const {},
  SongModel? reference,
  int? limit,
}) {
  final seenIds = <String>{...excludeIds};
  final seenTitles = <String>{...excludeTitleKeys};
  if (reference != null) {
    if (reference.id.isNotEmpty) seenIds.add(reference.id);
    final referenceKey = songTitleKey(reference.title);
    if (referenceKey.isNotEmpty) seenTitles.add(referenceKey);
  }

  final result = <SongModel>[];
  for (final song in songs) {
    if (limit != null && result.length >= limit) break;
    if (song.id.isEmpty || !seenIds.add(song.id)) continue;
    final titleKey = songTitleKey(song.title);
    if (titleKey.isEmpty || !seenTitles.add(titleKey)) continue;
    if (reference != null && isSameSongVariant(song, reference)) continue;
    result.add(song);
  }
  return result;
}
