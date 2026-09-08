import 'package:flutter/material.dart';

abstract final class BookAndQuillColors {
  static const ink = Color(0xFF1C1711);
  static const parchment = Color(0xFFE8D6A6);
  static const parchmentDark = Color(0xFFC3A56A);
  static const wood = Color(0xFF6D4022);
  static const woodDark = Color(0xFF2C170E);
  static const moss = Color(0xFF4D642D);
  static const stone = Color(0xFF242424);
  static const gold = Color(0xFFF4C950);
}

abstract final class BookAndQuillTheme {
  static ThemeData get theme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: BookAndQuillColors.stone,
      colorScheme: const ColorScheme.dark(
        primary: BookAndQuillColors.gold,
        secondary: BookAndQuillColors.moss,
        surface: BookAndQuillColors.woodDark,
      ),
      fontFamily: 'MinecraftLocalV2',
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: BookAndQuillColors.ink,
        selectionColor: Color(0x66879B5A),
        selectionHandleColor: BookAndQuillColors.moss,
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: Color(0xF0180018),
          border: Border.fromBorderSide(
            BorderSide(color: Color(0xFF502F7E), width: 2),
          ),
        ),
        textStyle: TextStyle(color: Colors.white, fontSize: 15),
      ),
    );
  }
}
