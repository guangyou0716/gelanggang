import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/domain/models.dart';
import 'package:gelanggang/src/domain/queue.dart';

Session session({
  int players = 8,
  int courts = 2,
  List<Game> games = const [],
}) => Session(
  id: 1,
  date: '2026-11-26',
  venue: 'Test Hall',
  startMinute: 1200,
  endMinute: 1320,
  courts: courts,
  courtRateSen: 2000,
  shuttles: 0,
  shuttlePriceSen: 0,
  attendance: [
    for (var p = 1; p <= players; p++)
      Attendance(playerId: p, arriveMinute: 0, leaveMinute: 120),
  ],
  games: games,
);

/// Starts the suggested game on every free court, like an organiser who
/// always accepts the suggestion.
Session fillCourts(Session s, {required void Function(Game) onStart}) {
  for (final c in freeCourts(s)) {
    final t = suggestNext(s);
    if (t == null) break;
    final id = s.games.fold<int>(0, (m, g) => max(m, g.id)) + 1;
    final g = Game(id: id, court: c, teamA: t.teamA, teamB: t.teamB);
    onStart(g);
    s = s.copyWith(games: [...s.games, g]);
  }
  return s;
}

/// Team A then team B, so suggestions can be compared by value.
List<int>? flat(Teams? t) => t == null ? null : [...t.teamA, ...t.teamB];

Session finish(Session s, Game g) {
  final seq = s.games.fold<int>(0, (m, x) => max(m, x.finishedSeq ?? 0));
  return s.copyWith(
    games: [for (final x in s.games) x.id == g.id ? x.finish(seq: seq + 1) : x],
  );
}

