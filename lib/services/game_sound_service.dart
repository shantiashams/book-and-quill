import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/app_settings.dart';
import 'windows_media_session_bridge.dart';

enum GameSound {
  insert(<String>['assets/imported/sounds/insert.ogg']),
  pickup(<String>['assets/imported/sounds/pickup.ogg']),
  pageTurn(<String>[
    'assets/imported/sounds/page_turn1.ogg',
    'assets/imported/sounds/page_turn2.ogg',
    'assets/imported/sounds/page_turn3.ogg',
    'assets/imported/sounds/page_turn4.ogg',
    'assets/imported/sounds/page_turn5.ogg',
    'assets/imported/sounds/page_turn6.ogg',
    'assets/imported/sounds/page_turn7.ogg',
    'assets/imported/sounds/page_turn8.ogg',
    'assets/imported/sounds/page_turn.ogg',
  ]),
  click(<String>['assets/imported/sounds/click.ogg']);

  const GameSound(this.assetPaths);
  final List<String> assetPaths;
}

class MusicToastInfo {
  const MusicToastInfo({required this.title, required this.artist});

  final String title;
  final String artist;
}

class MusicPlaybackInfo {
  const MusicPlaybackInfo({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.position,
    required this.duration,
    required this.isPaused,
    this.artworkAssetPath,
    this.artworkBytes,
    this.isExternal = false,
    this.canPlay = true,
    this.canPause = true,
    this.canPrevious = true,
    this.canNext = true,
    this.canSeek = true,
  });

  final String trackId;
  final String title;
  final String artist;
  final String album;
  final Duration position;
  final Duration duration;
  final bool isPaused;
  final String? artworkAssetPath;
  final Uint8List? artworkBytes;
  final bool isExternal;
  final bool canPlay;
  final bool canPause;
  final bool canPrevious;
  final bool canNext;
  final bool canSeek;

  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) {
      return 0;
    }
    return (position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
  }
}

enum _MusicContext { overworld, nether, end }

class _MusicTrack {
  const _MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.assetPaths,
    this.album = 'Minecraft - Volume Alpha',
    this.artworkAssetPath =
        'assets/imported/textures/alpha_albume_cover.png',
    this.context = _MusicContext.overworld,
  });

  final String id;
  final String title;
  final String artist;
  final List<String> assetPaths;
  final String album;
  final String artworkAssetPath;
  final _MusicContext context;
}

class _SliderTickState {
  _SliderTickState(this.at, this.value);

  DateTime at;
  double value;
}

class GameSoundService {
  final SoLoud _engine = SoLoud.instance;
  final WindowsMediaSessionBridge _windowsMedia = WindowsMediaSessionBridge();
  final math.Random _random = math.Random();
  final Map<String, bool> _assetAvailability = <String, bool>{};
  final Map<String, AudioSource> _sources = <String, AudioSource>{};
  final Map<GameSound, String> _lastPlayedPath = <GameSound, String>{};
  final Map<String, _SliderTickState> _sliderTicks =
      <String, _SliderTickState>{};

