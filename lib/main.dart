import 'package:material_ui/material_ui.dart';

import 'src/app.dart';
import 'src/data/store.dart';
import 'src/l10n/language.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(DeviceStorage());
  final language = LanguageSetting(DeviceLanguageStorage());
  await Future.wait([store.load(), language.load()]);
  await store.seedDemo(today: isoDate(DateTime.now()));
  runApp(GelanggangApp(store: store, language: language));
}
