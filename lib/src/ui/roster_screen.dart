import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/history.dart';
import '../domain/money.dart';
import 'common.dart';
import 'player_screen.dart';

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final ok = await attempt(context, () => widget.store.addPlayer(_name.text));
    if (ok) _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Players')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final records = playerRecords(store.sessions);
          final toCollect = records.values.fold<int>(
            0,
            (sum, r) => sum + r.owedSen,
          );
          final reminder = balancesText(store.sessions, store.names);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('player-name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(onPressed: _add, child: const Text('Add')),
                  ],
                ),
              ),
              if (store.players.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No players yet.'),
                )
              else
                ListTile(
                  key: const Key('balances-total'),
                  title: Text(
                    toCollect > 0
                        ? '${formatRm(toCollect)} to collect across sessions'
                        : 'Everyone is paid up',
                  ),
                  trailing: reminder == null
                      ? null
                      : TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: reminder),
                            );
                            if (context.mounted) {
                              toast(
                                context,
                                'Copied. Paste it into your group chat.',
                              );
                            }
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy reminder'),
                        ),
                ),
              for (final p in store.players)
                ListTile(
                  title: Text(p.guest ? '${p.name} (guest)' : p.name),
                  subtitle: Text(recordSummary(records[p.id])),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PlayerScreen(store: store, playerId: p.id),
                    ),
                  ),
                  trailing: store.canRemovePlayer(p.id)
                      ? IconButton(
                          tooltip: 'Remove ${p.name}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              attempt(context, () => store.removePlayer(p.id)),
                        )
                      : const Icon(Icons.chevron_right),
                ),
            ],
          );
        },
      ),
    );
  }
}
