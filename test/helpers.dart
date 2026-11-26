import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/app.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:material_ui/material_ui.dart';

/// The app on a phone-sized screen with in-memory storage.
Future<AppStore> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final store = AppStore(MemoryStorage());
  await tester.pumpWidget(GelanggangApp(store: store));
  return store;
}

/// Scrolls the screen's list back to the top, then down until [finder] shows.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  final list = find.byType(Scrollable).first;
  await tester.drag(list, const Offset(0, 5000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 150, scrollable: list);
  await tester.pumpAndSettle();
}
