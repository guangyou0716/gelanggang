/// Data for one organiser's badminton group. Everything is stored on the
/// device as JSON; there are no accounts and no server.
library;

class Player {
  const Player({required this.id, required this.name, this.guest = false});

  final int id;
  final String name;

  /// Not a regular: new check-ins start as guests (see [Attendance.guest]).
  final bool guest;

  Player copyWith({bool? guest}) =>
      Player(id: id, name: name, guest: guest ?? this.guest);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (guest) 'guest': true,
  };

  static Player fromJson(Map<String, Object?> json) => Player(
    id: json['id']! as int,
    name: json['name']! as String,
    guest: json['guest'] as bool? ?? false,
  );
}

/// How a session's cost is shared.
enum SplitMode {
  /// Everyone present pays the same.
  equal,

  /// In proportion to the minutes each player was there (late arrivals and
  /// early leavers pay less).
  byMinutes,

  /// In proportion to the games each player started (handy for shuttles).
  byGames;

  /// Unknown or missing names (older or damaged data) read as [equal].
  static SplitMode parse(Object? name) => SplitMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => SplitMode.equal,
  );
}

/// A player at a session, with the minutes after the session start when they
/// arrived and left.
class Attendance {
  const Attendance({
    required this.playerId,
    required this.arriveMinute,
    required this.leaveMinute,
    this.paid = false,
    this.resting = false,
    this.guest = false,
  });

  final int playerId;
  final int arriveMinute;
  final int leaveMinute;
  final bool paid;

  /// Sitting out: still counted for the cost split, but not suggested for the
  /// next game.
  final bool resting;

  /// A guest at this session: pays the session's flat guest fee (when it has
  /// one) instead of a share. Kept per session, so changing the roster later
  /// does not rewrite old sessions.
  final bool guest;

  int get minutes => leaveMinute - arriveMinute;

  Attendance copyWith({
    int? arriveMinute,
    int? leaveMinute,
    bool? paid,
    bool? resting,
    bool? guest,
  }) => Attendance(
    playerId: playerId,
    arriveMinute: arriveMinute ?? this.arriveMinute,
    leaveMinute: leaveMinute ?? this.leaveMinute,
    paid: paid ?? this.paid,
    resting: resting ?? this.resting,
    guest: guest ?? this.guest,
  );

  Map<String, Object?> toJson() => {
    'playerId': playerId,
    'arrive': arriveMinute,
    'leave': leaveMinute,
    'paid': paid,
    if (resting) 'resting': true,
    if (guest) 'guest': true,
  };

  static Attendance fromJson(Map<String, Object?> json) => Attendance(
    playerId: json['playerId']! as int,
    arriveMinute: json['arrive']! as int,
    leaveMinute: json['leave']! as int,
    paid: json['paid'] as bool? ?? false,
    resting: json['resting'] as bool? ?? false,
    guest: json['guest'] as bool? ?? false,
  );
}

/// One evening (or morning) of badminton.
class Session {
  const Session({
    required this.id,
    required this.date,
    required this.venue,
    required this.startMinute,
    required this.endMinute,
    required this.courts,
    required this.courtRateSen,
    required this.shuttles,
    required this.shuttlePriceSen,
    this.courtSplit = SplitMode.equal,
    this.shuttleSplit = SplitMode.equal,
    this.guestFeeSen = 0,
    this.attendance = const [],
    this.games = const [],
  });

  final int id;

  /// ISO date, e.g. "2026-11-26".
  final String date;
  final String venue;

  /// Minutes after midnight, e.g. 20:00 is 1200. [endMinute] is after
  /// [startMinute] on the same day.
  final int startMinute;
  final int endMinute;
  final int courts;

  /// Price of one court for one hour.
  final int courtRateSen;
  final int shuttles;
  final int shuttlePriceSen;

  /// How the court hire is shared.
  final SplitMode courtSplit;

  /// How the shuttle cost is shared.
  final SplitMode shuttleSplit;

  /// Flat fee each guest pays instead of a share; 0 means guests share like
  /// everyone else.
  final int guestFeeSen;
  final List<Attendance> attendance;

  /// Doubles games in the order they were started.
  final List<Game> games;

  int get durationMinutes => endMinute - startMinute;

