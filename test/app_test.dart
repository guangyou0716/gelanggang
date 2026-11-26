import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('organiser adds players, runs a session and gets the message', (
    tester,
  ) async {
    final store = await pumpApp(tester);
    expect(find.textContaining('No sessions yet'), findsOneWidget);

    // Roster.
    await tester.tap(find.byTooltip('Players'));
    await tester.pumpAndSettle();
    for (final name in ['Aiman', 'Bee Ling', 'Chandran']) {
      await tester.enterText(find.byKey(const Key('player-name')), name);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byKey(const Key('player-name')), 'aiman');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('aiman is already on the list'), findsOneWidget);
    expect(store.players, hasLength(3));
    await tester.pageBack();
    await tester.pumpAndSettle();

    // New session: a bad amount is caught by the form.
    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-venue')), 'Dewan Demo');
    await tester.enterText(find.byKey(const Key('field-rate')), 'abc');
    await tester.enterText(find.byKey(const Key('field-shuttles')), '6');
    await tester.enterText(find.byKey(const Key('field-shuttlePrice')), '4.50');
    await tester.tap(find.byKey(const Key('save-session')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount like 20 or 4.50'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field-rate')), '20');
    await tester.tap(find.byKey(const Key('save-session')));
    await tester.pumpAndSettle();

    // Session screen: RM 80 courts + RM 27 shuttles.
    expect(find.text('RM 107.00'), findsOneWidget);
    for (final name in ['Aiman', 'Bee Ling', 'Chandran']) {
      await reveal(tester, find.bySemanticsLabel('$name came'));
      await tester.tap(find.bySemanticsLabel('$name came'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Who came (3)'), findsOneWidget);
    expect(find.text('RM 35.67'), findsNWidgets(2));
    expect(find.text('RM 35.66'), findsOneWidget);

    // Aiman paid; Chandran came an hour late and the split goes by time.
    await reveal(tester, find.widgetWithText(FilterChip, 'Paid').first);
    await tester.tap(find.widgetWithText(FilterChip, 'Paid').first);
    await tester.pumpAndSettle();
    for (final picker in ['court-split', 'shuttle-split']) {
      await reveal(tester, find.byKey(Key(picker)));
      await tester.tap(
        find.descendant(
          of: find.byKey(Key(picker)),
          matching: find.text('By time'),
        ),
      );
      await tester.pumpAndSettle();
    }
    await reveal(tester, find.text('20:00-22:00 · tap to change').last);
    await tester.tap(find.text('20:00-22:00 · tap to change').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('arrive')), '21:00');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('21:00-22:00 · tap to change'), findsOneWidget);
    // 120 : 120 : 60 minutes of RM 107.00.
    final text = tester
        .widget<SelectableText>(find.byKey(const Key('settle-text')))
        .data!;
    expect(text, contains('Split by time played:'));
    expect(text, contains('- Aiman: RM 42.80 (paid, thanks!)'));
    expect(text, contains('- Bee Ling: RM 42.80'));
    expect(text, contains('- Chandran: RM 21.40'));

    // Back home: the session shows what is left to collect.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('RM 64.20 to collect'), findsOneWidget);
  });

  testWidgets('an arrival time outside the session is refused', (tester) async {
    final store = await pumpApp(tester);
    await store.seedDemo(today: '2026-11-26');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('20:00-22:00 · tap to change').first);
    await tester.tap(find.text('20:00-22:00 · tap to change').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('arrive')), '19:00');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Arrival and leaving times must be within the session'),
      findsOneWidget,
    );
  });
}
