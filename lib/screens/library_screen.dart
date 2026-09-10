import 'dart:async';
import 'dart:io' show exit;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/book_record.dart';
import '../models/usage_stats.dart';
import '../services/book_file_service.dart';
import '../services/android_platform.dart';
import '../services/book_storage.dart';
import '../services/game_sound_service.dart';
import '../theme/app_background.dart';
import '../theme/book_appearance_palette.dart';
import '../theme/book_and_quill_theme.dart';
import '../widgets/chiseled_bookshelf.dart';
import '../widgets/gear_button.dart';
import '../widgets/pixel_button.dart';
import '../widgets/rename_book_dialog.dart';
import 'book_editor_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.storage,
    required this.initialSlots,
    required this.sounds,
    required this.fullscreenListenable,
    required this.onToggleFullscreen,
    required this.transparentModeListenable,
    required this.onSetTransparentMode,
    this.initialSettings = AppSettings.defaults,
    this.initialUsageStats = UsageStats.empty,
    this.initialShelfNames = const <String>[],
    super.key,
  });

  final BookStorage storage;
  final List<BookRecord?> initialSlots;
  final AppSettings initialSettings;
  final UsageStats initialUsageStats;
  final List<String> initialShelfNames;
  final GameSoundService sounds;
  final ValueListenable<bool> fullscreenListenable;
  final Future<bool> Function() onToggleFullscreen;
  final ValueListenable<bool> transparentModeListenable;
  final Future<bool> Function(bool enabled) onSetTransparentMode;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final List<BookRecord?> _slots = List<BookRecord?>.from(widget.initialSlots);
  late final List<String> _shelfNames =
      List<String>.from(widget.initialShelfNames);
  final TextEditingController _searchController = TextEditingController();
  final BookFileService _files = BookFileService();
  final GlobalKey _libraryStackKey = GlobalKey();
  final GlobalKey _shelfViewportKey = GlobalKey();
  final LayerLink _headerIconLink = LayerLink();
  final ValueNotifier<Offset> _dragFeedbackTarget =
      ValueNotifier<Offset>(Offset.zero);
  late AppSettings _settings = widget.initialSettings;
  late UsageStats _usageStats = widget.initialUsageStats;
  Timer? _statsSaveTimer;
  Timer? _dragShelfTimer;
  Timer? _dragReleaseTimer;
  Timer? _shelfControlsHideTimer;
  _PendingBookDrag? _pendingBookDrag;
  int? _dragSourceSlot;
  int? _dragHoverSlot;
  int? _dragShelfDirection;
  bool _dragSettling = false;
  bool _createdShelfDuringDrag = false;
  int? _suppressedTapSlot;
  DateTime _suppressTapUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _shelfSwipeBlocked = false;
  bool _shelfSwipeActive = false;
  double _shelfSwipeDistance = 0;
  double _shelfSwipeOffset = 0;
  double _shelfSwipeExtent = 1;
  double _shelfSwipeAnimationStart = 0;
  double _shelfSwipeAnimationTarget = 0;
  int _shelfSwipeAnimationGeneration = 0;
  late final AnimationController _shelfSwipeController;
  int _shelfIndex = 0;
  int _shelfDirection = 1;
  int _shelfViewKey = 0;
  String _query = '';
  bool _showShelfControls = false;
  bool _exitInProgress = false;

  int get _shelfCount => (_slots.length / BookStorage.shelfSize).ceil();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shelfSwipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    )..addListener(_tickShelfSwipeAnimation);
    while (_shelfNames.length < _shelfCount) {
      _shelfNames.add(_defaultShelfName(_shelfNames.length));
    }
    if (_shelfNames.length > _shelfCount) {
      _shelfNames.removeRange(_shelfCount, _shelfNames.length);
    }
  }

  String _defaultShelfName(int index) => 'Shelf ${index + 1}';

  String _shelfName(int index) {
    if (index < 0 || index >= _shelfNames.length) {
      return _defaultShelfName(index);
    }
    return _shelfNames[index];
  }

  void _ensureShelf(int index) {
    while (_slots.length < (index + 1) * BookStorage.shelfSize) {
      _slots.addAll(List<BookRecord?>.filled(BookStorage.shelfSize, null));
    }
    while (_shelfNames.length <= index) {
      _shelfNames.add(_defaultShelfName(_shelfNames.length));
    }
  }

  List<BookRecord?> get _visibleShelf {
    _ensureShelf(_shelfIndex);
    final start = _shelfIndex * BookStorage.shelfSize;
    return _slots.sublist(start, start + BookStorage.shelfSize);
  }

  int _globalSlot(int localSlot) => _shelfIndex * BookStorage.shelfSize + localSlot;

  Future<void> _openSlot(int localSlot) {
    if (_shelfSwipeActive) {
      return Future<void>.value();
    }
    final slot = _globalSlot(localSlot);
    if (_suppressedTapSlot == slot &&
        DateTime.now().isBefore(_suppressTapUntil)) {
      return Future<void>.value();
    }
    return _openGlobalSlot(slot);
  }

  Future<void> _openGlobalSlot(int slot, {String? searchQuery}) async {
    _ensureShelf(slot ~/ BookStorage.shelfSize);
    var book = _slots[slot];
    if (book == null) {
      book = _freshBookForSlot(slot);
      _recordUsage(booksCreated: 1);
      setState(() => _slots[slot] = book);
      await widget.storage.saveSlots(_slots);
      await widget.sounds.play(GameSound.insert);
    } else {
      await widget.sounds.play(GameSound.pageTurn);
    }
    _recordUsage(booksOpened: 1);

    if (!mounted) {
      return;
    }
    final result = await Navigator.of(context).push<BookRecord>(
      MaterialPageRoute<BookRecord>(
        builder: (_) => BookEditorScreen(
          initialBook: book!,
          initialTwoPage: _settings.openBooksInTwoPageMode,
          bookSizeScale: _settings.bookSizeScale,
          autoHideEditorControls: _settings.autoHideEditorControls,
          pageDateFormat: _settings.pageDateFormat,
          backgroundId: _settings.backgroundId,
          backgroundOpacity: _settings.backgroundOpacity,
          initialSearchQuery: searchQuery,
          transparentModeListenable: widget.transparentModeListenable,
          onSetTransparentMode: widget.onSetTransparentMode,
          sounds: widget.sounds,
          onOpenSettings: () async {
            await _openSettings();
            return _settings;
          },
          onAutosave: _autosaveBook,
          onTextEdited: (typed, deleted, insertedText) => _recordUsage(
            lettersTyped: typed,
            lettersDeleted: deleted,
            typedText: insertedText,
          ),
          onPageTurned: () => _recordUsage(pageTurns: 1),
          onPagesChanged: (inserted, deleted) => _recordUsage(
            pagesInserted: inserted,
            pagesDeleted: deleted,
          ),
          onBookExported: () => _recordUsage(booksExported: 1),
          onKeyboardKeyPressed: (key, count) => _recordUsage(
            keyPresses: <String, int>{key: count},
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _slots[slot] = result);
      await widget.storage.saveSlots(_slots);
    }
  }

  BookRecord _freshBookForSlot(int slot) {
    final fresh = BookRecord.fresh(
      slot,
      randomizeCoverColor: _settings.randomizeNewBookColors,
    );
    final shelfStart = (slot ~/ BookStorage.shelfSize) * BookStorage.shelfSize;
    final usedVariants = <int>{};
    for (var index = shelfStart;
        index < shelfStart + BookStorage.shelfSize && index < _slots.length;
        index++) {
      final existing = _slots[index];
      if (existing != null) {
        usedVariants.add(existing.visualVariant);
      }
    }
    final availableVariants = <int>[
      for (var variant = 0;
          variant < BookRecord.visualVariantCount;
          variant++)
        if (!usedVariants.contains(variant)) variant,
    ];
    if (availableVariants.isEmpty) {
      return fresh;
    }
    return fresh.copyWith(
      visualVariant:
          availableVariants[math.Random().nextInt(availableVariants.length)],
    );
  }

  Future<void> _autosaveBook(BookRecord book) async {
    _ensureShelf(book.slot ~/ BookStorage.shelfSize);
    _slots[book.slot] = book;
    await widget.storage.saveSlots(_slots);
  }

  Future<void> _showSlotMenu(int localSlot, Offset position) async {
    if (_shelfSwipeActive) {
      return;
    }
    final slot = _globalSlot(localSlot);
    final book = _slots[slot];
    if (book == null) {
      await _showShelfMenu(position);
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(overlay.globalToLocal(position), overlay.globalToLocal(position)),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF1A1018),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'favorite', child: Text(book.favorite ? 'Remove favorite' : 'Mark favorite')),
        const PopupMenuItem<String>(value: 'rename', child: Text('Rename book')),
        const PopupMenuItem<String>(value: 'customize', child: Text('Customize book')),
        const PopupMenuItem<String>(value: 'duplicate', child: Text('Duplicate book')),
        if (AndroidPlatform.isAndroid)
          const PopupMenuItem<String>(value: 'move', child: Text('Move book')),
        const PopupMenuItem<String>(value: 'export', child: Text('Export book...')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'remove',
          child: Text(
            'Remove book',
            style: TextStyle(color: Color(0xFFFF6B6B)),
          ),
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case 'favorite':
        setState(() => _slots[slot] = book.copyWith(favorite: !book.favorite, updatedAt: DateTime.now()));
        await widget.storage.saveSlots(_slots);
        break;
      case 'rename':
        await _renameBook(slot, book);
        break;
      case 'customize':
        await _customizeBook(slot, book);
        break;
      case 'duplicate':
        await _duplicateBook(book);
        break;
      case 'move':
        await _moveBookOnTouch(slot, book);
        break;
      case 'export':
        await _exportBook(book);
        break;
      case 'remove':
        await _removeBook(slot);
        break;
    }
  }

  Future<void> _renameBook(int slot, BookRecord book) async {
    final name = await showRenameBookDialog(
      context,
      currentTitle: book.title,
    );
    if (name == null || !mounted || _slots[slot]?.id != book.id) {
      return;
    }
    setState(() => _slots[slot] = book.copyWith(title: name, updatedAt: DateTime.now()));
    await widget.storage.saveSlots(_slots);
  }

  Future<void> _moveBookOnTouch(int source, BookRecord book) async {
    final destinations = <int>[
      for (var slot = 0; slot < _slots.length; slot++)
        if (_slots[slot] == null) slot,
      _slots.length,
    ];
    final target = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move book'),
        content: SizedBox(width: 360, height: 320,
          child: ListView.builder(
            itemCount: destinations.length,
            itemBuilder: (context, index) {
              final slot = destinations[index];
              return ListTile(
                title: Text(slot == _slots.length ? 'New shelf'
                    : '${_shelfName(slot ~/ BookStorage.shelfSize)} — slot ${slot % BookStorage.shelfSize + 1}'),
                onTap: () => Navigator.of(context).pop(slot),
              );
            },
          ),
        ),
        actions: <Widget>[TextButton(
          onPressed: () => Navigator.of(context).pop(), child: const Text('CANCEL'))],
      ),
    );
    if (!mounted || target == null || _slots[source]?.id != book.id) return;
    if (target < _slots.length && _slots[target] != null) return;
    setState(() {
      _ensureShelf(target ~/ BookStorage.shelfSize);
      _slots[source] = null;
      _slots[target] = book.copyWith(slot: target, updatedAt: DateTime.now());
      _shelfIndex = target ~/ BookStorage.shelfSize;
      _shelfViewKey++;
    });
    await widget.storage.saveSlots(_slots);
    await widget.storage.saveShelfNames(_shelfNames);
  }

  Future<void> _customizeBook(int slot, BookRecord book) async {
    final customized = await showDialog<BookRecord>(
      context: context,
      builder: (context) => _BookCustomizationDialog(
        book: book,
        sounds: widget.sounds,
      ),
    );
    if (customized == null || !mounted || _slots[slot]?.id != book.id) {
      return;
    }
    setState(() {
      _slots[slot] = customized.copyWith(
        slot: slot,
        updatedAt: DateTime.now(),
      );
    });
    await widget.storage.saveSlots(_slots);
  }

  int _firstEmptySlot() {
    final slot = _slots.indexWhere((book) => book == null);
    if (slot >= 0) {
      return slot;
    }
    final next = _slots.length;
    _ensureShelf(next ~/ BookStorage.shelfSize);
    return next;
  }

  Future<void> _duplicateBook(BookRecord source) async {
    final slot = _firstEmptySlot();
    final targetShelf = slot ~/ BookStorage.shelfSize;
    final now = DateTime.now();
    final copy = source.copyWith(
      id: '${now.microsecondsSinceEpoch}-$slot',
      slot: slot,
      title: '${source.title} Copy',
      signed: false,
      author: '',
      createdAt: now,
      updatedAt: now,
    );
    setState(() {
      if (targetShelf != _shelfIndex) {
        _shelfDirection = targetShelf > _shelfIndex ? 1 : -1;
        _shelfViewKey++;
      }
      _slots[slot] = copy;
      _shelfIndex = targetShelf;
    });
    await widget.storage.saveSlots(_slots);
    await widget.sounds.play(GameSound.insert);
    _recordUsage(booksDuplicated: 1);
  }

  Future<void> _exportBook(BookRecord book) async {
    try {
      final saved = await _files.exportBook(book);
      if (saved && mounted) {
        _recordUsage(booksExported: 1);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Book exported.')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    }
  }

  Future<void> _showShelfMenu(Offset position) async {
    if (_dragSourceSlot != null ||
        _shelfSwipeActive ||
        _query.trim().isNotEmpty) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(overlay.globalToLocal(position), overlay.globalToLocal(position)),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF1A1018),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'rename',
          child: Text('Rename shelf'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          enabled: _shelfCount > 1,
          child: Text(
            'Delete shelf',
            style: TextStyle(
              color: _shelfCount > 1 ? const Color(0xFFFF7777) : null,
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'exit',
          child: Text(
            'Exit app',
            style: TextStyle(color: Color(0xFFFF6B6B)),
          ),
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'rename') {
      await _renameCurrentShelf();
    } else if (action == 'delete') {
      await _deleteCurrentShelf();
    } else if (action == 'exit') {
      await _exitApp();
    }
  }

  Future<void> _exitApp() async {
    if (_exitInProgress) {
      return;
    }
    _exitInProgress = true;
    _statsSaveTimer?.cancel();
    try {
      await widget.storage.saveSlots(_slots);
      await widget.storage.saveShelfNames(_shelfNames);
      await widget.storage.saveSettings(_settings);
      await widget.storage.saveUsageStats(_usageStats);
    } on Object {
      // Exiting must remain available even if a final disk write fails.
    }
    if (AndroidPlatform.isAndroid) {
      _exitInProgress = false;
      await SystemNavigator.pop();
      return;
    }
    try {
      await widget.sounds.dispose();
    } on Object {
      // The process exit below is the final fallback for native cleanup.
    }
    exit(0);
  }

  Future<void> _showMainMenu(Offset position) async {
    if (_dragSourceSlot != null || _shelfSwipeActive) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(overlay.globalToLocal(position), overlay.globalToLocal(position)),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF1A1018),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'exit',
          child: Text(
            'Exit app',
            style: TextStyle(color: Color(0xFFFF6B6B)),
          ),
        ),
      ],
    );
    if (!mounted || action != 'exit') {
      return;
    }
    await _exitApp();
  }

  Future<void> _importBook() async {
    final slot = _firstEmptySlot();
    try {
      final imported = await _files.importBook(slot: slot);
      if (imported == null || !mounted) {
        return;
      }
      final now = DateTime.now();
      final targetShelf = slot ~/ BookStorage.shelfSize;
      setState(() {
        if (targetShelf != _shelfIndex) {
          _shelfDirection = targetShelf > _shelfIndex ? 1 : -1;
          _shelfViewKey++;
        }
        _slots[slot] = imported.copyWith(
          id: '${now.microsecondsSinceEpoch}-$slot',
          slot: slot,
          createdAt: now,
          updatedAt: now,
        );
        _shelfIndex = targetShelf;
      });
      await widget.storage.saveSlots(_slots);
      await widget.sounds.play(GameSound.insert);
      _recordUsage(booksImported: 1);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $error')));
      }
    }
  }

  Future<void> _removeBook(int slot) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: BookAndQuillColors.woodDark,
            title: const Text('Remove this book?'),
            content: const Text('This permanently clears the selected shelf slot.'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'REMOVE',
                  style: TextStyle(color: Color(0xFFFF6B6B)),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _slots[slot] = null);
    await widget.storage.saveSlots(_slots);
    await widget.sounds.play(GameSound.pickup);
    _recordUsage(booksDeleted: 1);
  }

  void _prepareBookDrag(int localSlot, PointerDownEvent event) {
    if (event.buttons != 1 ||
        _dragSourceSlot != null ||
        _shelfSwipeActive) {
      return;
    }
    final slot = _globalSlot(localSlot);
    if (slot < 0 || slot >= _slots.length || _slots[slot] == null) {
      return;
    }
    _pendingBookDrag = _PendingBookDrag(
      pointer: event.pointer,
      sourceSlot: slot,
      startPosition: event.position,
    );
    _createdShelfDuringDrag = false;
    _dragFeedbackTarget.value = _stackLocalPosition(event.position);
  }

  void _updateShelfControlsForPointer(Offset globalPosition) {
    if (!_settings.autoHideEditorControls) {
      _shelfControlsHideTimer?.cancel();
      _shelfControlsHideTimer = null;
      return;
    }
    final renderObject =
        _libraryStackKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final local = renderObject.globalToLocal(globalPosition);
    final shouldShow = local.dy >= renderObject.size.height - 105;
    if (shouldShow) {
      _shelfControlsHideTimer?.cancel();
      _shelfControlsHideTimer = null;
      if (!_showShelfControls) {
        setState(() => _showShelfControls = true);
      }
      return;
    }
    if (!_showShelfControls || _shelfControlsHideTimer != null) {
      return;
    }
    _shelfControlsHideTimer = Timer(const Duration(milliseconds: 700), () {
      _shelfControlsHideTimer = null;
      if (mounted) {
        setState(() => _showShelfControls = false);
      }
    });
  }

  void _handlePointerHover(PointerHoverEvent event) {
    _updateShelfControlsForPointer(event.position);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _updateShelfControlsForPointer(event.position);
    final pending = _pendingBookDrag;
    if (pending == null || pending.pointer != event.pointer) {
      return;
    }

    if (_dragSourceSlot == null) {
      final distance = (event.position - pending.startPosition).distance;
      if (distance < 14) {
        return;
      }
      _dragFeedbackTarget.value = _stackLocalPosition(event.position);
      setState(() {
        _dragSourceSlot = pending.sourceSlot;
        _dragHoverSlot = null;
      });
      widget.sounds.play(GameSound.pickup);
    } else {
      _dragFeedbackTarget.value = _stackLocalPosition(event.position);
    }

    _updateDragHover(event.position);
    _updateDragShelfEdge(event.position);
  }

  void _handlePointerUp(PointerUpEvent event) {
    final pending = _pendingBookDrag;
    if (pending == null || pending.pointer != event.pointer) {
      return;
    }
    if (_dragSourceSlot == null) {
      _pendingBookDrag = null;
      return;
    }

    final sourceSlot = _dragSourceSlot!;
    final targetSlot = _dragHoverSlot == null
        ? null
        : _globalSlot(_dragHoverSlot!);
    _suppressedTapSlot = sourceSlot;
    _suppressTapUntil =
        DateTime.now().add(const Duration(milliseconds: 240));
    _settleBookDrag(sourceSlot, targetSlot);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    final pending = _pendingBookDrag;
    if (pending == null || pending.pointer != event.pointer) {
      return;
    }
    final sourceSlot = _dragSourceSlot;
    if (sourceSlot != null) {
      _suppressedTapSlot = sourceSlot;
      _suppressTapUntil =
          DateTime.now().add(const Duration(milliseconds: 240));
      widget.sounds.play(GameSound.insert);
    }
    _clearBookDragState();
  }

  void _settleBookDrag(int sourceSlot, int? targetSlot) {
    _pendingBookDrag = null;
    _dragShelfTimer?.cancel();
    _dragShelfTimer = null;
    final acceptedTarget = targetSlot != null && targetSlot != sourceSlot
        ? targetSlot
        : null;
    final settleLocalSlot = acceptedTarget == null
        ? sourceSlot ~/ BookStorage.shelfSize == _shelfIndex
            ? sourceSlot % BookStorage.shelfSize
            : null
        : acceptedTarget % BookStorage.shelfSize;
    if (settleLocalSlot != null) {
      final center = _shelfSlotCenterInStack(settleLocalSlot);
      if (center != null) {
        _dragFeedbackTarget.value = center;
      }
    }
    setState(() {
      _dragSettling = true;
      _dragHoverSlot = null;
      _dragShelfDirection = null;
    });
    _dragReleaseTimer?.cancel();
    _dragReleaseTimer = Timer(const Duration(milliseconds: 210), () {
      _dragReleaseTimer = null;
      _clearBookDragState(cancelRelease: false);
      if (acceptedTarget != null) {
        _moveDraggedBook(sourceSlot, acceptedTarget);
      } else {
        widget.sounds.play(GameSound.insert);
      }
    });
  }

  void _clearBookDragState({bool cancelRelease = true}) {
    _dragShelfTimer?.cancel();
    _dragShelfTimer = null;
    if (cancelRelease) {
      _dragReleaseTimer?.cancel();
      _dragReleaseTimer = null;
    }
    _pendingBookDrag = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _dragSourceSlot = null;
      _dragHoverSlot = null;
      _dragShelfDirection = null;
      _dragSettling = false;
      _createdShelfDuringDrag = false;
    });
  }

  Offset _stackLocalPosition(Offset globalPosition) {
    final renderObject =
        _libraryStackKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.globalToLocal(globalPosition);
    }
    return globalPosition;
  }

  int? _shelfSlotAtGlobalPosition(Offset globalPosition) {
    final renderObject =
        _shelfViewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final viewportPosition = renderObject.globalToLocal(globalPosition);
    final side = math
        .min(
          650.0,
          math.min(renderObject.size.width, renderObject.size.height),
        )
        .toDouble();
    final shelfOrigin = Offset(
      (renderObject.size.width - side) / 2,
      (renderObject.size.height - side) / 2,
    );
    return ChiseledBookshelf.slotAtLocalPosition(
      viewportPosition - shelfOrigin,
      Size.square(side),
    );
  }

  Offset? _shelfSlotCenterInStack(int localSlot) {
    if (localSlot < 0 || localSlot >= BookStorage.shelfSize) {
      return null;
    }
    final viewportObject =
        _shelfViewportKey.currentContext?.findRenderObject();
    final stackObject = _libraryStackKey.currentContext?.findRenderObject();
    if (viewportObject is! RenderBox ||
        stackObject is! RenderBox ||
        !viewportObject.hasSize ||
        !stackObject.hasSize) {
      return null;
    }
    final side = math
        .min(
          650.0,
          math.min(viewportObject.size.width, viewportObject.size.height),
        )
        .toDouble();
    final slotRect = ChiseledBookshelf.slotRects[localSlot];
    final shelfOrigin = Offset(
      (viewportObject.size.width - side) / 2,
      (viewportObject.size.height - side) / 2,
    );
    final centerInViewport = shelfOrigin +
        Offset(
          side * slotRect.center.dx,
          side * slotRect.center.dy,
        );
    final globalCenter = viewportObject.localToGlobal(centerInViewport);
    return stackObject.globalToLocal(globalCenter);
  }

  void _updateDragHover(Offset globalPosition) {
    var localSlot = _shelfSlotAtGlobalPosition(globalPosition);
    final sourceSlot = _dragSourceSlot;
    if (localSlot != null &&
        sourceSlot != null &&
        _globalSlot(localSlot) == sourceSlot) {
      localSlot = null;
    }
    if (localSlot == _dragHoverSlot) {
      return;
    }
    setState(() => _dragHoverSlot = localSlot);
  }

  void _updateDragShelfEdge(Offset globalPosition) {
    final renderObject =
        _libraryStackKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final position = renderObject.globalToLocal(globalPosition);
    final edgeWidth =
        (renderObject.size.width * 0.09).clamp(72.0, 120.0).toDouble();
    int? direction;
    if (position.dx <= edgeWidth && _shelfIndex > 0) {
      direction = -1;
    } else if (position.dx >= renderObject.size.width - edgeWidth &&
        (_shelfIndex + 1 < _shelfCount || !_createdShelfDuringDrag)) {
      direction = 1;
    }
    if (direction == _dragShelfDirection) {
      return;
    }

    _dragShelfTimer?.cancel();
    setState(() => _dragShelfDirection = direction);
    if (direction == null) {
      return;
    }
    _dragShelfTimer = Timer(const Duration(milliseconds: 560), () {
      if (!mounted ||
          _dragSourceSlot == null ||
          _dragShelfDirection != direction) {
        return;
      }
      final target = _shelfIndex + direction!;
      if (target < 0 ||
          (target >= _shelfCount &&
              (direction! < 0 || _createdShelfDuringDrag))) {
        return;
      }
      final creatingShelf = target >= _shelfCount;
      setState(() {
        if (creatingShelf) {
          _ensureShelf(target);
          _createdShelfDuringDrag = true;
        }
        _shelfDirection = direction!;
        _shelfIndex = target;
        _shelfViewKey++;
        _dragHoverSlot = null;
        _dragShelfDirection = null;
      });
      if (creatingShelf) {
        widget.storage.saveSlots(_slots);
        widget.storage.saveShelfNames(_shelfNames);
      }
      widget.sounds.playShelfTurn();
    });
  }

  Future<void> _moveDraggedBook(int sourceSlot, int targetSlot) async {
    if (sourceSlot < 0 ||
        sourceSlot >= _slots.length ||
        targetSlot < 0 ||
        targetSlot >= _slots.length ||
        sourceSlot == targetSlot) {
      return;
    }
    final sourceBook = _slots[sourceSlot];
    if (sourceBook == null) {
      return;
    }
    final targetBook = _slots[targetSlot];
    setState(() {
      _slots[targetSlot] = sourceBook.copyWith(slot: targetSlot);
      _slots[sourceSlot] = targetBook?.copyWith(slot: sourceSlot);
    });
    await widget.storage.saveSlots(_slots);
    await widget.storage.saveShelfNames(_shelfNames);
    await widget.sounds.play(GameSound.insert);
  }

  Future<void> _goToNextShelf() async {
    if (_dragSourceSlot != null || _shelfSwipeActive) {
      return;
    }
    if (_shelfIndex + 1 < _shelfCount) {
      _showShelf(_shelfIndex + 1);
      return;
    }

    setState(() {
      _shelfDirection = 1;
      _shelfIndex++;
      _shelfViewKey++;
      _ensureShelf(_shelfIndex);
    });
    await widget.storage.saveSlots(_slots);
    await widget.storage.saveShelfNames(_shelfNames);
    await widget.sounds.playShelfTurn();
  }

  void _startShelfSwipe(DragStartDetails _, double extent) {
    _shelfSwipeBlocked =
        _pendingBookDrag != null || _dragSourceSlot != null;
    if (_shelfSwipeBlocked) {
      return;
    }

    _shelfSwipeAnimationGeneration++;
    _shelfSwipeController.stop();
    _shelfSwipeExtent = math.max(1, extent).toDouble();
    setState(() {
      _shelfSwipeDistance = _shelfSwipeActive ? _shelfSwipeOffset : 0;
      _shelfSwipeActive = true;
      if (_shelfSwipeDistance == 0) {
        _shelfSwipeOffset = 0;
      }
    });
  }

  void _updateShelfSwipe(DragUpdateDetails details) {
    if (_shelfSwipeBlocked ||
        !_shelfSwipeActive ||
        _pendingBookDrag != null ||
        _dragSourceSlot != null) {
      return;
    }

    setState(() {
      _shelfSwipeDistance += details.delta.dx;
      var visibleOffset = _shelfSwipeDistance;
      if (_shelfIndex == 0 && visibleOffset > 0) {
        visibleOffset *= 0.28;
      }
      _shelfSwipeOffset = visibleOffset
          .clamp(-_shelfSwipeExtent, _shelfSwipeExtent)
          .toDouble();
    });
  }

  void _endShelfSwipe(DragEndDetails details) {
    final blocked = _shelfSwipeBlocked || _dragSourceSlot != null;
    final distance = _shelfSwipeDistance;
    final velocity = details.primaryVelocity ?? 0;
    _shelfSwipeBlocked = false;
    if (blocked || !_shelfSwipeActive) {
      _shelfSwipeDistance = 0;
      return;
    }

    const distanceThreshold = 52.0;
    const velocityThreshold = 650.0;
    if (distance <= -distanceThreshold || velocity <= -velocityThreshold) {
      _settleShelfSwipe(1);
    } else if ((distance >= distanceThreshold ||
            velocity >= velocityThreshold) &&
        _shelfIndex > 0) {
      _settleShelfSwipe(-1);
    } else {
      _settleShelfSwipe(0);
    }
  }

  void _cancelShelfSwipe() {
    _shelfSwipeBlocked = false;
    _shelfSwipeDistance = 0;
    if (_shelfSwipeActive) {
      _settleShelfSwipe(0);
    }
  }

  void _settleShelfSwipe(int direction) {
    final target = direction == 0
        ? 0.0
        : direction > 0
            ? -_shelfSwipeExtent
            : _shelfSwipeExtent;
    _animateShelfSwipeTo(target, () {
      if (direction == 0) {
        setState(() {
          _shelfSwipeActive = false;
          _shelfSwipeDistance = 0;
          _shelfSwipeOffset = 0;
        });
        return;
      }
      _completeShelfSwipe(direction);
    });
  }

  void _animateShelfSwipeTo(double target, VoidCallback onCompleted) {
    final generation = ++_shelfSwipeAnimationGeneration;
    _shelfSwipeController.stop();
    _shelfSwipeAnimationStart = _shelfSwipeOffset;
    _shelfSwipeAnimationTarget = target;
    _shelfSwipeController.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted ||
          generation != _shelfSwipeAnimationGeneration ||
          _shelfSwipeController.status != AnimationStatus.completed) {
        return;
      }
      onCompleted();
    });
  }

  void _tickShelfSwipeAnimation() {
    if (!mounted) {
      return;
    }
    final progress =
        Curves.easeOutCubic.transform(_shelfSwipeController.value);
    setState(() {
      _shelfSwipeOffset = _shelfSwipeAnimationStart +
          (_shelfSwipeAnimationTarget - _shelfSwipeAnimationStart) * progress;
    });
  }

  void _completeShelfSwipe(int direction) {
    final targetShelf = _shelfIndex + direction;
    if (targetShelf < 0) {
      _settleShelfSwipe(0);
      return;
    }
    final creatingShelf = targetShelf >= _shelfCount;
    setState(() {
      if (creatingShelf) {
        _ensureShelf(targetShelf);
      }
      _shelfDirection = direction;
      _shelfIndex = targetShelf;
      _shelfViewKey++;
      _shelfSwipeActive = false;
      _shelfSwipeDistance = 0;
      _shelfSwipeOffset = 0;
    });
    if (creatingShelf) {
      widget.storage.saveSlots(_slots);
      widget.storage.saveShelfNames(_shelfNames);
    }
    widget.sounds.playShelfTurn();
  }

  void _showShelf(int index) {
    if (_dragSourceSlot != null ||
        _shelfSwipeActive ||
        index < 0 ||
        index >= _shelfCount ||
        index == _shelfIndex) {
      return;
    }
    setState(() {
      _shelfDirection = index > _shelfIndex ? 1 : -1;
      _shelfIndex = index;
      _shelfViewKey++;
    });
    widget.sounds.playShelfTurn();
  }

  Future<void> _renameCurrentShelf() async {
    if (_dragSourceSlot != null ||
        _shelfSwipeActive ||
        _query.trim().isNotEmpty) {
      return;
    }
    final shelf = _shelfIndex;
    final name = await showRenameShelfDialog(
      context,
      currentName: _shelfName(shelf),
    );
    if (name == null || name.isEmpty || !mounted || shelf >= _shelfNames.length) {
      return;
    }
    setState(() => _shelfNames[shelf] = name);
    await widget.storage.saveShelfNames(_shelfNames);
  }

  Future<void> _deleteCurrentShelf() async {
    if (_dragSourceSlot != null ||
        _shelfSwipeActive ||
        _shelfCount <= 1) {
      return;
    }

    final start = _shelfIndex * BookStorage.shelfSize;
    final end = start + BookStorage.shelfSize;
    final shelfBooks = _slots
        .sublist(start, end)
        .whereType<BookRecord>()
        .toList(growable: false);
    final writtenBooks = shelfBooks
        .where((book) => book.hasWriting)
        .toList(growable: false);
    if (writtenBooks.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: BookAndQuillColors.woodDark,
          title: const Text("Shelf Can't Be Deleted"),
          content: const Text(
            'Delete or move the books in the shelf to delete the shelf.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final removedBooks = shelfBooks.length;
    final bookMessage = removedBooks == 0
        ? 'This shelf is empty.'
        : 'This will permanently delete $removedBooks '
            '${removedBooks == 1 ? 'book' : 'books'} on this shelf.';
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: BookAndQuillColors.woodDark,
            title: Text('Delete ${_shelfName(_shelfIndex)}?'),
            content: Text(bookMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('DELETE SHELF'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }

    final revisedSlots = List<BookRecord?>.from(_slots)..removeRange(start, end);
    for (var slot = start; slot < revisedSlots.length; slot++) {
      final book = revisedSlots[slot];
      if (book != null && book.slot != slot) {
        revisedSlots[slot] = book.copyWith(slot: slot);
      }
    }

    final revisedShelfNames = List<String>.from(_shelfNames)
      ..removeAt(_shelfIndex);
    for (var index = 0; index < revisedShelfNames.length; index++) {
      if (RegExp(r'^Shelf \d+$').hasMatch(revisedShelfNames[index])) {
        revisedShelfNames[index] = _defaultShelfName(index);
      }
    }
    final newShelfCount = revisedSlots.length ~/ BookStorage.shelfSize;
    final newShelfIndex = _shelfIndex.clamp(0, newShelfCount - 1).toInt();
    setState(() {
      _shelfDirection = _shelfIndex >= newShelfCount ? -1 : 1;
      _shelfIndex = newShelfIndex;
      _shelfViewKey++;
      _slots
        ..clear()
        ..addAll(revisedSlots);
      _shelfNames
        ..clear()
        ..addAll(revisedShelfNames);
    });
    await widget.storage.saveSlots(_slots);
    await widget.storage.saveShelfNames(_shelfNames);
    await widget.sounds.playShelfDelete();
    if (removedBooks > 0) {
      _recordUsage(booksDeleted: removedBooks);
    }
  }

  KeyEventResult _handleLibraryKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.delete ||
        _query.isNotEmpty ||
        ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    unawaited(_deleteCurrentShelf());
    return KeyEventResult.handled;
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute<AppSettings>(
        builder: (_) => SettingsScreen(
          initialSettings: _settings,
          sounds: widget.sounds,
          fullscreenListenable: widget.fullscreenListenable,
          onToggleFullscreen: widget.onToggleFullscreen,
          onOpenStats: _openStats,
          onImportBook: _importBook,
        ),
      ),
    );
    if (updated == null || !mounted) {
      return;
    }
    setState(() {
      _settings = updated;
      if (_settings.autoHideEditorControls) {
        _shelfControlsHideTimer?.cancel();
        _shelfControlsHideTimer = null;
        _showShelfControls = false;
      } else {
        _shelfControlsHideTimer?.cancel();
        _shelfControlsHideTimer = null;
      }
    });
    widget.sounds.applySettings(updated);
    await widget.storage.saveSettings(updated);
  }

  void _recordUsage({
    int lettersTyped = 0,
    int lettersDeleted = 0,
    int booksCreated = 0,
    int booksOpened = 0,
    int booksDeleted = 0,
    int booksImported = 0,
    int booksExported = 0,
    int booksDuplicated = 0,
    int pagesInserted = 0,
    int pagesDeleted = 0,
    int pageTurns = 0,
    String typedText = '',
    Map<String, int> keyPresses = const <String, int>{},
  }) {
    _usageStats = _usageStats.add(
      lettersTyped: lettersTyped,
      lettersDeleted: lettersDeleted,
      booksCreated: booksCreated,
      booksOpened: booksOpened,
      booksDeleted: booksDeleted,
      booksImported: booksImported,
      booksExported: booksExported,
      booksDuplicated: booksDuplicated,
      pagesInserted: pagesInserted,
      pagesDeleted: pagesDeleted,
      pageTurns: pageTurns,
      typedText: typedText,
      keyPresses: keyPresses,
    );
    _statsSaveTimer?.cancel();
    _statsSaveTimer = Timer(
      const Duration(milliseconds: 600),
      () => widget.storage.saveUsageStats(_usageStats),
    );
  }

  Future<void> _openStats(AppSettings previewSettings) async {
    _statsSaveTimer?.cancel();
    await widget.storage.saveUsageStats(_usageStats);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StatsScreen(
          slots: List<BookRecord?>.unmodifiable(_slots),
          usage: _usageStats,
          sounds: widget.sounds,
          backgroundId: previewSettings.backgroundId,
          backgroundOpacity: previewSettings.backgroundOpacity,
          onResetStats: _resetUsageStats,
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AndroidPlatform.isAndroid && state != AppLifecycleState.resumed) {
      _statsSaveTimer?.cancel();
      unawaited(widget.storage.saveUsageStats(_usageStats).catchError((Object error) {
        debugPrint('Could not save backgrounded statistics: $error');
      }));
    }
  }

  Future<void> _resetUsageStats() async {
    _statsSaveTimer?.cancel();
    _usageStats = UsageStats.empty;
    await widget.storage.saveUsageStats(_usageStats);
  }

  List<BookRecord> get _searchResults {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return const <BookRecord>[];
    }
    final results = _slots.whereType<BookRecord>().where((book) => book.searchableText.contains(query)).toList();
    results.sort((a, b) {
      if (a.favorite != b.favorite) {
        return a.favorite ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return results;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statsSaveTimer?.cancel();
    _dragShelfTimer?.cancel();
    _dragReleaseTimer?.cancel();
    _shelfControlsHideTimer?.cancel();
    _shelfSwipeAnimationGeneration++;
    _shelfSwipeController.dispose();
    widget.storage.saveUsageStats(_usageStats);
    widget.storage.saveShelfNames(_shelfNames);
    _searchController.dispose();
    _dragFeedbackTarget.dispose();
    widget.sounds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final occupied = _slots.whereType<BookRecord>().length;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _openSettings,
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleLibraryKeyEvent,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: _handlePointerHover,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: Scaffold(
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapUp: (details) =>
                  _showMainMenu(details.globalPosition),
              onLongPressStart: AndroidPlatform.isAndroid
                  ? (details) => _showMainMenu(details.globalPosition)
                  : null,
              child: Stack(
                key: _libraryStackKey,
                children: <Widget>[
            Positioned.fill(
              child: AppBackground(
                backgroundId: _settings.backgroundId,
                opacity: _settings.backgroundOpacity,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.all(AndroidPlatform.isAndroid ? 12 : 22),
                child: LayoutBuilder(builder: (context, constraints) {
                  final keyboardOpen = AndroidPlatform.isAndroid &&
                      MediaQuery.viewInsetsOf(context).bottom > 0;
                  final content = Column(
                  children: <Widget>[
                    _buildHeader(occupied),
                    const SizedBox(height: 10),
                    if (_query.trim().isEmpty && !keyboardOpen) ...<Widget>[
                      _buildShelfTitle(),
                      const SizedBox(height: 6),
                    ],
                    Expanded(
                      child: _query.trim().isEmpty
                          ? _buildShelf()
                          : _buildSearchResults(),
                    ),
                    if (!keyboardOpen) ...<Widget>[
                      const SizedBox(height: 12),
                      _buildFooter(),
                    ],
                  ],
                  );
                  if (!AndroidPlatform.isAndroid) return content;
                  return SingleChildScrollView(child: SizedBox(
                    height: math.max(constraints.maxHeight,
                      keyboardOpen ? 200.0 : 360.0).toDouble(),
                    child: content,
                  ));
                }),
              ),
            ),
            if (_dragSourceSlot != null && !_dragSettling) ...<Widget>[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _ShelfDragEdgeHint(
                  direction: -1,
                  enabled: _shelfIndex > 0,
                  active: _dragShelfDirection == -1,
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _ShelfDragEdgeHint(
                  direction: 1,
                  enabled: _shelfIndex + 1 < _shelfCount ||
                      !_createdShelfDuringDrag,
                  active: _dragShelfDirection == 1,
                  createsShelf: _shelfIndex + 1 >= _shelfCount,
                ),
              ),
            ],
            if (_dragSourceSlot != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: _PhysicsBookDragFeedback(
                    key: const ValueKey<String>('book-drag-feedback'),
                    target: _dragFeedbackTarget,
                    settling: _dragSettling,
                  ),
                ),
              ),
            CompositedTransformFollower(
              link: _headerIconLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.topLeft,
              child: const _SpringHeaderIcon(),
            ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int occupied) {
    if (AndroidPlatform.isAndroid) {
      return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (MediaQuery.viewInsetsOf(context).bottom == 0) ...<Widget>[
        Row(children: <Widget>[
          CompositedTransformTarget(link: _headerIconLink,
            child: const SizedBox(width: 64, height: 64)),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const FittedBox(fit: BoxFit.scaleDown,
                child: Text('BOOK AND QUILL',
                  style: TextStyle(color: Colors.white, fontSize: 18))),
              Text('$occupied books', style: const TextStyle(fontSize: 11)),
              const Row(children: <Widget>[
                Flexible(child: Text('Made by SHANTIASHAMS',
                  style: TextStyle(color: BookAndQuillColors.gold, fontSize: 9))),
                SizedBox(width: 4), _PlayerHeadIcon(),
              ]),
            ],
          )),
          GearButton(sounds: widget.sounds, onPressed: _openSettings),
        ]),
        const SizedBox(height: 8),
        ],
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
            isDense: true, hintText: 'Search your library',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty ? null : IconButton(
              tooltip: 'Clear search', icon: const Icon(Icons.close),
              onPressed: () { _searchController.clear(); setState(() => _query = ''); }),
            filled: true, fillColor: const Color(0xCC1A1018),
            border: const OutlineInputBorder(),
          ),
        ),
      ]);
    }
    return Row(
      children: <Widget>[
        CompositedTransformTarget(
          link: _headerIconLink,
          child: const SizedBox(width: 64, height: 64),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'BOOK AND QUILL',
              style: TextStyle(fontSize: 24, letterSpacing: 2, color: Colors.white, shadows: <Shadow>[Shadow(color: Colors.black, offset: Offset(3, 3))]),
            ),
            Text('$occupied books across $_shelfCount shelves', style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 12)),
            const SizedBox(height: 2),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Made by SHANTIASHAMS',
                  style: TextStyle(
                    color: BookAndQuillColors.gold,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(width: 5),
                _PlayerHeadIcon(),
              ],
            ),
          ],
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 330),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search your library',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: const Color(0xCC1A1018),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GearButton(
          sounds: widget.sounds,
          onPressed: _openSettings,
        ),
      ],
    );
  }

  Widget _buildShelfTitle() {
    return SizedBox(
      width: double.infinity,
      height: 38,
      child: Center(
        child: Tooltip(
          message: AndroidPlatform.isAndroid ? 'Tap to rename; hold for menu' : 'Click to rename',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _renameCurrentShelf,
              onLongPressStart: AndroidPlatform.isAndroid
                  ? (details) => _showShelfMenu(details.globalPosition)
                  : null,
              onSecondaryTapUp: (details) =>
                  _showShelfMenu(details.globalPosition),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  _shelfName(_shelfIndex),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    letterSpacing: 1.6,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black, offset: Offset(3, 3)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<BookRecord?> _shelfSlotsForIndex(int shelfIndex) {
    final start = shelfIndex * BookStorage.shelfSize;
    return List<BookRecord?>.generate(BookStorage.shelfSize, (offset) {
      final slot = start + offset;
      return slot >= 0 && slot < _slots.length ? _slots[slot] : null;
    });
  }

  Widget _buildShelfPage(
    int shelfIndex, {
    required bool interactive,
    Key? key,
    int? draggedLocalSlot,
  }) {
    final page = Center(
      key: key,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 650),
        child: ChiseledBookshelf(
          slots: shelfIndex == _shelfIndex
              ? _visibleShelf
              : _shelfSlotsForIndex(shelfIndex),
          onSlotPressed: interactive ? _openSlot : (_) {},
          onSlotSecondaryPressed:
              interactive ? _showSlotMenu : (_, __) {},
          onBookPointerDown: interactive && !AndroidPlatform.isAndroid
              ? _prepareBookDrag : null,
          highlightedSlot: interactive ? _dragHoverSlot : null,
          draggedSlot: interactive ? draggedLocalSlot : null,
          dragActive: interactive && _dragSourceSlot != null,
        ),
      ),
    );
    return interactive ? page : IgnorePointer(child: page);
  }

  Widget _buildShelf() {
    final sourceSlot = _dragSourceSlot;
    final draggedLocalSlot = sourceSlot != null &&
            sourceSlot ~/ BookStorage.shelfSize == _shelfIndex
        ? sourceSlot % BookStorage.shelfSize
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportExtent = math.max(1, constraints.maxWidth).toDouble();
        final shelfBody = _shelfSwipeActive
            ? Stack(
                alignment: Alignment.center,
                fit: StackFit.expand,
                children: <Widget>[
                  if (_shelfIndex > 0)
                    Transform.translate(
                      offset: Offset(
                        _shelfSwipeOffset - _shelfSwipeExtent,
                        0,
                      ),
                      child: _buildShelfPage(
                        _shelfIndex - 1,
                        interactive: false,
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(
                      _shelfSwipeOffset + _shelfSwipeExtent,
                      0,
                    ),
                    child: _buildShelfPage(
                      _shelfIndex + 1,
                      interactive: false,
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(_shelfSwipeOffset, 0),
                    child: _buildShelfPage(
                      _shelfIndex,
                      interactive: true,
                      draggedLocalSlot: draggedLocalSlot,
                    ),
                  ),
                ],
              )
            : AnimatedSwitcher(
                duration: Duration(milliseconds: AndroidPlatform.isAndroid ? 180 : 360),
                reverseDuration: Duration(milliseconds: AndroidPlatform.isAndroid ? 150 : 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (context, animatedChild) {
                      final progress =
                          Curves.easeOutCubic.transform(animation.value);
                      final leaving =
                          animation.status == AnimationStatus.reverse;
                      final travel = (1 - progress) *
                          (leaving ? -_shelfDirection : _shelfDirection);
                      return IgnorePointer(
                        ignoring: leaving,
                        child: Opacity(
                          opacity: animation.value,
                          child: FractionalTranslation(
                            translation: Offset(travel.toDouble(), 0),
                            child: animatedChild,
                          ),
                        ),
                      );
                    },
                  );
                },
                child: _buildShelfPage(
                  _shelfIndex,
                  key: ValueKey<int>(_shelfViewKey),
                  interactive: true,
                  draggedLocalSlot: draggedLocalSlot,
                ),
              );
        return ClipRect(
          key: _shelfViewportKey,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (details) =>
                _startShelfSwipe(details, viewportExtent),
            onHorizontalDragUpdate: _updateShelfSwipe,
            onHorizontalDragEnd: _endShelfSwipe,
            onHorizontalDragCancel: _cancelShelfSwipe,
            onSecondaryTapUp: (details) =>
                _showShelfMenu(details.globalPosition),
            child: MouseRegion(
              cursor: _shelfSwipeActive
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.grab,
              child: shelfBody,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    final results = _searchResults;
    final searchQuery = _query.trim();
    if (results.isEmpty) {
      return const Center(child: Text('No matching books.', style: TextStyle(color: Colors.white, fontSize: 18)));
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final book = results[index];
            final snippetPage = book.pages.firstWhere(
              (page) => page.text
                  .toLowerCase()
                  .contains(searchQuery.toLowerCase()),
              orElse: () => book.pages.first,
            );
            final snippet = snippetPage.text.replaceAll('\n', ' ').trim();
            return ListTile(
              tileColor: const Color(0xDD1A1018),
              leading: Icon(book.favorite ? Icons.auto_awesome : Icons.menu_book, color: book.favorite ? BookAndQuillColors.gold : BookAndQuillColors.parchment),
              title: Text(book.title, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                <String>[
                  if (book.author.isNotEmpty) 'by ${book.author}',
                  if (snippet.isNotEmpty) snippet.length > 100 ? '${snippet.substring(0, 100)}...' : snippet,
                ].join('  •  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '${_shelfName(book.slot ~/ BookStorage.shelfSize)} / '
                'Slot ${book.slot % BookStorage.shelfSize + 1}',
              ),
              onTap: () => _openGlobalSlot(
                book.slot,
                searchQuery: searchQuery,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (AndroidPlatform.isAndroid) {
      return SizedBox(height: 48, child: Row(children: <Widget>[
        IconButton(tooltip: 'Previous shelf',
          onPressed: _shelfIndex > 0 && !_shelfSwipeActive
              ? () => _showShelf(_shelfIndex - 1) : null,
          icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text('Shelf ${_shelfIndex + 1} of $_shelfCount',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
        IconButton(tooltip: 'Next shelf',
          onPressed: !_shelfSwipeActive ? _goToNextShelf : null,
          icon: const Icon(Icons.chevron_right)),
        Builder(builder: (buttonContext) => IconButton(
          tooltip: 'Shelf menu', icon: const Icon(Icons.more_vert),
          onPressed: () {
            final box = buttonContext.findRenderObject()! as RenderBox;
            _showShelfMenu(box.localToGlobal(Offset.zero));
          },
        )),
      ]));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final showHint = constraints.maxWidth >= 1120;
        final controlsVisible = !_settings.autoHideEditorControls ||
            _showShelfControls;
        return SizedBox(
          width: double.infinity,
          height: 35,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              IgnorePointer(
                ignoring: !controlsVisible,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  offset: controlsVisible
                      ? Offset.zero
                      : const Offset(0, 1.35),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: controlsVisible ? 1 : 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        PixelButton(
                          label: '< SHELF',
                          width: 118,
                          compact: true,
                          enabled: _dragSourceSlot == null &&
                              !_shelfSwipeActive &&
                              _shelfIndex > 0,
                          onPressed: () => _showShelf(_shelfIndex - 1),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Shelf ${_shelfIndex + 1} of $_shelfCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 14),
                        PixelButton(
                          label: 'SHELF >',
                          width: 118,
                          compact: true,
                          enabled: _dragSourceSlot == null &&
                              !_shelfSwipeActive,
                          onPressed: _goToNextShelf,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (showHint)
                const Positioned(
                  right: 0,
                  child: Text(
                    'Drag shelf sideways • Drag books • Right-click books or shelf',
                    style: TextStyle(
                      color: Color(0xFF969696),
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SpringHeaderIcon extends StatefulWidget {
  const _SpringHeaderIcon();

  @override
  State<_SpringHeaderIcon> createState() => _SpringHeaderIconState();
}

class _SpringHeaderIconState extends State<_SpringHeaderIcon>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Offset _position = Offset.zero;
  Offset _target = Offset.zero;
  Offset _velocity = Offset.zero;
  Offset? _pointerOrigin;
  Duration _lastElapsed = Duration.zero;
  bool _dragging = false;

  void _begin(PointerDownEvent event) {
    if (event.buttons != kPrimaryMouseButton) {
      return;
    }
    setState(() {
      _dragging = true;
      _pointerOrigin = event.position - _target;
    });
    _lastElapsed = Duration.zero;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _move(PointerMoveEvent event) {
    if (!_dragging || _pointerOrigin == null) {
      return;
    }
    _target = event.position - _pointerOrigin!;
  }

  void _release([PointerEvent? _]) {
    if (!_dragging) {
      return;
    }
    setState(() {
      _dragging = false;
      _pointerOrigin = null;
      _target = Offset.zero;
    });
    _lastElapsed = Duration.zero;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final elapsedMicros = _lastElapsed == Duration.zero
        ? 16667
        : (elapsed - _lastElapsed).inMicroseconds;
    _lastElapsed = elapsed;
    final dt = (elapsedMicros / Duration.microsecondsPerSecond)
        .clamp(0.001, 0.032)
        .toDouble();
    const stiffness = 105.0;
    const damping = 15.5;
    final acceleration = (_target - _position) * stiffness -
        _velocity * damping;
    _velocity += acceleration * dt;
    _position += _velocity * dt;
    if (!_dragging &&
        _position.distance < 0.08 &&
        _velocity.distance < 0.08) {
      _position = Offset.zero;
      _velocity = Offset.zero;
      _ticker.stop();
      _lastElapsed = Duration.zero;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _dragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _begin,
        onPointerMove: _move,
        onPointerUp: _release,
        onPointerCancel: _release,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Transform.translate(
            offset: _position,
            child: Transform.rotate(
              angle: (_position.dx / 240).clamp(-0.28, 0.28).toDouble(),
              child: Transform.scale(
                scale: _dragging ? 1.06 : 1,
                child: ClipRect(
                  child: Transform.scale(
                    scale: 3,
                    child: Image.asset(
                      'assets/imported/textures/book_and_quil.png',
                      width: 64,
                      height: 64,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (_, __, ___) => Transform.scale(
                        scale: 1 / 3,
                        child: const Icon(
                          Icons.menu_book,
                          size: 52,
                          color: BookAndQuillColors.parchment,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerHeadIcon extends StatelessWidget {
  const _PlayerHeadIcon();

  static const List<String> _paths = <String>[
    'assets/imported/textures/shantia.png',
    'assets/imported/shantia.png',
    'assets/shantia.png',
  ];

  Widget _assetAt(int index) {
    if (index >= _paths.length) {
      return const Icon(
        Icons.person,
        size: 14,
        color: BookAndQuillColors.gold,
      );
    }
    return Image.asset(
      _paths[index],
      width: 16,
      height: 16,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.none,
      errorBuilder: (_, __, ___) => _assetAt(index + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 16, height: 16, child: _assetAt(0));
  }
}

class _PendingBookDrag {
  const _PendingBookDrag({
    required this.pointer,
    required this.sourceSlot,
    required this.startPosition,
  });

  final int pointer;
  final int sourceSlot;
  final Offset startPosition;
}

class _ShelfDragEdgeHint extends StatelessWidget {
  const _ShelfDragEdgeHint({
    required this.direction,
    required this.enabled,
    required this.active,
    this.createsShelf = false,
  });

  final int direction;
  final bool enabled;
  final bool active;
  final bool createsShelf;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: active ? 112 : 82,
        color: !enabled
            ? const Color(0x16000000)
            : active
                ? BookAndQuillColors.gold.withValues(alpha: 0.25)
                : const Color(0x520B0907),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: enabled ? 1 : 0.2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                direction < 0 ? '<' : '>',
                style: TextStyle(
                  color: active ? BookAndQuillColors.gold : Colors.white,
                  fontSize: active ? 46 : 38,
                  shadows: const <Shadow>[
                    Shadow(color: Colors.black, offset: Offset(3, 3)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                active
                    ? 'KEEP HOLDING'
                    : createsShelf
                        ? 'NEW\nSHELF'
                    : direction < 0
                        ? 'PREVIOUS\nSHELF'
                        : 'NEXT\nSHELF',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  height: 1.25,
                  shadows: <Shadow>[
                    Shadow(color: Colors.black, offset: Offset(2, 2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhysicsBookDragFeedback extends StatefulWidget {
  const _PhysicsBookDragFeedback({
    required this.target,
    required this.settling,
    super.key,
  });

  final ValueListenable<Offset> target;
  final bool settling;

  @override
  State<_PhysicsBookDragFeedback> createState() =>
      _PhysicsBookDragFeedbackState();
}

class _PhysicsBookDragFeedbackState
    extends State<_PhysicsBookDragFeedback>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late Offset _target;
  late Offset _position;
  Offset _velocity = Offset.zero;
  Duration? _lastElapsed;
  double _age = 0;

  @override
  void initState() {
    super.initState();
    _target = widget.target.value;
    _position = _target;
    widget.target.addListener(_targetChanged);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(covariant _PhysicsBookDragFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      oldWidget.target.removeListener(_targetChanged);
      _target = widget.target.value;
      widget.target.addListener(_targetChanged);
    }
  }

  void _targetChanged() {
    _target = widget.target.value;
  }

  void _tick(Duration elapsed) {
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous == null) {
      return;
    }
    final rawDelta = (elapsed - previous).inMicroseconds / 1000000;
    final delta = rawDelta.clamp(0.001, 0.033).toDouble();
    final displacement = _target - _position;
    const springStrength = 92.0;
    const damping = 11.5;
    _velocity += displacement * springStrength * delta;
    final drag = (1 - damping * delta).clamp(0.0, 1.0).toDouble();
    _velocity *= drag;
    _position += _velocity * delta;
    _age += delta;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.target.removeListener(_targetChanged);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const feedbackSize = 96.0;
    final grabProgress = (_age / 0.22).clamp(0.0, 1.0).toDouble();
    final grabScale =
        0.72 + Curves.easeOutBack.transform(grabProgress) * 0.38;
    final velocityTilt =
        (_velocity.dx / 1050).clamp(-0.22, 0.22).toDouble();
    final idleTilt = math.sin(_age * 7) * 0.014;
    final bob = math.sin(_age * 11) * 1.8;

    Widget bookImage({Color? color}) {
      return Image.asset(
        'assets/imported/textures/book_item.png',
        width: 76,
        height: 76,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        color: color,
        colorBlendMode: color == null ? null : BlendMode.srcIn,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/imported/textures/book_and_quil.png',
          width: 76,
          height: 76,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          color: color,
          colorBlendMode: color == null ? null : BlendMode.srcIn,
          errorBuilder: (_, __, ___) => Icon(
            Icons.menu_book,
            size: 68,
            color: color ?? BookAndQuillColors.parchment,
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: _position.dx - feedbackSize / 2,
            top: _position.dy - feedbackSize / 2 + bob,
            width: feedbackSize,
            height: feedbackSize,
            child: Transform.scale(
              scale: grabScale,
              child: AnimatedScale(
                scale: widget.settling ? 0.52 : 1,
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeInBack,
                child: Transform.rotate(
                  angle: velocityTilt + idleTilt,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Transform.translate(
                        offset: Offset(
                          7 + velocityTilt.abs() * 10,
                          10 + velocityTilt.abs() * 5,
                        ),
                        child: Opacity(
                          opacity: 0.48,
                          child: bookImage(color: Colors.black),
                        ),
                      ),
                      bookImage(),
                    ],
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

class _BookCustomizationDialog extends StatefulWidget {
  const _BookCustomizationDialog({
    required this.book,
    required this.sounds,
  });

  final BookRecord book;
  final GameSoundService sounds;

  @override
  State<_BookCustomizationDialog> createState() =>
      _BookCustomizationDialogState();
}

class _BookCustomizationDialogState
    extends State<_BookCustomizationDialog> {
  final math.Random _random = math.Random();
  late int _visualVariant;
  late int _presetIndex;
  late int _customColorValue;
  late bool _customControlsOpen;
  late final TextEditingController _hexController;

  Color? get _previewColor {
    if (_presetIndex == BookRecord.originalCoverPreset) {
      return null;
    }
    return _presetIndex == BookRecord.customCoverPreset
        ? Color(_customColorValue)
        : BookAppearancePalette.resolvePreset(
            _presetIndex,
            _visualVariant,
          );
  }

  int get _red => (_customColorValue >> 16) & 0xFF;
  int get _green => (_customColorValue >> 8) & 0xFF;
  int get _blue => _customColorValue & 0xFF;
  String get _hexColor =>
      (_customColorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  @override
  void initState() {
    super.initState();
    _visualVariant = widget.book.visualVariant
        .clamp(0, BookRecord.visualVariantCount - 1)
        .toInt();
    _presetIndex = widget.book.coverPresetIndex >=
                BookRecord.originalCoverPreset &&
            widget.book.coverPresetIndex < BookRecord.coverPresetCount
        ? widget.book.coverPresetIndex
        : 0;
    _customColorValue =
        0xFF000000 | (widget.book.customCoverColorValue & 0xFFFFFF);
    _customControlsOpen =
        _presetIndex == BookRecord.customCoverPreset;
    _hexController = TextEditingController(text: _hexColor);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _selectPreset(int index) {
    final appliedColor =
        BookAppearancePalette.resolvePreset(index, _visualVariant);
    setState(() {
      _presetIndex = index;
      if (_customControlsOpen) {
        _syncCustomColor(appliedColor);
      }
    });
    widget.sounds.play(GameSound.click);
  }

  void _selectCustom() {
    final appliedColor = _presetIndex >= 0 &&
            _presetIndex < BookRecord.coverPresetCount
        ? BookAppearancePalette.resolvePreset(_presetIndex, _visualVariant)
        : null;
    setState(() {
      _customControlsOpen = true;
      if (appliedColor != null) {
        _syncCustomColor(appliedColor);
      }
      _presetIndex = BookRecord.customCoverPreset;
    });
    widget.sounds.play(GameSound.click);
  }

  void _selectOriginal() {
    setState(() => _presetIndex = BookRecord.originalCoverPreset);
    widget.sounds.play(GameSound.click);
  }

  void _changeVisualVariant(int delta) {
    setState(() {
      _visualVariant =
          (_visualVariant + delta) % BookRecord.visualVariantCount;
      if (_customControlsOpen &&
          _presetIndex >= 0 &&
          _presetIndex < BookRecord.coverPresetCount) {
        _syncCustomColor(
          BookAppearancePalette.resolvePreset(_presetIndex, _visualVariant),
        );
      }
    });
    widget.sounds.play(GameSound.pageTurn);
  }

  void _randomize() {
    var nextVariant = _random.nextInt(BookRecord.visualVariantCount);
    var nextPreset = _random.nextInt(BookRecord.coverPresetCount);
    if (nextVariant == _visualVariant && nextPreset == _presetIndex) {
      nextPreset = (nextPreset + 1) % BookRecord.coverPresetCount;
    }
    setState(() {
      _visualVariant = nextVariant;
      _presetIndex = nextPreset;
      if (_customControlsOpen) {
        _syncCustomColor(
          BookAppearancePalette.resolvePreset(nextPreset, nextVariant),
        );
      }
    });
  }

  void _syncCustomColor(Color color) {
    _customColorValue = color.toARGB32();
    _hexController.value = TextEditingValue(
      text: _hexColor,
      selection: const TextSelection.collapsed(offset: 6),
    );
  }

  void _setRgb({int? red, int? green, int? blue}) {
    final nextRed = red ?? _red;
    final nextGreen = green ?? _green;
    final nextBlue = blue ?? _blue;
    setState(() {
      _customColorValue = 0xFF000000 |
          ((nextRed & 0xFF) << 16) |
          ((nextGreen & 0xFF) << 8) |
          (nextBlue & 0xFF);
      _presetIndex = BookRecord.customCoverPreset;
      _customControlsOpen = true;
      _hexController.value = TextEditingValue(
        text: _hexColor,
        selection: const TextSelection.collapsed(offset: 6),
      );
    });
  }

  void _setHex(String value) {
    if (value.length != 6) {
      return;
    }
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) {
      return;
    }
    setState(() {
      _customColorValue = 0xFF000000 | parsed;
      _presetIndex = BookRecord.customCoverPreset;
      _customControlsOpen = true;
    });
  }

  void _save() {
    Navigator.of(context).pop(
      widget.book.copyWith(
        visualVariant: _visualVariant,
        coverPresetIndex: _presetIndex,
        customCoverColorValue: _customColorValue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedName = _presetIndex == BookRecord.originalCoverPreset
        ? 'ORIGINAL'
        : _presetIndex == BookRecord.customCoverPreset
            ? 'CUSTOM RGB'
            : BookAppearancePalette.presetName(_presetIndex).toUpperCase();
    return AlertDialog(
      backgroundColor: BookAndQuillColors.woodDark,
      title: const Center(child: Text('Customize Book')),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: BookAppearancePreview(
                  visualVariant: _visualVariant,
                  coverColor: _previewColor,
                  width: 96,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Previous book design',
                    onPressed: () => _changeVisualVariant(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Flexible(
                    child: Text(
                      'BOOK DESIGN ${_visualVariant + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: BookAndQuillColors.gold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next book design',
                    onPressed: () => _changeVisualVariant(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: PixelButton(
                  label: 'RANDOMIZE',
                  width: 150,
                  compact: true,
                  sounds: widget.sounds,
                  onPressed: _randomize,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'MINECRAFT COLORS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final index
                        in BookAppearancePalette.presetDisplayOrder)
                      Tooltip(
                        message: BookAppearancePalette.presetName(index),
                        child: Semantics(
                          button: true,
                          label:
                              '${BookAppearancePalette.presetName(index)} book color',
                          selected: _presetIndex == index,
                          child: InkWell(
                            onTap: () => _selectPreset(index),
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: BookAppearancePalette.rawPresetColor(
                                  index,
                                ),
                                border: Border.all(
                                  color: _presetIndex == index
                                      ? BookAndQuillColors.gold
                                      : const Color(0xFF17100C),
                                  width: _presetIndex == index ? 4 : 2,
                                ),
                              ),
                              child: _presetIndex == index
                                  ? Icon(
                                      Icons.check,
                                      color: index == 0 || index == 8
                                          ? Colors.black
                                          : Colors.white,
                                      shadows: const <Shadow>[
                                        Shadow(
                                          color: Colors.black,
                                          offset: Offset(1, 1),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'SELECTED: $selectedName',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFD7D7D7)),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: _selectOriginal,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: _presetIndex == BookRecord.originalCoverPreset
                            ? BookAndQuillColors.gold
                            : const Color(0xFF8A8A8A),
                        width:
                            _presetIndex == BookRecord.originalCoverPreset
                                ? 3
                                : 1,
                      ),
                    ),
                    child: const Text('ORIGINAL'),
                  ),
                  OutlinedButton(
                    onPressed: _selectCustom,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: _customControlsOpen
                            ? BookAndQuillColors.gold
                            : const Color(0xFF8A8A8A),
                        width: _customControlsOpen
                            ? 3
                            : 1,
                      ),
                    ),
                    child: const Text('CUSTOM RGB'),
                  ),
                ],
              ),
              if (_customControlsOpen) ...<Widget>[
                const SizedBox(height: 12),
                _RgbBookSlider(
                  label: 'R',
                  value: _red,
                  color: const Color(0xFFE04B43),
                  onChanged: (value) => _setRgb(red: value),
                  sounds: widget.sounds,
                  sliderId: 'book-rgb-red',
                ),
                _RgbBookSlider(
                  label: 'G',
                  value: _green,
                  color: const Color(0xFF55C96A),
                  onChanged: (value) => _setRgb(green: value),
                  sounds: widget.sounds,
                  sliderId: 'book-rgb-green',
                ),
                _RgbBookSlider(
                  label: 'B',
                  value: _blue,
                  color: const Color(0xFF4E83E8),
                  onChanged: (value) => _setRgb(blue: value),
                  sounds: widget.sounds,
                  sliderId: 'book-rgb-blue',
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text('HEX  #'),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 118,
                      child: TextField(
                        controller: _hexController,
                        maxLength: 6,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-F]'),
                          ),
                        ],
                        onChanged: _setHex,
                        decoration: const InputDecoration(
                          counterText: '',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        PixelButton(
          label: 'SAVE',
          width: 120,
          compact: true,
          sounds: widget.sounds,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _RgbBookSlider extends StatelessWidget {
  const _RgbBookSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
    required this.sounds,
    required this.sliderId,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;
  final GameSoundService sounds;
  final String sliderId;

  void _change(int next) {
    final clamped = next.clamp(0, 255).toInt();
    if (clamped == value) {
      return;
    }
    onChanged(clamped);
    sounds.playSliderTick(sliderId, clamped / 255);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 46,
          child: Text(
            '$label  $value',
            style: TextStyle(color: color),
          ),
        ),
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent) {
                return;
              }
              final direction = event.scrollDelta.dy > 0 ? -1 : 1;
              _change(value + direction);
            },
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                inactiveTrackColor: const Color(0xFF3C3C3C),
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.16),
                trackHeight: 7,
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                label: '$value',
                onChanged: (next) => _change(next.round()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
