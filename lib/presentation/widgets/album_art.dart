import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils/artwork_url.dart';

class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    this.url,
    this.fallbackUrl,
    this.size = 56,
    this.radius = 12,
  });

  final String? url;
  final String? fallbackUrl;
  final double size, radius;

  Widget _networkArt(BuildContext context) {
    final source = url;
    if (source == null) return _fallback(context);

    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, 768)
        .toInt();
    final primary = artworkUrlForSize(source, targetSize: decodeSize) ?? source;
    final fallbackSource =
        artworkUrlForSize(
          fallbackUrl ?? source,
          targetSize: decodeSize.clamp(64, 480).toInt(),
        ) ??
        primary;

    Widget image(String imageUrl, Widget Function() onError) =>
        CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          // Solo se fija el ancho: fijar ancho y alto a la vez deforma las
          // miniaturas 16:9 de YouTube al decodificarlas como un cuadrado.
          memCacheWidth: decodeSize,
          maxWidthDiskCache: decodeSize,
          filterQuality: FilterQuality.low,
          fadeInDuration: const Duration(milliseconds: 90),
          errorWidget: (context, url, error) => onError(),
        );

    return image(
      primary,
      () => primary == fallbackSource
          ? _fallback(context)
          : image(fallbackSource, () => _fallback(context)),
    );
  }

  Widget _fallback(BuildContext context) => Icon(
    Icons.music_note_rounded,
    size: size * .48,
    color: Theme.of(context).colorScheme.primary,
  );

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: _networkArt(context),
    ),
  );
}
