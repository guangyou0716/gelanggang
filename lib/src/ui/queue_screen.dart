import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/models.dart';
import '../domain/queue.dart';
import 'common.dart';

/// "Who plays next": courts in use, the suggested next four (which the
/// organiser can change), the waiting list and the game log.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, required this.store, required this.sessionId});

  final AppStore store;
  final int sessionId;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  /// The organiser's changes to the suggestion: slot index (0-1 team A,
  /// 2-3 team B) to player. Dropped when that player is no longer free.
  final Map<int, int> _swaps = {};

  AppStore get store => widget.store;

  List<int>? _nextFour(Session s) {
    final suggestion = suggestNext(s);
    if (suggestion == null) return null;
    final slots = [...suggestion.teamA, ...suggestion.teamB];
    final waiting = waitingOrder(s).toSet();
    _swaps.removeWhere((_, p) => !waiting.contains(p));
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
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Instead of ${names[slots[slot]]}'),
        children: [
          for (final p in waiting)
            if (p != slots[slot])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p),
                child: Text(
                  slots.contains(p)
                      ? '${names[p]} (swap places)'
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
      toast(context, 'Scores are whole numbers, like 21');
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

  Future<void> _remove(Game g, String what) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(what),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure == true) await store.removeGame(widget.sessionId, g.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.session(widget.sessionId);
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This session was deleted.')),
          );
        }
        final names = store.names;
        final text = Theme.of(context).textTheme;
        final active = {
          for (final g in s.games)
            if (!g.finished) g.court: g,
        };
        final free = freeCourts(s);
        final next = _nextFour(s);
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
          appBar: AppBar(title: const Text('Court queue')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              for (var c = 1; c <= s.courts; c++)
                _CourtTile(
                  court: c,
                  game: active[c],
                  names: names,
                  onFinish: (g) => _finish(g, names),
                  onCancel: (g) => _remove(g, 'Take this game off court?'),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Next up', style: text.titleSmall),
              ),
              if (next == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    s.attendance.length < 4
                        ? 'Tick at least four players under "Who came" first.'
                        : 'Waiting for four free players '
                              '(${waiting.length} free now).',
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
                            child: Text('vs', style: text.labelLarge),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final i in [team * 2, team * 2 + 1])
                              ActionChip(
                                key: Key('next-$i'),
                                avatar: const Icon(Icons.swap_horiz, size: 18),
                                label: Text(names[next[i]] ?? '?'),
                                tooltip: 'Change ${names[next[i]]}',
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
                      ? const Text('All courts are busy.')
                      : FilledButton.icon(
                          key: const Key('start-game'),
                          icon: const Icon(Icons.play_arrow),
                          label: Text('Start on court ${free.first}'),
                          onPressed: () async {
                            final ok = await attempt(
                              context,
                              () => store.startGame(
                                s.id,
                                court: free.first,
                                teamA: next.sublist(0, 2),
                                teamB: next.sublist(2),
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
                  'Waiting (${waiting.length})',
                  style: text.titleSmall,
                ),
              ),
              for (final (i, p) in waiting.indexed)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  title: Text(names[p] ?? '?'),
                  subtitle: Text(gamesLabel(played[p] ?? 0)),
                  trailing: TextButton(
                    onPressed: () => store.setResting(s.id, p, true),
                    child: const Text('Sit out'),
                  ),
                ),
              for (final p in resting)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.event_seat_outlined),
                  title: Text('${names[p] ?? '?'} (sitting out)'),
                  subtitle: Text(gamesLabel(played[p] ?? 0)),
                  trailing: TextButton(
                    onPressed: () => store.setResting(s.id, p, false),
                    child: const Text('Back in'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Games (${log.length})', style: text.titleSmall),
              ),
              if (log.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Finished games show up here.'),
                ),
              for (final g in log)
                ListTile(
                  dense: true,
                  title: Text(
                    '${teamName(g.teamA, names)} vs ${teamName(g.teamB, names)}',
                  ),
                  subtitle: Text(
                    'Court ${g.court}'
                    '${g.scoreA == null ? '' : ' · ${g.scoreA}-${g.scoreB}'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove game',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        _remove(g, 'Remove this game from the log?'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String teamName(List<int> team, Map<int, String> names) =>
    team.map((p) => names[p] ?? '?').join(' & ');

String gamesLabel(int n) => '$n game${n == 1 ? '' : 's'}';

class _CourtTile extends StatelessWidget {
  const _CourtTile({
    required this.court,
    required this.game,
    required this.names,
    required this.onFinish,
    required this.onCancel,
  });

  final int court;
  final Game? game;
  final Map<int, String> names;
  final ValueChanged<Game> onFinish;
  final ValueChanged<Game> onCancel;

  @override
  Widget build(BuildContext context) {
    final g = game;
    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ListTile(
        title: Text('Court $court'),
        subtitle: Text(
          g == null
              ? 'Free'
              : '${teamName(g.teamA, names)} vs ${teamName(g.teamB, names)}',
        ),
        trailing: g == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Cancel game on court $court',
                    icon: const Icon(Icons.close),
                    onPressed: () => onCancel(g),
                  ),
                  FilledButton.tonal(
                    key: Key('finish-$court'),
                    onPressed: () => onFinish(g),
                    child: const Text('Finish'),
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
    return AlertDialog(
      title: const Text('Game finished'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Score (optional)'),
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-score'),
          onPressed: () => Navigator.pop(context, (_a.text, _b.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
