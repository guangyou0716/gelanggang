import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/data/store.dart';

Map<String, Object?> session({
  int id = 2,
  List<Object?> attendance = const [
    {'playerId': 1, 'arrive': 0, 'leave': 120, 'paid': false},
  ],
  List<Object?> games = const [],
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'date': '2026-11-26',
  'venue': 'Hall',
  'start': 1200,
  'end': 1320,
  'courts': 1,
  'courtRateSen': 3000,
  'shuttles': 0,
  'shuttlePriceSen': 0,
  'attendance': attendance,
  'games': games,
  ...extra,
};

String backup({
  Object? version = 1,
  int nextId = 3,
  List<Object?>? players,
  List<Object?>? sessions,
}) => jsonEncode({
  'app': 'gelanggang',
  'version': version,
  'nextId': nextId,
  'players':
      players ??
      [
        {'id': 1, 'name': 'Aiman'},
      ],
  'sessions': sessions ?? [session()],
});

Matcher inputError(Object message) =>
    throwsA(isA<InputError>().having((e) => e.message, 'message', message));

void main() {
  test('a backup of the demo restores to exactly the same data on another '
      'phone, and new ids never clash', () async {
    final from = AppStore(MemoryStorage());
    await from.seedDemo(today: '2026-11-26');
    final text = from.exportBackup();
    expect(text, contains('\n  "app": "gelanggang"'), reason: 'readable');
    expect(AppStore.checkBackup(text), (
      players: from.players.length,
      sessions: from.sessions.length,
    ));

    final storage = MemoryStorage();
    final to = AppStore(storage);
    await to.addPlayer('Someone Else');
    await to.restoreBackup(text);
    expect(to.exportBackup(), text);
    expect(storage.data, isNotNull);

    // The restored data survives a restart.
    final again = AppStore(storage);
    await again.load();
    expect(again.exportBackup(), text);

    final allIds = {
      for (final p in again.players) p.id,
      for (final s in again.sessions) s.id,
    };
    final fresh = await again.addPlayer('Zara');
    expect(allIds.contains(fresh.id), isFalse);
  });

  test('a too-small nextId is raised past every id in the backup', () async {
    final store = AppStore(MemoryStorage());
    await store.restoreBackup(backup(nextId: 1));
    final p = await store.addPlayer('Bee Ling');
    expect(p.id, 3);
  });

  test('a backup from before games and separate modes still restores', () {
    final legacy = jsonEncode({
      'version': 1,
      'nextId': 3,
      'players': [
        {'id': 1, 'name': 'Aiman'},
      ],
      'sessions': [
        session(extra: {'splitMode': 'byMinutes'})..remove('games'),
      ],
    });
    expect(AppStore.checkBackup(legacy), (players: 1, sessions: 1));
  });

  test('two games on two courts, finished games reusing a court and '
      'scores all restore', () {
    final text = backup(
      players: [
        for (var i = 1; i <= 8; i++) {'id': i * 10, 'name': 'P$i'},
      ],
      sessions: [
        session(
          extra: {'courts': 2},
          attendance: [
            for (var i = 1; i <= 8; i++)
              {'playerId': i * 10, 'arrive': 0, 'leave': 120},
          ],
          games: [
            {
              'id': 1,
              'court': 1,
              'a': [10, 20],
              'b': [30, 40],
              'finished': 1,
              'scoreA': 21,
              'scoreB': 19,
            },
            {
              'id': 2,
              'court': 1,
              'a': [10, 30],
              'b': [50, 60],
            },
            {
              'id': 3,
              'court': 2,
              'a': [20, 40],
              'b': [70, 80],
            },
          ],
        ),
      ],
      nextId: 90,
    );
    expect(AppStore.checkBackup(text), (players: 8, sessions: 1));
  });

  group('a bad backup is refused with a reason, and changes nothing', () {
    final cases = <String, (String, Object)>{
      'empty': ('  \n', 'Paste a backup first'),
      'not JSON': ('hello', contains('not a gelanggang backup')),
      'cut off': (
        backup().substring(0, backup().length ~/ 2),
        contains('not a gelanggang backup'),
      ),
      'a JSON list': ('[1, 2]', contains('not a gelanggang backup')),
      'missing sessions': (
        jsonEncode({'version': 1, 'nextId': 2, 'players': []}),
        contains('not a gelanggang backup'),
      ),
      'unknown version': (
        backup(version: 0),
        contains('not a gelanggang backup'),
      ),
      'newer version': (backup(version: 2), contains('newer version')),
      'wrong type': (
        backup(
          players: [
            {'id': '1', 'name': 'Aiman'},
          ],
        ),
        contains('not a gelanggang backup'),
      ),
      'negative payment': (
        backup(
          sessions: [
            session(
              attendance: [
                {
                  'playerId': 1,
                  'arrive': 0,
                  'leave': 120,
                  'paid': true,
                  'paidSen': -5,
                },
              ],
            ),
          ],
        ),
        contains('not a gelanggang backup'),
      ),
      'player twice': (
        backup(
          players: [
            {'id': 1, 'name': 'Aiman'},
            {'id': 3, 'name': 'aiman'},
          ],
          nextId: 4,
        ),
        'aiman is in the backup twice',
      ),
      'empty name': (
        backup(
          players: [
            {'id': 1, 'name': 'Aiman'},
            {'id': 3, 'name': '  '},
          ],
        ),
        contains('player name in the backup is not valid'),
      ),
      'repeated id': (
        backup(
          players: [
            {'id': 1, 'name': 'Aiman'},
            {'id': 2, 'name': 'Bee Ling'},
          ],
        ),
        'The backup repeats an id',
      ),
      'unknown player': (
        backup(
          sessions: [
            session(
              attendance: [
                {'playerId': 9, 'arrive': 0, 'leave': 120},
              ],
            ),
          ],
        ),
        'Session 2026-11-26 (Hall) lists a player who is not in the backup',
      ),
      'player twice in a session': (
        backup(
          sessions: [
            session(
              attendance: [
                {'playerId': 1, 'arrive': 0, 'leave': 120},
                {'playerId': 1, 'arrive': 0, 'leave': 60},
              ],
            ),
          ],
        ),
        'Session 2026-11-26 (Hall) lists a player twice',
      ),
      'ends before it starts': (
        backup(
          sessions: [
            session(extra: {'end': 1100}),
          ],
        ),
        'Session 2026-11-26 (Hall): The session must end after it starts',
      ),
      'impossible date': (
        backup(
          sessions: [
            session(extra: {'date': '2026-02-30'}),
          ],
        ),
        contains('Enter the date as YYYY-MM-DD'),
      ),
      'game with someone absent': (
        backup(
          players: [
            for (var i = 1; i <= 4; i++) {'id': i * 10, 'name': 'P$i'},
          ],
          sessions: [
            session(
              attendance: [
                for (var i = 1; i <= 3; i++)
                  {'playerId': i * 10, 'arrive': 0, 'leave': 120},
              ],
              games: [
                {
                  'id': 1,
                  'court': 1,
                  'a': [10, 20],
                  'b': [30, 40],
                  'finished': 1,
                },
              ],
            ),
          ],
          nextId: 50,
        ),
        contains('Everyone in a game must be at the session'),
      ),
      'game with a player twice': (
        backup(
          players: [
            for (var i = 1; i <= 4; i++) {'id': i * 10, 'name': 'P$i'},
          ],
          sessions: [
            session(
              attendance: [
                for (var i = 1; i <= 4; i++)
                  {'playerId': i * 10, 'arrive': 0, 'leave': 120},
              ],
              games: [
                {
                  'id': 1,
                  'court': 1,
                  'a': [10, 20],
                  'b': [30, 10],
                  'finished': 1,
                },
              ],
            ),
          ],
          nextId: 50,
        ),
        'Session 2026-11-26 (Hall) has a game that is not valid',
      ),

      'two games on one court at once': (
        backup(
          players: [
            for (var i = 1; i <= 8; i++) {'id': i * 10, 'name': 'P$i'},
          ],
          sessions: [
            session(
              extra: {'courts': 2},
              attendance: [
                for (var i = 1; i <= 8; i++)
                  {'playerId': i * 10, 'arrive': 0, 'leave': 120},
              ],
              games: [
                {
                  'id': 1,
                  'court': 1,
                  'a': [10, 20],
                  'b': [30, 40],
                },
                {
                  'id': 2,
                  'court': 1,
                  'a': [50, 60],
                  'b': [70, 80],
                },
              ],
            ),
          ],
          nextId: 90,
        ),
        'Session 2026-11-26 (Hall) has a game that is not valid',
      ),
      'one player in two games at once': (
        backup(
          players: [
            for (var i = 1; i <= 8; i++) {'id': i * 10, 'name': 'P$i'},
          ],
          sessions: [
            session(
              extra: {'courts': 2},
              attendance: [
                for (var i = 1; i <= 8; i++)
                  {'playerId': i * 10, 'arrive': 0, 'leave': 120},
              ],
              games: [
                {
                  'id': 1,
                  'court': 1,
                  'a': [10, 20],
                  'b': [30, 40],
                },
                {
                  'id': 2,
                  'court': 2,
                  'a': [10, 60],
                  'b': [70, 80],
                },
              ],
            ),
          ],
          nextId: 90,
        ),
        'Session 2026-11-26 (Hall) has a game that is not valid',
      ),
      'a drawn score': (
        backup(
          players: [
            for (var i = 1; i <= 8; i++) {'id': i * 10, 'name': 'P$i'},
          ],
          sessions: [
            session(
              extra: {'courts': 2},
              attendance: [
                for (var i = 1; i <= 8; i++)
                  {'playerId': i * 10, 'arrive': 0, 'leave': 120},
              ],
              games: [
                {
                  'id': 1,
                  'court': 1,
                  'a': [10, 20],
                  'b': [30, 40],
                  'finished': 1,
                  'scoreA': 21,
                  'scoreB': 21,
                },
              ],
            ),
          ],
          nextId: 90,
        ),
        'Session 2026-11-26 (Hall) has a game that is not valid',
      ),
      'half a score': (
        backup(
          players: [
            for (var i = 1; i <= 8; i++) {'id': i * 10, 'name': 'P$i'},
          ],
          sessions: [
            session(
              extra: {'courts': 2},
              attendance: [
                for (var i = 1; i <= 8; i++)
                  {'playerId': i * 10, 'arrive': 0, 'leave': 120},
              ],
              games: [
                {
                  'id': 1,
                  'court': 1,
                  'a': [10, 20],
                  'b': [30, 40],
                  'finished': 1,
                  'scoreA': 21,
                },
              ],
            ),
          ],
          nextId: 90,
        ),
        'Session 2026-11-26 (Hall) has a game that is not valid',
      ),
      'a score of 100': (
        backup(
          players: [
            for (var i = 1; i <= 8; i++) {'id': i * 10, 'name': 'P$i'},
          ],
          sessions: [
            session(
              extra: {'courts': 2},
              attendance: [
                for (var i = 1; i <= 8; i++)
                  {'playerId': i * 10, 'arrive': 0, 'leave': 120},
              ],
              games: [
                {
                  'id': 1,
                  'court': 1,
                  'a': [10, 20],
                  'b': [30, 40],
                  'finished': 1,
                  'scoreA': 100,
                  'scoreB': 98,
                },
              ],
            ),
          ],
          nextId: 90,
        ),
        'Session 2026-11-26 (Hall) has a game that is not valid',
      ),
      'a score on a game still on court': (
        backup(
          players: [
            for (var i = 1; i <= 8; i++) {'id': i * 10, 'name': 'P$i'},
          ],
          sessions: [
            session(
              extra: {'courts': 2},
              attendance: [
                for (var i = 1; i <= 8; i++)
                  {'playerId': i * 10, 'arrive': 0, 'leave': 120},
              ],
              games: [
                {
                  'id': 1,
                  'court': 1,
                  'a': [10, 20],
                  'b': [30, 40],
                  'scoreA': 21,
                  'scoreB': 15,
                },
              ],
            ),
          ],
          nextId: 90,
        ),
        'Session 2026-11-26 (Hall) has a game that is not valid',
      ),
      'a game id twice': (
        backup(
          players: [
            for (var i = 1; i <= 8; i++) {'id': i * 10, 'name': 'P$i'},
          ],
          sessions: [
            session(
              extra: {'courts': 2},
              attendance: [
                for (var i = 1; i <= 8; i++)
                  {'playerId': i * 10, 'arrive': 0, 'leave': 120},
              ],
              games: [
                {
                  'id': 1,
                  'court': 1,
                  'a': [10, 20],
                  'b': [30, 40],
                  'finished': 1,
                },
                {
                  'id': 1,
                  'court': 2,
                  'a': [50, 60],
                  'b': [70, 80],
                },
              ],
            ),
          ],
          nextId: 90,
        ),
        'Session 2026-11-26 (Hall) has a game that is not valid',
      ),
      'a name with stray spaces': (
        backup(
          players: [
            {'id': 1, 'name': 'Aiman'},
            {'id': 3, 'name': 'Bee  Ling '},
          ],
          nextId: 4,
        ),
        contains('player name in the backup is not valid'),
      ),
    };
    for (final MapEntry(key: name, value: (text, message)) in cases.entries) {
      test(name, () async {
        expect(() => AppStore.checkBackup(text), inputError(message));
        final storage = MemoryStorage();
        final store = AppStore(storage);
        await store.addPlayer('Kept');
        final before = storage.data;
        await expectLater(store.restoreBackup(text), inputError(message));
        expect(storage.data, before);
        expect(store.players.single.name, 'Kept');
      });
    }
  });

  group('saved data the app cannot read', () {
    test('is set aside, survives the next change and the next launch, and '
        'can be thrown away', () async {
      final newer = backup(version: 2);
      final storage = MemoryStorage(newer);
      final store = AppStore(storage);
      await store.load();
      expect(store.isEmpty, isTrue);
      expect(store.setAside, newer);

      await store.seedDemo(today: '2026-11-26');
      expect(store.isEmpty, isTrue, reason: 'no demo over real data');
      await store.addPlayer('Aiman');
      expect(storage.aside, newer);

      final relaunched = AppStore(storage);
      await relaunched.load();
      expect(relaunched.players.single.name, 'Aiman');
      expect(relaunched.setAside, newer);

      await relaunched.discardSetAside();
      expect(relaunched.setAside, isNull);
      expect(storage.aside, isNull);
    });

    test('readable data sets nothing aside', () async {
      final storage = MemoryStorage(backup());
      final store = AppStore(storage);
      await store.load();
      expect(store.players.single.name, 'Aiman');
      expect(store.setAside, isNull);
      expect(storage.aside, isNull);
    });

    test('the demo is only for a real first launch', () async {
      final first = AppStore(MemoryStorage());
      await first.load();
      await first.seedDemo(today: '2026-11-26');
      expect(first.isEmpty, isFalse);

      // An organiser who deleted everything does not get the demo back.
      final storage = MemoryStorage(
        jsonEncode({'version': 1, 'nextId': 1, 'players': [], 'sessions': []}),
      );
      final cleared = AppStore(storage);
      await cleared.load();
      await cleared.seedDemo(today: '2026-11-26');
      expect(cleared.isEmpty, isTrue);
    });
  });
}
