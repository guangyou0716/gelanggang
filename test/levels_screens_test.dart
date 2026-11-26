import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/domain/queue.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('a court switched to singles suggests one on one, shows level '
      'totals and starts a singles game', (tester) async {
    final store = await pumpApp(tester);
    await store.seedDemo(today: '2026-11-26');
    await tester.pumpAndSettle();
    final sid = store.sessions.first.id;
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-queue')));
    await tester.pumpAndSettle();

    // Court 2 is free and plays doubles: four chips.
    expect(find.byKey(const Key('next-3')), findsOneWidget);
    expect(find.bySemanticsLabel('Game on court 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('type-singles')));
    await tester.pumpAndSettle();
    expect(store.session(sid)!.singlesCourts, [2]);
    expect(find.text('Court 2 · singles'), findsOneWidget);
    expect(find.byKey(const Key('next-1')), findsOneWidget);
    expect(find.byKey(const Key('next-2')), findsNothing);
    final suggested = suggestNext(store.session(sid)!, levels: store.levels)!;
    expect(suggested.teamA, hasLength(1));
    final levels = store.levels;
    final a = levels[suggested.teamA.single];
    final b = levels[suggested.teamB.single];
    if (a != null && b != null) {
      expect(find.text('Levels $a v $b'), findsOneWidget);
    } else {
      expect(find.byKey(const Key('level-totals')), findsNothing);
    }

    await tester.tap(find.byKey(const Key('start-game')));
    await tester.pumpAndSettle();
    final game = store.session(sid)!.games.last;
    expect(game.court, 2);
    expect(game.singles, isTrue);
    expect(game.teamA, suggested.teamA);
    expect(game.teamB, suggested.teamB);
    // Both courts busy; the next suggestion is for court 1 (doubles), and
    // only two players are left waiting.
    expect(
      find.text('Waiting for four free players (2 free now).'),
      findsOneWidget,
    );

    // The switch now applies to court 1 (in play longest, so free next):
    // singles there makes a game of the two left waiting, ready for when
    // a court frees up. Court 2 keeps its own setting.
    expect(find.bySemanticsLabel('Game on court 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('type-singles')));
    await tester.pumpAndSettle();
    expect(store.session(sid)!.singlesCourts, [1, 2]);
    expect(find.text('Court 1 · singles'), findsOneWidget);
    expect(find.byKey(const Key('next-1')), findsOneWidget);
    expect(find.text('All courts are busy.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('type-doubles')));
    await tester.pumpAndSettle();
    expect(store.session(sid)!.singlesCourts, [2]);
    expect(store.session(sid)!.games.first.singles, isFalse);
  });

  testWidgets('with no free players the singles hint asks for two', (
    tester,
  ) async {
    final store = await pumpApp(tester);
    final s = await store.createSession(
      date: '2026-11-26',
      venue: 'Hall',
      startMinute: 1200,
      endMinute: 1320,
      courts: 1,
      courtRateSen: 2000,
      shuttles: 0,
      shuttlePriceSen: 0,
    );
    final p = await store.addPlayer('Aiman');
    await store.toggleAttendance(s.id, p.id);
    await store.setCourtSingles(s.id, 1, true);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Hall'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-queue')));
    await tester.pumpAndSettle();
    expect(
      find.text('Tick at least two players under "Who came" first.'),
      findsOneWidget,
    );
    final q = await store.addPlayer('Bee Ling');
    await store.toggleAttendance(s.id, q.id);
    await store.setResting(s.id, q.id, true);
    await tester.pumpAndSettle();
    expect(
      find.text('Waiting for two free players (1 free now).'),
      findsOneWidget,
    );
  });

  testWidgets('a level is picked on the player screen and shown in the '
      'roster and the queue', (tester) async {
    final store = await pumpApp(tester);
    final p = await store.addPlayer('Aiman');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Players'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('No level')), findsOneWidget);
    await tester.tap(find.text('Aiman'));
    await tester.pumpAndSettle();
    expect(find.text('Level'), findsOneWidget);
    await tester.tap(find.byKey(const Key('level-3')));
    await tester.pumpAndSettle();
    expect(store.players.single.level, 3);
    expect(
      tester.widget<ChoiceChip>(find.byKey(const Key('level-3'))).selected,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('level-none')));
    await tester.pumpAndSettle();
    expect(store.players.single.level, isNull);
    await tester.tap(find.byKey(const Key('level-5')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Level 5')), findsOneWidget);

    final s = await store.createSession(
      date: '2026-11-26',
      venue: 'Hall',
      startMinute: 1200,
      endMinute: 1320,
      courts: 1,
      courtRateSen: 2000,
      shuttles: 0,
      shuttlePriceSen: 0,
    );
    await store.toggleAttendance(s.id, p.id);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Hall'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-queue')));
    await tester.pumpAndSettle();
    expect(find.text('0 games · level 5'), findsOneWidget);
  });
}
