import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/rich_text_editing_controller.dart';
import '../models/app_settings.dart';
import '../models/book_record.dart';
import '../models/rich_page.dart';
import '../services/book_file_service.dart';
import '../services/android_platform.dart';
import '../services/fullscreen_service.dart';
import '../services/game_sound_service.dart';
import '../theme/app_background.dart';
import '../theme/book_and_quill_theme.dart';
import '../widgets/gear_button.dart';
import '../widgets/page_sheet.dart';
import '../widgets/pixel_button.dart';
import '../widgets/rename_book_dialog.dart';
import '../widgets/book_text_entry_dialog.dart';

typedef TextActivityCallback = void Function(
  int typed,
  int deleted,
  String insertedText,
);
typedef PageActivityCallback = void Function(int inserted, int deleted);
typedef KeyActivityCallback = void Function(String key, int count);

enum _TransparentResizeEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class BookEditorScreen extends StatefulWidget {
  const BookEditorScreen({
    required this.initialBook,
    required this.onAutosave,
    required this.sounds,
    required this.onOpenSettings,
    required this.transparentModeListenable,
    required this.onSetTransparentMode,
    this.initialTwoPage = false,
    this.bookSizeScale = 1.0,
    this.autoHideEditorControls = true,
    this.pageDateFormat = PageDateFormat.dateOnly,
    this.backgroundId = 'stone_bricks',
    this.backgroundOpacity = AppSettings.defaultBackgroundOpacity,
    this.initialSearchQuery,
    this.onTextEdited,
    this.onPageTurned,
    this.onPagesChanged,
    this.onBookExported,
    this.onKeyboardKeyPressed,
    super.key,
  });

  final BookRecord initialBook;
  final bool initialTwoPage;
  final double bookSizeScale;
  final bool autoHideEditorControls;
  final PageDateFormat pageDateFormat;
  final String backgroundId;
  final double backgroundOpacity;
  final String? initialSearchQuery;
  final Future<void> Function(BookRecord book) onAutosave;
  final GameSoundService sounds;
  final Future<AppSettings> Function() onOpenSettings;
  final ValueListenable<bool> transparentModeListenable;
  final Future<bool> Function(bool enabled) onSetTransparentMode;
  final TextActivityCallback? onTextEdited;
  final VoidCallback? onPageTurned;
  final PageActivityCallback? onPagesChanged;
  final VoidCallback? onBookExported;
  final KeyActivityCallback? onKeyboardKeyPressed;

  @override
  State<BookEditorScreen> createState() => _BookEditorScreenState();
}

