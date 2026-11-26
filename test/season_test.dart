import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/models.dart';
import 'package:gelanggang/src/domain/season.dart';

Future<Session> session(AppStore store, String date, List<Player> who) async {
  final s = await store.createSession(
    date: date,
    venue: 'Hall',
    startMinute: 1200,
    endMinute: 1320,
    courts: 1,
    courtRateSen: 2000,
    shuttles: 3,
    shuttlePriceSen: 450,
    playerIds: [for (final p in who) p.id],
  );
  return s;
}

void main() {
  group('datesFor', () {
    test('ranges for a day in November', () {
      final today = DateTime(2026, 11, 26);
      expect(datesFor(SeasonRange.thisMonth, today), (
        from: '2026-11-01',
        to: '2026-11-30',
      ));
      expect(datesFor(SeasonRange.lastMonth, today), (
        from: '2026-10-01',
        to: '2026-10-31',
      ));
      expect(datesFor(SeasonRange.last3Months, today), (
        from: '2026-09-01',
        to: '2026-11-30',
      ));
      expect(datesFor(SeasonRange.thisYear, today), (
        from: '2026-01-01',
        to: '2026-12-31',
      ));
      expect(datesFor(SeasonRange.all, today), isNull);
    });

    test('ranges cross the year and know February and leap years', () {
      expect(datesFor(SeasonRange.lastMonth, DateTime(2027, 1, 3)), (
        from: '2026-12-01',
        to: '2026-12-31',
      ));
      expect(datesFor(SeasonRange.last3Months, DateTime(2027, 2, 10)), (
        from: '2026-12-01',
        to: '2027-02-28',
      ));
      expect(datesFor(SeasonRange.thisMonth, DateTime(2028, 2, 29)), (
        from: '2028-02-01',
        to: '2028-02-29',
      ));
      expect(datesFor(SeasonRange.lastMonth, DateTime(2026, 3, 31)), (
        from: '2026-02-01',
        to: '2026-02-28',
      ));
    });
  });

  group('SeasonSummary', () {
    test('counts only sessions in the range, both ends included', () async {
      final store = AppStore(MemoryStorage());
      final a = await store.addPlayer('Aiman');
      final b = await store.addPlayer('Bee Ling');
      await session(store, '2026-10-31', [a, b]);
      final first = await session(store, '2026-11-01', [a, b]);
      await session(store, '2026-11-30', [a]);
      await session(store, '2026-12-01', [a, b]);
      await store.setPaid(first.id, b.id, true);

      final s = SeasonSummary.of(
        store.sessions,
        store.players,
        SeasonRange.thisMonth,
        DateTime(2026, 11, 26),
      );
      expect(s.sessions, 2);
      expect([for (final r in s.rows) r.name], ['Aiman', 'Bee Ling']);
      final aiman = s.rows.first, bee = s.rows.last;
      expect(aiman.record.sessions, 2);
      expect(aiman.attendancePercent, 100);
      expect(bee.record.sessions, 1);
      expect(bee.attendancePercent, 50);
      // 1 court x 2 h x RM20 + 3 x RM4.50 = RM53.50 a session.
      expect(aiman.record.shareSen, 2675 + 5350);
      expect(aiman.record.owedSen, 2675 + 5350);
      expect(bee.record.shareSen, 2675);
      expect(bee.record.paidSen, 2675);
      expect(bee.record.owedSen, 0);
      expect(s.shareSen, 10700);
      expect(s.paidSen, 2675);
      expect(s.owedSen, 8025);
    });

    test('a player no longer in the roster still counts, named "?"', () {
      const gone = Session(
        id: 1,
        date: '2026-11-20',
        venue: 'Hall',
        startMinute: 1200,
        endMinute: 1260,
        courts: 1,
        courtRateSen: 1000,
        shuttles: 0,
        shuttlePriceSen: 0,
        attendance: [Attendance(playerId: 9, arriveMinute: 0, leaveMinute: 60)],
      );
      final s = SeasonSummary.of(
        [gone],
        const [],
        SeasonRange.all,
        DateTime(2026, 11, 26),
      );
      expect(s.rows.single.name, '?');
      expect(s.rows.single.record.owedSen, 1000);
    });

    test('random groups: shares add up to the cost of the sessions in range, '
        'and paid + owed = share for everyone', () async {
      final rng = Random(8);
      for (var round = 0; round < 40; round++) {
        final store = AppStore(MemoryStorage());
        final players = [
          for (var i = 0; i < 2 + rng.nextInt(8); i++)
            await store.addPlayer('P$i'),
        ];
        for (var i = 0; i < 1 + rng.nextInt(6); i++) {
          final who = [
            for (final p in players)
              if (rng.nextBool()) p,
          ];
          final s = await store.createSession(
            date:
                '2026-${(9 + rng.nextInt(4)).toString().padLeft(2, '0')}-'
                '${(1 + rng.nextInt(28)).toString().padLeft(2, '0')}',
            venue: 'Hall',
            startMinute: 1200,
            endMinute: 1200 + 30 * (1 + rng.nextInt(6)),
            courts: 1 + rng.nextInt(3),
            courtRateSen: rng.nextInt(5000),
            shuttles: rng.nextInt(10),
            shuttlePriceSen: rng.nextInt(800),
            guestFeeSen: rng.nextInt(3) * 500,
            courtSplit: SplitMode.values[rng.nextInt(SplitMode.values.length)],
            playerIds: [for (final p in who) p.id],
          );
          for (final p in who) {
            if (rng.nextInt(3) == 0) await store.setPaid(s.id, p.id, true);
          }
        }
        for (final range in SeasonRange.values) {
          final today = DateTime(2026, 11, 26);
          final summary = SeasonSummary.of(
            store.sessions,
            store.players,
            range,
            today,
          );
          final dates = datesFor(range, today);
          final inRange = [
            for (final s in store.sessions)
              if (dates == null ||
                  (s.date.compareTo(dates.from) >= 0 &&
                      s.date.compareTo(dates.to) <= 0))
                s,
          ];
          final cost = inRange
              .where((s) => s.attendance.isNotEmpty)
              .fold<int>(0, (sum, s) => sum + totalCostSen(s));
          expect(summary.sessions, inRange.length);
          expect(summary.shareSen, cost, reason: 'round $round $range');
          for (final r in summary.rows) {
            expect(r.record.paidSen + r.record.owedSen, r.record.shareSen);
            expect(r.record.paidSen, greaterThanOrEqualTo(0));
            expect(r.attendancePercent, inInclusiveRange(1, 100));
          }
        }
      }
    });
  });

  group('CSV', () {
    test('header, one line per player, CRLF, plain ringgit amounts', () async {
      final store = AppStore(MemoryStorage());
      final a = await store.addPlayer('Aiman');
      final g = await store.addPlayer('Iskandar');
      await store.setPlayerGuest(g.id, true);
      final s = await session(store, '2026-11-26', [a, g]);
      await store.setPaid(s.id, a.id, true);
      final csv = SeasonSummary.of(
        store.sessions,
        store.players,
        SeasonRange.all,
        DateTime(2026, 11, 26),
      ).toCsv();
      expect(
        csv,
        'player,guest,sessions,attendance_percent,games,wins,share_rm,'
        'paid_rm,owed_rm\r\n'
        'Aiman,no,1,100,0,0,26.75,26.75,0.00\r\n'
        'Iskandar,yes,1,100,0,0,26.75,0.00,26.75\r\n',
      );
    });

    test('names that a spreadsheet would run as a formula stay text; commas, '
        'quotes and line breaks are quoted', () {
      expect(csvField('Aiman'), 'Aiman');
      expect(
        csvField('=HYPERLINK("http://x")'),
        '"\'=HYPERLINK(""http://x"")"',
      );
      expect(csvField('+60123'), "'+60123");
      expect(csvField('-2'), "'-2");
      expect(csvField('@SUM(A1)'), "'@SUM(A1)");
      expect(csvField('\tTab'), "'\tTab");
      expect(csvField('\rCR'), '"\'\rCR"');
      expect(csvField('Lee, Ah Kow'), '"Lee, Ah Kow"');
      expect(csvField('Say "hi"'), '"Say ""hi"""');
      expect(csvField('two\nlines'), '"two\nlines"');
      expect(csvField(''), '');
    });

    test('an empty summary is just the header', () {
      final csv = SeasonSummary.of(
        const [],
        const [],
        SeasonRange.thisMonth,
        DateTime(2026, 11, 26),
      ).toCsv();
      expect(csv.split('\r\n'), hasLength(2));
      expect(csv, startsWith('player,guest,'));
    });
  });
}
