import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

/// Material's own checks: tap targets at least 48x48 (Android) and 44x44
/// (iOS), every tappable thing labelled, and text contrast.
Future<void> meetsGuidelines(WidgetTester tester, String screen) async {
  for (final guideline in [
    androidTapTargetGuideline,
    iOSTapTargetGuideline,
    labeledTapTargetGuideline,
    textContrastGuideline,
  ]) {
    await expectLater(tester, meetsGuideline(guideline), reason: screen);
  }
}

void main() {
  testWidgets('every screen meets the tap target, label and contrast '
      'guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    final store = await pumpApp(tester);
    await store.seedDemo(today: '2026-11-26');
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'home');

    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'session');

    await tester.tap(find.byKey(const Key('open-queue')));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'queue');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Players'));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'players');
    await tester.tap(find.text('Bee Ling'));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'player');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'backup');
    semantics.dispose();
  });

  testWidgets('screen readers hear what each control is for', (tester) async {
    final semantics = tester.ensureSemantics();
    final store = await pumpApp(tester);
    // A tablet, so the times fit on one line and the 48 px minimum shows.
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 1.5;
    await store.seedDemo(today: '2026-11-26');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    // Figures read as one item.
    expect(find.bySemanticsLabel(RegExp(r'^Total\nRM \d')), findsOneWidget);
    // Per-row controls name the player.
    await reveal(tester, find.bySemanticsLabel('Daniel paid'));
    expect(find.bySemanticsLabel('Daniel paid'), findsOneWidget);
    await reveal(
      tester,
      find.bySemanticsLabel('Change times for Hui Min, 21:00 to 22:00'),
    );
    final times = find.bySemanticsLabel(
      'Change times for Hui Min, 21:00 to 22:00',
    );
    expect(times, findsOneWidget);
    final node = tester.getSemantics(times);
    expect(node.rect.height, greaterThanOrEqualTo(48), reason: 'tap target');
    // A screen reader's double tap opens the times dialog.
    tester.semantics.tap(
      find.semantics.byLabel('Change times for Hui Min, 21:00 to 22:00'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hui Min: time at the court'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('twice the text size: nothing overflows and no text is '
      'squeezed into a narrow column', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = await pumpApp(tester);
    await store.seedDemo(today: '2026-11-26');
    await tester.pumpAndSettle();
    Future<void> check(String screen) async {
      expect(tester.takeException(), isNull, reason: screen);
      final list = find.byType(Scrollable);
      for (var i = 0; i < 40; i++) {
        expectNoSqueezedText(tester, screen);
        if (list.evaluate().isEmpty) break;
        final pos = tester.state<ScrollableState>(list.first).position;
        if (pos.pixels >= pos.maxScrollExtent) break;
        await tester.drag(list.first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: screen);
      }
    }

    await check('home');
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await check('session');
    // Before rows were stacked this was over 18,000 px.
    final pos = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(pos.maxScrollExtent, lessThan(8000));
    await reveal(tester, find.byKey(const Key('open-queue')));
    await tester.tap(find.byKey(const Key('open-queue')));
    await tester.pumpAndSettle();
    await check('queue');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Players'));
    await tester.pumpAndSettle();
    await check('players');
    await reveal(tester, find.textContaining('Bee Ling').first);
    await tester.tap(find.textContaining('Bee Ling').first);
    await tester.pumpAndSettle();
    await check('player');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();
    await check('backup');
  });
}

/// Fails if a piece of text of four or more characters is laid out in a
/// column narrower than three of its characters (it would wrap almost a
/// letter per line).
void expectNoSqueezedText(WidgetTester tester, String screen) {
  final view = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (final element in find.byType(RichText).evaluate()) {
    final box = element.renderObject! as RenderParagraph;
    if (!box.attached || !box.hasSize) continue;
    final text = box.text.toPlainText().trim();
    if (text.length < 4) continue;
    final origin = box.localToGlobal(Offset.zero);
    if (origin.dy < 0 || origin.dy > view.height) continue;
    final style =
        (box.text as TextSpan).style ?? DefaultTextStyle.of(element).style;
    final em = box.textScaler.scale(style.fontSize ?? 14);
    expect(
      box.size.width,
      greaterThanOrEqualTo(em * 3),
      reason: '$screen: "$text" is squeezed to ${box.size.width} px',
    );
  }
}
