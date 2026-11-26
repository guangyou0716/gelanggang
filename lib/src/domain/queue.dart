/// The court queue: who is on court, who waits, and a fair suggestion for the
/// next doubles game. Pure functions of a [Session], so they are easy to test
/// and always give the same answer for the same session.
library;

import 'models.dart';

/// A suggested game: [teamA] against [teamB].
typedef Teams = ({List<int> teamA, List<int> teamB});

/// Players in a game that has not finished yet.
Set<int> onCourt(Session s) => {
  for (final g in s.games)
    if (!g.finished) ...g.players,
};

/// Courts (1-based) without a game on them, lowest first.
List<int> freeCourts(Session s) {
  final busy = {
    for (final g in s.games)
      if (!g.finished) g.court,
  };
  return [
    for (var c = 1; c <= s.courts; c++)
      if (!busy.contains(c)) c,
  ];
}

/// Games each present player has started (finished or still on court).
Map<int, int> gamesPlayed(Session s) {
  final counts = {for (final a in s.attendance) a.playerId: 0};
  for (final g in s.games) {
    for (final p in g.players) {
      counts[p] = (counts[p] ?? 0) + 1;
    }
  }
  return counts;
}

/// When each player last came off court, as the finished game's sequence
/// number; 0 if they have not finished a game yet.
Map<int, int> lastOffCourt(Session s) {
  final last = <int, int>{};
  for (final g in s.games) {
    final seq = g.finishedSeq;
    if (seq == null) continue;
    for (final p in g.players) {
      if (seq > (last[p] ?? 0)) last[p] = seq;
    }
  }
  return last;
}

/// Players who could go on court now, in queue order: present, not sitting
/// out and not on court.
///
/// Whoever came off court longest ago goes first (someone who has not played
/// yet counts as waiting since the start). Ties go to whoever has played
/// fewer games, then to whoever was ticked in first.
List<int> waitingOrder(Session s) {
  final busy = onCourt(s);
  final played = gamesPlayed(s);
  final last = lastOffCourt(s);
  final order = <int, int>{};
  final waiting = <int>[];
  for (final (i, a) in s.attendance.indexed) {
    order[a.playerId] = i;
    if (!a.resting && !busy.contains(a.playerId)) waiting.add(a.playerId);
  }
  int key(int p, Map<int, int> m) => m[p] ?? 0;
  waiting.sort(
    (x, y) => key(x, last) != key(y, last)
        ? key(x, last).compareTo(key(y, last))
        : key(x, played) != key(y, played)
        ? key(x, played).compareTo(key(y, played))
        : order[x]!.compareTo(order[y]!),
  );
  return waiting;
}

/// How often each pair of players has been partners, and opponents.
({Map<(int, int), int> partners, Map<(int, int), int> opponents}) pairCounts(
  Session s,
) {
  (int, int) pair(int a, int b) => a < b ? (a, b) : (b, a);
  final partners = <(int, int), int>{};
  final opponents = <(int, int), int>{};
  void add(Map<(int, int), int> m, int a, int b) =>
      m[pair(a, b)] = (m[pair(a, b)] ?? 0) + 1;
  for (final g in s.games) {
    add(partners, g.teamA[0], g.teamA[1]);
    add(partners, g.teamB[0], g.teamB[1]);
    for (final a in g.teamA) {
      for (final b in g.teamB) {
        add(opponents, a, b);
      }
    }
  }
  return (partners: partners, opponents: opponents);
}

/// Splits four players into two teams so that repeat partners are avoided
/// first and repeat opponents second. Of equally good splits the first of
/// (0+1 v 2+3), (0+2 v 1+3), (0+3 v 1+2) wins, so it is deterministic.
Teams pairUp(Session s, List<int> four) {
  if (four.length != 4 || four.toSet().length != 4) {
    throw ArgumentError.value(four, 'four', 'needs four different players');
  }
  final counts = pairCounts(s);
  int get(Map<(int, int), int> m, int a, int b) =>
      m[a < b ? (a, b) : (b, a)] ?? 0;
  final options = [
    (teamA: [four[0], four[1]], teamB: [four[2], four[3]]),
    (teamA: [four[0], four[2]], teamB: [four[1], four[3]]),
    (teamA: [four[0], four[3]], teamB: [four[1], four[2]]),
  ];
  Teams? best;
  var bestCost = 0;
  for (final o in options) {
    var opponents = 0;
    for (final a in o.teamA) {
      for (final b in o.teamB) {
        opponents += get(counts.opponents, a, b);
      }
    }
    final partners =
        get(counts.partners, o.teamA[0], o.teamA[1]) +
        get(counts.partners, o.teamB[0], o.teamB[1]);
    // A repeat partner always weighs more than any number of repeat
    // opponents (at most 4 per option per earlier game, so scale by a lot).
    final cost = partners * 1000000 + opponents;
    if (best == null || cost < bestCost) {
      best = o;
      bestCost = cost;
    }
  }
  return best!;
}

/// The next four from the front of the queue, paired up; null if fewer than
/// four players are waiting.
Teams? suggestNext(Session s) {
  final waiting = waitingOrder(s);
  if (waiting.length < 4) return null;
  return pairUp(s, waiting.take(4).toList());
}