class _BookEditorScreenState extends State<BookEditorScreen>
    with WidgetsBindingObserver {
  static const int _historyLimit = 120;
  static const List<int> _minecraftColors = <int>[
    0xFF000000,
    0xFF0000AA,
    0xFF00AA00,
    0xFF00AAAA,
    0xFFAA0000,
    0xFFAA00AA,
    0xFFFFAA00,
    0xFFAAAAAA,
    0xFF555555,
    0xFF5555FF,
    0xFF55FF55,
    0xFF55FFFF,
    0xFFFF5555,
    0xFFFF55FF,
    0xFFFFFF55,
    0xFFFFFFFF,
  ];
  static final Map<LogicalKeyboardKey, int> _numberColorShortcuts =
      <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit0: 0xFF000000,
    LogicalKeyboardKey.digit1: 0xFFAA0000,
    LogicalKeyboardKey.digit2: 0xFF5555FF,
    LogicalKeyboardKey.digit3: 0xFFFFAA00,
    LogicalKeyboardKey.digit4: 0xFF00AA00,
    LogicalKeyboardKey.digit5: 0xFF555555,
    LogicalKeyboardKey.digit6: 0xFFAAAAAA,
    LogicalKeyboardKey.digit7: 0xFFAA00AA,
    LogicalKeyboardKey.digit8: 0xFFFF55FF,
    LogicalKeyboardKey.digit9: 0xFF55FFFF,
  };

  late BookRecord _book;
  late final TextEditingController _titleController;
  final BookFileService _files = BookFileService();
  final List<RichTextEditingController> _controllers = <RichTextEditingController>[];
  final List<FocusNode> _focusNodes = <FocusNode>[];
  final List<RichTextEditingController?> _dateControllers =
      <RichTextEditingController?>[];
  final List<FocusNode?> _dateFocusNodes = <FocusNode?>[];
  final List<_EditorSnapshot> _undoStack = <_EditorSnapshot>[];
  final List<_EditorSnapshot> _redoStack = <_EditorSnapshot>[];
  final Set<LogicalKeyboardKey> _pendingShiftKeys = <LogicalKeyboardKey>{};

  Timer? _saveTimer;
  Timer? _obfuscationTimer;
  Timer? _leftControlsHideTimer;
  Timer? _rightControlsHideTimer;
  Timer? _bottomControlsHideTimer;
  bool _saving = false;
  bool _finishing = false;
  bool _dirty = false;
  bool _restoring = false;
  bool _reflowScheduled = false;
  int? _reflowStartPage;
  bool _twoPage = false;
  bool _mobileToolsOpen = false;
  bool _mobileLayoutInitialized = false;
  late bool _autoHideEditorControls;
  late double _bookSizeScale;
  late PageDateFormat _pageDateFormat;
  late String _backgroundId;
  late double _backgroundOpacity;
  late String _searchQuery;
  late bool _transparentMode;
  Offset? _transparentBookOffset;
  double? _transparentBookPageSize;
  bool _showLeftControls = false;
  bool _showRightControls = false;
  bool _showBottomControls = false;
  int _currentPage = 0;
  int _activeController = 0;
  int _changeVersion = 0;
  bool _editingDate = false;
  CharacterStyle _activeStyle = CharacterStyle.normal;

  int get _visiblePageCount => _twoPage ? 2 : 1;
  bool get _editable => !_book.signed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _book = widget.initialBook;
    _twoPage = widget.initialTwoPage && !AndroidPlatform.isAndroid;
    _autoHideEditorControls = widget.autoHideEditorControls;
    _bookSizeScale = widget.bookSizeScale;
    _pageDateFormat = widget.pageDateFormat;
    _backgroundId = widget.backgroundId;
    _backgroundOpacity = widget.backgroundOpacity;
    _searchQuery = widget.initialSearchQuery?.trim() ?? '';
    _transparentMode = widget.transparentModeListenable.value;
    widget.transparentModeListenable.addListener(
      _handleTransparentModeChanged,
    );
    final highestExistingPage =
        math.max(0, widget.initialBook.pages.length - 1).toInt();
    final searchPage = _firstPageContainingSearchMatch();
    final restoredPage = searchPage ??
        widget.initialBook.spreadStart.clamp(0, highestExistingPage).toInt();
    _currentPage = _twoPage ? (restoredPage ~/ 2) * 2 : restoredPage;
    _titleController = TextEditingController(text: _book.title);
    _installPageControllers();
    _obfuscationTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      for (final controller in _controllers) {
        controller.refreshObfuscatedText();
      }
      for (final controller in _dateControllers) {
        controller?.refreshObfuscatedText();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AndroidPlatform.isAndroid) return;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final desired = _mobileLayoutInitialized
        ? (_twoPage && wide)
        : (widget.initialTwoPage && wide);
    _mobileLayoutInitialized = true;
    if (_twoPage != desired) {
      _book = _captureBook();
      _twoPage = desired;
      if (_twoPage) _currentPage = (_currentPage ~/ 2) * 2;
      _installPageControllers();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AndroidPlatform.isAndroid && state != AppLifecycleState.resumed) {
      // Flush the debounce before Android backgrounds or suspends this route.
      unawaited(_saveNow().catchError((Object error) {
        debugPrint('Could not save backgrounded book: $error');
      }));
    }
  }

  @override
  void didUpdateWidget(covariant BookEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transparentModeListenable ==
        widget.transparentModeListenable) {
      return;
    }
    oldWidget.transparentModeListenable.removeListener(
      _handleTransparentModeChanged,
    );
    _transparentMode = widget.transparentModeListenable.value;
    widget.transparentModeListenable.addListener(
      _handleTransparentModeChanged,
    );
  }

  void _handleTransparentModeChanged() {
    if (mounted) {
      setState(() {
        _transparentMode = widget.transparentModeListenable.value;
      });
    }
  }

  int? _firstPageContainingSearchMatch() {
    if (_searchQuery.isEmpty) {
      return null;
    }
    final pattern = RegExp(
      RegExp.escape(_searchQuery),
      caseSensitive: false,
    );
    for (var index = 0; index < _book.pages.length; index++) {
      if (pattern.hasMatch(_book.pages[index].text)) {
        return index;
      }
    }
    return null;
  }

  void _clearSearchHighlights() {
    if (_searchQuery.isEmpty) {
      return;
    }
    _searchQuery = '';
    for (final controller in _controllers) {
      controller.setSearchQuery(null);
    }
    for (final controller in _dateControllers) {
      controller?.setSearchQuery(null);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _ensurePagesThrough(int lastIndex) {
    final pages = List<RichPage>.from(_book.pages);
    while (pages.length <= lastIndex) {
      pages.add(RichPage.empty);
    }
    if (pages.length != _book.pages.length) {
      _book = _book.copyWith(pages: pages, updatedAt: DateTime.now());
    }
  }

  void _installPageControllers({
    bool requestFocus = false,
    int focusVisibleIndex = 0,
    int? focusPlainOffset,
  }) {
    // TextFields keep using their old controllers until the next layout.
    // In particular, the Android IME can still be detaching during a page turn.
    final oldControllers = <RichTextEditingController?>[
      ..._controllers, ..._dateControllers,
    ];
    final oldNodes = <FocusNode?>[..._focusNodes, ..._dateFocusNodes];
    if (oldControllers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final controller in oldControllers) { controller?.dispose(); }
        for (final node in oldNodes) { node?.dispose(); }
      });
    }
    _controllers.clear();
    _focusNodes.clear();
    _dateControllers.clear();
    _dateFocusNodes.clear();

    if (_editable) {
      _ensurePagesThrough(_currentPage + _visiblePageCount - 1);
    }
    for (var visibleIndex = 0; visibleIndex < _visiblePageCount; visibleIndex++) {
      final pageIndex = _currentPage + visibleIndex;
      if (pageIndex >= _book.pages.length) {
        break;
      }
      final capturedVisibleIndex = visibleIndex;
      final capturedPageIndex = pageIndex;
      _focusNodes.add(FocusNode());
      final pageController = RichTextEditingController(
        page: _book.pages[pageIndex],
        onBeforeUserEdit: _pushHistory,
        onPageChanged: (page) => _onPageChanged(capturedPageIndex, page),
        onActiveStyleChanged: (style) {
          if (!_editingDate &&
              _activeController == capturedVisibleIndex &&
              mounted) {
            setState(() => _activeStyle = style);
          }
        },
      );
      pageController.setSearchQuery(_searchQuery);
      _controllers.add(pageController);
      final sourcePage = _book.pages[pageIndex];
      if (sourcePage.dateStamp == null) {
        _dateControllers.add(null);
        _dateFocusNodes.add(null);
      } else {
        final dateFocusNode = FocusNode();
        final dateController = RichTextEditingController(
          page: _dateEditorPageFor(sourcePage),
          onBeforeUserEdit: _pushHistory,
          onPageChanged: (datePage) =>
              _onDatePageChanged(capturedPageIndex, datePage),
          onActiveStyleChanged: (style) {
            if (_editingDate &&
                _activeController == capturedVisibleIndex &&
                mounted) {
              setState(() => _activeStyle = style);
            }
          },
        );
        dateController.selection = TextSelection.collapsed(
          offset: dateController.text.length,
        );
        _dateControllers.add(dateController);
        _dateFocusNodes.add(dateFocusNode);
      }
    }
    _editingDate = false;
    _activeController = _controllers.isEmpty
        ? 0
        : focusVisibleIndex.clamp(0, _controllers.length - 1).toInt();
    _activeStyle = _controllers.isEmpty
        ? CharacterStyle.normal
        : _controllers[_activeController].activeStyle;
    if (requestFocus && _focusNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          if (!mounted || _activeController >= _focusNodes.length) {
            return;
          }
          if (focusPlainOffset != null) {
            final controller = _controllers[_activeController];
            controller.selection = TextSelection.collapsed(
              offset: controller.editableOffsetForPlainOffset(
                focusPlainOffset,
              ),
            );
          }
          _focusNodes[_activeController].requestFocus();
        },
      );
    }
  }

  RichPage _dateEditorPageFor(RichPage page) {
    final dateStamp = page.dateStamp;
    if (dateStamp == null) {
      return RichPage.empty;
    }
    final text = page.dateText ?? formatPageDate(dateStamp, _pageDateFormat);
    return RichPage(
      text: text,
      runs: List<StyleRun>.unmodifiable(page.effectiveDateRuns(text)),
    );
  }

  List<StyleRun> _storedDateRuns(RichPage datePage) {
    if (datePage.text.isEmpty) {
      return const <StyleRun>[];
    }
    if (datePage.runs.isNotEmpty) {
      return List<StyleRun>.unmodifiable(datePage.runs);
    }
    return <StyleRun>[
      StyleRun(
        start: 0,
        end: datePage.text.length,
        style: CharacterStyle.normal,
      ),
    ];
  }

  void _onPageChanged(int pageIndex, RichPage page) {
    if (_restoring) {
      return;
    }
    final pages = List<RichPage>.from(_book.pages);
    if (pageIndex >= pages.length) {
      return;
    }
    final previousPage = pages[pageIndex];
    final delta = _TextEditDelta.between(previousPage.text, page.text);
    if (delta.typed > 0 || delta.deleted > 0) {
      widget.onTextEdited?.call(
        delta.typed,
        delta.deleted,
        delta.insertedText,
      );
    }
    if (_pendingShiftKeys.isNotEmpty &&
        RegExp(r'[A-Z]').hasMatch(delta.insertedText)) {
      final shiftPresses = _pendingShiftKeys.length;
      _pendingShiftKeys.clear();
      widget.onKeyboardKeyPressed?.call('SHIFT', shiftPresses);
    }
    pages[pageIndex] = RichPage(
      text: page.text,
      runs: page.runs,
      lineAlignments: page.lineAlignments,
      dateStamp: previousPage.dateStamp,
      dateText: previousPage.dateText,
      dateRuns: previousPage.dateRuns,
    );
    _book = _book.copyWith(pages: pages, updatedAt: DateTime.now());
    _markDirty();
    _schedulePageReflow(pageIndex);
  }

  void _onDatePageChanged(int pageIndex, RichPage datePage) {
    if (_restoring || pageIndex < 0 || pageIndex >= _book.pages.length) {
      return;
    }
    final pages = List<RichPage>.from(_book.pages);
    pages[pageIndex] = pages[pageIndex].copyWith(
      dateText: datePage.text,
      dateRuns: _storedDateRuns(datePage),
    );
    _book = _book.copyWith(pages: pages, updatedAt: DateTime.now());
    _markDirty();
  }

  void _schedulePageReflow(int pageIndex) {
    final visibleIndex = pageIndex - _currentPage;
    if (visibleIndex >= 0 && visibleIndex < _controllers.length &&
        !_controllers[visibleIndex].value.composing.isCollapsed &&
        _controllers[visibleIndex].value.composing.isValid) {
      return; // Wait for the soft keyboard to commit its current word.
    }
    if (_restoring ||
        !_editable ||
        pageIndex < 0 ||
        pageIndex >= _book.pages.length ||
        _pageLineCount(_book.pages[pageIndex]) <= PageSheet.textRowLimit) {
      return;
    }
    _reflowStartPage = _reflowStartPage == null
        ? pageIndex
        : math.min(_reflowStartPage!, pageIndex).toInt();
    if (_reflowScheduled) {
      return;
    }
    _reflowScheduled = true;
    scheduleMicrotask(() {
      _reflowScheduled = false;
      final startPage = _reflowStartPage;
      _reflowStartPage = null;
      if (startPage != null && mounted) {
        _reflowPagesFrom(startPage);
      }
    });
  }

  void _reflowPagesFrom(int startPage) {
    if (!_editable || !mounted) {
      return;
    }
    final startVisibleIndex = startPage - _currentPage;
    var focusPage = startPage;
    var focusPlainOffset = startVisibleIndex >= 0 &&
            startVisibleIndex < _controllers.length &&
            _controllers[startVisibleIndex].selection.isValid
        ? _controllers[startVisibleIndex].plainOffsetForEditableOffset(
            _controllers[startVisibleIndex].selection.extentOffset,
          )
        : _book.pages[startPage].text.length;
    _book = _captureBook();
    final pages = List<RichPage>.from(_book.pages);
    var insertedPages = 0;
    var didOverflow = false;

    for (var pageIndex = startPage;
        pageIndex < pages.length;
        pageIndex++) {
      final source = pages[pageIndex];
      if (_pageLineCount(source) <= PageSheet.textRowLimit) {
        continue;
      }
      final split = _splitPageAtLineLimit(source);
      pages[pageIndex] = split.page;
      didOverflow = true;
      if (focusPage == pageIndex && focusPlainOffset > split.splitOffset) {
        focusPage = pageIndex + 1;
        focusPlainOffset = math.max(
          0,
          focusPlainOffset - split.splitOffset - 1,
        ).toInt();
      }
      if (pageIndex + 1 >= pages.length) {
        pages.add(RichPage.empty);
        insertedPages++;
      }
      pages[pageIndex + 1] = _mergeOverflowWithNextPage(
        split.overflow,
        pages[pageIndex + 1],
      );
    }

    if (!didOverflow) {
      return;
    }
    _book = _book.copyWith(pages: pages, updatedAt: DateTime.now());
    final oldSpread = _currentPage;
    final nextSpread = _twoPage
        ? (focusPage ~/ 2) * 2
        : focusPage;
    final focusVisibleIndex = focusPage - nextSpread;
    setState(() => _currentPage = nextSpread);
    _installPageControllers(
      requestFocus: true,
      focusVisibleIndex: focusVisibleIndex,
      focusPlainOffset: focusPlainOffset,
    );
    _markDirty();
    if (insertedPages > 0) {
      widget.onPagesChanged?.call(insertedPages, 0);
    }
    if (nextSpread != oldSpread) {
      widget.onPageTurned?.call();
      unawaited(widget.sounds.play(GameSound.pageTurn));
    }
  }

  int _pageLineCount(RichPage page) =>
      '\n'.allMatches(page.text).length + 1;

  _PageSplit _splitPageAtLineLimit(RichPage source) {
    var newlineCount = 0;
    var boundary = source.text.length;
    for (var index = 0; index < source.text.length; index++) {
      if (source.text.codeUnitAt(index) != 10) {
        continue;
      }
      newlineCount++;
      if (newlineCount == PageSheet.textRowLimit) {
        boundary = index;
        break;
      }
    }
    return _PageSplit(
      page: _sliceRichPage(
        source,
        0,
        boundary,
        dateStamp: source.dateStamp,
        dateText: source.dateText,
        dateRuns: source.dateRuns,
      ),
      overflow: _sliceRichPage(
        source,
        math.min(boundary + 1, source.text.length).toInt(),
        source.text.length,
        dateStamp: null,
        dateText: null,
        dateRuns: const <StyleRun>[],
      ),
      splitOffset: boundary,
    );
  }

  RichPage _sliceRichPage(
    RichPage source,
    int start,
    int end, {
    required DateTime? dateStamp,
    required String? dateText,
    required List<StyleRun> dateRuns,
  }) {
    final boundedStart = start.clamp(0, source.text.length).toInt();
    final boundedEnd = end.clamp(boundedStart, source.text.length).toInt();
    final text = source.text.substring(boundedStart, boundedEnd);
    final styles = source.expandStyles().sublist(boundedStart, boundedEnd);
    final firstSourceLine = '\n'
        .allMatches(source.text.substring(0, boundedStart))
        .length;
    final slicedLineCount = '\n'.allMatches(text).length + 1;
    final alignments = <int, LineAlignment>{};
    for (final entry in source.lineAlignments.entries) {
      if (entry.key >= firstSourceLine &&
          entry.key < firstSourceLine + slicedLineCount) {
        alignments[entry.key - firstSourceLine] = entry.value;
      }
    }
    return _richPageFromParts(
      text,
      styles,
      alignments,
      dateStamp: dateStamp,
      dateText: dateText,
      dateRuns: dateRuns,
    );
  }

  RichPage _mergeOverflowWithNextPage(
    RichPage overflow,
    RichPage next,
  ) {
    final separator = overflow.text.isNotEmpty && next.text.isNotEmpty
        ? '\n'
        : '';
    final text = '${overflow.text}$separator${next.text}';
    final styles = <CharacterStyle>[
      ...overflow.expandStyles(),
      if (separator.isNotEmpty) CharacterStyle.normal,
      ...next.expandStyles(),
    ];
    final alignments = <int, LineAlignment>{
      ...overflow.lineAlignments,
    };
    final nextLineOffset =
        overflow.text.isEmpty ? 0 : _pageLineCount(overflow);
    for (final entry in next.lineAlignments.entries) {
      alignments[nextLineOffset + entry.key] = entry.value;
    }
    return _richPageFromParts(
      text,
      styles,
      alignments,
      dateStamp: next.dateStamp,
      dateText: next.dateText,
      dateRuns: next.dateRuns,
    );
  }

  RichPage _richPageFromParts(
    String text,
    List<CharacterStyle> styles,
    Map<int, LineAlignment> lineAlignments, {
    required DateTime? dateStamp,
    required String? dateText,
    required List<StyleRun> dateRuns,
  }) {
    final runs = <StyleRun>[];
    if (text.isNotEmpty) {
      var runStart = 0;
      var runStyle = styles[0];
      for (var index = 1; index <= text.length; index++) {
        final nextStyle = index < text.length ? styles[index] : null;
        if (nextStyle != runStyle) {
          if (runStyle != CharacterStyle.normal) {
            runs.add(
              StyleRun(start: runStart, end: index, style: runStyle),
            );
          }
          runStart = index;
          runStyle = nextStyle ?? CharacterStyle.normal;
        }
      }
    }
    return RichPage(
      text: text,
      runs: List<StyleRun>.unmodifiable(runs),
      lineAlignments:
          Map<int, LineAlignment>.unmodifiable(lineAlignments),
      dateStamp: dateStamp,
      dateText: dateText,
      dateRuns: dateRuns,
    );
  }

  BookRecord _captureBook() {
    final pages = List<RichPage>.from(_book.pages);
    for (var visibleIndex = 0; visibleIndex < _controllers.length; visibleIndex++) {
      final pageIndex = _currentPage + visibleIndex;
      if (pageIndex < pages.length) {
        final storedPage = pages[pageIndex];
        final writtenPage = _controllers[visibleIndex].page;
        final dateController = visibleIndex < _dateControllers.length
            ? _dateControllers[visibleIndex]
            : null;
        final datePage = dateController?.page;
        pages[pageIndex] = RichPage(
          text: writtenPage.text,
          runs: writtenPage.runs,
          lineAlignments: writtenPage.lineAlignments,
          dateStamp: storedPage.dateStamp,
          dateText: datePage?.text ?? storedPage.dateText,
          dateRuns: datePage == null
              ? storedPage.dateRuns
              : _storedDateRuns(datePage),
        );
      }
    }
    return _book.copyWith(
      title: _titleController.text.trim().isEmpty ? 'Untitled Book' : _titleController.text.trim(),
      pages: pages,
      spreadStart: _currentPage,
      updatedAt: DateTime.now(),
    );
  }

  void _pushHistory() {
    if (_restoring || !_editable) {
      return;
    }
    _undoStack.add(_EditorSnapshot(book: _captureBook(), currentPage: _currentPage, twoPage: _twoPage));
    if (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    if (mounted) {
      setState(() {});
    }
  }

  void _undo() {
    if (_undoStack.isEmpty || !_editable) {
      return;
    }
    _redoStack.add(_EditorSnapshot(book: _captureBook(), currentPage: _currentPage, twoPage: _twoPage));
    _restoreSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty || !_editable) {
      return;
    }
    _undoStack.add(_EditorSnapshot(book: _captureBook(), currentPage: _currentPage, twoPage: _twoPage));
    _restoreSnapshot(_redoStack.removeLast());
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    _restoring = true;
    try {
      _book = snapshot.book;
      _currentPage = snapshot.currentPage;
      _twoPage = snapshot.twoPage;
      _titleController.text = snapshot.book.title;
      _installPageControllers(requestFocus: true);
    } finally {
      _restoring = false;
    }
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    _changeVersion++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveNow);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _renameBook() async {
    final name = await showRenameBookDialog(
      context,
      currentTitle: _titleController.text,
    );
    if (name == null || !mounted) {
      return;
    }
    _titleController.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    _book = _book.copyWith(title: name, updatedAt: DateTime.now());
    _markDirty();
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    _book = _captureBook();
    if (!_dirty) {
      return;
    }
    final savingVersion = _changeVersion;
    if (mounted) {
      setState(() => _saving = true);
    }
    try {
      await widget.onAutosave(_book);
      if (_changeVersion == savingVersion) {
        _dirty = false;
      } else {
        _saveTimer = Timer(const Duration(milliseconds: 100), _saveNow);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _turnPage(int direction, {bool jumpToEnd = false}) async {
    _book = _captureBook();
    final step = _visiblePageCount;
    int next;
    if (jumpToEnd) {
      next = direction < 0 ? 0 : ((_book.pages.length - 1) ~/ step) * step;
    } else {
      next = _currentPage + direction * step;
    }
    if (next < 0) {
      return;
    }
    if (_book.signed && next >= _book.pages.length) {
      return;
    }
    final oldLength = _book.pages.length;
    _ensurePagesThrough(next + step - 1);
    if (_book.pages.length != oldLength) {
      _markDirty();
    }
    setState(() => _currentPage = next);
    _installPageControllers(requestFocus: _editable);
    widget.onPageTurned?.call();
    await widget.sounds.play(GameSound.pageTurn);
  }

  Future<void> _jumpToPage({int? initialPageIndex}) async {
    final initialPage = initialPageIndex ?? _currentPage;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => BookTextEntryDialog(
        title: 'Jump to page', initialValue: '${initialPage + 1}',
        label: '1 or higher', submitLabel: 'GO', numeric: true,
      ),
    );
    final requested = int.tryParse(value ?? '');
    if (requested == null || requested < 1 || !mounted) {
      return;
    }
    final pageIndex = requested - 1;
    if (_book.signed && pageIndex >= _book.pages.length) {
      return;
    }
    _book = _captureBook();
    _ensurePagesThrough(pageIndex);
    final spreadStart = _twoPage ? (pageIndex ~/ 2) * 2 : pageIndex;
    final targetVisibleIndex = _twoPage ? pageIndex - spreadStart : 0;
    setState(() => _currentPage = spreadStart);
    _installPageControllers(
      requestFocus: _editable,
      focusVisibleIndex: targetVisibleIndex,
    );
    widget.onPageTurned?.call();
    await widget.sounds.play(GameSound.pageTurn);
    _markDirty();
  }

  void _insertPage() {
    if (!_editable) {
      return;
    }
    _pushHistory();
    _book = _captureBook();
    final pages = List<RichPage>.from(_book.pages)..insert(_currentPage + _activeController, RichPage.empty);
    _book = _book.copyWith(pages: pages, updatedAt: DateTime.now());
    _installPageControllers(requestFocus: true);
    _markDirty();
    widget.onPagesChanged?.call(1, 0);
  }

  void _deletePage() {
    if (!_editable) {
      return;
    }
    _pushHistory();
    _book = _captureBook();
    final pages = List<RichPage>.from(_book.pages);
    final pageIndex = (_currentPage + _activeController).clamp(0, pages.length - 1).toInt();
    var deletedPages = 0;
    var deletedCharacters = 0;
    final removeEmptySpread = _twoPage &&
        _currentPage >= 2 &&
        _currentPage + 1 < pages.length &&
        pages[_currentPage].text.trim().isEmpty &&
        pages[_currentPage + 1].text.trim().isEmpty;
    if (removeEmptySpread) {
      pages.removeRange(_currentPage, _currentPage + 2);
      _currentPage -= 2;
      _activeController = 0;
      deletedPages = 2;
    } else if (pages.length == 1) {
      deletedCharacters = pages[0].text.runes.length;
      pages[0] = RichPage.empty;
    } else {
      deletedCharacters = pages[pageIndex].text.runes.length;
      pages.removeAt(pageIndex);
      deletedPages = 1;
    }
    if (_currentPage >= pages.length) {
      _currentPage = math.max(0, pages.length - _visiblePageCount).toInt();
    }
    _book = _book.copyWith(pages: pages, updatedAt: DateTime.now());
    _installPageControllers(requestFocus: true);
    _markDirty();
    if (deletedCharacters > 0) {
      widget.onTextEdited?.call(0, deletedCharacters, '');
    }
    if (deletedPages > 0) {
      widget.onPagesChanged?.call(0, deletedPages);
    }
  }

  void _toggleTwoPage() {
    _book = _captureBook();
    setState(() {
      _twoPage = !_twoPage;
      if (_twoPage) {
        _currentPage = (_currentPage ~/ 2) * 2;
      }
    });
    _installPageControllers(requestFocus: _editable);
  }

  RichTextEditingController? get _activeTextController {
    if (_controllers.isEmpty) {
      return null;
    }
    return _controllers[_activeController.clamp(0, _controllers.length - 1).toInt()];
  }

  RichTextEditingController? get _activeDateController {
    if (_dateControllers.isEmpty) {
      return null;
    }
    return _dateControllers[
      _activeController.clamp(0, _dateControllers.length - 1).toInt()
    ];
  }

  RichTextEditingController? get _activeFormattingController =>
      _editingDate ? _activeDateController : _activeTextController;

  bool get _bookPageHasFocus => _focusNodes.any((node) => node.hasFocus);
  bool get _dateFieldHasFocus =>
      _dateFocusNodes.any((node) => node?.hasFocus ?? false);
  bool get _editorTextHasFocus =>
      _bookPageHasFocus || _dateFieldHasFocus;

  bool _isShiftKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight;
  }

  bool _willBackspaceDeleteWrittenCharacter() {
    final controller = _activeTextController;
    if (controller == null || !_bookPageHasFocus) {
      return false;
    }
    final selection = controller.value.selection;
    if (!selection.isValid) {
      return false;
    }
    if (!selection.isCollapsed) {
      final start = math.min(selection.start, selection.end)
          .clamp(0, controller.text.length)
          .toInt();
      final end = math.max(selection.start, selection.end)
          .clamp(start, controller.text.length)
          .toInt();
      return controller.text
          .substring(start, end)
          .codeUnits
          .any((codeUnit) =>
              !RichTextEditingController.isAlignmentMarkerCodeUnit(codeUnit));
    }
    final caret = selection.extentOffset;
    if (caret <= 0 || caret > controller.text.length) {
      return false;
    }
    return !RichTextEditingController.isAlignmentMarkerCodeUnit(
      controller.text.codeUnitAt(caret - 1),
    );
  }

  bool _handleEditorKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (_isShiftKey(key) && event is KeyUpEvent) {
      _pendingShiftKeys.remove(key);
      return false;
    }
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    if (key == LogicalKeyboardKey.f1 && event is KeyDownEvent) {
      unawaited(widget.onSetTransparentMode(!_transparentMode));
      return true;
    }
    if (_isShiftKey(key) && event is KeyDownEvent) {
      if (_bookPageHasFocus) {
        _pendingShiftKeys.add(key);
      }
      return false;
    }
    if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      unawaited(_finish());
      return true;
    }
    if (key == LogicalKeyboardKey.capsLock && event is KeyDownEvent) {
      widget.onKeyboardKeyPressed?.call('CAPS', 1);
      return false;
    }
    if (key == LogicalKeyboardKey.delete && event is KeyDownEvent) {
      if (_editable) {
        _deletePage();
      }
      return true;
    }
    if (!_editable || !_editorTextHasFocus) {
      return false;
    }
    if (event is KeyDownEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyD) {
        _toggleCurrentDate();
        return true;
      }
      final shortcutColor = _numberColorShortcuts[key];
      if (shortcutColor != null) {
        _applyColor(shortcutColor);
        return true;
      }
    }
    if (key == LogicalKeyboardKey.tab) {
      if (_editingDate) {
        return false;
      }
      if (event is KeyDownEvent) {
        widget.onKeyboardKeyPressed?.call('TAB', 1);
        _activeTextController?.cycleSelectedLineAlignment();
        widget.sounds.play(GameSound.click);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.backspace &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        _willBackspaceDeleteWrittenCharacter()) {
      widget.onKeyboardKeyPressed?.call('BACKSPACE', 1);
    }
    return false;
  }

  void _applyModifier(TextModifier modifier) {
    if (!_editable) {
      return;
    }
    final controller = _activeFormattingController;
    if (controller == null) {
      return;
    }
    final enabled = !controller.activeStyle.has(modifier);
    controller.applyModifier(modifier, enabled);
    widget.sounds.play(GameSound.click);
  }

  void _applyColor(int color) {
    if (!_editable) {
      return;
    }
    _activeFormattingController?.applyColor(color);
    widget.sounds.play(GameSound.click);
  }

  void _clearFormatting() {
    if (!_editable) {
      return;
    }
    _activeFormattingController?.clearFormatting();
    widget.sounds.play(GameSound.click);
  }

  void _toggleCurrentDate() {
    if (!_editable || _controllers.isEmpty) {
      return;
    }
    final activeController = _controllers[_activeController];
    final focusPlainOffset = activeController.selection.isValid
        ? activeController.plainOffsetForEditableOffset(
            activeController.selection.extentOffset,
          )
        : null;
    _pushHistory();
    _book = _captureBook();
    final pageIndex = (_currentPage + _activeController)
        .clamp(0, _book.pages.length - 1)
        .toInt();
    final pages = List<RichPage>.from(_book.pages);
    final currentPage = pages[pageIndex];
    if (currentPage.dateStamp == null) {
      final now = DateTime.now();
      final text = formatPageDate(now, _pageDateFormat);
      pages[pageIndex] = currentPage.copyWith(
        dateStamp: now,
        dateText: text,
        dateRuns: <StyleRun>[
          StyleRun(
            start: 0,
            end: text.length,
            style: RichPage.defaultDateStyle,
          ),
        ],
      );
    } else {
      pages[pageIndex] = currentPage.copyWith(
        clearDateStamp: true,
        clearDateText: true,
        clearDateRuns: true,
      );
    }
    _book = _book.copyWith(pages: pages, updatedAt: DateTime.now());
    _installPageControllers(
      requestFocus: true,
      focusVisibleIndex: _activeController,
      focusPlainOffset: focusPlainOffset,
    );
    _markDirty();
  }

  Future<void> _exportBook() async {
    _book = _captureBook();
    try {
      final saved = await _files.exportBook(_book);
      if (saved && mounted) {
        widget.onBookExported?.call();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Book exported.')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    }
  }

  Future<void> _signBook() async {
    if (!_editable) {
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (context) => BookTextEntryDialog(
        title: 'Sign this book?', initialValue: _book.author,
        message: 'Signing this book makes this copy read-only.',
        label: 'Author', submitLabel: 'SIGN', maxLength: 32,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    _pushHistory();
    _book = _captureBook().copyWith(author: result, signed: true, updatedAt: DateTime.now());
    _installPageControllers();
    _markDirty();
    await _saveNow();
  }

  Future<void> _finish() async {
    if (_finishing) {
      return;
    }
    _finishing = true;
    _markDirty();
    try {
      await widget.onSetTransparentMode(false);
      await _saveNow();
      if (mounted) {
        Navigator.of(context).pop(_book);
      }
    } finally {
      _finishing = false;
    }
  }

  Future<void> _openSettings() async {
    _markDirty();
    await _saveNow();
    if (mounted) {
      final settings = await widget.onOpenSettings();
      if (mounted) {
        final dateFormatChanged =
            _pageDateFormat != settings.pageDateFormat;
        setState(() {
          _bookSizeScale = settings.bookSizeScale;
          _autoHideEditorControls = settings.autoHideEditorControls;
          _pageDateFormat = settings.pageDateFormat;
          _backgroundId = settings.backgroundId;
          _backgroundOpacity = settings.backgroundOpacity;
          if (_autoHideEditorControls) {
            _cancelControlHideTimers();
            _showLeftControls = false;
            _showRightControls = false;
            _showBottomControls = false;
          } else {
            _cancelControlHideTimers();
          }
        });
        if (dateFormatChanged) {
          _installPageControllers();
        }
      }
    }
  }

  void _updateControlsForPointer(Offset position, Size size) {
    if (!_autoHideEditorControls) {
      return;
    }
    const leftRevealDistance = 168.0;
    const rightRevealDistance = 226.0;
    const bottomRevealDistance = 94.0;
    final showLeft = position.dx <= leftRevealDistance;
    final showRight = position.dx >= size.width - rightRevealDistance;
    final showBottom = position.dy >= size.height - bottomRevealDistance;
    _updateLeftControlVisibility(showLeft);
    _updateRightControlVisibility(showRight);
    _updateBottomControlVisibility(showBottom);
  }

  void _hideAutoControls() {
    if (!_autoHideEditorControls) {
      return;
    }
    _updateLeftControlVisibility(false);
    _updateRightControlVisibility(false);
    _updateBottomControlVisibility(false);
  }

  void _updateLeftControlVisibility(bool shouldShow) {
    if (shouldShow) {
      _leftControlsHideTimer?.cancel();
      _leftControlsHideTimer = null;
      if (!_showLeftControls && mounted) {
        setState(() => _showLeftControls = true);
      }
    } else if (_showLeftControls && _leftControlsHideTimer == null) {
      _leftControlsHideTimer = Timer(const Duration(milliseconds: 700), () {
        _leftControlsHideTimer = null;
        if (mounted) {
          setState(() => _showLeftControls = false);
        }
      });
    }
  }

  void _updateRightControlVisibility(bool shouldShow) {
    if (shouldShow) {
      _rightControlsHideTimer?.cancel();
      _rightControlsHideTimer = null;
      if (!_showRightControls && mounted) {
        setState(() => _showRightControls = true);
      }
    } else if (_showRightControls && _rightControlsHideTimer == null) {
      _rightControlsHideTimer = Timer(const Duration(milliseconds: 700), () {
        _rightControlsHideTimer = null;
        if (mounted) {
          setState(() => _showRightControls = false);
        }
      });
    }
  }

  void _updateBottomControlVisibility(bool shouldShow) {
    if (shouldShow) {
      _bottomControlsHideTimer?.cancel();
      _bottomControlsHideTimer = null;
      if (!_showBottomControls && mounted) {
        setState(() => _showBottomControls = true);
      }
    } else if (_showBottomControls && _bottomControlsHideTimer == null) {
      _bottomControlsHideTimer = Timer(const Duration(milliseconds: 700), () {
        _bottomControlsHideTimer = null;
        if (mounted) {
          setState(() => _showBottomControls = false);
        }
      });
    }
  }

  void _cancelControlHideTimers() {
    _leftControlsHideTimer?.cancel();
    _rightControlsHideTimer?.cancel();
    _bottomControlsHideTimer?.cancel();
    _leftControlsHideTimer = null;
    _rightControlsHideTimer = null;
    _bottomControlsHideTimer = null;
  }

  Widget _animatedEditorControl({
    required bool visible,
    required Offset hiddenOffset,
    required Widget child,
  }) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : hiddenOffset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _obfuscationTimer?.cancel();
    _cancelControlHideTimers();
    widget.transparentModeListenable.removeListener(
      _handleTransparentModeChanged,
    );
    _titleController.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    for (final controller in _dateControllers) {
      controller?.dispose();
    }
    for (final node in _dateFocusNodes) {
      node?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await widget.onSetTransparentMode(false);
        _markDirty();
        await _saveNow();
        return true;
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _saveNow(),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
              _applyModifier(TextModifier.bold),
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
              _applyModifier(TextModifier.italic),
          const SingleActivator(LogicalKeyboardKey.keyU, control: true): () =>
              _applyModifier(TextModifier.underline),
          const SingleActivator(
            LogicalKeyboardKey.keyX,
            control: true,
            shift: true,
          ): () => _applyModifier(TextModifier.strikethrough),
          const SingleActivator(
            LogicalKeyboardKey.keyO,
            control: true,
            shift: true,
          ): () => _applyModifier(TextModifier.obfuscated),
          const SingleActivator(
            LogicalKeyboardKey.keyR,
            control: true,
            shift: true,
          ): _clearFormatting,
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _turnPage(1),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _turnPage(-1),
          const SingleActivator(LogicalKeyboardKey.pageDown, shift: true): () => _turnPage(1, jumpToEnd: true),
          const SingleActivator(LogicalKeyboardKey.pageUp, shift: true): () => _turnPage(-1, jumpToEnd: true),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) => _handleEditorKeyEvent(event)
              ? KeyEventResult.handled
              : KeyEventResult.ignored,
          child: Scaffold(
            backgroundColor: _transparentMode
                ? const Color(FullscreenService.transparentBackgroundArgb)
                : const Color(0xFF17130F),
            body: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _clearSearchHighlights(),
              child: Stack(
                children: <Widget>[
                  if (!_transparentMode)
                    Positioned.fill(
                      child: AppBackground(
                        backgroundId: _backgroundId,
                        opacity: _backgroundOpacity,
                      ),
                    ),
                  SafeArea(
                    child: Column(
                      children: <Widget>[
                        if (!_transparentMode) _buildTopBar(),
                        Expanded(
                          child: _buildEditorWorkspace(),
                        ),
                      ],
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

  Widget _buildTopBar() {
    final statusText = _book.signed
        ? 'Signed${_book.author.isEmpty ? '' : ' by ${_book.author}'}'
        : _saving
            ? 'Saving...'
            : _dirty
                ? 'Unsaved changes'
                : 'Autosaved';
    if (AndroidPlatform.isAndroid) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: <Widget>[
          IconButton(tooltip: 'Save and close book',
            onPressed: _finish, icon: const Icon(Icons.arrow_back)),
          Expanded(child: InkWell(
            onTap: _renameBook,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Text(_titleController.text, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
                Text(statusText, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BookAndQuillColors.gold, fontSize: 10)),
              ]),
            ),
          )),
          GearButton(sounds: widget.sounds, onPressed: _openSettings),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 204),
          Expanded(
            child: Tooltip(
              message: 'Click to rename book',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _renameBook,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: _searchHighlightedText(
                      _titleController.text,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        letterSpacing: 1,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black, offset: Offset(2, 2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 204,
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 150,
                  child: _searchHighlightedText(
                    statusText,
                    highlight: _book.signed,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _book.signed || _saving
                          ? BookAndQuillColors.gold
                          : const Color(0xFF8FA47A),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                GearButton(
                  sounds: widget.sounds,
                  onPressed: _openSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchHighlightedText(
    String source, {
    required TextStyle style,
    bool highlight = true,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    if (!highlight || _searchQuery.isEmpty || source.isEmpty) {
      return Text(
        source,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        style: style,
      );
    }
    final pattern = RegExp(
      RegExp.escape(_searchQuery),
      caseSensitive: false,
    );
    final matches = pattern.allMatches(source).toList(growable: false);
    if (matches.isEmpty) {
      return Text(
        source,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        style: style,
      );
    }
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(text: source.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: source.substring(match.start, match.end),
          style: const TextStyle(
            backgroundColor: RichTextEditingController.searchHighlightColor,
          ),
        ),
      );
      start = match.end;
    }
    if (start < source.length) {
      spans.add(TextSpan(text: source.substring(start)));
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  Widget _buildEditorWorkspace() {
    if (AndroidPlatform.isAndroid) return _buildMobileWorkspace();
    if (_transparentMode) {
      return _buildTransparentBookWorkspace();
    }
    final leftVisible =
        !_autoHideEditorControls || _showLeftControls;
    final rightVisible =
        !_autoHideEditorControls || _showRightControls;
    final bottomVisible =
        !_autoHideEditorControls || _showBottomControls;
    return LayoutBuilder(
      builder: (context, constraints) => MouseRegion(
        onExit: (_) => _hideAutoControls(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: (event) => _updateControlsForPointer(
            event.localPosition,
            Size(constraints.maxWidth, constraints.maxHeight),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 54),
                  child: KeyedSubtree(
                    key: ValueKey<double>(_bookSizeScale),
                    child: _buildPages(),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _animatedEditorControl(
                  visible: leftVisible,
                  hiddenOffset: const Offset(-1.08, 0),
                  child: _buildActionBar(),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _animatedEditorControl(
                  visible: rightVisible,
                  hiddenOffset: const Offset(1.08, 0),
                  child: _buildFormattingBar(),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: _animatedEditorControl(
                  visible: bottomVisible,
                  hiddenOffset: const Offset(0, 1.45),
                  child: Center(
                    child: PixelButton(
                      label: 'DONE',
                      width: 174,
                      sounds: widget.sounds,
                      onPressed: _finish,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double get _transparentSpreadWidthFactor => _twoPage ? 1.75 : 1.0;

  double _transparentMaximumPageSize(Size bounds) {
    const visibleFrameHeightFactor = 15 / 16;
    final visibleFrameWidthFactor = _twoPage ? 71 / 48 : 73 / 96;
    return math.min(
      bounds.height / visibleFrameHeightFactor,
      bounds.width / visibleFrameWidthFactor,
    ).toDouble();
  }

  double _transparentPageSizeFor(Size bounds) {
    final maximum = _transparentMaximumPageSize(bounds);
    if (maximum <= 0) {
      return 0;
    }
    final minimum = math.min(240.0, maximum).toDouble();
    final preferred = math.min(
      600.0 * _bookSizeScale.clamp(0.6, 1.4).toDouble(),
      maximum,
    ).toDouble();
    return (_transparentBookPageSize ?? preferred)
        .clamp(minimum, maximum)
        .toDouble();
  }

  Rect _transparentVisibleFrame(double pageSize) {
    // book.png is drawn at 4/3 scale inside each 600-unit PageSheet. These
    // bounds are the alpha bounds of the actual wooden frame, so interaction
    // stays on the visible book rather than its transparent atlas margins.
    return Rect.fromLTRB(
      pageSize * (_twoPage ? 13 / 96 : 5 / 48),
      pageSize / 192,
      pageSize * (_twoPage ? 155 / 96 : 83 / 96),
      pageSize * 181 / 192,
    );
  }

  Offset _clampTransparentBookOffset(
    Offset offset,
    Size bounds,
    double pageSize,
  ) {
    final visibleFrame = _transparentVisibleFrame(pageSize);
    return Offset(
      offset.dx
          .clamp(
            -visibleFrame.left,
            bounds.width - visibleFrame.right,
          )
          .toDouble(),
      offset.dy
          .clamp(
            -visibleFrame.top,
            bounds.height - visibleFrame.bottom,
          )
          .toDouble(),
    );
  }

  Rect _transparentBookRect(Size bounds) {
    final pageSize = _transparentPageSizeFor(bounds);
    final spreadWidth = pageSize * _transparentSpreadWidthFactor;
    final centeredOffset = Offset(
      (bounds.width - spreadWidth) / 2,
      (bounds.height - pageSize) / 2,
    );
    final offset = _clampTransparentBookOffset(
      _transparentBookOffset ?? centeredOffset,
      bounds,
      pageSize,
    );
    return offset & Size(spreadWidth, pageSize);
  }

  void _moveTransparentBook(Offset delta, Size bounds) {
    final current = _transparentBookRect(bounds);
    final offset = _clampTransparentBookOffset(
      current.topLeft + delta,
      bounds,
      current.height,
    );
    setState(() {
      _transparentBookOffset = offset;
      _transparentBookPageSize = current.height;
    });
  }

  void _resizeTransparentBook(
    Offset delta,
    Size bounds,
    _TransparentResizeEdge edge,
  ) {
    final current = _transparentBookRect(bounds);
    final widthFactor = _transparentSpreadWidthFactor;
    final movesLeftEdge = edge == _TransparentResizeEdge.left ||
        edge == _TransparentResizeEdge.topLeft ||
        edge == _TransparentResizeEdge.bottomLeft;
    final movesTopEdge = edge == _TransparentResizeEdge.top ||
        edge == _TransparentResizeEdge.topLeft ||
        edge == _TransparentResizeEdge.topRight;
    final movesRightEdge = edge == _TransparentResizeEdge.right ||
        edge == _TransparentResizeEdge.topRight ||
        edge == _TransparentResizeEdge.bottomRight;
    final movesBottomEdge = edge == _TransparentResizeEdge.bottom ||
        edge == _TransparentResizeEdge.bottomLeft ||
        edge == _TransparentResizeEdge.bottomRight;
    final isHorizontalEdge = edge == _TransparentResizeEdge.left ||
        edge == _TransparentResizeEdge.right;
    final isVerticalEdge = edge == _TransparentResizeEdge.top ||
        edge == _TransparentResizeEdge.bottom;
    final horizontalDelta =
        (movesLeftEdge ? -delta.dx : delta.dx) / widthFactor;
    final verticalDelta = movesTopEdge ? -delta.dy : delta.dy;
    final sizeDelta = isHorizontalEdge
        ? horizontalDelta
        : isVerticalEdge
            ? verticalDelta
            : horizontalDelta.abs() >= verticalDelta.abs()
                ? horizontalDelta
                : verticalDelta;
    final maximum = _transparentMaximumPageSize(bounds);
    final minimum = math.min(240.0, maximum).toDouble();
    final nextPageSize = (current.height + sizeDelta)
        .clamp(minimum, maximum)
        .toDouble();
    final nextWidth = nextPageSize * widthFactor;

    var nextLeft = current.left;
    var nextTop = current.top;
    if (movesLeftEdge) {
      nextLeft = current.right - nextWidth;
    } else if (!movesRightEdge) {
      nextLeft = current.center.dx - nextWidth / 2;
    }
    if (movesTopEdge) {
      nextTop = current.bottom - nextPageSize;
    } else if (!movesBottomEdge) {
      nextTop = current.center.dy - nextPageSize / 2;
    }
    final offset = _clampTransparentBookOffset(
      Offset(nextLeft, nextTop),
      bounds,
      nextPageSize,
    );
    setState(() {
      _transparentBookOffset = offset;
      _transparentBookPageSize = nextPageSize;
    });
  }

  Widget _transparentGestureRegion({
    required MouseCursor cursor,
    required void Function(Offset delta) onPointerMove,
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerMove: (event) => onPointerMove(event.delta),
        ),
      ),
    );
  }

  Widget _buildTransparentBookWorkspace() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Size(constraints.maxWidth, constraints.maxHeight);
        final bookRect = _transparentBookRect(bounds);
        final pageSize = bookRect.height;
        if (pageSize <= 0) {
          return const SizedBox.expand();
        }
        final visibleFrame = _transparentVisibleFrame(pageSize);
        final edgeThickness = (pageSize * 0.024).clamp(8.0, 16.0).toDouble();
        final requestedCornerSize =
            (pageSize * 0.07).clamp(24.0, 44.0).toDouble();
        final cornerSize = math.min(
          requestedCornerSize,
          math.min(visibleFrame.width, visibleFrame.height) / 3,
        ).toDouble();
        final topEdge = math.max(0.0, visibleFrame.top - edgeThickness / 2);
        final leftEdge = math.max(0.0, visibleFrame.left - edgeThickness / 2);
        final rightEdge = math.max(
          0.0,
          visibleFrame.right - edgeThickness / 2,
        );
        final bottomEdge = math.max(
          0.0,
          visibleFrame.bottom - edgeThickness / 2,
        );
        final dragTop = visibleFrame.top + edgeThickness * 0.65;
        final dragHeight = (pageSize * 0.045).clamp(10.0, 27.0).toDouble();

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned.fromRect(
              rect: bookRect,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  Positioned.fill(
                    child: _buildPages(fillAvailable: true),
                  ),
                  _transparentGestureRegion(
                    left: visibleFrame.left + cornerSize,
                    top: dragTop,
                    right: bookRect.width - visibleFrame.right + cornerSize,
                    height: dragHeight,
                    cursor: SystemMouseCursors.move,
                    onPointerMove: (delta) =>
                        _moveTransparentBook(delta, bounds),
                  ),
                  _transparentGestureRegion(
                    left: leftEdge,
                    top: visibleFrame.top + cornerSize,
                    width: edgeThickness,
                    height: visibleFrame.height - cornerSize * 2,
                    cursor: SystemMouseCursors.resizeLeftRight,
                    onPointerMove: (delta) => _resizeTransparentBook(
                      delta,
                      bounds,
                      _TransparentResizeEdge.left,
                    ),
                  ),
                  _transparentGestureRegion(
                    left: rightEdge,
                    top: visibleFrame.top + cornerSize,
                    width: edgeThickness,
                    height: visibleFrame.height - cornerSize * 2,
                    cursor: SystemMouseCursors.resizeLeftRight,
                    onPointerMove: (delta) => _resizeTransparentBook(
                      delta,
                      bounds,
                      _TransparentResizeEdge.right,
                    ),
                  ),
                  _transparentGestureRegion(
                    left: visibleFrame.left + cornerSize,
                    top: topEdge,
                    width: visibleFrame.width - cornerSize * 2,
                    height: edgeThickness,
                    cursor: SystemMouseCursors.resizeUpDown,
                    onPointerMove: (delta) => _resizeTransparentBook(
                      delta,
                      bounds,
                      _TransparentResizeEdge.top,
                    ),
                  ),
                  _transparentGestureRegion(
                    left: visibleFrame.left + cornerSize,
                    top: bottomEdge,
                    width: visibleFrame.width - cornerSize * 2,
                    height: edgeThickness,
                    cursor: SystemMouseCursors.resizeUpDown,
                    onPointerMove: (delta) => _resizeTransparentBook(
                      delta,
                      bounds,
                      _TransparentResizeEdge.bottom,
                    ),
                  ),
                  _transparentGestureRegion(
                    left: math.max(0.0, visibleFrame.left - cornerSize / 2),
                    top: math.max(0.0, visibleFrame.top - cornerSize / 2),
                    width: cornerSize,
                    height: cornerSize,
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    onPointerMove: (delta) => _resizeTransparentBook(
                      delta,
                      bounds,
                      _TransparentResizeEdge.topLeft,
                    ),
                  ),
                  _transparentGestureRegion(
                    left: visibleFrame.right - cornerSize / 2,
                    top: math.max(0.0, visibleFrame.top - cornerSize / 2),
                    width: cornerSize,
                    height: cornerSize,
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    onPointerMove: (delta) => _resizeTransparentBook(
                      delta,
                      bounds,
                      _TransparentResizeEdge.topRight,
                    ),
                  ),
                  _transparentGestureRegion(
                    left: math.max(0.0, visibleFrame.left - cornerSize / 2),
                    top: visibleFrame.bottom - cornerSize / 2,
                    width: cornerSize,
                    height: cornerSize,
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    onPointerMove: (delta) => _resizeTransparentBook(
                      delta,
                      bounds,
                      _TransparentResizeEdge.bottomLeft,
                    ),
                  ),
                  _transparentGestureRegion(
                    left: visibleFrame.right - cornerSize / 2,
                    top: visibleFrame.bottom - cornerSize / 2,
                    width: cornerSize,
                    height: cornerSize,
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    onPointerMove: (delta) => _resizeTransparentBook(
                      delta,
                      bounds,
                      _TransparentResizeEdge.bottomRight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobileWorkspace() {
    return LayoutBuilder(builder: (context, constraints) {
      final spreadFactor = _twoPage ? 1.75 : 1.0;
      // Crop only the transparent atlas margins, never the text. The outer
      // scroll view lets Android reveal the caret above the software keyboard.
      final pageSize = math.min(700.0,
        constraints.maxWidth / (spreadFactor - 0.20)).toDouble();
      final toolsHeight = math.min(290.0,
        math.max(0.0, (constraints.maxHeight - 56) * 0.65)).toDouble();
      return Column(children: <Widget>[
        Expanded(child: ClipRect(child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: SizedBox(
            width: constraints.maxWidth, height: pageSize,
            child: OverflowBox(
              alignment: Alignment.center,
              minWidth: pageSize * spreadFactor,
              maxWidth: pageSize * spreadFactor,
              minHeight: pageSize, maxHeight: pageSize,
              child: SizedBox(width: pageSize * spreadFactor, height: pageSize,
                child: _buildPages(fillAvailable: true)),
            ),
          ),
        ))),
        if (_mobileToolsOpen)
          Container(
            height: toolsHeight,
            color: const Color(0xF21A1410),
            child: Center(child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: <Widget>[
                _buildActionBar(), _buildFormattingBar(),
              ]),
            )),
          ),
        SizedBox(height: 52, child: Row(children: <Widget>[
          IconButton(tooltip: 'Previous page',
            onPressed: _currentPage > 0 ? () => _turnPage(-1) : null,
            icon: const Icon(Icons.chevron_left)),
          Expanded(child: TextButton.icon(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _mobileToolsOpen = !_mobileToolsOpen);
            },
            icon: Icon(_mobileToolsOpen ? Icons.close : Icons.edit),
            label: const Text('TOOLS'),
          )),
          TextButton(onPressed: _finish, child: const Text('DONE')),
          IconButton(tooltip: 'Next page',
            onPressed: !_book.signed ||
                _currentPage + _visiblePageCount < _book.pages.length
                ? () => _turnPage(1) : null,
            icon: const Icon(Icons.chevron_right)),
        ])),
      ]);
    });
  }

  Widget _buildActionBar() {
    return SizedBox(
      width: 126,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  PixelButton(label: 'UNDO', width: 106, compact: true, enabled: _undoStack.isNotEmpty && _editable, sounds: widget.sounds, onPressed: _undo),
                  const SizedBox(height: 8),
                  PixelButton(label: 'REDO', width: 106, compact: true, enabled: _redoStack.isNotEmpty && _editable, sounds: widget.sounds, onPressed: _redo),
                  const SizedBox(height: 18),
                  PixelButton(label: 'EXPORT', width: 106, compact: true, sounds: widget.sounds, onPressed: _exportBook),
                  const SizedBox(height: 8),
                  if (!AndroidPlatform.isAndroid || MediaQuery.sizeOf(context).width >= 700)
                    PixelButton(label: _twoPage ? '1 PAGE' : '2 PAGES', width: 106, compact: true, sounds: widget.sounds, onPressed: _toggleTwoPage),
                  const SizedBox(height: 18),
                  PixelButton(label: 'INSERT', width: 106, compact: true, enabled: _editable, sounds: widget.sounds, onPressed: _insertPage),
                  const SizedBox(height: 8),
                  PixelButton(label: 'DELETE', width: 106, compact: true, enabled: _editable, sounds: widget.sounds, onPressed: _deletePage),
                  const SizedBox(height: 8),
                  PixelButton(label: 'DATE', width: 106, compact: true, enabled: _editable, sounds: widget.sounds, onPressed: _toggleCurrentDate),
                  const SizedBox(height: 18),
                  PixelButton(label: 'SIGN', width: 106, compact: true, enabled: _editable, sounds: widget.sounds, onPressed: _signBook),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPages({bool fillAvailable = false}) {
    final canGoBack = _currentPage > 0;
    final canGoForward = _book.signed
        ? _currentPage + _visiblePageCount < _book.pages.length
        : true;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Each vanilla book atlas has transparent space around the visible
        // frame. A spread overlaps only those margins so the two parchment
        // sheets meet at a central spine without overlapping either editor.
        const spreadOverlapFactor = 0.25;
        final spreadWidthFactor = _twoPage ? 2 - spreadOverlapFactor : 1.0;
        final fittingPageSize = math.min(
          constraints.maxHeight,
          constraints.maxWidth / spreadWidthFactor,
        ).toDouble();
        final preferredPageSize = 600.0 *
            _bookSizeScale.clamp(0.6, 1.4).toDouble();
        final pageSize = fillAvailable
            ? fittingPageSize
            : math.min(
                preferredPageSize,
                fittingPageSize,
              ).toDouble();
        final overlap = _twoPage ? pageSize * spreadOverlapFactor : 0.0;
        final spreadWidth = _twoPage ? pageSize * 2 - overlap : pageSize;

        Widget buildPage(int visibleIndex) {
          return visibleIndex >= _controllers.length
              ? const SizedBox.expand()
              : PageSheet(
                  key: ValueKey<String>(
                    '${_currentPage + visibleIndex}-${_twoPage ? 2 : 1}',
                  ),
                  controller: _controllers[visibleIndex],
                  focusNode: _focusNodes[visibleIndex],
                  pageNumber: _currentPage + visibleIndex + 1,
                  totalPages: _book.pages.length,
                  readOnly: !_editable,
                  dateController: visibleIndex < _dateControllers.length
                      ? _dateControllers[visibleIndex]
                      : null,
                  dateFocusNode: visibleIndex < _dateFocusNodes.length
                      ? _dateFocusNodes[visibleIndex]
                      : null,
                  onDateFocused: () {
                    if (!mounted ||
                        visibleIndex >= _dateControllers.length ||
                        _dateControllers[visibleIndex] == null) {
                      return;
                    }
                    setState(() {
                      _activeController = visibleIndex;
                      _editingDate = true;
                      _activeStyle =
                          _dateControllers[visibleIndex]!.activeStyle;
                    });
                  },
                  onPageIndicatorPressed: _transparentMode
                      ? null
                      : () => _jumpToPage(
                            initialPageIndex: _currentPage + visibleIndex,
                          ),
                  onPreviousPage:
                      !_transparentMode &&
                              (!_twoPage || visibleIndex == 0) &&
                              canGoBack
                          ? () => _turnPage(
                                -1,
                                jumpToEnd:
                                    HardwareKeyboard.instance.isShiftPressed,
                              )
                          : null,
                  onNextPage:
                      !_transparentMode &&
                              (!_twoPage || visibleIndex == 1) &&
                              canGoForward
                          ? () => _turnPage(
                                1,
                                jumpToEnd:
                                    HardwareKeyboard.instance.isShiftPressed,
                              )
                          : null,
                  side: !_twoPage
                      ? PageSheetSide.single
                      : visibleIndex == 0
                          ? PageSheetSide.left
                          : PageSheetSide.right,
                  onFocused: () {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _activeController = visibleIndex;
                      _editingDate = false;
                      _activeStyle = _controllers[visibleIndex].activeStyle;
                    });
                  },
                );
        }

        return Center(
          child: SizedBox(
            width: spreadWidth,
            height: pageSize,
            child: _twoPage
                ? Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned(
                        left: 0,
                        top: 0,
                        width: pageSize,
                        height: pageSize,
                        child: buildPage(0),
                      ),
                      Positioned(
                        left: pageSize - overlap,
                        top: 0,
                        width: pageSize,
                        height: pageSize,
                        child: buildPage(1),
                      ),
                    ],
                  )
                : buildPage(0),
          ),
        );
      },
    );
  }

  Widget _buildFormattingBar() {
    return SizedBox(
      width: 184,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('FORMATTING', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _FormatButton(label: 'B', tooltip: 'Bold (Ctrl+B)', active: _activeStyle.has(TextModifier.bold), enabled: _editable, onPressed: () => _applyModifier(TextModifier.bold)),
                      _FormatButton(label: 'I', tooltip: 'Italic (Ctrl+I)', active: _activeStyle.has(TextModifier.italic), enabled: _editable, onPressed: () => _applyModifier(TextModifier.italic)),
                      _FormatButton(label: 'U', tooltip: 'Underline (Ctrl+U)', active: _activeStyle.has(TextModifier.underline), enabled: _editable, onPressed: () => _applyModifier(TextModifier.underline)),
                      _FormatButton(label: 'S', tooltip: 'Strikethrough (Ctrl+Shift+X)', active: _activeStyle.has(TextModifier.strikethrough), enabled: _editable, onPressed: () => _applyModifier(TextModifier.strikethrough)),
                      _FormatButton(label: '§', tooltip: 'Obfuscated (Ctrl+Shift+O)', active: _activeStyle.has(TextModifier.obfuscated), enabled: _editable, onPressed: () => _applyModifier(TextModifier.obfuscated)),
                      _FormatButton(label: 'R', tooltip: 'Clear formatting (Ctrl+Shift+R)', active: false, enabled: _editable, onPressed: _clearFormatting),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text('COLORS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 9),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final color in _minecraftColors)
                        _ColorSwatch(
                          color: Color(color),
                          selected: _activeStyle.color == color,
                          enabled: _editable,
                          onPressed: () => _applyColor(color),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (AndroidPlatform.isAndroid) ...<Widget>[
                    PixelButton(label: 'ALIGN', compact: true,
                      enabled: _editable && !_editingDate,
                      onPressed: () => _activeTextController?.cycleSelectedLineAlignment()),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    AndroidPlatform.isAndroid
                        ? 'Select page or date text, then open Tools to format it. Align cycles left, center and right.'
                        : 'Select page or date text, then choose a color or modifier. Tab changes page alignment, Ctrl+0–9 selects a color, and Ctrl+D toggles the date.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFAAA49A), fontSize: 11, height: 1.35),
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

class _PageSplit {
  const _PageSplit({
    required this.page,
    required this.overflow,
    required this.splitOffset,
  });

  final RichPage page;
  final RichPage overflow;
  final int splitOffset;
}

class _EditorSnapshot {
  const _EditorSnapshot({required this.book, required this.currentPage, required this.twoPage});

  final BookRecord book;
  final int currentPage;
  final bool twoPage;
}

class _TextEditDelta {
  const _TextEditDelta({
    required this.typed,
    required this.deleted,
    required this.insertedText,
  });

  final int typed;
  final int deleted;
  final String insertedText;

  factory _TextEditDelta.between(String before, String after) {
    // Automatic word wrapping replaces boundary spaces with visual newlines.
    // Compare those representations as the same logical character so a wrap
    // does not inflate typing and deletion statistics.
    final oldRunes = before
        .replaceAll('\n', ' ')
        .runes
        .toList(growable: false);
    final newRunes = after
        .replaceAll('\n', ' ')
        .runes
        .toList(growable: false);
    var prefix = 0;
    final shortest = math.min(oldRunes.length, newRunes.length).toInt();
    while (prefix < shortest && oldRunes[prefix] == newRunes[prefix]) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < shortest - prefix &&
        oldRunes[oldRunes.length - suffix - 1] ==
            newRunes[newRunes.length - suffix - 1]) {
      suffix++;
    }

    final insertedEnd = newRunes.length - suffix;
    return _TextEditDelta(
      typed: insertedEnd - prefix,
      deleted: oldRunes.length - prefix - suffix,
      insertedText: String.fromCharCodes(
        newRunes.sublist(prefix, insertedEnd),
      ),
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool active;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Container(
          width: 42,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: !enabled
                ? const Color(0xFF333333)
                : active
                    ? const Color(0xFF6D8F3B)
                    : const Color(0xFF5B5B5B),
            border: Border.all(
              color: active ? Colors.white : const Color(0xFF1B1B1B),
              width: 2,
            ),
          ),
          child: Text(label, style: TextStyle(color: enabled ? Colors.white : Colors.grey, fontSize: 17)),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onPressed : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled ? color : Color.lerp(color, Colors.grey, 0.65),
          border: Border.all(color: selected ? Colors.white : const Color(0xFF252525), width: selected ? 3 : 2),
          boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black54, offset: Offset(2, 2))],
        ),
      ),
    );
  }
}
