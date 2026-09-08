import 'package:flutter/material.dart';

import '../models/app_settings.dart';

class AppBackgroundPreset {
  const AppBackgroundPreset({
    required this.id,
    required this.label,
    required this.assetPaths,
    required this.fallbackColor,
  });

  final String id;
  final String label;
  final List<String> assetPaths;
  final Color fallbackColor;
}

abstract final class AppBackgroundCatalog {
  static const String defaultId = 'stone_bricks';

  static const List<AppBackgroundPreset> presets = <AppBackgroundPreset>[
    AppBackgroundPreset(
      id: 'stone',
      label: 'Stone',
      assetPaths: <String>['assets/imported/textures/stone.png'],
      fallbackColor: Color(0xFF7D7D7D),
    ),
    AppBackgroundPreset(
      id: 'cobblestone',
      label: 'Cobblestone',
      assetPaths: <String>[
        'assets/imported/textures/cobblestone.png',
        'assets/imported/textures/cobble_stone.png',
      ],
      fallbackColor: Color(0xFF686868),
    ),
    AppBackgroundPreset(
      id: 'stone_bricks',
      label: 'Stone Bricks',
      assetPaths: <String>[
        'assets/imported/textures/stone_bricks.png',
        'assets/imported/textures/stone_brick.png',
      ],
      fallbackColor: Color(0xFF4A4A4A),
    ),
    AppBackgroundPreset(
      id: 'dirt',
      label: 'Dirt',
      assetPaths: <String>['assets/imported/textures/dirt.png'],
      fallbackColor: Color(0xFF866043),
    ),
    AppBackgroundPreset(
      id: 'sand',
      label: 'Sand',
      assetPaths: <String>['assets/imported/textures/sand.png'],
      fallbackColor: Color(0xFFE2CF8E),
    ),
    AppBackgroundPreset(
      id: 'sandstone',
      label: 'Sandstone',
      assetPaths: <String>['assets/imported/textures/sandstone.png'],
      fallbackColor: Color(0xFFD9C27C),
    ),
    AppBackgroundPreset(
      id: 'quartz',
      label: 'Quartz',
      assetPaths: <String>[
        'assets/imported/textures/quartz_block_side.png',
        'assets/imported/textures/quartz_block.png',
        'assets/imported/textures/quartz.png',
      ],
      fallbackColor: Color(0xFFE5DFD4),
    ),
    AppBackgroundPreset(
      id: 'smooth_quartz',
      label: 'Smooth Quartz',
      assetPaths: <String>[
        'assets/imported/textures/smooth_quartz.png',
        'assets/imported/textures/smooth_quartz_block.png',
      ],
      fallbackColor: Color(0xFFE9E5DD),
    ),
    AppBackgroundPreset(
      id: 'red_concrete',
      label: 'Red Concrete',
      assetPaths: <String>['assets/imported/textures/red_concrete.png'],
      fallbackColor: Color(0xFF8E2020),
    ),
    AppBackgroundPreset(
      id: 'orange_concrete',
      label: 'Orange Concrete',
      assetPaths: <String>['assets/imported/textures/orange_concrete.png'],
      fallbackColor: Color(0xFFE06101),
    ),
    AppBackgroundPreset(
      id: 'yellow_concrete',
      label: 'Yellow Concrete',
      assetPaths: <String>['assets/imported/textures/yellow_concrete.png'],
      fallbackColor: Color(0xFFF0AF15),
    ),
    AppBackgroundPreset(
      id: 'lime_concrete',
      label: 'Lime Concrete',
      assetPaths: <String>['assets/imported/textures/lime_concrete.png'],
      fallbackColor: Color(0xFF5EA818),
    ),
    AppBackgroundPreset(
      id: 'green_concrete',
      label: 'Green Concrete',
      assetPaths: <String>['assets/imported/textures/green_concrete.png'],
      fallbackColor: Color(0xFF495B24),
    ),
    AppBackgroundPreset(
      id: 'cyan_concrete',
      label: 'Cyan Concrete',
      assetPaths: <String>['assets/imported/textures/cyan_concrete.png'],
      fallbackColor: Color(0xFF157788),
    ),
    AppBackgroundPreset(
      id: 'light_blue_concrete',
      label: 'Light Blue Concrete',
      assetPaths: <String>[
        'assets/imported/textures/light_blue_concrete.png',
      ],
      fallbackColor: Color(0xFF2389C6),
    ),
    AppBackgroundPreset(
      id: 'blue_concrete',
      label: 'Blue Concrete',
      assetPaths: <String>['assets/imported/textures/blue_concrete.png'],
      fallbackColor: Color(0xFF2C2E8F),
    ),
    AppBackgroundPreset(
      id: 'purple_concrete',
      label: 'Purple Concrete',
      assetPaths: <String>['assets/imported/textures/purple_concrete.png'],
      fallbackColor: Color(0xFF64209C),
    ),
    AppBackgroundPreset(
      id: 'magenta_concrete',
      label: 'Magenta Concrete',
      assetPaths: <String>['assets/imported/textures/magenta_concrete.png'],
      fallbackColor: Color(0xFFA9309F),
    ),
    AppBackgroundPreset(
      id: 'pink_concrete',
      label: 'Pink Concrete',
      assetPaths: <String>['assets/imported/textures/pink_concrete.png'],
      fallbackColor: Color(0xFFD5658E),
    ),
    AppBackgroundPreset(
      id: 'brown_concrete',
      label: 'Brown Concrete',
      assetPaths: <String>['assets/imported/textures/brown_concrete.png'],
      fallbackColor: Color(0xFF603B1F),
    ),
    AppBackgroundPreset(
      id: 'white_concrete',
      label: 'White Concrete',
      assetPaths: <String>['assets/imported/textures/white_concrete.png'],
      fallbackColor: Color(0xFFCFD5D6),
    ),
    AppBackgroundPreset(
      id: 'light_gray_concrete',
      label: 'Light Gray Concrete',
      assetPaths: <String>[
        'assets/imported/textures/light_gray_concrete.png',
      ],
      fallbackColor: Color(0xFF7D7D73),
    ),
    AppBackgroundPreset(
      id: 'gray_concrete',
      label: 'Gray Concrete',
      assetPaths: <String>['assets/imported/textures/gray_concrete.png'],
      fallbackColor: Color(0xFF36393D),
    ),
    AppBackgroundPreset(
      id: 'black_concrete',
      label: 'Black Concrete',
      assetPaths: <String>['assets/imported/textures/black_concrete.png'],
      fallbackColor: Color(0xFF080A0F),
    ),
    AppBackgroundPreset(
      id: 'obsidian',
      label: 'Obsidian',
      assetPaths: <String>['assets/imported/textures/obsidian.png'],
      fallbackColor: Color(0xFF201B35),
    ),
    AppBackgroundPreset(
      id: 'netherrack',
      label: 'Netherrack',
      assetPaths: <String>[
        'assets/imported/textures/netherrack.png',
        'assets/imported/textures/nether_rack.png',
      ],
      fallbackColor: Color(0xFF6E3535),
    ),
    AppBackgroundPreset(
      id: 'end_stone',
      label: 'End Stone',
      assetPaths: <String>['assets/imported/textures/end_stone.png'],
      fallbackColor: Color(0xFFD8D9A7),
    ),
    AppBackgroundPreset(
      id: 'oak_planks',
      label: 'Oak Planks',
      assetPaths: <String>['assets/imported/textures/oak_planks.png'],
      fallbackColor: Color(0xFFB8945F),
    ),
    AppBackgroundPreset(
      id: 'spruce_planks',
      label: 'Spruce Planks',
      assetPaths: <String>['assets/imported/textures/spruce_planks.png'],
      fallbackColor: Color(0xFF73542E),
    ),
    AppBackgroundPreset(
      id: 'birch_planks',
      label: 'Birch Planks',
      assetPaths: <String>['assets/imported/textures/birch_planks.png'],
      fallbackColor: Color(0xFFD9C983),
    ),
    AppBackgroundPreset(
      id: 'jungle_planks',
      label: 'Jungle Planks',
      assetPaths: <String>['assets/imported/textures/jungle_planks.png'],
      fallbackColor: Color(0xFFB47755),
    ),
    AppBackgroundPreset(
      id: 'acacia_planks',
      label: 'Acacia Planks',
      assetPaths: <String>['assets/imported/textures/acacia_planks.png'],
      fallbackColor: Color(0xFFAD5D37),
    ),
    AppBackgroundPreset(
      id: 'dark_oak_planks',
      label: 'Dark Oak Planks',
      assetPaths: <String>['assets/imported/textures/dark_oak_planks.png'],
      fallbackColor: Color(0xFF4A321D),
    ),
    AppBackgroundPreset(
      id: 'mangrove_planks',
      label: 'Mangrove Planks',
      assetPaths: <String>['assets/imported/textures/mangrove_planks.png'],
      fallbackColor: Color(0xFF773A3A),
    ),
    AppBackgroundPreset(
      id: 'cherry_planks',
      label: 'Cherry Planks',
      assetPaths: <String>['assets/imported/textures/cherry_planks.png'],
      fallbackColor: Color(0xFFE2A4A4),
    ),
    AppBackgroundPreset(
      id: 'bamboo_planks',
      label: 'Bamboo Planks',
      assetPaths: <String>['assets/imported/textures/bamboo_planks.png'],
      fallbackColor: Color(0xFFC5A94D),
    ),
    AppBackgroundPreset(
      id: 'pale_oak_planks',
      label: 'Pale Oak Planks',
      assetPaths: <String>['assets/imported/textures/pale_oak_planks.png'],
      fallbackColor: Color(0xFFD4CCC0),
    ),
    AppBackgroundPreset(
      id: 'crimson_planks',
      label: 'Crimson Planks',
      assetPaths: <String>['assets/imported/textures/crimson_planks.png'],
      fallbackColor: Color(0xFF653147),
    ),
    AppBackgroundPreset(
      id: 'warped_planks',
      label: 'Warped Planks',
      assetPaths: <String>['assets/imported/textures/warped_planks.png'],
      fallbackColor: Color(0xFF2B756E),
    ),
    AppBackgroundPreset(
      id: 'bookshelf',
      label: 'Bookshelf',
      assetPaths: <String>['assets/imported/textures/bookshelf.png'],
      fallbackColor: Color(0xFF8B6138),
    ),
    AppBackgroundPreset(
      id: 'iron_block',
      label: 'Iron Block',
      assetPaths: <String>['assets/imported/textures/iron_block.png'],
      fallbackColor: Color(0xFFD8D8D8),
    ),
    AppBackgroundPreset(
      id: 'copper_block',
      label: 'Copper Block',
      assetPaths: <String>[
        'assets/imported/textures/copper_block.png',
        'assets/imported/textures/block_of_copper.png',
      ],
      fallbackColor: Color(0xFFC56E4B),
    ),
    AppBackgroundPreset(
      id: 'gold_block',
      label: 'Gold Block',
      assetPaths: <String>['assets/imported/textures/gold_block.png'],
      fallbackColor: Color(0xFFF4D03F),
    ),
    AppBackgroundPreset(
      id: 'diamond_block',
      label: 'Diamond Block',
      assetPaths: <String>['assets/imported/textures/diamond_block.png'],
      fallbackColor: Color(0xFF55D7C8),
    ),
    AppBackgroundPreset(
      id: 'netherite_block',
      label: 'Netherite Block',
      assetPaths: <String>[
        'assets/imported/textures/netherite_block.png',
        'assets/imported/textures/block_of_netherite.png',
      ],
      fallbackColor: Color(0xFF403A3D),
    ),
  ];

