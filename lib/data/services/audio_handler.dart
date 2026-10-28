import 'dart:async';
import 'dart:math' as math;

// `AudioDeviceType` sigue marcado como experimental en audio_session, pero es
// la única API multiplataforma para detectar auriculares Bluetooth/USB.
// ignore_for_file: experimental_member_use

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song_model.dart';
import '../repositories/music_repository.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/artwork_url.dart';
import '../../core/utils/song_unavailable_exception.dart';
import 'download_service.dart';
import 'listening_stats_service.dart';

class _PlaybackFailure implements Exception {
  const _PlaybackFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class _NoConnection implements Exception {
  const _NoConnection();
}

/// Reproductor principal de Simple Music.
///
/// Mantiene una cola lógica completa (independiente de qué streams ya se
/// resolvieron), lo que permite reordenar, quitar y encolar canciones sin
/// tocar la reproducción en curso. Usa dos `AudioPlayer` para poder hacer un
/// crossfade real con solapamiento.
class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler(
    this.repository, {
    required Box settings,
    required AudioSession session,
    this.downloads,
    this.stats,
    this.history,
    // ignore: prefer_initializing_formals
  }) : _settings = settings,
       // ignore: prefer_initializing_formals
       _session = session,
       _players = [
         AudioPlayer(
           handleInterruptions: false,
           handleAudioSessionActivation: false,
         ),
         AudioPlayer(
           handleInterruptions: false,
           handleAudioSessionActivation: false,
         ),
       ] {
    _active = _players[0];
    _standby = _players[1];
    for (final player in _players) {
      _bindPlayer(player);
    }
    _listenAudioSession();
    _listenConnectivity();
    _reloadCrossfadeSettings();
    // El ticker solo arranca cuando hay reproducción activa (ver _emitPlaying).
    _settingsSubscription = _settings.watch().listen((event) {
      if (event.key == AppConstants.crossfadeEnabledKey ||
          event.key == AppConstants.crossfadeSecondsKey) {
        _reloadCrossfadeSettings();
      }
    });
  }

  void _reloadCrossfadeSettings() {
    _crossfadeEnabledCache =
        _settings.get(AppConstants.crossfadeEnabledKey, defaultValue: false) ==
            true;
    final seconds = _settings.get(
      AppConstants.crossfadeSecondsKey,
      defaultValue: 3,
    );
    final value = seconds is int ? seconds : 3;
    _crossfadeDurationCache = Duration(seconds: value.clamp(1, 12));
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 750), (_) => _onTick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  final MusicRepository repository;
  final Box _settings;
  final AudioSession _session;
  final DownloadService? downloads;
  final ListeningStatsService? stats;
  final Box? history;

  final List<AudioPlayer> _players;
  late AudioPlayer _active;
  late AudioPlayer _standby;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _historyChanges = StreamController<void>.broadcast();
  final _devicesController = StreamController<Set<AudioDevice>>.broadcast();

  final List<SongModel> _queueSongs = [];
  int _currentIndex = -1;
  int _playRequestId = 0;
  bool _isResolvingStream = false;
  bool _needsLoad = false;
  bool _restoredSession = false;
  Duration _resumePosition = Duration.zero;
  int _lastPlayedSeconds = -1;
  int _lastSavedSecond = -1;
  int _pendingListeningSeconds = 0;
  bool _recordedPlay = false;
  Future<bool>? _queueEnrichment;
  String? _lastEnrichedSeedId;
  bool _wasPlayingBeforeInterruption = false;
  bool _ducking = false;

  /// Estado que el usuario quiere conservar (play/pausa). No se debe usar
  /// `_active.playing` para decidir si seguir reproduciendo al cambiar de
  /// canción: durante una carga el player se detiene temporalmente y eso
  /// convertía un Next rápido en una pausa inesperada.
  bool _playIntent = false;
  String? _errorMessage;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;
  bool autoPlayRelated = true;

  Timer? _ticker;
  Timer? _fadeTimer;
  AudioPlayer? _fadingPlayer;
  bool _crossfading = false;
  bool _preparingCrossfade = false;
  bool _startingCrossfade = false;
  int? _preparedNextIndex;
  Set<AudioDevice> _lastDevices = {};
  bool _devicesInitialized = false;
  StreamSubscription? _interruptionSubscription;
  StreamSubscription? _noisySubscription;
  StreamSubscription? _devicesSubscription;
  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _settingsSubscription;
  bool? _online;
  bool? _lastPlayingEmitted;
  Duration? _lastDurationEmitted;
  String _lastStateSignature = '';
  DateTime _lastStateAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Caché de los valores de crossfade para no leer Hive en cada tick.
  bool _crossfadeEnabledCache = false;
  Duration _crossfadeDurationCache = const Duration(seconds: 3);

  // La cola serializada se reutiliza entre guardados periódicos; solo se
  // reescribe cuando la cola cambia de verdad.
  List<Map<String, dynamic>>? _sessionQueueJson;
  bool _sessionQueueDirty = true;
  int? _lastPersistedIndex;
  int? _lastPersistedPositionMs;
  int _sessionWriteId = 0;
  Future<void> _sessionWrite = Future<void>.value();

  bool get isResolvingStream => _isResolvingStream;
  bool get hasRestoredSession => _restoredSession;
  int get currentIndex => _currentIndex;
  SongModel? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _queueSongs.length
      ? _queueSongs[_currentIndex]
      : null;
  List<SongModel> get queueSongs => List.unmodifiable(_queueSongs);
  bool get hasNext =>
      _currentIndex >= 0 &&
      (_currentIndex < _queueSongs.length - 1 ||
          _repeatMode == AudioServiceRepeatMode.all ||
          autoPlayRelated);
  bool get hasPrevious => _currentIndex > 0;
  double get currentVolume => _active.volume;

