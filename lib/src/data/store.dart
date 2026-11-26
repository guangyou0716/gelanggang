import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/queue.dart';

/// Where the app keeps its single JSON document.
abstract interface class Storage {
  Future<String?> read();
  Future<void> write(String data);
}

/// For tests and the first frame before the device storage is ready.
class MemoryStorage implements Storage {
  MemoryStorage([this.data]);

  String? data;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String value) async => data = value;
}

/// On the device (Android/iOS) or in the browser's local storage (web).
class DeviceStorage implements Storage {
  static const _key = 'gelanggang.v1';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String data) async =>
      (await SharedPreferences.getInstance()).setString(_key, data);
}

/// Thrown for input the organiser can fix; the message is shown as is.
class InputError implements Exception {
  const InputError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The organiser's roster and sessions. Every change is saved right away.
class AppStore extends ChangeNotifier {
  AppStore(this._storage);

  static const int schemaVersion = 1;

  final Storage _storage;
  List<Player> _players = [];
  List<Session> _sessions = [];
  int _nextId = 1;

  List<Player> get players => List.unmodifiable(_players);

  /// Newest first.
  List<Session> get sessions => List.unmodifiable(
    [..._sessions]..sort(
      (a, b) => b.date != a.date ? b.date.compareTo(a.date) : b.id - a.id,
    ),
  );

  Map<int, String> get names => {for (final p in _players) p.id: p.name};

