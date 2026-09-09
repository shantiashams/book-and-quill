import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/rich_page.dart';

typedef RichPageCallback = void Function(RichPage page);

class RichTextEditingController extends TextEditingController {
  RichTextEditingController({
    required RichPage page,
    required this.onBeforeUserEdit,
    required this.onPageChanged,
    required this.onActiveStyleChanged,
  })  : _styles = _editableStylesForPage(page),
        _dateStamp = page.dateStamp,
        _dateText = page.dateText,
        _dateRuns = page.dateRuns,
        _activeStyle = CharacterStyle.normal,
        super(text: _editableTextForPage(page)) {
    addListener(_handleSelectionChanged);
  }

  static const String centerAlignmentMarker = '\uE000';
  static const String rightAlignmentMarker = '\uE001';
  static const Color searchHighlightColor = Color(0xCCFFD54A);

  final VoidCallback onBeforeUserEdit;
  final RichPageCallback onPageChanged;
  final ValueChanged<CharacterStyle> onActiveStyleChanged;

  List<CharacterStyle> _styles;
  DateTime? _dateStamp;
  String? _dateText;
  List<StyleRun> _dateRuns;
  CharacterStyle _activeStyle;
  String _searchQuery = '';
  List<TextRange> _searchHighlightRanges = const <TextRange>[];
  bool _programmatic = false;
  double _alignmentWidth = 388;
  TextSelection _lastSelection = const TextSelection.collapsed(offset: -1);

  set alignmentWidth(double value) {
    _alignmentWidth = value.clamp(0, 1000).toDouble();
  }

  static bool isAlignmentMarkerCodeUnit(int codeUnit) {
    return codeUnit == centerAlignmentMarker.codeUnitAt(0) ||
        codeUnit == rightAlignmentMarker.codeUnitAt(0);
  }

  static String _editableTextForPage(RichPage page) {
    final output = StringBuffer();
    var line = 0;
    void addMarker() {
      switch (page.alignmentForLine(line)) {
        case LineAlignment.left:
          break;
        case LineAlignment.center:
          output.write(centerAlignmentMarker);
          break;
        case LineAlignment.right:
          output.write(rightAlignmentMarker);
          break;
      }
    }

    addMarker();
    for (var index = 0; index < page.text.length; index++) {
      final codeUnit = page.text.codeUnitAt(index);
      output.writeCharCode(codeUnit);
      if (codeUnit == 10) {
        line++;
        addMarker();
      }
    }
    return output.toString();
  }

  static List<CharacterStyle> _editableStylesForPage(RichPage page) {
    final plainStyles = page.expandStyles();
    final editableStyles = <CharacterStyle>[];
    var line = 0;
    if (page.alignmentForLine(line) != LineAlignment.left) {
      editableStyles.add(CharacterStyle.normal);
    }
    for (var index = 0; index < page.text.length; index++) {
      editableStyles.add(plainStyles[index]);
      if (page.text.codeUnitAt(index) == 10) {
        line++;
        if (page.alignmentForLine(line) != LineAlignment.left) {
          editableStyles.add(CharacterStyle.normal);
        }
      }
    }
    return editableStyles;
  }

  CharacterStyle get activeStyle => _activeStyle;

  void setSearchQuery(String? query) {
    final normalized = query?.trim() ?? '';
    if (_searchQuery == normalized) {
      return;
    }
    _searchQuery = normalized;
    _searchHighlightRanges = _searchRangesForText(text, normalized);
    notifyListeners();
  }

  static List<TextRange> _searchRangesForText(
    String editableText,
    String query,
  ) {
    if (query.isEmpty || editableText.isEmpty) {
      return const <TextRange>[];
    }
    final plainText = StringBuffer();
    final editableOffsets = <int>[];
    for (var index = 0; index < editableText.length; index++) {
      final codeUnit = editableText.codeUnitAt(index);
      if (isAlignmentMarkerCodeUnit(codeUnit)) {
        continue;
      }
      plainText.writeCharCode(codeUnit);
      editableOffsets.add(index);
    }
    if (editableOffsets.isEmpty) {
      return const <TextRange>[];
    }
    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    return <TextRange>[
      for (final match in pattern.allMatches(plainText.toString()))
        if (match.start < match.end)
          TextRange(
            start: editableOffsets[match.start],
            end: editableOffsets[match.end - 1] + 1,
          ),
    ];
  }

