import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/history.dart';
import '../domain/money.dart';
import '../l10n/language.dart';

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
        ..showSnackBar(SnackBar(content: Text(e.localize(context.s))));
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
String recordSummary(PlayerRecord? r, [Strings t = Strings.en]) {
  if (r == null || r.sessions == 0) return t(K.noSessionsYet);
  return [
    t.sessions(r.sessions),
    t.games(r.games),
    r.owedSen > 0
        ? t(K.owesAmount, {'amount': formatRm(r.owedSen)})
        : t(K.paidUp),
  ].join(' · ');
}

/// "[text] · level 4" (e.g. "2 games · level 4"), or just [text] when no
/// level is set.
String withLevel(String text, int? level, Strings t) =>
    level == null ? text : t(K.withLevel, {'text': text, 'level': level});
