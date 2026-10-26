import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
  String _highResolution(String source) {
    final uri = Uri.tryParse(source);
    if (uri?.host == 'i.ytimg.com' && uri!.pathSegments.length >= 3) {
      final segments = [...uri.pathSegments]..[2] = 'maxresdefault.jpg';
      return uri.replace(pathSegments: segments).toString();
    }
    return source.replaceFirst(
      RegExp(r'=w\d+-h\d+[^&]*'),
      '=w1200-h1200-l90-rj',
    );
  }

  Widget _networkArt(BuildContext context, String source) {
    final highResolution = _highResolution(source);
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, 768)
        .toInt();
    Widget fallback() => Icon(
      Icons.music_note_rounded,
      size: size * .48,
      color: Theme.of(context).colorScheme.primary,
    );
    final fallbackSource = fallbackUrl ?? source;
    Widget original() => CachedNetworkImage(
      imageUrl: fallbackSource,
      fit: BoxFit.cover,
      memCacheWidth: decodeSize,
      memCacheHeight: decodeSize,
      fadeInDuration: const Duration(milliseconds: 110),
      errorWidget: (context, url, error) => fallback(),
    );
    return CachedNetworkImage(
      imageUrl: highResolution,
      fit: BoxFit.cover,
      memCacheWidth: decodeSize,
      memCacheHeight: decodeSize,
      fadeInDuration: const Duration(milliseconds: 110),
      errorWidget: (context, url, error) =>
          highResolution == fallbackSource ? fallback() : original(),
    );
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: url == null
          ? Icon(
              Icons.music_note_rounded,
              size: size * .48,
              color: Theme.of(context).colorScheme.primary,
            )
          : _networkArt(context, url!),
    ),
  );
}
