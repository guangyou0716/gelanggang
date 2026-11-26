import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/costs.dart';
import '../domain/money.dart';
import 'backup_screen.dart';
import 'roster_screen.dart';
import 'session_form_screen.dart';
import 'session_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final sessions = store.sessions;
        return Scaffold(
          appBar: AppBar(
            title: const Text('gelanggang'),
            actions: [
              IconButton(
                tooltip: 'Players',
                icon: const Icon(Icons.group_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RosterScreen(store: store),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Backup and restore',
                icon: Badge(
                  isLabelVisible: store.setAside != null,
                  child: const Icon(Icons.settings_backup_restore),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BackupScreen(store: store),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final id = await Navigator.of(context).push<int>(
                MaterialPageRoute(
                  builder: (_) => SessionFormScreen(store: store),
                ),
              );
              if (id != null && context.mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SessionScreen(store: store, sessionId: id),
                  ),
                );
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('New session'),
          ),
          body: sessions.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No sessions yet. Add your players, then start a session.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = sessions[i];
                    final owed = outstandingSen(s);
                    return ListTile(
                      title: Text('${s.date} · ${s.venue}'),
                      subtitle: Text(
                        '${s.attendance.length} players · ${formatRm(totalCostSen(s))}'
                        '${owed > 0 ? ' · ${formatRm(owed)} to collect' : ' · all paid'}',
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
        );
      },
    );
  }
}
