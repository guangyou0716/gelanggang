import '../l10n/strings.dart';
import 'models.dart';
import 'money.dart';
import 'queue.dart';
import 'split.dart';

/// Court hire: courts x hourly rate x hours, rounded half up to the sen.
int courtCostSen(Session s) {
  final exact = s.courts * s.courtRateSen * s.durationMinutes;
  return (exact * 2 + 60) ~/ 120;
}

int shuttleCostSen(Session s) => s.shuttles * s.shuttlePriceSen;

int totalCostSen(Session s) => courtCostSen(s) + shuttleCostSen(s);

/// One player's part of a session's cost.
typedef Share = ({int courtSen, int shuttleSen, int guestFeeSen});

extension ShareTotal on Share {
  int get totalSen => courtSen + shuttleSen + guestFeeSen;
}

/// Whether [s] charges its guests the flat fee: it has a fee, at least one
/// guest and at least one regular to share the rest. Otherwise guests share
/// like everyone else.
bool guestFeeApplies(Session s) =>
    s.guestFeeSen > 0 &&
    s.attendance.any((a) => a.guest) &&
    s.attendance.any((a) => !a.guest);

/// Whether the guests' flat fees would come to the whole session or more, in
/// which case the guests split the total instead (see [shareBreakdown]).
bool guestFeesCoverAll(Session s) =>
    guestFeeApplies(s) &&
    s.guestFeeSen * s.attendance.where((a) => a.guest).length >=
        totalCostSen(s);

/// How each player present shares [s], keyed by player id. The parts add up to
/// exactly [totalCostSen]. Empty when nobody is present.
///
/// With a guest fee, each guest pays the flat fee (it goes towards the court
/// hire first, then the shuttles) and the regulars share what is left. If the
/// fees would come to more than the whole session, the guests split the total
/// equally instead and the regulars pay nothing.
Map<int, Share> shareBreakdown(Session s) {
  if (s.attendance.isEmpty) return {};
  var courtPot = courtCostSen(s);
  var shuttlePot = shuttleCostSen(s);
  final fees = <int, int>{};
  var payers = s.attendance;
  if (guestFeeApplies(s)) {
    final guests = [
      for (final a in s.attendance)
        if (a.guest) a.playerId,
    ];
    final total = courtPot + shuttlePot;
    final feeTotal = s.guestFeeSen * guests.length;
    if (feeTotal >= total) {
      final equal = splitByWeights(total, List.filled(guests.length, 1));
      for (var i = 0; i < guests.length; i++) {
        fees[guests[i]] = equal[i];
      }
      courtPot = 0;
      shuttlePot = 0;
    } else {
      for (final g in guests) {
        fees[g] = s.guestFeeSen;
      }
      final fromCourt = feeTotal < courtPot ? feeTotal : courtPot;
      courtPot -= fromCourt;
      shuttlePot -= feeTotal - fromCourt;
    }
    payers = [
      for (final a in s.attendance)
        if (!a.guest) a,
    ];
  }
  final court = _splitPot(s, courtPot, payers, s.courtSplit);
  final shuttle = _splitPot(s, shuttlePot, payers, s.shuttleSplit);
  return {
    for (final a in s.attendance)
      a.playerId: (
        courtSen: court[a.playerId] ?? 0,
        shuttleSen: shuttle[a.playerId] ?? 0,
        guestFeeSen: fees[a.playerId] ?? 0,
      ),
  };
}

Map<int, int> _splitPot(
  Session s,
  int pot,
  List<Attendance> payers,
  SplitMode mode,
) {
  if (payers.isEmpty) return {};
  final games = mode == SplitMode.byGames ? gamesPlayed(s) : const <int, int>{};
  final weights = [
    for (final a in payers)
      switch (mode) {
        SplitMode.equal => 1,
        SplitMode.byMinutes => a.minutes,
        SplitMode.byGames => games[a.playerId] ?? 0,
      },
  ];
  // Nobody present for any minutes, or no games logged yet: split equally.
  final useWeights = weights.every((w) => w == 0)
      ? List.filled(weights.length, 1)
      : weights;
  final shares = splitByWeights(pot, useWeights);
  return {
    for (var i = 0; i < payers.length; i++) payers[i].playerId: shares[i],
  };
}

