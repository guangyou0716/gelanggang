import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import 'common.dart';

/// Copy everything out as text, or put a copied backup back. There is no
/// cloud: the organiser keeps the text wherever they like (a message to
/// themselves, a notes app) and pastes it on the new phone.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _paste = TextEditingController();
  String? _error;

  AppStore get store => widget.store;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) toast(context, done);
  }

  Future<void> _restore() async {
    final BackupSummary incoming;
    try {
      incoming = AppStore.checkBackup(_paste.text);
    } on InputError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() => _error = null);
    final now = store.summary;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything with this backup?'),
        content: Text(
          'The backup has ${_count(incoming.players, 'player')} and '
          '${_count(incoming.sessions, 'session')}. It replaces the '
          '${_count(now.players, 'player')} and '
          '${_count(now.sessions, 'session')} on this phone, which cannot be '
          'undone. Copy a backup of them first if you may need them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-restore'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await attempt(context, () => store.restoreBackup(_paste.text));
    if (ok && mounted) {
      _paste.clear();
      toast(context, 'Backup restored.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final now = store.summary;
          final aside = store.setAside;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (aside != null) ...[
                Card(
                  key: const Key('set-aside'),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Some saved data could not be read',
                          style: text.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'It may be damaged or come from a newer version of '
                          'the app. It was kept aside, untouched. Copy it and '
                          'keep it until you have checked it.',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _copy(aside, 'Copied.'),
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy it'),
                            ),
                            TextButton(
                              onPressed: () async {
                                final sure = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text(
                                      'Throw away the unreadable data?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Keep it'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Throw away'),
                                      ),
                                    ],
                                  ),
                                );
                                if (sure == true) {
                                  await store.discardSetAside();
                                }
                              },
                              child: const Text('Throw it away'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text('Back up', style: text.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Everything stays on this phone. Copy a backup now and then '
                'and keep it somewhere safe, such as a message to yourself. '
                'This phone has ${_count(now.players, 'player')} and '
                '${_count(now.sessions, 'session')}.',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: const Key('copy-backup'),
                  onPressed: () => _copy(
                    store.exportBackup(),
                    'Backup copied. Paste it somewhere safe.',
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy backup'),
                ),
              ),
              const SizedBox(height: 32),
              Text('Restore', style: text.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'Paste a backup to replace everything on this phone with it.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('restore-text'),
                controller: _paste,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: 'Backup text',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  errorMaxLines: 4,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const Key('restore'),
                  onPressed: _restore,
                  icon: const Icon(Icons.settings_backup_restore),
                  label: const Text('Restore'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
