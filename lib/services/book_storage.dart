import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/book_record.dart';
import '../models/usage_stats.dart';
import 'android_platform.dart';

class BookStorage {
  static Future<BookStorage> open() async => AndroidPlatform.isAndroid
      ? BookStorage(dataDirectory: await AndroidPlatform.dataDirectory())
      : BookStorage();

  BookStorage({Directory? dataDirectory})
      : _dataDirectory = dataDirectory ?? _defaultDataDirectory(),
        _legacyDataDirectory =
            dataDirectory == null ? _defaultLegacyDataDirectory() : null;

  static const int shelfSize = 6;
  static const int slotCount = shelfSize;
  final Directory _dataDirectory;
  final Directory? _legacyDataDirectory;
  Future<void> _writeQueue = Future<void>.value();
  Future<void> _settingsWriteQueue = Future<void>.value();
  Future<void> _statsWriteQueue = Future<void>.value();
  Future<void> _shelfNamesWriteQueue = Future<void>.value();

  File get _libraryFile => File('${_dataDirectory.path}${Platform.pathSeparator}library.json');
  File get _backupFile => File('${_dataDirectory.path}${Platform.pathSeparator}library.backup.json');
  File get _settingsFile => File(
        '${_dataDirectory.path}${Platform.pathSeparator}settings.json',
      );
  File get _statsFile => File(
        '${_dataDirectory.path}${Platform.pathSeparator}stats.json',
      );
  File get _shelfNamesFile => File(
        '${_dataDirectory.path}${Platform.pathSeparator}shelves.json',
      );

  static Directory _defaultDataDirectory() {
    if (Platform.isWindows) {
      final root = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          Directory.current.path;
      return Directory('$root${Platform.pathSeparator}Book and Quill');
    }

    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return Directory('$home${Platform.pathSeparator}.book-and-quill');
  }

  static Directory _defaultLegacyDataDirectory() {
    if (Platform.isWindows) {
      final root = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          Directory.current.path;
      return Directory('$root${Platform.pathSeparator}Quillcraft');
    }

    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return Directory('$home${Platform.pathSeparator}.quillcraft');
  }

  Future<List<BookRecord?>> loadSlots() async {
    await _migrateLegacyLibraryIfNeeded();
    if (!await _libraryFile.exists()) {
      return List<BookRecord?>.filled(shelfSize, null);
    }

    try {
      final decoded = jsonDecode(await _libraryFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return List<BookRecord?>.filled(shelfSize, null);
      }
      final books = decoded['books'];
      if (books is! List) {
        return List<BookRecord?>.filled(shelfSize, null);
      }
      final restored = <BookRecord>[];
      for (final dynamic item in books) {
        if (item is! Map) {
          continue;
        }
        final book = BookRecord.fromJson(Map<String, dynamic>.from(item));
        if (book.slot >= 0) {
          restored.add(book);
        }
      }
      final storedCapacity = (decoded['slotCapacity'] as num?)?.toInt() ?? shelfSize;
      return _booksToSlots(restored, minimumCapacity: storedCapacity);
    } on Object {
      return _loadBackupOrEmpty();
    }
  }

  Future<AppSettings> loadSettings() async {
    if (!await _settingsFile.exists()) {
      return AppSettings.defaults;
    }
    try {
      final decoded = jsonDecode(await _settingsFile.readAsString());
      if (decoded is Map<String, dynamic>) {
        return AppSettings.fromJson(decoded);
      }
    } on Object {
      // A damaged preferences file must not prevent the library from opening.
    }
    return AppSettings.defaults;
  }

