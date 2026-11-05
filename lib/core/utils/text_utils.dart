/// Utilidades de texto compartidas por la búsqueda local, el orden y las
/// sugerencias. Todo es puro y no toca red ni disco para poder usarse en
/// cualquier provider o widget sin efectos secundarios.
library;

const Map<String, String> _diacritics = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ý': 'y',
  'ÿ': 'y',
  'ø': 'o',
  'æ': 'ae',
  'œ': 'oe',
  'ß': 'ss',
};

/// Minúsculas, sin tildes, sin puntuación y con espacios colapsados.
String normalize(String input) {
  if (input.isEmpty) return '';
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final replacement = _diacritics[char];
    if (replacement != null) {
      buffer.write(replacement);
    } else if (RegExp(r'[a-z0-9]').hasMatch(char)) {
      buffer.write(char);
    } else {
      buffer.write(' ');
    }
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Tokens de la consulta, ignorando vacíos.
List<String> tokenize(String input) {
  final normalized = normalize(input);
  if (normalized.isEmpty) return const [];
  return normalized.split(' ').where((token) => token.isNotEmpty).toList();
}

bool containsNormalized(String haystack, String needle) {
  if (needle.isEmpty) return true;
  return normalize(haystack).contains(normalize(needle));
}

/// Distancia de Levenshtein con dos filas para no reservar matrices grandes.
int levenshtein(String a, String b) {
  final left = normalize(a);
  final right = normalize(b);
  if (left.isEmpty) return right.length;
  if (right.isEmpty) return left.length;
  if (left == right) return 0;
  var previous = List<int>.generate(right.length + 1, (index) => index);
  var current = List<int>.filled(right.length + 1, 0);
  for (var i = 1; i <= left.length; i++) {
    current[0] = i;
    for (var j = 1; j <= right.length; j++) {
      final cost = left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1;
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + cost;
      var best = deletion < insertion ? deletion : insertion;
      if (substitution < best) best = substitution;
      current[j] = best;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[right.length];
}

/// Similitud normalizada entre 0 y 1.
double similarity(String a, String b) {
  final left = normalize(a);
  final right = normalize(b);
  final maxLength = left.length > right.length ? left.length : right.length;
  if (maxLength == 0) return 1;
  return 1 - levenshtein(left, right) / maxLength;
}

/// Fragmento de una línea con la coincidencia centrada y sin cortar palabras
/// de forma agresiva. Se usa en los resultados de búsqueda por letra.
String snippetAround(String line, String query, {int radius = 48}) {
  final normalizedLine = normalize(line);
  final normalizedQuery = normalize(query);
  if (normalizedQuery.isEmpty) {
    return line.length <= radius * 2
        ? line
        : '${line.substring(0, radius * 2)}…';
  }
  final index = normalizedLine.indexOf(normalizedQuery);
  if (index < 0) {
    return line.length <= radius * 2
        ? line
        : '${line.substring(0, radius * 2)}…';
  }
  // normalize() puede cambiar la longitud; aproximamos con el índice y
  // recortamos sobre la línea original de forma segura.
  final start = (index - radius).clamp(0, line.length);
  final end = (index + query.length + radius).clamp(0, line.length);
  final prefix = start > 0 ? '…' : '';
  final suffix = end < line.length ? '…' : '';
  return '$prefix${line.substring(start, end).trim()}$suffix';
}
