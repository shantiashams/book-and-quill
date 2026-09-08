import 'package:flutter/material.dart';

import '../services/game_sound_service.dart';

class PixelButton extends StatefulWidget {
  const PixelButton({
    required this.label,
    required this.onPressed,
    this.width = 140,
    this.enabled = true,
    this.compact = false,
    this.sounds,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final double width;
  final bool enabled;
  final bool compact;
  final GameSoundService? sounds;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;
    final background = !active
        ? const Color(0xFF454545)
        : _hovering
            ? const Color(0xFF788F43)
            : const Color(0xFF6A6A6A);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
        _pressed = false;
      }),
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: active ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: active ? () => setState(() => _pressed = false) : null,
        onTapUp: active
            ? (_) {
                setState(() => _pressed = false);
                widget.sounds?.play(GameSound.click);
                widget.onPressed();
              }
            : null,
        child: Transform.translate(
          offset: Offset(0, _pressed ? 2 : 0),
          child: SizedBox(
            width: widget.width,
            height: widget.compact ? 35 : 42,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.asset(
                  !active
                      ? 'assets/imported/textures/button_disabled.png'
                      : _hovering
                          ? 'assets/imported/textures/button_highlighted.png'
                          : 'assets/imported/textures/button.png',
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: background,
                  ),
                ),
                IgnorePointer(
                  child: _ButtonBevel(enabled: active),
                ),
                Center(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: active ? Colors.white : const Color(0xFF9A9A9A),
                      fontSize: widget.compact ? 14 : 16,
                      shadows: const <Shadow>[
                        Shadow(color: Color(0xFF202020), offset: Offset(2, 2)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonBevel extends StatelessWidget {
  const _ButtonBevel({
    required this.enabled,
  });

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: enabled
                ? const Color(0xFFBDBDBD)
                : const Color(0xFF666666),
            width: 2,
          ),
          top: BorderSide(
            color: enabled
                ? const Color(0xFFBDBDBD)
                : const Color(0xFF666666),
            width: 2,
          ),
          right: const BorderSide(color: Color(0xFF202020), width: 2),
          bottom: const BorderSide(color: Color(0xFF202020), width: 2),
        ),
      ),
    );
  }
}
