import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/book_record.dart';
import '../models/usage_stats.dart';
import '../services/book_storage.dart';
import '../services/android_platform.dart';
import '../services/game_sound_service.dart';
import '../theme/app_background.dart';
import '../theme/book_and_quill_theme.dart';
import '../widgets/gear_button.dart';
import '../widgets/pixel_button.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({
    required this.slots,
    required this.usage,
    required this.sounds,
    required this.onResetStats,
    this.backgroundId = 'stone_bricks',
    this.backgroundOpacity = AppSettings.defaultBackgroundOpacity,
    super.key,
  });

  final List<BookRecord?> slots;
  final UsageStats usage;
  final GameSoundService sounds;
  final Future<void> Function() onResetStats;
  final String backgroundId;
  final double backgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final totals = _LibraryTotals.fromSlots(slots);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: AppBackground(
                  backgroundId: backgroundId,
                  opacity: backgroundOpacity,
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: <Widget>[
                      if (AndroidPlatform.isAndroid)
                        Row(children: <Widget>[
                          IconButton(tooltip: 'Back',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back)),
                          const Expanded(child: Text('STATISTICS',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 20))),
                          const SizedBox(width: 48),
                        ])
                      else SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            Positioned(
                              left: 0,
                              child: PixelButton(
                                label: 'BACK',
                                width: 104,
                                compact: true,
                                sounds: sounds,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                            const Text(
                              'STATISTICS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                letterSpacing: 2,
                                shadows: <Shadow>[
                                  Shadow(
                                    color: Colors.black,
                                    offset: Offset(3, 3),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              right: 0,
                              child: GearButton(
                                sounds: sounds,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_number(totals.books)} BOOKS ACROSS '
                        '${_number(totals.shelves)} SHELVES',
                        style: const TextStyle(
                          color: BookAndQuillColors.gold,
                          fontSize: 15,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1120),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  const _SectionTitle('YOUR LIBRARY'),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: <Widget>[
                                      _StatCard(
                                        label: 'BOOKS',
                                        value: _number(totals.books),
                                        detail: '${totals.emptySlots} empty slots',
                                      ),
                                      _StatCard(
                                        label: 'SHELVES',
                                        value: _number(totals.shelves),
                                        detail: '${totals.totalSlots} total slots',
                                      ),
                                      _StatCard(
                                        label: 'WRITTEN PAGES',
                                        value: _number(totals.writtenPages),
                                        detail: '${totals.totalPages} pages total',
                                      ),
                                      _StatCard(
                                        label: 'CURRENT CHARACTERS',
                                        value: _number(totals.characters),
                                        detail: 'Saved across every book',
                                      ),
                                      _StatCard(
                                        label: 'WORDS',
                                        value: _number(totals.words),
                                        detail: 'Current saved word count',
                                      ),
                                      _StatCard(
                                        label: 'FAVOURITES',
                                        value: _number(totals.favourites),
                                        detail: 'Enchanted books',
                                      ),
                                      _StatCard(
                                        label: 'SIGNED BOOKS',
                                        value: _number(totals.signedBooks),
                                        detail: 'Read-only books',
                                      ),
                                      _StatCard(
                                        label: 'AVG. PAGES / BOOK',
                                        value: totals.averagePages,
                                        detail: 'Including blank pages',
                                      ),
                                    ],
                                  ),
                                  if (totals.longestBook != null) ...<Widget>[
                                    const SizedBox(height: 16),
                                    _HighlightCard(
                                      title: 'MOST WRITTEN BOOK',
                                      value: totals.longestBook!.title,
                                      detail:
                                          '${_number(totals.longestBookCharacters)} characters',
                                    ),
                                  ],
                                  const SizedBox(height: 26),
                                  const _SectionTitle('ALL-TIME ACTIVITY'),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: <Widget>[
                                      _StatCard(
                                        label: 'LETTERS TYPED',
                                        value: _number(usage.lettersTyped),
                                        detail: 'Includes pasted text',
                                      ),
                                      _StatCard(
                                        label: 'LETTERS DELETED',
                                        value: _number(usage.lettersDeleted),
                                        detail: 'Includes replaced text',
                                      ),
                                      _StatCard(
                                        label: 'PAGE TURNS',
                                        value: _number(usage.pageTurns),
                                        detail: 'Buttons, keys, and jumps',
                                      ),
                                      _StatCard(
                                        label: 'BOOKS OPENED',
                                        value: _number(usage.booksOpened),
                                        detail: 'New and existing books',
                                      ),
                                      _StatCard(
                                        label: 'BOOKS CREATED',
                                        value: _number(usage.booksCreated),
                                        detail: 'New empty books',
                                      ),
                                      _StatCard(
                                        label: 'BOOKS DELETED',
                                        value: _number(usage.booksDeleted),
                                        detail: 'Removed shelf books',
                                      ),
                                      _StatCard(
                                        label: 'PAGES INSERTED',
                                        value: _number(usage.pagesInserted),
                                        detail: 'Using Insert',
                                      ),
                                      _StatCard(
                                        label: 'PAGES DELETED',
                                        value: _number(usage.pagesDeleted),
                                        detail: 'Using Delete',
                                      ),
                                      _StatCard(
                                        label: 'BOOKS IMPORTED',
                                        value: _number(usage.booksImported),
                                        detail: 'Imported files',
                                      ),
                                      _StatCard(
                                        label: 'BOOKS EXPORTED',
                                        value: _number(usage.booksExported),
                                        detail: 'Successful exports',
                                      ),
                                      _StatCard(
                                        label: 'BOOKS DUPLICATED',
                                        value: _number(usage.booksDuplicated),
                                        detail: 'Shelf copies',
                                      ),
                                      _StatCard(
                                        label: 'APP LAUNCHES',
                                        value: _number(usage.appLaunches),
                                        detail: 'Times Book and Quill opened',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Center(
                                    child: PixelButton(
                                      label: 'TYPING HEATMAP',
                                      width: 210,
                                      compact: true,
                                      sounds: sounds,
                                      onPressed: () =>
                                          _showTypingHeatmap(context),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'See which keyboard keys you use most',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFAAA49A),
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Center(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFFFF5555),
                                        side: const BorderSide(
                                          color: Color(0xFFAA2E2E),
                                          width: 2,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 26,
                                          vertical: 14,
                                        ),
                                      ),
                                      onPressed: () {
                                        sounds.play(GameSound.click);
                                        _confirmResetStats(context);
                                      },
                                      child: const Text(
                                        'RESET STATS',
                                        style: TextStyle(
                                          color: Color(0xFFFF5555),
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Made by SHANTIASHAMS',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: BookAndQuillColors.gold,
                                      fontSize: 11,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmResetStats(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: BookAndQuillColors.woodDark,
            title: const Text('Reset all statistics?'),
            content: const Text(
              'This resets writing activity and the typing '
              'heatmap. Your books and shelves will not be changed.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text(
                  'RESET STATS',
                  style: TextStyle(color: Color(0xFFFF5555)),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    await onResetStats();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showTypingHeatmap(BuildContext context) {
    final trackedCharacters = usage.characterCounts.values.fold<int>(
      0,
      (total, count) => total + count,
    );
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 650),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            decoration: BoxDecoration(
              color: const Color(0xF51B130E),
              border: Border.all(color: BookAndQuillColors.gold, width: 3),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Colors.black87, offset: Offset(8, 8)),
              ],
            ),
            child: Column(
              children: <Widget>[
                const Text(
                  'TYPING HEATMAP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    letterSpacing: 2,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black, offset: Offset(3, 3)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_number(trackedCharacters)} tracked keyboard actions',
                  style: const TextStyle(
                    color: BookAndQuillColors.gold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Written characters remain counted after deletion. Backspace '
                  'counts only when it deletes text; Tab, Caps Lock, and '
                  'Shift-assisted uppercase writing are also tracked.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFB4AEA4),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _TypingKeyboard(
                    characterCounts: usage.characterCounts,
                  ),
                ),
                const SizedBox(height: 12),
                const _TypingLegend(),
                const SizedBox(height: 16),
                PixelButton(
                  label: 'CLOSE',
                  width: 130,
                  compact: true,
                  sounds: sounds,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _number(int value) {
    final digits = value.toString();
    final result = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        result.write(',');
      }
      result.write(digits[index]);
    }
    return result.toString();
  }

}

class _KeyboardKeySpec {
  const _KeyboardKeySpec(
    this.label, {
    this.countKey,
    this.width = 1,
  });

  final String label;
  final String? countKey;
  final double width;
}

const List<List<_KeyboardKeySpec>> _keyboardRows =
    <List<_KeyboardKeySpec>>[
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('`', countKey: '`'),
    _KeyboardKeySpec('1', countKey: '1'),
    _KeyboardKeySpec('2', countKey: '2'),
    _KeyboardKeySpec('3', countKey: '3'),
    _KeyboardKeySpec('4', countKey: '4'),
    _KeyboardKeySpec('5', countKey: '5'),
    _KeyboardKeySpec('6', countKey: '6'),
    _KeyboardKeySpec('7', countKey: '7'),
    _KeyboardKeySpec('8', countKey: '8'),
    _KeyboardKeySpec('9', countKey: '9'),
    _KeyboardKeySpec('0', countKey: '0'),
    _KeyboardKeySpec('-', countKey: '-'),
    _KeyboardKeySpec('=', countKey: '='),
    _KeyboardKeySpec('BACKSPACE', countKey: 'BACKSPACE', width: 2),
  ],
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('TAB', countKey: 'TAB', width: 1.5),
    _KeyboardKeySpec('Q', countKey: 'Q'),
    _KeyboardKeySpec('W', countKey: 'W'),
    _KeyboardKeySpec('E', countKey: 'E'),
    _KeyboardKeySpec('R', countKey: 'R'),
    _KeyboardKeySpec('T', countKey: 'T'),
    _KeyboardKeySpec('Y', countKey: 'Y'),
    _KeyboardKeySpec('U', countKey: 'U'),
    _KeyboardKeySpec('I', countKey: 'I'),
    _KeyboardKeySpec('O', countKey: 'O'),
    _KeyboardKeySpec('P', countKey: 'P'),
    _KeyboardKeySpec('[', countKey: '['),
    _KeyboardKeySpec(']', countKey: ']'),
    _KeyboardKeySpec('\\', countKey: '\\', width: 1.5),
  ],
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('CAPS', countKey: 'CAPS', width: 1.8),
    _KeyboardKeySpec('A', countKey: 'A'),
    _KeyboardKeySpec('S', countKey: 'S'),
    _KeyboardKeySpec('D', countKey: 'D'),
    _KeyboardKeySpec('F', countKey: 'F'),
    _KeyboardKeySpec('G', countKey: 'G'),
    _KeyboardKeySpec('H', countKey: 'H'),
    _KeyboardKeySpec('J', countKey: 'J'),
    _KeyboardKeySpec('K', countKey: 'K'),
    _KeyboardKeySpec('L', countKey: 'L'),
    _KeyboardKeySpec(';', countKey: ';'),
    _KeyboardKeySpec("'", countKey: "'"),
    _KeyboardKeySpec('ENTER', countKey: 'ENTER', width: 2.2),
  ],
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('SHIFT', countKey: 'SHIFT', width: 2.3),
    _KeyboardKeySpec('Z', countKey: 'Z'),
    _KeyboardKeySpec('X', countKey: 'X'),
    _KeyboardKeySpec('C', countKey: 'C'),
    _KeyboardKeySpec('V', countKey: 'V'),
    _KeyboardKeySpec('B', countKey: 'B'),
    _KeyboardKeySpec('N', countKey: 'N'),
    _KeyboardKeySpec('M', countKey: 'M'),
    _KeyboardKeySpec(',', countKey: ','),
    _KeyboardKeySpec('.', countKey: '.'),
    _KeyboardKeySpec('/', countKey: '/'),
    _KeyboardKeySpec('SHIFT', countKey: 'SHIFT', width: 2.7),
  ],
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('SPACE', countKey: 'SPACE', width: 7),
  ],
];

class _TypingKeyboard extends StatelessWidget {
  const _TypingKeyboard({required this.characterCounts});

  final Map<String, int> characterCounts;

  @override
  Widget build(BuildContext context) {
    var maximumCount = 0;
    for (final count in characterCounts.values) {
      if (count > maximumCount) {
        maximumCount = count;
      }
    }

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 970,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var rowIndex = 0;
                  rowIndex < _keyboardRows.length;
                  rowIndex++) ...<Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (var keyIndex = 0;
                        keyIndex < _keyboardRows[rowIndex].length;
                        keyIndex++) ...<Widget>[
                      if (keyIndex > 0) const SizedBox(width: 6),
                      _TypingKey(
                        spec: _keyboardRows[rowIndex][keyIndex],
                        count: _keyboardRows[rowIndex][keyIndex].countKey ==
                                null
                            ? 0
                            : characterCounts[
                                    _keyboardRows[rowIndex][keyIndex]
                                        .countKey] ??
                                0,
                        maximumCount: maximumCount,
                      ),
                    ],
                  ],
                ),
                if (rowIndex < _keyboardRows.length - 1)
                  const SizedBox(height: 7),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingKey extends StatelessWidget {
  const _TypingKey({
    required this.spec,
    required this.count,
    required this.maximumCount,
  });

  final _KeyboardKeySpec spec;
  final int count;
  final int maximumCount;

  @override
  Widget build(BuildContext context) {
    final tracked = spec.countKey != null;
    final intensity = !tracked || maximumCount == 0
        ? 0.0
        : math.log(count + 1) / math.log(maximumCount + 1);
    final color = tracked
        ? Color.lerp(
            const Color(0xFF284E91),
            const Color(0xFFD64545),
            intensity,
          )!
        : const Color(0xFF45413D);
    final pressKey = const <String>{
      'BACKSPACE',
      'CAPS',
      'SHIFT',
      'TAB',
    }.contains(spec.countKey);
    final tooltip = tracked
        ? '${spec.label}: ${StatsScreen._number(count)} '
            '${pressKey ? (count == 1 ? 'press' : 'presses') : (count == 1 ? 'time typed' : 'times typed')}'
        : '${spec.label} does not write a character and is not counted';

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 250),
      child: Container(
        width: 54 * spec.width,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          border: const Border(
            left: BorderSide(color: Color(0xFFB4B4B4), width: 2),
            top: BorderSide(color: Color(0xFFB4B4B4), width: 2),
            right: BorderSide(color: Color(0xFF171717), width: 2),
            bottom: BorderSide(color: Color(0xFF171717), width: 2),
          ),
          boxShadow: count == 0
              ? null
              : <BoxShadow>[
                  BoxShadow(
                    color: color.withOpacity(0.45),
                    blurRadius: 6,
                  ),
                ],
        ),
        child: Text(
          spec.label,
          style: TextStyle(
            color: Colors.white,
            fontSize: spec.label.length > 2 ? 9 : 16,
            shadows: const <Shadow>[
              Shadow(color: Colors.black, offset: Offset(2, 2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingLegend extends StatelessWidget {
  const _TypingLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'LOW',
          style: TextStyle(color: Color(0xFFAAA49A), fontSize: 10),
        ),
        const SizedBox(width: 8),
        Container(
          width: 170,
          height: 12,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[
                Color(0xFF284E91),
                Color(0xFF8A4969),
                Color(0xFFD64545),
              ],
            ),
            border: Border.all(color: const Color(0xFF171717)),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'HIGH',
          style: TextStyle(color: Color(0xFFAAA49A), fontSize: 10),
        ),
      ],
    );
  }
}

class _LibraryTotals {
  const _LibraryTotals({
    required this.books,
    required this.shelves,
    required this.totalSlots,
    required this.emptySlots,
    required this.totalPages,
    required this.writtenPages,
    required this.characters,
    required this.words,
    required this.favourites,
    required this.signedBooks,
    required this.averagePages,
    required this.longestBook,
    required this.longestBookCharacters,
  });

  final int books;
  final int shelves;
  final int totalSlots;
  final int emptySlots;
  final int totalPages;
  final int writtenPages;
  final int characters;
  final int words;
  final int favourites;
  final int signedBooks;
  final String averagePages;
  final BookRecord? longestBook;
  final int longestBookCharacters;

  factory _LibraryTotals.fromSlots(List<BookRecord?> slots) {
    final books = slots.whereType<BookRecord>().toList(growable: false);
    var totalPages = 0;
    var writtenPages = 0;
    var characters = 0;
    var words = 0;
    var favourites = 0;
    var signedBooks = 0;
    BookRecord? longestBook;
    var longestBookCharacters = 0;

    for (final book in books) {
      totalPages += book.pages.length;
      if (book.favorite) {
        favourites++;
      }
      if (book.signed) {
        signedBooks++;
      }
      var bookCharacters = 0;
      for (final page in book.pages) {
        final text = page.text;
        final pageCharacters = text.runes.length;
        bookCharacters += pageCharacters;
        characters += pageCharacters;
        if (text.trim().isNotEmpty) {
          writtenPages++;
          words += RegExp(r'\S+').allMatches(text).length;
        }
      }
      if (longestBook == null || bookCharacters > longestBookCharacters) {
        longestBook = book;
        longestBookCharacters = bookCharacters;
      }
    }

    final shelves = slots.isEmpty
        ? 1
        : (slots.length + BookStorage.shelfSize - 1) ~/ BookStorage.shelfSize;
    final totalSlots = shelves * BookStorage.shelfSize;
    return _LibraryTotals(
      books: books.length,
      shelves: shelves,
      totalSlots: totalSlots,
      emptySlots: totalSlots - books.length,
      totalPages: totalPages,
      writtenPages: writtenPages,
      characters: characters,
      words: words,
      favourites: favourites,
      signedBooks: signedBooks,
      averagePages:
          books.isEmpty ? '0.0' : (totalPages / books.length).toStringAsFixed(1),
      longestBook: longestBook,
      longestBookCharacters: longestBookCharacters,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 17,
        letterSpacing: 1.5,
        shadows: <Shadow>[
          Shadow(color: Colors.black, offset: Offset(2, 2)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 252,
      height: 105,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xE8241A13),
        border: const Border(
          left: BorderSide(color: Color(0xFF9A9A9A), width: 2),
          top: BorderSide(color: Color(0xFF9A9A9A), width: 2),
          right: BorderSide(color: Color(0xFF171717), width: 2),
          bottom: BorderSide(color: Color(0xFF171717), width: 2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BookAndQuillColors.gold,
              fontSize: 24,
              shadows: <Shadow>[
                Shadow(color: Colors.black, offset: Offset(2, 2)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF9D978D), fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.title,
    required this.value,
    required this.detail,
  });

  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xE82F2417),
        border: Border.all(color: BookAndQuillColors.gold, width: 2),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.auto_stories,
            color: BookAndQuillColors.gold,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(color: Color(0xFFAAA49A), fontSize: 10),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 17),
                ),
              ],
            ),
          ),
          Text(
            detail,
            style: const TextStyle(color: BookAndQuillColors.gold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
