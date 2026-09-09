import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/book_record.dart';
import '../services/android_platform.dart';
import '../theme/book_and_quill_theme.dart';
import '../theme/book_appearance_palette.dart';

class ChiseledBookshelf extends StatelessWidget {
  const ChiseledBookshelf({
    required this.slots,
    required this.onSlotPressed,
    required this.onSlotSecondaryPressed,
    this.onBookPointerDown,
    this.highlightedSlot,
    this.draggedSlot,
    this.dragActive = false,
    super.key,
  });

  // The six physical shelf slots are fixed 4×6-pixel hit areas. A five-pixel
  // book design is bottom-aligned inside its slot, exactly like the vanilla
  // occupied texture.
  static const List<Rect> slotRects = <Rect>[
    Rect.fromLTWH(0.0625, 0.0625, 0.2500, 0.3750),
    Rect.fromLTWH(0.3750, 0.0625, 0.2500, 0.3750),
    Rect.fromLTWH(0.6875, 0.0625, 0.2500, 0.3750),
    Rect.fromLTWH(0.0625, 0.5625, 0.2500, 0.3750),
    Rect.fromLTWH(0.3750, 0.5625, 0.2500, 0.3750),
    Rect.fromLTWH(0.6875, 0.5625, 0.2500, 0.3750),
  ];

  // These remain tied to the six vanilla book designs, not their destination
  // shelf positions. That lets any saved book design appear in any slot.
  static const List<Rect> visualSourceRects = <Rect>[
    Rect.fromLTWH(0.0625, 0.1250, 0.2500, 0.3125),
    Rect.fromLTWH(0.3750, 0.0625, 0.2500, 0.3750),
    Rect.fromLTWH(0.6875, 0.0625, 0.2500, 0.3750),
    Rect.fromLTWH(0.0625, 0.5625, 0.2500, 0.3750),
    Rect.fromLTWH(0.3750, 0.6250, 0.2500, 0.3125),
    Rect.fromLTWH(0.6875, 0.5625, 0.2500, 0.3750),
  ];

  final List<BookRecord?> slots;
  final ValueChanged<int> onSlotPressed;
  final void Function(int slot, Offset globalPosition) onSlotSecondaryPressed;
  final void Function(int slot, PointerDownEvent event)? onBookPointerDown;
  final int? highlightedSlot;
  final int? draggedSlot;
  final bool dragActive;

  static int? slotAtLocalPosition(Offset position, Size shelfSize) {
    final side = shelfSize.shortestSide;
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx > side ||
        position.dy > side) {
      return null;
    }
    for (var slot = 0; slot < slotRects.length; slot++) {
      final normalizedRect = slotRects[slot];
      final rect = Rect.fromLTWH(
        side * normalizedRect.left,
        side * normalizedRect.top,
        side * normalizedRect.width,
        side * normalizedRect.height,
      );
      if (rect.contains(position)) {
        return slot;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: Image.asset(
                  'assets/imported/textures/chiseled_bookshelf_empty.png',
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                  errorBuilder: (_, __, ___) => CustomPaint(
                    painter: _FallbackShelfPainter(),
                  ),
                ),
              ),
              for (var slot = 0; slot < slotRects.length; slot++)
                _positionedSlot(context, slot, size),
            ],
          );
        },
      ),
    );
  }

  Widget _positionedSlot(BuildContext context, int slot, double size) {
    final normalizedRect = slotRects[slot];
    return Positioned(
      left: size * normalizedRect.left,
      top: size * normalizedRect.top,
      width: size * normalizedRect.width,
      height: size * normalizedRect.height,
      child: _ShelfSlot(
        key: ValueKey<String>('shelf-slot-$slot'),
        slot: slot,
        book: slots[slot],
        shelfSize: size,
        dropHighlighted: highlightedSlot == slot,
        isDragging: draggedSlot == slot,
        dragActive: dragActive,
        onPointerDown: (event) => onBookPointerDown?.call(slot, event),
        onPressed: () => onSlotPressed(slot),
        onSecondaryPressed: (position) =>
            onSlotSecondaryPressed(slot, position),
      ),
    );
  }
}

