import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/game_sound_service.dart';
import '../services/android_platform.dart';
import '../theme/book_and_quill_theme.dart';

class MusicToastOverlay extends StatefulWidget {
  const MusicToastOverlay({required this.sounds, super.key});

  final GameSoundService sounds;

  @override
  State<MusicToastOverlay> createState() => _MusicToastOverlayState();
}

class _MusicToastOverlayState extends State<MusicToastOverlay> {
  bool _hovering = false;
  bool _autoExpanded = false;
  bool _touchExpanded = false;

  bool get _expanded =>
      widget.sounds.musicIslandAlwaysExpanded.value || _autoExpanded || _touchExpanded;

  @override
  void initState() {
    super.initState();
    widget.sounds.musicToast.addListener(_handleMusicToast);
    widget.sounds.musicIslandAlwaysExpanded.addListener(_handleIslandSize);
    if (widget.sounds.musicToast.value != null) {
      _autoExpanded = true;
    }
  }

  @override
  void didUpdateWidget(covariant MusicToastOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sounds == widget.sounds) {
      return;
    }
    oldWidget.sounds.musicToast.removeListener(_handleMusicToast);
    oldWidget.sounds.musicIslandAlwaysExpanded.removeListener(_handleIslandSize);
    widget.sounds.musicToast.addListener(_handleMusicToast);
    widget.sounds.musicIslandAlwaysExpanded.addListener(_handleIslandSize);
    _handleMusicToast();
  }

  void _handleIslandSize() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleMusicToast() {
    if (!mounted) {
      return;
    }
    setState(() {
      _autoExpanded = _hovering || widget.sounds.musicToast.value != null;
    });
  }

  void _handleEnter(PointerEnterEvent _) {
    setState(() {
      _hovering = true;
      _autoExpanded = true;
    });
  }

  void _handleExit(PointerExitEvent _) {
    setState(() {
      _hovering = false;
      _autoExpanded = false;
    });
  }

  @override
  void dispose() {
    widget.sounds.musicToast.removeListener(_handleMusicToast);
    widget.sounds.musicIslandAlwaysExpanded.removeListener(_handleIslandSize);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AndroidPlatform.isAndroid) return _buildTouchIsland(context);
    final availableWidth =
        math.max(0.0, MediaQuery.sizeOf(context).width - 24).toDouble();
    final expandedWidth = math.min(400.0, availableWidth).toDouble();
    final collapsedWidth = math.min(190.0, expandedWidth).toDouble();
    const expandedHoverMargin = 16.0;
    final expandedHoverWidth =
        math.min(availableWidth, expandedWidth + expandedHoverMargin * 2)
            .toDouble();

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.sounds.musicIslandEnabled,
        builder: (context, islandEnabled, _) {
          if (!islandEnabled) {
            return const SizedBox.shrink();
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.sounds.musicControlsEnabled,
              builder: (context, controlsEnabled, _) {
                return ValueListenableBuilder<MusicPlaybackInfo?>(
                  valueListenable: widget.sounds.musicPlayback,
                  builder: (context, playback, _) {
                    return MouseRegion(
                      onEnter: _handleEnter,
                      onExit: _handleExit,
                      cursor: _expanded
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width:
                            _expanded ? expandedHoverWidth : collapsedWidth,
                        height: _expanded
                            ? 132 + expandedHoverMargin
                            : 24,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Semantics(
                            container: true,
                            label: playback == null
                                ? 'Music controller'
                                : 'Now playing ${playback.title} by '
                                    '${playback.artist}',
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width:
                                  _expanded ? expandedWidth : collapsedWidth,
                              height: _expanded ? 132 : 24,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: const Color(0xF51B140B),
                                border: Border.all(
                                  color: BookAndQuillColors.gold,
                                  width: 2,
                                ),
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(15),
                                  bottomRight: Radius.circular(15),
                                ),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    color: Color(0x88000000),
                                    offset: Offset(0, 5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: _expanded
                                    ? FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.topCenter,
                                        child: SizedBox(
                                          width: expandedWidth,
                                          height: 132,
                                          child: _ExpandedMusicController(
                                            sounds: widget.sounds,
                                            playback: playback,
                                            controlsEnabled: controlsEnabled,
                                          ),
                                        ),
                                      )
                                    : _CollapsedMusicController(
                                        sounds: widget.sounds,
                                        playback: playback,
                                        controlsEnabled: controlsEnabled,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildTouchIsland(BuildContext context) {
    return Positioned(left: 12, right: 12,
      top: MediaQuery.paddingOf(context).top,
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.sounds.musicIslandEnabled,
        builder: (context, enabled, _) {
          if (!enabled) return const SizedBox.shrink();
          return Align(alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400),
              child: Material(color: const Color(0xF51B140B),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: BookAndQuillColors.gold, width: 2),
                  borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: AnimatedSize(duration: const Duration(milliseconds: 180),
                  alignment: Alignment.topCenter,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: widget.sounds.musicControlsEnabled,
                    builder: (context, controls, _) =>
                      ValueListenableBuilder<MusicPlaybackInfo?>(
                        valueListenable: widget.sounds.musicPlayback,
                        builder: (context, playback, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            SizedBox(height: 48, child: Row(children: <Widget>[
                              Expanded(child: _CollapsedMusicController(
                                sounds: widget.sounds, playback: playback,
                                controlsEnabled: controls)),
                              if (!widget.sounds.musicIslandAlwaysExpanded.value)
                                IconButton(
                                  tooltip: _expanded ? 'Close music controls' : 'Open music controls',
                                  onPressed: () => setState(() {
                                    final wasExpanded = _expanded;
                                    _autoExpanded = false;
                                    _touchExpanded = !wasExpanded;
                                  }),
                                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                                ),
                            ])),
                            if (_expanded) SizedBox(height: 132,
                              child: _ExpandedMusicController(sounds: widget.sounds,
                                playback: playback, controlsEnabled: controls)),
                          ],
                        ),
                      ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CollapsedMusicController extends StatelessWidget {
  const _CollapsedMusicController({
    required this.sounds,
    required this.playback,
    required this.controlsEnabled,
  });

  final GameSoundService sounds;
  final MusicPlaybackInfo? playback;
  final bool controlsEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 5),
      child: _MusicProgressBar(
        progress: playback?.progress ?? 0,
        paused: playback?.isPaused ?? false,
        enabled: controlsEnabled &&
            playback != null &&
            playback!.canSeek &&
            playback!.duration > Duration.zero,
        height: 8,
        onSeek: sounds.seekMusic,
      ),
    );
  }
}

class _ExpandedMusicController extends StatelessWidget {
  const _ExpandedMusicController({
    required this.sounds,
    required this.playback,
    required this.controlsEnabled,
  });

  final GameSoundService sounds;
  final MusicPlaybackInfo? playback;
  final bool controlsEnabled;

  @override
  Widget build(BuildContext context) {
    final title = playback?.title ??
        (controlsEnabled ? 'NO MUSIC PLAYING' : 'MUSIC IS OFF');
    final artist = playback?.artist ??
        (controlsEnabled ? 'Press play to begin' : 'Enable music in Sounds');
    final external = playback?.isExternal ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
      child: Column(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                _MusicCover(playback: playback),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BookAndQuillColors.gold,
                          fontSize: 17,
                          shadows: <Shadow>[
                            Shadow(
                              color: Color(0xFF33220A),
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BookAndQuillColors.parchment,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: <Widget>[
                          _TransportButton(
                            label: 'Previous song',
                            icon: Icons.skip_previous,
                            enabled: controlsEnabled &&
                                (!external ||
                                    (playback?.canPrevious ?? false)),
                            sounds: sounds,
                            onPressed: () => unawaited(sounds.previousMusic()),
                          ),
                          const SizedBox(width: 7),
                          _TransportButton(
                            label: playback?.isPaused ?? true
                                ? 'Play music'
                                : 'Pause music',
                            icon: playback?.isPaused ?? true
                                ? Icons.play_arrow
                                : Icons.pause,
                            emphasized: true,
                            enabled: controlsEnabled &&
                                (!external ||
                                    (playback?.canPlay ?? false) ||
                                    (playback?.canPause ?? false)),
                            sounds: sounds,
                            onPressed: () =>
                                unawaited(sounds.toggleMusicPause()),
                          ),
                          const SizedBox(width: 7),
                          _TransportButton(
                            label: 'Next song',
                            icon: Icons.skip_next,
                            enabled: controlsEnabled &&
                                (!external || (playback?.canNext ?? false)),
                            sounds: sounds,
                            onPressed: () => unawaited(sounds.nextMusic()),
                          ),
                          const Spacer(),
                          Text(
                            '${_formatDuration(playback?.position)} / '
                            '${_formatDuration(playback?.duration)}',
                            style: const TextStyle(
                              color: BookAndQuillColors.parchmentDark,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          _MusicProgressBar(
            progress: playback?.progress ?? 0,
            paused: playback?.isPaused ?? false,
            enabled: controlsEnabled &&
                playback != null &&
                playback!.canSeek &&
                playback!.duration > Duration.zero,
            height: 8,
            onSeek: sounds.seekMusic,
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration? value) {
    if (value == null || value.isNegative) {
      return '0:00';
    }
    final totalSeconds = value.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _MusicCover extends StatelessWidget {
  const _MusicCover({required this.playback});

  final MusicPlaybackInfo? playback;

  @override
  Widget build(BuildContext context) {
    final artworkBytes = playback?.artworkBytes;
    final artworkPath = playback?.artworkAssetPath;
    Widget fallback() {
      return Center(
        child: Image.asset(
          'assets/imported/textures/book_item.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.menu_book,
            color: BookAndQuillColors.parchment,
            size: 42,
          ),
        ),
      );
    }

    final Widget image;
    if (artworkBytes != null && artworkBytes.isNotEmpty) {
      image = Image.memory(
        artworkBytes,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => fallback(),
      );
    } else if (artworkPath != null) {
      image = Image.asset(
        artworkPath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => fallback(),
      );
    } else {
      image = fallback();
    }

    return Container(
      width: 72,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2013),
        border: Border.all(color: BookAndQuillColors.gold, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0xAA000000), offset: Offset(3, 3)),
        ],
      ),
      child: image,
    );
  }
}

class _MusicProgressBar extends StatefulWidget {
  const _MusicProgressBar({
    required this.progress,
    required this.paused,
    required this.enabled,
    required this.onSeek,
    this.height = 8,
  });

  final double progress;
  final bool paused;
  final bool enabled;
  final ValueChanged<double> onSeek;
  final double height;

  @override
  State<_MusicProgressBar> createState() => _MusicProgressBarState();
}

class _MusicProgressBarState extends State<_MusicProgressBar> {
  double? _previewProgress;

  double _progressAt(double localX, double width) {
    if (width <= 0) {
      return 0;
    }
    return (localX / width).clamp(0.0, 1.0).toDouble();
  }

  void _preview(Offset position, double width) {
    setState(() {
      _previewProgress = _progressAt(position.dx, width);
    });
  }

  void _commit() {
    final value = _previewProgress;
    if (value == null) {
      return;
    }
    widget.onSeek(value);
    setState(() => _previewProgress = null);
  }

  @override
  Widget build(BuildContext context) {
    final shownProgress =
        (_previewProgress ?? widget.progress).clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.enabled
                ? (details) => _preview(details.localPosition, width)
                : null,
            onTapUp: widget.enabled ? (_) => _commit() : null,
            onTapCancel: widget.enabled
                ? () => setState(() => _previewProgress = null)
                : null,
            onHorizontalDragStart: widget.enabled
                ? (details) => _preview(details.localPosition, width)
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (details) => _preview(details.localPosition, width)
                : null,
            onHorizontalDragEnd: widget.enabled ? (_) => _commit() : null,
            onHorizontalDragCancel: widget.enabled
                ? () => setState(() => _previewProgress = null)
                : null,
            child: SizedBox(
              height: math.max(widget.height, 12.0).toDouble(),
              child: Center(
                child: SizedBox(
                  height: widget.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A2A14),
                            border: Border.all(
                              color: BookAndQuillColors.parchmentDark,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 1,
                        top: 1,
                        bottom: 1,
                        width: math
                            .max(0.0, (width - 2) * shownProgress)
                            .toDouble(),
                        child: ColoredBox(
                          color: widget.paused
                              ? const Color(0xFFC89E35)
                              : BookAndQuillColors.gold,
                        ),
                      ),
                      if (widget.enabled && width > 8)
                        Positioned(
                          left: (width - 8) * shownProgress,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: widget.height + 4,
                            decoration: BoxDecoration(
                              color: BookAndQuillColors.gold,
                              border: Border.all(
                                color: BookAndQuillColors.woodDark,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TransportButton extends StatefulWidget {
  const _TransportButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.sounds,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final GameSoundService sounds;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final color = !enabled
        ? const Color(0xFF352B1C)
        : _hovering
            ? const Color(0xFFD9AA36)
            : widget.emphasized
                ? const Color(0xFFA97922)
                : const Color(0xFF6D4A20);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        onEnter: (_) {
          if (enabled) {
            setState(() => _hovering = true);
          }
        },
        onExit: (_) => setState(() {
          _hovering = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel:
              enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: enabled
              ? (_) {
                  setState(() => _pressed = false);
                  unawaited(widget.sounds.play(GameSound.click));
                  widget.onPressed();
                }
              : null,
          child: Transform.translate(
            offset: Offset(0, _pressed ? 2 : 0),
            child: Container(
              width: widget.emphasized ? 39 : 34,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                border: const Border(
                  left: BorderSide(
                    color: BookAndQuillColors.parchment,
                    width: 1.5,
                  ),
                  top: BorderSide(
                    color: BookAndQuillColors.parchment,
                    width: 1.5,
                  ),
                  right: BorderSide(
                    color: BookAndQuillColors.woodDark,
                    width: 1.5,
                  ),
                  bottom: BorderSide(
                    color: BookAndQuillColors.woodDark,
                    width: 1.5,
                  ),
                ),
              ),
              child: Icon(
                widget.icon,
                color: enabled
                    ? BookAndQuillColors.parchment
                    : const Color(0xFF776A55),
                size: widget.emphasized ? 23 : 21,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
