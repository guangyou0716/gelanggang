import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/models.dart';
import 'package:gelanggang/src/domain/queue.dart';

Session session({
  int players = 8,
  int courts = 2,
  List<int> singles = const [],
  List<Game> games = const [],
}) => Session(
  id: 1,
  date: '2026-11-26',
  venue: 'Test Hall',
  startMinute: 1200,
  endMinute: 1320,
  courts: courts,
  courtRateSen: 2000,
  shuttles: 7,
  shuttlePriceSen: 450,
  shuttleSplit: SplitMode.byGames,
  singlesCourts: singles,
  attendance: [
    for (var p = 1; p <= players; p++)
      Attendance(playerId: p, arriveMinute: 0, leaveMinute: 120),
  ],
  games: games,
);

List<int> flat(Teams t) => [...t.teamA, ...t.teamB];

Session finish(Session s, Game g) {
  final seq = s.games.fold<int>(0, (m, x) => max(m, x.finishedSeq ?? 0));
  return s.copyWith(
    games: [for (final x in s.games) x.id == g.id ? x.finish(seq: seq + 1) : x],
  );
}

Session start(Session s, int court, Teams t) {
  final id = s.games.fold<int>(0, (m, g) => max(m, g.id)) + 1;
  return s.copyWith(
    games: [
      ...s.games,
      Game(id: id, court: court, teamA: t.teamA, teamB: t.teamB),
    ],
  );
}

/// How long a player has waited, for comparing: smaller waited longer.
(int, int) waitKey(Session s, int p) =>
    (lastOffCourt(s)[p] ?? 0, gamesPlayed(s)[p] ?? 0);

int compareKeys((int, int) a, (int, int) b) =>
    a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2;

/// All [k]-sized groups of [items], in order.
Iterable<List<int>> groups(List<int> items, int k, [int from = 0]) sync* {
  if (k == 0) {
    yield [];
    return;
  }
  for (var i = from; i <= items.length - k; i++) {
    for (final rest in groups(items, k - 1, i + 1)) {
      yield [items[i], ...rest];
    }
  }
}

/// Recomputes the pairing cost of [t] independently of queue.dart's loop.
(int, int, int) splitCost(Session s, Teams t, Map<int, int> levels) {
  final counts = pairCounts(s);
  int get(Map<(int, int), int> m, int a, int b) =>
      m[a < b ? (a, b) : (b, a)] ?? 0;
  final partners =
      get(counts.partners, t.teamA[0], t.teamA[1]) +
      get(counts.partners, t.teamB[0], t.teamB[1]);
  var opponents = 0;
  for (final a in t.teamA) {
    for (final b in t.teamB) {
      opponents += get(counts.opponents, a, b);
    }
  }
  return (partners, levelGap(t.teamA, t.teamB, levels), opponents);
}

int compareCost((int, int, int) a, (int, int, int) b) => a.$1 != b.$1
    ? a.$1 - b.$1
    : a.$2 != b.$2
    ? a.$2 - b.$2
    : a.$3 - b.$3;

