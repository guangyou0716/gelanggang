import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/store.dart';
import '../domain/costs.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../l10n/language.dart';
import 'common.dart';

/// Creates a session, or edits one when [sessionId] is given. Pops with the
/// session id after saving.
class SessionFormScreen extends StatefulWidget {
  const SessionFormScreen({super.key, required this.store, this.sessionId});

  final AppStore store;
  final int? sessionId;

  @override
  State<SessionFormScreen> createState() => _SessionFormScreenState();
}

class _SessionFormScreenState extends State<SessionFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;

  /// When creating: the latest session, offered to fill the form in.
  Session? _template;

  /// The form was filled in from [_template].
  bool _filled = false;

  /// Check in [_template]'s players (still in the roster) on save.
  bool _bringPlayers = true;

  Session? get _existing =>
      widget.sessionId == null ? null : widget.store.session(widget.sessionId!);

  @override
  void initState() {
    super.initState();
    final s = _existing;
    const rm = _rm;
    _c = {
      'date': TextEditingController(text: s?.date ?? isoDate(DateTime.now())),
      'venue': TextEditingController(text: s?.venue ?? ''),
      'start': TextEditingController(
        text: formatClock(s?.startMinute ?? 20 * 60),
      ),
      'end': TextEditingController(text: formatClock(s?.endMinute ?? 22 * 60)),
      'courts': TextEditingController(text: '${s?.courts ?? 2}'),
      'rate': TextEditingController(text: s == null ? '' : rm(s.courtRateSen)),
      'shuttles': TextEditingController(text: '${s?.shuttles ?? 0}'),
      'shuttlePrice': TextEditingController(
        text: s == null ? '' : rm(s.shuttlePriceSen),
      ),
      'guestFee': TextEditingController(
        text: s == null ? '0' : rm(s.guestFeeSen),
      ),
    };
    if (widget.sessionId == null) _template = widget.store.lastSession;
  }

  static String _rm(int sen) => (sen / 100).toStringAsFixed(2);

  /// Copies the last session's venue, times, courts and prices into the
  /// form. The date stays today and shuttles start at 0: those are new.
  void _fillFromTemplate() {
    final s = _template!;
    setState(() {
      _filled = true;
      _c['venue']!.text = s.venue;
      _c['start']!.text = formatClock(s.startMinute);
      _c['end']!.text = formatClock(s.endMinute);
      _c['courts']!.text = '${s.courts}';
      _c['rate']!.text = _rm(s.courtRateSen);
      _c['shuttles']!.text = '0';
      _c['shuttlePrice']!.text = _rm(s.shuttlePriceSen);
      _c['guestFee']!.text = _rm(s.guestFeeSen);
    });
  }

  Widget _repeatCard(Session s) {
    final t = context.s;
    final players = widget.store.rosterPlayersAt(s);
    if (_filled) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(K.repeatFilled, {'date': t.date(s.date)}),
              key: const Key('repeat-filled'),
            ),
            if (players.isNotEmpty)
              CheckboxListTile(
                key: const Key('repeat-players'),
                contentPadding: EdgeInsets.zero,
                value: _bringPlayers,
                onChanged: (v) => setState(() => _bringPlayers = v ?? false),
                title: Text(
                  t(K.repeatPlayers, {'players': t.players(players.length)}),
                ),
              ),
          ],
        ),
      );
    }
    return Card(
      key: const Key('repeat-card'),
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: const Icon(Icons.replay),
        title: Text(t(K.repeatLast)),
        subtitle: Text(
          t(K.repeatLastBody, {
            'date': t.date(s.date),
            'venue': s.venue,
            'players': t.players(players.length),
          }),
        ),
        trailing: TextButton(
          key: const Key('repeat-fill'),
          onPressed: _fillFromTemplate,
          child: Text(t(K.repeatFill)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? context.s(K.required) : null;
  String? _clock(String? v) => parseClock(v ?? '') == null
      ? context.s(K.useClock, {'example': '20:00'})
      : null;
  String? _money(String? v) =>
      parseRm(v ?? '') == null ? context.s(K.amountHint) : null;
  String? _count(String? v, int min, int max) {
    final n = int.tryParse((v ?? '').trim());
    return (n == null || n < min || n > max)
        ? context.s(K.numberRange, {'min': min, 'max': max})
        : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final store = widget.store;
    final start = parseClock(_c['start']!.text)!;
    final end = parseClock(_c['end']!.text)!;
    final courts = int.parse(_c['courts']!.text.trim());
    final rate = parseRm(_c['rate']!.text)!;
    final shuttles = int.parse(_c['shuttles']!.text.trim());
    final shuttlePrice = parseRm(_c['shuttlePrice']!.text)!;
    final guestFee = parseRm(_c['guestFee']!.text)!;
    final existing = _existing;
    late int id;
    final template = _filled ? _template : null;
    final ok = await attempt(context, () async {
      if (existing == null) {
        id = (await store.createSession(
          date: _c['date']!.text.trim(),
          venue: _c['venue']!.text,
          startMinute: start,
          endMinute: end,
          courts: courts,
          courtRateSen: rate,
          shuttles: shuttles,
          shuttlePriceSen: shuttlePrice,
          guestFeeSen: guestFee,
          courtSplit: template?.courtSplit ?? SplitMode.equal,
          shuttleSplit: template?.shuttleSplit ?? SplitMode.equal,
          singlesCourts: template?.singlesCourts ?? const [],
          playerIds: template != null && _bringPlayers
              ? store.rosterPlayersAt(template)
              : const [],
        )).id;
      } else {
        // A shorter session cuts arrival/leaving times to fit.
        final duration = end - start;
        id = existing.id;
        await store.updateSession(
          existing.copyWith(
            date: _c['date']!.text.trim(),
            venue: _c['venue']!.text.trim(),
            startMinute: start,
            endMinute: end,
            courts: courts,
            courtRateSen: rate,
            shuttles: shuttles,
            shuttlePriceSen: shuttlePrice,
            guestFeeSen: guestFee,
            attendance: [
              for (final a in existing.attendance)
                a.copyWith(
                  arriveMinute: a.arriveMinute.clamp(
                    0,
                    duration < 0 ? 0 : duration,
                  ),
                  leaveMinute: a.leaveMinute.clamp(
                    0,
                    duration < 0 ? 0 : duration,
                  ),
                ),
            ],
          ),
        );
      }
    });
    if (ok && mounted) Navigator.of(context).pop(id);
  }

  Widget _field(
    String key,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: Key('field-$key'),
      controller: _c[key],
      keyboardType: keyboard,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final editing = widget.sessionId != null;
    final t = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(t(editing ? K.editSession : K.newSession))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_template case final s?) _repeatCard(s),
            _field('date', t(K.dateField), validator: _required),
            _field(
              'venue',
              t(K.venue),
              validator: _required,
              hint: t(K.venueHint),
            ),
            Row(
              children: [
                Expanded(child: _field('start', t(K.start), validator: _clock)),
                const SizedBox(width: 12),
                Expanded(child: _field('end', t(K.end), validator: _clock)),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _field(
                    'courts',
                    t(K.figCourts),
                    validator: (v) => _count(v, 1, 20),
                    keyboard: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'rate',
                    t(K.courtRateField),
                    validator: _money,
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _field(
                    'shuttles',
                    t(K.shuttlesUsed),
                    validator: (v) => _count(v, 0, 500),
                    keyboard: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'shuttlePrice',
                    t(K.shuttlePrice),
                    validator: _money,
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            _field(
              'guestFee',
              t(K.guestFeeField),
              validator: _money,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              hint: t(K.guestFeeHint),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('save-session'),
              onPressed: _save,
              child: Text(t(editing ? K.save : K.createSession)),
            ),
          ],
        ),
      ),
    );
  }
}
