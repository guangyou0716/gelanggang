import 'package:material_ui/material_ui.dart';

import 'data/store.dart';
import 'l10n/language.dart';
import 'ui/appearance.dart';
import 'ui/home_screen.dart';

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class GelanggangApp extends StatefulWidget {
  const GelanggangApp({
    super.key,
    required this.store,
    this.language,
    this.appearance,
  });

  final AppStore store;

  /// The organiser's language choice; when not given, the app follows the
  /// device and a choice lasts until it closes.
  final LanguageSetting? language;

  /// Light/dark choice; when not given, the app follows the device and a
  /// choice lasts until it closes.
  final AppearanceSetting? appearance;

  @override
  State<GelanggangApp> createState() => _GelanggangAppState();
}

class _GelanggangAppState extends State<GelanggangApp> {
  late final _fallback = LanguageSetting(MemoryLanguageStorage());
  late final _fallbackAppearance = AppearanceSetting(MemoryAppearanceStorage());

  LanguageSetting get _language => widget.language ?? _fallback;
  AppearanceSetting get _appearance => widget.appearance ?? _fallbackAppearance;

  @override
  void dispose() {
    _fallback.dispose();
    _fallbackAppearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_language, _appearance]),
      builder: (context, _) {
        final chosen = _language.chosen;
        return MaterialApp(
          title: 'gelanggang',
          debugShowCheckedModeBanner: false,
          theme: gelanggangTheme(Brightness.light),
          darkTheme: gelanggangTheme(Brightness.dark),
          themeMode: _appearance.chosen.mode,
          locale: chosen == null ? null : Locale(chosen.code),
          supportedLocales: supportedLocales,
          localizationsDelegates: const [
            StringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          // Follow the device when nothing is chosen; English for a device
          // language the app does not have.
          localeListResolutionCallback: (locales, _) =>
              Locale(languageForDevice(locales).code),
          home: HomeScreen(
            store: widget.store,
            language: _language,
            appearance: _appearance,
          ),
        );
      },
    );
  }
}