void main() {
  group('saved data', () {
    test('a player level round-trips and is left out when not set', () {
      const p = Player(id: 1, name: 'Aiman', level: 3);
      expect(p.toJson(), {'id': 1, 'name': 'Aiman', 'level': 3});
      expect(Player.fromJson(p.toJson()).level, 3);
      expect(p.withLevel(null).toJson(), {'id': 1, 'name': 'Aiman'});
      expect(p.copyWith(guest: true).level, 3, reason: 'guest keeps level');
      expect(Player.fromJson({'id': 1, 'name': 'Old'}).level, isNull);
    });

    test('singles courts and one-on-one games round-trip; older sessions '
        'read as all doubles', () {
      final s = session(
        singles: [2],
        games: [
          const Game(id: 1, court: 2, teamA: [1], teamB: [2]),
        ],
      );
      final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>;
      expect(json['singles'], [2]);
      final back = Session.fromJson(json);
      expect(back.singlesCourts, [2]);
      expect(back.isSingles(2), isTrue);
      expect(back.isSingles(1), isFalse);
      expect(back.games.single.singles, isTrue);
      expect(back.games.single.players, [1, 2]);
      final old = session().toJson();
      expect(old.containsKey('singles'), isFalse);
      expect(Session.fromJson(old).singlesCourts, isEmpty);
    });

    test('a game must be two against two or one on one', () {
      for (final (a, b) in [
        ([1], [2, 3]),
        ([1, 2, 3], [4, 5, 6]),
        (<int>[], <int>[]),
      ]) {
        expect(
          () => Game.fromJson({'id': 1, 'court': 1, 'a': a, 'b': b}),
          throwsFormatException,
          reason: '$a v $b',
        );
      }
    });
  });

  group('pairing four players', () {
    test('team level sums are balanced: 5+1 against 4+2', () {
      final s = session();
      final t = pairUp(s, [1, 2, 3, 4], levels: {1: 5, 2: 4, 3: 2, 4: 1});
      expect(t.teamA, [1, 4]);
      expect(t.teamB, [2, 3]);
      expect(levelGap(t.teamA, t.teamB, {1: 5, 2: 4, 3: 2, 4: 1}), 0);
      // Without levels: the first split, as before levels existed.
      expect(flat(pairUp(s, [1, 2, 3, 4])), [1, 2, 3, 4]);
    });

    test('avoiding a repeat partner comes before level balance', () {
      final s = session(
        games: [
          const Game(id: 1, court: 1, teamA: [1, 4], teamB: [5, 6]),
        ],
      );
      final levels = {1: 5, 2: 4, 3: 2, 4: 1};
      final t = pairUp(s, [1, 2, 3, 4], levels: levels);
      // 1+4 v 2+3 is level but repeats 1&4; 1+3 v 2+4 (7 v 5) beats
      // 1+2 v 3+4 (9 v 3).
      expect(flat(t), [1, 3, 2, 4]);
    });

    test('level balance comes before repeat opponents', () {
      final s = session(
        games: [
          const Game(id: 1, court: 1, teamA: [1, 5], teamB: [2, 6]),
          const Game(id: 2, court: 2, teamA: [4, 7], teamB: [3, 8]),
        ],
      );
      // 1+4 v 2+3 is the only level split, though 1-2 and 4-3 met before.
      final t = pairUp(s, [1, 2, 3, 4], levels: {1: 5, 2: 4, 3: 2, 4: 1});
      expect(flat(t), [1, 4, 2, 3]);
    });

    test('a player without a level counts as the average of the others', () {
      final levels = {1: 5, 2: 5, 3: 1};
      // Player 4 counts as 11/3: 5+5 v 1+3.7 is far worse than 5+1 v 5+3.7.
      expect(flat(pairUp(session(), [1, 2, 3, 4], levels: levels)), [
        1,
        3,
        2,
        4,
      ]);
      expect(levelGap([1, 2], [3, 4], levels), 30 - 14);
      expect(levelGap([1, 2], [3, 4], const {}), 0);
    });

    test('two players make a singles game; anything else is refused', () {
      final t = pairUp(session(), [3, 1]);
      expect(t.teamA, [3]);
      expect(t.teamB, [1]);
      for (final bad in [
        [1],
        [1, 1],
        [1, 2, 3],
        [1, 2, 3, 3],
      ]) {
        expect(() => pairUp(session(), bad), throwsArgumentError);
      }
    });

    test('singles games count opponents but no partners', () {
      final c = pairCounts(
        session(
          games: [
            const Game(id: 1, court: 1, teamA: [1], teamB: [2]),
          ],
        ),
      );
      expect(c.partners, isEmpty);
      expect(c.opponents, {(1, 2): 1});
    });
  });

  group('choosing who plays', () {
    test('a player without a level does not count towards the spread', () {
      expect(levelSpread([1, 2, 3], {1: 2, 3: 4}), 2);
      expect(levelSpread([1, 2], {1: 2}), 0);
      expect(levelSpread([1, 2], const {}), 0);
    });

    test('among players who waited equally long, a big level gap is avoided '
        'with the earliest group that has none', () {
      final s = session();
      // Everyone has a level here: a player without one does not count
      // towards the spread.
      final levels = {1: 1, 2: 5, 3: 5, 4: 5, 5: 5, 6: 1, 7: 1, 8: 3};
      // 1-4 would be 1 v 5 (a big gap); 1, 6, 7 and 8 (levels 1-3) is the
      // earliest ticked-in group without one.
      expect(levelSpread([1, 2, 3, 4], levels), 4);
      expect(choosePlayers(s, 4, levels: levels), [1, 6, 7, 8]);
      // No big gap in the first four: plain queue order.
      expect(choosePlayers(s, 4, levels: {1: 2, 2: 4, 3: 3, 4: 4, 5: 3}), [
        1,
        2,
        3,
        4,
      ]);
      // Every group has a big gap: the smallest one.
      // 1, 3, 4, 5 (levels 1-4) is the only group without a 1 v 5.
      expect(
        choosePlayers(
          session(players: 5),
          4,
          levels: {1: 1, 2: 5, 3: 1, 4: 4, 5: 1},
        ),
        [1, 3, 4, 5],
      );
      // Without levels: the first four ticked in.
      expect(choosePlayers(s, 4), [1, 2, 3, 4]);
    });

    test('nobody who waited longer is passed over for a closer level', () {
      // 1-4 played and came off; 5 and 6 (far apart) have waited longest.
      var s = session(
        players: 6,
        games: [
          const Game(id: 1, court: 1, teamA: [1, 2], teamB: [3, 4]),
        ],
      );
      s = finish(s, s.games.single);
      final levels = {1: 3, 2: 3, 3: 3, 4: 3, 5: 1, 6: 5};
      final chosen = choosePlayers(s, 4, levels: levels)!;
      expect(chosen.take(2), [5, 6]);
      expect(chosen, hasLength(4));
      // The other two are the equally-waiting 1-4: any two have spread 4.
      expect(chosen.skip(2), [1, 2]);
    });

    test('singles on a court: two players, no big gap among equals', () {
      final s = session(singles: [1]);
      final levels = {1: 1, 2: 4, 3: 4, 4: 2, 5: 5, 6: 3, 7: 5, 8: 2};
      expect(playersFor(s, 1), 2);
      expect(playersFor(s, 2), 4);
      final t = suggestNext(s, levels: levels)!;
      expect(t.teamA.length, 1);
      // 1 v 2 would be level 1 v 4; 1 v 4 (levels 1 and 2) is fine.
      expect(flat(t), [1, 4]);
      expect(flat(suggestNext(s, levels: levels, court: 2)!), hasLength(4));
      expect(choosePlayers(session(players: 1), 2), isNull);
    });

    test('the next court is the lowest free one, else the longest in play', () {
      var s = session(courts: 2);
      expect(nextCourt(s), 1);
      s = start(s, 2, (teamA: [1, 2], teamB: [3, 4]));
      s = start(s, 1, (teamA: [5, 6], teamB: [7, 8]));
      expect(freeCourts(s), isEmpty);
      expect(nextCourt(s), 2, reason: 'court 2 started first');
      s = finish(s, s.games.first);
      expect(nextCourt(s), 2);
    });
  });

  test('split by games counts a singles game as one game per player', () {
    var s = session(players: 6, singles: [2]);
    s = start(s, 1, (teamA: [1, 2], teamB: [3, 4]));
    s = start(s, 2, (teamA: [5], teamB: [6]));
    s = finish(s, s.games[1]);
    s = start(s, 2, (teamA: [5], teamB: [6]));
    expect(gamesPlayed(s), {1: 1, 2: 1, 3: 1, 4: 1, 5: 2, 6: 2});
    final shares = sharesFor(s);
    expect(shares.values.fold<int>(0, (a, b) => a + b), totalCostSen(s));
    final shuttle = {
      for (final e in shareBreakdown(s).entries) e.key: e.value.shuttleSen,
    };
    // 3150 sen over 8 games played: 393.75 per game.
    expect(shuttle.values.fold<int>(0, (a, b) => a + b), 3150);
    expect(shuttle[5]! - 2 * shuttle[1]!, inInclusiveRange(-1, 1));
  });

  test('property tests (random groups, levels, singles and doubles courts, '
      'any finishing order): fairness first, closest levels among equals, '
      'balanced teams, deterministic, and no levels means the old queue', () {
    final rng = Random(7);
    for (var round = 0; round < 150; round++) {
      final players = 2 + rng.nextInt(13);
      final courts = 1 + rng.nextInt(4);
      final singles = [
        for (var c = 1; c <= courts; c++)
          if (rng.nextInt(3) == 0) c,
      ];
      final levels = {
        for (var p = 1; p <= players; p++)
          if (rng.nextInt(4) != 0) p: 1 + rng.nextInt(5),
      };
      final useLevels = round.isEven ? levels : const <int, int>{};
      var s = session(players: players, courts: courts, singles: singles);
      for (var step = 0; step < 40; step++) {
        for (final c in freeCourts(s)) {
          final n = playersFor(s, c);
          final t = suggestNext(s, levels: useLevels, court: c);
          final waiting = waitingOrder(s);
          if (waiting.length < n) {
            expect(t, isNull);
            continue;
          }
          final chosen = flat(t!);
          expect(chosen, hasLength(n));
          expect(chosen.toSet(), hasLength(n));
          expect(t.teamA.length, t.teamB.length);
          expect(waiting.toSet().containsAll(chosen), isTrue);
          expect(
            flat(suggestNext(s, levels: useLevels, court: c)!),
            chosen,
            reason: 'deterministic',
          );
          // Fairness: everyone chosen waited at least as long as everyone
          // left waiting.
          final left = waiting.where((p) => !chosen.contains(p));
          for (final c1 in chosen) {
            for (final w in left) {
              expect(
                compareKeys(waitKey(s, c1), waitKey(s, w)) <= 0,
                isTrue,
                reason: '$c1 chosen over $w who waited longer',
              );
            }
          }
          if (useLevels.isEmpty) {
            expect(chosen.toSet(), waiting.take(n).toSet());
          } else {
            // Brute force over every fair group in ticked-in order: the
            // first without a big gap, else the first with the smallest gap.
            final cutKey = waitKey(s, waiting[n - 1]);
            final must = [
              for (final p in waiting)
                if (compareKeys(waitKey(s, p), cutKey) < 0) p,
            ];
            final tied = [
              for (final p in waiting)
                if (compareKeys(waitKey(s, p), cutKey) == 0) p,
            ].take(levelChoiceWindow).toList();
            final all = [
              for (final g in groups(tied, n - must.length)) [...must, ...g],
            ];
            final spreads = [for (final g in all) levelSpread(g, useLevels)];
            var want = spreads.indexWhere((x) => x < bigLevelGap);
            if (want < 0) want = spreads.indexOf(spreads.reduce(min));
            expect(chosen.toSet(), all[want].toSet());
            if (spreads.first < bigLevelGap) {
              expect(chosen.toSet(), waiting.take(n).toSet());
            }
          }
          if (n == 4) {
            // The split is the cheapest of the three (brute force).
            final cost = splitCost(s, t, useLevels);
            final four = [...t.teamA, ...t.teamB]..sort();
            for (final o in [
              (teamA: [four[0], four[1]], teamB: [four[2], four[3]]),
              (teamA: [four[0], four[2]], teamB: [four[1], four[3]]),
              (teamA: [four[0], four[3]], teamB: [four[1], four[2]]),
            ]) {
              expect(
                compareCost(cost, splitCost(s, o, useLevels)) <= 0,
                isTrue,
              );
            }
          }
          s = start(s, c, t);
        }
        final active = [
          for (final g in s.games)
            if (!g.finished) g,
        ];
        if (active.isEmpty) break;
        s = finish(s, active[rng.nextInt(active.length)]);
      }
      // Splits by games still add up exactly with singles mixed in.
      expect(
        sharesFor(s).values.fold<int>(0, (a, b) => a + b),
        totalCostSen(s),
      );
      final counted = <int, int>{};
      for (final g in s.games) {
        for (final p in g.players) {
          counted[p] = (counted[p] ?? 0) + 1;
        }
      }
      for (final e in gamesPlayed(s).entries) {
        expect(e.value, counted[e.key] ?? 0);
      }
    }
  });

  group('store', () {
    Future<(AppStore, int, List<int>)> setUp() async {
      final store = AppStore(MemoryStorage());
      final s = await store.createSession(
        date: '2026-11-26',
        venue: 'Hall',
        startMinute: 1200,
        endMinute: 1320,
        courts: 2,
        courtRateSen: 2000,
        shuttles: 4,
        shuttlePriceSen: 450,
      );
      final ids = <int>[];
      for (final name in ['A1', 'B2', 'C3', 'D4', 'E5', 'F6']) {
        final p = await store.addPlayer(name);
        await store.toggleAttendance(s.id, p.id);
        ids.add(p.id);
      }
      return (store, s.id, ids);
    }

    Matcher refused(String message) =>
        throwsA(isA<InputError>().having((e) => e.message, 'message', message));

    test('levels are set, cleared, checked and kept after a restart', () async {
      final storage = MemoryStorage();
      final store = AppStore(storage);
      final p = await store.addPlayer('Aiman');
      await store.setPlayerLevel(p.id, 5);
      expect(store.levels, {p.id: 5});
      for (final bad in [0, 6, -1]) {
        await expectLater(
          store.setPlayerLevel(p.id, bad),
          refused('The level for Aiman must be from 1 to 5'),
        );
      }
      final again = AppStore(storage);
      await again.load();
      expect(again.players.single.level, 5);
      await again.setPlayerLevel(p.id, null);
      expect(again.levels, isEmpty);
      expect(again.players.single.level, isNull);
    });

    test('a singles court: one-on-one games start, bad ones are refused, '
        'and fewer courts drop the setting', () async {
      final (store, sid, p) = await setUp();
      await store.setCourtSingles(sid, 2, true);
      expect(store.session(sid)!.singlesCourts, [2]);
      await store.setCourtSingles(sid, 2, true);
      expect(store.session(sid)!.singlesCourts, [2], reason: 'idempotent');
      await expectLater(
        store.startGame(sid, court: 2, teamA: [p[0]], teamB: [p[0]]),
        refused('A singles game needs two different players'),
      );
      await expectLater(
        store.startGame(sid, court: 2, teamA: [p[0]], teamB: [p[1], p[2]]),
        refused('A game is two against two, or one against one for singles'),
      );
      final g = await store.startGame(
        sid,
        court: 2,
        teamA: [p[0]],
        teamB: [p[1]],
      );
      expect(g.singles, isTrue);
      expect(onCourt(store.session(sid)!), {p[0], p[1]});
      await store.finishGame(sid, g.id, scoreA: 21, scoreB: 9);
      // Court 1 still plays doubles.
      final next = suggestNext(store.session(sid)!, court: 1)!;
      expect(flat(next), hasLength(4));
      await store.setCourtSingles(sid, 2, false);
      expect(store.session(sid)!.singlesCourts, isEmpty);
      await store.setCourtSingles(sid, 2, true);
      final s = store.session(sid)!;
      await store.updateSession(s.copyWith(courts: 1));
      expect(store.session(sid)!.singlesCourts, isEmpty);
    });

    test('the demo has levels for everyone but the guest and its amounts '
        'are unchanged by them', () async {
      final store = AppStore(MemoryStorage());
      await store.seedDemo(today: '2026-11-26');
      final guest = store.players.firstWhere((p) => p.guest);
      expect(guest.level, isNull);
      expect(store.levels, hasLength(store.players.length - 1));
      final today = store.sessions.first;
      expect(today.singlesCourts, isEmpty);
      expect(today.games.every((g) => !g.singles), isTrue);
    });
  });
}
