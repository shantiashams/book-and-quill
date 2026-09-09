import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:book_and_quill/controllers/rich_text_editing_controller.dart';
import 'package:book_and_quill/models/book_record.dart';
import 'package:book_and_quill/models/rich_page.dart';
import 'package:book_and_quill/widgets/chiseled_bookshelf.dart';
import 'package:book_and_quill/widgets/page_sheet.dart';
import 'package:book_and_quill/widgets/pixel_button.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('pixel button renders and responds', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      PixelButton(label: 'TEST', onPressed: () => pressed = true))));
    await tester.tap(find.text('TEST'));
    expect(pressed, isTrue);
  });

  testWidgets('desktop pages retain writing and interactive controls when scaled', (tester) async {
    final controller = RichTextEditingController(
      page: const RichPage(text: 'abc'), onBeforeUserEdit: () {},
      onPageChanged: (_) {}, onActiveStyleChanged: (_) {});
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var indicator = false;
    var previous = false;
    var next = false;
    Widget pageAt(double size) => MaterialApp(home: Center(child: SizedBox.square(
      dimension: size, child: PageSheet(controller: controller,
        focusNode: focus, pageNumber: 2, totalPages: 4, readOnly: false,
        onFocused: () {}, dateController: null, dateFocusNode: null,
        onDateFocused: () {},
        onPageIndicatorPressed: () => indicator = true,
        onPreviousPage: () => previous = true,
        onNextPage: () => next = true,
      ),
    )));
    for (final size in <double>[600, 300]) {
      await tester.pumpWidget(pageAt(size));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'abc');
      expect(field.maxLines, 15);
      expect(field.style?.fontFamily, 'MinecraftLocalV2');
      expect(field.style?.fontSize, 18);
      await tester.tap(find.byKey(const ValueKey<String>('page-2-indicator')));
      await tester.tap(find.byKey(const ValueKey<String>('page-2-back-arrow')));
      await tester.tap(find.byKey(const ValueKey<String>('page-2-forward-arrow')));
      expect(tester.takeException(), isNull);
    }
    expect(indicator && previous && next, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('six shelf hit areas match the 16 by 16 texture and never overlap', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Align(alignment: Alignment.topLeft,
      child: SizedBox.square(dimension: 600, child: ChiseledBookshelf(
        slots: const <BookRecord?>[null, null, null, null, null, null],
        onSlotPressed: (_) {}, onSlotSecondaryPressed: (_, __) {},
      )),
    )));
    final rectangles = <Rect>[];
    for (var slot = 0; slot < 6; slot++) {
      final rect = tester.getRect(find.byKey(ValueKey<String>('shelf-slot-$slot')));
      expect(rect.left, closeTo(37.5 + (slot % 3) * 187.5, 0.01));
      expect(rect.top, closeTo(slot < 3 ? 37.5 : 337.5, 0.01));
      expect(rect.size, const Size(150, 225));
      expect(rectangles.any((other) => other.overlaps(rect)), isFalse);
      rectangles.add(rect);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('favorite glint and labels do not intercept book taps', (tester) async {
    final pressed = <int>[];
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox.square(
      dimension: 500, child: ChiseledBookshelf(
        slots: List<BookRecord?>.generate(6, (slot) => BookRecord.fresh(slot)
          .copyWith(favorite: true, visualVariant: slot)),
        onSlotPressed: pressed.add, onSlotSecondaryPressed: (_, __) {},
      ),
    ))));
    for (var slot = 0; slot < 6; slot++) {
      await tester.tap(find.byKey(ValueKey<String>('shelf-slot-$slot')));
    }
    expect(pressed, <int>[0, 1, 2, 3, 4, 5]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
