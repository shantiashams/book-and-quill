import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

/// Controls borderless fullscreen and an always-on-top book overlay on Windows.
///
/// Other supported Flutter platforms fall back to hiding their system UI.
/// Keeping the Windows implementation here avoids requiring another package or
/// changes to the native runner for the F11 and F1 shortcuts.
class FullscreenService {
  static const int transparentBackgroundArgb = 0xFF010203;
  static _WindowsFullscreenBackend? _activeTransparentBackend;

  /// These actions move the native overlay rather than its Flutter contents.
  static bool beginTransparentWindowDrag() =>
      _activeTransparentBackend?.beginWindowDrag() ?? false;

  static bool updateTransparentWindowDrag() =>
      _activeTransparentBackend?.updateWindowDrag() ?? false;

  static void endTransparentWindowDrag() {
    _activeTransparentBackend?.endWindowDrag();
  }

  FullscreenService() {
    if (Platform.isWindows) {
      try {
        _windows = _WindowsFullscreenBackend();
      } on Object {
        _windows = null;
      }
    }
  }

  _WindowsFullscreenBackend? _windows;
  bool _isFullscreen = false;
  bool _isTransparent = false;
  bool _fullscreenBeforeTransparent = false;

  bool get isFullscreen => _isFullscreen;
  bool get isTransparent => _isTransparent;

  Future<bool> toggle() => setFullscreen(!_isFullscreen);

  Future<bool> setFullscreen(bool enabled) async {
    if (enabled == _isFullscreen) {
      return _isFullscreen;
    }

    final windows = _windows;
    if (windows != null) {
      final changed = enabled
          ? windows.enterFullscreen()
          : windows.exitFullscreen();
      if (changed) {
        _isFullscreen = enabled;
      }
      return _isFullscreen;
    }

    try {
      if (enabled) {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
      } else {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      }
      _isFullscreen = enabled;
    } on Object {
      // An unsupported platform simply keeps its previous window state.
    }
    return _isFullscreen;
  }

  Future<bool> setTransparent(bool enabled) async {
    if (enabled == _isTransparent) {
      return _isTransparent;
    }
    final windows = _windows;
    if (windows == null) {
      return _isTransparent;
    }

    if (enabled) {
      final wasFullscreen = _isFullscreen;
      if (!wasFullscreen && !await setFullscreen(true)) {
        return false;
      }
      if (!windows.enterTransparent()) {
        if (!wasFullscreen) {
          await setFullscreen(false);
        }
        return false;
      }
      _fullscreenBeforeTransparent = wasFullscreen;
      _isTransparent = true;
      _activeTransparentBackend = windows;
      return true;
    }

    if (!windows.exitTransparent()) {
      return _isTransparent;
    }
    _activeTransparentBackend = null;
    _isTransparent = false;
    final keepFullscreen = _fullscreenBeforeTransparent;
    _fullscreenBeforeTransparent = false;
    if (!keepFullscreen) {
      await setFullscreen(false);
    }
    return false;
  }

  void restoreWindow() {
    if (_isTransparent) {
      _windows?.endWindowDrag();
      _windows?.exitTransparent();
      _activeTransparentBackend = null;
      _isTransparent = false;
      _fullscreenBeforeTransparent = false;
    }
    if (!_isFullscreen) {
      return;
    }
    final windows = _windows;
    if (windows != null) {
      windows.exitFullscreen();
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
    _isFullscreen = false;
  }
}

final class _WinPoint extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

final class _WinRect extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int right;

  @Int32()
  external int bottom;
}

final class _WindowPlacement extends Struct {
  @Uint32()
  external int length;

  @Uint32()
  external int flags;

  @Uint32()
  external int showCommand;

  external _WinPoint minimumPosition;
  external _WinPoint maximumPosition;
  external _WinRect normalPosition;
}

final class _MonitorInfo extends Struct {
  @Uint32()
  external int size;

  external _WinRect monitor;
  external _WinRect workArea;

  @Uint32()
  external int flags;
}

typedef _GetCursorPosNative = Int32 Function(Pointer<_WinPoint>);
typedef _GetCursorPosDart = int Function(Pointer<_WinPoint>);
typedef _GetWindowRectNative = Int32 Function(Pointer<Void>, Pointer<_WinRect>);
typedef _GetWindowRectDart = int Function(Pointer<Void>, Pointer<_WinRect>);
typedef _GetDpiForWindowNative = Uint32 Function(Pointer<Void>);
typedef _GetDpiForWindowDart = int Function(Pointer<Void>);

