import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowsMediaCommand {
  const WindowsMediaCommand(this.name, {this.position});

  final String name;
  final Duration? position;
}

class ExternalMediaSnapshot {
  const ExternalMediaSnapshot({
    required this.sourceId,
    required this.title,
    required this.artist,
    required this.album,
    required this.position,
    required this.duration,
    required this.isPaused,
    required this.canPlay,
    required this.canPause,
    required this.canPrevious,
    required this.canNext,
    required this.canSeek,
    this.artwork,
  });

  final String sourceId;
  final String title;
  final String artist;
  final String album;
  final Duration position;
  final Duration duration;
  final bool isPaused;
  final bool canPlay;
  final bool canPause;
  final bool canPrevious;
  final bool canNext;
  final bool canSeek;
  final Uint8List? artwork;

  String get identity => '$sourceId\u0000$title\u0000$artist\u0000$album';
}

class WindowsMediaPollResult {
  const WindowsMediaPollResult({
    required this.external,
    required this.commands,
  });

  final ExternalMediaSnapshot? external;
  final List<WindowsMediaCommand> commands;
}

class WindowsMediaSessionBridge {
  static const MethodChannel _channel =
      MethodChannel('book_and_quill/windows_media');

  bool _available = false;
  bool _initializing = false;
  String? _cachedArtworkPath;
  Uint8List? _cachedArtwork;
  String? _externalIdentity;
  Uint8List? _externalArtwork;

  bool get isAvailable => _available;
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<bool> initialize() async {
    if (_available) {
      return _available;
    }
    if (_initializing) {
      return false;
    }
    if (!isSupported) {
      return false;
    }
    _initializing = true;
    try {
      _available = await _channel.invokeMethod<bool>('initialize') ?? false;
    } on MissingPluginException {
      _available = false;
    } on PlatformException catch (error) {
      debugPrint('Windows media integration could not start: $error');
      _available = false;
    } finally {
      _initializing = false;
    }
    return _available;
  }

  Future<void> publishLocal({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    required String artworkAssetPath,
    required Duration position,
    required Duration duration,
    required bool isPaused,
  }) async {
    if (!_available) {
      return;
    }
    final artwork = await _loadArtwork(artworkAssetPath);
    try {
      await _channel.invokeMethod<void>('publishLocal', <String, Object?>{
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'album': album,
        'artwork': artwork,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'isPaused': isPaused,
      });
    } on PlatformException catch (error) {
      debugPrint('Windows could not update Book and Quill media: $error');
    }
  }

  Future<WindowsMediaPollResult?> poll() async {
    if (!_available) {
      return null;
    }
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>('poll');
      if (response == null) {
        return null;
      }
      final commands = <WindowsMediaCommand>[];
      final rawCommands = response['commands'];
      if (rawCommands is List) {
        for (final rawCommand in rawCommands) {
          if (rawCommand is! Map) {
            continue;
          }
          final name = rawCommand['name'];
          if (name is! String) {
            continue;
          }
          final positionMs = rawCommand['positionMs'];
          commands.add(WindowsMediaCommand(
            name,
            position: positionMs is num
                ? Duration(milliseconds: positionMs.toInt())
                : null,
          ));
        }
      }

      ExternalMediaSnapshot? external;
      final rawExternal = response['external'];
      if (rawExternal is Map && rawExternal['available'] == true) {
        final identity = '${rawExternal['sourceId'] ?? ''}\u0000'
            '${rawExternal['title'] ?? ''}\u0000'
            '${rawExternal['artist'] ?? ''}\u0000'
            '${rawExternal['album'] ?? ''}';
        if (_externalIdentity != identity) {
          _externalIdentity = identity;
          _externalArtwork = null;
        }
        final artwork = rawExternal['artwork'];
        if (artwork is Uint8List && artwork.isNotEmpty) {
          _externalArtwork = artwork;
        }
        external = ExternalMediaSnapshot(
          sourceId: rawExternal['sourceId'] as String? ?? '',
          title: rawExternal['title'] as String? ?? 'Unknown media',
          artist: rawExternal['artist'] as String? ?? '',
          album: rawExternal['album'] as String? ?? '',
          position: Duration(
            milliseconds: (rawExternal['positionMs'] as num?)?.toInt() ?? 0,
          ),
          duration: Duration(
            milliseconds: (rawExternal['durationMs'] as num?)?.toInt() ?? 0,
          ),
          isPaused: rawExternal['isPaused'] as bool? ?? true,
          canPlay: rawExternal['canPlay'] as bool? ?? false,
          canPause: rawExternal['canPause'] as bool? ?? false,
          canPrevious: rawExternal['canPrevious'] as bool? ?? false,
          canNext: rawExternal['canNext'] as bool? ?? false,
          canSeek: rawExternal['canSeek'] as bool? ?? false,
          artwork: _externalArtwork,
        );
      } else {
        _externalIdentity = null;
        _externalArtwork = null;
      }
      return WindowsMediaPollResult(external: external, commands: commands);
    } on PlatformException catch (error) {
      debugPrint('Windows media session could not be read: $error');
      return null;
    }
  }

  Future<void> controlExternal(
    String command, {
    Duration? position,
  }) async {
    if (!_available) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('controlExternal', <String, Object?>{
        'command': command,
        if (position != null) 'positionMs': position.inMilliseconds,
      });
    } on PlatformException catch (error) {
      debugPrint('Windows media control failed: $error');
    }
  }

  Future<void> clearLocal() async {
    if (!_available) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('clearLocal');
    } on PlatformException {
      // The native runner can already be shutting down at this point.
    }
  }

  Future<Uint8List?> _loadArtwork(String path) async {
    if (_cachedArtworkPath == path) {
      return _cachedArtwork;
    }
    _cachedArtworkPath = path;
    _cachedArtwork = null;
    try {
      final data = await rootBundle.load(path);
      _cachedArtwork = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } on Object {
      // The in-app cover has its own fallback. Windows simply omits artwork
      // when an optional album image has not been copied into the project yet.
    }
    return _cachedArtwork;
  }

  Future<void> dispose() async {
    await clearLocal();
    _available = false;
  }
}
