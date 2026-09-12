import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/rich_text_editing_controller.dart';
import '../theme/book_and_quill_theme.dart';

enum PageSheetSide {
  single,
  left,
  right,
}

const double _pageLogicalSize = 600;
const int _bookGridRows = 18;
const double _bookGridFontSize = 18;
const double _bookGridLineAdvance = 22;
const double _bookGridWidth = 400;
const double _leftPageEditorWidth = 420;
const double _bookTextStartInset = 12;
const double _leftPageTextStartInset = 30;
const double _oneGlyphWrapReduction = 12;
const double _leftPageBlockedHitboxWidth = _oneGlyphWrapReduction * 2;
const double _bookGridTextHeight = _bookGridRows * _bookGridLineAdvance;
const double _bookGridViewportHeight = _bookGridTextHeight + 12;
const double _bookGridLineHeight =
    _bookGridLineAdvance / _bookGridFontSize;
const double _arrowShift = 20;
const double _footerBottom = 64;
const double _footerHeight = 26;
const double _pageArrowWidth = 58;
const double _footerGap = 12;

class PageSheet extends StatelessWidget {
  const PageSheet({
    required this.controller,
    required this.focusNode,
    required this.pageNumber,
    required this.totalPages,
    required this.onFocused,
    required this.readOnly,
    required this.dateController,
    required this.dateFocusNode,
    required this.onDateFocused,
    this.onPageIndicatorPressed,
    this.onPreviousPage,
    this.onNextPage,
    this.side = PageSheetSide.single,
    super.key,
  });

  final RichTextEditingController controller;
  final FocusNode focusNode;
  final int pageNumber;
  final int totalPages;
  final VoidCallback onFocused;
  final bool readOnly;
  final RichTextEditingController? dateController;
  final FocusNode? dateFocusNode;
  final VoidCallback onDateFocused;
  final VoidCallback? onPageIndicatorPressed;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final PageSheetSide side;

  static const int textRowLimit = _bookGridRows;

