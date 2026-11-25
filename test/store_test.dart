import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/models.dart';

Future<Session> newSession(AppStore store, {String date = '2026-11-26'}) =>
    store.createSession(
      date: date,
      venue: 'Hall',
      startMinute: 1200,
      endMinute: 1320,
      courts: 2,
      courtRateSen: 2000,
      shuttles: 6,
      shuttlePriceSen: 450,
    );

void main() {
  test('players: trimmed, unique (ignoring case), sorted, safe to remove only if unused', () async {
    final store = AppStore(MemoryStorage());
    await store.addPlayer('  farah   binti  ');
    await store.addPlayer('Aiman');
    expect(store.players.map((p) => p.name), ['Aiman', 'farah binti']);
    expect(() => store.addPlayer('AIMAN'), throwsA(isA<InputError>()));
    expect(() => store.addPlayer('   '), throwsA(isA<InputError>()));
    expect(() => store.addPlayer('x' * 41), throwsA(isA<InputError>()));

    final s = await newSession(store);
    final aiman = store.players.first;
    await store.toggleAttendance(s.id, aiman.id);
    expect(store.canRemovePlayer(aiman.id), isFalse);
    expect(() => store.removePlayer(aiman.id), throwsA(isA<InputError>()));
    await store.removePlayer(store.players.last.id);
    expect(store.players, hasLength(1));
  });

  test('sessions are validated', () async {
    final store = AppStore(MemoryStorage());
    Future<Session> bad({
      String date = '2026-11-26',
      String venue = 'Hall',
      int start = 1200,
      int end = 1320,
      int courts = 1,
      int shuttles = 0,
      int rate = 100,
      int shuttlePrice = 0,
    }) => store.createSession(
      date: date,
      venue: venue,
      startMinute: start,
      endMinute: end,
      courts: courts,
      courtRateSen: rate,
      shuttles: shuttles,
      shuttlePriceSen: shuttlePrice,
    );
    for (final call in [
      () => bad(date: '26/11/2026'),
      () => bad(date: '2026-13-01'),
      () => bad(date: '2026-02-30'),
      () => bad(venue: '  '),
      () => bad(end: 1200),
      () => bad(courts: 0),
      () => bad(courts: 21),
      () => bad(shuttles: -1),
      () => bad(rate: -1),
      () => bad(rate: 100001),
      () => bad(shuttlePrice: -1),
    ]) {
      await expectLater(call(), throwsA(isA<InputError>()));
    }
    expect(store.sessions, isEmpty);
  });

  test(
    'attendance: join for the whole session, change times within it, leave',
    () async {
      final store = AppStore(MemoryStorage());
      final p = await store.addPlayer('Aiman');
      final s = await newSession(store);
      await store.toggleAttendance(s.id, p.id);
      var a = store.session(s.id)!.attendance.single;
      expect((a.arriveMinute, a.leaveMinute), (0, 120));
      await store.updateAttendance(
        s.id,
        a.copyWith(arriveMinute: 30, paid: true),
      );
      a = store.session(s.id)!.attendance.single;
      expect((a.arriveMinute, a.paid), (30, true));
      await expectLater(
        store.updateAttendance(s.id, a.copyWith(leaveMinute: 121)),
        throwsA(isA<InputError>()),
      );
      await expectLater(
        store.updateAttendance(
          s.id,
          a.copyWith(arriveMinute: 100, leaveMinute: 90),
        ),
        throwsA(isA<InputError>()),
      );
      await store.toggleAttendance(s.id, p.id);
      expect(store.session(s.id)!.attendance, isEmpty);
    },
  );

  test(
    'everything survives a save and reload; sessions newest first',
    () async {
      final storage = MemoryStorage();
      final store = AppStore(storage);
      final p = await store.addPlayer('Aiman');
      final older = await newSession(store, date: '2026-11-19');
      final newer = await newSession(store);
      await store.toggleAttendance(newer.id, p.id);
      await store.updateSession(
        store.session(newer.id)!.copyWith(splitMode: SplitMode.byMinutes),
      );

      final again = AppStore(storage);
      await again.load();
      expect(again.players.single.name, 'Aiman');
      expect(again.sessions.map((s) => s.id), [newer.id, older.id]);
      final s = again.session(newer.id)!;
      expect(s.splitMode, SplitMode.byMinutes);
      expect(s.attendance.single.playerId, p.id);
      // New ids keep counting up after a reload.
      expect((await again.addPlayer('Bee Ling')).id, greaterThan(newer.id));
    },
  );

  test(
    'unreadable or future-version data is ignored, not crashed on',
    () async {
      for (final raw in [
        'not json',
        '{"version": 99}',
        '{"version": 1}',
        '[]',
      ]) {
        final store = AppStore(MemoryStorage(raw));
        await store.load();
        expect(store.isEmpty, isTrue, reason: raw);
      }
    },
  );

  test(
    'demo data: synthetic players, one session split by time, only when empty',
    () async {
      final store = AppStore(MemoryStorage());
      await store.seedDemo(today: '2026-11-26');
      expect(store.players, hasLength(8));
      final s = store.sessions.single;
      expect(s.splitMode, SplitMode.byMinutes);
      expect(sharesFor(s).values.reduce((a, b) => a + b), totalCostSen(s));
      expect(outstandingSen(s), lessThan(totalCostSen(s)));
      await store.seedDemo(today: '2026-11-27');
      expect(store.sessions, hasLength(1));
    },
  );
}