  Session? session(int id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Loads saved data. A missing or unreadable document starts empty (and is
  /// not overwritten until the next change).
  Future<void> load() async {
    final raw = await _storage.read();
    if (raw == null) return;
    try {
      final json = (jsonDecode(raw) as Map).cast<String, Object?>();
      if (json['version'] != schemaVersion) return;
      // Parse everything before keeping any of it, so a bad document never
      // leaves the store half loaded (and then saved over the good data).
      final players = [
        for (final p in json['players']! as List<Object?>)
          Player.fromJson((p! as Map).cast<String, Object?>()),
      ];
      final sessions = [
        for (final s in json['sessions']! as List<Object?>)
          Session.fromJson((s! as Map).cast<String, Object?>()),
      ];
      final nextId = json['nextId']! as int;
      _players = players;
      _sessions = sessions;
      _nextId = nextId;
    } on Object catch (e) {
      debugPrint('gelanggang: ignoring unreadable saved data ($e)');
      return;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    await _storage.write(
      jsonEncode({
        'version': schemaVersion,
        'nextId': _nextId,
        'players': [for (final p in _players) p.toJson()],
        'sessions': [for (final s in _sessions) s.toJson()],
      }),
    );
  }

  bool get isEmpty => _players.isEmpty && _sessions.isEmpty;

  Future<Player> addPlayer(String name) async {
    final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) throw const InputError('Enter a name');
    if (trimmed.length > 40) {
      throw const InputError('Keep the name under 40 characters');
    }
    if (_players.any((p) => p.name.toLowerCase() == trimmed.toLowerCase())) {
      throw InputError('$trimmed is already on the list');
    }
    final player = Player(id: _nextId++, name: trimmed);
    _players = [..._players, player]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _save();
    return player;
  }

  /// Players who were at a session stay in its history, so they cannot be
  /// removed.
  bool canRemovePlayer(int id) =>
      !_sessions.any((s) => s.attendance.any((a) => a.playerId == id));

  Future<void> removePlayer(int id) async {
    if (!canRemovePlayer(id)) {
      throw const InputError('This player is in a past session');
    }
    _players = _players.where((p) => p.id != id).toList();
    await _save();
  }

  Future<Session> createSession({
    required String date,
    required String venue,
    required int startMinute,
    required int endMinute,
    required int courts,
    required int courtRateSen,
    required int shuttles,
    required int shuttlePriceSen,
  }) async {
    final s = Session(
      id: _nextId++,
      date: date,
      venue: venue.trim(),
      startMinute: startMinute,
      endMinute: endMinute,
      courts: courts,
      courtRateSen: courtRateSen,
      shuttles: shuttles,
      shuttlePriceSen: shuttlePriceSen,
    );
    _check(s);
    _sessions = [..._sessions, s];
    await _save();
    return s;
  }

  Future<void> updateSession(Session s) async {
    _check(s);
    _sessions = [for (final old in _sessions) old.id == s.id ? s : old];
    await _save();
  }

  Future<void> deleteSession(int id) async {
    _sessions = _sessions.where((s) => s.id != id).toList();
    await _save();
  }

  /// Adds or removes [playerId] from session [sessionId]; a new arrival is
  /// there for the whole session until changed.
  Future<void> toggleAttendance(int sessionId, int playerId) async {
    final s = session(sessionId)!;
    final present = s.attendance.any((a) => a.playerId == playerId);
    if (present && s.games.any((g) => g.players.contains(playerId))) {
      throw InputError(
        '${names[playerId] ?? 'This player'} has games in this session; '
        'remove those games first',
      );
    }
    await updateSession(
      s.copyWith(
        attendance: present
            ? s.attendance.where((a) => a.playerId != playerId).toList()
            : [
                ...s.attendance,
                Attendance(
                  playerId: playerId,
                  arriveMinute: 0,
                  leaveMinute: s.durationMinutes,
                ),
              ],
      ),
    );
  }

  Future<void> updateAttendance(int sessionId, Attendance a) async {
    final s = session(sessionId)!;
    await updateSession(
      s.copyWith(
        attendance: [
          for (final old in s.attendance) old.playerId == a.playerId ? a : old,
        ],
      ),
    );
  }

  /// Puts [teamA] against [teamB] on [court]. All four must be present, not
  /// sitting out and not already on court, and the court must be free.
  Future<Game> startGame(
    int sessionId, {
    required int court,
    required List<int> teamA,
    required List<int> teamB,
  }) async {
    final s = session(sessionId)!;
    final players = [...teamA, ...teamB];
    if (teamA.length != 2 || teamB.length != 2 || players.toSet().length != 4) {
      throw const InputError('A game needs four different players');
    }
    if (!freeCourts(s).contains(court)) {
      throw InputError('Court $court is not free');
    }
    final waiting = waitingOrder(s).toSet();
    for (final p in players) {
      if (!waiting.contains(p)) {
        throw InputError('${names[p] ?? 'A player'} is not free to play');
      }
    }
    final game = Game(
      id: s.games.fold<int>(0, (m, g) => g.id > m ? g.id : m) + 1,
      court: court,
      teamA: List.unmodifiable(teamA),
      teamB: List.unmodifiable(teamB),
    );
    await updateSession(s.copyWith(games: [...s.games, game]));
    return game;
  }

  /// Takes a game off court, with an optional score (both or neither,
  /// 0-99, no draws).
  Future<void> finishGame(
    int sessionId,
    int gameId, {
    int? scoreA,
    int? scoreB,
  }) async {
    final s = session(sessionId)!;
    final game = s.games.firstWhere((g) => g.id == gameId);
    if (game.finished) throw const InputError('This game is already finished');
    if ((scoreA == null) != (scoreB == null)) {
      throw const InputError('Enter both scores or neither');
    }
    if (scoreA != null && scoreB != null) {
      if (scoreA < 0 || scoreA > 99 || scoreB < 0 || scoreB > 99) {
        throw const InputError('Scores must be between 0 and 99');
      }
      if (scoreA == scoreB) {
        throw const InputError('A badminton game cannot end in a draw');
      }
    }
    final seq = s.games.fold<int>(
      0,
      (m, g) => (g.finishedSeq ?? 0) > m ? g.finishedSeq! : m,
    );
    final done = game.finish(seq: seq + 1, scoreA: scoreA, scoreB: scoreB);
    await updateSession(
      s.copyWith(games: [for (final g in s.games) g.id == gameId ? done : g]),
    );
  }

  /// Removes a game started by mistake, or a wrong entry in the log.
  Future<void> removeGame(int sessionId, int gameId) async {
    final s = session(sessionId)!;
    await updateSession(
      s.copyWith(games: s.games.where((g) => g.id != gameId).toList()),
    );
  }

  /// Sitting out keeps a player in the cost split but out of the queue.
  Future<void> setResting(int sessionId, int playerId, bool resting) async {
    final s = session(sessionId)!;
    final a = s.attendance.firstWhere((a) => a.playerId == playerId);
    await updateAttendance(sessionId, a.copyWith(resting: resting));
  }

  /// "2026-11-26" yes; "2026-13-01" or "2026-02-30" no (DateTime.parse
  /// would roll those over into the next month).
  static bool _isRealDate(String date) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return false;
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return false;
    final back =
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    return back == date;
  }

  static void _check(Session s) {
    if (!_isRealDate(s.date)) {
      throw const InputError('Enter the date as YYYY-MM-DD');
    }
    if (s.venue.isEmpty) throw const InputError('Enter the venue');
    if (s.venue.length > 60) {
      throw const InputError('Keep the venue under 60 characters');
    }
    if (s.endMinute <= s.startMinute) {
      throw const InputError('The session must end after it starts');
    }
    if (s.courts < 1 || s.courts > 20) {
      throw const InputError('Courts must be between 1 and 20');
    }
    if (s.courtRateSen < 0 || s.courtRateSen > 100000) {
      throw const InputError('Court rate must be between RM0 and RM1000');
    }
    if (s.shuttlePriceSen < 0 || s.shuttlePriceSen > 10000) {
      throw const InputError('Shuttle price must be between RM0 and RM100');
    }
    if (s.shuttles < 0 || s.shuttles > 500) {
      throw const InputError('Shuttles must be between 0 and 500');
    }
    for (final a in s.attendance) {
      if (a.arriveMinute < 0 ||
          a.leaveMinute > s.durationMinutes ||
          a.leaveMinute < a.arriveMinute) {
        throw const InputError(
          'Arrival and leaving times must be within the session',
        );
      }
    }
    final present = {for (final a in s.attendance) a.playerId};
    for (final g in s.games) {
      if (!g.finished && g.court > s.courts) {
        throw InputError(
          'Court ${g.court} still has a game on; finish it first',
        );
      }
      if (!g.players.every(present.contains)) {
        throw const InputError('Everyone in a game must be at the session');
      }
    }
  }

  /// Synthetic demo data for the first launch (and the public web demo).
  Future<void> seedDemo({required String today}) async {
    if (!isEmpty) return;
    for (final name in [
      'Aiman',
      'Bee Ling',
      'Chandran',
      'Daniel',
      'Farah',
      'Ganesh',
      'Hui Min',
      'Iskandar',
    ]) {
      await addPlayer(name);
    }
    final s = await createSession(
      date: today,
      venue: 'Demo Sports Hall (synthetic)',
      startMinute: 20 * 60,
      endMinute: 22 * 60,
      courts: 2,
      courtRateSen: 2000,
      shuttles: 6,
      shuttlePriceSen: 450,
    );
    for (final p in _players) {
      await toggleAttendance(s.id, p.id);
    }
    final late = _players.firstWhere((p) => p.name == 'Hui Min');
    final early = _players.firstWhere((p) => p.name == 'Daniel');
    final current = session(s.id)!;
    await updateSession(
      current.copyWith(
        splitMode: SplitMode.byMinutes,
        attendance: [
          for (final a in current.attendance)
            a.playerId == late.id
                ? a.copyWith(arriveMinute: 60)
                : a.playerId == early.id
                ? a.copyWith(leaveMinute: 90, paid: true)
                : a,
        ],
      ),
    );
    // A few games so the court queue has something to show: two finished,
    // one on court 1, four players waiting.
    for (final (court, score) in [(1, (21, 17)), (2, (19, 21))]) {
      final next = suggestNext(session(s.id)!)!;
      final g = await startGame(
        s.id,
        court: court,
        teamA: next.teamA,
        teamB: next.teamB,
      );
      await finishGame(s.id, g.id, scoreA: score.$1, scoreB: score.$2);
    }
    final next = suggestNext(session(s.id)!)!;
    await startGame(s.id, court: 1, teamA: next.teamA, teamB: next.teamB);
  }
}
