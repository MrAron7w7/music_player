import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/download_service.dart';
import '../data/services/listening_stats_service.dart';

final downloadServiceProvider = Provider<DownloadService>(
  (ref) => throw UnimplementedError('DownloadService no inicializado'),
);

final downloadsProvider = StreamProvider<List<DownloadEntry>>((ref) {
  final service = ref.watch(downloadServiceProvider);
  return (() async* {
    yield service.entries;
    yield* service.stream;
  })();
});

final downloadProgressProvider = StreamProvider<Map<String, double>>((ref) {
  final service = ref.watch(downloadServiceProvider);
  return (() async* {
    yield service.progress;
    yield* service.progressStream;
  })();
});

final statsServiceProvider = Provider<ListeningStatsService>(
  (ref) => throw UnimplementedError('ListeningStatsService no inicializado'),
);

final statsProvider = StreamProvider<StatsSnapshot>((ref) {
  final service = ref.watch(statsServiceProvider);
  return (() async* {
    yield service.snapshot();
    yield* service.stream;
  })();
});
