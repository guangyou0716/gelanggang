import 'models.dart';
import 'money.dart';
import 'split.dart';

/// Court hire: courts x hourly rate x hours, rounded half up to the sen.
int courtCostSen(Session s) {
  final exact = s.courts * s.courtRateSen * s.durationMinutes;
  return (exact * 2 + 60) ~/ 120;
}

int shuttleCostSen(Session s) => s.shuttles * s.shuttlePriceSen;

int totalCostSen(Session s) => courtCostSen(s) + shuttleCostSen(s);

/// What each player present owes for [s], keyed by player id, adding up to
/// exactly [totalCostSen]. Empty when nobody is present.
Map<int, int> sharesFor(Session s) {
  if (s.attendance.isEmpty) return {};
  final weights = [
    for (final a in s.attendance)
      switch (s.splitMode) {
        SplitMode.equal => 1,
        SplitMode.byMinutes => a.minutes,
      },
  ];
  // Everyone present for zero minutes: fall back to an equal split.
  final useWeights = weights.every((w) => w == 0)
      ? List.filled(weights.length, 1)
      : weights;
  final shares = splitByWeights(totalCostSen(s), useWeights);
  return {
    for (var i = 0; i < s.attendance.length; i++)
      s.attendance[i].playerId: shares[i],
  };
}

/// Total still owed for [s] by players not marked paid.
int outstandingSen(Session s) {
  final shares = sharesFor(s);
  return s.attendance
      .where((a) => !a.paid)
      .fold(0, (sum, a) => sum + (shares[a.playerId] ?? 0));
}

/// "20:00" for 1200.
String formatClock(int minuteOfDay) {
  final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
  final m = (minuteOfDay % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Parses "20:00" or "8:30" into minutes after midnight; null when invalid.
int? parseClock(String input) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(input.trim());
  if (match == null) return null;
  final h = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  if (h > 23 || m > 59) return null;
  return h * 60 + m;
}

/// A message the organiser can paste into the group chat. Nothing is sent by
/// the app, and no payment links are made.
String settleUpText(Session s, Map<int, String> names) {
  final shares = sharesFor(s);
  final buffer = StringBuffer()
    ..writeln(
      'Badminton ${s.date} ${formatClock(s.startMinute)}-${formatClock(s.endMinute)}, ${s.venue}',
    )
    ..writeln(
      'Courts ${formatRm(courtCostSen(s))} + shuttles ${formatRm(shuttleCostSen(s))} = ${formatRm(totalCostSen(s))}',
    )
    ..writeln(switch (s.splitMode) {
      SplitMode.equal => 'Split equally:',
      SplitMode.byMinutes => 'Split by time played:',
    });
  for (final a in s.attendance) {
    final paid = a.paid ? ' (paid, thanks!)' : '';
    buffer.writeln(
      '- ${names[a.playerId] ?? '?'}: ${formatRm(shares[a.playerId] ?? 0)}$paid',
    );
  }
  return buffer.toString().trimRight();
}