  bool _isSearchHighlighted(int index) {
    for (final range in _searchHighlightRanges) {
      if (index < range.start) {
        return false;
      }
      if (index < range.end) {
        return true;
      }
    }
    return false;
  }

  int editableOffsetForPlainOffset(int plainOffset) {
    final target = plainOffset.clamp(0, page.text.length).toInt();
    var plain = 0;
    for (var editable = 0; editable < text.length; editable++) {
      if (isAlignmentMarkerCodeUnit(text.codeUnitAt(editable))) {
        continue;
      }
      if (plain >= target) {
        return editable;
      }
      plain++;
    }
    return text.length;
  }

  int plainOffsetForEditableOffset(int editableOffset) {
    final target = editableOffset.clamp(0, text.length).toInt();
    var plain = 0;
    for (var editable = 0; editable < target; editable++) {
      if (!isAlignmentMarkerCodeUnit(text.codeUnitAt(editable))) {
        plain++;
      }
    }
    return plain;
  }

  set activeStyle(CharacterStyle style) {
    if (_activeStyle == style) {
      return;
    }
    _activeStyle = style;
    onActiveStyleChanged(style);
  }

  RichPage get page {
    final plainText = StringBuffer();
    final plainStyles = <CharacterStyle>[];
    final lineAlignments = <int, LineAlignment>{};
    var line = 0;
    var atLineStart = true;
    for (var index = 0; index < text.length; index++) {
      final codeUnit = text.codeUnitAt(index);
      if (isAlignmentMarkerCodeUnit(codeUnit)) {
        if (atLineStart) {
          lineAlignments[line] = codeUnit == centerAlignmentMarker.codeUnitAt(0)
              ? LineAlignment.center
              : LineAlignment.right;
        }
        continue;
      }
      plainText.writeCharCode(codeUnit);
      plainStyles.add(_styleAtIndex(index));
      if (codeUnit == 10) {
        line++;
        atLineStart = true;
      } else {
        atLineStart = false;
      }
    }

    final plain = plainText.toString();
    final runs = <StyleRun>[];
    if (plain.isNotEmpty) {
      var runStart = 0;
      var runStyle = plainStyles[0];
      for (var index = 1; index <= plain.length; index++) {
        final nextStyle = index < plain.length ? plainStyles[index] : null;
        if (nextStyle != runStyle) {
          if (runStyle != CharacterStyle.normal) {
            runs.add(StyleRun(start: runStart, end: index, style: runStyle));
          }
          runStart = index;
          runStyle = nextStyle ?? CharacterStyle.normal;
        }
      }
    }
    return RichPage(
      text: plain,
      runs: List<StyleRun>.unmodifiable(runs),
      lineAlignments: Map<int, LineAlignment>.unmodifiable(lineAlignments),
      dateStamp: _dateStamp,
      dateText: _dateText,
      dateRuns: _dateRuns,
    );
  }

  @override
  set value(TextEditingValue newValue) {
    if (!newValue.composing.isValid || newValue.composing.isCollapsed) {
      newValue = _sanitizeAlignmentMarkers(newValue);
    }
    final oldValue = super.value;
    if (!_programmatic && oldValue.text != newValue.text) {
      onBeforeUserEdit();
      _applyTextDelta(oldValue, newValue);
    }
    _searchHighlightRanges = _searchRangesForText(
      newValue.text,
      _searchQuery,
    );
    super.value = newValue;
    if (!_programmatic && (oldValue.text != newValue.text ||
        (oldValue.composing.isValid && !oldValue.composing.isCollapsed &&
         (!newValue.composing.isValid || newValue.composing.isCollapsed)))) {
      onPageChanged(page);
    }
  }

