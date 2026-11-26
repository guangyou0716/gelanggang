import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/models.dart';

Attendance at(int id, {bool guest = false, int arrive = 0, int leave = 120}) =>
    Attendance(
      playerId: id,
      arriveMinute: arrive,
      leaveMinute: leave,
      guest: guest,
    );

Game game(int id, List<int> a, List<int> b) =>
    Game(id: id, court: 1, teamA: a, teamB: b, finishedSeq: id);

/// 2 courts x RM 20 x 2 h = RM 80 courts, 6 x RM 4.50 = RM 27 shuttles.
Session session({
  List<Attendance> attendance = const [],
  List<Game> games = const [],
  SplitMode court = SplitMode.equal,
  SplitMode shuttle = SplitMode.equal,
  int guestFee = 0,
  int shuttles = 6,
}) => Session(
  id: 1,
  date: '2026-11-26',
  venue: 'Hall',
  startMinute: 1200,
  endMinute: 1320,
  courts: 2,
  courtRateSen: 2000,
  shuttles: shuttles,
  shuttlePriceSen: 450,
  courtSplit: court,
  shuttleSplit: shuttle,
  guestFeeSen: guestFee,
  attendance: attendance,
  games: games,
);

int sum(Iterable<int> xs) => xs.fold(0, (a, b) => a + b);

