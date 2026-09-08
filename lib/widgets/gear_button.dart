import 'package:flutter/material.dart';

import '../services/game_sound_service.dart';

class GearButton extends StatefulWidget {
  const GearButton({
    required this.onPressed,
    this.sounds,
    this.size = 40,
    super.key,
  });

  static const String assetPath = 'assets/imported/textures/settings.png';

  final VoidCallback onPressed;
  final GameSoundService? sounds;
  final double size;

  @override
  State<GearButton> createState() => _GearButtonState();
}

class _GearButtonState extends State<GearButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Settings',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() {
          _hovering = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.sounds?.play(GameSound.click);
            widget.onPressed();
          },
          child: Transform.translate(
            offset: Offset(0, _pressed ? 2 : 0),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.asset(
                    _hovering
                        ? 'assets/imported/textures/button_highlighted.png'
                        : 'assets/imported/textures/button.png',
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: _hovering
                          ? const Color(0xFF788F43)
                          : const Color(0xFF6A6A6A),
                    ),
                  ),
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: Color(0xFFBDBDBD),
                            width: 2,
                          ),
                          top: BorderSide(
                            color: Color(0xFFBDBDBD),
                            width: 2,
                          ),
                          right: BorderSide(
                            color: Color(0xFF202020),
                            width: 2,
                          ),
                          bottom: BorderSide(
                            color: Color(0xFF202020),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(widget.size * 0.20),
                    child: Image.asset(
                      GearButton.assetPath,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.settings,
                        color: Colors.white,
                        size: 23,
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
  }
}