  static const List<_MusicTrack> _musicTracks = <_MusicTrack>[
    _MusicTrack(
      id: 'minecraft',
      title: 'Minecraft',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_minecraft.ogg',
        'assets/imported/music/music_minecraft.ogg',
      ],
    ),
    _MusicTrack(
      id: 'clark',
      title: 'Clark',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_clark.ogg',
        'assets/imported/music/music_clark.ogg',
      ],
    ),
    _MusicTrack(
      id: 'sweden',
      title: 'Sweden',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_sweden.ogg',
        'assets/imported/music/music_sweden.ogg',
      ],
    ),
    _MusicTrack(
      id: 'subwoofer_lullaby',
      title: 'Subwoofer Lullaby',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_subwoofer_lullaby.ogg',
      ],
    ),
    _MusicTrack(
      id: 'living_mice',
      title: 'Living Mice',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_living_mice.ogg',
      ],
    ),
    _MusicTrack(
      id: 'haggstrom',
      title: 'Haggstrom',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_haggstrom.ogg',
      ],
    ),
    _MusicTrack(
      id: 'danny',
      title: 'Danny',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_danny.ogg',
      ],
    ),
    _MusicTrack(
      id: 'key',
      title: 'Key',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_key.ogg',
      ],
    ),
    _MusicTrack(
      id: 'oxygene',
      title: 'Oxygene',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_oxygene.ogg',
      ],
    ),
    _MusicTrack(
      id: 'dry_hands',
      title: 'Dry Hands',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_dry_hands.ogg',
      ],
    ),
    _MusicTrack(
      id: 'wet_hands',
      title: 'Wet Hands',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_wet_hands.ogg',
      ],
    ),
    _MusicTrack(
      id: 'mice_on_venus',
      title: 'Mice on Venus',
      artist: 'C418',
      assetPaths: <String>[
        'assets/imported/sounds/music_mice_on_venus.ogg',
      ],
    ),
    _MusicTrack(
      id: 'nether_concrete_halls',
      title: 'Concrete Halls',
      artist: 'C418',
      album: 'Minecraft - Volume Beta',
      artworkAssetPath:
          'assets/imported/textures/beta_albume_cover.png',
      context: _MusicContext.nether,
      assetPaths: <String>[
        'assets/imported/sounds/nether_concrete_halls.ogg',
      ],
    ),
    _MusicTrack(
      id: 'nether_dead_voxel',
      title: 'Dead Voxel',
      artist: 'C418',
      album: 'Minecraft - Volume Beta',
      artworkAssetPath:
          'assets/imported/textures/beta_albume_cover.png',
      context: _MusicContext.nether,
      assetPaths: <String>[
        'assets/imported/sounds/nether_dead_voxel.ogg',
      ],
    ),
    _MusicTrack(
      id: 'nether_warmth',
      title: 'Warmth',
      artist: 'C418',
      album: 'Minecraft - Volume Beta',
      artworkAssetPath:
          'assets/imported/textures/beta_albume_cover.png',
      context: _MusicContext.nether,
      assetPaths: <String>[
        'assets/imported/sounds/nether_warmth.ogg',
      ],
    ),
    _MusicTrack(
      id: 'nether_ballad_of_the_cats',
      title: 'Ballad of the Cats',
      artist: 'C418',
      album: 'Minecraft - Volume Beta',
      artworkAssetPath:
          'assets/imported/textures/beta_albume_cover.png',
      context: _MusicContext.nether,
      assetPaths: <String>[
        'assets/imported/sounds/nether_ballad_of_the_cats.ogg',
      ],
    ),
    _MusicTrack(
      id: 'nether_chrysopoeia',
      title: 'Chrysopoeia',
      artist: 'Lena Raine',
      album: 'Minecraft: Nether Update',
      artworkAssetPath: 'assets/imported/textures/book_item.png',
      context: _MusicContext.nether,
      assetPaths: <String>[
        'assets/imported/sounds/nether_chrysopoeia.ogg',
      ],
    ),
    _MusicTrack(
      id: 'nether_rubedo',
      title: 'Rubedo',
      artist: 'Lena Raine',
      album: 'Minecraft: Nether Update',
      artworkAssetPath: 'assets/imported/textures/book_item.png',
      context: _MusicContext.nether,
      assetPaths: <String>[
        'assets/imported/sounds/nether_rubedo.ogg',
      ],
    ),
    _MusicTrack(
      id: 'nether_so_below',
      title: 'So Below',
      artist: 'Lena Raine',
      album: 'Minecraft: Nether Update',
      artworkAssetPath: 'assets/imported/textures/book_item.png',
      context: _MusicContext.nether,
      assetPaths: <String>[
        'assets/imported/sounds/nether_so_below.ogg',
      ],
    ),
    _MusicTrack(
      id: 'end_the_end',
      title: 'The End',
      artist: 'C418',
      album: 'Minecraft - Volume Beta',
      artworkAssetPath:
          'assets/imported/textures/beta_albume_cover.png',
      context: _MusicContext.end,
      assetPaths: <String>[
        'assets/imported/sounds/end_the_end.ogg',
      ],
    ),
    _MusicTrack(
      id: 'end_alpha',
      title: 'Alpha',
      artist: 'C418',
      album: 'Minecraft - Volume Beta',
      artworkAssetPath:
          'assets/imported/textures/beta_albume_cover.png',
      assetPaths: <String>[
        'assets/imported/sounds/end_alpha.ogg',
      ],
    ),
  ];

  final ValueNotifier<MusicToastInfo?> musicToast =
      ValueNotifier<MusicToastInfo?>(null);
  final ValueNotifier<MusicPlaybackInfo?> musicPlayback =
      ValueNotifier<MusicPlaybackInfo?>(null);
  final ValueNotifier<bool> musicControlsEnabled =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> musicIslandEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> musicIslandAlwaysExpanded =
      ValueNotifier<bool>(false);

  Future<void>? _initialization;
  Timer? _musicTimer;
  Timer? _musicProgressTimer;
  Timer? _windowsMediaPollTimer;
  Timer? _windowsMediaRetryTimer;
  Timer? _externalProgressTimer;
  Timer? _toastTimer;
  dynamic _musicHandle;
  String? _lastMusicTrackId;
  _MusicTrack? _activeMusicTrack;
  Duration _activeMusicDuration = Duration.zero;
  MusicPlaybackInfo? _localMusicPlayback;
  MusicPlaybackInfo? _externalMusicPlayback;
  DateTime? _lastSystemMediaSync;
  String? _lastSystemMediaTrackId;
  bool? _lastSystemMediaPaused;
  DateTime? _externalProgressUpdatedAt;
  DateTime? _externalPauseIntentUntil;
  DateTime? _externalSeekIntentUntil;
  bool? _externalPauseIntent;
  Duration? _externalSeekOrigin;
  Duration? _externalSeekTarget;
  String? _externalIntentTrackId;
  String? _lastExternalSnapshotTrackId;
  Duration? _lastExternalSnapshotPosition;
  bool _windowsMediaPollRunning = false;
  int _windowsMediaRetryCount = 0;
  bool _musicPaused = false;
  bool _musicStartPending = false;
  bool _musicFinishing = false;
  int _musicGeneration = 0;
  final List<String> _musicHistory = <String>[];
  int _musicHistoryIndex = -1;
  _MusicContext _musicContext = _MusicContext.overworld;
  bool _initialized = false;
  bool _disposed = false;

  double masterVolume = AppSettings.defaults.masterVolume;
  double pageTurnVolume = AppSettings.defaults.pageTurnVolume;
  double clickVolume = AppSettings.defaults.clickVolume;
  double sliderVolume = AppSettings.defaults.sliderVolume;
  double musicVolume = AppSettings.defaults.musicVolume;
  MusicFrequency musicFrequency = MusicFrequency.defaultFrequency;
  bool musicToastEnabled = true;

  void applySettings(AppSettings settings) {
    final previousMusicContext = _musicContext;
    final previousMusicFrequency = musicFrequency;
    masterVolume = settings.masterVolume.clamp(0.0, 1.0).toDouble();
    pageTurnVolume = settings.pageTurnVolume.clamp(0.0, 1.0).toDouble();
    clickVolume = settings.clickVolume.clamp(0.0, 1.0).toDouble();
    sliderVolume = settings.sliderVolume.clamp(0.0, 1.0).toDouble();
    musicVolume = settings.musicVolume.clamp(0.0, 1.0).toDouble();
    musicFrequency = settings.musicFrequency;
    musicToastEnabled = settings.musicToast;
    if (musicIslandEnabled.value != settings.musicIsland) {
      musicIslandEnabled.value = settings.musicIsland;
    }
    musicIslandAlwaysExpanded.value = settings.musicIslandAlwaysExpanded;
    _musicContext = switch (settings.backgroundId) {
      'netherrack' => _MusicContext.nether,
      'end_stone' => _MusicContext.end,
      _ => _MusicContext.overworld,
    };
    _refreshVisibleMusicPlayback();

    if (musicFrequency == MusicFrequency.off) {
      unawaited(_stopMusic());
      return;
    }

    final handle = _musicHandle;
    if (handle != null && _initialized) {
      try {
        _engine.setVolume(handle, masterVolume * musicVolume);
      } on Object {
        // The track may have ended between the settings change and this call.
      }
    }
    if (!musicToastEnabled) {
      _clearToast();
    }
    if (previousMusicContext != _musicContext) {
      final activeTrack = _activeMusicTrack;
      if (activeTrack != null &&
          activeTrack.context != _MusicContext.overworld &&
          activeTrack.context != _musicContext) {
        unawaited(_restartMusicAfterContextChange());
        return;
      }
      if (activeTrack == null) {
        _musicTimer?.cancel();
        _musicTimer = null;
        _scheduleMusicIfNeeded(initial: true);
        return;
      }
    }
    _scheduleMusicIfNeeded(
      initial: previousMusicFrequency == MusicFrequency.off ||
          _lastMusicTrackId == null,
    );
  }

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_disposed || _initialized) {
      return;
    }
    if (await _windowsMedia.initialize()) {
      _startWindowsMediaPolling();
    } else if (_windowsMedia.isSupported) {
      _scheduleWindowsMediaRetry();
    }
    if (_engine.isInitialized) {
      _initialized = true;
    } else {
      try {
        await _engine.init();
        _initialized = true;
      } on Object catch (error) {
        _initialized = _engine.isInitialized;
        if (!_initialized) {
          debugPrint('Book and Quill audio initialization failed: $error');
        }
      }
    }
    if (_initialized) {
      _scheduleMusicIfNeeded(initial: true);
    }
  }

  Future<void> play(
    GameSound sound, {
    double? pitch,
    double randomPitchRange = 0,
    double volumeScale = 1,
    double? categoryVolumeOverride,
  }) async {
    if (_disposed || masterVolume <= 0) {
      return;
    }

    try {
      final selectedPath = await _chooseSoundAsset(sound);
      if (selectedPath == null) {
        return;
      }
      await initialize();
      if (!_initialized || _disposed) {
        return;
      }

      final source = _sources[selectedPath] ??=
          await _engine.loadAsset(selectedPath);
      final categoryVolume = categoryVolumeOverride ??
          switch (sound) {
            GameSound.pageTurn => pageTurnVolume,
            GameSound.click => clickVolume,
            GameSound.insert => clickVolume,
            GameSound.pickup => clickVolume,
          };
      final handle = await _engine.play(
        source,
        volume: masterVolume * categoryVolume * volumeScale,
      );
      final randomizedPitch =
          (pitch ?? 1.0) + (_random.nextDouble() * 2 - 1) * randomPitchRange;
      if (sound == GameSound.pageTurn ||
          pitch != null ||
          randomPitchRange > 0) {
        final pageVariation = sound == GameSound.pageTurn &&
                pitch == null &&
                randomPitchRange == 0
            ? 0.90 + _random.nextDouble() * 0.20
            : randomizedPitch;
        _engine.setRelativePlaySpeed(
          handle,
          pageVariation.clamp(0.45, 2.0).toDouble(),
        );
      }
    } on Object catch (error) {
      debugPrint('Book and Quill could not play ${sound.name}: $error');
    }
  }

  Future<void> playShelfTurn() {
    return play(
      GameSound.insert,
      pitch: 0.92,
      randomPitchRange: 0.17,
      volumeScale: 0.82,
    );
  }

  Future<void> playShelfDelete() {
    return play(
      GameSound.pickup,
      pitch: 1.0,
      randomPitchRange: 0.19,
      volumeScale: 0.90,
    );
  }

  void playSliderTick(String sliderId, double normalizedValue) {
    if (_disposed || masterVolume <= 0 || sliderVolume <= 0) {
      return;
    }
    final now = DateTime.now();
    final value = normalizedValue.clamp(0.0, 1.0).toDouble();
    final previous = _sliderTicks[sliderId];
    if (previous != null) {
      final elapsed = now.difference(previous.at).inMilliseconds;
      final distance = (value - previous.value).abs();
      if (elapsed < 28 || distance < 0.006) {
        return;
      }
      final speed = (distance / math.max(elapsed, 1) * 1000)
          .clamp(0.0, 5.0)
          .toDouble();
      // Speed supplies most of the pitch lift; position adds a subtle rising
      // scale without making a slow drag shrill.
      final pitch = 0.76 + speed * 0.13 + value * 0.22;
      _sliderTicks[sliderId] = _SliderTickState(now, value);
      unawaited(play(
        GameSound.click,
        pitch: pitch,
        volumeScale: 0.34,
        categoryVolumeOverride: sliderVolume,
      ));
      return;
    }
    _sliderTicks[sliderId] = _SliderTickState(now, value);
    unawaited(play(
      GameSound.click,
      pitch: 0.78 + value * 0.22,
      volumeScale: 0.34,
      categoryVolumeOverride: sliderVolume,
    ));
  }

  Future<String?> _chooseSoundAsset(GameSound sound) async {
    var availablePaths = <String>[];
    for (final path in sound.assetPaths) {
      if (await _assetExists(path)) {
        availablePaths.add(path);
      }
    }
    if (sound == GameSound.pageTurn && availablePaths.length > 1) {
      final numberedVariants = availablePaths
          .where((path) => !path.endsWith('/page_turn.ogg'))
          .toList(growable: false);
      if (numberedVariants.isNotEmpty) {
        availablePaths = numberedVariants;
      }
    }
    if (availablePaths.isEmpty) {
      return null;
    }
    final lastPath = _lastPlayedPath[sound];
    final choices = availablePaths.length > 1 && lastPath != null
        ? availablePaths
            .where((path) => path != lastPath)
            .toList(growable: false)
        : availablePaths;
    final selectedPath = choices[_random.nextInt(choices.length)];
    _lastPlayedPath[sound] = selectedPath;
    return selectedPath;
  }

  void _scheduleMusicIfNeeded({bool initial = false}) {
    if (!_canPlayMusic) {
      _musicTimer?.cancel();
      _musicTimer = null;
      unawaited(_stopMusic());
      return;
    }
    if (_musicHandle != null || _musicStartPending) {
      return;
    }
    _musicTimer?.cancel();
    _musicTimer = null;
    final delay = initial
        ? Duration(seconds: 2 + _random.nextInt(4))
        : _musicDelay();
    _musicTimer = Timer(
      delay,
      () => unawaited(_playMusicTrack(addToHistory: true)),
    );
  }

  Duration _musicDelay() {
    return switch (musicFrequency) {
      MusicFrequency.off => Duration.zero,
      MusicFrequency.defaultFrequency =>
        Duration(minutes: 12 + _random.nextInt(9)),
      MusicFrequency.constant => Duration(seconds: 2 + _random.nextInt(5)),
    };
  }

  bool get _canPlayMusic =>
      !_disposed &&
      masterVolume > 0 &&
      musicVolume > 0 &&
      musicFrequency != MusicFrequency.off;

  Future<List<({_MusicTrack track, String path})>>
      _availableMusicTracks() async {
    final available = <({_MusicTrack track, String path})>[];
    for (final track in _musicTracks) {
      if (track.context != _MusicContext.overworld &&
          track.context != _musicContext) {
        continue;
      }
      for (final path in track.assetPaths) {
        if (await _assetExists(path)) {
          available.add((track: track, path: path));
          break;
        }
      }
    }
    return available;
  }

  Future<void> _playMusicTrack({
    String? requestedTrackId,
    int? requestedHistoryIndex,
    required bool addToHistory,
  }) async {
    if (!_canPlayMusic) {
      return;
    }
    final generation = ++_musicGeneration;
    _musicStartPending = true;
    _musicFinishing = false;
    await _stopActiveMusic(clearPlayback: true);
    if (generation != _musicGeneration || !_canPlayMusic) {
      return;
    }
    await initialize();
    if (!_initialized || generation != _musicGeneration || !_canPlayMusic) {
      if (generation == _musicGeneration) {
        _musicStartPending = false;
      }
      return;
    }

    final available = await _availableMusicTracks();
    if (generation != _musicGeneration || !_canPlayMusic) {
      return;
    }
    if (available.isEmpty) {
      _musicStartPending = false;
      return;
    }

    ({_MusicTrack track, String path})? requested;
    if (requestedTrackId != null) {
      for (final entry in available) {
        if (entry.track.id == requestedTrackId) {
          requested = entry;
          break;
        }
      }
    }
    final choices = requested != null
        ? <({_MusicTrack track, String path})>[requested]
        : available.length > 1 && _lastMusicTrackId != null
            ? available
                .where((entry) => entry.track.id != _lastMusicTrackId)
                .toList(growable: false)
            : available;
    final selected = choices[_random.nextInt(choices.length)];
    final track = selected.track;
    try {
      final source = _sources[selected.path] ??=
          await _engine.loadAsset(selected.path);
      if (generation != _musicGeneration || !_canPlayMusic) {
        return;
      }
      final handle = await _engine.play(
        source,
        volume: masterVolume * musicVolume,
      );
      if (generation != _musicGeneration || !_canPlayMusic) {
        try {
          await _engine.stop(handle);
        } on Object {
          // A superseded transition may already have stopped this handle.
        }
        return;
      }
      _musicHandle = handle;
      _activeMusicTrack = track;
      _activeMusicDuration = _engine.getLength(source);
      _musicPaused = false;
      _musicStartPending = false;
      _lastMusicTrackId = track.id;
      if (requested != null && requestedHistoryIndex != null) {
        _musicHistoryIndex = requestedHistoryIndex;
      } else if (addToHistory || requested == null) {
        if (_musicHistoryIndex + 1 < _musicHistory.length) {
          _musicHistory.removeRange(
            _musicHistoryIndex + 1,
            _musicHistory.length,
          );
        }
        if (_musicHistory.isEmpty || _musicHistory.last != track.id) {
          _musicHistory.add(track.id);
        }
        _musicHistoryIndex = _musicHistory.length - 1;
      }
      _updateMusicPlayback(Duration.zero);
      _startMusicProgressTimer();
      _scheduleMusicCompletion(Duration.zero);
      if (musicToastEnabled) {
        _showToast(MusicToastInfo(title: track.title, artist: track.artist));
      }
    } on Object catch (error) {
      if (generation == _musicGeneration) {
        _musicStartPending = false;
        await _stopActiveMusic(clearPlayback: true);
        debugPrint('Book and Quill could not play background music: $error');
        _scheduleMusicIfNeeded();
      }
    }
  }

  Future<void> previousMusic() async {
    if (_localMusicPlayback == null && _externalMusicPlayback != null) {
      await _windowsMedia.controlExternal('previous');
      return;
    }
    if (!_canPlayMusic) {
      return;
    }
    if (_musicHistoryIndex > 0) {
      final targetIndex = _musicHistoryIndex - 1;
      await _playMusicTrack(
        requestedTrackId: _musicHistory[targetIndex],
        requestedHistoryIndex: targetIndex,
        addToHistory: false,
      );
      return;
    }
    final activeTrack = _activeMusicTrack;
    if (activeTrack != null) {
      await _playMusicTrack(
        requestedTrackId: activeTrack.id,
        requestedHistoryIndex:
            _musicHistoryIndex >= 0 ? _musicHistoryIndex : null,
        addToHistory: _musicHistoryIndex < 0,
      );
      return;
    }
    await _playMusicTrack(addToHistory: true);
  }

  Future<void> nextMusic() async {
    if (_localMusicPlayback == null && _externalMusicPlayback != null) {
      await _windowsMedia.controlExternal('next');
      return;
    }
    if (!_canPlayMusic) {
      return;
    }
    final nextHistoryIndex = _musicHistoryIndex + 1;
    if (nextHistoryIndex >= 0 && nextHistoryIndex < _musicHistory.length) {
      await _playMusicTrack(
        requestedTrackId: _musicHistory[nextHistoryIndex],
        requestedHistoryIndex: nextHistoryIndex,
        addToHistory: false,
      );
      return;
    }
    await _playMusicTrack(addToHistory: true);
  }

  Future<void> toggleMusicPause() async {
    final external = _externalMusicPlayback;
    if (_localMusicPlayback == null && external != null) {
      final shouldPause = !external.isPaused;
      final now = DateTime.now();
      _externalIntentTrackId = external.trackId;
      _externalPauseIntent = shouldPause;
      _externalPauseIntentUntil = now.add(const Duration(seconds: 3));
      _externalMusicPlayback = _copyPlayback(
        external,
        isPaused: shouldPause,
      );
      _externalProgressUpdatedAt = now;
      _refreshVisibleMusicPlayback();
      await _windowsMedia.controlExternal(shouldPause ? 'pause' : 'play');
      return;
    }
    if (!_canPlayMusic) {
      return;
    }
    final handle = _musicHandle;
    if (handle == null) {
      await nextMusic();
      return;
    }
    try {
      if (!_engine.getIsValidVoiceHandle(handle)) {
        await _finishMusicTrack();
        return;
      }
      final position = _engine.getPosition(handle);
      final shouldPause = !_engine.getPause(handle);
      _engine.setPause(handle, shouldPause);
      _musicPaused = shouldPause;
      _updateMusicPlayback(position);
      if (shouldPause) {
        _musicTimer?.cancel();
        _musicTimer = null;
      } else {
        _scheduleMusicCompletion(position);
      }
    } on Object catch (error) {
      debugPrint('Book and Quill could not pause background music: $error');
    }
  }

  Future<void> seekMusic(double progress) async {
    final normalized = progress.clamp(0.0, 1.0).toDouble();
    final external = _externalMusicPlayback;
    if (_localMusicPlayback == null && external != null) {
      if (!external.canSeek || external.duration <= Duration.zero) {
        return;
      }
      final target = Duration(
        milliseconds:
            (external.duration.inMilliseconds * normalized).round(),
      );
      final now = DateTime.now();
      _externalIntentTrackId = external.trackId;
      _externalSeekOrigin = external.position;
      _externalSeekTarget = target;
      _externalSeekIntentUntil = now.add(const Duration(seconds: 3));
      _externalMusicPlayback = _copyPlayback(
        external,
        position: target,
      );
      _externalProgressUpdatedAt = now;
      _refreshVisibleMusicPlayback();
      await _windowsMedia.controlExternal('seek', position: target);
      return;
    }

    final handle = _musicHandle;
    if (handle == null || !_initialized || _activeMusicDuration <= Duration.zero) {
      return;
    }
    final target = Duration(
      milliseconds: (_activeMusicDuration.inMilliseconds * normalized).round(),
    );
    try {
      _engine.seek(handle, target);
      _updateMusicPlayback(target, forceSystemSync: true);
      _scheduleMusicCompletion(target);
    } on Object catch (error) {
      debugPrint('Book and Quill could not seek background music: $error');
    }
  }

  void _startMusicProgressTimer() {
    _musicProgressTimer?.cancel();
    _musicProgressTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refreshMusicProgress(),
    );
  }

  void _refreshMusicProgress() {
    final handle = _musicHandle;
    if (handle == null || !_initialized || _disposed) {
      return;
    }
    try {
      if (!_engine.getIsValidVoiceHandle(handle)) {
        unawaited(_finishMusicTrack());
        return;
      }
      _musicPaused = _engine.getPause(handle);
      _updateMusicPlayback(_engine.getPosition(handle));
    } on Object {
      // The completion timer will clean up an invalid handle.
    }
  }

  void _updateMusicPlayback(
    Duration position, {
    bool forceSystemSync = false,
  }) {
    final track = _activeMusicTrack;
    if (track == null) {
      _localMusicPlayback = null;
      _refreshVisibleMusicPlayback();
      return;
    }
    final maximum = _activeMusicDuration.inMilliseconds;
    final clampedPosition = maximum <= 0
        ? Duration.zero
        : Duration(
            milliseconds:
                position.inMilliseconds.clamp(0, maximum).toInt(),
          );
    final playback = MusicPlaybackInfo(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      position: clampedPosition,
      duration: _activeMusicDuration,
      isPaused: _musicPaused,
      artworkAssetPath: track.artworkAssetPath,
    );
    _localMusicPlayback = playback;
    _refreshVisibleMusicPlayback();
    _syncSystemMediaSession(playback, force: forceSystemSync);
  }

  void _refreshVisibleMusicPlayback() {
    final visible = _localMusicPlayback ?? _externalMusicPlayback;
    musicPlayback.value = visible;
    final controlsEnabled = visible?.isExternal == true
        ? (visible!.canPlay ||
            visible.canPause ||
            visible.canPrevious ||
            visible.canNext ||
            visible.canSeek)
        : _canPlayMusic;
    if (musicControlsEnabled.value != controlsEnabled) {
      musicControlsEnabled.value = controlsEnabled;
    }
  }

  MusicPlaybackInfo _copyPlayback(
    MusicPlaybackInfo value, {
    Duration? position,
    bool? isPaused,
  }) {
    return MusicPlaybackInfo(
      trackId: value.trackId,
      title: value.title,
      artist: value.artist,
      album: value.album,
      position: position ?? value.position,
      duration: value.duration,
      isPaused: isPaused ?? value.isPaused,
      artworkAssetPath: value.artworkAssetPath,
      artworkBytes: value.artworkBytes,
      isExternal: value.isExternal,
      canPlay: value.canPlay,
      canPause: value.canPause,
      canPrevious: value.canPrevious,
      canNext: value.canNext,
      canSeek: value.canSeek,
    );
  }

  void _syncSystemMediaSession(
    MusicPlaybackInfo playback, {
    bool force = false,
  }) {
    if (!_windowsMedia.isAvailable || playback.isExternal) {
      return;
    }
    final now = DateTime.now();
    final trackChanged = _lastSystemMediaTrackId != playback.trackId;
    final pauseChanged = _lastSystemMediaPaused != playback.isPaused;
    final timelineDue = _lastSystemMediaSync == null ||
        now.difference(_lastSystemMediaSync!) >= const Duration(seconds: 4);
    if (!force && !trackChanged && !pauseChanged && !timelineDue) {
      return;
    }
    _lastSystemMediaSync = now;
    _lastSystemMediaTrackId = playback.trackId;
    _lastSystemMediaPaused = playback.isPaused;
    unawaited(_windowsMedia.publishLocal(
      trackId: playback.trackId,
      title: playback.title,
      artist: playback.artist,
      album: playback.album,
      artworkAssetPath: playback.artworkAssetPath ??
          'assets/imported/textures/book_item.png',
      position: playback.position,
      duration: playback.duration,
      isPaused: playback.isPaused,
    ));
  }

  void _startWindowsMediaPolling() {
    _windowsMediaRetryCount = 0;
    _windowsMediaRetryTimer?.cancel();
    _windowsMediaRetryTimer = null;
    _windowsMediaPollTimer?.cancel();
    _externalProgressTimer?.cancel();
    _windowsMediaPollTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => unawaited(_pollWindowsMedia()),
    );
    _externalProgressTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _advanceExternalProgress(),
    );
    unawaited(_pollWindowsMedia());
  }

  void _scheduleWindowsMediaRetry() {
    if (_disposed ||
        _windowsMediaRetryTimer != null ||
        _windowsMediaRetryCount >= 3) {
      return;
    }
    _windowsMediaRetryCount += 1;
    _windowsMediaRetryTimer = Timer(const Duration(seconds: 2), () async {
      _windowsMediaRetryTimer = null;
      if (_disposed) {
        return;
      }
      if (await _windowsMedia.initialize()) {
        _startWindowsMediaPolling();
        final local = _localMusicPlayback;
        if (local != null) {
          _syncSystemMediaSession(local, force: true);
        }
      } else {
        _scheduleWindowsMediaRetry();
      }
    });
  }

  Future<void> _pollWindowsMedia() async {
    if (_windowsMediaPollRunning || _disposed) {
      return;
    }
    _windowsMediaPollRunning = true;
    try {
      final result = await _windowsMedia.poll();
      if (result == null || _disposed) {
        return;
      }
      for (final command in result.commands) {
        await _handleWindowsMediaCommand(command);
      }
      final snapshot = result.external;
      if (snapshot == null) {
        _externalMusicPlayback = null;
        _externalProgressUpdatedAt = null;
        _externalPauseIntentUntil = null;
        _externalSeekIntentUntil = null;
        _externalPauseIntent = null;
        _externalSeekOrigin = null;
        _externalSeekTarget = null;
        _externalIntentTrackId = null;
        _lastExternalSnapshotTrackId = null;
        _lastExternalSnapshotPosition = null;
      } else {
        final now = DateTime.now();
        final trackId = 'windows:${snapshot.identity}';
        final previous = _externalMusicPlayback;
        final sameTrack = previous?.trackId == trackId;
        if (_externalIntentTrackId != null &&
            _externalIntentTrackId != trackId) {
          _externalPauseIntentUntil = null;
          _externalSeekIntentUntil = null;
          _externalPauseIntent = null;
          _externalSeekOrigin = null;
          _externalSeekTarget = null;
          _externalIntentTrackId = null;
        }

        final previousRawPosition = _lastExternalSnapshotTrackId == trackId
            ? _lastExternalSnapshotPosition
            : null;
        final rawMovedBackward = previousRawPosition != null &&
            snapshot.position.inMilliseconds <
                previousRawPosition.inMilliseconds - 750;
        _lastExternalSnapshotTrackId = trackId;
        _lastExternalSnapshotPosition = snapshot.position;

        var isPaused = snapshot.isPaused;
        final pauseIntent = _externalIntentTrackId == trackId
            ? _externalPauseIntent
            : null;
        if (pauseIntent != null) {
          if (snapshot.isPaused == pauseIntent) {
            _externalPauseIntent = null;
            _externalPauseIntentUntil = null;
          } else if (_externalPauseIntentUntil != null &&
              now.isBefore(_externalPauseIntentUntil!)) {
            isPaused = pauseIntent;
          } else {
            _externalPauseIntent = null;
            _externalPauseIntentUntil = null;
          }
        }

        var position = snapshot.position;
        var seekJustConfirmed = false;
        final seekTarget = _externalIntentTrackId == trackId
            ? _externalSeekTarget
            : null;
        if (seekTarget != null && sameTrack && previous != null) {
          final seekOrigin = _externalSeekOrigin ?? previous.position;
          final seekingBackward = seekTarget < seekOrigin;
          final reachedTarget = seekingBackward
              ? rawMovedBackward &&
                  snapshot.position.inMilliseconds <=
                      seekTarget.inMilliseconds + 1500
              : snapshot.position.inMilliseconds >=
                  seekTarget.inMilliseconds - 1500;
          if (reachedTarget) {
            seekJustConfirmed = true;
            _externalSeekOrigin = null;
            _externalSeekTarget = null;
            _externalSeekIntentUntil = null;
          } else if (_externalSeekIntentUntil != null &&
              now.isBefore(_externalSeekIntentUntil!)) {
            position = previous.position;
          } else {
            _externalSeekOrigin = null;
            _externalSeekTarget = null;
            _externalSeekIntentUntil = null;
          }
        }

        if (sameTrack &&
            previous != null &&
            previous.position > position &&
            (!rawMovedBackward || seekJustConfirmed)) {
          position = previous.position;
        }
        _externalMusicPlayback = MusicPlaybackInfo(
          trackId: trackId,
          title: snapshot.title,
          artist: snapshot.artist.isEmpty
              ? snapshot.sourceId
              : snapshot.artist,
          album: snapshot.album,
          position: position,
          duration: snapshot.duration,
          isPaused: isPaused,
          artworkBytes: snapshot.artwork,
          isExternal: true,
          canPlay: snapshot.canPlay,
          canPause: snapshot.canPause,
          canPrevious: snapshot.canPrevious,
          canNext: snapshot.canNext,
          canSeek: snapshot.canSeek,
        );
        _externalProgressUpdatedAt = now;
        final startedPlaying = !isPaused &&
            (!sameTrack || (previous?.isPaused ?? true));
        if (startedPlaying && musicToastEnabled) {
          _showToast(MusicToastInfo(
            title: snapshot.title,
            artist: snapshot.artist.isEmpty
                ? snapshot.sourceId
                : snapshot.artist,
          ));
        }
      }
      _refreshVisibleMusicPlayback();
    } finally {
      _windowsMediaPollRunning = false;
    }
  }

  Future<void> _handleWindowsMediaCommand(WindowsMediaCommand command) async {
    if (_localMusicPlayback == null) {
      return;
    }
    switch (command.name) {
      case 'play':
        if (_musicPaused) {
          await toggleMusicPause();
        }
        break;
      case 'pause':
        if (!_musicPaused) {
          await toggleMusicPause();
        }
        break;
      case 'next':
        await nextMusic();
        break;
      case 'previous':
        await previousMusic();
        break;
      case 'seek':
        final position = command.position;
        if (position != null && _activeMusicDuration > Duration.zero) {
          await seekMusic(
            position.inMilliseconds / _activeMusicDuration.inMilliseconds,
          );
        }
        break;
    }
  }

  void _advanceExternalProgress() {
    final external = _externalMusicPlayback;
    final now = DateTime.now();
    if (_disposed ||
        external == null ||
        external.duration <= Duration.zero) {
      _externalProgressUpdatedAt = now;
      return;
    }
    final updatedAt = _externalProgressUpdatedAt;
    _externalProgressUpdatedAt = now;
    if (external.isPaused || updatedAt == null) {
      return;
    }
    final elapsed = now.difference(updatedAt);
    if (elapsed <= Duration.zero) {
      return;
    }
    final nextMilliseconds = math.min(
      external.duration.inMilliseconds,
      external.position.inMilliseconds + elapsed.inMilliseconds,
    );
    _externalMusicPlayback = _copyPlayback(
      external,
      position: Duration(milliseconds: nextMilliseconds),
    );
    if (_localMusicPlayback == null) {
      _refreshVisibleMusicPlayback();
    }
  }

  void _scheduleMusicCompletion(Duration position) {
    _musicTimer?.cancel();
    _musicTimer = null;
    if (_musicPaused || _activeMusicTrack == null) {
      return;
    }
    final remainingMilliseconds = math
        .max(
          0,
          _activeMusicDuration.inMilliseconds - position.inMilliseconds,
        )
        .toInt();
    _musicTimer = Timer(
      Duration(milliseconds: remainingMilliseconds + 300),
      () => unawaited(_finishMusicTrack()),
    );
  }

  Future<void> _finishMusicTrack() async {
    if (_musicFinishing || _musicHandle == null) {
      return;
    }
    _musicFinishing = true;
    ++_musicGeneration;
    await _stopActiveMusic(clearPlayback: true);
    _musicFinishing = false;
    if (!_disposed) {
      _scheduleMusicIfNeeded();
    }
  }

  void _showToast(MusicToastInfo info) {
    musicToast.value = info;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 5), _clearToast);
  }

  void _clearToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    musicToast.value = null;
  }

  Future<void> _restartMusicAfterContextChange() async {
    await _stopMusic();
    if (!_disposed) {
      _scheduleMusicIfNeeded(initial: true);
    }
  }

  Future<void> _stopMusic() async {
    ++_musicGeneration;
    _musicStartPending = false;
    _musicFinishing = false;
    await _stopActiveMusic(clearPlayback: true);
    _clearToast();
  }

  Future<void> _stopActiveMusic({required bool clearPlayback}) async {
    _musicTimer?.cancel();
    _musicTimer = null;
    _musicProgressTimer?.cancel();
    _musicProgressTimer = null;
    final hadLocalPlayback = _localMusicPlayback != null;
    final handle = _musicHandle;
    _musicHandle = null;
    _activeMusicTrack = null;
    _activeMusicDuration = Duration.zero;
    _musicPaused = false;
    if (clearPlayback) {
      _localMusicPlayback = null;
      _refreshVisibleMusicPlayback();
      if (hadLocalPlayback) {
        _lastSystemMediaSync = null;
        _lastSystemMediaTrackId = null;
        _lastSystemMediaPaused = null;
        await _windowsMedia.clearLocal();
      }
    }
    if (handle != null && _initialized) {
      try {
        await _engine.stop(handle);
      } on Object {
        // A completed handle can already be invalid.
      }
    }
  }

  Future<bool> _assetExists(String path) async {
    final cached = _assetAvailability[path];
    if (cached != null) {
      return cached;
    }
    try {
      await rootBundle.load(path);
      _assetAvailability[path] = true;
      return true;
    } on Object {
      _assetAvailability[path] = false;
      return false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _windowsMediaPollTimer?.cancel();
    _windowsMediaPollTimer = null;
    _windowsMediaRetryTimer?.cancel();
    _windowsMediaRetryTimer = null;
    _externalProgressTimer?.cancel();
    _externalProgressTimer = null;
    await _stopMusic();
    await _windowsMedia.dispose();
    if (_initialized) {
      for (final source in _sources.values) {
        try {
          await _engine.disposeSource(source);
        } on Object {
          // Continue releasing the remaining sounds.
        }
      }
      _sources.clear();
      try {
        _engine.deinit();
      } on Object {
        // Shutdown errors do not need to surface to the user.
      }
    }
    musicToast.dispose();
    musicPlayback.dispose();
    musicControlsEnabled.dispose();
    musicIslandEnabled.dispose();
    musicIslandAlwaysExpanded.dispose();
    _initialized = false;
  }
}
