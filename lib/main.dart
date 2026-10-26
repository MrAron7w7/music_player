import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:audio_session/audio_session.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/services/app_cache.dart';
import 'data/services/audio_cache_service.dart';
import 'data/services/download_service.dart';
import 'data/services/listening_stats_service.dart';
import 'data/services/yt_service.dart';
import 'data/repositories/local_repository.dart';
import 'data/repositories/music_repository.dart';
import 'data/services/audio_handler.dart';
import 'providers/cache_providers.dart';
import 'providers/downloads_providers.dart';
import 'providers/music_providers.dart';
import 'providers/player_providers.dart';
import 'providers/library_providers.dart';

late final YtService ytService;
late final MusicRepository musicRepository;
late final LocalRepository localRepository;
late final DownloadService downloadService;
late final ListeningStatsService statsService;
late final MusicAudioHandler audioHandler;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final boxes = await Future.wait([
    Hive.openBox(AppConstants.favoritesBox),
    Hive.openBox(AppConstants.playlistsBox),
    Hive.openBox(AppConstants.historyBox),
    Hive.openBox(AppConstants.settingsBox),
    Hive.openBox(AppConstants.downloadsBox),
    Hive.openBox(AppConstants.statsBox),
  ]);
  final cacheBox = await Hive.openBox(AppConstants.cacheBox);
  final appCache = AppCache(cacheBox);
  localRepository = LocalRepository(boxes[0], boxes[1], boxes[2], boxes[3]);
  final temporaryDirectory = await getTemporaryDirectory();
  final audioCache = AudioCacheService(
    Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}melody_audio',
    ),
  );
  final storedLimit = localRepository.settings.get(
    AppConstants.cacheLimitKey,
    defaultValue: AudioCacheService.defaultMaxBytes,
  );
  if (storedLimit is int) audioCache.setLimitBytes(storedLimit);
  await audioCache.init();

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  final api = await YTMusic.create();
  ytService = YtService(api, cache: appCache);
  musicRepository = MusicRepository(
    ytService,
    YoutubeExplode(),
    audioCache: audioCache,
  );

  final supportDirectory = await getApplicationSupportDirectory();
  downloadService = DownloadService(
    directory: Directory(
      '${supportDirectory.path}${Platform.pathSeparator}downloads',
    ),
    box: boxes[4],
    resolveStream: (id, quality) async {
      for (final fallback in MusicRepository.fallbackChain(quality)) {
        final uri = await musicRepository.getAudioStreamUrl(
          id,
          quality: fallback,
        );
        if (uri != null) return uri;
      }
      return null;
    },
    wifiOnly: () =>
        localRepository.settings.get(
          AppConstants.wifiOnlyDownloadsKey,
          defaultValue: false,
        ) ==
        true,
  );
  await downloadService.init();

  statsService = ListeningStatsService(boxes[5]);
  await statsService.init();

  AppTheme.themeMode.value = switch (localRepository.settings.get(
    'themeMode',
    defaultValue: 'system',
  )) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  musicRepository.quality = switch (localRepository.settings.get(
    'audioQuality',
  )) {
    'low' => AudioQuality.low,
    'medium' => AudioQuality.medium,
    _ => AudioQuality.high,
  };
  audioHandler = await AudioService.init(
    builder: () => MusicAudioHandler(
      musicRepository,
      settings: localRepository.settings,
      session: session,
      downloads: downloadService,
      stats: statsService,
      history: boxes[2],
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_app.audio',
      androidNotificationChannelName: 'Reproducción',
      androidNotificationChannelDescription:
          'Controles de reproducción de Simple Music',
      androidNotificationIcon: 'drawable/ic_stat_music',
      notificationColor: Color(0xFF2563EB),
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationClickStartsActivity: true,
      androidShowNotificationBadge: false,
      preloadArtwork: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    ),
  );
  audioHandler.autoPlayRelated = localRepository.settings.get(
    'autoPlayRelated',
    defaultValue: true,
  ) as bool;
  await audioHandler.restoreSession();
  runApp(
    ProviderScope(
      overrides: [
        ytServiceProvider.overrideWithValue(ytService),
        musicRepositoryProvider.overrideWithValue(musicRepository),
        localRepositoryProvider.overrideWithValue(localRepository),
        audioHandlerProvider.overrideWithValue(audioHandler),
        appCacheProvider.overrideWithValue(appCache),
        audioCacheProvider.overrideWithValue(audioCache),
        downloadServiceProvider.overrideWithValue(downloadService),
        statsServiceProvider.overrideWithValue(statsService),
      ],
      child: const MusicApp(),
    ),
  );
}
