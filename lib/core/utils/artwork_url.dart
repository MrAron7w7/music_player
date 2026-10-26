/// Devuelve la URL de portada adecuada para el tamaño real de decodificación.
///
/// YouTube publica varias variantes de la misma miniatura. Pedir siempre
/// `maxresdefault.jpg` para una fila de 56 px desperdicia red, disco y memoria;
/// para las listas basta con `hqdefault`/`mqdefault` y la imagen aparece antes.
/// En portadas que no son de YouTube se ajusta el parámetro `=w...-h...`.
String? artworkUrlForSize(String? source, {required int targetSize}) {
  if (source == null || source.isEmpty) return null;
  final uri = Uri.tryParse(source);
  if (uri == null) return source;

  if ((uri.host == 'i.ytimg.com' || uri.host == 'img.youtube.com') &&
      uri.pathSegments.length >= 3) {
    final variant = targetSize >= 720
        ? 'maxresdefault.jpg'
        : targetSize >= 480
        ? 'sddefault.jpg'
        : targetSize >= 240
        ? 'hqdefault.jpg'
        : 'mqdefault.jpg';
    final segments = [...uri.pathSegments]..[2] = variant;
    return uri.replace(pathSegments: segments).toString();
  }

  final size = targetSize.clamp(64, 1200);
  return source.replaceFirst(
    RegExp(r'=w\d+-h\d+[^&]*'),
    '=w$size-h$size-l90-rj',
  );
}