  Session copyWith({
    String? date,
    String? venue,
    int? startMinute,
    int? endMinute,
    int? courts,
    int? courtRateSen,
    int? shuttles,
    int? shuttlePriceSen,
    SplitMode? courtSplit,
    SplitMode? shuttleSplit,
    int? guestFeeSen,
    List<Attendance>? attendance,
    List<Game>? games,
  }) => Session(
    id: id,
    date: date ?? this.date,
    venue: venue ?? this.venue,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    courts: courts ?? this.courts,
    courtRateSen: courtRateSen ?? this.courtRateSen,
    shuttles: shuttles ?? this.shuttles,
    shuttlePriceSen: shuttlePriceSen ?? this.shuttlePriceSen,
    courtSplit: courtSplit ?? this.courtSplit,
    shuttleSplit: shuttleSplit ?? this.shuttleSplit,
    guestFeeSen: guestFeeSen ?? this.guestFeeSen,
    attendance: attendance ?? this.attendance,
    games: games ?? this.games,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'date': date,
    'venue': venue,
    'start': startMinute,
    'end': endMinute,
    'courts': courts,
    'courtRateSen': courtRateSen,
    'shuttles': shuttles,
    'shuttlePriceSen': shuttlePriceSen,
    // Read by app versions before separate court/shuttle modes.
    'splitMode': courtSplit.name,
    'courtSplit': courtSplit.name,
    'shuttleSplit': shuttleSplit.name,
    if (guestFeeSen != 0) 'guestFeeSen': guestFeeSen,
    'attendance': [for (final a in attendance) a.toJson()],
    'games': [for (final g in games) g.toJson()],
  };

  static Session fromJson(Map<String, Object?> json) {
    final guestFeeSen = json['guestFeeSen'] as int? ?? 0;
    if (guestFeeSen < 0) {
      throw const FormatException('A guest fee cannot be negative');
    }
    return Session(
      id: json['id']! as int,
      date: json['date']! as String,
      venue: json['venue']! as String,
      startMinute: json['start']! as int,
      endMinute: json['end']! as int,
      courts: json['courts']! as int,
      courtRateSen: json['courtRateSen']! as int,
      shuttles: json['shuttles']! as int,
      shuttlePriceSen: json['shuttlePriceSen']! as int,
      // Saved before separate modes: one mode for both costs.
      courtSplit: SplitMode.parse(json['courtSplit'] ?? json['splitMode']),
      shuttleSplit: SplitMode.parse(json['shuttleSplit'] ?? json['splitMode']),
      guestFeeSen: guestFeeSen,
      attendance: [
        for (final a in json['attendance']! as List<Object?>)
          Attendance.fromJson((a! as Map).cast<String, Object?>()),
      ],
      // Saved before the court queue existed: no games.
      games: [
        for (final g in json['games'] as List<Object?>? ?? const [])
          Game.fromJson((g! as Map).cast<String, Object?>()),
      ],
    );
  }
}

/// A doubles game on one court: [teamA] against [teamB], two players each.
class Game {
  const Game({
    required this.id,
    required this.court,
    required this.teamA,
    required this.teamB,
    this.finishedSeq,
    this.scoreA,
    this.scoreB,
  });

  /// Unique within its session.
  final int id;

  /// 1 to the session's number of courts.
  final int court;
  final List<int> teamA;
  final List<int> teamB;

  /// Null while the game is on court. When it finishes it gets the next
  /// number in the session (1, 2, 3...), which tells the queue how long ago
  /// each player last came off court.
  final int? finishedSeq;

  /// Optional final score; both or neither.
  final int? scoreA;
  final int? scoreB;

  bool get finished => finishedSeq != null;
  List<int> get players => [...teamA, ...teamB];

  Game finish({required int seq, int? scoreA, int? scoreB}) => Game(
    id: id,
    court: court,
    teamA: teamA,
    teamB: teamB,
    finishedSeq: seq,
    scoreA: scoreA,
    scoreB: scoreB,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'court': court,
    'a': teamA,
    'b': teamB,
    if (finishedSeq != null) 'finished': finishedSeq,
    if (scoreA != null) 'scoreA': scoreA,
    if (scoreB != null) 'scoreB': scoreB,
  };

  static Game fromJson(Map<String, Object?> json) {
    final teamA = List<int>.unmodifiable(json['a']! as List<Object?>);
    final teamB = List<int>.unmodifiable(json['b']! as List<Object?>);
    if (teamA.length != 2 || teamB.length != 2) {
      throw const FormatException('A game has two players per team');
    }
    return Game(
      id: json['id']! as int,
      court: json['court']! as int,
      teamA: teamA,
      teamB: teamB,
      finishedSeq: json['finished'] as int?,
      scoreA: json['scoreA'] as int?,
      scoreB: json['scoreB'] as int?,
    );
  }
}
