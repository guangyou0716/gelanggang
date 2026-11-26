import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/domain/history.dart';
import 'package:gelanggang/src/domain/models.dart';

/// 1 court x RM 30 x 1 h, no shuttles: RM 30 split equally.
Session session(
  int id,
  String date,
  List<int> players, {
  Set<int> paid = const {},
  List<Game> games = const [],
}) => Session(
  id: id,
  date: date,
  venue: 'Hall',
  startMinute: 1200,
  endMinute: 1260,
  courts: 1,
  courtRateSen: 3000,
  shuttles: 0,
  shuttlePriceSen: 0,
  attendance: [
    for (final p in players)
      Attendance(
        playerId: p,
        arriveMinute: 0,
        leaveMinute: 60,
        paid: paid.contains(p),
      ),
  ],
  games: games,
);

void main() {
  final week1 = session(
    1,
    '2026-11-12',
    [1, 2, 3, 4],
    paid: {1, 2},
    games: [
      const Game(
        id: 1,
        court: 1,
        teamA: [1, 2],
        teamB: [3, 4],
        finishedSeq: 1,
        scoreA: 21,
        scoreB: 15,
      ),
      // Still on court: counts as a game, not as a win.
      const Game(id: 2, court: 1, teamA: [1, 3], teamB: [2, 4]),
    ],
  );
  final week2 = session(5, '2026-11-19', [1, 3, 4], paid: {1, 4});
  // Made earlier (lower id) but played later: order goes by date.
  final week3 = session(2, '2026-11-26', [1, 3]);

  test('records add up sessions, games, wins and unpaid shares', () {
    final r = playerRecords([week3, week1, week2]);
    expect(r.keys.toSet(), {1, 2, 3, 4});
    expect(r[1]!.sessions, 3);
    expect(r[1]!.games, 2);
    expect(r[1]!.wins, 1);
    expect(r[1]!.owedSen, 1500);
    expect(r[1]!.lastDate, '2026-11-26');
    expect(r[3]!.owedSen, 750 + 1000 + 1500);
    expect(r[3]!.unpaidSessions, 3);
    expect(r[3]!.wins, 0);
    expect(r[4]!.owedSen, 750);
    expect(r[2]!.owedSen, 0);
  });

  test('carried over: only earlier, unpaid sessions of players present', () {
    final all = [week1, week2, week3];
    expect(carriedOver(all, week3), {3: 750 + 1000});
    expect(carriedOver(all, week2), {3: 750, 4: 750});
    expect(carriedOver(all, week1), isEmpty);
    // Same date: the session made first counts as earlier.
    final sameDay = session(6, '2026-11-26', [3]);
    expect(carriedOver([...all, sameDay], sameDay), {3: 750 + 1000 + 1500});
    expect(carriedOver([...all, sameDay], week3), {3: 1750});
  });

  test('balances message lists who owes, most first; null when paid up', () {
    final names = {1: 'Aiman', 2: 'Bee Ling', 3: 'Chandran', 4: 'Daniel'};
    expect(balancesText([week1, week2, week3], names), '''
Badminton balances (RM 55.00 to collect):
- Chandran: RM 32.50 (3 sessions)
- Aiman: RM 15.00 (1 session)
- Daniel: RM 7.50 (1 session)''');
    expect(
      balancesText([
        session(1, '2026-11-12', [1], paid: {1}),
      ], names),
      isNull,
    );
  });
}
