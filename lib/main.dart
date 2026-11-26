import 'package:material_ui/material_ui.dart';

import 'src/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await loadApp());
}
