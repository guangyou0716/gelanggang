import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/domain/queue.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('organiser runs the court queue from the demo session', (
    tester,
  ) async {
    final store = await pumpApp(tester);
    await store.seedDemo(today: '2026-11-26');
    await tester.pumpAndSettle();
    final sid = store.sessions.single.id;
    String name(int id) => store.names[id]!;

    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    expect(
      find.text('Court queue · 4 on court · 2 games played'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('open-queue')));
    await tester.pumpAndSettle();

    // Court 1 busy, court 2 free, four waiting.
    expect(find.text('Court 2'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Waiting (4)'), findsOneWidget);
    expect(find.text('Games (2)'), findsOneWidget);
    expect(find.text('Court 1 · 21-17'), findsOneWidget);
    final suggested = suggestNext(store.session(sid)!)!;
    final first = suggested.teamA.first;
    final second = suggested.teamA.last;
    expect(
      tester.widget<ActionChip>(find.byKey(const Key('next-0'))).label,
      isA<Text>().having((t) => t.data, 'data', name(first)),
    );

    // Swap the first two players' places, then start on court 2.
    await tester.tap(find.byKey(const Key('next-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${name(second)} (swap places)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-game')));
    await tester.pumpAndSettle();
    final started = store.session(sid)!.games.last;
    expect(started.court, 2);
    expect(started.teamA, [second, first]);
    expect(find.text('All courts are busy.'), findsNothing);
    expect(
      find.textContaining('Waiting for four free players'),
      findsOneWidget,
    );

    // Finish court 1: a draw is refused, then 21-18 is logged.
    await tester.tap(find.byKey(const Key('finish-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('score-a')), '20');
    await tester.enterText(find.byKey(const Key('score-b')), '20');
    await tester.tap(find.byKey(const Key('save-score')));
    await tester.pumpAndSettle();
    expect(find.text('A badminton game cannot end in a draw'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('score-a')), '21');
    await tester.enterText(find.byKey(const Key('score-b')), '18');
    await tester.tap(find.byKey(const Key('save-score')));
    await tester.pumpAndSettle();
    expect(find.text('Court 1 · 21-18'), findsOneWidget);
    expect(find.text('Games (3)'), findsOneWidget);
    expect(find.text('Waiting (4)'), findsOneWidget);

    // Someone sits out: they leave the queue, then come back.
    final waiting = waitingOrder(store.session(sid)!);
    await tester.tap(find.text('Sit out').first);
    await tester.pumpAndSettle();
    expect(find.text('${name(waiting.first)} (sitting out)'), findsOneWidget);
    expect(find.text('Waiting (3)'), findsOneWidget);
    await tester.tap(find.text('Back in'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting (4)'), findsOneWidget);
  });

  testWidgets('a player with games cannot be unticked from the session', (
    tester,
  ) async {
    final store = await pumpApp(tester);
    await store.seedDemo(today: '2026-11-26');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Aiman came'));
    await tester.pumpAndSettle();
    expect(
      find.text('Aiman has games in this session; remove those games first'),
      findsOneWidget,
    );
    expect(store.sessions.single.attendance, hasLength(8));
  });
}
