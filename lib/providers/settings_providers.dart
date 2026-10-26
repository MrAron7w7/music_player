import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../data/services/audio_cache_service.dart';
import 'cache_providers.dart';
import 'library_providers.dart';

final wifiOnlyDownloadsProvider = StateProvider<bool>(
  (ref) =>
      ref
              .watch(localRepositoryProvider)
              .settings
              .get(AppConstants.wifiOnlyDownloadsKey, defaultValue: false)
          as bool,
);

final offlineModeProvider = StateProvider<bool>(
  (ref) =>
      ref
              .watch(localRepositoryProvider)
              .settings
              .get(AppConstants.offlineModeKey, defaultValue: false)
          as bool,
);

final crossfadeEnabledProvider = StateProvider<bool>(
  (ref) =>
      ref
              .watch(localRepositoryProvider)
              .settings
              .get(AppConstants.crossfadeEnabledKey, defaultValue: false)
          as bool,
);

final crossfadeSecondsProvider = StateProvider<int>((ref) {
  final raw = ref
      .watch(localRepositoryProvider)
      .settings
      .get(AppConstants.crossfadeSecondsKey, defaultValue: 3);
  return raw is int ? raw.clamp(1, 12) : 3;
});

final headsetAutoplayProvider = StateProvider<bool>(
  (ref) =>
      ref
              .watch(localRepositoryProvider)
              .settings
              .get(AppConstants.headsetAutoplayKey, defaultValue: false)
          as bool,
);

/// 0 significa "sin límite".
final audioCacheLimitProvider = StateProvider<int>((ref) {
  final raw = ref
      .watch(localRepositoryProvider)
      .settings
      .get(
        AppConstants.cacheLimitKey,
        defaultValue: AudioCacheService.defaultMaxBytes,
      );
  return raw is int && raw >= 0 ? raw : AudioCacheService.defaultMaxBytes;
});

class CacheUsage {
  const CacheUsage({
    required this.audioBytes,
    required this.audioFiles,
    required this.metadataBytes,
    required this.metadataEntries,
    required this.coverDiskBytes,
    required this.coverMemoryBytes,
  });

  final int audioBytes;
  final int audioFiles;
  final int metadataBytes;
  final int metadataEntries;
  final int coverDiskBytes;
  final int coverMemoryBytes;

  int get coverBytes => coverDiskBytes + coverMemoryBytes;
  int get totalBytes => audioBytes + metadataBytes + coverBytes;
}

final cacheUsageProvider = FutureProvider.autoDispose<CacheUsage>((ref) async {
  final audio = ref.watch(audioCacheProvider);
  final appCache = ref.watch(appCacheProvider);
  var coverDisk = 0;
  try {
    final temp = await getTemporaryDirectory();
    final coverDir = Directory(
      '${temp.path}${Platform.pathSeparator}libCachedImageData',
    );
    if (await coverDir.exists()) {
      await for (final entity in coverDir.list(recursive: true)) {
        if (entity is File) {
          try {
            coverDisk += await entity.length();
          } catch (_) {}
        }
      }
    }
  } catch (_) {}
  return CacheUsage(
    audioBytes: await audio.sizeBytes(),
    audioFiles: await audio.fileCount(),
    metadataBytes: appCache.estimatedBytes(),
    metadataEntries: appCache.entryCount,
    coverDiskBytes: coverDisk,
    coverMemoryBytes: PaintingBinding.instance.imageCache.currentSizeBytes,
  );
});
