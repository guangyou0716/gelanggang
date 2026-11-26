import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/history.dart';
import 'package:gelanggang/src/domain/models.dart';
import 'package:gelanggang/src/l10n/language.dart';
import 'package:gelanggang/src/l10n/ms.dart';
import 'package:gelanggang/src/l10n/zh.dart';
import 'package:material_ui/material_ui.dart';

const ms = Strings(AppLanguage.ms);
const zh = Strings(AppLanguage.zh);

Session hall({
  List<Attendance> attendance = const [],
  int guestFeeSen = 0,
  SplitMode shuttleSplit = SplitMode.equal,
}) => Session(
  id: 1,
  date: '2026-11-26',
  venue: 'Hall',
  startMinute: 1200,
  endMinute: 1320,
  courts: 1,
  courtRateSen: 3000,
  shuttles: 2,
  shuttlePriceSen: 500,
  guestFeeSen: guestFeeSen,
  shuttleSplit: shuttleSplit,
  attendance: attendance,
);

Attendance came(
  int id, {
  bool paid = false,
  int? paidSen,
  bool guest = false,
}) => Attendance(
  playerId: id,
  arriveMinute: 0,
  leaveMinute: 120,
  paid: paid,
  paidSen: paidSen,
  guest: guest,
);

void main() {
  group('catalogue', () {
    for (final (language, table) in [
      (AppLanguage.ms, msStrings),
      (AppLanguage.zh, zhStrings),
    ]) {
      test('${language.code}: every key is translated, nothing extra', () {
        final missing = K.values.where((k) => !table.containsKey(k));
        expect(missing, isEmpty, reason: 'missing in ${language.code}');
        expect(table.length, K.values.length);
      });

      test('${language.code}: placeholders match English exactly', () {
        for (final k in K.values) {
          expect(
            Strings.placeholdersOf(table[k]!),
            Strings.placeholdersOf(k.en),
            reason: '${language.code} ${k.name}: "${table[k]}"',
          );
        }
      });

      test('${language.code}: no empty text, no stray braces', () {
        for (final k in K.values) {
          final text = table[k]!;
          expect(text.trim(), isNotEmpty, reason: k.name);
          final stripped = text.replaceAll(RegExp(r'\{\w+\}'), '');
          expect(stripped, isNot(matches(RegExp(r'[{}]'))), reason: k.name);
        }
      });
    }

    test('English has no stray braces either', () {
      for (final k in K.values) {
        final stripped = k.en.replaceAll(RegExp(r'\{\w+\}'), '');
        expect(stripped, isNot(matches(RegExp(r'[{}]'))), reason: k.name);
      }
    });

    test('every key renders in every language once its placeholders are '
        'given', () {
      for (final language in AppLanguage.values) {
        final t = Strings(language);
        for (final k in K.values) {
          final args = {for (final p in Strings.placeholdersOf(k.en)) p: 'X'};
          final out = t(k, args);
          expect(out, isNot(contains('{')), reason: '${language.code} $k');
        }
      }
    });

    test('typed text that looks like a placeholder is shown as typed', () {
      final s = hall(attendance: [came(1)]);
      for (final t in [Strings.en, ms, zh]) {
        final text = settleUpText(s, {1: '{name} {n}'}, strings: t);
        expect(text, contains('{name} {n}'));
        expect(t(K.removeName, {'name': '{amount}'}), contains('{amount}'));
      }
    });

    test('a missing placeholder value is an error, not "{name}" on screen', () {
      expect(() => ms(K.removeName), throwsArgumentError);
    });

    test('every K used in lib/ exists and every key is used somewhere', () {
      final source = [
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              !f.path.endsWith('ms.dart') &&
              !f.path.endsWith('zh.dart'))
            f.readAsStringSync(),
      ].join('\n');
      final used = {
        for (final m in RegExp(r'\bK\.(\w+)').allMatches(source)) m.group(1)!,
      };
      final names = {for (final k in K.values) k.name};
      expect(used.difference(names), isEmpty, reason: 'unknown keys');
      expect(names.difference(used), isEmpty, reason: 'unused keys');
    });
  });

  group('dates', () {
    test('English keeps the ISO date; Malay and Chinese spell it out', () {
      expect(Strings.en.date('2026-11-26'), '2026-11-26');
      expect(ms.date('2026-11-26'), 'Khamis, 26 Nov 2026');
      expect(zh.date('2026-11-26'), '2026年11月26日（周四）');
      expect(ms.date('2026-08-02'), 'Ahad, 2 Ogo 2026');
      expect(zh.date('2026-08-02'), '2026年8月2日（周日）');
      expect(ms.date('2027-01-04'), 'Isnin, 4 Jan 2027');
    });

    test('something that is not a real date is shown as it is', () {
      for (final t in [Strings.en, ms, zh]) {
        expect(t.date('2026-02-30'), '2026-02-30');
        expect(t.date('soon'), 'soon');
      }
    });

    test('name tables are complete', () {
      expect(msWeekdays, hasLength(7));
      expect(msMonths, hasLength(12));
      expect(zhWeekdays, hasLength(7));
    });
  });

  group('counts', () {
    test('English says 1 player / 2 players; Malay and Chinese do not '
        'change the word', () {
      expect(Strings.en.players(1), '1 player');
      expect(Strings.en.players(2), '2 players');
      expect(ms.players(1), '1 pemain');
      expect(ms.players(2), '2 pemain');
      expect(zh.sessions(3), '3 场');
      expect(zh.games(1), '1 局');
    });
  });

  group('device language', () {
    test('the first device language the app has wins, else English', () {
      expect(languageForDevice(const [Locale('ms', 'MY')]), AppLanguage.ms);
      expect(
        languageForDevice(const [Locale('fr'), Locale('zh', 'CN')]),
        AppLanguage.zh,
      );
      expect(languageForDevice(const [Locale('fr')]), AppLanguage.en);
      expect(languageForDevice(const []), AppLanguage.en);
      expect(languageForDevice(null), AppLanguage.en);
    });

    test('the choice is saved, cleared, and an unknown saved code is '
        'treated as no choice', () async {
      final storage = MemoryLanguageStorage();
      final setting = LanguageSetting(storage);
      await setting.load();
      expect(setting.chosen, isNull);
      await setting.choose(AppLanguage.zh);
      expect(storage.code, 'zh');

      final later = LanguageSetting(storage);
      await later.load();
      expect(later.chosen, AppLanguage.zh);
      await later.choose(null);
      expect(storage.code, isNull);

      final odd = LanguageSetting(MemoryLanguageStorage('tlh'));
      await odd.load();
      expect(odd.chosen, isNull);
    });
  });

  group('errors', () {
    test('a store error is English by default and translates on request', () {
      const e = InputError(K.errEnterName);
      expect(e.message, 'Enter a name');
      expect(e.localize(ms), 'Masukkan nama');
      expect(e.localize(zh), '请输入姓名');
    });

    test('nested backup errors translate every part', () async {
      const text = '''
{"version": 1, "nextId": 3,
 "players": [{"id": 1, "name": "Aiman"}],
 "sessions": [{"id": 2, "date": "2026-11-26", "venue": "Hall",
   "start": 1320, "end": 1200, "courts": 1,
   "courtRateSen": 0, "shuttles": 0, "shuttlePriceSen": 0,
   "attendance": [], "games": []}]}''';
      try {
        AppStore.checkBackup(text);
        fail('should refuse');
      } on InputError catch (e) {
        expect(
          e.message,
          'Session 2026-11-26 (Hall): The session must end after it starts',
        );
        expect(
          e.localize(ms),
          'Sesi 2026-11-26 (Hall): Sesi mesti tamat selepas ia bermula',
        );
        expect(e.localize(zh), '场次 2026-11-26（Hall）：场次的结束时间必须晚于开始时间');
      }
    });

    test('a name stand-in ("This player") is translated too', () async {
      final store = AppStore(MemoryStorage());
      final ids = [
        for (final n in ['A1', 'B2', 'C3', 'D4']) (await store.addPlayer(n)).id,
      ];
      final s = await store.createSession(
        date: '2026-11-26',
        venue: 'Hall',
        startMinute: 1200,
        endMinute: 1320,
        courts: 1,
        courtRateSen: 0,
        shuttles: 0,
        shuttlePriceSen: 0,
      );
      for (final id in ids) {
        await store.toggleAttendance(s.id, id);
      }
      try {
        await store.startGame(
          s.id,
          court: 1,
          teamA: [ids[0], ids[1]],
          teamB: [ids[2], 999],
        );
        fail('should refuse');
      } on InputError catch (e) {
        expect(e.message, 'A player is not free to play');
        expect(e.localize(zh), '某位球员 现在不能上场');
      }
    });
  });

  group('group messages', () {
    final names = {1: 'Aiman', 2: 'Bee Ling', 3: 'Chandran'};

    test('settle-up in Malay', () {
      final s = hall(
        attendance: [
          came(1, paid: true, paidSen: 2000),
          came(2),
          came(3, guest: true),
        ],
        guestFeeSen: 1000,
      );
      expect(
        settleUpText(s, names, earlierSen: {2: 750}, strings: ms),
        'Badminton Khamis, 26 Nov 2026 20:00-22:00, Hall\n'
        'Gelanggang RM 60.00 + bulu tangkis RM 10.00 = RM 70.00\n'
        'Tetamu membayar kadar tetap RM 10.00.\n'
        'Dibahagi sama rata:\n'
        '- Aiman: RM 30.00 (dibayar RM 20.00, RM 10.00 lagi)\n'
        '- Bee Ling: RM 30.00 + RM 7.50 dari sesi lepas = RM 37.50\n'
        '- Chandran (tetamu): RM 10.00',
      );
    });

    test('settle-up in Chinese, separate split modes, paid and owing '
        'from before', () {
      final s = hall(
        attendance: [came(1, paid: true), came(2, paid: true, paidSen: 4000)],
        shuttleSplit: SplitMode.byGames,
      );
      expect(
        settleUpText(s, names, earlierSen: {1: 500}, strings: zh),
        '羽毛球 2026年11月26日（周四） 20:00-22:00，Hall\n'
        '场地 RM 60.00 + 用球 RM 10.00 = RM 70.00\n'
        '场地平均分摊，用球按打的局数分摊：\n'
        '- Aiman：RM 35.00（已付，谢谢！） · 之前场次仍欠 RM 5.00\n'
        '- Bee Ling：RM 35.00（已付，谢谢！需退还 RM 5.00）',
      );
    });

    test('English message is unchanged by default', () {
      final s = hall(attendance: [came(1), came(2)]);
      expect(
        settleUpText(s, names),
        settleUpText(s, names, strings: Strings.en),
      );
      expect(settleUpText(s, names), startsWith('Badminton 2026-11-26 '));
    });

    test('balances reminder in both', () {
      final sessions = [
        hall(attendance: [came(1), came(2, paid: true)]),
      ];
      expect(
        balancesText(sessions, names, strings: ms),
        'Baki badminton (RM 35.00 belum dikutip):\n'
        '- Aiman: RM 35.00 (1 sesi)',
      );
      expect(
        balancesText(sessions, names, strings: zh),
        '羽毛球欠款（共待收 RM 35.00）：\n'
        '- Aiman：RM 35.00（1 场）',
      );
    });
  });
}