void main() {
  test('first game: the first four ticked in, nobody else', () {
    final s = session();
    expect(waitingOrder(s), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(flat(suggestNext(s)), [1, 2, 3, 4]);
    expect(freeCourts(s), [1, 2]);
  });

  test('players on court or sitting out are not in the queue', () {
    var s = session(
      games: [
        const Game(id: 1, court: 2, teamA: [1, 2], teamB: [3, 4]),
      ],
    );
    s = s.copyWith(
      attendance: [
        for (final a in s.attendance)
          a.playerId == 5 ? a.copyWith(resting: true) : a,
      ],
    );
    expect(onCourt(s), {1, 2, 3, 4});
    expect(freeCourts(s), [1]);
    expect(waitingOrder(s), [6, 7, 8]);
    expect(suggestNext(s), isNull, reason: 'only three free players');
  });

  test('whoever came off court longest ago goes first', () {
    // Game 1 (1-4) finished first, game 2 (5-8) second; 9 and 10 have not
    // played yet, so they have waited since the start.
    final s = session(
      players: 10,
      games: [
        const Game(
          id: 1,
          court: 1,
          teamA: [1, 2],
          teamB: [3, 4],
          finishedSeq: 1,
        ),
        const Game(
          id: 2,
          court: 2,
          teamA: [5, 6],
          teamB: [7, 8],
          finishedSeq: 2,
        ),
      ],
    );
    expect(waitingOrder(s), [9, 10, 1, 2, 3, 4, 5, 6, 7, 8]);
    expect(gamesPlayed(s), {
      1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 0, 10: 0, //
    });
  });

  test('same wait: fewer games first, then check-in order', () {
    // Games 1-4 (finished 1st) and 1+2 v 5+6 (finished 3rd) are in the log;
    // the organiser removed the game 5+6 v 7+8 (finished 2nd) as a mistake.
    // 7 and 8 have not played; 3 and 4 came off first; 1, 2, 5 and 6 came
    // off together, but 5 and 6 have one game and 1 and 2 have two.
    final s = session(
      games: [
        const Game(
          id: 1,
          court: 1,
          teamA: [1, 2],
          teamB: [3, 4],
          finishedSeq: 1,
        ),
        const Game(
          id: 3,
          court: 2,
          teamA: [1, 2],
          teamB: [5, 6],
          finishedSeq: 3,
        ),
      ],
    );
    expect(waitingOrder(s), [7, 8, 3, 4, 5, 6, 1, 2]);
  });

  test('pairing avoids repeat partners, then repeat opponents', () {
    // 1+2 were partners and 3+4 were partners: the next split must differ.
    final s = session(
      games: [
        const Game(
          id: 1,
          court: 1,
          teamA: [1, 2],
          teamB: [3, 4],
          finishedSeq: 1,
        ),
      ],
    );
    expect(flat(pairUp(s, [1, 2, 3, 4])), [1, 3, 2, 4]);
    // After 1+3 v 2+4 as well, only 1+4 v 2+3 has no repeat partners.
    final s2 = s.copyWith(
      games: [
        ...s.games,
        const Game(
          id: 2,
          court: 1,
          teamA: [1, 3],
          teamB: [2, 4],
          finishedSeq: 2,
        ),
      ],
    );
    expect(flat(pairUp(s2, [1, 2, 3, 4])), [1, 4, 2, 3]);
    expect(() => pairUp(s, [1, 2, 3]), throwsArgumentError);
    expect(() => pairUp(s, [1, 2, 3, 3]), throwsArgumentError);
  });

  test('games saved before the queue existed load with no games', () {
    final json = session().toJson()..remove('games');
    final back = Session.fromJson(jsonDecode(jsonEncode(json)));
    expect(back.games, isEmpty);
    expect(back.attendance.every((a) => !a.resting), isTrue);
  });

  test('a saved game with a wrong team size is refused when loading', () {
    for (final team in [
      [1],
      [1, 2, 3],
      ['x', 2],
    ]) {
      expect(
        () => Game.fromJson({
          'id': 1,
          'court': 1,
          'a': team,
          'b': [3, 4],
        }),
        throwsA(anything),
        reason: '$team',
      );
    }
  });

  test('a game and sitting out survive JSON', () {
    var s = session(
      games: [
        const Game(id: 1, court: 1, teamA: [1, 2], teamB: [3, 4]),
        const Game(
          id: 2,
          court: 2,
          teamA: [5, 6],
          teamB: [7, 8],
          finishedSeq: 1,
          scoreA: 21,
          scoreB: 19,
        ),
      ],
    );
    s = s.copyWith(
      attendance: [
        s.attendance.first.copyWith(resting: true),
        ...s.attendance.skip(1),
      ],
    );
    final back = Session.fromJson(
      (jsonDecode(jsonEncode(s.toJson())) as Map).cast<String, Object?>(),
    );
    expect(back.attendance.first.resting, isTrue);
    expect(back.games[0].finished, isFalse);
    expect(back.games[1].scoreA, 21);
    expect(back.games[1].scoreB, 19);
    expect(back.games[1].finishedSeq, 1);
    expect(back.games[1].teamB, [7, 8]);
  });

  group('property tests (random groups, 1-4 courts)', () {
    test('when games last the same time: games played never differ by more '
        'than one, and nobody plays twice while someone waits', () {
      final random = Random(2026);
      for (var run = 0; run < 1500; run++) {
        final players = 4 + random.nextInt(13);
        var s = session(players: players, courts: 1 + random.nextInt(4));
        final starts = <int, List<int>>{};
        for (var step = 0; step < 40; step++) {
          s = fillCourts(
            s,
            onStart: (g) {
              for (final p in g.players) {
                (starts[p] ??= []).add(g.id);
              }
            },
          );
          // The game that started first finishes first.
          s = finish(s, s.games.firstWhere((g) => !g.finished));
          final counts = gamesPlayed(s).values;
          expect(
            counts.reduce(max) - counts.reduce(min),
            lessThanOrEqualTo(1),
            reason: 'run $run step $step',
          );
        }
        // Between two games of any player, no one else started two games.
        for (final mine in starts.values) {
          for (var i = 0; i + 1 < mine.length; i++) {
            for (final theirs in starts.values) {
              final between = theirs
                  .where((g) => g > mine[i] && g < mine[i + 1])
                  .length;
              expect(between, lessThanOrEqualTo(1), reason: 'run $run');
            }
          }
        }
      }
    });

    test('in any finishing order: nobody jumps the queue, the suggestion is '
        'deterministic, and repeat partners are avoided when possible', () {
      final random = Random(42);
      for (var run = 0; run < 1500; run++) {
        var s = session(
          players: 4 + random.nextInt(13),
          courts: 1 + random.nextInt(4),
        );
        for (var step = 0; step < 40; step++) {
          // Fill the free courts one game at a time, checking each suggestion.
          while (freeCourts(s).isNotEmpty && suggestNext(s) != null) {
            final next = suggestNext(s)!;
            // Same session (even after a save and load): same suggestion.
            final reloaded = Session.fromJson(
              (jsonDecode(jsonEncode(s.toJson())) as Map)
                  .cast<String, Object?>(),
            );
            expect(flat(suggestNext(reloaded)), flat(next));

            // Nobody left waiting came off court earlier than a chosen one.
            final last = lastOffCourt(s);
            final chosen = [...next.teamA, ...next.teamB];
            final left = waitingOrder(s).where((p) => !chosen.contains(p));
            final latestChosen = chosen.map((p) => last[p] ?? 0).reduce(max);
            for (final p in left) {
              expect(
                last[p] ?? 0,
                greaterThanOrEqualTo(latestChosen),
                reason: 'run $run step $step: $p was skipped',
              );
            }

            // If some split of these four has no repeat partners, use one.
            final counts = pairCounts(s).partners;
            int partnered(List<int> t) =>
                counts[t[0] < t[1] ? (t[0], t[1]) : (t[1], t[0])] ?? 0;
            final c = [...chosen]..sort();
            final best = [
              partnered([c[0], c[1]]) + partnered([c[2], c[3]]),
              partnered([c[0], c[2]]) + partnered([c[1], c[3]]),
              partnered([c[0], c[3]]) + partnered([c[1], c[2]]),
            ].reduce(min);
            expect(
              partnered(next.teamA) + partnered(next.teamB),
              best,
              reason: 'run $run step $step',
            );
            final id = s.games.fold<int>(0, (m, g) => max(m, g.id)) + 1;
            s = s.copyWith(
              games: [
                ...s.games,
                Game(
                  id: id,
                  court: freeCourts(s).first,
                  teamA: next.teamA,
                  teamB: next.teamB,
                ),
              ],
            );
          }
          final active = [
            for (final g in s.games)
              if (!g.finished) g,
          ];
          if (active.isEmpty) break;
          s = finish(s, active[random.nextInt(active.length)]);
        }
      }
    });
  });
}
