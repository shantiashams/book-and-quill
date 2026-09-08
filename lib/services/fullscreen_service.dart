import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

/// Controls borderless fullscreen and book-only transparency on Windows.
///
/// Other supported Flutter platforms fall back to hiding their system UI.
/// Keeping the Windows implementation here avoids requiring another package or
/// changes to the native runner for the F11 and F1 shortcuts.
class FullscreenService {
  static const int transparentBackgroundArgb = 0xFF010203;

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
      return true;
    }

    windows.exitTransparent();
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
      _windows?.exitTransparent();
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
  static const int _layeredColorKey = 0x00000001;
  static const int _layeredAlpha = 0x00000002;
  // COLORREF stores the Flutter RGB(1, 2, 3) background as 0x00BBGGRR.
  static const int _transparentColorKey = 0x00030201;
  static const int _monitorDefaultToNearest = 0x00000002;
  static const int _heapZeroMemory = 0x00000008;
  static const int _noSize = 0x0001;
  static const int _noMove = 0x0002;
  static const int _noZOrder = 0x0004;
  static const int _frameChanged = 0x0020;
  static const int _noOwnerZOrder = 0x0200;

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
    _setWindowPos(
      window,
      nullptr,
      0,
      0,
      0,
      0,
      _noMove | _noSize | _noZOrder | _noOwnerZOrder | _frameChanged,
    );
    _transparentWindow = window;
    _windowExtendedStyle = extendedStyle;
    return true;
  }

  bool exitTransparent() {
    final window = _transparentWindow;
    final extendedStyle = _windowExtendedStyle;
    if (window == null || extendedStyle == null) {
      return true;
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
      _noMove | _noSize | _noZOrder | _noOwnerZOrder | _frameChanged,
    );
    _transparentWindow = null;
    _windowExtendedStyle = null;
    return true;
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
