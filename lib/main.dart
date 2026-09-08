import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_settings.dart';
import 'models/book_record.dart';
import 'models/usage_stats.dart';
import 'screens/library_screen.dart';
import 'services/book_storage.dart';
import 'services/fullscreen_service.dart';
import 'services/game_sound_service.dart';
import 'theme/book_and_quill_theme.dart';
import 'widgets/music_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = BookStorage();
  final List<BookRecord?> initialSlots = await storage.loadSlots();
  final List<String> initialShelfNames = await storage.loadShelfNames();
  final AppSettings initialSettings = await storage.loadSettings();
  final UsageStats initialUsageStats =
      (await storage.loadUsageStats()).add(appLaunches: 1);
  await storage.saveUsageStats(initialUsageStats);
  final sounds = GameSoundService();
  sounds.applySettings(initialSettings);
  await sounds.initialize();

  runApp(
    BookAndQuillApp(
      storage: storage,
      initialSlots: initialSlots,
      initialShelfNames: initialShelfNames,
      initialSettings: initialSettings,
      initialUsageStats: initialUsageStats,
      sounds: sounds,
    ),
  );
}

class BookAndQuillApp extends StatefulWidget {
  const BookAndQuillApp({
    required this.storage,
    required this.initialSlots,
    required this.initialShelfNames,
    required this.sounds,
    this.initialSettings = AppSettings.defaults,
    this.initialUsageStats = UsageStats.empty,
    super.key,
  });

  final BookStorage storage;
  final List<BookRecord?> initialSlots;
  final List<String> initialShelfNames;
  final AppSettings initialSettings;
  final UsageStats initialUsageStats;
  final GameSoundService sounds;

  @override
  State<BookAndQuillApp> createState() => _BookAndQuillAppState();
}

class _BookAndQuillAppState extends State<BookAndQuillApp> {
  final FullscreenService _fullscreenService = FullscreenService();
  final ValueNotifier<bool> _fullscreenState = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _transparentState = ValueNotifier<bool>(false);
  bool _fullscreenChangeInProgress = false;
  bool _transparentChangeInProgress = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return true;
    }
    return false;
  }

  Future<bool> _toggleFullscreen() async {
    if (_fullscreenChangeInProgress) {
      return _fullscreenState.value;
    }
    if (_transparentState.value) {
      await _setTransparentMode(false);
    }
    _fullscreenChangeInProgress = true;
    try {
      final fullscreen = await _fullscreenService.toggle();
      if (mounted) {
        _fullscreenState.value = fullscreen;
      }
      return fullscreen;
    } finally {
      _fullscreenChangeInProgress = false;
    }
  }

  Future<bool> _setTransparentMode(bool enabled) async {
    if (_transparentChangeInProgress) {
      return _transparentState.value;
    }
    _transparentChangeInProgress = true;
    try {
      final transparent = await _fullscreenService.setTransparent(enabled);
      if (mounted) {
        _transparentState.value = transparent;
        _fullscreenState.value = _fullscreenService.isFullscreen;
      }
      return transparent;
    } finally {
      _transparentChangeInProgress = false;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _fullscreenService.restoreWindow();
    _fullscreenState.dispose();
    _transparentState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Book and Quill',
      theme: BookAndQuillTheme.theme,
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: _transparentState,
          child: child ?? const SizedBox.shrink(),
          builder: (context, transparent, app) => Stack(
            fit: StackFit.expand,
            children: <Widget>[
              app!,
              if (!transparent) MusicToastOverlay(sounds: widget.sounds),
            ],
          ),
        );
      },
      home: LibraryScreen(
        storage: widget.storage,
        initialSlots: widget.initialSlots,
        initialShelfNames: widget.initialShelfNames,
        initialSettings: widget.initialSettings,
        initialUsageStats: widget.initialUsageStats,
        sounds: widget.sounds,
        fullscreenListenable: _fullscreenState,
        onToggleFullscreen: _toggleFullscreen,
        transparentModeListenable: _transparentState,
        onSetTransparentMode: _setTransparentMode,
      ),
    );
  }
}
