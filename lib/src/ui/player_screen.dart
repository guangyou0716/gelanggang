import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/costs.dart';
import '../domain/history.dart';
import '../domain/money.dart';
import '../domain/queue.dart';
import '../l10n/language.dart';
import 'common.dart';
import 'session_screen.dart';

/// One player's history: sessions, games, what they still owe.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.store, required this.playerId});

  final AppStore store;
  final int playerId;

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final player = store.players.where((p) => p.id == playerId).firstOrNull;
        if (player == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(t(K.playerRemoved))),
          );
        }
        final record = playerRecords(store.sessions)[playerId];
        // Newest first, only sessions they came to.
        final sessions = [
          for (final s in store.sessions)
            if (s.attendance.any((a) => a.playerId == playerId)) s,
        ];
        final text = Theme.of(context).textTheme;
        final owed = record?.owedSen ?? 0;
        return Scaffold(
          appBar: AppBar(title: Text(player.name)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _Stat(t(K.statSessions), '${record?.sessions ?? 0}'),
                    _Stat(t(K.statGames), '${record?.games ?? 0}'),
                    _Stat(t(K.statWins), '${record?.wins ?? 0}'),
                    _Stat(t(K.statOwes), formatRm(owed)),
                  ],
                ),
              ),
              SwitchListTile(
                key: const Key('player-guest'),
                title: Text(t(K.guest)),
                subtitle: Text(t(K.guestSwitchBody)),
                value: player.guest,
                onChanged: (v) => store.setPlayerGuest(playerId, v),
              ),
              if (owed > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    key: const Key('settle-all'),
                    icon: const Icon(Icons.done_all),
                    label: Text(
                      t(K.markAmountPaid, {'amount': formatRm(owed)}),
                    ),
                    onPressed: () async {
                      final sure = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(
                            t(K.settleAllTitle, {'name': player.name}),
                          ),
                          content: Text(
                            t(K.settleAllBody, {
                              'amount': formatRm(owed),
                              'sessions': t.sessions(record!.unpaidSessions),
                            }),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(t(K.cancel)),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(t(K.markPaid)),
                            ),
                          ],
                        ),
                      );
                      if (sure == true && context.mounted) {
                        await attempt(context, () => store.settleAll(playerId));
                      }
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(t(K.history), style: text.titleSmall),
              ),
              if (sessions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t(K.notAtAnySession)),
                ),
              for (final s in sessions)
                Builder(
                  builder: (context) {
                    final a = s.attendance.firstWhere(
                      (a) => a.playerId == playerId,
                    );
                    final share = sharesFor(s)[playerId] ?? 0;
                    final due = dueSen(a, share);
                    final games = gamesPlayed(s)[playerId] ?? 0;
                    // The amount goes on its own line, not beside the
                    // title, so neither gets squeezed (long part-paid text,
                    // large text sizes).
                    return ListTile(
                      title: Text(
                        t(K.sessionListTitle, {
                          'date': t.date(s.date),
                          'venue': s.venue,
                        }),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.guest
                                ? t(K.historyGuest, {'games': t.games(games)})
                                : t.games(games),
                          ),
                          Text(
                            share == 0
                                ? formatRm(0)
                                : due == 0
                                ? t(K.sharePaid, {'amount': formatRm(share)})
                                : due < share
                                ? t(K.dueOfShare, {
                                    'due': formatRm(due),
                                    'share': formatRm(share),
                                  })
                                : t(K.shareOwed, {'amount': formatRm(share)}),
                            style: due == 0
                                ? null
                                : TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SessionScreen(store: store, sessionId: s.id),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium),
          Text(value, style: text.titleLarge),
        ],
      ),
    );
  }
}
