import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/costs.dart';
import '../domain/history.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/queue.dart';
import '../l10n/language.dart';
import 'common.dart';
import 'queue_screen.dart';
import 'session_form_screen.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({
    super.key,
    required this.store,
    required this.sessionId,
  });

  final AppStore store;
  final int sessionId;

  Future<void> _editTimes(
    BuildContext context,
    Session s,
    Attendance a,
    String name,
  ) async {
    final times = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _TimesDialog(
        name: name,
        arrive: formatClock(s.startMinute + a.arriveMinute),
        leave: formatClock(s.startMinute + a.leaveMinute),
      ),
    );
    if (times == null || !context.mounted) return;
    final arriveAt = parseClock(times.$1);
    final leaveAt = parseClock(times.$2);
    if (arriveAt == null || leaveAt == null) {
      toast(context, context.s(K.useClock, {'example': '20:30'}));
      return;
    }
    await attempt(
      context,
      () => store.updateAttendance(
        s.id,
        a.copyWith(
          arriveMinute: arriveAt - s.startMinute,
          leaveMinute: leaveAt - s.startMinute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.session(sessionId);
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(t(K.sessionDeleted))),
          );
        }
        final names = store.names;
        final shares = sharesFor(s);
        final present = {for (final a in s.attendance) a.playerId: a};
        final owed = outstandingSen(s);
        final earlier = carriedOver(store.sessions, s);
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(t.date(s.date)),
            actions: [
              IconButton(
                tooltip: t(K.editSession),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push<int>(
                  MaterialPageRoute(
                    builder: (_) =>
                        SessionFormScreen(store: store, sessionId: s.id),
                  ),
                ),
              ),
              IconButton(
                tooltip: t(K.deleteSession),
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(t(K.deleteSessionConfirm)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(t(K.cancel)),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(t(K.delete)),
                        ),
                      ],
                    ),
                  );
                  if (sure == true && context.mounted) {
                    Navigator.of(context).pop();
                    await store.deleteSession(s.id);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ListTile(
                title: Text(s.venue, style: text.titleMedium),
                subtitle: Text(
                  t(K.sessionSummary, {
                    'start': formatClock(s.startMinute),
                    'end': formatClock(s.endMinute),
                    'courts': t.count(K.courtsOne, K.courtsOther, s.courts),
                    'rate': formatRm(s.courtRateSen),
                    'shuttles': t.count(
                      K.shuttlesOne,
                      K.shuttlesOther,
                      s.shuttles,
                    ),
                    'price': formatRm(s.shuttlePriceSen),
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _Figure(t(K.figCourts), formatRm(courtCostSen(s))),
                    _Figure(t(K.figShuttles), formatRm(shuttleCostSen(s))),
                    _Figure(t(K.figTotal), formatRm(totalCostSen(s))),
                    _Figure(t(K.figToCollect), formatRm(owed)),
                  ],
                ),
              ),
              _SplitPicker(
                label: t(K.courtCost),
                pickerKey: const Key('court-split'),
                mode: s.courtSplit,
                onChanged: (mode) =>
                    store.updateSession(s.copyWith(courtSplit: mode)),
              ),
              _SplitPicker(
                label: t(K.figShuttles),
                pickerKey: const Key('shuttle-split'),
                mode: s.shuttleSplit,
                onChanged: (mode) =>
                    store.updateSession(s.copyWith(shuttleSplit: mode)),
              ),
              if (s.guestFeeSen > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    t(
                      guestFeesCoverAll(s)
                          ? K.guestFeesCoverAll
                          : guestFeeApplies(s)
                          ? K.guestFeeApplies
                          : K.guestFeeWhen,
                      {'amount': formatRm(s.guestFeeSen)},
                    ),
                    style: text.bodySmall,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: OutlinedButton.icon(
                  key: const Key('open-queue'),
                  icon: const Icon(Icons.sports_tennis),
                  label: Text(
                    t(K.queueButton, {
                      'onCourt': onCourt(s).length,
                      'games': t.games(s.games.where((g) => g.finished).length),
                    }),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          QueueScreen(store: store, sessionId: s.id),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  t(K.whoCame, {'n': s.attendance.length}),
                  style: text.titleSmall,
                ),
              ),
              if (store.players.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t(K.addPlayersFirst)),
                ),
              for (final p in store.players)
                _PlayerRow(
                  name: p.name,
                  attendance: present[p.id],
                  session: s,
                  shareSen: shares[p.id],
                  earlierSen: earlier[p.id] ?? 0,
                  onToggle: () => attempt(
                    context,
                    () => store.toggleAttendance(s.id, p.id),
                  ),
                  onPaid: (paid) => store.setPaid(s.id, p.id, paid),
                  onTimes: () => _editTimes(context, s, present[p.id]!, p.name),
                  onGuest: (guest) =>
                      store.setAttendanceGuest(s.id, p.id, guest),
                ),
              if (s.attendance.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(t(K.messageForGroup), style: text.titleSmall),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        settleUpText(s, names, earlierSen: earlier, strings: t),
                        key: const Key('settle-text'),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: settleUpText(
                            s,
                            names,
                            earlierSen: earlier,
                            strings: t,
                          ),
                        ),
                      );
                      if (context.mounted) {
                        toast(context, t(K.copiedForChat));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(t(K.copyMessage)),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Read as one item, "Total RM 107.00", by screen readers.
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

class _SplitPicker extends StatelessWidget {
  const _SplitPicker({
    required this.label,
    required this.pickerKey,
    required this.mode,
    required this.onChanged,
  });

  final String label;
  final Key pickerKey;
  final SplitMode mode;
  final ValueChanged<SplitMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<SplitMode>(
              key: pickerKey,
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: SplitMode.equal,
                  label: Text(t(K.splitEqually)),
                ),
                ButtonSegment(
                  value: SplitMode.byMinutes,
                  label: Text(t(K.splitByTime)),
                ),
                ButtonSegment(
                  value: SplitMode.byGames,
                  label: Text(t(K.splitByGames)),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (m) => onChanged(m.single),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RowAction { toggleGuest, notPaid }

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.name,
    required this.attendance,
    required this.session,
    required this.shareSen,
    required this.earlierSen,
    required this.onToggle,
    required this.onPaid,
    required this.onTimes,
    required this.onGuest,
  });

  final String name;
  final Attendance? attendance;
  final Session session;
  final int? shareSen;

  /// Still owed from earlier sessions.
  final int earlierSen;
  final VoidCallback onToggle;
  final ValueChanged<bool> onPaid;
  final VoidCallback onTimes;
  final ValueChanged<bool> onGuest;

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    final a = attendance;
    final share = shareSen ?? 0;
    final due = a == null ? 0 : dueSen(a, share);
    final over = a == null ? 0 : overpaidSen(a, share);
    final paidInFull = a != null && a.paid && due == 0;
    final error = Theme.of(context).colorScheme.error;
    // With large text there is no room beside the name, so the share and
    // its buttons go on a line of their own under it.
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13;
    Widget controls(Attendance a) => Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(formatRm(share)),
        // A part-paid share shows unticked; ticking it records the new
        // amount in full.
        FilterChip(
          label: Text(
            t(K.paid),
            semanticsLabel: t(K.playerPaid, {'name': name}),
          ),
          selected: paidInFull,
          onSelected: onPaid,
        ),
        PopupMenuButton<_RowAction>(
          tooltip: t(K.moreFor, {'name': name}),
          onSelected: (action) => switch (action) {
            _RowAction.toggleGuest => onGuest(!a.guest),
            _RowAction.notPaid => onPaid(false),
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _RowAction.toggleGuest,
              child: Text(t(a.guest ? K.countAsRegular : K.countAsGuest)),
            ),
            // A part-paid share shows unticked, so this is the one way to
            // set it straight back to not paid.
            if (a.paid)
              PopupMenuItem(
                key: Key('not-paid-${a.playerId}'),
                value: _RowAction.notPaid,
                child: Text(t(K.markNotPaid)),
              ),
          ],
        ),
      ],
    );
    final times = a == null
        ? const <String, Object>{}
        : {
            'arrive': formatClock(session.startMinute + a.arriveMinute),
            'leave': formatClock(session.startMinute + a.leaveMinute),
          };
    return ListTile(
      leading: Checkbox(
        value: a != null,
        onChanged: (_) => onToggle(),
        semanticLabel: t(K.playerCame, {'name': name}),
      ),
      title: Text(name),
      subtitle: a == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  button: true,
                  onTap: onTimes,
                  label: t(K.changeTimesFor, {'name': name, ...times}),
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: onTimes,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 1,
                        child: Text(t(K.timesTapToChange, times)),
                      ),
                    ),
                  ),
                ),
                if (a.paid && due > 0)
                  Text(
                    t(K.shareWentUp, {
                      'paid': formatRm(a.paidSen!),
                      'due': formatRm(due),
                    }),
                    key: Key('due-${a.playerId}'),
                    style: TextStyle(color: error),
                  ),
                if (over > 0)
                  Text(
                    t(K.shareWentDown, {
                      'paid': formatRm(a.paidSen!),
                      'over': formatRm(over),
                    }),
                    key: Key('over-${a.playerId}'),
                  ),
                if (a.guest || earlierSen > 0)
                  Text(
                    [
                      if (a.guest) t(K.guest),
                      if (earlierSen > 0)
                        t(K.owedFromEarlier, {'amount': formatRm(earlierSen)}),
                    ].join(' · '),
                    style: TextStyle(color: earlierSen > 0 ? error : null),
                  ),
                if (stacked) controls(a),
              ],
            ),
      trailing: a == null || stacked ? null : controls(a),
    );
  }
}

/// Asks for arrival and leaving times; pops with the two texts, or null.
class _TimesDialog extends StatefulWidget {
  const _TimesDialog({
    required this.name,
    required this.arrive,
    required this.leave,
  });

  final String name;
  final String arrive;
  final String leave;

  @override
  State<_TimesDialog> createState() => _TimesDialogState();
}

class _TimesDialogState extends State<_TimesDialog> {
  late final _arrive = TextEditingController(text: widget.arrive);
  late final _leave = TextEditingController(text: widget.leave);

  @override
  void dispose() {
    _arrive.dispose();
    _leave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    return AlertDialog(
      title: Text(t(K.timesTitle, {'name': widget.name})),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('arrive'),
            controller: _arrive,
            decoration: InputDecoration(labelText: t(K.arrivedLabel)),
          ),
          TextField(
            key: const Key('leave'),
            controller: _leave,
            decoration: InputDecoration(labelText: t(K.leftLabel)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t(K.cancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_arrive.text, _leave.text)),
          child: Text(t(K.save)),
        ),
      ],
    );
  }
}
