import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/money.dart';
import '../domain/season.dart';
import '../l10n/language.dart';
import 'common.dart';

/// Each player's sessions, games, wins and money over a date range, with a
/// CSV copy for a spreadsheet.
class SeasonScreen extends StatefulWidget {
  const SeasonScreen({super.key, required this.store, this.today});

  final AppStore store;

  /// "Today" for the date ranges; the real date when not given (tests pass
  /// one).
  final DateTime? today;

  @override
  State<SeasonScreen> createState() => _SeasonScreenState();
}

class _SeasonScreenState extends State<SeasonScreen> {
  SeasonRange _range = SeasonRange.last3Months;

  static const _labels = {
    SeasonRange.thisMonth: K.rangeThisMonth,
    SeasonRange.lastMonth: K.rangeLastMonth,
    SeasonRange.last3Months: K.rangeLast3Months,
    SeasonRange.thisYear: K.rangeThisYear,
    SeasonRange.all: K.rangeAll,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    final store = widget.store;
    final today = widget.today ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(t(K.season))),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final summary = SeasonSummary.of(
            store.sessions,
            store.players,
            _range,
            today,
          );
          final dates = datesFor(_range, today);
          final sessions = t.sessions(summary.sessions);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in SeasonRange.values)
                      ChoiceChip(
                        key: Key('range-${r.name}'),
                        label: Text(t(_labels[r]!)),
                        selected: _range == r,
                        onSelected: (_) => setState(() => _range = r),
                      ),
                  ],
                ),
              ),
              ListTile(
                key: const Key('season-header'),
                title: Text(
                  dates == null
                      ? t(K.seasonAllTime, {'sessions': sessions})
                      : t(K.seasonPeriod, {
                          'from': t.date(dates.from),
                          'to': t.date(dates.to),
                          'sessions': sessions,
                        }),
                ),
                subtitle: summary.rows.isEmpty
                    ? null
                    : Text(
                        t(K.seasonTotals, {
                          'share': formatRm(summary.shareSen),
                          'paid': formatRm(summary.paidSen),
                          'owed': formatRm(summary.owedSen),
                        }),
                      ),
              ),
              if (summary.rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t(K.seasonEmpty),
                    key: const Key('season-empty'),
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const Key('copy-csv'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: summary.toCsv()),
                        );
                        if (context.mounted) toast(context, t(K.csvCopied));
                      },
                      icon: const Icon(Icons.table_view_outlined),
                      label: Text(t(K.copyCsv)),
                    ),
                  ),
                ),
                const Divider(height: 24),
                for (final row in summary.rows)
                  _SeasonTile(key: Key('season-${row.playerId}'), row: row),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SeasonTile extends StatelessWidget {
  const _SeasonTile({super.key, required this.row});

  final SeasonRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    final r = row.record;
    final money = {
      'paid': formatRm(r.paidSen),
      'share': formatRm(r.shareSen),
      'owed': formatRm(r.owedSen),
    };
    final played = t(K.seasonPlayed, {
      'sessions': t.sessions(r.sessions),
      'percent': row.attendancePercent,
      'games': t.games(r.games),
      'wins': r.wins,
    });
    final paid = t(r.owedSen > 0 ? K.seasonPaidOwes : K.seasonPaid, money);
    final name = row.guest ? t(K.nameGuest, {'name': row.name}) : row.name;
    // One announcement per player for screen readers.
    return MergeSemantics(
      child: ListTile(
        title: Text(name),
        subtitle: Text('$played\n$paid'),
        isThreeLine: true,
        trailing: r.owedSen > 0
            ? Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              )
            : null,
      ),
    );
  }
}