typedef _GetForegroundWindowNative = Pointer<Void> Function();
typedef _GetForegroundWindowDart = Pointer<Void> Function();
typedef _GetWindowLongPtrNative = IntPtr Function(Pointer<Void>, Int32);
typedef _GetWindowLongPtrDart = int Function(Pointer<Void>, int);
typedef _SetWindowLongPtrNative = IntPtr Function(
  Pointer<Void>,
  Int32,
  IntPtr,
);
typedef _SetWindowLongPtrDart = int Function(Pointer<Void>, int, int);
typedef _GetWindowPlacementNative = Int32 Function(
  Pointer<Void>,
  Pointer<_WindowPlacement>,
);
typedef _GetWindowPlacementDart = int Function(
  Pointer<Void>,
  Pointer<_WindowPlacement>,
);
typedef _SetWindowPlacementNative = Int32 Function(
  Pointer<Void>,
  Pointer<_WindowPlacement>,
);
typedef _SetWindowPlacementDart = int Function(
  Pointer<Void>,
  Pointer<_WindowPlacement>,
);
typedef _MonitorFromWindowNative = Pointer<Void> Function(
  Pointer<Void>,
  Uint32,
);
typedef _MonitorFromWindowDart = Pointer<Void> Function(
  Pointer<Void>,
  int,
);
typedef _GetMonitorInfoNative = Int32 Function(
  Pointer<Void>,
  Pointer<_MonitorInfo>,
);
typedef _GetMonitorInfoDart = int Function(
  Pointer<Void>,
  Pointer<_MonitorInfo>,
);
typedef _SetWindowPosNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
  Int32,
  Int32,
  Int32,
  Int32,
  Uint32,
);
typedef _SetWindowPosDart = int Function(
  Pointer<Void>,
  Pointer<Void>,
  int,
  int,
  int,
  int,
  int,
);
typedef _SetLayeredWindowAttributesNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Uint8,
  Uint32,
);
typedef _SetLayeredWindowAttributesDart = int Function(
  Pointer<Void>,
  int,
  int,
  int,
);
typedef _GetProcessHeapNative = Pointer<Void> Function();
typedef _GetProcessHeapDart = Pointer<Void> Function();
typedef _HeapAllocNative = Pointer<Void> Function(
  Pointer<Void>,
  Uint32,
  IntPtr,
);
typedef _HeapAllocDart = Pointer<Void> Function(
  Pointer<Void>,
  int,
  int,
);
typedef _HeapFreeNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Void>,
);
typedef _HeapFreeDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Void>,
);

class _WindowsFullscreenBackend {
  _WindowsFullscreenBackend() {
    final user32 = DynamicLibrary.open('user32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    _getCursorPos = user32.lookupFunction<_GetCursorPosNative, _GetCursorPosDart>(
      'GetCursorPos',
    );
    _getWindowRect = user32.lookupFunction<_GetWindowRectNative, _GetWindowRectDart>(
      'GetWindowRect',
    );
    try {
      _getDpiForWindow = user32.lookupFunction<
          _GetDpiForWindowNative, _GetDpiForWindowDart>('GetDpiForWindow');
    } on ArgumentError {
      // GetDpiForWindow was added in Windows 10 version 1607.
      _getDpiForWindow = null;
    }

    _getForegroundWindow = user32.lookupFunction<
        _GetForegroundWindowNative,
        _GetForegroundWindowDart>('GetForegroundWindow');
    _getWindowLongPtr = user32.lookupFunction<
        _GetWindowLongPtrNative,
        _GetWindowLongPtrDart>('GetWindowLongPtrW');
    _setWindowLongPtr = user32.lookupFunction<
        _SetWindowLongPtrNative,
        _SetWindowLongPtrDart>('SetWindowLongPtrW');
    _getWindowPlacement = user32.lookupFunction<
        _GetWindowPlacementNative,
        _GetWindowPlacementDart>('GetWindowPlacement');
    _setWindowPlacement = user32.lookupFunction<
        _SetWindowPlacementNative,
        _SetWindowPlacementDart>('SetWindowPlacement');
    _monitorFromWindow = user32.lookupFunction<
        _MonitorFromWindowNative,
        _MonitorFromWindowDart>('MonitorFromWindow');
    _getMonitorInfo = user32.lookupFunction<
        _GetMonitorInfoNative,
        _GetMonitorInfoDart>('GetMonitorInfoW');
    _setWindowPos = user32.lookupFunction<
        _SetWindowPosNative,
        _SetWindowPosDart>('SetWindowPos');
    _setLayeredWindowAttributes = user32.lookupFunction<
        _SetLayeredWindowAttributesNative,
        _SetLayeredWindowAttributesDart>('SetLayeredWindowAttributes');
    _heapAlloc = kernel32.lookupFunction<_HeapAllocNative, _HeapAllocDart>(
      'HeapAlloc',
    );
    _heapFree = kernel32.lookupFunction<_HeapFreeNative, _HeapFreeDart>(
      'HeapFree',
    );
    final getProcessHeap = kernel32.lookupFunction<
        _GetProcessHeapNative,
        _GetProcessHeapDart>('GetProcessHeap');
    _processHeap = getProcessHeap();
    if (_processHeap.address == 0) {
      throw StateError('The Windows process heap is unavailable.');
    }
  }

