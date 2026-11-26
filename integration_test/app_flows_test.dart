// End-to-end flows on a real device (Linux desktop in CI): the app starts
// through the same loadApp() as main(), with the real shared_preferences
// plugin, and every check goes through the screens. "Reopen" builds a new
// app from what the plugin saved, as if the phone had restarted the app.
//
// Run: xvfb-run -a flutter test integration_test -d linux
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/bootstrap.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Today" for the demo group, so its dates are the same on every run.
final today = DateTime(2026, 11, 26, 19);

int _launches = 0;

/// Starts the app as the phone would: from what is saved on the device.
Future<void> launch(WidgetTester tester) async {
  // The integration binding leaves typing to the real keyboard; enterText()
  // needs the test text input, which the app cannot tell apart.
  if (!tester.testTextInput.isRegistered) tester.testTextInput.register();
  // A phone-shaped screen (432 x 960) inside the desktop window.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final app = await loadApp(now: today);
  // A new key: nothing is kept from the previous launch's widgets.
  await tester.pumpWidget(KeyedSubtree(key: ValueKey(_launches++), child: app));
  await tester.pumpAndSettle();
}

/// What the plugin wrote to disk under the app's [key]. The plugin keeps an
/// in-memory copy, so this reads its file (Linux: shared_preferences.json in
/// the app support folder; the app's keys carry a "flutter." prefix). Other
/// platforms keep their data elsewhere and return null here.
Future<String?> savedOnDisk(String key) async {
  if (!Platform.isLinux) return null;
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/shared_preferences.json');
  if (!file.existsSync()) return null;
  final data = jsonDecode(await file.readAsString()) as Map<String, Object?>;
  return data['flutter.$key'] as String?;
}

/// Expects the saved value of [key] to match, in the plugin's in-memory copy
/// and (on Linux) in its file on disk.
Future<void> expectSaved(String key, Matcher matches) async {
  expect((await SharedPreferences.getInstance()).getString(key), matches);
  if (Platform.isLinux) expect(await savedOnDisk(key), matches);
}

/// Scrolls the current screen's list down until [finder] shows.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isNotEmpty) return;
  // The screen's own list (text fields have Scrollables of their own).
  final list = find.byType(Scrollable).first;
  await tester.drag(list, const Offset(0, 5000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 150, scrollable: list);
  await tester.pumpAndSettle();
}

/// Scrolls to [finder] and expects exactly one.
Future<void> expectShown(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  expect(finder, findsOneWidget);
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The back button in whatever language the app is in.
Future<void> back(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).last);
  await tester.tap(
    find.byTooltip(MaterialLocalizations.of(context).backButtonTooltip).last,
  );
  await tester.pumpAndSettle();
}

