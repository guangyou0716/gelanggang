import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/queue.dart';

/// Six players ticked in to a two-court session; returns the session id and
/// the player ids in check-in order.
Future<(int, List<int>)> setUp6(AppStore store) async {
  final s = await store.createSession(
    date: '2026-11-26',
    venue: 'Hall',
    startMinute: 1200,
    endMinute: 1320,
    courts: 2,
    courtRateSen: 2000,
    shuttles: 6,
    shuttlePriceSen: 450,
  );
  final ids = <int>[];
  for (final name in ['A1', 'B2', 'C3', 'D4', 'E5', 'F6']) {
    final p = await store.addPlayer(name);
    await store.toggleAttendance(s.id, p.id);
    ids.add(p.id);
  }
  return (s.id, ids);
}

Matcher refused(String message) =>
    throwsA(isA<InputError>().having((e) => e.message, 'message', message));

void main() {
  test('start, finish with a score, and the queue moves on', () async {
    final store = AppStore(MemoryStorage());
    final (sid, p) = await setUp6(store);
    final g = await store.startGame(
      sid,
      court: 1,
      teamA: [p[0], p[1]],
      teamB: [p[2], p[3]],
    );
    expect(waitingOrder(store.session(sid)!), [p[4], p[5]]);
    await store.finishGame(sid, g.id, scoreA: 21, scoreB: 15);
    final s = store.session(sid)!;
    expect(s.games.single.finishedSeq, 1);
    expect((s.games.single.scoreA, s.games.single.scoreB), (21, 15));
    // E5 and F6 have waited since the start, so they lead the queue.
    expect(waitingOrder(s), [p[4], p[5], p[0], p[1], p[2], p[3]]);
    // A second finish gets the next sequence number.
    final g2 = await store.startGame(
      sid,
      court: 2,
      teamA: [p[4], p[5]],
      teamB: [p[0], p[1]],
    );
    await store.finishGame(sid, g2.id);
    expect(store.session(sid)!.games.last.finishedSeq, 2);
    expect(store.session(sid)!.games.last.scoreA, isNull);
  });

  test('bad games are refused with a clear message', () async {
    final store = AppStore(MemoryStorage());
    final (sid, p) = await setUp6(store);
    await expectLater(
      store.startGame(sid, court: 1, teamA: [p[0], p[0]], teamB: [p[2], p[3]]),
      refused('A game needs four different players'),
    );
    await expectLater(
      store.startGame(sid, court: 3, teamA: [p[0], p[1]], teamB: [p[2], p[3]]),
      refused('Court 3 is not free'),
    );
    final g = await store.startGame(
      sid,
      court: 1,
      teamA: [p[0], p[1]],
      teamB: [p[2], p[3]],
    );
    await expectLater(
      store.startGame(sid, court: 1, teamA: [p[4], p[5]], teamB: [p[0], p[1]]),
      refused('Court 1 is not free'),
    );
    await expectLater(
      store.startGame(sid, court: 2, teamA: [p[4], p[5]], teamB: [p[0], p[1]]),
      refused('A1 is not free to play'),
    );
    await store.setResting(sid, p[5], true);
    final stranger = await store.addPlayer('Not Here');
    await expectLater(
      store.startGame(
        sid,
        court: 2,
        teamA: [p[4], p[5]],
        teamB: [stranger.id, p[0]],
      ),
      refused('F6 is not free to play'),
    );
    for (final (a, b, message) in [
      (21, null, 'Enter both scores or neither'),
      (21, 21, 'A badminton game cannot end in a draw'),
      (100, 98, 'Scores must be between 0 and 99'),
      (-1, 21, 'Scores must be between 0 and 99'),
    ]) {
      await expectLater(
        store.finishGame(sid, g.id, scoreA: a, scoreB: b),
        refused(message),
      );
    }
    await store.finishGame(sid, g.id);
    await expectLater(
      store.finishGame(sid, g.id),
      refused('This game is already finished'),
    );
    expect(store.session(sid)!.games, hasLength(1));
  });

  test('a player with games cannot be unticked; courts cannot shrink under a '
      'game; removing games undoes both', () async {
    final store = AppStore(MemoryStorage());
    final (sid, p) = await setUp6(store);
    final g = await store.startGame(
      sid,
      court: 2,
      teamA: [p[0], p[1]],
      teamB: [p[2], p[3]],
    );
    await expectLater(
      store.toggleAttendance(sid, p[0]),
      refused('A1 has games in this session; remove those games first'),
    );
    await expectLater(
      store.updateSession(store.session(sid)!.copyWith(courts: 1)),
      refused('Court 2 still has a game on; finish it first'),
    );
    // Finished games may sit on a court that no longer exists.
    await store.finishGame(sid, g.id);
    await store.updateSession(store.session(sid)!.copyWith(courts: 1));
    await store.removeGame(sid, g.id);
    await store.toggleAttendance(sid, p[0]);
    expect(store.session(sid)!.attendance, hasLength(5));
  });

  test(
    'sitting out: still pays, not in the queue, survives a reload',
    () async {
      final storage = MemoryStorage();
      final store = AppStore(storage);
      final (sid, p) = await setUp6(store);
      await store.setResting(sid, p[0], true);
      final s = store.session(sid)!;
      expect(waitingOrder(s), isNot(contains(p[0])));
      expect(sharesFor(s)[p[0]], greaterThan(0));

      final again = AppStore(storage);
      await again.load();
      expect(
        again
            .session(sid)!
            .attendance
            .firstWhere((a) => a.playerId == p[0])
            .resting,
        isTrue,
      );
      await again.setResting(sid, p[0], false);
      expect(waitingOrder(again.session(sid)!).first, p[0]);
    },
  );

  test('saved data with a broken game is ignored, not crashed on', () async {
    final storage = MemoryStorage();
    final store = AppStore(storage);
    final (sid, p) = await setUp6(store);
    await store.startGame(
      sid,
      court: 1,
      teamA: [p[0], p[1]],
      teamB: [p[2], p[3]],
    );
    final doc = (jsonDecode(storage.data!) as Map).cast<String, Object?>();
    final game =
        (((doc['sessions']! as List).single as Map)['games'] as List).single
            as Map;
    game['a'] = [p[0]];
    final broken = AppStore(MemoryStorage(jsonEncode(doc)));
    await broken.load();
    // Nothing is half loaded: not even the (valid) players.
    expect(broken.isEmpty, isTrue);
    expect(broken.players, isEmpty);
  });

  test('demo data includes a game log and a game on court', () async {
    final store = AppStore(MemoryStorage());
    await store.seedDemo(today: '2026-11-26');
    final s = store.sessions.single;
    expect(s.games.where((g) => g.finished), hasLength(2));
    expect(onCourt(s), hasLength(4));
    expect(waitingOrder(s), hasLength(4));
    expect(freeCourts(s), [2]);
    // Four players are on their second game, the other four played once.
    expect(gamesPlayed(s).values.toList()..sort(), [1, 1, 1, 1, 2, 2, 2, 2]);
  });
}
