import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/models.dart';

Session session({
  int courts = 2,
  int rate = 2000,
  int start = 1200,
  int end = 1320,
  int shuttles = 6,
  int shuttlePrice = 450,
  SplitMode mode = SplitMode.equal,
  List<Attendance> attendance = const [],
}) => Session(
  id: 1,
  date: '2026-11-26',
  venue: 'Hall',
  startMinute: start,
  endMinute: end,
  courts: courts,
  courtRateSen: rate,
  shuttles: shuttles,
  shuttlePriceSen: shuttlePrice,
  splitMode: mode,
  attendance: attendance,
);

Attendance at(int id, [int arrive = 0, int leave = 120, bool paid = false]) =>
    Attendance(
      playerId: id,
      arriveMinute: arrive,
      leaveMinute: leave,
      paid: paid,
    );

void main() {
  test('court cost is courts x rate x hours, rounded half up', () {
    expect(courtCostSen(session()), 8000);
    // 1 court, RM 15/hour, 1h30 = RM 22.50.
    expect(courtCostSen(session(courts: 1, rate: 1500, end: 1290)), 2250);
    // RM 0.01/hour for 30 minutes = 0.5 sen -> 1 sen.
    expect(courtCostSen(session(courts: 1, rate: 1, end: 1230)), 1);
    // 20 minutes = 0.333 sen -> 0 sen.
    expect(courtCostSen(session(courts: 1, rate: 1, end: 1220)), 0);
    expect(shuttleCostSen(session()), 2700);
    expect(totalCostSen(session()), 10700);
  });

  test('equal split of the total among those present', () {
    final s = session(attendance: [at(1), at(2), at(3)]);
    expect(sharesFor(s), {1: 3567, 2: 3567, 3: 3566});
  });

  test('split by minutes charges late arrivals and early leavers less', () {
    final s = session(
      mode: SplitMode.byMinutes,
      attendance: [at(1), at(2, 60), at(3, 0, 90)],
    );
    final shares = sharesFor(s);
    expect(shares.values.reduce((a, b) => a + b), 10700);
    // 120 : 60 : 90 minutes = 4755.6 / 2377.8 / 3566.7 sen; the two leftover
    // sen go to the largest remainders (players 2 and 3).
    expect(shares, {1: 4755, 2: 2378, 3: 3567});
  });

  test(
    'nobody present means no shares; zero minutes everywhere splits equally',
    () {
      expect(sharesFor(session()), isEmpty);
      final s = session(
        mode: SplitMode.byMinutes,
        attendance: [at(1, 0, 0), at(2, 0, 0)],
      );
      expect(sharesFor(s), {1: 5350, 2: 5350});
    },
  );

  test('outstanding leaves out those marked paid', () {
    final s = session(attendance: [at(1, 0, 120, true), at(2), at(3)]);
    expect(outstandingSen(s), 3567 + 3566);
  });

  test('clock helpers', () {
    expect(formatClock(1200), '20:00');
    expect(formatClock(65), '01:05');
    expect(parseClock('8:30'), 510);
    expect(parseClock('20:00'), 1200);
    for (final bad in ['', '24:00', '12:60', '1230', 'ab:cd']) {
      expect(parseClock(bad), isNull, reason: bad);
    }
  });

  test('settle-up message lists everyone and marks who paid', () {
    final s = session(attendance: [at(1, 0, 120, true), at(2)]);
    final text = settleUpText(s, {1: 'Aiman', 2: 'Bee Ling'});
    expect(text, '''Badminton 2026-11-26 20:00-22:00, Hall
Courts RM 80.00 + shuttles RM 27.00 = RM 107.00
Split equally:
- Aiman: RM 53.50 (paid, thanks!)
- Bee Ling: RM 53.50''');
  });
}
