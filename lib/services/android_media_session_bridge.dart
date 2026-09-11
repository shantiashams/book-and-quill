import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_platform.dart';

/// Android's native media session is independent of the in-app music island.
class AndroidMediaSessionBridge {
  static const channel = MethodChannel('book_and_quill/media');
  bool _available = false;
  bool _disposed = false;
  bool _hasSession = false;
  int _generation = 0;
  Future<void> _queue = Future<void>.value();

  bool get hasSession => _hasSession;
  bool get isAvailable => _available;

  Future<void> initialize(
    Future<void> Function(String command, Duration? position) onCommand,
  ) async {
    if (_disposed || !AndroidPlatform.isAndroid || _available) return;
    channel.setMethodCallHandler((call) async {
      if (_disposed || call.method != 'command') return;
      final data = Map<Object?, Object?>.from(call.arguments as Map);
      final milliseconds = data['positionMs'] as num?;
      await onCommand(data['name'] as String,
        milliseconds == null ? null : Duration(milliseconds: milliseconds.toInt()));
    });
    try {
      _available = await channel.invokeMethod<bool>('initialize') ?? false;
    } on PlatformException catch (error) {
      debugPrint('Android media session unavailable: ${error.code}');
    } on MissingPluginException {
      _available = false;
    }
  }

  Future<void> publish({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    required String? artworkAssetPath,
    required Duration position,
    required Duration duration,
    required bool isPaused,
  }) {
    if (!_available || _disposed) return Future<void>.value();
    final generation = _generation;
    _queue = _queue.then((_) async {
      if (_disposed || generation != _generation) return;
      try {
        final started = await channel.invokeMethod<bool>('publish', <String, Object?>{
          'trackId': trackId, 'title': title, 'artist': artist, 'album': album,
          'artwork': artworkAssetPath,
          'positionMs': position.inMilliseconds, 'durationMs': duration.inMilliseconds,
          'paused': isPaused,
        }) ?? false;
        if (generation == _generation) _hasSession = started;
      } on PlatformException catch (error) {
        debugPrint('Android media update failed: ${error.code}');
        _hasSession = false;
      } on MissingPluginException {
        _hasSession = false;
      }
    });
    return _queue;
  }

  Future<bool> requestFocus() async {
    if (!_available) return true; // Desktop or a native bridge unavailable fallback.
    if (_disposed || !_hasSession) return false;
    try { return await channel.invokeMethod<bool>('requestFocus') ?? false; }
    on PlatformException { return false; }
    on MissingPluginException { return false; }
  }

  Future<void> clear() {
    _generation++;
    _hasSession = false;
    if (!_available) return Future<void>.value();
    _queue = _queue.then((_) async {
      try { await channel.invokeMethod<void>('clear'); }
      on PlatformException catch (error) { debugPrint('Android media clear failed: ${error.code}'); }
      on MissingPluginException { /* The engine may already be shutting down. */ }
    });
    return _queue;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await clear();
    if (AndroidPlatform.isAndroid) channel.setMethodCallHandler(null);
    _available = false;
  }
}
