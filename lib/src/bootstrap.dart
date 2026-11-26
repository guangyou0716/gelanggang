import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/store.dart';
import 'l10n/language.dart';

/// Reads the saved data and language from the device, adds the demo group
/// on a true first launch, and returns the app ready to run.
///
/// [now] fixes "today" for the demo sessions (tests); it defaults to the
/// clock. The integration tests call this to start the real app, with real
/// device storage, as if it had just been opened.
Future<Widget> loadApp({DateTime? now}) async {
  final store = AppStore(DeviceStorage());
  final language = LanguageSetting(DeviceLanguageStorage());
  await Future.wait([store.load(), language.load()]);
  await store.seedDemo(today: isoDate(now ?? DateTime.now()));
  return GelanggangApp(store: store, language: language);
}
