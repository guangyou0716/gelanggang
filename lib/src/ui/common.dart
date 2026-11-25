import 'package:material_ui/material_ui.dart';

import '../data/store.dart';

/// Runs [action]; an [InputError] is shown to the organiser instead of thrown.
Future<bool> attempt(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } on InputError catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