  static const int _windowStyleIndex = -16;
  static const int _extendedWindowStyleIndex = -20;
  static const int _overlappedWindowStyle = 0x00CF0000;
  static const int _layeredWindowStyle = 0x00080000;
  static const int _topmostWindowStyle = 0x00000008;
  static const int _layeredColorKey = 0x00000001;
  static const int _layeredAlpha = 0x00000002;
  // COLORREF stores the Flutter RGB(1, 2, 3) background as 0x00BBGGRR.
  static const int _transparentColorKey = 0x00030201;
  static const int _monitorDefaultToNearest = 0x00000002;
  static const int _heapZeroMemory = 0x00000008;
  static const int _noSize = 0x0001;
  static const int _noMove = 0x0002;
  static const int _noZOrder = 0x0004;
  static const int _noActivate = 0x0010;
  static const int _frameChanged = 0x0020;
  static const int _noOwnerZOrder = 0x0200;

  late final _GetCursorPosDart _getCursorPos;
  late final _GetWindowRectDart _getWindowRect;
  _GetDpiForWindowDart? _getDpiForWindow;
  late final _GetForegroundWindowDart _getForegroundWindow;
  late final _GetWindowLongPtrDart _getWindowLongPtr;
  late final _SetWindowLongPtrDart _setWindowLongPtr;
  late final _GetWindowPlacementDart _getWindowPlacement;
  late final _SetWindowPlacementDart _setWindowPlacement;
  late final _MonitorFromWindowDart _monitorFromWindow;
  late final _GetMonitorInfoDart _getMonitorInfo;
  late final _SetWindowPosDart _setWindowPos;
  late final _SetLayeredWindowAttributesDart _setLayeredWindowAttributes;
  late final _HeapAllocDart _heapAlloc;
  late final _HeapFreeDart _heapFree;
  late final Pointer<Void> _processHeap;

  Pointer<Void>? _window;
  int? _windowStyle;
  _SavedWindowPlacement? _savedPlacement;
  Pointer<Void>? _transparentWindow;
  int? _windowExtendedStyle;
  ({int left, int top, int width, int height})? _boundsBeforeTransparent;
  ({double x, double y})? _dragAnchor;

  int _windowDpi(Pointer<Void> window) {
    final dpi = _getDpiForWindow?.call(window) ?? 96;
    return dpi > 0 ? dpi : 96;
  }

  ({int left, int top, int width, int height})? _readWindowBounds(
    Pointer<Void> window,
  ) {
    final rect = _allocate<_WinRect>(sizeOf<_WinRect>());
    if (rect.address == 0) return null;
    try {
      if (_getWindowRect(window, rect) == 0) return null;
      return (
        left: rect.ref.left, top: rect.ref.top,
        width: rect.ref.right - rect.ref.left,
        height: rect.ref.bottom - rect.ref.top,
      );
    } finally {
      _free(rect);
    }
  }

  ({int x, int y})? _readCursorPosition() {
    final point = _allocate<_WinPoint>(sizeOf<_WinPoint>());
    if (point.address == 0) return null;
    try {
      if (_getCursorPos(point) == 0) return null;
      return (x: point.ref.x, y: point.ref.y);
    } finally {
      _free(point);
    }
  }

  bool beginWindowDrag() {
    endWindowDrag();
    final window = _transparentWindow;
    if (window == null) return false;
    final bounds = _readWindowBounds(window);
    final cursor = _readCursorPosition();
    if (bounds == null || cursor == null) return false;
    final scale = _windowDpi(window) / 96.0;
    _dragAnchor = (
      x: (cursor.x - bounds.left) / scale,
      y: (cursor.y - bounds.top) / scale,
    );
    return true;
  }

