/// The court queue: who is on court, who waits, and a fair suggestion for the
/// next game (doubles or singles). Pure functions of a [Session] (and the
/// players' levels), so they are easy to test and always give the same answer
/// for the same input.
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

/// How often each pair of players has been partners, and opponents. Singles
/// games have no partners.
({Map<(int, int), int> partners, Map<(int, int), int> opponents}) pairCounts(
  Session s,
) {
  (int, int) pair(int a, int b) => a < b ? (a, b) : (b, a);
  final partners = <(int, int), int>{};
  final opponents = <(int, int), int>{};
  void add(Map<(int, int), int> m, int a, int b) =>
      m[pair(a, b)] = (m[pair(a, b)] ?? 0) + 1;
  for (final g in s.games) {
    if (!g.singles) {
      add(partners, g.teamA[0], g.teamA[1]);
      add(partners, g.teamB[0], g.teamB[1]);
    }
    for (final a in g.teamA) {
      for (final b in g.teamB) {
        add(opponents, a, b);
      }
    }
  }
  return (partners: partners, opponents: opponents);
}

/// Players a game on [court] needs: 2 for singles, 4 for doubles.
int playersFor(Session s, int court) => s.isSingles(court) ? 2 : 4;

/// The court the next suggestion is for: the lowest free court, or when all
/// are busy the court whose game started first (likely to free up first).
int nextCourt(Session s) {
  final free = freeCourts(s);
  if (free.isNotEmpty) return free.first;
  for (final g in s.games) {
    if (!g.finished) return g.court;
  }
  return 1;
}

/// How far apart two teams are in level: the difference of their level
/// sums. A player without a level counts as the average of the levels that
/// are set among [players] (everything is scaled by the number of known
/// levels so it stays in whole numbers); with no levels at all every split
/// is 0.
int levelGap(List<int> teamA, List<int> teamB, Map<int, int> levels) {
  final players = [...teamA, ...teamB];
  final known = [
    for (final p in players)
      if (levels[p] != null) levels[p]!,
  ];
  if (known.isEmpty) return 0;
  final k = known.length;
  final fill = known.fold<int>(0, (a, b) => a + b);
  int sum(List<int> team) => team.fold<int>(
    0,
    (t, p) => t + (levels[p] == null ? fill : levels[p]! * k),
  );
  return (sum(teamA) - sum(teamB)).abs();
}

/// Widest level gap inside a group: highest minus lowest level that is set
/// (players without a level are left out); 0 with fewer than two levels.
int levelSpread(Iterable<int> players, Map<int, int> levels) {
  int? lo, hi;
  for (final p in players) {
    final l = levels[p];
    if (l == null) continue;
    if (lo == null || l < lo) lo = l;
    if (hi == null || l > hi) hi = l;
  }
  return lo == null ? 0 : hi! - lo;
}

/// Splits four players into two teams so that repeat partners are avoided
/// first, then the team level sums are as close as possible ([levelGap]),
/// then repeat opponents are avoided. Of equally good splits the first of
/// (0+1 v 2+3), (0+2 v 1+3), (0+3 v 1+2) wins, so it is deterministic.
/// Two players make a singles game: the first against the second.
Teams pairUp(Session s, List<int> players, {Map<int, int> levels = const {}}) {
  if ((players.length != 4 && players.length != 2) ||
      players.toSet().length != players.length) {
    throw ArgumentError.value(
      players,
      'players',
      'needs two or four different players',
    );
  }
  if (players.length == 2) return (teamA: [players[0]], teamB: [players[1]]);
  final four = players;
  final counts = pairCounts(s);
  int get(Map<(int, int), int> m, int a, int b) =>
      m[a < b ? (a, b) : (b, a)] ?? 0;
  final options = [
    (teamA: [four[0], four[1]], teamB: [four[2], four[3]]),
    (teamA: [four[0], four[2]], teamB: [four[1], four[3]]),
    (teamA: [four[0], four[3]], teamB: [four[1], four[2]]),
  ];
  Teams? best;
  (int, int, int)? bestCost;
  bool better((int, int, int) a, (int, int, int) b) =>
      a.$1 != b.$1 ? a.$1 < b.$1 : (a.$2 != b.$2 ? a.$2 < b.$2 : a.$3 < b.$3);
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
    // Compared in order: a repeat partner always weighs more than any level
    // gap, and a level gap more than any number of repeat opponents.
    final cost = (partners, levelGap(o.teamA, o.teamB, levels), opponents);
    if (bestCost == null || better(cost, bestCost)) {
      best = o;
      bestCost = cost;
    }
  }
  return best!;
}

/// At most this many equally-waiting players are considered when levels pick
/// among them (keeps the search small: at most 1820 groups).
const int levelChoiceWindow = 16;

/// A group whose [levelSpread] is this or more has a big level gap (say a
/// level 1 beginner with a level 4 or 5 player).
const int bigLevelGap = 3;

/// The [n] players for the next game, in queue order; null if fewer than [n]
/// are waiting.
///
/// Fairness comes first: nobody is passed over for a player who has waited
/// less (came off court more recently, or as recently with more games).
/// Only among players who have waited exactly as long as the last one who
/// fits can levels change who plays, and only to avoid a big level gap
/// ([bigLevelGap]): the earliest ticked-in group without one wins, or if
/// every group has one, the group with the smallest [levelSpread]. With no
/// levels set, or no big gap in the first [n], this is simply the first [n]
/// in the queue.
List<int>? choosePlayers(Session s, int n, {Map<int, int> levels = const {}}) {
  final waiting = waitingOrder(s);
  if (waiting.length < n) return null;
  final played = gamesPlayed(s);
  final last = lastOffCourt(s);
  bool sameWait(int a, int b) =>
      (last[a] ?? 0) == (last[b] ?? 0) && (played[a] ?? 0) == (played[b] ?? 0);
  final cut = waiting[n - 1];
  final firstTied = waiting.indexWhere((p) => sameWait(p, cut));
  final must = waiting.sublist(0, firstTied);
  final tied = [
    for (final p in waiting.skip(firstTied))
      if (sameWait(p, cut)) p,
  ].take(levelChoiceWindow).toList();
  final need = n - must.length;
  List<int>? best;
  var bestSpread = 0;
  // Groups of [need] from [tied] in lexicographic order of position, so the
  // first group found is the earliest ticked in. The very first group is
  // the plain queue order.
  bool pick(int from, List<int> chosen) {
    if (chosen.length == need) {
      final group = [...must, ...chosen];
      final spread = levelSpread(group, levels);
      if (best == null || spread < bestSpread) {
        best = group;
        bestSpread = spread;
      }
      return spread < bigLevelGap; // Stop at the first group without one.
    }
    for (var i = from; i <= tied.length - (need - chosen.length); i++) {
      if (pick(i + 1, [...chosen, tied[i]])) return true;
    }
    return false;
  }

  pick(0, []);
  final chosen = best!.toSet();
  return [
    for (final p in waiting)
      if (chosen.contains(p)) p,
  ];
}

/// The suggested next game on [court] (by default [nextCourt]): singles or
/// doubles as set for that court, players from [choosePlayers], paired up by
/// [pairUp]; null if too few players are waiting.
Teams? suggestNext(Session s, {Map<int, int> levels = const {}, int? court}) {
  final n = playersFor(s, court ?? nextCourt(s));
  final players = choosePlayers(s, n, levels: levels);
  if (players == null) return null;
  return pairUp(s, players, levels: levels);
}
