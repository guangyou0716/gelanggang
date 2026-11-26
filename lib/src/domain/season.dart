/// A season summary: each player's sessions, games, wins and money over a
/// date range, and the same as CSV for a spreadsheet.
library;

import 'history.dart';
import 'models.dart';

/// The date ranges the summary offers.
enum SeasonRange { thisMonth, lastMonth, last3Months, thisYear, all }

/// First and last ISO date (both included) of [range] for [today]; null
/// for [SeasonRange.all].
({String from, String to})? datesFor(SeasonRange range, DateTime today) {
  String iso(int y, int m, int d) =>
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}';
  // Day 0 of the next month is the last day of this one.
  String lastDay(int y, int m) {
    final d = DateTime.utc(y, m + 1, 0);
    return iso(d.year, d.month, d.day);
  }

  final y = today.year, m = today.month;
  switch (range) {
    case SeasonRange.thisMonth:
      return (from: iso(y, m, 1), to: lastDay(y, m));
    case SeasonRange.lastMonth:
      final first = DateTime.utc(y, m - 1);
      return (
        from: iso(first.year, first.month, 1),
        to: lastDay(first.year, first.month),
      );
    case SeasonRange.last3Months:
      // This month and the two before it.
      final first = DateTime.utc(y, m - 2);
      return (from: iso(first.year, first.month, 1), to: lastDay(y, m));
    case SeasonRange.thisYear:
      return (from: iso(y, 1, 1), to: iso(y, 12, 31));
    case SeasonRange.all:
      return null;
  }
}

/// One player's line in the summary.
class SeasonRow {
  const SeasonRow({
    required this.playerId,
    required this.name,
    required this.guest,
    required this.record,
    required this.sessionsInRange,
  });

  final int playerId;
  final String name;

  /// A guest in the roster.
  final bool guest;
  final PlayerRecord record;

  /// How many sessions the summary covers (for the attendance rate).
  final int sessionsInRange;

  /// Sessions attended out of all sessions in the range, 0-100, rounded.
  int get attendancePercent => sessionsInRange == 0
      ? 0
      : (record.sessions * 100 / sessionsInRange).round();
}

/// The summary over [range] for [today].
class SeasonSummary {
  SeasonSummary._(this.sessions, this.rows);

  /// Builds the summary from all [sessions] and the roster [players].
  /// Players who came to no session in the range are left out; someone no
  /// longer in the roster still counts (named "?").
  factory SeasonSummary.of(
    Iterable<Session> sessions,
    List<Player> players,
    SeasonRange range,
    DateTime today,
  ) {
    final dates = datesFor(range, today);
    final picked = [
      for (final s in sessions)
        if (dates == null ||
            (s.date.compareTo(dates.from) >= 0 &&
                s.date.compareTo(dates.to) <= 0))
          s,
    ];
    final byId = {for (final p in players) p.id: p};
    final rows = [
      for (final e in playerRecords(picked).entries)
        SeasonRow(
          playerId: e.key,
          name: byId[e.key]?.name ?? '?',
          guest: byId[e.key]?.guest ?? false,
          record: e.value,
          sessionsInRange: picked.length,
        ),
    ]..sort(compareRows);
    return SeasonSummary._(picked.length, List.unmodifiable(rows));
  }

  /// Most sessions first, then most games, then by name.
  static int compareRows(SeasonRow a, SeasonRow b) {
    if (a.record.sessions != b.record.sessions) {
      return b.record.sessions.compareTo(a.record.sessions);
    }
    if (a.record.games != b.record.games) {
      return b.record.games.compareTo(a.record.games);
    }
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.playerId.compareTo(b.playerId);
  }

  /// Number of sessions in the range.
  final int sessions;
  final List<SeasonRow> rows;

  int get shareSen => rows.fold(0, (sum, r) => sum + r.record.shareSen);
  int get paidSen => rows.fold(0, (sum, r) => sum + r.record.paidSen);
  int get owedSen => rows.fold(0, (sum, r) => sum + r.record.owedSen);

  /// The summary as CSV (RFC 4180: comma separated, CRLF line ends, fields
  /// quoted when needed). Amounts are plain ringgit with two decimals so a
  /// spreadsheet reads them as numbers. Column names stay English in every
  /// language so a sheet built on them keeps working.
  String toCsv() {
    String rm(int sen) {
      final sign = sen < 0 ? '-' : '';
      final abs = sen.abs();
      return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
    }

    final lines = [
      [
        'player',
        'guest',
        'sessions',
        'attendance_percent',
        'games',
        'wins',
        'share_rm',
        'paid_rm',
        'owed_rm',
      ],
      for (final r in rows)
        [
          r.name,
          r.guest ? 'yes' : 'no',
          '${r.record.sessions}',
          '${r.attendancePercent}',
          '${r.record.games}',
          '${r.record.wins}',
          rm(r.record.shareSen),
          rm(r.record.paidSen),
          rm(r.record.owedSen),
        ],
    ];
    return '${lines.map((l) => l.map(csvField).join(',')).join('\r\n')}\r\n';
  }
}

/// One CSV field. Text a spreadsheet would run as a formula (starting with
/// =, +, -, @, a tab or a carriage return) gets a leading apostrophe, so a
/// player named "=HYPERLINK(...)" stays text. Fields with a comma, quote or
/// line break are quoted, with quotes doubled.
String csvField(String value) {
  var v = value;
  if (v.isNotEmpty && '=+-@\t\r'.contains(v[0])) v = "'$v";
  if (v.contains(RegExp('[",\r\n]'))) v = '"${v.replaceAll('"', '""')}"';
  return v;
}
