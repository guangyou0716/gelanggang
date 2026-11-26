import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/app.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/models.dart';
import 'package:material_ui/material_ui.dart';

import 'backup_screen_test.dart' show captureClipboard;
import 'helpers.dart';

/// A version 1 document as the first app version saved it: one split mode
/// ("splitMode"), no guest fee, no singles, no levels, no games key.
String oldDocument() => jsonEncode({
  'version': 1,
  'nextId': 4,
  'players': [
    {'id': 1, 'name': 'Aiman'},
    {'id': 2, 'name': 'Bee Ling'},
  ],
  'sessions': [
    {
      'id': 3,
      'date': '2026-11-19',
      'venue': 'Old Hall',
      'start': 1230,
      'end': 1350,
      'courts': 2,
      'courtRateSen': 1800,
      'shuttles': 5,
      'shuttlePriceSen': 400,
      'splitMode': 'byMinutes',
      'attendance': [
        {'playerId': 1, 'arrive': 0, 'leave': 120, 'paid': true},
        {'playerId': 2, 'arrive': 30, 'leave': 120, 'paid': false},
      ],
    },
  ],
});

void main() {
  group('store', () {
    test('createSession checks players in for the whole session, as guests '
        'when the roster says so, skipping unknown and repeated ids', () async {
      final store = AppStore(MemoryStorage());
      final a = await store.addPlayer('Aiman');
      final g = await store.addPlayer('Iskandar');
      await store.setPlayerGuest(g.id, true);
      final s = await store.createSession(
        date: '2026-11-26',
        venue: 'Hall',
        startMinute: 1200,
        endMinute: 1290,
        courts: 1,
        courtRateSen: 2000,
        shuttles: 0,
        shuttlePriceSen: 450,
        courtSplit: SplitMode.byMinutes,
        shuttleSplit: SplitMode.byGames,
        singlesCourts: const [3, 1, 1, 0],
        playerIds: [g.id, 999, a.id, g.id],
      );
      expect([for (final x in s.attendance) x.playerId], [g.id, a.id]);
      expect([for (final x in s.attendance) x.guest], [true, false]);
      expect(s.attendance.every((x) => x.arriveMinute == 0), isTrue);
      expect(s.attendance.every((x) => x.leaveMinute == 90), isTrue);
      expect(s.attendance.every((x) => !x.paid), isTrue);
      expect(s.courtSplit, SplitMode.byMinutes);
      expect(s.shuttleSplit, SplitMode.byGames);
      // Only this session's courts, once each.
      expect(s.singlesCourts, [1]);
    });

    test('a session that is refused does not use up an id', () async {
      final store = AppStore(MemoryStorage());
      await expectLater(
        store.createSession(
          date: '2026-11-26',
          venue: 'Hall',
          startMinute: 1300,
          endMinute: 1200,
          courts: 1,
          courtRateSen: 0,
          shuttles: 0,
          shuttlePriceSen: 0,
        ),
        throwsA(isA<InputError>()),
      );
      expect(store.sessions, isEmpty);
      final p = await store.addPlayer('Aiman');
      expect(p.id, 1);
    });

    test('lastSession is the latest by date, then the one made last', () async {
      final store = AppStore(MemoryStorage());
      expect(store.lastSession, isNull);
      Future<Session> make(String date, String venue) => store.createSession(
        date: date,
        venue: venue,
        startMinute: 1200,
        endMinute: 1260,
        courts: 1,
        courtRateSen: 0,
        shuttles: 0,
        shuttlePriceSen: 0,
      );
      await make('2026-11-26', 'A');
      final b = await make('2026-11-26', 'B');
      await make('2026-11-19', 'C (entered late)');
      expect(store.lastSession!.id, b.id);
    });

    test('an old version 1 document loads, and its last session can be '
        'repeated and saved; the new document reads back', () async {
      final storage = MemoryStorage(oldDocument());
      final store = AppStore(storage);
      await store.load();
      expect(store.setAside, isNull);
      final last = store.lastSession!;
      expect(last.courtSplit, SplitMode.byMinutes);
      expect(store.rosterPlayersAt(last), [1, 2]);
      final again = await store.createSession(
        date: '2026-11-26',
        venue: last.venue,
        startMinute: last.startMinute,
        endMinute: last.endMinute,
        courts: last.courts,
        courtRateSen: last.courtRateSen,
        shuttles: 0,
        shuttlePriceSen: last.shuttlePriceSen,
        courtSplit: last.courtSplit,
        shuttleSplit: last.shuttleSplit,
        playerIds: store.rosterPlayersAt(last),
      );
      expect(again.id, 4);
      final reread = AppStore(MemoryStorage(storage.data));
      await reread.load();
      expect(reread.setAside, isNull);
      expect(reread.lastSession!.venue, 'Old Hall');
      expect(reread.lastSession!.attendance, hasLength(2));
      expect(
        sharesFor(reread.lastSession!).values.fold<int>(0, (a, b) => a + b),
        totalCostSen(reread.lastSession!),
      );
      // The old session is unchanged: Aiman paid, Bee Ling did not.
      final old = reread.session(3)!;
      expect([for (final a in old.attendance) a.paid], [true, false]);
    });

    test('damaged saved data: nothing to repeat, and the damaged document '
        'stays set aside after a new session is made', () async {
      const damaged = '{"version": 1, "players": [{"id": 1}]';
      final storage = MemoryStorage(damaged);
      final store = AppStore(storage);
      await store.load();
      expect(store.setAside, damaged);
      expect(store.lastSession, isNull);
      await store.createSession(
        date: '2026-11-26',
        venue: 'Hall',
        startMinute: 1200,
        endMinute: 1260,
        courts: 1,
        courtRateSen: 0,
        shuttles: 0,
        shuttlePriceSen: 0,
        playerIds: const [1],
      );
      expect(storage.aside, damaged);
      expect(store.lastSession!.attendance, isEmpty);
    });
  });

  group('screens', () {
    testWidgets('no sessions yet: the form offers nothing to repeat', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repeat-card')), findsNothing);
    });

    testWidgets('"Fill in" copies the last session (date stays today, '
        'shuttles 0) and checks the same players in', (tester) async {
      final store = await pumpApp(tester);
      await store.seedDemo(today: '2026-11-19');
      await tester.pumpAndSettle();
      final last = store.lastSession!;
      await store.setCourtSingles(last.id, 2, true);
      final before = store.sessions.length;

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Same as last time?'), findsOneWidget);
      expect(
        find.text('2026-11-19 · Demo Sports Hall (synthetic) · 8 players'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('repeat-fill')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repeat-card')), findsNothing);
      String field(String key) => tester
          .widget<TextFormField>(find.byKey(Key('field-$key')))
          .controller!
          .text;
      expect(field('date'), isoDate(DateTime.now()));
      expect(field('venue'), last.venue);
      expect(field('start'), '20:00');
      expect(field('courts'), '${last.courts}');
      expect(field('rate'), (last.courtRateSen / 100).toStringAsFixed(2));
      expect(field('shuttles'), '0');
      expect(field('guestFee'), (last.guestFeeSen / 100).toStringAsFixed(2));
      expect(
        find.text('Check in the same players (8 players)'),
        findsOneWidget,
      );

      await reveal(tester, find.byKey(const Key('save-session')));
      await tester.tap(find.byKey(const Key('save-session')));
      await tester.pumpAndSettle();
      expect(store.sessions, hasLength(before + 1));
      final made = store.sessions.firstWhere(
        (s) => s.id != last.id && s.date == isoDate(DateTime.now()),
      );
      expect(
        [for (final a in made.attendance) a.playerId],
        [for (final a in last.attendance) a.playerId],
      );
      expect(made.games, isEmpty);
      expect(made.shuttles, 0);
      expect(made.attendance.every((a) => !a.paid && !a.resting), isTrue);
      expect(made.courtSplit, last.courtSplit);
      expect(made.shuttleSplit, last.shuttleSplit);
      expect(made.singlesCourts, [2]);
    });

    testWidgets('unticking "same players" makes the session with nobody '
        'checked in', (tester) async {
      final store = await pumpApp(tester);
      await store.seedDemo(today: '2026-11-19');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repeat-fill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repeat-players')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('save-session')));
      await tester.tap(find.byKey(const Key('save-session')));
      await tester.pumpAndSettle();
      expect(store.lastSession!.attendance, isEmpty);
    });

    testWidgets('season summary: ranges, per-player lines and the CSV copy', (
      tester,
    ) async {
      final copied = captureClipboard(tester);
      final store = await pumpApp(tester);
      await store.seedDemo(today: '2026-11-26');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-season')));
      await tester.pumpAndSettle();
      expect(find.text('Season summary'), findsOneWidget);
      // Last 3 months by default (the real today; the demo may be outside).
      final chip = tester.widget<ChoiceChip>(
        find.byKey(const Key('range-last3Months')),
      );
      expect(chip.selected, isTrue);

      await tester.tap(find.byKey(const Key('range-all')));
      await tester.pumpAndSettle();
      expect(find.textContaining('All time · 2 sessions'), findsOneWidget);
      expect(find.textContaining('Asked RM'), findsOneWidget);
      // Bee Ling came twice and still owes from last week.
      final bee = store.players.firstWhere((p) => p.name == 'Bee Ling');
      final tile = find.byKey(Key('season-${bee.id}'));
      await reveal(tester, tile);
      final text = tester.widget<ListTile>(
        find.descendant(of: tile, matching: find.byType(ListTile)),
      );
      expect(((text.subtitle! as Text).data)!, contains('2 sessions (100%)'));
      expect(((text.subtitle! as Text).data)!, contains('owes RM'));

      await reveal(tester, find.byKey(const Key('copy-csv')));
      await tester.tap(find.byKey(const Key('copy-csv')));
      await tester.pumpAndSettle();
      expect(
        find.text('Copied as CSV. Paste it into a spreadsheet.'),
        findsOneWidget,
      );
      final lines = copied.single.split('\r\n');
      expect(lines.first, startsWith('player,guest,sessions'));
      // Header, 8 players, trailing empty line.
      expect(lines, hasLength(10));
      expect(
        lines.where((l) => l.startsWith('Bee Ling,no,2,100,')),
        hasLength(1),
      );
    });

    testWidgets('season summary for a period with no sessions', (tester) async {
      final store = await pumpApp(tester);
      await store.seedDemo(today: '2020-01-15');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-season')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('range-thisMonth')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('season-empty')), findsOneWidget);
      expect(find.byKey(const Key('copy-csv')), findsNothing);
    });
  });
}