  Future<List<String>> loadShelfNames() async {
    if (!await _shelfNamesFile.exists()) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(await _shelfNamesFile.readAsString());
      final rawNames = decoded is Map ? decoded['names'] : decoded;
      if (rawNames is List) {
        return <String>[
          for (var index = 0; index < rawNames.length; index++)
            rawNames[index].toString().trim().isEmpty
                ? 'Shelf ${index + 1}'
                : rawNames[index].toString().trim(),
        ];
      }
    } on Object {
      // Shelf labels are optional and must not prevent the library from loading.
    }
    return const <String>[];
  }

  Future<UsageStats> loadUsageStats() async {
    if (!await _statsFile.exists()) {
      return UsageStats.empty;
    }
    try {
      final decoded = jsonDecode(await _statsFile.readAsString());
      if (decoded is Map<String, dynamic>) {
        return UsageStats.fromJson(decoded);
      }
    } on Object {
      // Statistics are non-critical and must never block the library.
    }
    return UsageStats.empty;
  }

  Future<void> _migrateLegacyLibraryIfNeeded() async {
    final legacyDirectory = _legacyDataDirectory;
    if (legacyDirectory == null || await _libraryFile.exists()) {
      return;
    }

    final separator = Platform.pathSeparator;
    final legacyLibrary = File('${legacyDirectory.path}${separator}library.json');
    if (!await legacyLibrary.exists()) {
      return;
    }

    await _dataDirectory.create(recursive: true);
    await legacyLibrary.copy(_libraryFile.path);

    final legacyBackup =
        File('${legacyDirectory.path}${separator}library.backup.json');
    if (await legacyBackup.exists() && !await _backupFile.exists()) {
      await legacyBackup.copy(_backupFile.path);
    }
  }

  Future<List<BookRecord?>> _loadBackupOrEmpty() async {
    if (!await _backupFile.exists()) {
      return List<BookRecord?>.filled(shelfSize, null);
    }

    final restored = <BookRecord>[];
    var storedCapacity = shelfSize;
    try {
      final decoded = jsonDecode(await _backupFile.readAsString());
      if (decoded is Map<String, dynamic> && decoded['books'] is List) {
        storedCapacity = (decoded['slotCapacity'] as num?)?.toInt() ?? shelfSize;
        for (final dynamic item in decoded['books'] as List) {
          if (item is Map) {
            final book = BookRecord.fromJson(Map<String, dynamic>.from(item));
            if (book.slot >= 0) {
              restored.add(book);
            }
          }
        }
      }
    } on Object {
      // Both files are unreadable. Returning an empty shelf is safer than
      // overwriting either file during startup.
    }
    return _booksToSlots(restored, minimumCapacity: storedCapacity);
  }

  List<BookRecord?> _booksToSlots(List<BookRecord> books, {int minimumCapacity = shelfSize}) {
    final highestSlot = books.fold<int>(-1, (highest, book) => book.slot > highest ? book.slot : highest);
    final required = highestSlot + 1 > minimumCapacity ? highestSlot + 1 : minimumCapacity;
    final shelfCount = required <= 0 ? 1 : ((required + shelfSize - 1) ~/ shelfSize);
    final slots = List<BookRecord?>.filled(shelfCount * shelfSize, null);
    for (final book in books) {
      if (book.slot < slots.length) {
        slots[book.slot] = book;
      }
    }
    return slots;
  }

  Future<void> saveSlots(List<BookRecord?> slots) async {
    final payload = <String, Object>{
      'formatVersion': 4,
      'savedAt': DateTime.now().toIso8601String(),
      'slotCapacity': slots.length,
      'books': slots.whereType<BookRecord>().map((book) => book.toJson()).toList(),
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);

    _writeQueue = _writeQueue
        .catchError((Object _) {
          // A later save should still be attempted if an earlier disk write failed.
        })
        .then((_) => _writeEncodedLibrary(encoded));
    return _writeQueue;
  }

  Future<void> saveSettings(AppSettings settings) {
    final encoded = const JsonEncoder.withIndent('  ').convert(settings.toJson());
    _settingsWriteQueue = _settingsWriteQueue
        .catchError((Object _) {
          // Keep later preference writes usable after an earlier failure.
        })
        .then((_) => _writeSettings(encoded));
    return _settingsWriteQueue;
  }

  Future<void> saveShelfNames(List<String> names) {
    final payload = <String, Object>{
      'formatVersion': 1,
      'names': List<String>.unmodifiable(names),
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    _shelfNamesWriteQueue = _shelfNamesWriteQueue
        .catchError((Object _) {
          // Keep later shelf-name writes usable after an earlier failure.
        })
        .then((_) => _writeShelfNames(encoded));
    return _shelfNamesWriteQueue;
  }

  Future<void> saveUsageStats(UsageStats stats) {
    final encoded = const JsonEncoder.withIndent('  ').convert(stats.toJson());
    _statsWriteQueue = _statsWriteQueue
        .catchError((Object _) {
          // Keep later statistics writes usable after an earlier failure.
        })
        .then((_) => _writeUsageStats(encoded));
    return _statsWriteQueue;
  }

  Future<void> _writeUsageStats(String encoded) async {
    await _dataDirectory.create(recursive: true);
    final temporary = File('${_statsFile.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    if (await _statsFile.exists()) {
      await _statsFile.delete();
    }
    await temporary.rename(_statsFile.path);
  }

  Future<void> _writeSettings(String encoded) async {
    await _dataDirectory.create(recursive: true);
    final temporary = File('${_settingsFile.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    if (await _settingsFile.exists()) {
      await _settingsFile.delete();
    }
    await temporary.rename(_settingsFile.path);
  }

  Future<void> _writeShelfNames(String encoded) async {
    await _dataDirectory.create(recursive: true);
    final temporary = File('${_shelfNamesFile.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    if (await _shelfNamesFile.exists()) {
      await _shelfNamesFile.delete();
    }
    await temporary.rename(_shelfNamesFile.path);
  }

  Future<void> _writeEncodedLibrary(String encoded) async {
    await _dataDirectory.create(recursive: true);
    final temporary = File('${_libraryFile.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);

    if (await _libraryFile.exists()) {
      await _libraryFile.copy(_backupFile.path);
      await _libraryFile.delete();
    }
    await temporary.rename(_libraryFile.path);
  }
}