  bool updateWindowDrag() {
    final window = _transparentWindow;
    final anchor = _dragAnchor;
    if (window == null || anchor == null) return false;
    final cursor = _readCursorPosition();
    if (cursor == null) return false;
    final scale = _windowDpi(window) / 96.0;
    // Use desktop coordinates, not Flutter event.delta: moving the native
    // window changes local pointer coordinates. Negative monitor origins are
    // valid. Rescale the grab offset after a per-monitor DPI change.
    return _setWindowPos(
      window, nullptr,
      (cursor.x - anchor.x * scale).round(),
      (cursor.y - anchor.y * scale).round(),
      0, 0,
      _noSize | _noZOrder | _noActivate | _noOwnerZOrder,
    ) != 0;
  }

  void endWindowDrag() {
    _dragAnchor = null;
  }

  bool enterFullscreen() {
    if (_window != null) {
      return true;
    }

    final window = _getForegroundWindow();
    if (window.address == 0) {
      return false;
    }
    final placementPointer = _allocate<_WindowPlacement>(
      sizeOf<_WindowPlacement>(),
    );
    if (placementPointer.address == 0) {
      return false;
    }

    try {
      placementPointer.ref.length = sizeOf<_WindowPlacement>();
      if (_getWindowPlacement(window, placementPointer) == 0) {
        return false;
      }

      final monitor = _monitorFromWindow(window, _monitorDefaultToNearest);
      if (monitor.address == 0) {
        return false;
      }
      final monitorPointer = _allocate<_MonitorInfo>(sizeOf<_MonitorInfo>());
      if (monitorPointer.address == 0) {
        return false;
      }

      try {
        monitorPointer.ref.size = sizeOf<_MonitorInfo>();
        if (_getMonitorInfo(monitor, monitorPointer) == 0) {
          return false;
        }

        final style = _getWindowLongPtr(window, _windowStyleIndex);
        if (style == 0) {
          return false;
        }
        final savedPlacement = _SavedWindowPlacement.fromNative(
          placementPointer.ref,
        );
        _setWindowLongPtr(
          window,
          _windowStyleIndex,
          style & ~_overlappedWindowStyle,
        );

        final bounds = monitorPointer.ref.monitor;
        final resized = _setWindowPos(
          window,
          nullptr,
          bounds.left,
          bounds.top,
          bounds.right - bounds.left,
          bounds.bottom - bounds.top,
          _noOwnerZOrder | _frameChanged,
        );
        if (resized == 0) {
          _setWindowLongPtr(window, _windowStyleIndex, style);
          return false;
        }

        _window = window;
        _windowStyle = style;
        _savedPlacement = savedPlacement;
        return true;
      } finally {
        _free(monitorPointer);
      }
    } finally {
      _free(placementPointer);
    }
  }

  bool exitFullscreen() {
    final window = _window;
    final style = _windowStyle;
    final savedPlacement = _savedPlacement;
    if (window == null || style == null || savedPlacement == null) {
      return true;
    }

    final placementPointer = _allocate<_WindowPlacement>(
      sizeOf<_WindowPlacement>(),
    );
    try {
      _setWindowLongPtr(window, _windowStyleIndex, style);
      if (placementPointer.address != 0) {
        savedPlacement.writeTo(placementPointer.ref);
        _setWindowPlacement(window, placementPointer);
      }
      _setWindowPos(
        window,
        nullptr,
        0,
        0,
        0,
        0,
        _noMove |
            _noSize |
            _noZOrder |
            _noOwnerZOrder |
            _frameChanged,
      );
    } finally {
      if (placementPointer.address != 0) {
        _free(placementPointer);
      }
      _window = null;
      _windowStyle = null;
      _savedPlacement = null;
    }
    return true;
  }

  bool enterTransparent() {
    if (_transparentWindow != null) {
      return true;
    }
    final window = _window ?? _getForegroundWindow();
    if (window.address == 0) {
      return false;
    }
    final originalBounds = _readWindowBounds(window);
    if (originalBounds == null) return false;
    final extendedStyle = _getWindowLongPtr(
      window,
      _extendedWindowStyleIndex,
    );
    _setWindowLongPtr(
      window,
      _extendedWindowStyleIndex,
      extendedStyle | _layeredWindowStyle,
    );
    final changed = _setLayeredWindowAttributes(
      window,
      _transparentColorKey,
      255,
      _layeredColorKey,
    );
    if (changed == 0) {
      _setWindowLongPtr(
        window,
        _extendedWindowStyleIndex,
        extendedStyle,
      );
      return false;
    }
    // Z-order must change here: SWP_NOZORDER would silently ignore TOPMOST.
    // NOACTIVATE lets the user keep typing in another app after switching away.
    if (!_setTopmost(window, true)) {
      _setLayeredWindowAttributes(window, 0, 255, _layeredAlpha);
      _setWindowLongPtr(window, _extendedWindowStyleIndex, extendedStyle);
      _setWindowPos(
        window, nullptr, 0, 0, 0, 0,
        _noMove | _noSize | _noZOrder | _noActivate |
            _noOwnerZOrder | _frameChanged,
      );
      return false;
    }
    _transparentWindow = window;
    _windowExtendedStyle = extendedStyle;
    _boundsBeforeTransparent = originalBounds;
    return true;
  }

