import 'dart:async';
import 'dart:math' as math;

// `AudioDeviceType` sigue marcado como experimental en audio_session, pero es
// la única API multiplataforma para detectar auriculares Bluetooth/USB.
// ignore_for_file: experimental_member_use

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song_model.dart';
import '../repositories/music_repository.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/artwork_url.dart';
import '../../core/utils/song_variant_utils.dart';
import 'download_service.dart';
import 'listening_stats_service.dart';
import 'smart_queue_service.dart';
import 'idle_stop_timer.dart';
import 'connectivity_gate.dart';
import 'session_store.dart';
import 'listening_tracker.dart';

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
    this.favorites,
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
    _sessionStore = SessionStore(_settings);
    _listeningTracker = ListeningTracker(stats);
    _idleStopTimer = IdleStopTimer(() {
      if (!_active.playing && !_playIntent) unawaited(stop());
    });
    _connectivityGate = ConnectivityGate();
    _connectivitySubscription = _connectivityGate.changes.listen((online) {
      _online = online;
    });
    unawaited(_connectivityGate.refresh().then((online) => _online = online));
    smartQueueService = SmartQueueService(
      repository: repository,
      stats: stats,
      history: history,
      favorites: favorites,
    );
    for (final player in _players) {
      _bindPlayer(player);
    }
    _listenAudioSession();
    _reloadCrossfadeSettings();
    _reloadPlaybackSpeed();
    // El ticker solo arranca cuando hay reproducción activa (ver _emitPlaying).
    _settingsSubscription = _settings.watch().listen((event) {
      if (event.key == AppConstants.crossfadeEnabledKey ||
          event.key == AppConstants.crossfadeSecondsKey) {
        _reloadCrossfadeSettings();
      }
      if (event.key == AppConstants.playbackSpeedKey) {
        _reloadPlaybackSpeed();
      }
      if (event.key == 'idleStopMinutes' && !_active.playing && !_playIntent) {
        _startIdleStopTimer();
      }
    });
    _favoritesSubscription = favorites?.watch().listen((event) {
      if (event.key == currentSong?.id) _broadcastState(force: true);
    });
  }

  void _reloadPlaybackSpeed() {
    final saved = _settings.get(AppConstants.playbackSpeedKey);
    final value = (saved is num ? saved.toDouble() : 1.0).clamp(0.5, 2.0);
    if ((_speed - value).abs() > 0.0001) {
      _speed = value;
      for (final player in _players) {
        unawaited(player.setSpeed(value));
      }
    }
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
    _ticker = Timer.periodic(
      const Duration(milliseconds: 750),
      (_) => _onTick(),
    );
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
  final Box? favorites;
  late final SmartQueueService smartQueueService;
  late final ConnectivityGate _connectivityGate;
  late final SessionStore _sessionStore;
  late final ListeningTracker _listeningTracker;

  final List<AudioPlayer> _players;
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];
  late AudioPlayer _active;
  late AudioPlayer _standby;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _historyChanges = StreamController<void>.broadcast();
  final _playbackNotices = StreamController<String>.broadcast();
  final _devicesController = StreamController<Set<AudioDevice>>.broadcast();

  final List<SongModel> _queueSongs = [];
  List<SongModel>? _shuffleOriginalOrder;
  int _currentIndex = -1;
  int? _smartQueueStartIndex;
  int _playRequestId = 0;
  bool _isResolvingStream = false;
  bool _needsLoad = false;
  bool _restoredSession = false;
  Duration _resumePosition = Duration.zero;
  int _lastSavedSecond = -1;
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
  late final IdleStopTimer _idleStopTimer;
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
  StreamSubscription? _favoritesSubscription;
  bool? _online;
  bool? _lastPlayingEmitted;
  Duration? _lastDurationEmitted;
  String _lastStateSignature = '';
  DateTime _lastStateAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Caché de los valores de crossfade para no leer Hive en cada tick.
  bool _crossfadeEnabledCache = false;
  Duration _crossfadeDurationCache = const Duration(seconds: 3);

  /// Velocidad de reproducción actual (1.0 por defecto).
  double _speed = 1.0;

  /// Velocidad de reproducción actual, expuesta a la UI.
  double get speed => _speed;

  // La cola serializada se reutiliza entre guardados periódicos; solo se
  // reescribe cuando la cola cambia de verdad.

  bool get isResolvingStream => _isResolvingStream;
  bool get hasRestoredSession => _restoredSession;
  int get currentIndex => _currentIndex;
  int? get smartQueueStartIndex => _smartQueueStartIndex;
  SongModel? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _queueSongs.length
      ? _queueSongs[_currentIndex]
      : null;
  List<SongModel> get queueSongs => List.unmodifiable(_queueSongs);
  bool get hasNext =>
      _currentIndex >= 0 &&
      (_nextPlayableIndex() != null ||
          _repeatMode == AudioServiceRepeatMode.all ||
          autoPlayRelated);
  bool get hasPrevious => _currentIndex > 0;

  /// Si al pulsar siguiente se usará la cola inteligente (autoPlayRelated).
  /// También es true cuando las siguientes pistas son solo covers/versiones de
  /// la canción actual y hay que buscar una canción distinta.
  bool get nextUsesSmartQueue =>
      autoPlayRelated &&
      _repeatMode != AudioServiceRepeatMode.all &&
      _currentIndex >= 0 &&
      currentSong != null &&
      _nextPlayableIndex() == null;
  double get currentVolume => _active.volume;

  /// Siguiente pista que no sea la misma canción ni una versión/cover de ella.
  /// Devuelve null cuando la cola solo tiene variantes de la canción actual.
  int? _nextPlayableIndex({int? start}) {
    final reference = currentSong;
    if (reference == null || _queueSongs.isEmpty) return null;
    final from = start ?? _currentIndex + 1;
    for (var index = from; index < _queueSongs.length; index++) {
      final candidate = _queueSongs[index];
      if (candidate.id == reference.id) continue;
      // Las versiones descargadas son elementos explícitos de la cola; no se
      // deben descartar al avanzar.
      if (_offlineNow && !_canResolveOffline(candidate)) continue;
      return index;
    }
    return null;
  }

  bool _canResolveOffline(SongModel song) =>
      downloads?.fileFor(song.id) != null ||
      repository.audioCache?.cachedFile(song.id) != null;

  bool get _offlineNow =>
      _settings.get('offlineMode', defaultValue: false) == true ||
      _online == false;

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
  Stream<String> get playbackNotices => _playbackNotices.stream;
  Stream<Set<AudioDevice>> get devicesStream async* {
    yield Set.unmodifiable(_lastDevices);
    yield* _devicesController.stream;
  }

  AudioPlayer get player => _active;

  /// Establece la velocidad de reproducción, la persiste y la aplica a ambos
  /// players (activo y de crossfade).
  Future<void> setPlaybackSpeed(double speed) async {
    final clamped = speed.clamp(0.5, 2.0);
    if ((_speed - clamped).abs() < 0.0001) return;
    _speed = clamped;
    await _settings.put(AppConstants.playbackSpeedKey, clamped);
    for (final player in _players) {
      await player.setSpeed(clamped);
    }
    _broadcastState();
  }

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
    _playerSubscriptions.add(
      player.positionStream.listen((position) {
        if (identical(player, _active)) _positionController.add(position);
      }),
    );
    _playerSubscriptions.add(
      player.durationStream.listen((duration) {
        if (identical(player, _active)) _emitDuration(duration);
      }),
    );
    _playerSubscriptions.add(
      player.playingStream.listen((playing) {
        if (identical(player, _active) && !_crossfading) {
          _emitPlaying(playing);
        }
        if (identical(player, _active)) _broadcastState();
      }),
    );
    _playerSubscriptions.add(
      player.playbackEventStream.listen(
        (_) {
          if (identical(player, _active)) _broadcastState();
        },
        onError: (Object error, StackTrace _) {
          if (identical(player, _active)) _publishPlaybackError(error);
        },
      ),
    );
    _playerSubscriptions.add(
      player.processingStateStream.listen((state) {
        if (!identical(player, _active)) return;
        if (state == ProcessingState.completed) _onCompleted();
        _broadcastState();
      }),
    );
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
          MediaControl.custom(
            androidIcon: _shuffleMode == AudioServiceShuffleMode.all
                ? 'drawable/ic_shuffle_on'
                : 'drawable/ic_shuffle',
            label: 'Aleatorio',
            name: 'toggleShuffle',
          ),
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.custom(
            androidIcon: _isFavorite(currentSong)
                ? 'drawable/ic_favorite'
                : 'drawable/ic_favorite_border',
            label: _isFavorite(currentSong)
                ? 'Quitar de favoritos'
                : 'Añadir a favoritos',
            name: 'toggleFavorite',
          ),
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [1, 2, 3],
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

  bool _isFavorite(SongModel? song) =>
      song != null && (favorites?.containsKey(song.id) ?? false);

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case 'toggleShuffle':
        await setShuffleMode(
          _shuffleMode == AudioServiceShuffleMode.all
              ? AudioServiceShuffleMode.none
              : AudioServiceShuffleMode.all,
        );
      case 'toggleFavorite':
        final song = currentSong;
        final box = favorites;
        if (song != null && box != null) {
          if (box.containsKey(song.id)) {
            await box.delete(song.id);
          } else {
            await box.put(song.id, song.toJson());
          }
          _broadcastState(force: true);
        }
    }
    return null;
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

  // ---------------------------------------------------------------------------
  // Carga y reproducción
  // ---------------------------------------------------------------------------

  Future<bool> _refreshConnectivity() async {
    final online = await _connectivityGate.refresh();
    _online = online;
    return online;
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
    if (downloads?.isDownloaded(song.id) == true) {
      await downloads?.delete(song.id);
      throw _PlaybackFailure(
        'La descarga de “${song.title}” está dañada o incompleta y se eliminó.',
      );
    }
    final cached = repository.audioCache?.cachedFile(song.id);
    if (cached != null) {
      return AudioSource.file(cached.path, tag: _mediaItem(song));
    }

    final offline = _settings.get('offlineMode', defaultValue: false) == true;
    if (offline || _online == false) {
      throw const _PlaybackFailure(
        'Modo offline activo. Esta canción no está descargada.',
      );
    }
    if (!allowNetwork) {
      throw const _PlaybackFailure(
        'Esta canción no está disponible sin conexión.',
      );
    }
    if (!await _refreshConnectivity()) throw const _NoConnection();

    // Aunque se prueben varias calidades, el usuario no debe esperar más de
    // ~25 s en total. Si la red está caída, se muestra el error y se permite
    // reintentar en lugar de encadenar esperas por cada calidad.
    final deadline = DateTime.now().add(const Duration(seconds: 26));
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
      } on _NoConnection {
        rethrow;
      }
      if (uri != null) {
        return AudioSource.uri(uri, tag: _mediaItem(song));
      }
    }
    throw const _PlaybackFailure(
      'No se pudo reproducir esta canción. Inténtalo de nuevo.',
    );
  }

  Future<void> _loadCurrent({
    required bool autoPlay,
    Duration? position,
    int failureDepth = 0,
  }) async {
    if (_currentIndex < 0 || _currentIndex >= _queueSongs.length) return;
    _idleStopTimer.cancel();
    final song = _queueSongs[_currentIndex];
    final downloadedFile = downloads?.fileFor(song.id);
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
        await _active
            .setAudioSource(source)
            .timeout(
              downloads?.fileFor(song.id) != null
                  ? const Duration(seconds: 12)
                  : const Duration(seconds: 30),
            );
        await _active.setSpeed(_speed);
        await _standby.setSpeed(_speed);
      } catch (error) {
        if (downloadedFile != null) rethrow;
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
        await _active
            .setAudioSource(retry)
            .timeout(const Duration(seconds: 30));
        await _active.setSpeed(_speed);
        await _standby.setSpeed(_speed);
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
      _listeningTracker.beginSong();
      _broadcastState();
      if (autoPlay && _playIntent) {
        await _startPlayback(recordPlay: true);
      } else {
        _emitPlaying(false);
        _startIdleStopTimer();
      }
      unawaited(_persistSession());
      unawaited(_prefetchUpcoming());
    } catch (error) {
      if (requestId != _playRequestId) return;
      await _active.stop().catchError((_) {});
      if (downloadedFile != null) {
        await downloads?.delete(song.id);
      }
      if (failureDepth < 2) {
        final next = _nextPlayableIndex(start: _currentIndex + 1);
        if (next != null) {
          _playbackNotices.add(
            downloadedFile != null
                ? 'La descarga de “${song.title}” está dañada; se eliminó y se continúa.'
                : 'No se pudo reproducir “${song.title}”; se continúa con la siguiente.',
          );
          _currentIndex = next;
          _emitQueue();
          await _loadCurrent(
            autoPlay: autoPlay,
            failureDepth: failureDepth + 1,
          );
          return;
        }
      }
      _publishPlaybackError(
        error,
        message: downloadedFile != null
            ? 'La descarga de “${song.title}” está dañada y se eliminó.'
            : null,
      );
    }
  }

  Future<void> _startPlayback({bool recordPlay = false}) async {
    if (_currentIndex < 0 || _currentIndex >= _queueSongs.length) return;
    _playIntent = true;
    _idleStopTimer.cancel();
    if (_needsLoad) {
      await _loadCurrent(autoPlay: true, position: _resumePosition);
      return;
    }
    _errorMessage = null;
    if (_active.processingState == ProcessingState.completed) {
      await _active.seek(Duration.zero);
      _listeningTracker.beginSong();
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
      if (recordPlay) {
        final song = currentSong;
        if (song != null) {
          final alreadyRecorded = _listeningTracker.recordedPlay;
          _listeningTracker.recordPlay(song);
          if (!alreadyRecorded) unawaited(_addHistory(song));
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
      while (box.length > AppConstants.maxHistory) {
        await box.deleteAt(0);
      }
      _historyChanges.add(null);
    } catch (_) {}
  }

  /// Resuelve en segundo plano el stream de las siguientes canciones.
  Future<void> _prefetchUpcoming() async {
    if (_currentIndex < 0) return;
    final cache = repository.audioCache;
    if (cache == null ||
        _offlineNow ||
        _settings.get('prefetchAudio', defaultValue: false) != true) {
      return;
    }
    await _refreshConnectivity();
    if (_online != true || !_connectivityGate.canPrefetch) return;
    final requestId = _playRequestId;
    final current = currentSong;
    try {
      for (
        var offset = 1;
        offset <= 2 && _currentIndex + offset < _queueSongs.length;
        offset++
      ) {
        final song = _queueSongs[_currentIndex + offset];
        if (current != null && isSameSongVariant(song, current)) continue;
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
    await _refreshConnectivity();
    unawaited(_flushListening());
    unawaited(_persistSession(force: true));
    if (_repeatMode == AudioServiceRepeatMode.one) {
      await _active.seek(Duration.zero);
      await _startPlayback(recordPlay: true);
      return;
    }
    final nextIndex = _nextPlayableIndex();
    if (nextIndex != null) {
      _currentIndex = nextIndex;
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
        final smartNext = _nextPlayableIndex();
        if (smartNext != null) {
          _currentIndex = smartNext;
          await _loadCurrent(autoPlay: true);
          return;
        }
      }
    }
    _playIntent = false;
    _emitPlaying(false);
    _broadcastState();
    _startIdleStopTimer();
  }

  /// Añade una cola inteligente (álbum + relacionadas + artista) sin cortar
  /// la reproducción. Si una fuente falla, las demás siguen aportando.
  Future<bool> _ensureSmartQueue(SongModel seed, {bool force = false}) async {
    if (!autoPlayRelated || seed.id.isEmpty) return false;
    if (!force && _lastEnrichedSeedId == seed.id) return false;
    if (_queueEnrichment != null) return false;
    if (_offlineNow || !await _refreshConnectivity()) return false;

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
    try {
      final unique = await smartQueueService.recommendations(
        seed: seed,
        queuedSongs: List<SongModel>.of(_queueSongs),
      );
      if (requestId != _playRequestId) return false;
      if (unique.isEmpty) {
        _lastEnrichedSeedId = seed.id;
        return false;
      }

      _smartQueueStartIndex ??= _queueSongs.length;
      _queueSongs.addAll(unique);
      _lastEnrichedSeedId = seed.id;
      _emitQueue();
      unawaited(_persistSession());
      unawaited(_prefetchUpcoming());
      return true;
    } catch (_) {
      // Las recomendaciones nunca deben romper la reproducción actual.
      if (requestId == _playRequestId) _lastEnrichedSeedId = seed.id;
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
    final current = currentSong;
    if (current != null &&
        (_queueSongs[nextIndex].id == current.id ||
            isSameSongVariant(_queueSongs[nextIndex], current))) {
      _preparedNextIndex = null;
      return;
    }
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
      _listeningTracker.beginSong();
      mediaItem.add(_mediaItem(nextSong));
      _broadcastState();

      _listeningTracker.recordPlay(nextSong);
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
    final remainingSongs = _queueSongs.length - _currentIndex - 1;
    final seed = currentSong;
    if (remainingSongs <= 3 && seed != null) {
      unawaited(_ensureSmartQueue(seed));
    }
    if (_active.playing && !_needsLoad) {
      final seconds = _active.position.inSeconds;
      _listeningTracker.tick(currentSong, seconds);
      final second = seconds;
      if (second != _lastSavedSecond && second % 10 == 0) {
        _lastSavedSecond = second;
        _persistSession();
      }
      unawaited(_maybePrepareCrossfade());
      unawaited(_maybeStartCrossfade());
    }
  }

  Future<void> _flushListening() => _listeningTracker.flush(currentSong);

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
      _shuffleOriginalOrder = List<SongModel>.of(songs);
      list.remove(selected);
      list.shuffle(math.Random());
      list.insert(0, selected);
      _currentIndex = 0;
      _shuffleMode = AudioServiceShuffleMode.all;
    } else {
      _shuffleOriginalOrder = null;
      _currentIndex = safeIndex;
      _shuffleMode = AudioServiceShuffleMode.none;
    }
    _queueSongs
      ..clear()
      ..addAll(list);
    _smartQueueStartIndex = null;
    _emitQueue();
    _listeningTracker.beginSong();
    await _loadCurrent(autoPlay: true);
    if (_errorMessage == null && currentSong != null) {
      unawaited(_ensureSmartQueue(currentSong!, force: true));
    }
  }

  Future<void> addSongToQueue(SongModel song) async {
    final insertionIndex = _smartQueueStartIndex ?? _queueSongs.length;
    _queueSongs.insert(insertionIndex, song);
    if (_smartQueueStartIndex != null) {
      _smartQueueStartIndex = _smartQueueStartIndex! + 1;
    }
    _emitQueue();
    if (_currentIndex < 0) {
      _currentIndex = insertionIndex;
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
    if (_smartQueueStartIndex != null &&
        _smartQueueStartIndex! > _currentIndex) {
      _smartQueueStartIndex = _smartQueueStartIndex! + 1;
    }
    _preparedNextIndex = null;
    _cancelCrossfade(stopFading: true);
    _emitQueue();
    _persistSession();
  }

  Future<void> addSongsToQueue(List<SongModel> songs) async {
    if (songs.isEmpty) return;
    final insertionIndex = _smartQueueStartIndex ?? _queueSongs.length;
    _queueSongs.insertAll(insertionIndex, songs);
    if (_smartQueueStartIndex != null) {
      _smartQueueStartIndex = _smartQueueStartIndex! + songs.length;
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
      if (_smartQueueStartIndex != null && index < _smartQueueStartIndex!) {
        _smartQueueStartIndex = _smartQueueStartIndex! - 1;
      }
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
    if (_smartQueueStartIndex != null && index < _smartQueueStartIndex!) {
      _smartQueueStartIndex = _smartQueueStartIndex! - 1;
    }
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
    final smartStart = _smartQueueStartIndex;
    if (smartStart != null) {
      if (oldIndex < smartStart && newIndex >= smartStart) {
        _smartQueueStartIndex = smartStart - 1;
      } else if (oldIndex >= smartStart && newIndex < smartStart) {
        _smartQueueStartIndex = smartStart + 1;
      }
    }
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
    if (_smartQueueStartIndex != null &&
        _smartQueueStartIndex! > _currentIndex) {
      _smartQueueStartIndex = null;
    }
    _preparedNextIndex = null;
    _cancelCrossfade(stopFading: true);
    _emitQueue();
    _persistSession();
  }

  Future<void> clearQueue() async {
    await stop();
    _queueSongs.clear();
    _smartQueueStartIndex = null;
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
    _sessionStore.markQueueDirty();
    queue.add(_queueSongs.map(_mediaItem).toList());
    _broadcastState();
  }

  // ---------------------------------------------------------------------------
  // Sesión persistente
  // ---------------------------------------------------------------------------

  Future<void> _persistSession({bool force = false}) => _sessionStore.persist(
    songs: _queueSongs,
    index: _currentIndex,
    position: _needsLoad ? _resumePosition : _active.position,
    smartStartIndex: _smartQueueStartIndex,
    force: force,
  );

  Future<void> _clearPersistedSession() => _sessionStore.clear();

  Future<void> restoreSession() async {
    if (_queueSongs.isNotEmpty) return;
    final restored = _sessionStore.restore();
    if (restored == null) return;

    _queueSongs
      ..clear()
      ..addAll(restored.songs);
    _currentIndex = restored.index;
    _smartQueueStartIndex = restored.smartStartIndex;
    _resumePosition = restored.position;
    _needsLoad = true;
    _restoredSession = true;
    _playIntent = false;
    _errorMessage = null;
    _lastStateSignature = '';
    mediaItem.add(_mediaItem(restored.songs[restored.index]));
    queue.add(restored.songs.map(_mediaItem).toList());
    _positionController.add(_resumePosition);
    _emitDuration(restored.songs[restored.index].duration);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: _resumePosition,
        queueIndex: restored.index,
        controls: const [],
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
    _startIdleStopTimer();
  }

  void _startIdleStopTimer() {
    _idleStopTimer.cancel();
    final minutes = _settings.get('idleStopMinutes', defaultValue: 10);
    if (minutes is! int || minutes <= 0) return;
    _idleStopTimer.schedule(Duration(minutes: minutes));
  }

  @override
  Future<void> stop() async {
    _idleStopTimer.cancel();
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
    await _refreshConnectivity();
    _cancelCrossfade(stopFading: true);
    unawaited(_flushListening());
    final nextIndex = _nextPlayableIndex();
    if (nextIndex != null) {
      _currentIndex = nextIndex;
      await _loadCurrent(autoPlay: _shouldKeepPlaying);
    } else if (_repeatMode == AudioServiceRepeatMode.all) {
      _currentIndex = 0;
      await _loadCurrent(autoPlay: _shouldKeepPlaying);
    } else if (autoPlayRelated && currentSong != null) {
      final added = await _ensureSmartQueue(currentSong!, force: true);
      if (added) {
        final smartNext = _nextPlayableIndex();
        if (smartNext != null) {
          _currentIndex = smartNext;
          await _loadCurrent(autoPlay: _shouldKeepPlaying);
        }
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
    if (shuffleMode == _shuffleMode) return;
    if (shuffleMode == AudioServiceShuffleMode.all) {
      _shuffleOriginalOrder = List<SongModel>.of(_queueSongs);
    }
    _shuffleMode = shuffleMode;
    if (shuffleMode == AudioServiceShuffleMode.all &&
        _currentIndex >= 0 &&
        _currentIndex < _queueSongs.length - 1) {
      final marker = _smartQueueStartIndex;
      if (marker != null && marker > _currentIndex) {
        final regular = _queueSongs.sublist(_currentIndex + 1, marker)
          ..shuffle();
        for (var i = 0; i < regular.length; i++) {
          _queueSongs[_currentIndex + 1 + i] = regular[i];
        }
        final recommended = _queueSongs.sublist(marker)..shuffle();
        for (var i = 0; i < recommended.length; i++) {
          _queueSongs[marker + i] = recommended[i];
        }
      } else {
        final upcoming = _queueSongs.sublist(_currentIndex + 1)..shuffle();
        for (var i = 0; i < upcoming.length; i++) {
          _queueSongs[_currentIndex + 1 + i] = upcoming[i];
        }
      }
      _preparedNextIndex = null;
      _cancelCrossfade(stopFading: true);
      _emitQueue();
      _persistSession();
    } else if (shuffleMode != AudioServiceShuffleMode.all &&
        _shuffleOriginalOrder != null) {
      final current = currentSong;
      final originalIds = _shuffleOriginalOrder!.map((song) => song.id).toSet();
      final additions = _queueSongs
          .where((song) => !originalIds.contains(song.id))
          .toList();
      _queueSongs
        ..clear()
        ..addAll(_shuffleOriginalOrder!)
        ..addAll(additions);
      if (current != null) {
        final restoredIndex = _queueSongs.indexWhere(
          (song) => song.id == current.id,
        );
        if (restoredIndex >= 0) _currentIndex = restoredIndex;
      }
      _shuffleOriginalOrder = null;
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
    if (!_active.playing) {
      await stop();
    }
    await super.onTaskRemoved();
  }

  Future<void> openDownloadedSong(
    SongModel song, {
    List<SongModel>? queue,
    int index = 0,
  }) => playSongs(queue ?? [song], startIndex: index, shuffle: false);

  Future<void> dispose() async {
    _stopTicker();
    _idleStopTimer.dispose();
    _fadeTimer?.cancel();
    await _settingsSubscription?.cancel();
    await _favoritesSubscription?.cancel();
    await _interruptionSubscription?.cancel();
    await _noisySubscription?.cancel();
    await _devicesSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _connectivityGate.dispose();
    for (final subscription in _playerSubscriptions) {
      await subscription.cancel();
    }
    _playerSubscriptions.clear();
    unawaited(_flushListening());
    await _persistSession(force: true);
    for (final player in _players) {
      await player.dispose();
    }
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _historyChanges.close();
    await _playbackNotices.close();
    await _devicesController.close();
  }
}
