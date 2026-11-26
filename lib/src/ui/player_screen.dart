import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/costs.dart';
import '../domain/history.dart';
import '../domain/money.dart';
import '../domain/queue.dart';
import 'common.dart';
import 'queue_screen.dart';
import 'session_screen.dart';

/// One player's history: sessions, games, what they still owe.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.store, required this.playerId});

  final AppStore store;
  final int playerId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final player = store.players.where((p) => p.id == playerId).firstOrNull;
        if (player == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This player was removed.')),
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
                    _Stat('Sessions', '${record?.sessions ?? 0}'),
                    _Stat('Games', '${record?.games ?? 0}'),
                    _Stat('Wins', '${record?.wins ?? 0}'),
                    _Stat('Owes', formatRm(owed)),
                  ],
                ),
              ),
              SwitchListTile(
                key: const Key('player-guest'),
                title: const Text('Guest'),
                subtitle: const Text(
                  'New check-ins count as a guest. Past sessions stay as they '
                  'were.',
                ),
                value: player.guest,
                onChanged: (v) => store.setPlayerGuest(playerId, v),
              ),
              if (owed > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    key: const Key('settle-all'),
                    icon: const Icon(Icons.done_all),
                    label: Text('Mark ${formatRm(owed)} as paid'),
                    onPressed: () async {
                      final sure = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(
                            'Mark all of ${player.name}\'s sessions as paid?',
                          ),
                          content: Text(
                            '${formatRm(owed)} over '
                            '${record!.unpaidSessions} session'
                            '${record.unpaidSessions == 1 ? '' : 's'}.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Mark paid'),
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
                child: Text('History', style: text.titleSmall),
              ),
              if (sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Not at any session yet.'),
                ),
              for (final s in sessions)
                Builder(
                  builder: (context) {
                    final a = s.attendance.firstWhere(
                      (a) => a.playerId == playerId,
                    );
                    final share = sharesFor(s)[playerId] ?? 0;
                    final games = gamesPlayed(s)[playerId] ?? 0;
                    return ListTile(
                      title: Text('${s.date} · ${s.venue}'),
                      subtitle: Text(
                        '${gamesLabel(games)}${a.guest ? ' · guest' : ''}',
                      ),
                      trailing: Text(
                        share == 0
                            ? formatRm(0)
                            : a.paid
                            ? '${formatRm(share)} paid'
                            : '${formatRm(share)} owed',
                        style: a.paid || share == 0
                            ? null
                            : TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium),
        Text(value, style: text.titleLarge),
      ],
    );
  }
}
