import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/app.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/l10n/language.dart';
import 'package:material_ui/material_ui.dart';

/// The session screen's title on a narrow phone (360 dp wide) in [code].
Future<RenderParagraph> titleOnNarrowPhone(
  WidgetTester tester,
  String code,
  String date, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final language = LanguageSetting(MemoryLanguageStorage(code));
  await language.load();
  final store = AppStore(MemoryStorage());
  await store.seedDemo(today: '2026-11-26');
  await tester.pumpWidget(GelanggangApp(store: store, language: language));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Demo Sports Hall'));
  await tester.pumpAndSettle();
  final title = find.descendant(
    of: find.byType(AppBar),
    matching: find.text(date),
  );
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: title, matching: find.byType(RichText)),
  );
}

void main() {
  const dates = {
    'zh': '2026年11月26日（周四）',
    'ms': 'Khamis, 26 Nov 2026',
    'en': '2026-11-26',
  };
  for (final MapEntry(key: code, value: date) in dates.entries) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('$code session title shows the whole date, weekday '
          'included, on a narrow phone at ${scale}x text', (tester) async {
        final title = await titleOnNarrowPhone(
          tester,
          code,
          date,
          textScale: scale,
        );
        // Not cut off with an ellipsis, and fully inside the app bar.
        expect(title.didExceedMaxLines, isFalse);
        final bar = tester.getRect(find.byType(AppBar));
        final box = MatrixUtils.transformRect(
          title.getTransformTo(null),
          Offset.zero & title.size,
        );
        expect(bar.left <= box.left && box.right <= bar.right, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