  /// Solo la intención explícita del usuario decide si el próximo cambio de
  /// canción debe seguir sonando. Así una pausa durante la carga no se pierde.
  bool get _shouldKeepPlaying => _playIntent;

  Duration get currentPosition =>
      _needsLoad ? _resumePosition : _active.position;
  Duration? get currentDuration => _active.duration ?? currentSong?.duration;

  Stream<Duration> get positionStream async* {
    yield currentPosition;
    yield* _positionController.stream;
  }

  Stream<Duration?> get durationStream async* {
    yield currentDuration;
    yield* _durationController.stream;
  }

  Stream<bool> get playingStream async* {
    yield _active.playing;
    yield* _playingController.stream;
  }

  Stream<void> get historyChanges => _historyChanges.stream;
  Stream<Set<AudioDevice>> get devicesStream async* {
    yield Set.unmodifiable(_lastDevices);
    yield* _devicesController.stream;
  }

  AudioPlayer get player => _active;

  // ---------------------------------------------------------------------------
  // Inicialización de audio, auriculares y foco
  // ---------------------------------------------------------------------------

  void _emitPlaying(bool value) {
    if (_lastPlayingEmitted == value) return;
    _lastPlayingEmitted = value;
    _playingController.add(value);
    if (value && _currentIndex >= 0) {
      _startTicker();
    } else {
      _stopTicker();
    }
  }

  void _emitDuration(Duration? value) {
    if (_lastDurationEmitted == value) return;
    _lastDurationEmitted = value;
    _durationController.add(value);
  }

  void _bindPlayer(AudioPlayer player) {
    player.positionStream.listen((position) {
      if (identical(player, _active)) _positionController.add(position);
    });
    player.durationStream.listen((duration) {
      if (identical(player, _active)) _emitDuration(duration);
    });
    player.playingStream.listen((playing) {
      if (identical(player, _active) && !_crossfading) {
        _emitPlaying(playing);
      }
      if (identical(player, _active)) _broadcastState();
    });
    player.playbackEventStream.listen(
      (_) {
        if (identical(player, _active)) _broadcastState();
      },
      onError: (Object error, StackTrace _) {
        if (identical(player, _active)) _publishPlaybackError(error);
      },
    );
    player.processingStateStream.listen((state) {
      if (!identical(player, _active)) return;
      if (state == ProcessingState.completed) _onCompleted();
      _broadcastState();
    });
  }

  void _listenAudioSession() {
    _interruptionSubscription = _session.interruptionEventStream.listen((
      event,
    ) async {
      if (event.begin) {
        _wasPlayingBeforeInterruption = _active.playing;
        if (event.type == AudioInterruptionType.duck) {
          _ducking = true;
          await _active.setVolume(.22);
        } else if (_active.playing) {
          await _pauseInternal(fromInterruption: true);
        }
      } else {
        if (_ducking) {
          _ducking = false;
          await _active.setVolume(1);
        } else if (_wasPlayingBeforeInterruption &&
            event.type == AudioInterruptionType.pause) {
          _wasPlayingBeforeInterruption = false;
          await play();
        }
      }
    });
    _noisySubscription = _session.becomingNoisyEventStream.listen((_) async {
      if (_active.playing) {
        _wasPlayingBeforeInterruption = false;
        await _pauseInternal();
      }
    });
    _devicesSubscription = _session.devicesStream.listen((devices) {
      final hadHeadphones = _hasHeadphones(_lastDevices);
      final hasHeadphones = _hasHeadphones(devices);
      final changed = !setEquals(devices, _lastDevices);
      _lastDevices = devices;
      if (changed) _devicesController.add(Set.unmodifiable(devices));
      if (!_devicesInitialized) {
        _devicesInitialized = true;
        return;
      }
      if (hadHeadphones && !hasHeadphones && _active.playing) {
        unawaited(_pauseInternal());
        return;
      }
      final autoplay =
          _settings.get('headsetAutoplay', defaultValue: false) == true;
      if (!hadHeadphones &&
          hasHeadphones &&
          autoplay &&
          !_active.playing &&
          _queueSongs.isNotEmpty) {
        unawaited(play());
      }
    });
  }

