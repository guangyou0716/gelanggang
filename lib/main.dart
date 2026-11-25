import 'package:material_ui/material_ui.dart';

import 'src/app.dart';
import 'src/data/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(DeviceStorage());
  await store.load();
  await store.seedDemo(today: isoDate(DateTime.now()));
  runApp(GelanggangApp(store: store));
}