class BookAppearancePreview extends StatelessWidget {
  const BookAppearancePreview({
    required this.visualVariant,
    required this.coverColor,
    this.width = 112,
    super.key,
  });

  final int visualVariant;
  final Color? coverColor;
  final double width;

  @override
  Widget build(BuildContext context) {
    final variant = visualVariant
        .clamp(0, BookRecord.visualVariantCount - 1)
        .toInt();
    final sourceRect = ChiseledBookshelf.visualSourceRects[variant];
    final height = width * sourceRect.height / sourceRect.width;
    final shelfSize = width / sourceRect.width;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF120B08),
        border: Border.all(color: const Color(0xFF6F5135), width: 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SizedBox(
          width: width,
          height: height,
          child: _OccupiedTextureCrop(
            visualVariant: variant,
            shelfSize: shelfSize,
            coverColor: coverColor,
          ),
        ),
      ),
    );
  }
}

class _ShelfSlot extends StatefulWidget {
  const _ShelfSlot({
    required this.slot,
    required this.book,
    required this.shelfSize,
    required this.dropHighlighted,
    required this.isDragging,
    required this.dragActive,
    required this.onPointerDown,
    required this.onPressed,
    required this.onSecondaryPressed,
    super.key,
  });

  final int slot;
  final BookRecord? book;
  final double shelfSize;
  final bool dropHighlighted;
  final bool isDragging;
  final bool dragActive;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback onPressed;
  final ValueChanged<Offset> onSecondaryPressed;

  @override
  State<_ShelfSlot> createState() => _ShelfSlotState();
}

