/// Data for one organiser's badminton group. Everything is stored on the
/// device as JSON; there are no accounts and no server.
library;

class Player {
  const Player({required this.id, required this.name});

  final int id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  static Player fromJson(Map<String, Object?> json) =>
      Player(id: json['id']! as int, name: json['name']! as String);
}

/// How a session's cost is shared.
enum SplitMode {
  /// Everyone present pays the same.
  equal,

  /// In proportion to the minutes each player was there (late arrivals and
  /// early leavers pay less).
  byMinutes,
}

/// A player at a session, with the minutes after the session start when they
/// arrived and left.
class Attendance {
  const Attendance({
    required this.playerId,
    required this.arriveMinute,
    required this.leaveMinute,
    this.paid = false,
  });

  final int playerId;
  final int arriveMinute;
  final int leaveMinute;
  final bool paid;

  int get minutes => leaveMinute - arriveMinute;

  Attendance copyWith({int? arriveMinute, int? leaveMinute, bool? paid}) =>
      Attendance(
        playerId: playerId,
        arriveMinute: arriveMinute ?? this.arriveMinute,
        leaveMinute: leaveMinute ?? this.leaveMinute,
        paid: paid ?? this.paid,
      );

  Map<String, Object?> toJson() => {
    'playerId': playerId,
    'arrive': arriveMinute,
    'leave': leaveMinute,
    'paid': paid,
  };

  static Attendance fromJson(Map<String, Object?> json) => Attendance(
    playerId: json['playerId']! as int,
    arriveMinute: json['arrive']! as int,
    leaveMinute: json['leave']! as int,
    paid: json['paid'] as bool? ?? false,
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
    this.splitMode = SplitMode.equal,
    this.attendance = const [],
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
  final SplitMode splitMode;
  final List<Attendance> attendance;

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
    SplitMode? splitMode,
    List<Attendance>? attendance,
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
    splitMode: splitMode ?? this.splitMode,
    attendance: attendance ?? this.attendance,
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
    'splitMode': splitMode.name,
    'attendance': [for (final a in attendance) a.toJson()],
  };

  static Session fromJson(Map<String, Object?> json) => Session(
    id: json['id']! as int,
    date: json['date']! as String,
    venue: json['venue']! as String,
    startMinute: json['start']! as int,
    endMinute: json['end']! as int,
    courts: json['courts']! as int,
    courtRateSen: json['courtRateSen']! as int,
    shuttles: json['shuttles']! as int,
    shuttlePriceSen: json['shuttlePriceSen']! as int,
    splitMode: SplitMode.values.firstWhere(
      (m) => m.name == json['splitMode'],
      orElse: () => SplitMode.equal,
    ),
    attendance: [
      for (final a in json['attendance']! as List<Object?>)
        Attendance.fromJson((a! as Map).cast<String, Object?>()),
    ],
  );
}
