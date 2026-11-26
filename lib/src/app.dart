import 'package:material_ui/material_ui.dart';

import 'data/store.dart';
import 'l10n/language.dart';
import 'ui/home_screen.dart';

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class GelanggangApp extends StatefulWidget {
  const GelanggangApp({super.key, required this.store, this.language});

  final AppStore store;

  /// The organiser's language choice; when not given, the app follows the
  /// device and a choice lasts until it closes.
  final LanguageSetting? language;

  @override
  State<GelanggangApp> createState() => _GelanggangAppState();
}

class _GelanggangAppState extends State<GelanggangApp> {
  late final _fallback = LanguageSetting(MemoryLanguageStorage());

  LanguageSetting get _language => widget.language ?? _fallback;

  @override
  void dispose() {
    _fallback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _language,
      builder: (context, _) {
        final chosen = _language.chosen;
        return MaterialApp(
          title: 'gelanggang',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0F766E),
            ),
          ),
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
          home: HomeScreen(store: widget.store, language: _language),
        );
      },
    );
  }
}
