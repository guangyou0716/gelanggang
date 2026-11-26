import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/store.dart';
import '../domain/costs.dart';
import '../domain/models.dart';
import '../domain/money.dart';
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

  Session? get _existing =>
      widget.sessionId == null ? null : widget.store.session(widget.sessionId!);

  @override
  void initState() {
    super.initState();
    final s = _existing;
    String rm(int sen) => (sen / 100).toStringAsFixed(2);
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
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;
  String? _clock(String? v) =>
      parseClock(v ?? '') == null ? 'Use HH:MM, like 20:00' : null;
  String? _money(String? v) =>
      parseRm(v ?? '') == null ? 'Enter an amount like 20 or 4.50' : null;
  String? _count(String? v, int min, int max) {
    final n = int.tryParse((v ?? '').trim());
    return (n == null || n < min || n > max)
        ? 'Enter a number from $min to $max'
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
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit session' : 'New session')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field('date', 'Date (YYYY-MM-DD)', validator: _required),
            _field(
              'venue',
              'Venue',
              validator: _required,
              hint: 'e.g. Dewan Badminton Taman Jaya',
            ),
            Row(
              children: [
                Expanded(child: _field('start', 'Start', validator: _clock)),
                const SizedBox(width: 12),
                Expanded(child: _field('end', 'End', validator: _clock)),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _field(
                    'courts',
                    'Courts',
                    validator: (v) => _count(v, 1, 20),
                    keyboard: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'rate',
                    'Court rate (RM/hour)',
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
                    'Shuttles used',
                    validator: (v) => _count(v, 0, 500),
                    keyboard: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'shuttlePrice',
                    'Price per shuttle (RM)',
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
              'Guest fee (RM, 0 = guests share like regulars)',
              validator: _money,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              hint: 'e.g. 15',
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('save-session'),
              onPressed: _save,
              child: Text(editing ? 'Save' : 'Create session'),
            ),
          ],
        ),
      ),
    );
  }
}