String settleText(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byKey(const Key('settle-text'))).data!;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Each flow starts on a phone that has never run the app.
    await (await SharedPreferences.getInstance()).clear();
  });

  testWidgets('first launch, new session, check-in, court queue, split and '
      'settle, then the app reopens with everything kept', (tester) async {
    await launch(tester);
    // A true first launch shows the synthetic demo group.
    expect(find.textContaining('Demo Sports Hall'), findsOneWidget);
    await expectSaved('gelanggang.v1', contains('Demo Sports Hall'));

    // Roster: one new player; a duplicate is refused.
    await tester.tap(find.byTooltip('Players'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('player-name')), 'Jun Wei');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('player-name')), 'jun wei');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('jun wei is already on the list'), findsOneWidget);
    await back(tester);

    // New session: 2 courts x 2 h x RM 20 + 5 shuttles x RM 4 = RM 100.
    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-date')), '2026-11-27');
    await tester.enterText(
      find.byKey(const Key('field-venue')),
      'Dewan Ujian (synthetic)',
    );
    await tester.enterText(find.byKey(const Key('field-courts')), '2');
    await tester.enterText(find.byKey(const Key('field-rate')), '20');
    await tester.enterText(find.byKey(const Key('field-shuttles')), '5');
    await tester.enterText(find.byKey(const Key('field-shuttlePrice')), '4');
    await tapOn(tester, find.byKey(const Key('save-session')));
    expect(find.text('RM 100.00'), findsWidgets);

    // Check in five players.
    const came = ['Aiman', 'Bee Ling', 'Chandran', 'Daniel', 'Jun Wei'];
    for (final name in came) {
      await tapOn(tester, find.bySemanticsLabel('$name came'));
    }
    await expectShown(tester, find.text('Who came (5)'));

    // Court queue: start the suggested game, then finish it 21-15.
    await tapOn(tester, find.byKey(const Key('open-queue')));
    expect(find.text('Waiting (5)'), findsOneWidget);
    await tapOn(tester, find.byKey(const Key('start-game')));
    expect(find.text('Waiting (1)'), findsOneWidget);
    await tapOn(tester, find.byKey(const Key('finish-1')));
    await tester.enterText(find.byKey(const Key('score-a')), '21');
    await tester.enterText(find.byKey(const Key('score-b')), '15');
    await tester.tap(find.byKey(const Key('save-score')));
    await tester.pumpAndSettle();
    expect(find.text('Court 1 · 21-15'), findsOneWidget);
    expect(find.text('Games (1)'), findsOneWidget);
    await back(tester);

    // Split by games: the one who only waited pays nothing.
    for (final picker in ['court-split', 'shuttle-split']) {
      await tapOn(
        tester,
        find.descendant(
          of: find.byKey(Key(picker)),
          matching: find.text('By games'),
        ),
      );
    }
    await reveal(tester, find.byKey(const Key('settle-text')));
    expect(
      settleText(tester),
      allOf(
        contains('Courts RM 80.00 + shuttles RM 20.00 = RM 100.00'),
        contains('Split by games played:'),
        contains('- Daniel: RM 25.00\n'),
        contains('- Jun Wei: RM 0.00'),
        contains(
          '- Bee Ling: RM 25.00 + RM 24.98 from earlier sessions = RM 49.98',
        ),
      ),
    );

    // Daniel pays at the court.
    await tapOn(tester, find.bySemanticsLabel(RegExp('^Daniel paid')));
    await reveal(tester, find.byKey(const Key('settle-text')));
    expect(settleText(tester), contains('- Daniel: RM 25.00 (paid, thanks!)'));
    await back(tester);
    expect(find.textContaining('Dewan Ujian (synthetic)'), findsOneWidget);
    await expectSaved('gelanggang.v1', contains('Dewan Ujian (synthetic)'));
    expect(find.textContaining('RM 75.00 to collect'), findsOneWidget);

    // The app is closed and opened again: everything comes back from the
    // device, and the demo group is not added a second time.
    await launch(tester);
    expect(find.textContaining('Demo Sports Hall'), findsOneWidget);
    await tester.tap(find.textContaining('Dewan Ujian (synthetic)'));
    await tester.pumpAndSettle();
    await expectShown(tester, find.text('Who came (5)'));
    await reveal(tester, find.byKey(const Key('settle-text')));
    expect(
      settleText(tester),
      allOf(
        contains('Split by games played:'),
        contains('- Daniel: RM 25.00 (paid, thanks!)'),
        contains('- Jun Wei: RM 0.00'),
      ),
    );
    await tapOn(tester, find.byKey(const Key('open-queue')));
    expect(find.text('Court 1 · 21-15'), findsOneWidget);

    // A singles game: court 1 switched to singles pairs the one who has
    // waited longest (Jun Wei) with the first of the others; it is logged
    // and counts towards the split by games.
    await tapOn(tester, find.byKey(const Key('type-singles')));
    expect(find.text('Court 1 · singles'), findsOneWidget);
    String chip(int i) =>
        (tester.widget<ActionChip>(find.byKey(Key('next-$i'))).label as Text)
            .data!;
    expect([chip(0), chip(1)], ['Jun Wei', 'Aiman']);
    expect(find.byKey(const Key('next-2')), findsNothing);
    await tapOn(tester, find.byKey(const Key('start-game')));
    expect(find.text('Jun Wei vs Aiman'), findsOneWidget);
    await tapOn(tester, find.byKey(const Key('finish-1')));
    await tester.enterText(find.byKey(const Key('score-a')), '21');
    await tester.enterText(find.byKey(const Key('score-b')), '10');
    await tester.tap(find.byKey(const Key('save-score')));
    await tester.pumpAndSettle();
    expect(find.text('Court 1 · 21-10'), findsOneWidget);
    expect(find.text('Games (2)'), findsOneWidget);
    await expectSaved('gelanggang.v1', contains('"singles":[1]'));

    // Reopened again: the court is still singles and the game is kept.
    await launch(tester);
    await tester.tap(find.textContaining('Dewan Ujian (synthetic)'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('settle-text')));
    expect(settleText(tester), matches(RegExp(r'- Jun Wei: RM 16\.6[678]')));
    await tapOn(tester, find.byKey(const Key('open-queue')));
    expect(find.text('Court 1 · singles'), findsOneWidget);
    expect(find.text('Court 1 · 21-10'), findsOneWidget);
  });

  testWidgets('backup copied on one phone restores on another and survives '
      'a restart', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Players'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('player-name')), 'Jun Wei');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await back(tester);

    // Copy the backup through the real clipboard.
    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This phone has 9 players and 2 sessions'),
      findsOneWidget,
    );
    await tapOn(tester, find.byKey(const Key('copy-backup')));
    expect(
      find.text('Backup copied. Paste it somewhere safe.'),
      findsOneWidget,
    );
    final backup = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    expect(backup, contains('"name": "Jun Wei"'));

    // The other phone has never run the app: it starts with the demo group.
    await (await SharedPreferences.getInstance()).clear();
    await launch(tester);
    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This phone has 8 players and 2 sessions'),
      findsOneWidget,
    );

    // A cut-off paste is refused and changes nothing.
    await tester.enterText(
      find.byKey(const Key('restore-text')),
      backup!.substring(0, backup.length ~/ 2),
    );
    await tapOn(tester, find.byKey(const Key('restore')));
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.textContaining('This phone has 8 players and 2 sessions'),
      findsOneWidget,
    );

    // The whole backup asks first, then replaces everything.
    await tester.enterText(find.byKey(const Key('restore-text')), backup);
    await tapOn(tester, find.byKey(const Key('restore')));
    expect(
      find.textContaining(
        'The backup has 9 players and 2 sessions. It replaces the 8 players '
        'and 2 sessions on this phone',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-restore')));
    await tester.pumpAndSettle();
    expect(find.text('Backup restored.'), findsOneWidget);
    await expectSaved('gelanggang.v1', contains('"name":"Jun Wei"'));

    // After a restart the restored data is what the phone has.
    await launch(tester);
    await tester.tap(find.byTooltip('Players'));
    await tester.pumpAndSettle();
    await expectShown(tester, find.text('Jun Wei'));
    await back(tester);
    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This phone has 9 players and 2 sessions'),
      findsOneWidget,
    );
  });

  testWidgets('language switch changes the screens and the group message and '
      'is kept after a restart', (tester) async {
    await launch(tester);
    expect(find.text('New session'), findsOneWidget);

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-zh')));
    await tester.pumpAndSettle();
    expect(find.text('新场次'), findsOneWidget);
    expect(find.textContaining('2026年11月26日（周四）'), findsOneWidget);
    await expectSaved('gelanggang.language', equals('zh'));
    // Kept apart from the organiser's data.
    await expectSaved('gelanggang.v1', isNot(contains('"zh"')));

    // Restart: still Chinese; the settle-up message is Chinese too.
    await launch(tester);
    expect(find.text('新场次'), findsOneWidget);
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('settle-text')));
    expect(settleText(tester), contains('羽毛球'));
    await back(tester);

    // Bahasa Melayu, then back to following the device.
    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-ms')));
    await tester.pumpAndSettle();
    expect(find.text('Sesi baharu'), findsOneWidget);
    expect(find.textContaining('Khamis, 26 Nov 2026'), findsOneWidget);
    await expectSaved('gelanggang.language', equals('ms'));

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-device')));
    await tester.pumpAndSettle();
    await expectSaved('gelanggang.language', isNull);
    await launch(tester);
    // The CI machine's language is English (or one the app does not have).
    expect(find.text('New session'), findsOneWidget);
  });
}
