import 'package:flutter_test/flutter_test.dart';
import 'package:book_and_quill/models/book_record.dart';
import 'package:book_and_quill/models/rich_page.dart';

void main() {
  test('book record survives JSON round trip', () {
    final original = BookRecord.fresh(3).copyWith(
      title: 'Redstone notes',
      pages: const <RichPage>[
        RichPage(text: 'first page'),
        RichPage(text: 'second page'),
      ],
      spreadStart: 0,
    );

    final restored = BookRecord.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.slot, 3);
    expect(restored.title, 'Redstone notes');
    expect(restored.pages.map((page) => page.text), <String>['first page', 'second page']);
  });

  test('book record migrates legacy string pages', () {
    final restored = BookRecord.fromJson(<String, Object>{
      'slot': 0,
      'pages': <String>['only page'],
    });

    expect(restored.pages, hasLength(1));
    expect(restored.pages.first.text, 'only page');
  });

  test('rich page style runs survive JSON', () {
    final page = RichPage(
      text: 'hello',
      runs: const <StyleRun>[
        StyleRun(
          start: 0,
          end: 5,
          style: CharacterStyle(
            color: 0xFF55FFFF,
            modifiers: <TextModifier>{TextModifier.bold, TextModifier.underline},
          ),
        ),
      ],
    );
    final restored = RichPage.fromJson(page.toJson());
    expect(restored.text, 'hello');
    expect(restored.runs.single.style.color, 0xFF55FFFF);
    expect(restored.runs.single.style.has(TextModifier.bold), isTrue);
  });

  test('expanded styles stay growable while typing', () {
    final styles = const RichPage(text: 'abc').expandStyles();

    styles.replaceRange(
      1,
      2,
      const <CharacterStyle>[
        CharacterStyle(modifiers: <TextModifier>{TextModifier.strikethrough}),
        CharacterStyle(modifiers: <TextModifier>{TextModifier.underline}),
      ],
    );

    expect(styles, hasLength(4));
    expect(styles[1].has(TextModifier.strikethrough), isTrue);
    expect(styles[2].has(TextModifier.underline), isTrue);
    expect(styles[1].has(TextModifier.underline), isFalse);
  });

  test('underline and strikethrough remain independent modifiers', () {
    final underlined = CharacterStyle.normal.toggle(TextModifier.underline, true);
    final struck = CharacterStyle.normal.toggle(TextModifier.strikethrough, true);

    expect(underlined.has(TextModifier.underline), isTrue);
    expect(underlined.has(TextModifier.strikethrough), isFalse);
    expect(struck.has(TextModifier.strikethrough), isTrue);
    expect(struck.has(TextModifier.underline), isFalse);
    expect(underlined, isNot(struck));
  });
}
