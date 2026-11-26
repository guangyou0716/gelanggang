import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/history.dart';
import '../domain/money.dart';
import '../l10n/language.dart';
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
    final t = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(t(K.players))),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final records = playerRecords(store.sessions);
          final toCollect = records.values.fold<int>(
            0,
            (sum, r) => sum + r.owedSen,
          );
          final reminder = balancesText(
            store.sessions,
            store.names,
            strings: t,
          );
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
                        decoration: InputDecoration(
                          labelText: t(K.name),
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(onPressed: _add, child: Text(t(K.add))),
                  ],
                ),
              ),
              if (store.players.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t(K.noPlayers)),
                )
              else
                ListTile(
                  key: const Key('balances-total'),
                  title: Text(
                    toCollect > 0
                        ? t(K.toCollectAcross, {'amount': formatRm(toCollect)})
                        : t(K.everyonePaidUp),
                  ),
                  // Under the total rather than beside it, so it still fits
                  // with large text.
                  subtitle: reminder == null
                      ? null
                      : Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: reminder),
                              );
                              if (context.mounted) {
                                toast(context, t(K.copiedForChat));
                              }
                            },
                            icon: const Icon(Icons.copy),
                            label: Text(t(K.copyReminder)),
                          ),
                        ),
                ),
              for (final p in store.players)
                ListTile(
                  title: Text(
                    p.guest ? t(K.nameGuest, {'name': p.name}) : p.name,
                  ),
                  subtitle: Text(recordSummary(records[p.id], t)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PlayerScreen(store: store, playerId: p.id),
                    ),
                  ),
                  trailing: store.canRemovePlayer(p.id)
                      ? IconButton(
                          tooltip: t(K.removeName, {'name': p.name}),
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