  @override
  Widget build(BuildContext context) {
    final previousArrowLeft = side == PageSheetSide.single
        ? 130 - _arrowShift
        : 130 + _arrowShift;
    // Keep navigation and the editable date in one footer row, above the
    // texture's lower edge. The 18-row writing viewport ends above this row.
    final nextArrowLeft = previousArrowLeft + _pageArrowWidth + _footerGap;
    final dateLeft = nextArrowLeft + _pageArrowWidth + _footerGap;

    return AspectRatio(
      aspectRatio: 1,
      // Scale one fixed page surface so resizing never changes the 18 complete
      // rows, word-wrap width, or any interactive alignment.
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _pageLogicalSize,
          height: _pageLogicalSize,
          child: Builder(
            builder: (context) {
              // The mirrored left page exposes the atlas's narrower outer
              // parchment edge. Give page 1 one extra 12-unit inset so its
              // first glyph sits slightly farther right than before.
              final textStartInset = side == PageSheetSide.left
                  ? _leftPageTextStartInset
                  : _bookTextStartInset;
              final wrapReduction = side == PageSheetSide.single ||
                      side == PageSheetSide.right
                  ? _oneGlyphWrapReduction
                  : 0.0;
              final dateRightInset = side == PageSheetSide.left
                  ? 104.0
                  : 122.0;
              final editorHitboxWidth = side == PageSheetSide.left
                  ? _leftPageEditorWidth
                  : _bookGridWidth;
              final textWidth =
                  editorHitboxWidth - textStartInset - wrapReduction;
              controller.alignmentWidth = textWidth;
              // MinecraftLocalV2 keeps Minecraft's real proportional advances.
              // Narrow glyphs such as i therefore no longer inherit the wide
              // empty tail of the fixed-cell grid font.
              const bodyStyle = TextStyle(
                color: BookAndQuillColors.ink,
                fontFamily: 'MinecraftLocalV2',
                fontSize: _bookGridFontSize,
                height: _bookGridLineHeight,
                letterSpacing: 0,
                wordSpacing: 0,
              );

              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  IgnorePointer(
                    child: _MinecraftBookAtlas(side: side),
                  ),
                  Positioned(
                    left: 100,
                    top: 52,
                    width: editorHitboxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: _bookGridWidth,
                          child: Center(
                            child: _PageIndicator(
                              key: ValueKey<String>(
                                'page-$pageNumber-indicator',
                              ),
                              label: 'Page $pageNumber of $totalPages',
                              onPressed: onPageIndicatorPressed,
                            ),
                          ),
                        ),
                        const SizedBox(height: _bookGridLineAdvance),
                        SizedBox(
                          key: ValueKey<String>('page-$pageNumber-text-grid'),
                          width: editorHitboxWidth,
                          height: _bookGridViewportHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              Focus(
                                onFocusChange: (focused) {
                                  if (focused) {
                                    onFocused();
                                  }
                                },
                                child: TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  readOnly: readOnly,
                                  expands: false,
                                  minLines: _bookGridRows,
                                  maxLines: _bookGridRows,
                                  inputFormatters: <TextInputFormatter>[
                                    MinecraftWordWrapFormatter(
                                      maxWidth: textWidth,
                                      textStyle: bodyStyle,
                                    ),
                                  ],
                                  keyboardType: TextInputType.multiline,
                                  textAlignVertical: TextAlignVertical.top,
                                  scrollPhysics:
                                      const ClampingScrollPhysics(),
                                  style: bodyStyle,
                                  strutStyle: const StrutStyle(
                                    fontFamily: 'MinecraftLocalV2',
                                    fontSize: _bookGridFontSize,
                                    height: _bookGridLineHeight,
                                    forceStrutHeight: true,
                                  ),
                                  cursorColor: BookAndQuillColors.ink,
                                  cursorWidth: 2,
                                  onTap: onFocused,
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.only(
                                      left: textStartInset,
                                      right: wrapReduction,
                                    ),
                                    counterText: '',
                                    hintText: readOnly
                                        ? ''
                                        : 'Write something...',
                                    hintStyle: bodyStyle.copyWith(
                                      color: const Color(0x774B3A29),
                                    ),
                                  ),
                                ),
                              ),
                              if (side == PageSheetSide.left)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: _leftPageBlockedHitboxWidth,
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.basic,
                                    child: Listener(
                                      behavior: HitTestBehavior.opaque,
                                      onPointerDown: (_) {},
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (dateController != null && dateFocusNode != null)
                    Positioned(
                      left: dateLeft,
                      right: dateRightInset,
                      bottom: _footerBottom,
                      height: _footerHeight,
                      child: Focus(
                        key: ValueKey<String>('page-$pageNumber-date'),
                        onFocusChange: (focused) {
                          if (focused) {
                            onDateFocused();
                          }
                        },
                        child: MouseRegion(
                          cursor: readOnly
                              ? SystemMouseCursors.basic
                              : SystemMouseCursors.text,
                          child: TextField(
                            controller: dateController,
                            focusNode: dateFocusNode,
                            readOnly: readOnly,
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            textAlignVertical: TextAlignVertical.center,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.deny(
                                RegExp(r'[\r\n]'),
                              ),
                              LengthLimitingTextInputFormatter(32),
                            ],
                            onTap: onDateFocused,
                            cursorColor: Color(
                              dateController!.activeStyle.color,
                            ),
                            cursorWidth: 1.5,
                            style: const TextStyle(
                              color: BookAndQuillColors.ink,
                              fontFamily: 'MinecraftLocalV2',
                              fontSize: 13,
                              height: 1,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 5,
                              ),
                              counterText: '',
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (onPreviousPage != null)
                    Positioned(
                      left: previousArrowLeft,
                      bottom: _footerBottom,
                      child: _BookPageArrow(
                        key: ValueKey<String>(
                          'page-$pageNumber-back-arrow',
                        ),
                        backwards: true,
                        onPressed: onPreviousPage!,
                      ),
                    ),
                  if (onNextPage != null)
                    Positioned(
                      left: nextArrowLeft,
                      bottom: _footerBottom,
                      child: _BookPageArrow(
                        key: ValueKey<String>(
                          'page-$pageNumber-forward-arrow',
                        ),
                        backwards: false,
                        onPressed: onNextPage!,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PageIndicator extends StatefulWidget {
  const _PageIndicator({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<_PageIndicator> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onPressed != null;
    return MouseRegion(
      cursor: interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: interactive ? (_) => setState(() => _hovering = true) : null,
      onExit: interactive ? (_) => setState(() => _hovering = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _hovering
                  ? const Color(0xFF5A4026)
                  : BookAndQuillColors.ink,
              fontSize: 18,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _BookPageArrow extends StatefulWidget {
  const _BookPageArrow({
    required this.backwards,
    required this.onPressed,
    super.key,
  });

  final bool backwards;
  final VoidCallback onPressed;

  @override
  State<_BookPageArrow> createState() => _BookPageArrowState();
}

class _BookPageArrowState extends State<_BookPageArrow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final direction = widget.backwards ? 'backward' : 'forward';
    final suffix = _hovering ? '_highlighted' : '';
    return Tooltip(
      message: widget.backwards ? 'Previous page' : 'Next page',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: SizedBox(
            width: _pageArrowWidth,
            height: 24,
            child: Image.asset(
              'assets/imported/textures/page_$direction$suffix.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              errorBuilder: (_, __, ___) => Icon(
                widget.backwards
                    ? Icons.arrow_back_rounded
                    : Icons.arrow_forward_rounded,
                color: const Color(0xFFD8C9A8),
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MinecraftWordWrapFormatter extends TextInputFormatter {
  MinecraftWordWrapFormatter({
    required this.maxWidth,
    required this.textStyle,
  });

  final double maxWidth;
  final TextStyle textStyle;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if ((newValue.composing.isValid && !newValue.composing.isCollapsed) ||
        newValue.text.isEmpty || maxWidth <= 0) {
      return newValue;
    }
    final normalized = _normalize(newValue.text);
    if (normalized == newValue.text) {
      return newValue;
    }

    int mappedOffset(int offset) {
      if (offset < 0) {
        return offset;
      }
      final bounded = offset.clamp(0, newValue.text.length).toInt();
      return _normalize(newValue.text.substring(0, bounded)).length;
    }

    final nextSelection = newValue.selection.isValid
        ? TextSelection(
            baseOffset: mappedOffset(newValue.selection.baseOffset),
            extentOffset: mappedOffset(newValue.selection.extentOffset),
            affinity: newValue.selection.affinity,
            isDirectional: newValue.selection.isDirectional,
          )
        : const TextSelection.collapsed(offset: -1);

    return newValue.copyWith(
      text: normalized,
      selection: nextSelection,
      composing: TextRange.empty,
    );
  }

  String _normalize(String source) {
    final normalizedSource = source.replaceAll('\r\n', '\n').replaceAll('\r', '');
    final sourceLines = normalizedSource.split('\n');
    final outputLines = <String>[];
    for (final sourceLine in sourceLines) {
      String marker = '';
      var content = sourceLine;
      if (content.isNotEmpty &&
          RichTextEditingController.isAlignmentMarkerCodeUnit(
            content.codeUnitAt(0),
          )) {
        marker = content.substring(0, 1);
        content = content.substring(1);
      }
      outputLines.addAll(_wrapLine(content, marker));
    }
    return outputLines.join('\n');
  }

  List<String> _wrapLine(String content, String marker) {
    if (content.isEmpty) {
      return <String>[marker];
    }
    final lines = <String>[];
    var current = '';
    var brokeOnTrailingSpace = false;
    final tokens = RegExp(r'[ \t]+|[^ \t]+').allMatches(content);
    for (final match in tokens) {
      final token = match.group(0)!.replaceAll('\t', '    ');
      final whitespace = token.trim().isEmpty;
      if (whitespace) {
        final candidate = '$current$token';
        if (_fits(candidate)) {
          current = candidate;
          brokeOnTrailingSpace = false;
        } else {
          lines.add('$marker${current.trimRight()}');
          current = '';
          brokeOnTrailingSpace = true;
        }
        continue;
      }

      final candidate = '$current$token';
      if (_fits(candidate)) {
        current = candidate;
        brokeOnTrailingSpace = false;
        continue;
      }
      if (current.trimRight().isNotEmpty) {
        lines.add('$marker${current.trimRight()}');
      }
      current = '';
      brokeOnTrailingSpace = false;
      for (final piece in _breakLongWord(token)) {
        if (piece.isCompleteLine) {
          lines.add('$marker${piece.text}');
        } else {
          current = piece.text;
        }
      }
    }
    if (current.isNotEmpty || lines.isEmpty || brokeOnTrailingSpace) {
      lines.add('$marker$current');
    }
    return lines;
  }

  List<_WrappedWordPiece> _breakLongWord(String word) {
    if (_fits(word)) {
      return <_WrappedWordPiece>[
        _WrappedWordPiece(word, isCompleteLine: false),
      ];
    }
    final pieces = <_WrappedWordPiece>[];
    var current = '';
    for (final character in word.characters) {
      final next = '$current$character';
      if (current.isNotEmpty && !_fits(next)) {
        pieces.add(_WrappedWordPiece(current, isCompleteLine: true));
        current = character;
      } else {
        current = next;
      }
    }
    if (current.isNotEmpty) {
      pieces.add(_WrappedWordPiece(current, isCompleteLine: false));
    }
    return pieces;
  }

  bool _fits(String text) {
    final fittedText = text
        .replaceAll(RichTextEditingController.centerAlignmentMarker, '')
        .replaceAll(RichTextEditingController.rightAlignmentMarker, '')
        .replaceAll(' ', '\u00A0');
    final painter = TextPainter(
      text: TextSpan(
        text: fittedText,
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width <= maxWidth + 0.25;
  }
}

class _WrappedWordPiece {
  const _WrappedWordPiece(this.text, {required this.isCompleteLine});

  final String text;
  final bool isCompleteLine;
}

class _MinecraftBookAtlas extends StatelessWidget {
  const _MinecraftBookAtlas({required this.side});

  final PageSheetSide side;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return OverflowBox(
            alignment: side == PageSheetSide.left
                ? Alignment.topRight
                : Alignment.topLeft,
            minWidth: constraints.maxWidth * 4 / 3,
            maxWidth: constraints.maxWidth * 4 / 3,
            minHeight: constraints.maxHeight * 4 / 3,
            maxHeight: constraints.maxHeight * 4 / 3,
            child: Transform.flip(
              flipX: side == PageSheetSide.left,
              child: Image.asset(
                'assets/imported/textures/book.png',
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                errorBuilder: (_, __, ___) =>
                    const _FallbackBookBackground(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FallbackBookBackground extends StatelessWidget {
  const _FallbackBookBackground();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _FallbackBookPainter());
}

class _FallbackBookPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.13,
        size.width * 0.67,
        size.height * 0.74,
      ),
      Paint()..color = const Color(0x99000000),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.14,
        size.height * 0.09,
        size.width * 0.69,
        size.height * 0.75,
      ),
      Paint()..color = const Color(0xFF6A3F20),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.17,
        size.height * 0.11,
        size.width * 0.63,
        size.height * 0.70,
      ),
      Paint()..color = BookAndQuillColors.parchment,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.17,
        size.height * 0.78,
        size.width * 0.63,
        size.height * 0.03,
      ),
      Paint()..color = BookAndQuillColors.parchmentDark,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