void main() {
  group('by games played', () {
    test('shuttles follow games while courts stay equal', () {
      final s = session(
        attendance: [for (var i = 1; i <= 5; i++) at(i)],
        // Players 1-4 play twice, player 5 once (with 1, 2, 3).
        games: [
          game(1, [1, 2], [3, 4]),
          game(2, [1, 3], [2, 4]),
          game(3, [5, 1], [2, 3]),
        ],
        shuttle: SplitMode.byGames,
      );
      final b = shareBreakdown(s);
      // Courts: RM 80 / 5.
      expect([for (var i = 1; i <= 5; i++) b[i]!.courtSen], everyElement(1600));
      // Shuttles RM 27 by games 3:3:3:2:1 (12 player-games).
      expect(
        [for (var i = 1; i <= 5; i++) b[i]!.shuttleSen],
        [675, 675, 675, 450, 225],
      );
      expect(sum(sharesFor(s).values), totalCostSen(s));
    });

    test('no games logged yet: falls back to an equal split', () {
      final s = session(
        attendance: [at(1), at(2), at(3)],
        court: SplitMode.byGames,
        shuttle: SplitMode.byGames,
      );
      expect(sharesFor(s).values, [3567, 3567, 3566]);
    });

    test('someone who played no games pays nothing for that cost', () {
      final s = session(
        attendance: [at(1), at(2), at(3), at(4), at(5)],
        games: [
          game(1, [1, 2], [3, 4]),
        ],
        shuttle: SplitMode.byGames,
      );
      expect(shareBreakdown(s)[5]!.shuttleSen, 0);
      expect(shareBreakdown(s)[1]!.shuttleSen, 675);
    });
  });

  group('guest fee', () {
    test('guests pay the flat fee, regulars share the rest', () {
      final s = session(
        attendance: [at(1), at(2), at(3), at(4, guest: true)],
        guestFee: 1500,
      );
      expect(guestFeeApplies(s), isTrue);
      expect(guestFeesCoverAll(s), isFalse);
      final b = shareBreakdown(s);
      expect(b[4], (courtSen: 0, shuttleSen: 0, guestFeeSen: 1500));
      // RM 107 - RM 15 = RM 92 over three: court pot RM 65, shuttles RM 27.
      expect(sum([for (var i = 1; i <= 3; i++) b[i]!.courtSen]), 6500);
      expect(sum([for (var i = 1; i <= 3; i++) b[i]!.shuttleSen]), 2700);
      expect(sharesFor(s), {1: 3067, 2: 3067, 3: 3066, 4: 1500});
    });

    test('fees beyond the court hire come off the shuttles', () {
      final s = session(
        attendance: [at(1), at(2, guest: true), at(3, guest: true)],
        guestFee: 5000,
      );
      final b = shareBreakdown(s);
      expect(b[1], (courtSen: 0, shuttleSen: 700, guestFeeSen: 0));
      expect(sum(sharesFor(s).values), 10700);
    });

    test('fees worth more than the session: guests split it, regulars '
        'pay nothing', () {
      final s = session(
        attendance: [at(1), at(2, guest: true), at(3, guest: true)],
        guestFee: 6000,
      );
      expect(sharesFor(s), {1: 0, 2: 5350, 3: 5350});
      expect(guestFeesCoverAll(s), isTrue);
      expect(settleUpText(s, {}), contains('Guests share the whole cost.'));
      expect(settleUpText(s, {}), isNot(contains('flat')));
    });

    test('no fee, no guests or only guests: everyone shares alike', () {
      for (final s in [
        session(attendance: [at(1), at(2, guest: true)]),
        session(attendance: [at(1), at(2)], guestFee: 1500),
        session(
          attendance: [at(1, guest: true), at(2, guest: true)],
          guestFee: 1500,
        ),
      ]) {
        expect(guestFeeApplies(s), isFalse);
        expect(sharesFor(s).values, [5350, 5350]);
      }
    });
  });

  test('randomised: shares add up, nobody is charged below zero, guests pay '
      'at most the fee, and the result is the same every time', () {
    final rng = Random(26);
    for (var run = 0; run < 2000; run++) {
      final n = 1 + rng.nextInt(12);
      final attendance = [
        for (var i = 1; i <= n; i++)
          at(
            i,
            guest: rng.nextInt(4) == 0,
            arrive: rng.nextInt(60),
            leave: 60 + rng.nextInt(61),
          ),
      ];
      final games = <Game>[];
      if (n >= 4) {
        for (var g = 1; g <= rng.nextInt(8); g++) {
          final four = ([for (var i = 1; i <= n; i++) i]..shuffle(rng)).take(4);
          final p = four.toList();
          games.add(game(g, [p[0], p[1]], [p[2], p[3]]));
        }
      }
      final s = session(
        attendance: attendance,
        games: games,
        court: SplitMode.values[rng.nextInt(3)],
        shuttle: SplitMode.values[rng.nextInt(3)],
        guestFee: rng.nextBool() ? 0 : rng.nextInt(6000),
        shuttles: rng.nextInt(20),
      );
      final shares = sharesFor(s);
      expect(sum(shares.values), totalCostSen(s), reason: 'run $run');
      expect(shares.values.every((v) => v >= 0), isTrue);
      expect(shares.keys.toSet(), {for (final a in attendance) a.playerId});
      if (guestFeeApplies(s)) {
        for (final a in attendance.where((a) => a.guest)) {
          expect(shares[a.playerId], lessThanOrEqualTo(s.guestFeeSen));
        }
      }
      expect(sharesFor(s), shares);
    }
  });

  test('message: separate modes, the guest fee and amounts from before', () {
    final s = session(
      attendance: [
        at(1),
        at(2),
        at(3, guest: true),
        const Attendance(
          playerId: 4,
          arriveMinute: 0,
          leaveMinute: 120,
          paid: true,
        ),
      ],
      court: SplitMode.byMinutes,
      shuttle: SplitMode.byGames,
      guestFee: 1500,
    );
    final text = settleUpText(
      s,
      {1: 'Aiman', 2: 'Bee Ling', 3: 'Chandran', 4: 'Daniel'},
      earlierSen: {2: 1000, 4: 450},
    );
    expect(
      text,
      '''
Badminton 2026-11-26 20:00-22:00, Hall
Courts RM 80.00 + shuttles RM 27.00 = RM 107.00
Guests pay a flat RM 15.00.
Courts split by time played, shuttles by games played:
- Aiman: RM 30.67
- Bee Ling: RM 30.67 + RM 10.00 from earlier sessions = RM 40.67
- Chandran (guest): RM 15.00
- Daniel: RM 30.66 (paid, thanks!) · RM 4.50 still owed from earlier sessions''',
    );
  });
}
