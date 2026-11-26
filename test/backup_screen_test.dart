import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/app.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

/// Records what the app copies to the clipboard.
List<String> captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  testWidgets('copy a backup on one phone, restore it on another', (
    tester,
  ) async {
    final copied = captureClipboard(tester);
    final old = await pumpApp(tester);
    await old.seedDemo(today: '2026-11-26');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This phone has 8 players and 2 sessions'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('copy-backup')));
    await tester.pumpAndSettle();
    expect(
      find.text('Backup copied. Paste it somewhere safe.'),
      findsOneWidget,
    );
    expect(copied.single, old.exportBackup());

    // The new phone: one player of its own.
    final fresh = AppStore(MemoryStorage());
    await fresh.addPlayer('Zara');
    await tester.pumpWidget(
      GelanggangApp(key: const ValueKey('new phone'), store: fresh),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();

    // Something that is not a backup is refused under the field.
    await tester.enterText(find.byKey(const Key('restore-text')), 'hello');
    await tester.tap(find.byKey(const Key('restore')));
    await tester.pumpAndSettle();
    expect(find.textContaining('not a gelanggang backup'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    // The real one asks first, then replaces everything.
    await tester.enterText(
      find.byKey(const Key('restore-text')),
      copied.single,
    );
    await tester.tap(find.byKey(const Key('restore')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'The backup has 8 players and 2 sessions. It replaces the 1 player '
        'and 0 sessions on this phone',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fresh.players.single.name, 'Zara');

    await tester.tap(find.byKey(const Key('restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-restore')));
    await tester.pumpAndSettle();
    expect(find.text('Backup restored.'), findsOneWidget);
    expect(fresh.exportBackup(), copied.single);
    expect(
      find.textContaining('This phone has 8 players and 2 sessions'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Demo Sports Hall'), findsOneWidget);
  });

  testWidgets('unreadable saved data shows a badge and can be copied out', (
    tester,
  ) async {
    final copied = captureClipboard(tester);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    const raw = '{"version": 9, "players": "from the future"}';
    final storage = MemoryStorage(raw);
    final store = AppStore(storage);
    await store.load();
    await tester.pumpWidget(GelanggangApp(store: store));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Badge>(
            find.descendant(
              of: find.byTooltip('Backup and restore'),
              matching: find.byType(Badge),
            ),
          )
          .isLabelVisible,
      isTrue,
    );
    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();
    expect(find.text('Some saved data could not be read'), findsOneWidget);
    await tester.tap(find.text('Copy it'));
    await tester.pumpAndSettle();
    expect(copied.single, raw);

    await tester.tap(find.text('Throw it away'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(storage.aside, raw);
    await tester.tap(find.text('Throw it away'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Throw away'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('set-aside')), findsNothing);
    expect(storage.aside, isNull);
  });
}
