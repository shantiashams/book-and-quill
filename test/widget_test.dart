import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:book_and_quill/controllers/rich_text_editing_controller.dart';
import 'package:book_and_quill/models/book_record.dart';
import 'package:book_and_quill/models/rich_page.dart';
import 'package:book_and_quill/widgets/chiseled_bookshelf.dart';
import 'package:book_and_quill/widgets/page_sheet.dart';
import 'package:book_and_quill/widgets/pixel_button.dart';

void main() {
  testWidgets('pixel button renders and responds', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixelButton(
            label: 'TEST',
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.text('TEST'), findsOneWidget);
    await tester.tap(find.text('TEST'));
    expect(pressed, isTrue);
  });

  testWidgets('page surface scales while its 20 by 15 grid stays stable',
      (tester) async {
    final controller = RichTextEditingController(
      page: const RichPage(text: 'abc'),
      onBeforeUserEdit: () {},
      onPageChanged: (_) {},
      onActiveStyleChanged: (_) {},
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    Widget pageAt(double size) => MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: size,
              child: PageSheet(
                controller: controller,
                focusNode: focusNode,
                pageNumber: 1,
                totalPages: 1,
                onFocused: () {},
                readOnly: false,
              ),
            ),
          ),
        );

    await tester.pumpWidget(pageAt(600));
    final fullSizeField = tester.widget<TextField>(find.byType(TextField));
    expect(fullSizeField.style?.fontFamily, 'MinecraftBookGridV3');
    expect(fullSizeField.style?.fontSize, 18);
    expect(fullSizeField.style?.height, closeTo(4 / 3, 0.0001));
    final fullSizeGrid = tester.widget<SizedBox>(
      find.byKey(const ValueKey<String>('page-1-text-grid')),
    );
    expect(fullSizeGrid.width, 360);
    expect(fullSizeGrid.height, 360);
    expect(find.text('3/1023'), findsNothing);

    await tester.pumpWidget(pageAt(300));
    final halfSizeField = tester.widget<TextField>(find.byType(TextField));
    expect(halfSizeField.style?.fontFamily, 'MinecraftBookGridV3');
    expect(halfSizeField.style?.fontSize, 18);
    final halfSizeGrid = tester.widget<SizedBox>(
      find.byKey(const ValueKey<String>('page-1-text-grid')),
    );
    expect(halfSizeGrid.width, 360);
    expect(halfSizeGrid.height, 360);
    expect(find.text('3/1023'), findsNothing);
  });

  testWidgets('page header and vanilla arrows are interactive on the book',
      (tester) async {
    var indicatorPressed = false;
    var previousPressed = false;
    var nextPressed = false;
    final controller = RichTextEditingController(
      page: const RichPage(text: 'abc'),
      onBeforeUserEdit: () {},
      onPageChanged: (_) {},
      onActiveStyleChanged: (_) {},
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 600,
            child: PageSheet(
              controller: controller,
              focusNode: focusNode,
              pageNumber: 2,
              totalPages: 4,
              onFocused: () {},
              readOnly: false,
              onPageIndicatorPressed: () => indicatorPressed = true,
              onPreviousPage: () => previousPressed = true,
              onNextPage: () => nextPressed = true,
            ),
          ),
        ),
      ),
    );

    final indicator = find.text('Page 2 of 4');
    expect(indicator, findsOneWidget);
    expect(tester.widget<Text>(indicator).style?.fontSize, 18);
    expect(find.byKey(const ValueKey<String>('page-2-back-arrow')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('page-2-forward-arrow')),
        findsOneWidget);
    final backArrowPosition = tester.widget<Positioned>(
      find.ancestor(
        of: find.byKey(const ValueKey<String>('page-2-back-arrow')),
        matching: find.byType(Positioned),
      ),
    );
    final forwardArrowPosition = tester.widget<Positioned>(
      find.ancestor(
        of: find.byKey(const ValueKey<String>('page-2-forward-arrow')),
        matching: find.byType(Positioned),
      ),
    );
    expect(backArrowPosition.bottom, 72);
    expect(forwardArrowPosition.bottom, 72);

    await tester.tap(
      find.byKey(const ValueKey<String>('page-2-indicator')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('page-2-back-arrow')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('page-2-forward-arrow')),
    );
    expect(indicatorPressed, isTrue);
    expect(previousPressed, isTrue);
    expect(nextPressed, isTrue);
  });

  testWidgets('shelf selection cells are exact and do not overlap',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.square(
            dimension: 600,
            child: ChiseledBookshelf(
              slots: const <BookRecord?>[null, null, null, null, null, null],
              onSlotPressed: (_) {},
              onSlotSecondaryPressed: (_, __) {},
            ),
          ),
        ),
      ),
    );

    final topRects = <Rect>[];
    final bottomRects = <Rect>[];
    for (var slot = 0; slot < 3; slot++) {
      final rect =
          tester.getRect(find.byKey(ValueKey<String>('shelf-slot-$slot')));
      topRects.add(rect);
      expect(rect.top, closeTo(87, 0.01));
      expect(rect.height, closeTo(192, 0.01));
    }
    for (var slot = 3; slot < 6; slot++) {
      final rect =
          tester.getRect(find.byKey(ValueKey<String>('shelf-slot-$slot')));
      bottomRects.add(rect);
      expect(rect.top, closeTo(321, 0.01));
      expect(rect.height, closeTo(234, 0.01));
      expect(rect.bottom, closeTo(555, 0.01));
    }

    expect(topRects[0].left, closeTo(63, 0.01));
    expect(topRects[0].width, closeTo(153, 0.01));
    expect(topRects[1].left, closeTo(225, 0.01));
    expect(topRects[1].width, closeTo(150, 0.01));
    expect(topRects[0].right, lessThan(topRects[1].left));
    expect(bottomRects[0].right, lessThan(bottomRects[1].left));
    expect(topRects[1].right, lessThanOrEqualTo(topRects[2].left));
    expect(bottomRects[1].right, lessThanOrEqualTo(bottomRects[2].left));
  });

  testWidgets('glint follows the corrected left and lower-middle silhouettes',
      (tester) async {
    final books = List<BookRecord?>.generate(
      6,
      (slot) => BookRecord.fresh(slot).copyWith(favorite: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.square(
            dimension: 600,
            child: ChiseledBookshelf(
              slots: books,
              onSlotPressed: (_) {},
              onSlotSecondaryPressed: (_, __) {},
            ),
          ),
        ),
      ),
    );

    Path glintPath(int slot, Size size) {
      final finder = find.descendant(
        of: find.byKey(ValueKey<String>('shelf-slot-$slot')),
        matching: find.byType(ClipPath),
      );
      expect(finder, findsOneWidget);
      return tester.widget<ClipPath>(finder).clipper!.getClip(size);
    }

    final topLeftSize =
        tester.getSize(find.byKey(const ValueKey<String>('shelf-slot-0')));
    final topLeftBounds = glintPath(0, topLeftSize).getBounds();
    expect(topLeftBounds.top, closeTo(0, 0.01));
    expect(topLeftBounds.right, closeTo(topLeftSize.width, 0.01));
    expect(topLeftBounds.bottom, closeTo(topLeftSize.height * 0.91, 0.01));

    final bottomLeftSize =
        tester.getSize(find.byKey(const ValueKey<String>('shelf-slot-3')));
    final bottomLeftBounds = glintPath(3, bottomLeftSize).getBounds();
    expect(bottomLeftBounds.top, closeTo(bottomLeftSize.height * 0.08, 0.01));
    expect(bottomLeftBounds.right, closeTo(bottomLeftSize.width, 0.01));
    expect(bottomLeftBounds.bottom, closeTo(bottomLeftSize.height, 0.01));

    final bottomMiddleSize =
        tester.getSize(find.byKey(const ValueKey<String>('shelf-slot-4')));
    final bottomMiddleBounds = glintPath(4, bottomMiddleSize).getBounds();
    expect(bottomMiddleBounds.left, closeTo(0, 0.01));
    expect(bottomMiddleBounds.top,
        closeTo(bottomMiddleSize.height * 0.08, 0.01));
    expect(bottomMiddleBounds.right, closeTo(bottomMiddleSize.width, 0.01));
    expect(bottomMiddleBounds.bottom, closeTo(bottomMiddleSize.height, 0.01));
  });
}