  static AppBackgroundPreset presetFor(String id) {
    return presets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => presets.firstWhere(
        (preset) => preset.id == defaultId,
      ),
    );
  }
}

class AppBackground extends StatelessWidget {
  const AppBackground({
    required this.backgroundId,
    this.opacity = AppSettings.defaultBackgroundOpacity,
    super.key,
  });

  final String backgroundId;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final preset = AppBackgroundCatalog.presetFor(backgroundId);
    // Opacity describes how much of the original texture remains visible:
    // 0 is solid black; 1 leaves the texture completely undimmed.
    final darkness = 1.0 - opacity.clamp(0.0, 1.0).toDouble();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        BlockTextureImage(preset: preset, repeat: true),
        ColoredBox(color: Colors.black.withAlpha((darkness * 255).round())),
      ],
    );
  }
}

class BlockTextureImage extends StatelessWidget {
  const BlockTextureImage({
    required this.preset,
    this.repeat = false,
    this.fit = BoxFit.cover,
    super.key,
  });

  final AppBackgroundPreset preset;
  final bool repeat;
  final BoxFit fit;

  Widget _assetAt(int index) {
    if (index >= preset.assetPaths.length) {
      return ColoredBox(color: preset.fallbackColor);
    }
    return Image.asset(
      preset.assetPaths[index],
      fit: repeat ? null : fit,
      repeat: repeat ? ImageRepeat.repeat : ImageRepeat.noRepeat,
      scale: repeat ? 0.25 : null,
      filterQuality: FilterQuality.none,
      errorBuilder: (_, __, ___) => _assetAt(index + 1),
    );
  }

  @override
  Widget build(BuildContext context) => _assetAt(0);
}
