/// Across sessions: what each player still owes and how often they come.
library;

import 'costs.dart';
import 'money.dart';
import 'models.dart';
import 'queue.dart';

/// Sessions in the order they happened: by date, then by when they were made.
int compareSessions(Session a, Session b) =>
    a.date != b.date ? a.date.compareTo(b.date) : a.id.compareTo(b.id);

/// One player's record over all sessions.
class PlayerRecord {
  const PlayerRecord({
    this.sessions = 0,
    this.games = 0,
    this.wins = 0,
    this.owedSen = 0,
    this.unpaidSessions = 0,
    this.lastDate,
  });

  final int sessions;

  /// Games started (finished or on court).
  final int games;

  /// Finished games with a score that this player's team won.
  final int wins;

  /// Still owed over all sessions (see `dueSen`).
  final int owedSen;
  final int unpaidSessions;

  /// Date of the latest session they came to.
  final String? lastDate;
}

/// Records for everyone who came to at least one of [sessions].
Map<int, PlayerRecord> playerRecords(Iterable<Session> sessions) {
  final records = <int, PlayerRecord>{};
  for (final s in [...sessions]..sort(compareSessions)) {
    final shares = sharesFor(s);
    final played = gamesPlayed(s);
    final wins = <int, int>{};
    for (final g in s.games) {
      final a = g.scoreA, b = g.scoreB;
      if (!g.finished || a == null || b == null || a == b) continue;
      for (final p in a > b ? g.teamA : g.teamB) {
        wins[p] = (wins[p] ?? 0) + 1;
      }
    }
    for (final att in s.attendance) {
      final id = att.playerId;
      final r = records[id] ?? const PlayerRecord();
      final owed = dueSen(att, shares[id] ?? 0);
      records[id] = PlayerRecord(
        sessions: r.sessions + 1,
        games: r.games + (played[id] ?? 0),
        wins: r.wins + (wins[id] ?? 0),
        owedSen: r.owedSen + owed,
        unpaidSessions: r.unpaidSessions + (owed > 0 ? 1 : 0),
        lastDate: s.date,
      );
    }
  }
  return records;
}

/// What each player at [current] still owes from sessions before it (by date,
/// then creation order). Players who owe nothing are left out.
Map<int, int> carriedOver(Iterable<Session> sessions, Session current) {
  final present = {for (final a in current.attendance) a.playerId};
  final owed = <int, int>{};
  for (final s in sessions) {
    if (compareSessions(s, current) >= 0) continue;
    final shares = sharesFor(s);
    for (final a in s.attendance) {
      if (!present.contains(a.playerId)) continue;
      final due = dueSen(a, shares[a.playerId] ?? 0);
      if (due > 0) owed[a.playerId] = (owed[a.playerId] ?? 0) + due;
    }
  }
  return owed;
}

/// A reminder listing everyone who still owes something, most owed first.
/// Null when everyone has paid.
String? balancesText(Iterable<Session> sessions, Map<int, String> names) {
  final owing =
      [
        for (final e in playerRecords(sessions).entries)
          if (e.value.owedSen > 0) e,
      ]..sort(
        (a, b) => b.value.owedSen != a.value.owedSen
            ? b.value.owedSen.compareTo(a.value.owedSen)
            : (names[a.key] ?? '').compareTo(names[b.key] ?? ''),
      );
  if (owing.isEmpty) return null;
  final total = owing.fold<int>(0, (sum, e) => sum + e.value.owedSen);
  final buffer = StringBuffer()
    ..writeln('Badminton balances (${formatRm(total)} to collect):');
  for (final e in owing) {
    final n = e.value.unpaidSessions;
    buffer.writeln(
      '- ${names[e.key] ?? '?'}: ${formatRm(e.value.owedSen)} '
      '($n session${n == 1 ? '' : 's'})',
    );
  }
  return buffer.toString().trimRight();
}
