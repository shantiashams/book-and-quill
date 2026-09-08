class UsageStats {
  const UsageStats({
    this.lettersTyped = 0,
    this.lettersDeleted = 0,
    this.booksCreated = 0,
    this.booksOpened = 0,
    this.booksDeleted = 0,
    this.booksImported = 0,
    this.booksExported = 0,
    this.booksDuplicated = 0,
    this.pagesInserted = 0,
    this.pagesDeleted = 0,
    this.pageTurns = 0,
    this.appLaunches = 0,
    this.characterCounts = const <String, int>{},
    this.trackingStartedAt,
    this.lastActivityAt,
  });

  static const UsageStats empty = UsageStats();

  final int lettersTyped;
  final int lettersDeleted;
  final int booksCreated;
  final int booksOpened;
  final int booksDeleted;
  final int booksImported;
  final int booksExported;
  final int booksDuplicated;
  final int pagesInserted;
  final int pagesDeleted;
  final int pageTurns;
  final int appLaunches;
  final Map<String, int> characterCounts;
  final DateTime? trackingStartedAt;
  final DateTime? lastActivityAt;

  UsageStats add({
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
    int appLaunches = 0,
    String typedText = '',
    Map<String, int> keyPresses = const <String, int>{},
  }) {
    final now = DateTime.now();
    final nextCharacterCounts = Map<String, int>.from(characterCounts);
    for (final rune in typedText.runes) {
      final key = keyboardKeyForCharacter(String.fromCharCode(rune));
      if (key != null) {
        nextCharacterCounts[key] = (nextCharacterCounts[key] ?? 0) + 1;
      }
    }
    for (final entry in keyPresses.entries) {
      if (entry.key.isNotEmpty && entry.value > 0) {
        nextCharacterCounts[entry.key] =
            (nextCharacterCounts[entry.key] ?? 0) + entry.value;
      }
    }
    return UsageStats(
      lettersTyped: this.lettersTyped + lettersTyped,
      lettersDeleted: this.lettersDeleted + lettersDeleted,
      booksCreated: this.booksCreated + booksCreated,
      booksOpened: this.booksOpened + booksOpened,
      booksDeleted: this.booksDeleted + booksDeleted,
      booksImported: this.booksImported + booksImported,
      booksExported: this.booksExported + booksExported,
      booksDuplicated: this.booksDuplicated + booksDuplicated,
      pagesInserted: this.pagesInserted + pagesInserted,
      pagesDeleted: this.pagesDeleted + pagesDeleted,
      pageTurns: this.pageTurns + pageTurns,
      appLaunches: this.appLaunches + appLaunches,
      characterCounts: Map<String, int>.unmodifiable(nextCharacterCounts),
      trackingStartedAt: trackingStartedAt ?? now,
      lastActivityAt: now,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'formatVersion': 2,
      'lettersTyped': lettersTyped,
      'lettersDeleted': lettersDeleted,
      'booksCreated': booksCreated,
      'booksOpened': booksOpened,
      'booksDeleted': booksDeleted,
      'booksImported': booksImported,
      'booksExported': booksExported,
      'booksDuplicated': booksDuplicated,
      'pagesInserted': pagesInserted,
      'pagesDeleted': pagesDeleted,
      'pageTurns': pageTurns,
      'appLaunches': appLaunches,
      'characterCounts': characterCounts,
      'trackingStartedAt': trackingStartedAt?.toIso8601String() ?? '',
      'lastActivityAt': lastActivityAt?.toIso8601String() ?? '',
    };
  }

  factory UsageStats.fromJson(Map<String, dynamic> json) {
    int readCount(String key) {
      return ((json[key] as num?)?.toInt() ?? 0).clamp(0, 1 << 62).toInt();
    }

    final restoredCharacterCounts = <String, int>{};
    final rawCharacterCounts = json['characterCounts'];
    if (rawCharacterCounts is Map) {
      for (final entry in rawCharacterCounts.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (key.isNotEmpty && value is num) {
          final count = value.toInt().clamp(0, 1 << 62).toInt();
          if (count > 0) {
            restoredCharacterCounts[key] = count;
          }
        }
      }
    }

    return UsageStats(
      lettersTyped: readCount('lettersTyped'),
      lettersDeleted: readCount('lettersDeleted'),
      booksCreated: readCount('booksCreated'),
      booksOpened: readCount('booksOpened'),
      booksDeleted: readCount('booksDeleted'),
      booksImported: readCount('booksImported'),
      booksExported: readCount('booksExported'),
      booksDuplicated: readCount('booksDuplicated'),
      pagesInserted: readCount('pagesInserted'),
      pagesDeleted: readCount('pagesDeleted'),
      pageTurns: readCount('pageTurns'),
      appLaunches: readCount('appLaunches'),
      characterCounts:
          Map<String, int>.unmodifiable(restoredCharacterCounts),
      trackingStartedAt: DateTime.tryParse(
        json['trackingStartedAt']?.toString() ?? '',
      ),
      lastActivityAt: DateTime.tryParse(
        json['lastActivityAt']?.toString() ?? '',
      ),
    );
  }

  static String? keyboardKeyForCharacter(String character) {
    if (character == ' ') {
      return 'SPACE';
    }
    if (character == '\n' || character == '\r') {
      return 'ENTER';
    }
    if (character.length == 1) {
      final codeUnit = character.codeUnitAt(0);
      if (codeUnit >= 65 && codeUnit <= 90) {
        return character;
      }
      if (codeUnit >= 97 && codeUnit <= 122) {
        return character.toUpperCase();
      }
      if (codeUnit >= 48 && codeUnit <= 57) {
        return character;
      }
    }

    switch (character) {
      case '`':
      case '~':
        return '`';
      case '-':
      case '_':
        return '-';
      case '=':
      case '+':
        return '=';
      case '[':
      case '{':
        return '[';
      case ']':
      case '}':
        return ']';
      case '\\':
      case '|':
        return '\\';
      case ';':
      case ':':
        return ';';
      case "'":
      case '"':
        return "'";
      case ',':
      case '<':
        return ',';
      case '.':
      case '>':
        return '.';
      case '/':
      case '?':
        return '/';
    }
    return null;
  }
}
