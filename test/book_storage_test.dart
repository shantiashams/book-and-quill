import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:book_and_quill/models/book_record.dart';
import 'package:book_and_quill/services/book_storage.dart';

void main() {
  test('storage saves and loads a fixed six-slot shelf', () async {
    final directory = await Directory.systemTemp.createTemp('book-and-quill-test-');
    addTearDown(() => directory.delete(recursive: true));
    final storage = BookStorage(dataDirectory: directory);
    final slots = List<BookRecord?>.filled(BookStorage.slotCount, null);
    slots[2] = BookRecord.fresh(2).copyWith(title: 'Testing');

    await storage.saveSlots(slots);
    final restored = await storage.loadSlots();

    expect(restored, hasLength(6));
    expect(restored[2]?.title, 'Testing');
    expect(restored[0], isNull);
  });

  test('storage preserves additional empty shelves', () async {
    final directory = await Directory.systemTemp.createTemp('book-and-quill-shelves-');
    addTearDown(() => directory.delete(recursive: true));
    final storage = BookStorage(dataDirectory: directory);
    final slots = List<BookRecord?>.filled(18, null);
    slots[7] = BookRecord.fresh(7);

    await storage.saveSlots(slots);
    final restored = await storage.loadSlots();

    expect(restored, hasLength(18));
    expect(restored[7]?.slot, 7);
  });
}
