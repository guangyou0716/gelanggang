import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import 'common.dart';

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
        builder: (context, _) => ListView(
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
              ),
            for (final p in store.players)
              ListTile(
                title: Text(p.name),
                trailing: store.canRemovePlayer(p.id)
                    ? IconButton(
                        tooltip: 'Remove ${p.name}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            attempt(context, () => store.removePlayer(p.id)),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