  bool exitTransparent() {
    endWindowDrag();
    final window = _transparentWindow;
    final extendedStyle = _windowExtendedStyle;
    if (window == null || extendedStyle == null) {
      return true;
    }
    // Moving the overlay also moves its borderless fullscreen host. Restore
    // that host before showing the normal app, even if F1 began fullscreen.
    final bounds = _boundsBeforeTransparent;
    if (bounds != null && _setWindowPos(
      window, nullptr, bounds.left, bounds.top, bounds.width, bounds.height,
      _noZOrder | _noActivate | _noOwnerZOrder | _frameChanged,
    ) == 0) {
      return false;
    }
    // Restore the state from before F1, including a pre-existing topmost flag.
    // If demotion fails, retain F1 state so the user can retry the toggle.
    final wasTopmost = (extendedStyle & _topmostWindowStyle) != 0;
    if (!_setTopmost(window, wasTopmost)) {
      return false;
    }
    _setLayeredWindowAttributes(
      window,
      0,
      255,
      _layeredAlpha,
    );
    _setWindowLongPtr(
      window,
      _extendedWindowStyleIndex,
      extendedStyle,
    );
    _setWindowPos(
      window,
      nullptr,
      0,
      0,
      0,
      0,
      _noMove | _noSize | _noZOrder | _noActivate |
          _noOwnerZOrder | _frameChanged,
    );
    _transparentWindow = null;
    _windowExtendedStyle = null;
    _boundsBeforeTransparent = null;
    return true;
  }

  bool _setTopmost(Pointer<Void> window, bool enabled) {
    // Win32 pseudo-handles HWND_TOPMOST (-1) and HWND_NOTOPMOST (-2).
    return _setWindowPos(
      window,
      Pointer<Void>.fromAddress(enabled ? -1 : -2),
      0, 0, 0, 0,
      _noMove | _noSize | _noActivate | _noOwnerZOrder | _frameChanged,
    ) != 0;
  }

  Pointer<T> _allocate<T extends NativeType>(int byteCount) {
    return _heapAlloc(
      _processHeap,
      _heapZeroMemory,
      byteCount,
    ).cast<T>();
  }

  void _free<T extends NativeType>(Pointer<T> pointer) {
    _heapFree(_processHeap, 0, pointer.cast<Void>());
  }
}

class _SavedWindowPlacement {
  const _SavedWindowPlacement({
    required this.flags,
    required this.showCommand,
    required this.minimumX,
    required this.minimumY,
    required this.maximumX,
    required this.maximumY,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory _SavedWindowPlacement.fromNative(_WindowPlacement placement) {
    return _SavedWindowPlacement(
      flags: placement.flags,
      showCommand: placement.showCommand,
      minimumX: placement.minimumPosition.x,
      minimumY: placement.minimumPosition.y,
      maximumX: placement.maximumPosition.x,
      maximumY: placement.maximumPosition.y,
      left: placement.normalPosition.left,
      top: placement.normalPosition.top,
      right: placement.normalPosition.right,
      bottom: placement.normalPosition.bottom,
    );
  }

  final int flags;
  final int showCommand;
  final int minimumX;
  final int minimumY;
  final int maximumX;
  final int maximumY;
  final int left;
  final int top;
  final int right;
  final int bottom;

  void writeTo(_WindowPlacement placement) {
    placement.length = sizeOf<_WindowPlacement>();
    placement.flags = flags;
    placement.showCommand = showCommand;
    placement.minimumPosition.x = minimumX;
    placement.minimumPosition.y = minimumY;
    placement.maximumPosition.x = maximumX;
    placement.maximumPosition.y = maximumY;
    placement.normalPosition.left = left;
    placement.normalPosition.top = top;
    placement.normalPosition.right = right;
    placement.normalPosition.bottom = bottom;
  }
}
