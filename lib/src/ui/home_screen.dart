import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/costs.dart';
import '../domain/money.dart';
import '../l10n/language.dart';
import 'appearance.dart';
import 'backup_screen.dart';
import 'roster_screen.dart';
import 'season_screen.dart';
import 'session_form_screen.dart';
import 'session_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.language,
    required this.appearance,
  });

  final AppStore store;
  final LanguageSetting language;
  final AppearanceSetting appearance;

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final sessions = store.sessions;
        return Scaffold(
          appBar: AppBar(
            title: const Text('gelanggang'),
            actions: [
              _DisplayButton(language: language, appearance: appearance),
              IconButton(
                tooltip: t(K.players),
                icon: const Icon(Icons.group_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RosterScreen(store: store),
                  ),
                ),
              ),
              IconButton(
                key: const Key('open-season'),
                tooltip: t(K.season),
                icon: const Icon(Icons.insights_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SeasonScreen(store: store),
                  ),
                ),
              ),
              IconButton(
                tooltip: t(K.backupAndRestore),
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
            label: Text(t(K.newSession)),
          ),
          body: sessions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(t(K.noSessions), textAlign: TextAlign.center),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = sessions[i];
                    final owed = outstandingSen(s);
                    final figures = {
                      'players': t.players(s.attendance.length),
                      'total': formatRm(totalCostSen(s)),
                      'owed': formatRm(owed),
                    };
                    return ListTile(
                      title: Text(
                        t(K.sessionListTitle, {
                          'date': t.date(s.date),
                          'venue': s.venue,
                        }),
                      ),
                      subtitle: Text(
                        t(
                          owed > 0
                              ? K.sessionListToCollect
                              : K.sessionListAllPaid,
                          figures,
                        ),
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

/// Picks the app's language (the device's, or one chosen here) and its
/// appearance (light, dark, or the device's). Both are kept on the device.
///
/// One menu for both keeps the app bar to five buttons, so the title still
/// fits on a narrow phone.
class _DisplayButton extends StatelessWidget {
  const _DisplayButton({required this.language, required this.appearance});

  final LanguageSetting language;
  final AppearanceSetting appearance;

  // Menu values; null would mean "closed".
  static const _followDevice = 'device';
  static const _appearancePrefix = 'appearance-';

  void _select(String value) {
    if (value.startsWith(_appearancePrefix)) {
      appearance.choose(
        Appearance.fromCode(value.substring(_appearancePrefix.length)),
      );
    } else {
      language.choose(AppLanguage.fromCode(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    final device = languageForDevice(
      WidgetsBinding.instance.platformDispatcher.locales,
    );
    final chosen = language.chosen;
    final header = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: Theme.of(context).colorScheme.primary);
    PopupMenuItem<String> heading(String text) => PopupMenuItem<String>(
      enabled: false,
      height: 36,
      child: Semantics(header: true, child: Text(text, style: header)),
    );
    return PopupMenuButton<String>(
      key: const Key('language'),
      tooltip: t(K.languageAndAppearance),
      icon: const Icon(Icons.translate),
      onSelected: _select,
      itemBuilder: (_) => [
        heading(t(K.language)),
        CheckedPopupMenuItem(
          key: const Key('language-device'),
          value: _followDevice,
          checked: chosen == null,
          child: Text(t(K.languageDevice, {'language': device.nativeName})),
        ),
        for (final l in AppLanguage.values)
          CheckedPopupMenuItem(
            key: Key('language-${l.code}'),
            value: l.code,
            checked: chosen == l,
            child: Text(l.nativeName),
          ),
        const PopupMenuDivider(),
        heading(t(K.appearance)),
        for (final a in Appearance.values)
          CheckedPopupMenuItem(
            key: Key('appearance-${a.code}'),
            value: '$_appearancePrefix${a.code}',
            checked: appearance.chosen == a,
            child: Text(switch (a) {
              Appearance.device => t(K.appearanceDevice),
              Appearance.light => t(K.appearanceLight),
              Appearance.dark => t(K.appearanceDark),
            }),
          ),
      ],
    );
  }
}