class _ShelfSlotState extends State<_ShelfSlot>
    with SingleTickerProviderStateMixin {
  bool _hovering = false;
  late final AnimationController _glintController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void initState() {
    super.initState();
    _syncGlintAnimation();
  }

  @override
  void didUpdateWidget(covariant _ShelfSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book?.favorite != widget.book?.favorite) {
      _syncGlintAnimation();
    }
  }

  void _syncGlintAnimation() {
    if (widget.book?.favorite ?? false) {
      _glintController.repeat();
    } else {
      _glintController.stop();
      _glintController.value = 0;
    }
  }

  @override
  void dispose() {
    _glintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final visualVariant = (book?.visualVariant ?? 0)
        .clamp(0, BookRecord.visualVariantCount - 1)
        .toInt();
    final visualRect = ChiseledBookshelf.visualSourceRects[visualVariant];
    final visualHeightFactor = visualRect.height / 0.375;

    return MouseRegion(
        cursor: widget.dragActive
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Listener(
          onPointerDown: book == null ? null : widget.onPointerDown,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            onLongPressStart: AndroidPlatform.isAndroid
                ? (details) => widget.onSecondaryPressed(details.globalPosition)
                : null,
            onSecondaryTapUp: (details) =>
                widget.onSecondaryPressed(details.globalPosition),
            child: AnimatedScale(
              scale: widget.dropHighlighted ? 1.025 : 1.0,
              duration: const Duration(milliseconds: 110),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                decoration: BoxDecoration(
                  color: _hovering && book == null
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.transparent,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AnimatedOpacity(
                      opacity: widget.isDragging ? 0.22 : 1.0,
                      duration: const Duration(milliseconds: 120),
                      child: book == null
                          ? const SizedBox.expand()
                          : Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                widthFactor: 1,
                                heightFactor: visualHeightFactor,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: <Widget>[
                                    _OccupiedTextureCrop(
                                      visualVariant: visualVariant,
                                      shelfSize: widget.shelfSize,
                                      coverColor:
                                          BookAppearancePalette.resolve(book),
                                    ),
                                    if (_hovering)
                                      IgnorePointer(
                                        child: ColoredBox(
                                          color: Colors.white.withValues(
                                            alpha: 0.07,
                                          ),
                                        ),
                                      ),
                                    if (book.favorite)
                                      IgnorePointer(
                                        child: _EnchantmentGlint(
                                          animation: _glintController,
                                        ),
                                      ),
                                    IgnorePointer(
                                      child: _BookTitleLabel(
                                        title: book.title,
                                        shelfSize: widget.shelfSize,
                                        visualVariant: visualVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    if (widget.dropHighlighted)
                      IgnorePointer(
                        child: book == null
                            ? ColoredBox(
                                color: BookAndQuillColors.gold.withValues(
                                  alpha: 0.22,
                                ),
                              )
                            : ColoredBox(
                                color: BookAndQuillColors.gold.withValues(
                                  alpha: 0.27,
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

class _BookTitleLabel extends StatelessWidget {
  const _BookTitleLabel({
    required this.title,
    required this.shelfSize,
    required this.visualVariant,
  });

  static const List<Rect> _bandRects = <Rect>[
    Rect.fromLTWH(1 / 4, 2 / 5, 2 / 4, 2 / 5),
    Rect.fromLTWH(0, 3 / 6, 1, 1 / 6),
    Rect.fromLTWH(0, 1 / 3, 1, 1 / 3),
    Rect.fromLTWH(0, 2 / 6, 1, 1 / 6),
    Rect.fromLTWH(0, 2 / 5, 1, 1 / 5),
    Rect.fromLTWH(1 / 4, 2 / 6, 2 / 4, 2 / 6),
  ];

  final String title;
  final double shelfSize;
  final int visualVariant;

  @override
  Widget build(BuildContext context) {
    final displayTitle = title.trim().isEmpty ? 'Untitled Book' : title.trim();
    final variant = visualVariant.clamp(0, _bandRects.length - 1).toInt();
    final band = _bandRects[variant];
    final singleRowBand = variant == 1 || variant == 3 || variant == 4;
    final safeHeightFactor = singleRowBand ? 0.70 : 0.84;
    final fontSize = (shelfSize * 0.019).clamp(8.0, 13.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: <Widget>[
            Positioned(
              left: constraints.maxWidth * band.left,
              top: constraints.maxHeight * band.top,
              width: constraints.maxWidth * band.width,
              height: constraints.maxHeight * band.height,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.center,
                  child: FractionallySizedBox(
                    widthFactor: 0.96,
                    heightFactor: safeHeightFactor,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        displayTitle,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1,
                        ).copyWith(
                          fontSize: fontSize,
                          shadows: const <Shadow>[
                            Shadow(
                              color: Color(0xFF100905),
                              offset: Offset(2, 2),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EnchantmentGlint extends StatelessWidget {
  const _EnchantmentGlint({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    // Minecraft renders item glint as two oversized scrolling texture passes.
    // The parent slot is the exact occupied book rectangle, so clipping to the
    // slot reproduces the vanilla silhouette without another approximate mask.
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _GlintTexturePass(
            animation: animation,
            angle: -0.48,
            speed: 1.0,
            direction: 1,
            opacity: 0.18,
            color: const Color(0xFF8D63FF),
          ),
          _GlintTexturePass(
            animation: animation,
            angle: 0.22,
            speed: 0.63,
            phaseOffset: 0.37,
            direction: -1,
            opacity: 0.11,
            color: const Color(0xFFB59CFF),
          ),
        ],
      ),
    );
  }
}

class _GlintTexturePass extends StatelessWidget {
  const _GlintTexturePass({
    required this.animation,
    required this.angle,
    required this.speed,
    required this.direction,
    required this.opacity,
    required this.color,
    this.phaseOffset = 0,
  });

  final Animation<double> animation;
  final double angle;
  final double speed;
  final double phaseOffset;
  final double direction;
  final double opacity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final phase = (animation.value * speed + phaseOffset) % 1.0;
            return OverflowBox(
              alignment: Alignment.center,
              minWidth: size.width * 4.5,
              maxWidth: size.width * 4.5,
              minHeight: size.height * 4.5,
              maxHeight: size.height * 4.5,
              child: Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(
                    (phase - 0.5) * size.width * 0.34 * direction,
                    (phase - 0.5) * size.height * 0.18,
                  ),
                  child: Transform.rotate(
                    angle: angle,
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: Image.asset(
            'assets/imported/textures/enchanted_glint_item.png',
            width: size.width * 4.5,
            height: size.height * 4.5,
            repeat: ImageRepeat.repeat,
            fit: BoxFit.none,
            scale: 0.22,
            filterQuality: FilterQuality.none,
            color: color,
            colorBlendMode: BlendMode.screen,
            errorBuilder: (_, __, ___) => const _FallbackGlint(),
          ),
        );
      },
    );
  }
}

class _FallbackGlint extends StatelessWidget {
  const _FallbackGlint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0x006E38A8),
            Color(0xCC7B45C6),
            Color(0xDDD9C9FF),
            Color(0xCC4B71C6),
            Color(0x006E38A8),
          ],
          stops: <double>[0.18, 0.38, 0.5, 0.62, 0.82],
        ),
      ),
    );
  }
}

class _OccupiedTextureCrop extends StatelessWidget {
  const _OccupiedTextureCrop({
    required this.visualVariant,
    required this.shelfSize,
    required this.coverColor,
  });

  final int visualVariant;
  final double shelfSize;
  final Color? coverColor;

  @override
  Widget build(BuildContext context) {
    final variant = visualVariant
        .clamp(0, BookRecord.visualVariantCount - 1)
        .toInt();
    final sourceRect = ChiseledBookshelf.visualSourceRects[variant];
    final cropOffset = Offset(
      shelfSize * sourceRect.left,
      shelfSize * sourceRect.top,
    );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const _BookSpines(),
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: shelfSize,
            maxWidth: shelfSize,
            minHeight: shelfSize,
            maxHeight: shelfSize,
            child: Transform.translate(
              offset: -cropOffset,
              child: Image.asset(
                'assets/imported/textures/chiseled_bookshelf_occupied.png',
                width: shelfSize,
                height: shelfSize,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        if (coverColor != null)
          CustomPaint(
            painter: _BookColorVariantPainter(
              visualVariant: variant,
              coverColor: coverColor!,
            ),
          ),
      ],
    );
  }
}

class _BookColorVariantPainter extends CustomPainter {
  const _BookColorVariantPainter({
    required this.visualVariant,
    required this.coverColor,
  });

  static const List<double> _shadeFactors = <double>[
    0.38,
    0.54,
    0.72,
    0.90,
    1.10,
  ];

  // Each entry represents the exact pixels inside one of Minecraft's six book
  // rectangles. A negative value leaves the original texture pixel untouched;
  // all other values select a cover-color shade from darkest to lightest. In
  // designs 1 and 6, both complete middle rows are protected: the 2×2 gold
  // center plus the two vertical brown pixels at either side.
  static const List<List<List<int>>> _shadeMaps = <List<List<int>>>[
    <List<int>>[
      <int>[1, 3, 2, 1],
      <int>[2, 4, 2, 1],
      <int>[-1, -1, -1, -1],
      <int>[-1, -1, -1, -1],
      <int>[2, 3, 2, 1],
    ],
    <List<int>>[
      <int>[2, 2, 1, 1],
      <int>[2, 3, 2, 1],
      <int>[3, 4, 2, 1],
      <int>[-1, -1, -1, -1],
      <int>[3, 4, 2, 1],
      <int>[2, 3, 2, 1],
    ],
    <List<int>>[
      <int>[2, 2, 1, 1],
      <int>[3, 4, 2, 1],
      <int>[2, 3, 1, 0],
      <int>[2, 3, 1, 0],
      <int>[3, 4, 2, 1],
      <int>[2, 3, 1, 0],
    ],
    <List<int>>[
      <int>[1, 2, 1, 1],
      <int>[1, 3, 2, 1],
      <int>[-1, -1, -1, -1],
      <int>[3, 4, 3, 1],
      <int>[3, 4, 3, 1],
      <int>[2, 3, 2, 1],
    ],
    <List<int>>[
      <int>[3, 4, 2, 1],
      <int>[3, 4, 2, 1],
      <int>[-1, -1, -1, -1],
      <int>[3, 4, 2, 1],
      <int>[2, 3, 2, 1],
    ],
    <List<int>>[
      <int>[2, 2, 1, 1],
      <int>[3, 4, 2, 1],
      <int>[-1, -1, -1, -1],
      <int>[-1, -1, -1, -1],
      <int>[3, 4, 2, 1],
      <int>[2, 3, 2, 1],
    ],
  ];

  final int visualVariant;
  final Color coverColor;

  @override
  void paint(Canvas canvas, Size size) {
    final shadeMap =
        _shadeMaps[visualVariant.clamp(0, _shadeMaps.length - 1).toInt()];
    final pixelWidth = size.width / 4;
    final pixelHeight = size.height / shadeMap.length;
    final paint = Paint()..isAntiAlias = false;

    for (var row = 0; row < shadeMap.length; row++) {
      for (var column = 0; column < shadeMap[row].length; column++) {
        final shade = shadeMap[row][column];
        if (shade < 0) {
          continue;
        }
        paint.color = _shade(coverColor, _shadeFactors[shade]);
        canvas.drawRect(
          Rect.fromLTWH(
            column * pixelWidth,
            row * pixelHeight,
            pixelWidth,
            pixelHeight,
          ),
          paint,
        );
      }
    }
  }

  Color _shade(Color color, double factor) {
    int scaled(int channel) =>
        (channel * factor).round().clamp(0, 255).toInt();
    return Color.fromARGB(
      color.alpha,
      scaled(color.red),
      scaled(color.green),
      scaled(color.blue),
    );
  }

  @override
  bool shouldRepaint(covariant _BookColorVariantPainter oldDelegate) =>
      oldDelegate.visualVariant != visualVariant ||
      oldDelegate.coverColor != coverColor;
}

class _BookSpines extends StatelessWidget {
  const _BookSpines();

  @override
  Widget build(BuildContext context) {
    const colors = <Color>[
      Color(0xFF8A3425),
      Color(0xFF355F3D),
      Color(0xFF384B75),
      Color(0xFF725128),
    ];
    const heights = <double>[0.82, 0.94, 0.76, 0.88];

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (var index = 0; index < colors.length; index++)
            Expanded(
              child: FractionallySizedBox(
                heightFactor: heights[index],
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: colors[index],
                    border: const Border(
                      left: BorderSide(color: Color(0x66FFFFFF), width: 2),
                      top: BorderSide(color: Color(0x66FFFFFF), width: 2),
                      right: BorderSide(color: Color(0x88000000), width: 2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FallbackShelfPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 16;
    final paint = Paint();

    paint.color = BookAndQuillColors.woodDark;
    canvas.drawRect(Offset.zero & size, paint);

    final woodPixels = <Rect>[
      Rect.fromLTWH(0, 0, 16, 2),
      Rect.fromLTWH(0, 7, 16, 2),
      Rect.fromLTWH(0, 14, 16, 2),
      Rect.fromLTWH(0, 0, 2, 16),
      Rect.fromLTWH(14, 0, 2, 16),
      Rect.fromLTWH(5, 1, 1, 14),
      Rect.fromLTWH(10, 1, 1, 14),
    ];

    paint.color = BookAndQuillColors.wood;
    for (final rect in woodPixels) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left * unit,
          rect.top * unit,
          rect.width * unit,
          rect.height * unit,
        ),
        paint,
      );
    }

    paint.color = const Color(0xFF8D5930);
    canvas.drawRect(Rect.fromLTWH(unit, unit, 14 * unit, unit), paint);
    canvas.drawRect(Rect.fromLTWH(unit, 8 * unit, 14 * unit, unit), paint);

    paint.color = const Color(0xFF1A0E09);
    for (var row = 0; row < 2; row++) {
      for (var column = 0; column < 3; column++) {
        canvas.drawRect(
          Rect.fromLTWH(
            (1.7 + column * 4.2) * unit,
            (2.25 + row * 6.25) * unit,
            3.65 * unit,
            4.7 * unit,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
