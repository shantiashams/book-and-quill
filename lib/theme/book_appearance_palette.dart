import 'package:flutter/material.dart';

import '../models/book_record.dart';

class BookAppearancePalette {
  const BookAppearancePalette._();

  static const int _whitePresetIndex = 0;
  static const Set<int> _neutralSaturationPresetIndices = <int>{
    7, // Gray
    8, // Light Gray
    15, // Black
  };

  static const List<String> presetNames = <String>[
    'White',
    'Orange',
    'Magenta',
    'Light Blue',
    'Yellow',
    'Lime',
    'Pink',
    'Gray',
    'Light Gray',
    'Cyan',
    'Purple',
    'Blue',
    'Brown',
    'Green',
    'Red',
    'Black',
  ];

  // Minecraft's sixteen dye colors. Their hue chooses the book-cover hue;
  // the per-design Photoshop-style adjustments are applied below.
  static const List<Color> _presetColors = <Color>[
    Color(0xFFF9FFFE),
    Color(0xFFF9801D),
    Color(0xFFC74EBD),
    Color(0xFF3AB3DA),
    Color(0xFFFED83D),
    Color(0xFF80C71F),
    Color(0xFFF38BAA),
    Color(0xFF474F52),
    Color(0xFF9D9D97),
    Color(0xFF169C9C),
    Color(0xFF8932B8),
    Color(0xFF3C44AA),
    Color(0xFF835432),
    Color(0xFF5E7C16),
    Color(0xFFB02E26),
    Color(0xFF1D1D21),
  ];

  // Rainbow hues first, followed by brown and the neutral colors. These are
  // stable preset indices, so changing their display order never changes the
  // colors already saved on existing books.
  static const List<int> presetDisplayOrder = <int>[
    14, // Red
    1, // Orange
    4, // Yellow
    5, // Lime
    13, // Green
    9, // Cyan
    3, // Light Blue
    11, // Blue
    10, // Purple
    2, // Magenta
    6, // Pink
    12, // Brown
    0, // White
    8, // Light Gray
    7, // Gray
    15, // Black
  ];

  static const List<int> saturationAdjustments = <int>[
    100,
    100,
    100,
    100,
    100,
    100,
  ];

  static const List<int> lightnessAdjustments = <int>[
    10,
    0,
    -15,
    -15,
    -15,
    0,
  ];

  static int get presetCount => _presetColors.length;

  static String presetName(int index) =>
      presetNames[index.clamp(0, presetNames.length - 1).toInt()];

  static Color rawPresetColor(int index) =>
      _presetColors[index.clamp(0, _presetColors.length - 1).toInt()];

  static Color? resolve(BookRecord book) {
    if (book.coverPresetIndex == BookRecord.originalCoverPreset) {
      return null;
    }
    if (book.coverPresetIndex == BookRecord.customCoverPreset) {
      return Color(book.customCoverColorValue);
    }
    return resolvePreset(book.coverPresetIndex, book.visualVariant);
  }

  static Color resolvePreset(int presetIndex, int visualVariant) {
    final source = HSLColor.fromColor(rawPresetColor(presetIndex));
    final variant = visualVariant
        .clamp(0, BookRecord.visualVariantCount - 1)
        .toInt();

    // Photoshop's +100 saturation drives chromatic colors to full
    // saturation. Minecraft's gray, light-gray, and black dye values contain
    // tiny channel differences, so keep those presets neutral instead of
    // amplifying their incidental yellow or blue hue.
    final preserveNeutralSaturation =
        _neutralSaturationPresetIndices.contains(presetIndex);
    final saturated = !preserveNeutralSaturation && source.saturation > 0.01
        ? source.withSaturation(1)
        : source;
    // White becomes visibly cyan when designs 3-5 apply their usual -15
    // lightness adjustment, so those three combinations use neutral lightness.
    final adjustment = presetIndex == _whitePresetIndex &&
            variant >= 2 &&
            variant <= 4
        ? 0
        : lightnessAdjustments[variant];
    final lightness = adjustment >= 0
        ? saturated.lightness +
            (1 - saturated.lightness) * (adjustment / 100)
        : saturated.lightness * (1 + adjustment / 100);
    return saturated
        .withLightness(lightness.clamp(0.0, 1.0).toDouble())
        .toColor();
  }
}
