import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:book_and_quill/controllers/rich_text_editing_controller.dart';
import 'package:book_and_quill/models/app_settings.dart';
import 'package:book_and_quill/models/rich_page.dart';
import 'package:book_and_quill/services/android_media_session_bridge.dart';
import 'package:book_and_quill/services/book_storage.dart';
import 'package:book_and_quill/widgets/page_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  group('Android media settings and bridge', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() {
      messenger.setMockMethodCallHandler(AndroidMediaSessionBridge.channel, null);
      AndroidMediaSessionBridge.channel.setMethodCallHandler(null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('fresh and missing Android preferences default to music and island Off', () async {
      final directory = await Directory.systemTemp.createTemp('book-media-defaults-');
      try {
        final settings = await BookStorage(dataDirectory: directory).loadSettings();
        expect(settings.musicFrequency, MusicFrequency.off);
        expect(settings.musicIsland, isFalse);
        final migrated = AppSettings.fromJson(<String, dynamic>{});
        expect(migrated.musicFrequency, MusicFrequency.off);
        expect(migrated.musicIsland, isFalse);
        final saved = AppSettings.fromJson(const AppSettings(
          musicFrequency: MusicFrequency.constant, musicIsland: true).toJson());
        expect(saved.musicFrequency, MusicFrequency.constant);
        expect(saved.musicIsland, isTrue);
        expect(AppSettings.defaults.musicFrequency, MusicFrequency.defaultFrequency);
        expect(AppSettings.defaults.musicIsland, isTrue);
      } finally { await directory.delete(recursive: true); }
    });

    test('publishes metadata and timeline even when the app island is disabled', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(AndroidMediaSessionBridge.channel, (call) async {
        calls.add(call);
        return call.method == 'clear' ? null : true;
      });
      final bridge = AndroidMediaSessionBridge();
      try {
        await bridge.initialize((_, __) async {});
        expect(bridge.hasSession, isFalse);
        await bridge.publish(trackId: 'alpha', title: 'Alpha', artist: 'C418',
          album: 'Minecraft - Volume Beta', artworkAssetPath: 'assets/imported/textures/beta_albume_cover.png',
          position: const Duration(seconds: 42), duration: const Duration(minutes: 10), isPaused: false);
        expect(bridge.hasSession, isTrue);
        expect(await bridge.requestFocus(), isTrue);
        final data = calls.singleWhere((call) => call.method == 'publish').arguments as Map;
        expect(data['positionMs'], 42000);
        expect(data['durationMs'], 600000);
        expect(data['artist'], 'C418');
        expect(data['paused'], isFalse);
        expect(data['artwork'], endsWith('beta_albume_cover.png'));
        await bridge.clear();
        expect(bridge.hasSession, isFalse);
        expect(calls.last.method, 'clear');
      } finally { await bridge.dispose(); }
    });

    test('native start failure leaves no background media session', () async {
      messenger.setMockMethodCallHandler(AndroidMediaSessionBridge.channel, (call) async {
        if (call.method == 'publish') throw PlatformException(code: 'MEDIA_SESSION');
        return call.method == 'initialize' ? true : null;
      });
      final bridge = AndroidMediaSessionBridge();
      try {
        await bridge.initialize((_, __) async {});
        await bridge.publish(trackId: 'test', title: 'Test', artist: 'Artist', album: 'Album',
          artworkAssetPath: null, position: Duration.zero, duration: const Duration(minutes: 1), isPaused: true);
        expect(bridge.hasSession, isFalse);
        expect(await bridge.requestFocus(), isFalse);
      } finally { await bridge.dispose(); }
    });
  });

  for (final platform in <TargetPlatform>[TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('18 rows fit above date and arrows on $platform', (tester) async {
      RichTextEditingController controller(String text) => RichTextEditingController(
        page: RichPage(text: text), onBeforeUserEdit: () {}, onPageChanged: (_) {}, onActiveStyleChanged: (_) {});
      final body = controller(List.generate(18, (i) => 'Line ${i + 1}').join('\n'));
      final date = controller('2026-09-11 12:30');
      final focus = FocusNode();
      final dateFocus = FocusNode();
      addTearDown(body.dispose); addTearDown(date.dispose);
      addTearDown(focus.dispose); addTearDown(dateFocus.dispose);
      expect(PageSheet.textRowLimit, 18);
      for (final side in PageSheetSide.values) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(
          width: 600, height: 600,
          child: PageSheet(controller: body, focusNode: focus,
            pageNumber: 1, totalPages: 2, onFocused: () {}, readOnly: false,
            dateController: date, dateFocusNode: dateFocus, onDateFocused: () {},
            onPreviousPage: () {}, onNextPage: () {}, side: side),
        )))));
        final grid = tester.getRect(find.byKey(const ValueKey<String>('page-1-text-grid')));
        final stamp = tester.getRect(find.byKey(const ValueKey<String>('page-1-date')));
        final arrow = tester.getRect(find.byKey(const ValueKey<String>('page-1-forward-arrow')));
        expect(grid.height, greaterThanOrEqualTo(18 * 22));
        expect(grid.bottom, lessThanOrEqualTo(stamp.top));
        expect(stamp.bottom, lessThanOrEqualTo(arrow.top));
        expect(body.text.split('\n').length, 18);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(platform));
  }
}
