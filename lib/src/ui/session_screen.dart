import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/store.dart';
import '../domain/costs.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/queue.dart';
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
      toast(context, 'Use HH:MM, like 20:30');
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
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.session(sessionId);
        if (s == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This session was deleted.')),
          );
        }
        final names = store.names;
        final shares = sharesFor(s);
        final present = {for (final a in s.attendance) a.playerId: a};
        final owed = outstandingSen(s);
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.date),
            actions: [
              IconButton(
                tooltip: 'Edit session',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push<int>(
                  MaterialPageRoute(
                    builder: (_) =>
                        SessionFormScreen(store: store, sessionId: s.id),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Delete session',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete this session?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete'),
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
                  '${formatClock(s.startMinute)}-${formatClock(s.endMinute)} · '
                  '${s.courts} court${s.courts == 1 ? '' : 's'} at ${formatRm(s.courtRateSen)}/hour · '
                  '${s.shuttles} shuttle${s.shuttles == 1 ? '' : 's'} at ${formatRm(s.shuttlePriceSen)}',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _Figure('Courts', formatRm(courtCostSen(s))),
                    _Figure('Shuttles', formatRm(shuttleCostSen(s))),
                    _Figure('Total', formatRm(totalCostSen(s))),
                    _Figure('To collect', formatRm(owed)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SegmentedButton<SplitMode>(
                  segments: const [
                    ButtonSegment(
                      value: SplitMode.equal,
                      label: Text('Split equally'),
                    ),
                    ButtonSegment(
                      value: SplitMode.byMinutes,
                      label: Text('By time played'),
                    ),
                  ],
                  selected: {s.splitMode},
                  onSelectionChanged: (mode) =>
                      store.updateSession(s.copyWith(splitMode: mode.single)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: OutlinedButton.icon(
                  key: const Key('open-queue'),
                  icon: const Icon(Icons.sports_tennis),
                  label: Text(
                    'Court queue · ${onCourt(s).length} on court · '
                    '${gamesLabel(s.games.where((g) => g.finished).length)} played',
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
                  'Who came (${s.attendance.length})',
                  style: text.titleSmall,
                ),
              ),
              if (store.players.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Add players first (Players, top right).'),
                ),
              for (final p in store.players)
                _PlayerRow(
                  name: p.name,
                  attendance: present[p.id],
                  session: s,
                  shareSen: shares[p.id],
                  onToggle: () => attempt(
                    context,
                    () => store.toggleAttendance(s.id, p.id),
                  ),
                  onPaid: (paid) => store.updateAttendance(
                    s.id,
                    present[p.id]!.copyWith(paid: paid),
                  ),
                  onTimes: () => _editTimes(context, s, present[p.id]!, p.name),
                ),
              if (s.attendance.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Message for the group', style: text.titleSmall),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        settleUpText(s, names),
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
                        ClipboardData(text: settleUpText(s, names)),
                      );
                      if (context.mounted) {
                        toast(
                          context,
                          'Copied. Paste it into your group chat.',
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy message'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium),
        Text(value, style: text.titleLarge),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.name,
    required this.attendance,
    required this.session,
    required this.shareSen,
    required this.onToggle,
    required this.onPaid,
    required this.onTimes,
  });

  final String name;
  final Attendance? attendance;
  final Session session;
  final int? shareSen;
  final VoidCallback onToggle;
  final ValueChanged<bool> onPaid;
  final VoidCallback onTimes;

  @override
  Widget build(BuildContext context) {
    final a = attendance;
    return ListTile(
      leading: Checkbox(
        value: a != null,
        onChanged: (_) => onToggle(),
        semanticLabel: '$name came',
      ),
      title: Text(name),
      subtitle: a == null
          ? null
          : InkWell(
              onTap: onTimes,
              child: Text(
                '${formatClock(session.startMinute + a.arriveMinute)}-'
                '${formatClock(session.startMinute + a.leaveMinute)} · tap to change',
              ),
            ),
      trailing: a == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatRm(shareSen ?? 0)),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Paid'),
                  selected: a.paid,
                  onSelected: onPaid,
                ),
              ],
            ),
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
    return AlertDialog(
      title: Text('${widget.name}: time at the court'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('arrive'),
            controller: _arrive,
            decoration: const InputDecoration(labelText: 'Arrived (HH:MM)'),
          ),
          TextField(
            key: const Key('leave'),
            controller: _leave,
            decoration: const InputDecoration(labelText: 'Left (HH:MM)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_arrive.text, _leave.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
