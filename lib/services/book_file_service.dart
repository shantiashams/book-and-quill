import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../models/book_record.dart';
import 'android_platform.dart';

class BookFileService {
  static const XTypeGroup _bookFiles = XTypeGroup(
    label: 'Book and Quill books',
    extensions: <String>['qbook', 'json'],
  );

  Future<bool> exportBook(BookRecord book) async {
    final contents = const JsonEncoder.withIndent('  ').convert(
      <String, Object>{
        'format': 'book-and-quill-book',
        'formatVersion': 4,
        'exportedAt': DateTime.now().toIso8601String(),
        'book': book.toJson(),
      },
    );
    if (AndroidPlatform.isAndroid) {
      return AndroidPlatform.exportDocument(
        '${_safeFileName(book.title)}.qbook', contents,
      );
    }
    final location = await getSaveLocation(
      suggestedName: '${_safeFileName(book.title)}.qbook',
      acceptedTypeGroups: const <XTypeGroup>[_bookFiles],
    );
    if (location == null) {
      return false;
    }

    final bytes = Uint8List.fromList(utf8.encode(contents));
    await XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: '${_safeFileName(book.title)}.qbook',
    ).saveTo(location.path);
    return true;
  }

  Future<BookRecord?> importBook({required int slot}) async {
    final String? contents;
    if (AndroidPlatform.isAndroid) {
      contents = await AndroidPlatform.importDocument();
    } else {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[_bookFiles],
      );
      contents = await file?.readAsString();
    }
    if (contents == null) {
      return null;
    }

    final decoded = jsonDecode(contents);
    if (decoded is! Map) {
      throw const FormatException('This is not a Book and Quill book file.');
    }
    final root = Map<String, dynamic>.from(decoded);
    final rawBook = root['book'] ?? root;
    if (rawBook is! Map) {
      throw const FormatException('The selected file does not contain a book.');
    }
    return BookRecord.fromJson(Map<String, dynamic>.from(rawBook)).copyWith(
      slot: slot,
      updatedAt: DateTime.now(),
    );
  }

  String _safeFileName(String title) {
    final trimmed = title.trim().isEmpty ? 'Untitled Book' : title.trim();
    final cleaned = trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return cleaned.isEmpty ? 'Untitled Book' : cleaned;
  }
}