  TextEditingValue _sanitizeAlignmentMarkers(TextEditingValue source) {
    if (!source.text.runes.any(isAlignmentMarkerCodeUnit)) {
      return source;
    }
    final output = StringBuffer();
    final offsetMap = List<int>.filled(source.text.length + 1, 0);
    var atLineStart = true;
    var hasLineMarker = false;
    for (var index = 0; index < source.text.length; index++) {
      final codeUnit = source.text.codeUnitAt(index);
      if (isAlignmentMarkerCodeUnit(codeUnit)) {
        if (atLineStart && !hasLineMarker) {
          output.writeCharCode(codeUnit);
          hasLineMarker = true;
        }
      } else {
        output.writeCharCode(codeUnit);
        if (codeUnit == 10) {
          atLineStart = true;
          hasLineMarker = false;
        } else {
          atLineStart = false;
        }
      }
      offsetMap[index + 1] = output.length;
    }
    final normalized = output.toString();
    if (normalized == source.text) {
      return source;
    }

    int mappedOffset(int offset) {
      if (offset < 0) {
        return offset;
      }
      return offsetMap[offset.clamp(0, source.text.length).toInt()];
    }

    return source.copyWith(
      text: normalized,
      selection: source.selection.isValid
          ? TextSelection(
              baseOffset: mappedOffset(source.selection.baseOffset),
              extentOffset: mappedOffset(source.selection.extentOffset),
              affinity: source.selection.affinity,
              isDirectional: source.selection.isDirectional,
            )
          : const TextSelection.collapsed(offset: -1),
      composing: TextRange.empty,
    );
  }

  void _applyTextDelta(TextEditingValue oldValue, TextEditingValue newValue) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    var prefix = 0;
    final shortest = math.min(oldText.length, newText.length).toInt();
    while (prefix < shortest && oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < shortest - prefix &&
        oldText.codeUnitAt(oldText.length - suffix - 1) ==
            newText.codeUnitAt(newText.length - suffix - 1)) {
      suffix++;
    }

