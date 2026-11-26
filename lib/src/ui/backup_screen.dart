import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../l10n/language.dart';
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
  InputError? _error;

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
      setState(() => _error = e);
      return;
    }
    setState(() => _error = null);
    final now = store.summary;
    final t = context.s;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(K.replaceTitle)),
        content: Text(
          t(K.replaceBody, {
            'inPlayers': t.players(incoming.players),
            'inSessions': t.sessions(incoming.sessions),
            'nowPlayers': t.players(now.players),
            'nowSessions': t.sessions(now.sessions),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t(K.cancel)),
          ),
          FilledButton(
            key: const Key('confirm-restore'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t(K.replace)),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await attempt(context, () => store.restoreBackup(_paste.text));
    if (ok && mounted) {
      _paste.clear();
      toast(context, context.s(K.backupRestored));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(t(K.backupAndRestore))),
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
                        Text(t(K.unreadableTitle), style: text.titleSmall),
                        const SizedBox(height: 8),
                        Text(t(K.unreadableBody)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _copy(aside, t(K.copied)),
                              icon: const Icon(Icons.copy),
                              label: Text(t(K.copyIt)),
                            ),
                            TextButton(
                              onPressed: () async {
                                final sure = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(t(K.throwAwayConfirm)),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(t(K.keepIt)),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(t(K.throwAway)),
                                      ),
                                    ],
                                  ),
                                );
                                if (sure == true) {
                                  await store.discardSetAside();
                                }
                              },
                              child: Text(t(K.throwItAway)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(t(K.backUp), style: text.titleMedium),
              const SizedBox(height: 8),
              Text(
                t(K.backUpBody, {
                  'players': t.players(now.players),
                  'sessions': t.sessions(now.sessions),
                }),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: const Key('copy-backup'),
                  onPressed: () =>
                      _copy(store.exportBackup(), t(K.backupCopied)),
                  icon: const Icon(Icons.copy),
                  label: Text(t(K.copyBackup)),
                ),
              ),
              const SizedBox(height: 32),
              Text(t(K.restore), style: text.titleMedium),
              const SizedBox(height: 8),
              Text(t(K.restoreBody)),
              const SizedBox(height: 12),
              TextField(
                key: const Key('restore-text'),
                controller: _paste,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: t(K.backupText),
                  border: const OutlineInputBorder(),
                  errorText: _error?.localize(t),
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
                  label: Text(t(K.restore)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
