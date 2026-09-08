import 'package:book_and_quill/controllers/rich_text_editing_controller.dart';
import 'package:book_and_quill/models/rich_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller accepts insertion and deletion without a fixed-list crash', () {
    RichPage? changedPage;
    final controller = RichTextEditingController(
      page: const RichPage(text: 'abc'),
      onBeforeUserEdit: () {},
      onPageChanged: (page) => changedPage = page,
      onActiveStyleChanged: (_) {},
    );
    addTearDown(controller.dispose);

    controller.value = const TextEditingValue(
      text: 'abXYc',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(changedPage?.text, 'abXYc');

    controller.value = const TextEditingValue(
      text: 'aXYc',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(changedPage?.text, 'aXYc');
  });

  test('strikethrough does not turn into underline', () {
    final controller = RichTextEditingController(
      page: const RichPage(text: 'strike'),
      onBeforeUserEdit: () {},
      onPageChanged: (_) {},
      onActiveStyleChanged: (_) {},
    );
    addTearDown(controller.dispose);

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    controller.applyModifier(TextModifier.strikethrough, true);

    final style = controller.page.runs.single.style;
    expect(style.has(TextModifier.strikethrough), isTrue);
    expect(style.has(TextModifier.underline), isFalse);
  });
}