/// What each player present owes for [s] in total, keyed by player id,
/// adding up to exactly [totalCostSen]. Empty when nobody is present.
Map<int, int> sharesFor(Session s) => {
  for (final e in shareBreakdown(s).entries) e.key: e.value.totalSen,
};

/// What [a] still owes towards a [shareSen] share: all of it when not paid,
/// nothing when paid before amounts were recorded, otherwise whatever the
/// share has grown by since they paid (a late arrival who changed the split,
/// more shuttles, ...).
int dueSen(Attendance a, int shareSen) {
  if (!a.paid) return shareSen;
  final paid = a.paidSen;
  if (paid == null || paid >= shareSen) return 0;
  return shareSen - paid;
}

/// What [a] paid beyond a [shareSen] share that has since shrunk; the
/// organiser may want to give it back.
int overpaidSen(Attendance a, int shareSen) {
  final paid = a.paidSen;
  if (!a.paid || paid == null || paid <= shareSen) return 0;
  return paid - shareSen;
}

/// Total still owed for [s] (see [dueSen]).
int outstandingSen(Session s) {
  final shares = sharesFor(s);
  return s.attendance.fold(
    0,
    (sum, a) => sum + dueSen(a, shares[a.playerId] ?? 0),
  );
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

K _modeText(SplitMode m) => switch (m) {
  SplitMode.equal => K.modeEqually,
  SplitMode.byMinutes => K.modeByTime,
  SplitMode.byGames => K.modeByGames,
};

/// A message the organiser can paste into the group chat, in [strings]'
/// language. Nothing is sent by the app, and no payment links are made.
///
/// [earlierSen] is what each player still owes from earlier sessions (see
/// `carriedOver` in history.dart); it is added to their line.
String settleUpText(
  Session s,
  Map<int, String> names, {
  Map<int, int> earlierSen = const {},
  Strings strings = Strings.en,
}) {
  final t = strings;
  final shares = sharesFor(s);
  final buffer = StringBuffer()
    ..writeln(
      t(K.msgHeader, {
        'date': t.date(s.date),
        'start': formatClock(s.startMinute),
        'end': formatClock(s.endMinute),
        'venue': s.venue,
      }),
    )
    ..writeln(
      t(K.msgCosts, {
        'courts': formatRm(courtCostSen(s)),
        'shuttles': formatRm(shuttleCostSen(s)),
        'total': formatRm(totalCostSen(s)),
      }),
    );
  if (guestFeesCoverAll(s)) {
    buffer.writeln(t(K.msgGuestsShareAll));
  } else if (guestFeeApplies(s)) {
    buffer.writeln(t(K.msgGuestsFlat, {'amount': formatRm(s.guestFeeSen)}));
  }
  buffer.writeln(
    s.courtSplit == s.shuttleSplit
        ? t(K.msgSplit, {'mode': _modeText(s.courtSplit)})
        : t(K.msgSplitEach, {
            'court': _modeText(s.courtSplit),
            'shuttle': _modeText(s.shuttleSplit),
          }),
  );
  for (final a in s.attendance) {
    final share = shares[a.playerId] ?? 0;
    final earlier = earlierSen[a.playerId] ?? 0;
    final due = dueSen(a, share);
    final over = overpaidSen(a, share);
    final money = {
      'share': formatRm(share),
      'earlier': formatRm(earlier),
      'due': formatRm(due),
      'over': formatRm(over),
      if (a.paidSen != null) 'paid': formatRm(a.paidSen!),
    };
    final String amount;
    if (a.paid && due > 0) {
      amount = earlier > 0
          ? t(K.msgPartPaidEarlier, {
              ...money,
              'total': formatRm(due + earlier),
            })
          : t(K.msgPartPaid, money);
    } else if (a.paid) {
      amount =
          t(over > 0 ? K.msgPaidGiveBack : K.msgPaidThanks, money) +
          (earlier > 0 ? t(K.msgStillOwedEarlier, money) : '');
    } else if (earlier > 0) {
      amount = t(K.msgWithEarlier, {
        ...money,
        'total': formatRm(share + earlier),
      });
    } else {
      amount = formatRm(share);
    }
    buffer.writeln(
      t(a.guest ? K.msgLineGuest : K.msgLine, {
        'name': names[a.playerId] ?? '?',
        'amount': amount,
      }),
    );
  }
  return buffer.toString().trimRight();
}
