import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/app.dart';
import 'package:gelanggang/src/data/store.dart';
import 'package:gelanggang/src/l10n/language.dart';
import 'package:gelanggang/src/ui/appearance.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accessibility_test.dart' show meetsGuidelines;

/// The demo group on a phone with the appearance saved as [saved].
Future<(AppStore, MemoryAppearanceStorage, MemoryLanguageStorage)> pumpWith(
  WidgetTester tester, {
  String? saved,
  Brightness device = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = device;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final storage = MemoryAppearanceStorage(saved);
  final appearance = AppearanceSetting(storage);
  await appearance.load();
  final languageStorage = MemoryLanguageStorage();
  final language = LanguageSetting(languageStorage);
  final store = AppStore(MemoryStorage());
  await store.seedDemo(today: '2026-11-26');
  await tester.pumpWidget(
    GelanggangApp(store: store, language: language, appearance: appearance),
  );
  await tester.pumpAndSettle();
  return (store, storage, languageStorage);
}

Brightness shown(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

void main() {
  group('Appearance.fromCode', () {
    test('reads the saved codes', () {
      for (final a in Appearance.values) {
        expect(Appearance.fromCode(a.code), a);
      }
    });

    test('a missing, unknown or odd code follows the device', () {
      for (final code in [null, '', 'DARK', 'sepia', ' light', '{}']) {
        expect(Appearance.fromCode(code), Appearance.device, reason: '$code');
      }
    });
  });

  group('DeviceAppearanceStorage', () {
    test('keeps the choice under its own key, apart from the data', () async {
      SharedPreferences.setMockInitialValues({});
      final setting = AppearanceSetting(DeviceAppearanceStorage());
      await setting.choose(Appearance.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('gelanggang.appearance'), 'dark');
      expect(prefs.getKeys(), {'gelanggang.appearance'});

      final again = AppearanceSetting(DeviceAppearanceStorage());
      await again.load();
      expect(again.chosen, Appearance.dark);
    });

    test('a value of the wrong type or an unknown code does not crash the '
        'launch; it follows the device', () async {
      for (final stored in <Object>[
        42,
        true,
        1.5,
        <String>['dark'],
        'night',
      ]) {
        SharedPreferences.setMockInitialValues({
          'gelanggang.appearance': stored,
        });
        final setting = AppearanceSetting(DeviceAppearanceStorage());
        await setting.load();
        expect(setting.chosen, Appearance.device, reason: '$stored');
      }
    });
  });

  testWidgets('follows the device until a choice is made, and the choice is '
      'kept', (tester) async {
    final (_, storage, languageStorage) = await pumpWith(
      tester,
      device: Brightness.dark,
    );
    expect(shown(tester), Brightness.dark);
    expect(storage.code, isNull);

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.byKey(const Key('appearance-light')));
    await tester.pumpAndSettle();
    expect(shown(tester), Brightness.light);
    expect(storage.code, 'light');
    // Picking an appearance leaves the language alone.
    expect(languageStorage.code, isNull);

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-device')));
    await tester.pumpAndSettle();
    expect(shown(tester), Brightness.dark);
    expect(storage.code, 'device');
  });

  testWidgets('a saved choice wins over the device', (tester) async {
    await pumpWith(tester, saved: 'dark');
    expect(shown(tester), Brightness.dark);
  });

  testWidgets('the menu shows the current choices checked, in the chosen '
      'language', (tester) async {
    await pumpWith(tester, saved: 'dark');
    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-zh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    final dark = tester.widget<CheckedPopupMenuItem<String>>(
      find.byKey(const Key('appearance-dark')),
    );
    final light = tester.widget<CheckedPopupMenuItem<String>>(
      find.byKey(const Key('appearance-light')),
    );
    expect(dark.checked, isTrue);
    expect(light.checked, isFalse);
    // Choosing the language did not change the appearance.
    expect(shown(tester), Brightness.dark);
  });

  testWidgets('a restore leaves the appearance as it was', (tester) async {
    final (store, storage, _) = await pumpWith(tester, saved: 'dark');
    final backup = store.exportBackup();
    expect(backup, isNot(contains('appearance')));
    await store.restoreBackup(backup);
    await tester.pumpAndSettle();
    expect(shown(tester), Brightness.dark);
    expect(storage.code, 'dark');
  });

  testWidgets('in dark mode every screen meets the tap target, label and '
      'contrast guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpWith(tester, saved: 'dark');
    await meetsGuidelines(tester, 'dark home');

    await tester.tap(find.byKey(const Key('language')));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'dark language and appearance menu');
    await tester.tapAt(const Offset(200, 900));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'dark session');
    await tester.tap(find.byKey(const Key('open-queue')));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'dark queue');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Players'));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'dark players');
    await tester.tap(find.text('Bee Ling'));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'dark player');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-season')));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'dark season');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'dark backup');
    semantics.dispose();
  });
}
