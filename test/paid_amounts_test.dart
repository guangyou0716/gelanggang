import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/history.dart';
import 'package:gelanggang/src/domain/models.dart';

Future<Session> newSession(AppStore store, {String date = '2026-11-26'}) =>
    store.createSession(
      date: date,
      venue: 'Hall',
      startMinute: 1200,
      endMinute: 1320,
      courts: 1,
      courtRateSen: 3000,
      shuttles: 0,
      shuttlePriceSen: 0,
    );

void main() {
  group('dueSen and overpaidSen', () {
    const base = Attendance(playerId: 1, arriveMinute: 0, leaveMinute: 60);
    test('unpaid owes the whole share', () {
      expect(dueSen(base, 2000), 2000);
      expect(overpaidSen(base, 2000), 0);
    });
    test('paid before amounts were kept counts as paid in full', () {
      final a = base.copyWith(paid: true);
      expect(a.paidSen, isNull);
      expect(dueSen(a, 2000), 0);
      expect(overpaidSen(a, 2000), 0);
    });
    test('paid an amount: what the share grew by is due, a drop is over', () {
      final a = base.copyWith(paid: true, paidSen: 1500);
      expect(dueSen(a, 1500), 0);
      expect(dueSen(a, 2000), 500);
      expect(overpaidSen(a, 2000), 0);
      expect(dueSen(a, 1000), 0);
      expect(overpaidSen(a, 1000), 500);
    });
    test('unticking paid forgets the amount', () {
      final a = base.copyWith(paid: true, paidSen: 1500).copyWith(paid: false);
      expect(a.paid, isFalse);
      expect(a.paidSen, isNull);
      expect(a.toJson().containsKey('paidSen'), isFalse);
      // Other edits keep it.
      final b = base
          .copyWith(paid: true, paidSen: 1500)
          .copyWith(resting: true);
      expect(b.paidSen, 1500);
    });
  });

  test('marking paid records the share; a late arrival makes it shrink and '
      'a changed split makes it grow', () async {
    final store = AppStore(MemoryStorage());
    final aiman = await store.addPlayer('Aiman');
    final bee = await store.addPlayer('Bee Ling');
    final chan = await store.addPlayer('Chandran');
    final s = await newSession(store); // RM 60.00 court hire.
    await store.toggleAttendance(s.id, aiman.id);
    await store.toggleAttendance(s.id, bee.id);
    await store.setPaid(s.id, aiman.id, true);
    expect(store.session(s.id)!.attendance.first.paidSen, 3000);
    expect(outstandingSen(store.session(s.id)!), 3000);

    // Chandran turns up for the second hour only: shares drop.
    await store.toggleAttendance(s.id, chan.id);
    var now = store.session(s.id)!;
    expect(sharesFor(now)[aiman.id], 2000);
    expect(overpaidSen(now.attendance.first, 2000), 1000);
    expect(outstandingSen(now), 4000);
    expect(
      settleUpText(now, store.names),
      contains('- Aiman: RM 20.00 (paid, thanks! RM 10.00 to give back)'),
    );

    // By time: Chandran was there 60 of 120 minutes, the others 120.
    final late = now.attendance.firstWhere((a) => a.playerId == chan.id);
    await store.updateAttendance(s.id, late.copyWith(arriveMinute: 60));
    await store.updateSession(
      store.session(s.id)!.copyWith(courtSplit: SplitMode.byMinutes),
    );
    now = store.session(s.id)!;
    expect(sharesFor(now), {aiman.id: 2400, bee.id: 2400, chan.id: 1200});
    expect(dueSen(now.attendance.first, 2400), 0);

    // Then Chandran is removed (he did not come after all): Aiman owes more.
    await store.toggleAttendance(s.id, chan.id);
    now = store.session(s.id)!;
    expect(sharesFor(now)[aiman.id], 3000);
    expect(outstandingSen(now), 3000);
    expect(
      settleUpText(now, store.names),
      contains('- Aiman: RM 30.00 (paid, thanks!)'),
    );
  });

  test('a share that grew after paying is still owed everywhere: session, '
      'player record, carried over and the reminder', () async {
    final store = AppStore(MemoryStorage());
    final aiman = await store.addPlayer('Aiman');
    final bee = await store.addPlayer('Bee Ling');
    final first = await newSession(store, date: '2026-11-19');
    await store.toggleAttendance(first.id, aiman.id);
    await store.toggleAttendance(first.id, bee.id);
    await store.setPaid(first.id, aiman.id, true); // paid RM 30.00
    // The organiser finds they booked a second court.
    await store.updateSession(store.session(first.id)!.copyWith(courts: 2));
    final s1 = store.session(first.id)!;
    expect(sharesFor(s1)[aiman.id], 6000);
    expect(dueSen(s1.attendance.first, 6000), 3000);
    expect(
      settleUpText(s1, store.names),
      contains('- Aiman: RM 60.00 (paid RM 30.00, RM 30.00 more)'),
    );

    final record = playerRecords(store.sessions)[aiman.id]!;
    expect(record.owedSen, 3000);
    expect(record.unpaidSessions, 1);

    final second = await newSession(store);
    await store.toggleAttendance(second.id, aiman.id);
    final s2 = store.session(second.id)!;
    // Bee Ling is not at the second session, so only Aiman carries over.
    expect(carriedOver(store.sessions, s2), {aiman.id: 3000});
    expect(
      settleUpText(s2, store.names, earlierSen: {aiman.id: 3000}),
      contains('- Aiman: RM 60.00 + RM 30.00 from earlier sessions = RM 90.00'),
    );
    expect(
      balancesText(store.sessions, store.names),
      contains('- Aiman: RM 90.00 (2 sessions)'),
    );

    // Paying a part-paid share again records the new amount in full.
    await store.setPaid(first.id, aiman.id, true);
    expect(store.session(first.id)!.attendance.first.paidSen, 6000);
    expect(playerRecords(store.sessions)[aiman.id]!.owedSen, 6000);
  });

  test('settle all pays every share with something due, at today\'s '
      'amounts, and leaves the rest alone', () async {
    final store = AppStore(MemoryStorage());
    final aiman = await store.addPlayer('Aiman');
    final bee = await store.addPlayer('Bee Ling');
    final a = await newSession(store, date: '2026-11-12');
    final b = await newSession(store, date: '2026-11-19');
    final c = await newSession(store, date: '2026-11-26');
    for (final s in [a, b, c]) {
      await store.toggleAttendance(s.id, aiman.id);
      await store.toggleAttendance(s.id, bee.id);
    }
    await store.setPaid(a.id, aiman.id, true); // paid in full: 3000
    await store.setPaid(b.id, aiman.id, true);
    await store.updateSession(store.session(b.id)!.copyWith(courts: 2));
    expect(playerRecords(store.sessions)[aiman.id]!.owedSen, 3000 + 3000);

    await store.settleAll(aiman.id);
    expect(playerRecords(store.sessions)[aiman.id]!.owedSen, 0);
    expect(store.session(a.id)!.attendance.first.paidSen, 3000);
    expect(store.session(b.id)!.attendance.first.paidSen, 6000);
    expect(store.session(c.id)!.attendance.first.paidSen, 3000);
    expect(playerRecords(store.sessions)[bee.id]!.owedSen, 3000 + 6000 + 3000);
  });

  group('saved amounts', () {
    String doc(Map<String, Object?> attendance) => jsonEncode({
      'version': 1,
      'nextId': 3,
      'players': [
        {'id': 1, 'name': 'Aiman'},
      ],
      'sessions': [
        {
          'id': 2,
          'date': '2026-11-26',
          'venue': 'Hall',
          'start': 1200,
          'end': 1320,
          'courts': 1,
          'courtRateSen': 3000,
          'shuttles': 0,
          'shuttlePriceSen': 0,
          'attendance': [
            {'playerId': 1, 'arrive': 0, 'leave': 120, ...attendance},
          ],
        },
      ],
    });

    test('round trip; an amount on an unpaid share is dropped', () async {
      final store = AppStore(
        MemoryStorage(doc({'paid': true, 'paidSen': 4000})),
      );
      await store.load();
      expect(store.sessions.single.attendance.single.paidSen, 4000);
      final dropped = AppStore(
        MemoryStorage(doc({'paid': false, 'paidSen': 4000})),
      );
      await dropped.load();
      expect(dropped.sessions.single.attendance.single.paidSen, isNull);
    });

    test('older data with paid and no amount stays paid in full', () async {
      final store = AppStore(MemoryStorage(doc({'paid': true})));
      await store.load();
      expect(outstandingSen(store.sessions.single), 0);
    });

    test('a damaged amount: nothing loads, it is set aside and survives the '
        'next change', () async {
      for (final bad in [-1, '30.00', 12.5]) {
        final raw = doc({'paid': true, 'paidSen': bad});
        final storage = MemoryStorage(raw);
        final store = AppStore(storage);
        await store.load();
        expect(store.isEmpty, isTrue, reason: '$bad');
        expect(store.setAside, raw);
        await store.addPlayer('Bee Ling');
        expect(storage.data, isNot(raw));
        expect(storage.aside, raw, reason: 'kept for the organiser');
      }
    });
  });
}
