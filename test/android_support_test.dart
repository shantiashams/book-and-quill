import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:book_and_quill/controllers/rich_text_editing_controller.dart';
import 'package:book_and_quill/models/app_settings.dart';
import 'package:book_and_quill/models/book_record.dart';
import 'package:book_and_quill/models/rich_page.dart';
import 'package:book_and_quill/screens/book_editor_screen.dart';
import 'package:book_and_quill/services/android_platform.dart';
import 'package:book_and_quill/services/book_file_service.dart';
import 'package:book_and_quill/services/book_storage.dart';
import 'package:book_and_quill/services/game_sound_service.dart';
import 'package:book_and_quill/widgets/book_text_entry_dialog.dart';
import 'package:book_and_quill/widgets/chiseled_bookshelf.dart';
import 'package:book_and_quill/widgets/music_toast.dart';
import 'package:book_and_quill/widgets/page_sheet.dart';

class _SilentSounds extends GameSoundService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> play(GameSound sound, {
    double? pitch, double randomPitchRange = 0, double volumeScale = 1,
    double? categoryVolumeOverride,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final androidVariant = TargetPlatformVariant.only(TargetPlatform.android);

  // Pure Dart/service tests use package:test's teardown. Widget tests below
  // use Flutter's variant lifecycle, which restores the platform before
  // the binding checks its global debug-state invariants.
  group('Android services and text input', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() {
      messenger.setMockMethodCallHandler(AndroidPlatform.channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('Android opens private app storage instead of a desktop HOME directory', () async {
      final directory = await Directory.systemTemp.createTemp('quill-android-');
      addTearDown(() => directory.delete(recursive: true));
      messenger.setMockMethodCallHandler(AndroidPlatform.channel, (call) async {
        expect(call.method, 'getDataDirectory');
        return directory.path;
      });
      final storage = await BookStorage.open();
      await storage.saveSlots(<BookRecord?>[BookRecord.fresh(0), null, null, null, null, null]);
      expect(await File('${directory.path}/library.json').exists(), isTrue);
      final reopened = await BookStorage.open();
      expect((await reopened.loadSlots()).first?.title, 'Book 1');
    });

    test('missing Android storage fails instead of saving in the working directory', () async {
      messenger.setMockMethodCallHandler(AndroidPlatform.channel, (_) async => null);
      await expectLater(BookStorage.open(), throwsA(isA<FileSystemException>()));
    });

    test('document export/import preserves rich books and cancellation is harmless', () async {
      String? document;
      final original = BookRecord.fresh(0).copyWith(
        title: 'My journal', signed: true, author: 'Shantia', visualVariant: 4,
        pages: <RichPage>[RichPage(
          text: 'Hello دنیا', dateStamp: DateTime(2026, 9, 8), dateText: 'My date',
          runs: const <StyleRun>[StyleRun(start: 0, end: 5,
            style: CharacterStyle(color: 0xFFAA0000))],
        )],
      );
      var canceled = false;
      messenger.setMockMethodCallHandler(AndroidPlatform.channel, (call) async {
        if (call.method == 'exportBook') {
          if (canceled) return false;
          final args = Map<String, dynamic>.from(call.arguments as Map);
          expect(args['filename'], 'My journal.qbook');
          document = args['contents'] as String;
          expect((jsonDecode(document!) as Map)['formatVersion'], 4);
          return true;
        }
        expect(call.method, 'importBook');
        return canceled ? null : document;
      });
      final service = BookFileService();
      expect(await service.exportBook(original), isTrue);
      final restored = (await service.importBook(slot: 8))!;
      expect(restored.slot, 8);
      expect(restored.pages.first.toJson(), original.pages.first.toJson());
      expect(restored.signed, isTrue);
      expect(restored.visualVariant, 4);
      canceled = true;
      expect(await service.exportBook(original), isFalse);
      expect(await service.importBook(slot: 9), isNull);
      canceled = false;
      document = 'not a book';
      await expectLater(service.importBook(slot: 9), throwsFormatException);
    });

    test('keyboard composition commits before wrapping and preserves emoji clusters', () {
      final formatter = MinecraftWordWrapFormatter(
        maxWidth: 30, textStyle: const TextStyle(fontSize: 12),
      );
      const composing = TextEditingValue(text: 'longword',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 0, end: 8));
      expect(formatter.formatEditUpdate(TextEditingValue.empty, composing), composing);
      final committed = formatter.formatEditUpdate(composing,
        composing.copyWith(composing: TextRange.empty));
      expect(committed.text, contains('\n'));
      expect(committed.text.replaceAll('\n', ''), 'longword');
      const cluster = '👨‍👩‍👦';
      final emoji = formatter.formatEditUpdate(TextEditingValue.empty,
        const TextEditingValue(text: '$cluster$cluster'));
      expect(emoji.text.split('\n'), everyElement(cluster));

      var changes = 0;
      final controller = RichTextEditingController(page: RichPage.empty,
        onBeforeUserEdit: () {}, onPageChanged: (_) => changes++,
        onActiveStyleChanged: (_) {});
      addTearDown(controller.dispose);
      controller.value = composing;
      expect(controller.value.composing, composing.composing);
      controller.value = composing.copyWith(composing: TextRange.empty);
      expect(changes, 2); // A same-text IME commit must also schedule pagination.
    });

  });

  testWidgets('long-press opens book actions without opening the book', (tester) async {
    int? held;
    var opened = false;
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox.square(
      dimension: 300, child: ChiseledBookshelf(
        slots: <BookRecord?>[BookRecord.fresh(0), null, null, null, null, null],
        onSlotPressed: (_) => opened = true,
        onSlotSecondaryPressed: (slot, _) => held = slot,
      ),
    ))));
    await tester.longPress(find.byKey(const ValueKey<String>('shelf-slot-0')));
    expect(held, 0);
    expect(opened, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: androidVariant);

  testWidgets('phone editor remains usable with keyboard; tablet spread rotates safely', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final transparent = ValueNotifier<bool>(false);
    final sounds = _SilentSounds();
    addTearDown(transparent.dispose);
    addTearDown(sounds.dispose);
    BookRecord? saved;
    final book = BookRecord.fresh(0).copyWith(
      pages: const <RichPage>[RichPage(text: 'First'), RichPage(text: 'Second')]);
    Widget editor() => MaterialApp(home: BookEditorScreen(
      initialBook: book, initialTwoPage: true,
      transparentModeListenable: transparent,
      onSetTransparentMode: (_) async => false,
      sounds: sounds, onOpenSettings: () async => AppSettings.defaults,
      onAutosave: (book) async { saved = book; },
    ));
    await tester.pumpWidget(editor());
    expect(find.byType(PageSheet), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Typing on Android');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('TOOLS'));
    await tester.pump();
    expect(find.text('FORMATTING'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(saved?.pages.first.text, 'Typing on Android');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.viewInsets = const FakeViewPadding();
    tester.view.physicalSize = const Size(900, 700);
    await tester.pumpWidget(editor());
    expect(find.byType(PageSheet), findsNWidgets(2));
    tester.view.physicalSize = const Size(360, 780);
    await tester.pump();
    await tester.pump();
    expect(find.byType(PageSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: androidVariant);

  testWidgets('Android Back closes input dialogs through their full animation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showDialog<String>(context: context,
        builder: (_) => const BookTextEntryDialog(title: 'Jump to page',
          initialValue: '1', label: 'Page', submitLabel: 'GO', numeric: true)),
        child: const Text('OPEN'))))));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BookTextEntryDialog), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: androidVariant);

  testWidgets('music island opens and closes with touch and always-big is honored', (tester) async {
    final sounds = _SilentSounds();
    addTearDown(sounds.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(
      children: <Widget>[MusicToastOverlay(sounds: sounds)],
    ))));
    await tester.tap(find.byTooltip('Open music controls'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('NO MUSIC PLAYING'), findsOneWidget);
    await tester.tap(find.byTooltip('Close music controls'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('NO MUSIC PLAYING'), findsNothing);
    sounds.musicIslandAlwaysExpanded.value = true;
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('NO MUSIC PLAYING'), findsOneWidget);
    expect(find.byTooltip('Close music controls'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: androidVariant);
}