  void _listenConnectivity() {
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
        results,
      ) {
        _online = results.any((item) => item != ConnectivityResult.none);
      }, onError: (_) {});
      unawaited(() async {
        try {
          final result = await Connectivity().checkConnectivity();
          _online = result.any((item) => item != ConnectivityResult.none);
        } catch (_) {
          // Si el plugin falla, el propio stream de audio decide.
        }
      }());
    } catch (_) {}
  }

  bool _hasHeadphones(Set<AudioDevice> devices) => devices.any(
    (device) =>
        device.isOutput &&
        (device.type == AudioDeviceType.wiredHeadphones ||
            device.type == AudioDeviceType.wiredHeadset ||
            device.type == AudioDeviceType.bluetoothA2dp ||
            device.type == AudioDeviceType.bluetoothSco ||
            device.type == AudioDeviceType.usbAudio),
  );

  // ---------------------------------------------------------------------------
  // Estado para la notificación
  // ---------------------------------------------------------------------------

  MediaItem _mediaItem(SongModel song, {Duration? duration}) {
    // La notificación sólo necesita una portada pequeña; la UI usa la versión
    // de alta resolución desde `extras['song']`.
    final artUrl = artworkUrlForSize(song.artworkUrl, targetSize: 480);
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artists.join(', '),
      album: song.album,
      artUri: artUrl == null ? null : Uri.tryParse(artUrl),
      duration: duration ?? song.duration,
      extras: {
        if (song.thumbnailUrl != null) 'fallbackArtworkUrl': song.thumbnailUrl,
        'song': song.toJson(),
      },
    );
  }

  SongModel? _songFromMediaItem(MediaItem item) {
    final raw = item.extras?['song'];
    if (raw is Map) {
      try {
        return SongModel.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {}
    }
    return SongModel(
      id: item.id,
      title: item.title,
      artists: item.artist == null ? const [] : [item.artist!],
      album: item.album,
      duration: item.duration,
    );
  }

  void _broadcastState({bool force = false}) {
    final hasError = _errorMessage != null;
    final processing = hasError
        ? AudioProcessingState.error
        : _isResolvingStream
        ? AudioProcessingState.loading
        : switch (_active.processingState) {
            ProcessingState.idle => AudioProcessingState.idle,
            ProcessingState.loading => AudioProcessingState.loading,
            ProcessingState.buffering => AudioProcessingState.buffering,
            ProcessingState.ready => AudioProcessingState.ready,
            ProcessingState.completed => AudioProcessingState.completed,
          };
    final playing = _active.playing || _crossfading;
    final signature =
        '$hasError|$_errorMessage|$processing|$playing|$_currentIndex|'
        '$_repeatMode|$_shuffleMode|$_crossfading|$_needsLoad|'
        '$_isResolvingStream|${_active.speed}';
    final now = DateTime.now();
    if (!force &&
        signature == _lastStateSignature &&
        now.difference(_lastStateAt) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastStateSignature = signature;
    _lastStateAt = now;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processing,
        playing: playing,
        updatePosition: _needsLoad ? _resumePosition : _active.position,
        bufferedPosition: _active.bufferedPosition,
        speed: _active.speed,
        queueIndex: _currentIndex < 0 ? null : _currentIndex,
        repeatMode: _repeatMode,
        shuffleMode: _shuffleMode,
        errorCode: hasError ? -1 : 0,
        errorMessage: _errorMessage,
      ),
    );
  }

  void _publishPlaybackError(Object error, {String? message}) {
    _isResolvingStream = false;
    _playIntent = false;
    _needsLoad = true;
    _resumePosition = _active.position;
    _cancelCrossfade(stopFading: true);
    final friendly = switch (error) {
      _PlaybackFailure(:final message) => message,
      _NoConnection() =>
        'Sin conexión a internet. Revisa tu red e inténtalo de nuevo.',
      SongUnavailableException(:final SongUnavailableReason reason) =>
        _unavailableMessage(reason),
      _ => message ?? 'No se pudo reproducir esta canción. Inténtalo de nuevo.',
    };
    _errorMessage = friendly;
    _lastStateSignature = '';
    _emitPlaying(false);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
        errorCode: -1,
        errorMessage: friendly,
        queueIndex: _currentIndex < 0 ? null : _currentIndex,
      ),
    );
    _positionController.add(_resumePosition);
  }

  String _unavailableMessage(SongUnavailableReason reason) {
    switch (reason) {
      case SongUnavailableReason.ageRestricted:
        return 'Esta canción está restringida por edad.';
      case SongUnavailableReason.regionRestricted:
        return 'Esta canción no está disponible en tu región.';
      case SongUnavailableReason.purchaseRequired:
        return 'Esta canción requiere compra o alquiler.';
      case SongUnavailableReason.unavailable:
        return 'Esta canción ya no está disponible.';
      case SongUnavailableReason.streamError:
        return 'No se pudo obtener el audio de esta canción.';
      case SongUnavailableReason.apiError:
        return 'No se pudo conectar con YouTube. Inténtalo de nuevo.';
    }
  }

  // ---------------------------------------------------------------------------
  // Carga y reproducción
  // ---------------------------------------------------------------------------

  Future<bool> _hasInternet() async {
    final known = _online;
    if (known != null) return known;
    try {
      final result = await Connectivity().checkConnectivity();
      _online = result.any((item) => item != ConnectivityResult.none);
      return _online!;
    } catch (_) {
      // Si el plugin falla, dejamos que el propio stream sea quien decida.
      return true;
    }
  }

  Future<AudioSource> _sourceFor(
    SongModel song, {
    required AudioQuality preferred,
    bool forceRefresh = false,
    bool requireWatchPage = false,
    bool allowNetwork = true,
  }) async {
    final downloaded = downloads?.fileFor(song.id);
    if (downloaded != null) {
      return AudioSource.file(downloaded.path, tag: _mediaItem(song));
    }
    final cached = repository.audioCache?.cachedFile(song.id);
    if (cached != null) {
      return AudioSource.file(cached.path, tag: _mediaItem(song));
    }

    final offline = _settings.get('offlineMode', defaultValue: false) == true;
    if (offline) {
      throw const _PlaybackFailure(
        'Modo offline activo. Esta canción no está descargada.',
      );
    }
    if (!allowNetwork) {
      throw const _PlaybackFailure(
        'Esta canción no está disponible sin conexión.',
      );
    }
    if (!await _hasInternet()) throw const _NoConnection();

    // Aunque se prueben varias calidades, el usuario no debe esperar más de
    // ~25 s en total. Si la red está caída, se muestra el error y se permite
    // reintentar en lugar de encadenar esperas por cada calidad.
    final deadline = DateTime.now().add(const Duration(seconds: 26));
    SongUnavailableException? lastTransitory;
    for (final quality in MusicRepository.fallbackChain(preferred)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      Uri? uri;
      try {
        uri = await repository
            .getAudioStreamUrl(
              song.id,
              quality: quality,
              forceRefresh: forceRefresh || quality != preferred,
              requireWatchPage: requireWatchPage || quality != preferred,
            )
            .timeout(remaining, onTimeout: () => null);
      } on SongUnavailableException catch (e) {
        if (e.reason == SongUnavailableReason.apiError ||
            e.reason == SongUnavailableReason.streamError) {
          lastTransitory = e;
          continue;
        }
        rethrow;
      }
      if (uri != null) {
        return AudioSource.uri(uri, tag: _mediaItem(song));
      }
    }
    throw lastTransitory ??
        const _PlaybackFailure(
          'No se pudo obtener el audio. Puede que el video no esté disponible.',
        );
  }

  Future<void> _loadCurrent({
    required bool autoPlay,
    Duration? position,
  }) async {
    if (_currentIndex < 0 || _currentIndex >= _queueSongs.length) return;
    final song = _queueSongs[_currentIndex];
    final requestId = ++_playRequestId;
    _playIntent = autoPlay;
    _needsLoad = true;
    _isResolvingStream = true;
    _errorMessage = null;
    _preparedNextIndex = null;
    _cancelCrossfade(stopFading: true);
    _broadcastState();
    mediaItem.add(_mediaItem(song));

    try {
      // Detener el player anterior y resolver el stream en paralelo: el stop
      // tarda milisegundos y no debe sumarse a la latencia de la red.
      final preparation = Future.wait<void>([
        _active.stop().catchError((_) {}),
        _active.setVolume(1).catchError((_) {}),
      ]);
      final source = await _sourceFor(song, preferred: repository.quality);
      await preparation;
      if (requestId != _playRequestId) return;

      try {
        await _active.setAudioSource(source);
      } catch (error) {
        // La URL pudo caducar: se reintenta una vez con URL fresca.
        if (requestId != _playRequestId) return;
        repository.invalidateStream(song.id);
        final retry = await _sourceFor(
          song,
          preferred: AudioQuality.medium,
          forceRefresh: true,
          requireWatchPage: true,
        );
        if (requestId != _playRequestId) return;
        await _active.setAudioSource(retry);
      }
      if (requestId != _playRequestId) return;

      final startAt = position ?? Duration.zero;
      if (startAt > Duration.zero) {
        final duration = _active.duration;
        await _active.seek(
          duration != null && startAt > duration ? Duration.zero : startAt,
        );
      }
      _isResolvingStream = false;
      _needsLoad = false;
      _resumePosition = Duration.zero;
      _lastPlayedSeconds = -1;
      _pendingListeningSeconds = 0;
      _recordedPlay = false;
      _broadcastState();
      if (autoPlay && _playIntent) {
        await _startPlayback(recordPlay: true);
      } else {
        _emitPlaying(false);
      }
      unawaited(_persistSession());
      unawaited(_prefetchUpcoming());
    } catch (error) {
      if (requestId != _playRequestId) return;
      _publishPlaybackError(error);
    }
  }

  Future<void> _startPlayback({bool recordPlay = false}) async {
    if (_currentIndex < 0 || _currentIndex >= _queueSongs.length) return;
    _playIntent = true;
    if (_needsLoad) {
      await _loadCurrent(autoPlay: true, position: _resumePosition);
      return;
    }
    _errorMessage = null;
    if (_active.processingState == ProcessingState.completed) {
      await _active.seek(Duration.zero);
      _recordedPlay = false;
      _lastPlayedSeconds = -1;
      _pendingListeningSeconds = 0;
    }
    try {
      final activated = await _session.setActive(true);
      if (!activated) {
        _publishPlaybackError(
          const _PlaybackFailure(
            'Otra aplicación está usando el audio. Inténtalo de nuevo.',
          ),
        );
        return;
      }
      await _active.play();
      _emitPlaying(true);
      if (recordPlay && !_recordedPlay) {
        _recordedPlay = true;
        final song = currentSong;
        if (song != null) {
          _recordPlay(song);
          unawaited(_addHistory(song));
        }
      }
      _broadcastState();
    } catch (error) {
      _publishPlaybackError(error);
    }
  }

  Future<void> _addHistory(SongModel song) async {
    final box = history;
    if (box == null) return;
    try {
      await box.delete(song.id);
      await box.put(song.id, song.toJson());
      while (box.length > 100) {
        await box.deleteAt(0);
      }
      _historyChanges.add(null);
    } catch (_) {}
  }

  /// Resuelve en segundo plano el stream de las siguientes canciones.
  Future<void> _prefetchUpcoming() async {
    if (_currentIndex < 0) return;
    final cache = repository.audioCache;
    if (cache == null) return;
    final requestId = _playRequestId;
    try {
      for (
        var offset = 1;
        offset <= 2 && _currentIndex + offset < _queueSongs.length;
        offset++
      ) {
        final song = _queueSongs[_currentIndex + offset];
        if (downloads?.isDownloaded(song.id) == true ||
            cache.cachedFile(song.id) != null) {
          continue;
        }
        final uri = await repository.getAudioStreamUrl(
          song.id,
          quality: repository.quality,
        );
        if (requestId != _playRequestId) return;
        if (uri != null) unawaited(cache.prefetch(song.id, uri));
      }
    } catch (_) {
      // La precarga es opcional: un fallo no debe afectar la reproducción.
    }
  }

  Future<void> _onCompleted() async {
    if (_isResolvingStream) return;
    unawaited(_flushListening());
    unawaited(_persistSession(force: true));
    if (_repeatMode == AudioServiceRepeatMode.one) {
      await _active.seek(Duration.zero);
      await _startPlayback(recordPlay: true);
      return;
    }
    if (_currentIndex >= 0 && _currentIndex < _queueSongs.length - 1) {
      _currentIndex++;
      await _loadCurrent(autoPlay: true);
      return;
    }
    if (_repeatMode == AudioServiceRepeatMode.all && _queueSongs.isNotEmpty) {
      _currentIndex = 0;
      await _loadCurrent(autoPlay: true);
      return;
    }
    if (autoPlayRelated && currentSong != null) {
      final added = await _ensureSmartQueue(currentSong!, force: true);
      if (added) {
        _currentIndex++;
        await _loadCurrent(autoPlay: true);
        return;
      }
    }
    _playIntent = false;
    _emitPlaying(false);
    _broadcastState();
  }

  /// Añade una cola inteligente (álbum + relacionadas + artista) sin cortar
  /// la reproducción. Si una fuente falla, las demás siguen aportando.
  Future<bool> _ensureSmartQueue(SongModel seed, {bool force = false}) async {
    if (!autoPlayRelated || seed.id.isEmpty) return false;
    if (_settings.get('offlineMode', defaultValue: false) == true) return false;
    if (!force && _lastEnrichedSeedId == seed.id) return false;

    final running = _queueEnrichment;
    if (running != null) {
      await running;
      if (!force && _lastEnrichedSeedId == seed.id) return false;
    }

    final future = _enrichQueue(seed);
    _queueEnrichment = future;
    try {
      return await future;
    } finally {
      if (identical(_queueEnrichment, future)) _queueEnrichment = null;
    }
  }

  Future<bool> _enrichQueue(SongModel seed) async {
    final requestId = _playRequestId;
    final existing = _queueSongs.map((song) => song.id).toSet();
    final recent = <String>{};
    final box = history;
    if (box != null) {
      try {
        final entries = box.values.whereType<Map>().toList().reversed.take(14);
        for (final entry in entries) {
          final id = '${entry['id'] ?? entry['videoId'] ?? ''}';
          if (id.isNotEmpty) recent.add(id);
        }
      } catch (_) {}
    }

    try {
      final additions = await repository.yt.getSmartQueue(
        seed,
        excludeIds: {...existing, ...recent},
        limit: 24,
      );
      if (additions.isEmpty) return false;
      if (requestId != _playRequestId) return false;

      // La cola pudo cambiar mientras se resolvían las recomendaciones.
      final currentIds = _queueSongs.map((song) => song.id).toSet();
      final unique = additions
          .where((song) => !currentIds.contains(song.id))
          .toList();
      if (unique.isEmpty) return false;

      _queueSongs.addAll(unique);
      _lastEnrichedSeedId = seed.id;
      _emitQueue();
      unawaited(_persistSession());
      unawaited(_prefetchUpcoming());
      return true;
    } catch (_) {
      // Las recomendaciones nunca deben romper la reproducción actual.
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Crossfade
  // ---------------------------------------------------------------------------

  Future<void> _maybePrepareCrossfade() async {
    if (!_crossfadeEnabled ||
        _crossfading ||
        _preparingCrossfade ||
        _isResolvingStream ||
        _needsLoad ||
        !_active.playing ||
        _currentIndex < 0 ||
        _currentIndex >= _queueSongs.length - 1) {
      return;
    }
    final nextIndex = _currentIndex + 1;
    if (_preparedNextIndex == nextIndex) return;
    final duration = _active.duration;
    if (duration == null) return;
    final remaining = duration - _active.position;
    final fade = _crossfadeDuration;
    if (remaining > fade + const Duration(seconds: 5) ||
        remaining <= Duration.zero) {
      return;
    }

    final song = _queueSongs[nextIndex];
    _preparingCrossfade = true;
    try {
      await _standby.stop();
      await _standby.setVolume(0);
      final source = await _sourceFor(song, preferred: repository.quality);
      if (_currentIndex + 1 != nextIndex ||
          _preparedNextIndex == nextIndex ||
          _crossfading) {
        return;
      }
      await _standby.setAudioSource(source);
      if (_currentIndex + 1 != nextIndex || !_active.playing) return;
      _preparedNextIndex = nextIndex;
      _emitDuration(_standby.duration);
    } catch (_) {
      // Si no se puede preparar, la transición normal al terminar seguirá.
      _preparedNextIndex = null;
    } finally {
      _preparingCrossfade = false;
    }
  }

  Future<void> _maybeStartCrossfade() async {
    if (!_crossfadeEnabled ||
        _crossfading ||
        _startingCrossfade ||
        _preparedNextIndex != _currentIndex + 1 ||
        _currentIndex < 0) {
      return;
    }
    final duration = _active.duration;
    if (duration == null) return;
    final remaining = duration - _active.position;
    if (remaining > _crossfadeDuration || remaining <= Duration.zero) return;

    _startingCrossfade = true;
    try {
      final nextIndex = _currentIndex + 1;
      final nextSong = _queueSongs[nextIndex];
      final old = _active;
      unawaited(_flushListening());
      _crossfading = true;
      _active = _standby;
      _standby = old;
      _fadingPlayer = old;
      _preparedNextIndex = null;
      _currentIndex = nextIndex;
      _playIntent = true;
      _recordedPlay = false;
      _lastPlayedSeconds = -1;
      _pendingListeningSeconds = 0;
      mediaItem.add(_mediaItem(nextSong));
      _broadcastState();

      _recordPlay(nextSong);
      unawaited(_addHistory(nextSong));

      try {
        await _session.setActive(true);
        await old.setVolume(1);
        await _active.setVolume(0);
        await _active.play();
        _emitPlaying(true);
        _positionController.add(_active.position);
        _emitDuration(_active.duration);
        _broadcastState();
        final fadeMs = _crossfadeDuration.inMilliseconds.clamp(800, 12000);
        const step = 60;
        var elapsed = 0;
        _fadeTimer?.cancel();
        _fadeTimer = Timer.periodic(const Duration(milliseconds: step), (
          timer,
        ) {
          elapsed += step;
          final progress = (elapsed / fadeMs).clamp(0.0, 1.0);
          unawaited(_active.setVolume(progress).catchError((_) {}));
          unawaited(old.setVolume(1 - progress).catchError((_) {}));
          if (progress >= 1) {
            timer.cancel();
            unawaited(_finishCrossfade());
          }
        });
        unawaited(_persistSession());
      } catch (error) {
        await _finishCrossfade();
        _publishPlaybackError(error);
      }
    } finally {
      _startingCrossfade = false;
    }
  }

  Future<void> _finishCrossfade() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final fading = _fadingPlayer;
    _fadingPlayer = null;
    if (fading != null) {
      try {
        await fading.stop();
        await fading.setVolume(1);
      } catch (_) {}
    }
    try {
      await _active.setVolume(1);
    } catch (_) {}
    _crossfading = false;
    _emitPlaying(_active.playing);
    _broadcastState();
    unawaited(_prefetchUpcoming());
  }

  void _cancelCrossfade({required bool stopFading}) {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final fading = _fadingPlayer;
    _fadingPlayer = null;
    _crossfading = false;
    if (stopFading && fading != null) {
      unawaited(fading.stop().catchError((_) {}));
      unawaited(fading.setVolume(1).catchError((_) {}));
    }
    unawaited(_active.setVolume(1).catchError((_) {}));
    _preparedNextIndex = null;
  }

  bool get _crossfadeEnabled => _crossfadeEnabledCache;

  Duration get _crossfadeDuration => _crossfadeDurationCache;

  // ---------------------------------------------------------------------------
  // Ticker: estadísticas, sesión y crossfade
  // ---------------------------------------------------------------------------

  void _onTick() {
    if (_currentIndex < 0) return;
    if (_active.playing && !_needsLoad) {
      final seconds = _active.position.inSeconds;
      if (_lastPlayedSeconds >= 0 && seconds > _lastPlayedSeconds) {
        final delta = seconds - _lastPlayedSeconds;
        if (delta <= 3) _pendingListeningSeconds += delta;
      }
      _lastPlayedSeconds = seconds;
      if (_pendingListeningSeconds >= 10) {
        unawaited(_flushListening());
      }
      final second = seconds;
      if (second != _lastSavedSecond && second % 10 == 0) {
        _lastSavedSecond = second;
        _persistSession();
      }
      unawaited(_maybePrepareCrossfade());
      unawaited(_maybeStartCrossfade());
    }
  }

  Future<void> _flushListening() async {
    final seconds = _pendingListeningSeconds;
    if (seconds <= 0) return;
    _pendingListeningSeconds = 0;
    final song = currentSong;
    if (song == null) return;
    try {
      await stats?.addListening(song, seconds);
    } catch (_) {
      // Las estadísticas nunca deben interrumpir la reproducción.
    }
  }

  void _recordPlay(SongModel song) {
    final service = stats;
    if (service == null) return;
    unawaited(service.recordPlay(song).catchError((_) {}));
  }

  // ---------------------------------------------------------------------------
  // API pública de reproducción
  // ---------------------------------------------------------------------------

  Future<void> playSongs(
    List<SongModel> songs, {
    int startIndex = 0,
    required bool shuffle,
  }) async {
    if (songs.isEmpty) return;
    unawaited(_flushListening());
    final safeIndex = startIndex.clamp(0, songs.length - 1);
    final selected = songs[safeIndex];
    final list = List<SongModel>.of(songs);
    if (shuffle) {
      list.remove(selected);
      list.shuffle(math.Random());
      list.insert(0, selected);
      _currentIndex = 0;
      _shuffleMode = AudioServiceShuffleMode.all;
    } else {
      _currentIndex = safeIndex;
      _shuffleMode = AudioServiceShuffleMode.none;
    }
    _queueSongs
      ..clear()
      ..addAll(list);
    _emitQueue();
    _recordedPlay = false;
    await _loadCurrent(autoPlay: true);
    if (_errorMessage == null && currentSong != null) {
      unawaited(_ensureSmartQueue(currentSong!, force: true));
    }
  }

  Future<void> addSongToQueue(SongModel song) async {
    _queueSongs.add(song);
    _emitQueue();
    if (_currentIndex < 0) {
      _currentIndex = _queueSongs.length - 1;
      await _loadCurrent(autoPlay: true);
      if (_errorMessage == null && currentSong != null) {
        unawaited(_ensureSmartQueue(currentSong!, force: true));
      }
    } else {
      _persistSession();
    }
  }

  Future<void> playSongNext(SongModel song) async {
    if (_currentIndex < 0 || _queueSongs.isEmpty) {
      await addSongToQueue(song);
      return;
    }
    _queueSongs.insert(_currentIndex + 1, song);
    _preparedNextIndex = null;
    _cancelCrossfade(stopFading: true);
    _emitQueue();
    _persistSession();
  }

  Future<void> addSongsToQueue(List<SongModel> songs) async {
    for (final song in songs) {
      _queueSongs.add(song);
    }
    _emitQueue();
    if (_currentIndex < 0 && _queueSongs.isNotEmpty) {
      _currentIndex = 0;
      await _loadCurrent(autoPlay: false);
    } else {
      _persistSession();
    }
  }

  Future<void> removeSongFromQueue(int index) async {
    if (index < 0 || index >= _queueSongs.length) return;
    if (index == _currentIndex) {
      if (_queueSongs.length == 1) {
        await stop();
        _queueSongs.clear();
        _currentIndex = -1;
        await _clearPersistedSession();
        _emitQueue();
        mediaItem.add(null);
        return;
      }
      final wasPlaying = _shouldKeepPlaying;
      _cancelCrossfade(stopFading: true);
      _queueSongs.removeAt(index);
      if (index >= _queueSongs.length) {
        _currentIndex = _queueSongs.length - 1;
      } else {
        _currentIndex = index;
      }
      _emitQueue();
      await _loadCurrent(autoPlay: wasPlaying);
      return;
    }
    _queueSongs.removeAt(index);
    if (index < _currentIndex) _currentIndex--;
    _preparedNextIndex = null;
    _emitQueue();
    _persistSession();
  }

  Future<void> moveSongInQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queueSongs.length ||
        newIndex < 0 ||
        newIndex > _queueSongs.length) {
      return;
    }
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex) return;
    final song = _queueSongs.removeAt(oldIndex);
    _queueSongs.insert(newIndex, song);
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    _preparedNextIndex = null;
    _cancelCrossfade(stopFading: true);
    _emitQueue();
    _persistSession();
  }

  Future<void> clearUpcomingQueue() async {
    if (_currentIndex < 0 || _currentIndex >= _queueSongs.length - 1) return;
    _queueSongs.removeRange(_currentIndex + 1, _queueSongs.length);
    _preparedNextIndex = null;
    _cancelCrossfade(stopFading: true);
    _emitQueue();
    _persistSession();
  }

  Future<void> clearQueue() async {
    await stop();
    _queueSongs.clear();
    _currentIndex = -1;
    _preparedNextIndex = null;
    _emitQueue();
    mediaItem.add(null);
    await _clearPersistedSession();
  }

  Future<void> retryCurrent() async {
    if (_currentIndex < 0) return;
    final position = _active.position;
    _needsLoad = true;
    _resumePosition = position;
    repository.invalidateStream(_queueSongs[_currentIndex].id);
    await _loadCurrent(autoPlay: true, position: position);
  }

  void _emitQueue() {
    _sessionQueueDirty = true;
    queue.add(_queueSongs.map(_mediaItem).toList());
    _broadcastState();
  }

  // ---------------------------------------------------------------------------
  // Sesión persistente
  // ---------------------------------------------------------------------------

  Future<void> _persistSession({bool force = false}) {
    final next = _sessionWrite.then((_) => _persistSessionNow(force: force));
    _sessionWrite = next.catchError((_) {});
    return next;
  }

  Future<void> _persistSessionNow({bool force = false}) async {
    if (_queueSongs.isEmpty || _currentIndex < 0) return;
    final position = _needsLoad ? _resumePosition : _active.position;
    final positionMs = position.inMilliseconds;
    final index = _currentIndex;
    if (!force &&
        _lastPersistedIndex == index &&
        _lastPersistedPositionMs == positionMs) {
      return;
    }
    final writeId = _sessionWriteId;
    try {
      // La cola solo se serializa cuando cambia. Los guardados periódicos
      // escriben únicamente índice/posición, mucho más barato que reescribir
      // toda la cola cada 10 segundos.
      if (_sessionQueueDirty || _sessionQueueJson == null) {
        final queueJson = _queueSongs
            .map((song) => song.toJson())
            .toList(growable: false);
        _sessionQueueJson = queueJson;
        _sessionQueueDirty = false;
        if (writeId != _sessionWriteId) return;
        await _settings.put('playbackSessionQueue', {'queue': queueJson});
      }
      if (writeId != _sessionWriteId) return;
      await _settings.put('playbackSessionState', {
        'index': index,
        'positionMs': positionMs,
        'savedAt': DateTime.now().toIso8601String(),
      });
      _lastPersistedIndex = index;
      _lastPersistedPositionMs = positionMs;
      if (_settings.containsKey('playbackSession')) {
        await _settings.delete('playbackSession');
      }
    } catch (_) {
      // Si falló la escritura, el siguiente guardado debe reintentar la cola.
      _sessionQueueDirty = true;
      _lastPersistedIndex = null;
      _lastPersistedPositionMs = null;
    }
  }

  Future<void> _clearPersistedSession() {
    final next = _sessionWrite.then((_) => _clearPersistedSessionNow());
    _sessionWrite = next.catchError((_) {});
    return next;
  }

  Future<void> _clearPersistedSessionNow() async {
    _sessionWriteId++;
    _sessionQueueJson = null;
    _sessionQueueDirty = true;
    _lastPersistedIndex = null;
    _lastPersistedPositionMs = null;
    try {
      await _settings.delete('playbackSessionQueue');
      await _settings.delete('playbackSessionState');
      await _settings.delete('playbackSession');
    } catch (_) {}
  }

  Future<void> restoreSession() async {
    if (_queueSongs.isNotEmpty) return;

    List? list;
    var index = 0;
    var positionMs = 0;
    var legacy = false;
    final queueRaw = _settings.get('playbackSessionQueue');
    final stateRaw = _settings.get('playbackSessionState');
    if (queueRaw is Map && queueRaw['queue'] is List) {
      list = queueRaw['queue'] as List;
      if (stateRaw is Map) {
        index = (stateRaw['index'] as num?)?.toInt() ?? 0;
        positionMs = (stateRaw['positionMs'] as num?)?.toInt() ?? 0;
      }
    } else {
      final raw = _settings.get('playbackSession');
      if (raw is! Map || raw['queue'] is! List) return;
      list = raw['queue'] as List;
      index = (raw['index'] as num?)?.toInt() ?? 0;
      positionMs = (raw['positionMs'] as num?)?.toInt() ?? 0;
      legacy = true;
    }

    final songs = list
        .whereType<Map>()
        .map((entry) {
          try {
            return SongModel.fromJson(Map<String, dynamic>.from(entry));
          } catch (_) {
            return null;
          }
        })
        .whereType<SongModel>()
        .toList();
    if (songs.isEmpty) return;
    index = index.clamp(0, songs.length - 1);
    _queueSongs
      ..clear()
      ..addAll(songs);
    _currentIndex = index;
    _resumePosition = Duration(milliseconds: positionMs);
    _needsLoad = true;
    _restoredSession = true;
    _playIntent = false;
    _errorMessage = null;
    _sessionQueueJson = songs
        .map((song) => song.toJson())
        .toList(growable: false);
    _sessionQueueDirty = legacy;
    _lastPersistedIndex = index;
    _lastPersistedPositionMs = positionMs;
    _lastStateSignature = '';
    mediaItem.add(_mediaItem(songs[index]));
    queue.add(songs.map(_mediaItem).toList());
    _positionController.add(_resumePosition);
    _emitDuration(songs[index].duration);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.ready,
        playing: false,
        updatePosition: _resumePosition,
        queueIndex: index,
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Implementación de AudioService
  // ---------------------------------------------------------------------------

  @override
  Future<void> play() async => _startPlayback(recordPlay: false);

  @override
  Future<void> pause() => _pauseInternal();

  Future<void> _pauseInternal({bool fromInterruption = false}) async {
    _playIntent = false;
    _cancelCrossfade(stopFading: true);
    await _active.pause();
    _emitPlaying(false);
    _broadcastState();
    if (!fromInterruption) {
      unawaited(() async {
        try {
          await _session.setActive(false);
        } catch (_) {}
      }());
    }
    unawaited(_flushListening());
    unawaited(_persistSession(force: true));
  }

  @override
  Future<void> stop() async {
    _playRequestId++;
    _playIntent = false;
    _isResolvingStream = false;
    if (!_needsLoad) _resumePosition = _active.position;
    _needsLoad = true;
    _cancelCrossfade(stopFading: true);
    await _active.stop();
    _emitPlaying(false);
    _broadcastState();
    unawaited(() async {
      try {
        await _session.setActive(false);
      } catch (_) {}
    }());
    unawaited(_flushListening());
    await _persistSession(force: true);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    _cancelCrossfade(stopFading: true);
    if (_needsLoad) {
      _resumePosition = position;
      _positionController.add(position);
      _broadcastState(force: true);
      return;
    }
    await _active.seek(position);
    _positionController.add(position);
    _broadcastState(force: true);
  }

  @override
  Future<void> skipToNext() async {
    if (_queueSongs.isEmpty || _currentIndex < 0) return;
    _cancelCrossfade(stopFading: true);
    unawaited(_flushListening());
    if (_currentIndex < _queueSongs.length - 1) {
      _currentIndex++;
      await _loadCurrent(autoPlay: _shouldKeepPlaying);
    } else if (_repeatMode == AudioServiceRepeatMode.all) {
      _currentIndex = 0;
      await _loadCurrent(autoPlay: _shouldKeepPlaying);
    } else if (autoPlayRelated && currentSong != null) {
      final added = await _ensureSmartQueue(currentSong!, force: true);
      if (added) {
        _currentIndex++;
        await _loadCurrent(autoPlay: _shouldKeepPlaying);
      }
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queueSongs.isEmpty || _currentIndex < 0) return;
    if (!_needsLoad && _active.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    _cancelCrossfade(stopFading: true);
    unawaited(_flushListening());
    if (_currentIndex > 0) {
      _currentIndex--;
    } else if (_repeatMode == AudioServiceRepeatMode.all) {
      _currentIndex = _queueSongs.length - 1;
    } else {
      await seek(Duration.zero);
      return;
    }
    await _loadCurrent(autoPlay: _shouldKeepPlaying);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queueSongs.length) return;
    _cancelCrossfade(stopFading: true);
    unawaited(_flushListening());
    _currentIndex = index;
    await _loadCurrent(autoPlay: true);
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final song = _songFromMediaItem(mediaItem);
    if (song != null) await addSongToQueue(song);
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    final songs = mediaItems
        .map(_songFromMediaItem)
        .whereType<SongModel>()
        .toList();
    if (songs.isNotEmpty) await addSongsToQueue(songs);
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = _queueSongs.indexWhere((song) => song.id == mediaItem.id);
    if (index >= 0) await removeSongFromQueue(index);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    await removeSongFromQueue(index);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleMode = shuffleMode;
    if (shuffleMode == AudioServiceShuffleMode.all &&
        _currentIndex >= 0 &&
        _currentIndex < _queueSongs.length - 1) {
      final upcoming = _queueSongs.sublist(_currentIndex + 1)..shuffle();
      for (var i = 0; i < upcoming.length; i++) {
        _queueSongs[_currentIndex + 1 + i] = upcoming[i];
      }
      _preparedNextIndex = null;
      _cancelCrossfade(stopFading: true);
      _emitQueue();
      _persistSession();
    }
    _broadcastState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    _broadcastState();
  }

  @override
  Future<void> onTaskRemoved() async {
    unawaited(_flushListening());
    await _persistSession(force: true);
    await super.onTaskRemoved();
  }

  Future<void> openDownloadedSong(
    SongModel song, {
    List<SongModel>? queue,
    int index = 0,
  }) => playSongs(queue ?? [song], startIndex: index, shuffle: false);

  Future<void> dispose() async {
    _stopTicker();
    _fadeTimer?.cancel();
    await _settingsSubscription?.cancel();
    await _interruptionSubscription?.cancel();
    await _noisySubscription?.cancel();
    await _devicesSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    unawaited(_flushListening());
    await _persistSession(force: true);
    for (final player in _players) {
      await player.dispose();
    }
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _historyChanges.close();
    await _devicesController.close();
  }
}