    final removedEnd = oldText.length - suffix;
    final insertedLength = newText.length - prefix - suffix;
    final inherited = _activeStyle;
    final insertedStyles = List<CharacterStyle>.filled(
      insertedLength,
      inherited,
      growable: true,
    );
    _styles.replaceRange(prefix, removedEnd, insertedStyles);
    if (_styles.length != newText.length) {
      _styles = List<CharacterStyle>.filled(
        newText.length,
        CharacterStyle.normal,
        growable: true,
      );
    }
  }

  void applyModifier(TextModifier modifier, bool enabled) {
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) {
      activeStyle = activeStyle.toggle(modifier, enabled);
      return;
    }
    _applyToSelection((style) => style.toggle(modifier, enabled));
  }

  void applyColor(int color) {
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) {
      activeStyle = activeStyle.copyWith(color: color);
      return;
    }
    _applyToSelection((style) => style.copyWith(color: color));
  }

  void clearFormatting() {
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) {
      activeStyle = CharacterStyle.normal;
      return;
    }
    _applyToSelection((_) => CharacterStyle.normal);
  }

  void cycleSelectedLineAlignment() {
    final selection = value.selection;
    if (!selection.isValid) {
      return;
    }
    final selectionStart = math.min(selection.start, selection.end)
        .clamp(0, text.length)
        .toInt();
    final selectionEnd = math.max(selection.start, selection.end)
        .clamp(selectionStart, text.length)
        .toInt();
    final previousNewline = selectionStart == 0
        ? -1
        : text.lastIndexOf('\n', selectionStart - 1);
    final firstLineStart = previousNewline + 1;
    final lastSelectedOffset = selection.isCollapsed
        ? selectionStart
        : math.max(selectionStart, selectionEnd - 1).toInt();
    final lineStarts = <int>[];
    var lineStart = firstLineStart;
    while (lineStart <= lastSelectedOffset && lineStart <= text.length) {
      lineStarts.add(lineStart);
      final newline = text.indexOf('\n', lineStart);
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    if (lineStarts.isEmpty) {
      lineStarts.add(firstLineStart);
    }

    LineAlignment alignmentAt(int start) {
      if (start >= text.length) {
        return LineAlignment.left;
      }
      final codeUnit = text.codeUnitAt(start);
      if (codeUnit == centerAlignmentMarker.codeUnitAt(0)) {
        return LineAlignment.center;
      }
      if (codeUnit == rightAlignmentMarker.codeUnitAt(0)) {
        return LineAlignment.right;
      }
      return LineAlignment.left;
    }

    final nextAlignment = switch (alignmentAt(lineStarts.first)) {
      LineAlignment.left => LineAlignment.center,
      LineAlignment.center => LineAlignment.right,
      LineAlignment.right => LineAlignment.left,
    };
    final desiredMarker = switch (nextAlignment) {
      LineAlignment.left => null,
      LineAlignment.center => centerAlignmentMarker,
      LineAlignment.right => rightAlignmentMarker,
    };

    onBeforeUserEdit();
    var nextText = text;
    final nextStyles = List<CharacterStyle>.from(_styles);
    var nextBase = selection.baseOffset;
    var nextExtent = selection.extentOffset;
    for (final start in lineStarts.reversed) {
      final hasMarker = start < nextText.length &&
          isAlignmentMarkerCodeUnit(nextText.codeUnitAt(start));
      if (hasMarker && desiredMarker == null) {
        nextText = nextText.replaceRange(start, start + 1, '');
        nextStyles.removeAt(start);
        if (nextBase > start) {
          nextBase--;
        }
        if (nextExtent > start) {
          nextExtent--;
        }
      } else if (hasMarker) {
        nextText = nextText.replaceRange(start, start + 1, desiredMarker!);
        nextStyles[start] = CharacterStyle.normal;
      } else if (desiredMarker != null) {
        nextText = nextText.replaceRange(start, start, desiredMarker);
        nextStyles.insert(start, CharacterStyle.normal);
        if (nextBase >= start) {
          nextBase++;
        }
        if (nextExtent >= start) {
          nextExtent++;
        }
      }
    }

    _programmatic = true;
    try {
      _styles = nextStyles;
      _searchHighlightRanges = _searchRangesForText(
        nextText,
        _searchQuery,
      );
      super.value = TextEditingValue(
        text: nextText,
        selection: TextSelection(
          baseOffset: nextBase,
          extentOffset: nextExtent,
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
      );
      _activeStyle = _styleNearCaret(nextExtent);
      _lastSelection = const TextSelection.collapsed(offset: -1);
    } finally {
      _programmatic = false;
    }
    onActiveStyleChanged(_activeStyle);
    onPageChanged(page);
  }

  void _applyToSelection(CharacterStyle Function(CharacterStyle style) transform) {
    final selection = value.selection;
    final start = math.min(selection.start, selection.end).clamp(0, text.length).toInt();
    final end = math.max(selection.start, selection.end).clamp(start, text.length).toInt();
    if (start == end) {
      return;
    }
    onBeforeUserEdit();
    for (var index = start; index < end; index++) {
      _styles[index] = transform(_styles[index]);
    }
    _activeStyle = _styles[end - 1];
    notifyListeners();
    onActiveStyleChanged(_activeStyle);
    onPageChanged(page);
  }

  void replacePage(RichPage nextPage, {int? selectionOffset}) {
    _programmatic = true;
    try {
      final editableText = _editableTextForPage(nextPage);
      _styles = _editableStylesForPage(nextPage);
      _dateStamp = nextPage.dateStamp;
      _dateText = nextPage.dateText;
      _dateRuns = nextPage.dateRuns;
      _searchHighlightRanges = _searchRangesForText(
        editableText,
        _searchQuery,
      );
      final caret = (selectionOffset ?? editableText.length)
          .clamp(0, editableText.length)
          .toInt();
      super.value = TextEditingValue(
        text: editableText,
        selection: TextSelection.collapsed(offset: caret),
      );
      _activeStyle = _styleNearCaret(caret);
    } finally {
      _programmatic = false;
    }
    onActiveStyleChanged(_activeStyle);
  }

  CharacterStyle _styleAtIndex(int index) {
    if (index < 0 || index >= _styles.length) {
      return CharacterStyle.normal;
    }
    return _styles[index];
  }

  CharacterStyle _styleNearCaret(int caret) {
    if (_styles.isEmpty) {
      return CharacterStyle.normal;
    }
    if (caret > 0) {
      return _styleAtIndex(caret - 1);
    }
    return _styleAtIndex(0);
  }

  void _handleSelectionChanged() {
    final current = value.selection;
    if (!current.isValid || current == _lastSelection) {
      return;
    }
    _lastSelection = current;
    final style = current.isCollapsed
        ? _styleNearCaret(current.extentOffset)
        : _styleAtIndex(math.min(current.start, current.end).toInt());
    if (style != _activeStyle) {
      _activeStyle = style;
      onActiveStyleChanged(style);
    }
  }

  void refreshObfuscatedText() => notifyListeners();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    final children = <InlineSpan>[];
    var start = 0;
    while (start < text.length) {
      if (isAlignmentMarkerCodeUnit(text.codeUnitAt(start))) {
        children.add(
          TextSpan(
            text: text.substring(start, start + 1),
            style: _alignmentMarkerStyle(start, style),
          ),
        );
        start++;
        continue;
      }
      final currentStyle = _styleAtIndex(start);
      final searchHighlighted = _isSearchHighlighted(start);
      var end = start + 1;
      while (end < text.length &&
          !isAlignmentMarkerCodeUnit(text.codeUnitAt(end)) &&
          _styleAtIndex(end) == currentStyle &&
          _isSearchHighlighted(end) == searchHighlighted) {
        end++;
      }
      var segment = text.substring(start, end);
      if (currentStyle.has(TextModifier.obfuscated)) {
        segment = _obfuscate(segment, start);
      }
      final segmentStyle = _flutterStyle(currentStyle);
      children.add(
        TextSpan(
          text: segment,
          style: searchHighlighted
              ? segmentStyle.copyWith(
                  backgroundColor: searchHighlightColor,
                )
              : segmentStyle,
        ),
      );
      start = end;
    }
    return TextSpan(style: style, children: children);
  }

  TextStyle _alignmentMarkerStyle(int markerIndex, TextStyle? baseStyle) {
    final lineEnd = text.indexOf('\n', markerIndex + 1);
    final end = lineEnd < 0 ? text.length : lineEnd;
    final lineText = text.substring(markerIndex + 1, end).replaceAll(
          RegExp('[$centerAlignmentMarker$rightAlignmentMarker]'),
          '',
        );
    final painter = TextPainter(
      text: TextSpan(text: lineText, style: baseStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final available = _alignmentWidth;
    final remaining = math.max(0, available - painter.width).toDouble();
    final isCentered =
        text.codeUnitAt(markerIndex) == centerAlignmentMarker.codeUnitAt(0);
    final indent = isCentered ? remaining / 2 : remaining;
    final baseFontSize = baseStyle?.fontSize ?? 18;
    final baseLineHeight = baseFontSize * (baseStyle?.height ?? 1);
    const probeFontSize = 100.0;
    final marker = text.substring(markerIndex, markerIndex + 1);
    final markerPainter = TextPainter(
      text: TextSpan(
        text: marker,
        style: (baseStyle ?? const TextStyle()).copyWith(
          fontSize: probeFontSize,
          height: 1,
          letterSpacing: 0,
          wordSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final probeWidth = math.max(1, markerPainter.width).toDouble();
    final markerFontSize = indent <= 0
        ? 1.0
        : indent * probeFontSize / probeWidth;
    return (baseStyle ?? const TextStyle()).copyWith(
      color: Colors.transparent,
      fontSize: markerFontSize,
      height: baseLineHeight / markerFontSize,
      letterSpacing: 0,
      wordSpacing: 0,
      decoration: TextDecoration.none,
    );
  }

  TextStyle _flutterStyle(CharacterStyle style) {
    final decorations = <TextDecoration>[];
    if (style.has(TextModifier.underline)) {
      decorations.add(TextDecoration.underline);
    }
    if (style.has(TextModifier.strikethrough)) {
      decorations.add(TextDecoration.lineThrough);
    }
    return TextStyle(
      color: Color(style.color),
      fontWeight: style.has(TextModifier.bold) ? FontWeight.w700 : FontWeight.normal,
      fontStyle: style.has(TextModifier.italic) ? FontStyle.italic : FontStyle.normal,
      decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
      decorationColor: Color(style.color),
    );
  }

  String _obfuscate(String source, int seedOffset) {
    const glyphs = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!?/\\[]{}';
    final tick = DateTime.now().millisecondsSinceEpoch ~/ 80;
    final buffer = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      final codeUnit = source.codeUnitAt(index);
      if (codeUnit == 10 || codeUnit == 13 || codeUnit == 32 || codeUnit == 9) {
        buffer.writeCharCode(codeUnit);
      } else {
        final randomIndex = (tick * 17 + seedOffset * 13 + index * 29) % glyphs.length;
        buffer.write(glyphs[randomIndex]);
      }
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    removeListener(_handleSelectionChanged);
    super.dispose();
  }
}
