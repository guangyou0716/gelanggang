import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/app.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/domain/models.dart';
import 'package:gelanggang/src/l10n/language.dart';
import 'package:gelanggang/src/l10n/ms.dart';
import 'package:gelanggang/src/l10n/zh.dart';
import 'package:material_ui/material_ui.dart';

import 'accessibility_test.dart' show expectNoSqueezedText, meetsGuidelines;
import 'helpers.dart' show reveal;

/// The demo group on a phone, in [code] (or following [device]).
Future<(AppStore, MemoryLanguageStorage)> pumpIn(
  WidgetTester tester, {
  String? code,
  List<Locale>? device,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  if (device != null) {
    tester.platformDispatcher.localesTestValue = device;
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }
  final storage = MemoryLanguageStorage(code);
  final language = LanguageSetting(storage);
  await language.load();
  final store = AppStore(MemoryStorage());
  await store.seedDemo(today: '2026-11-26');
  await tester.pumpWidget(GelanggangApp(store: store, language: language));
  await tester.pumpAndSettle();
  return (store, storage);
}

/// No English text from the catalogue is left on screen (texts that read
/// the same in [table], like "Badminton", are skipped).
void expectNoEnglish(Map<K, String> table, String screen) {
  for (final k in K.values) {
    if (Strings.placeholdersOf(k.en).isNotEmpty) continue;
    if (k.en.length < 4 || table[k] == k.en) continue;
    expect(find.text(k.en), findsNothing, reason: '$screen: "${k.en}"');
  }
}

/// Walks home, session, queue, players, one player and backup, checking
/// each with [check] and the given [texts] (screen to texts it must show).
Future<void> tour(
  WidgetTester tester,
  Map<String, List<String>> texts,
  Future<void> Function(String screen) check, {
  required String players,
  required String backup,
}) async {
  Future<void> expectTexts(String screen) async {
    for (final t in texts[screen]!) {
      if (find.textContaining(t).evaluate().isEmpty) {
        await reveal(tester, find.textContaining(t));
      }
      expect(find.textContaining(t), findsWidgets, reason: '$screen: $t');
    }
    await check(screen);
  }

  // pageBack() looks for the English "Back" tooltip.
  Future<void> back() async {
    final context = tester.element(find.byType(Scaffold).last);
    await tester.tap(
      find.byTooltip(MaterialLocalizations.of(context).backButtonTooltip).last,
    );
    await tester.pumpAndSettle();
  }

  await expectTexts('home');
  await tester.tap(find.textContaining('Demo Sports Hall'));
  await tester.pumpAndSettle();
  await expectTexts('session');
  await reveal(tester, find.byKey(const Key('open-queue')));
  await tester.tap(find.byKey(const Key('open-queue')));
  await tester.pumpAndSettle();
  await expectTexts('queue');
  await back();
  await back();
  await tester.tap(find.byTooltip(players));
  await tester.pumpAndSettle();
  await expectTexts('players');
  await tester.tap(find.text('Bee Ling'));
  await tester.pumpAndSettle();
  await expectTexts('player');
  await back();
  await back();
  await tester.tap(find.byTooltip(backup));
  await tester.pumpAndSettle();
  await expectTexts('backup');
}

const msTexts = {
  'home': ['Sesi baharu', 'Khamis, 26 Nov 2026 · Demo Sports Hall'],
  'session': [
    'Jumlah',
    'Belum dikutip',
    'Kos gelanggang',
    'Sama rata',
    'Ikut masa',
    'Siapa yang datang (8)',
    'Tetamu membayar kadar tetap RM 15.00',
  ],
  'queue': ['Giliran gelanggang', 'Seterusnya', 'Gelanggang 1', 'lwn'],
  'players': ['Salin peringatan', 'belum dikutip bagi semua sesi', 'tetamu'],
  'player': ['Sesi', 'Perlawanan', 'Hutang', 'Sejarah', 'Tetamu'],
  'backup': ['Sandarkan', 'Pulihkan', 'Salin sandaran', '8 pemain'],
};

const zhTexts = {
  'home': ['新场次', '2026年11月26日（周四） · Demo Sports Hall'],
  'session': ['总计', '待收', '场地费', '平均', '按时间', '到场球员（8）', '访客固定支付 RM 15.00'],
  'queue': ['排队上场', '下一组', '1 号场', '对'],
  'players': ['复制提醒', '所有场次共待收', '访客'],
  'player': ['场次', '局数', '欠款', '记录', '访客'],
  'backup': ['备份', '恢复', '复制备份', '8 名球员'],
};

void main() {
  for (final (code, table, texts, players, backup) in [
    ('ms', msStrings, msTexts, 'Pemain', 'Sandaran dan pemulihan'),
    ('zh', zhStrings, zhTexts, '球员', '备份与恢复'),
  ]) {
    testWidgets('$code: every screen is translated and meets the '
        'accessibility guidelines', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpIn(tester, code: code);
      await tour(
        tester,
        texts,
        (screen) async {
          expectNoEnglish(table, screen);
          await meetsGuidelines(tester, '$code $screen');
        },
        players: players,
        backup: backup,
      );
      semantics.dispose();
    });

    testWidgets('$code: twice the text size, nothing overflows or is '
        'squeezed', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpIn(tester, code: code);
      await tour(
        tester,
        texts,
        (screen) async {
          expect(tester.takeException(), isNull, reason: screen);
          final list = find.byType(Scrollable);
          for (var i = 0; i < 40; i++) {
            expectNoSqueezedText(tester, '$code $screen');
            if (list.evaluate().isEmpty) break;
            final pos = tester.state<ScrollableState>(list.first).position;
            if (pos.pixels >= pos.maxScrollExtent) break;
            await tester.drag(list.first, const Offset(0, -400));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: screen);
          }
          // Back to the top so the next tap finds its target.
          if (list.evaluate().isNotEmpty) {
            await tester.drag(list.first, const Offset(0, 40000));
            await tester.pumpAndSettle();
          }
        },
        players: players,
        backup: backup,
      );
    });
  }

  testWidgets('the group message and the reminder come out in the chosen '
      'language', (tester) async {
    await pumpIn(tester, code: 'ms');
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('settle-text')));
    final message = tester
        .widget<SelectableText>(find.byKey(const Key('settle-text')))
        .data!;
    expect(message, startsWith('Badminton Khamis, 26 Nov 2026 20:00-22:00'));
    expect(message, contains('Gelanggang dibahagi ikut masa bermain'));
    expect(message, contains('- Iskandar (tetamu): RM 15.00'));
    expect(message, isNot(contains('Courts')));
  });

  testWidgets('follows the device language until one is picked, and the '
      'pick is kept', (tester) async {
    final (_, storage) = await pumpIn(
      tester,
      device: const [Locale('ms', 'MY')],
    );
    expect(find.text('Sesi baharu'), findsOneWidget);
    expect(storage.code, isNull);

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    expect(find.text('Ikut peranti ini (Bahasa Melayu)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('language-zh')));
    await tester.pumpAndSettle();
    expect(find.text('新场次'), findsOneWidget);
    expect(storage.code, 'zh');
    // Material's own texts follow too.
    expect(
      MaterialLocalizations.of(tester.element(find.text('新场次')))
          .backButtonTooltip,
      '返回',
    );

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    expect(find.text('跟随本设备（Bahasa Melayu）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('language-device')));
    await tester.pumpAndSettle();
    expect(find.text('Sesi baharu'), findsOneWidget);
    expect(storage.code, isNull);
  });

  testWidgets('a device language the app does not have falls back to '
      'English', (tester) async {
    await pumpIn(tester, device: const [Locale('fr', 'FR')]);
    expect(find.text('New session'), findsOneWidget);
  });

  testWidgets('a saved choice wins over the device language', (tester) async {
    await pumpIn(tester, code: 'en', device: const [Locale('zh', 'CN')]);
    expect(find.text('New session'), findsOneWidget);
  });

  testWidgets('errors from the store are shown in the chosen language', (
    tester,
  ) async {
    await pumpIn(tester, code: 'zh');
    await tester.tap(find.byTooltip('球员'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('player-name')), 'aiman');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('aiman 已在名单中'), findsOneWidget);
  });

  testWidgets('a part-paid share can be set straight back to not paid', (
    tester,
  ) async {
    final (store, _) = await pumpIn(tester, code: 'en');
    final s = store.sessions.first;
    final aiman = store.players.firstWhere((p) => p.name == 'Aiman');
    // Aiman paid, then the split changed so his share went up.
    await store.setPaid(s.id, aiman.id, true);
    final a = store
        .session(s.id)!
        .attendance
        .firstWhere((a) => a.playerId == aiman.id);
    await store.updateAttendance(
      s.id,
      a.copyWith(paidSen: (a.paidSen ?? 0) - 100),
    );
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(Key('due-${aiman.id}')));
    await tester.tap(find.byTooltip('More for Aiman'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('not-paid-${aiman.id}')));
    await tester.pumpAndSettle();
    final after = store
        .session(s.id)!
        .attendance
        .firstWhere((a) => a.playerId == aiman.id);
    expect(after.paid, isFalse);
    expect(after.paidSen, isNull);
    expect(find.byKey(Key('due-${aiman.id}')), findsNothing);

    // Not offered for someone who has not paid.
    await reveal(tester, find.byTooltip('More for Aiman'));
    await tester.tap(find.byTooltip('More for Aiman'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as not paid'), findsNothing);
    expect(find.text('Count as a guest'), findsOneWidget);
  });

  test('the demo attendance helper is as expected', () {
    // Guards the part-paid test above: copyWith keeps paid and changes the
    // amount.
    const a = Attendance(
      playerId: 1,
      arriveMinute: 0,
      leaveMinute: 60,
      paid: true,
      paidSen: 500,
    );
    expect(a.copyWith(paidSen: 400).paid, isTrue);
  });
}
