import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/history.dart';
import 'package:gelanggang/src/domain/models.dart';

Future<Session> newSession(
  AppStore store, {
  String date = '2026-11-26',
  int guestFeeSen = 0,
}) => store.createSession(
  date: date,
  venue: 'Hall',
  startMinute: 1200,
  endMinute: 1320,
  courts: 2,
  courtRateSen: 2000,
  shuttles: 6,
  shuttlePriceSen: 450,
  guestFeeSen: guestFeeSen,
);

void main() {
  test('a guest on the roster checks in as a guest; old sessions keep what '
      'they were', () async {
    final store = AppStore(MemoryStorage());
    final aiman = await store.addPlayer('Aiman');
    final bee = await store.addPlayer('Bee Ling');
    final first = await newSession(store, date: '2026-11-19');
    await store.toggleAttendance(first.id, bee.id);

    await store.setPlayerGuest(bee.id, true);
    expect(store.players.firstWhere((p) => p.id == bee.id).guest, isTrue);
    expect(store.session(first.id)!.attendance.single.guest, isFalse);

    final second = await newSession(store, guestFeeSen: 1500);
    await store.toggleAttendance(second.id, aiman.id);
    await store.toggleAttendance(second.id, bee.id);
    final s = store.session(second.id)!;
    expect(
      {for (final a in s.attendance) a.playerId: a.guest},
      {aiman.id: false, bee.id: true},
    );
    expect(sharesFor(s), {aiman.id: 9200, bee.id: 1500});

    // Just for this session, Bee Ling counts as a regular.
    await store.setAttendanceGuest(second.id, bee.id, false);
    expect(sharesFor(store.session(second.id)!), {
      aiman.id: 5350,
      bee.id: 5350,
    });
    expect(store.players.firstWhere((p) => p.id == bee.id).guest, isTrue);
  });

  test('guest fee is validated', () async {
    final store = AppStore(MemoryStorage());
    expect(
      () => newSession(store, guestFeeSen: 10001),
      throwsA(
        isA<InputError>().having(
          (e) => e.message,
          'message',
          'Guest fee must be between RM0 and RM100',
        ),
      ),
    );
    expect(
      () => newSession(store, guestFeeSen: -1),
      throwsA(isA<InputError>()),
    );
    expect(store.sessions, isEmpty);
  });

  test('settle all marks every unpaid share of one player paid', () async {
    final store = AppStore(MemoryStorage());
    final aiman = await store.addPlayer('Aiman');
    final bee = await store.addPlayer('Bee Ling');
    for (final date in ['2026-11-12', '2026-11-19', '2026-11-26']) {
      final s = await newSession(store, date: date);
      await store.toggleAttendance(s.id, aiman.id);
      await store.toggleAttendance(s.id, bee.id);
    }
    expect(playerRecords(store.sessions)[aiman.id]!.owedSen, 3 * 5350);
    await store.settleAll(aiman.id);
    final r = playerRecords(store.sessions);
    expect(r[aiman.id]!.owedSen, 0);
    expect(r[bee.id]!.owedSen, 3 * 5350);
    final latest = store.sessions.first;
    expect(carriedOver(store.sessions, latest), {bee.id: 2 * 5350});
  });

  test('guest flags, modes and fee survive a save and reload', () async {
    final storage = MemoryStorage();
    final store = AppStore(storage);
    final aiman = await store.addPlayer('Aiman');
    await store.setPlayerGuest(aiman.id, true);
    final s = await newSession(store, guestFeeSen: 1200);
    await store.toggleAttendance(s.id, aiman.id);
    await store.updateSession(
      store
          .session(s.id)!
          .copyWith(
            courtSplit: SplitMode.byGames,
            shuttleSplit: SplitMode.byMinutes,
          ),
    );
    final again = AppStore(storage);
    await again.load();
    expect(again.players.single.guest, isTrue);
    final back = again.session(s.id)!;
    expect(back.attendance.single.guest, isTrue);
    expect(back.courtSplit, SplitMode.byGames);
    expect(back.shuttleSplit, SplitMode.byMinutes);
    expect(back.guestFeeSen, 1200);
    // Older app versions still find a mode they know.
    final doc = jsonDecode(storage.data!) as Map;
    expect(((doc['sessions'] as List).single as Map)['splitMode'], 'byGames');
  });

  group('older and damaged saved data', () {
    Map<String, Object?> sessionJson(Map<String, Object?> extra) => {
      'id': 2,
      'date': '2026-11-26',
      'venue': 'Hall',
      'start': 1200,
      'end': 1320,
      'courts': 2,
      'courtRateSen': 2000,
      'shuttles': 6,
      'shuttlePriceSen': 450,
      'attendance': [
        {'playerId': 1, 'arrive': 0, 'leave': 120, 'paid': false},
      ],
      ...extra,
    };
    String doc(
      Map<String, Object?> session, {
      Map<String, Object?> player = const {},
    }) => jsonEncode({
      'version': 1,
      'nextId': 3,
      'players': [
        {'id': 1, 'name': 'Aiman', ...player},
      ],
      'sessions': [session],
    });

    test('a session from before separate modes uses its one mode for both '
        'costs, with no guest fee', () async {
      final store = AppStore(
        MemoryStorage(doc(sessionJson({'splitMode': 'byMinutes'}))),
      );
      await store.load();
      final s = store.sessions.single;
      expect(s.courtSplit, SplitMode.byMinutes);
      expect(s.shuttleSplit, SplitMode.byMinutes);
      expect(s.guestFeeSen, 0);
      expect(s.attendance.single.guest, isFalse);
      expect(store.players.single.guest, isFalse);
    });

    test('an unknown mode name reads as equal', () async {
      final store = AppStore(
        MemoryStorage(
          doc(sessionJson({'courtSplit': 'bySkill', 'shuttleSplit': 7})),
        ),
      );
      await store.load();
      expect(store.sessions.single.courtSplit, SplitMode.equal);
      expect(store.sessions.single.shuttleSplit, SplitMode.equal);
    });

    test('a damaged fee or guest flag is ignored as a whole and never saved '
        'over', () async {
      for (final raw in [
        doc(sessionJson({'guestFeeSen': -500})),
        doc(sessionJson({'guestFeeSen': '15.00'})),
        doc(sessionJson({}), player: {'guest': 'yes'}),
        doc(
          sessionJson({
            'attendance': [
              {'playerId': 1, 'arrive': 0, 'leave': 120, 'guest': 1},
            ],
          }),
        ),
      ]) {
        final storage = MemoryStorage(raw);
        final store = AppStore(storage);
        await store.load();
        expect(store.isEmpty, isTrue, reason: raw);
        expect(storage.data, raw, reason: 'nothing was written');
      }
    });
  });
}
