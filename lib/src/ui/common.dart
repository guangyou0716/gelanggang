import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/history.dart';
import '../domain/money.dart';

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

/// "3 sessions · 5 games · owes RM 12.50" for the roster.
String recordSummary(PlayerRecord? r) {
  if (r == null || r.sessions == 0) return 'No sessions yet';
  return [
    '${r.sessions} session${r.sessions == 1 ? '' : 's'}',
    '${r.games} game${r.games == 1 ? '' : 's'}',
    r.owedSen > 0 ? 'owes ${formatRm(r.owedSen)}' : 'paid up',
  ].join(' · ');
}
