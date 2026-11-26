import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/models.dart';
import '../domain/queue.dart';
import '../l10n/language.dart';
import 'common.dart';

/// "Who plays next": courts in use, the suggested next game (doubles or
/// singles, which the organiser can change), the waiting list and the game
/// log.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, required this.store, required this.sessionId});

  final AppStore store;
  final int sessionId;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  /// The organiser's changes to the suggestion: slot index (team A first,
  /// then team B) to player. Dropped when that player is no longer free.
  final Map<int, int> _swaps = {};

  AppStore get store => widget.store;

  List<int>? _nextGame(Session s) {
    final suggestion = suggestNext(s, levels: store.levels);
    if (suggestion == null) return null;
    final slots = [...suggestion.teamA, ...suggestion.teamB];
    final waiting = waitingOrder(s).toSet();
    _swaps.removeWhere(
      (slot, p) => slot >= slots.length || !waiting.contains(p),
    );
    // Apply each swap: the chosen player takes the slot, and if they were
    // already in another slot the two trade places.
    for (final MapEntry(key: slot, value: p) in _swaps.entries) {
      final at = slots.indexOf(p);
      if (at >= 0) slots[at] = slots[slot];
      slots[slot] = p;
    }
    return slots;
  }

  Future<void> _swap(Session s, List<int> slots, int slot) async {
    final names = store.names;
    final waiting = waitingOrder(s);
    final t = context.s;
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(t(K.insteadOf, {'name': names[slots[slot]] ?? '?'})),
        children: [
          for (final p in waiting)
            if (p != slots[slot])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p),
                child: Text(
                  slots.contains(p)
                      ? t(K.swapPlaces, {'name': names[p] ?? '?'})
                      : names[p] ?? '?',
                ),
              ),
        ],
      ),
    );
    if (picked != null) setState(() => _swaps[slot] = picked);
  }

  Future<void> _finish(Game g, Map<int, String> names) async {
    final score = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ScoreDialog(
        teamA: teamName(g.teamA, names),
        teamB: teamName(g.teamB, names),
      ),
    );
    if (score == null || !mounted) return;
    final a = score.$1.trim();
    final b = score.$2.trim();
    final scoreA = a.isEmpty ? null : int.tryParse(a);
    final scoreB = b.isEmpty ? null : int.tryParse(b);
    if ((a.isNotEmpty && scoreA == null) || (b.isNotEmpty && scoreB == null)) {
      toast(context, context.s(K.scoresWhole));
      return;
    }
    await attempt(
      context,
      () => store.finishGame(
        widget.sessionId,
        g.id,
        scoreA: scoreA,
        scoreB: scoreB,
      ),
    );
  }

  Future<void> _remove(Game g, K what) async {
    final t = context.s;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(what)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t(K.keep)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t(K.remove)),
          ),
        ],
      ),
    );
    if (sure == true) await store.removeGame(widget.sessionId, g.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.session(widget.sessionId);
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(t(K.sessionDeleted))),
          );
        }
        final names = store.names;
        final text = Theme.of(context).textTheme;
        final active = {
          for (final g in s.games)
            if (!g.finished) g.court: g,
        };
        final free = freeCourts(s);
        final court = nextCourt(s);
        final singles = s.isSingles(court);
        final next = _nextGame(s);
        final half = singles ? 1 : 2;
        final levels = store.levels;
        final waiting = waitingOrder(s);
        final played = gamesPlayed(s);
        final resting = [
          for (final a in s.attendance)
            if (a.resting) a.playerId,
        ];
        final log = [
          for (final g in s.games.reversed)
            if (g.finished) g,
        ];
        return Scaffold(
          appBar: AppBar(title: Text(t(K.courtQueue))),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              for (var c = 1; c <= s.courts; c++)
                _CourtTile(
                  court: c,
                  singles: s.isSingles(c),
                  game: active[c],
                  names: names,
                  strings: t,
                  onFinish: (g) => _finish(g, names),
                  onCancel: (g) => _remove(g, K.takeOffCourt),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(t(K.nextUp), style: text.titleSmall),
                    // Applies to the court the suggestion is for (the one on
                    // the start button).
                    Semantics(
                      label: t(K.gameTypeOn, {'court': court}),
                      container: true,
                      child: SegmentedButton<bool>(
                        key: const Key('game-type'),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(
                              t(K.doubles),
                              key: const Key('type-doubles'),
                            ),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(
                              t(K.singles),
                              key: const Key('type-singles'),
                            ),
                          ),
                        ],
                        selected: {singles},
                        onSelectionChanged: (v) async {
                          setState(_swaps.clear);
                          await store.setCourtSingles(s.id, court, v.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (next == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    s.attendance.length < half * 2
                        ? t(singles ? K.tickTwo : K.tickFour)
                        : t(singles ? K.waitingForTwo : K.waitingForFour, {
                            'n': waiting.length,
                          }),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final team in [0, 1]) ...[
                        if (team == 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Wrap(
                              spacing: 16,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(t(K.vs), style: text.labelLarge),
                                // Team level sums, when everyone has a level.
                                if (next.every((p) => levels[p] != null))
                                  Text(
                                    t(K.levelTotals, {
                                      'a': _levelSum(
                                        next.sublist(0, half),
                                        levels,
                                      ),
                                      'b': _levelSum(
                                        next.sublist(half),
                                        levels,
                                      ),
                                    }),
                                    key: const Key('level-totals'),
                                    style: text.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (
                              var i = team * half;
                              i < (team + 1) * half;
                              i++
                            )
                              ActionChip(
                                key: Key('next-$i'),
                                avatar: const Icon(Icons.swap_horiz, size: 18),
                                label: Text(names[next[i]] ?? '?'),
                                tooltip: t(K.changeName, {
                                  'name': names[next[i]] ?? '?',
                                }),
                                onPressed: () => _swap(s, next, i),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: free.isEmpty
                      ? Text(t(K.allCourtsBusy))
                      : FilledButton.icon(
                          key: const Key('start-game'),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(t(K.startOnCourt, {'court': free.first})),
                          onPressed: () async {
                            final ok = await attempt(
                              context,
                              () => store.startGame(
                                s.id,
                                court: free.first,
                                teamA: next.sublist(0, half),
                                teamB: next.sublist(half),
                              ),
                            );
                            if (ok) setState(_swaps.clear);
                          },
                        ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  t(K.waiting, {'n': waiting.length}),
                  style: text.titleSmall,
                ),
              ),
              for (final (i, p) in waiting.indexed)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  title: Text(names[p] ?? '?'),
                  subtitle: Text(
                    withLevel(gamesLabel(played[p] ?? 0, t), levels[p], t),
                  ),
                  trailing: TextButton(
                    onPressed: () => store.setResting(s.id, p, true),
                    child: Text(t(K.sitOut)),
                  ),
                ),
              for (final p in resting)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.event_seat_outlined),
                  title: Text(t(K.sittingOut, {'name': names[p] ?? '?'})),
                  subtitle: Text(gamesLabel(played[p] ?? 0, t)),
                  trailing: TextButton(
                    onPressed: () => store.setResting(s.id, p, false),
                    child: Text(t(K.backIn)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  t(K.gamesHeader, {'n': log.length}),
                  style: text.titleSmall,
                ),
              ),
              if (log.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(t(K.finishedShowHere)),
                ),
              for (final g in log)
                ListTile(
                  dense: true,
                  title: Text(matchName(g, names, t)),
                  subtitle: Text(
                    g.scoreA == null
                        ? t(K.court, {'court': g.court})
                        : t(K.courtScore, {
                            'court': g.court,
                            'a': g.scoreA!,
                            'b': g.scoreB!,
                          }),
                  ),
                  trailing: IconButton(
                    tooltip: t(K.removeGame),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(g, K.removeGameConfirm),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

int _levelSum(List<int> team, Map<int, int> levels) =>
    team.fold(0, (sum, p) => sum + levels[p]!);

String teamName(List<int> team, Map<int, String> names) =>
    team.map((p) => names[p] ?? '?').join(' & ');

/// "Aiman & Bee Ling vs Chandran & Daniel".
String matchName(Game g, Map<int, String> names, [Strings t = Strings.en]) =>
    t(K.teamVs, {'a': teamName(g.teamA, names), 'b': teamName(g.teamB, names)});

String gamesLabel(int n, [Strings t = Strings.en]) => t.games(n);

class _CourtTile extends StatelessWidget {
  const _CourtTile({
    required this.court,
    required this.singles,
    required this.game,
    required this.names,
    required this.strings,
    required this.onFinish,
    required this.onCancel,
  });

  final int court;
  final bool singles;
  final Game? game;
  final Map<int, String> names;
  final Strings strings;
  final ValueChanged<Game> onFinish;
  final ValueChanged<Game> onCancel;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final t = strings;
    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ListTile(
        title: Text(t(singles ? K.courtSingles : K.court, {'court': court})),
        subtitle: Text(g == null ? t(K.free) : matchName(g, names, t)),
        trailing: g == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: t(K.cancelGameOn, {'court': court}),
                    icon: const Icon(Icons.close),
                    onPressed: () => onCancel(g),
                  ),
                  FilledButton.tonal(
                    key: Key('finish-$court'),
                    onPressed: () => onFinish(g),
                    child: Text(t(K.finish)),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Asks for an optional final score; pops with the two texts, or null.
class _ScoreDialog extends StatefulWidget {
  const _ScoreDialog({required this.teamA, required this.teamB});

  final String teamA;
  final String teamB;

  @override
  State<_ScoreDialog> createState() => _ScoreDialogState();
}

class _ScoreDialogState extends State<_ScoreDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    return AlertDialog(
      title: Text(t(K.gameFinished)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t(K.scoreOptional)),
          TextField(
            key: const Key('score-a'),
            controller: _a,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: widget.teamA),
          ),
          TextField(
            key: const Key('score-b'),
            controller: _b,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: widget.teamB),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t(K.cancel)),
        ),
        FilledButton(
          key: const Key('save-score'),
          onPressed: () => Navigator.pop(context, (_a.text, _b.text)),
          child: Text(t(K.save)),
        ),
      ],
    );
  }
}
