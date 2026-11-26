import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/costs.dart';
import '../domain/models.dart';
import '../domain/queue.dart';

/// Where the app keeps its single JSON document, plus one spare slot for a
/// document it could not read (so a change never destroys it).
abstract interface class Storage {
  Future<String?> read();
  Future<void> write(String data);

  Future<String?> readAside();

  /// Null clears the slot.
  Future<void> writeAside(String? data);
}

/// For tests and the first frame before the device storage is ready.
class MemoryStorage implements Storage {
  MemoryStorage([this.data]);

  String? data;
  String? aside;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String value) async => data = value;

  @override
  Future<String?> readAside() async => aside;

  @override
  Future<void> writeAside(String? value) async => aside = value;
}

/// On the device (Android/iOS) or in the browser's local storage (web).
class DeviceStorage implements Storage {
  static const _key = 'gelanggang.v1';
  static const _asideKey = 'gelanggang.unreadable';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String data) async =>
      (await SharedPreferences.getInstance()).setString(_key, data);

  @override
  Future<String?> readAside() async =>
      (await SharedPreferences.getInstance()).getString(_asideKey);

  @override
  Future<void> writeAside(String? data) async {
    final prefs = await SharedPreferences.getInstance();
    if (data == null) {
      await prefs.remove(_asideKey);
    } else {
      await prefs.setString(_asideKey, data);
    }
  }
}

/// What a backup holds, shown before it replaces anything.
typedef BackupSummary = ({int players, int sessions});

/// A document that passed every check, ready to replace the store's data.
class _Document {
  const _Document(this.players, this.sessions, this.nextId);
  final List<Player> players;
  final List<Session> sessions;
  final int nextId;
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

  /// Saved data the app could not read (damaged, or from a newer version),
  /// kept aside so the organiser can copy it out. Null when there is none.
  String? get setAside => _setAside;
  String? _setAside;

  /// Whether [load] found a document (readable or not): not a first launch.
  bool _hadSavedDocument = false;

  /// Loads saved data. A missing document starts empty. An unreadable one
  /// also starts empty, but is first copied to the storage's spare slot, so
  /// the next change (which writes a new document) cannot destroy it.
  Future<void> load() async {
    _setAside = await _storage.readAside();
    final raw = await _storage.read();
    if (raw == null) {
      notifyListeners();
      return;
    }
    _hadSavedDocument = true;
    try {
      // Parse everything before keeping any of it, so a bad document never
      // leaves the store half loaded (and then saved over the good data).
      final doc = _parse(raw);
      _players = doc.players;
      _sessions = doc.sessions;
      _nextId = doc.nextId;
    } on Object catch (e) {
      debugPrint('gelanggang: setting aside unreadable saved data ($e)');
      await _storage.writeAside(raw);
      _setAside = raw;
    }
    notifyListeners();
  }

  /// Forgets the data kept aside (after the organiser has copied it).
  Future<void> discardSetAside() async {
    await _storage.writeAside(null);
    _setAside = null;
    notifyListeners();
  }

  /// Reads a saved document or backup. Throws on anything unexpected; only
  /// the version is checked, not whether the data makes sense.
  static _Document _parse(String raw) {
    final json = (jsonDecode(raw) as Map).cast<String, Object?>();
    final version = json['version'];
    if (version is int && version > schemaVersion) {
      throw const InputError(
        'This backup is from a newer version of gelanggang. Update the app, '
        'then restore it.',
      );
    }
    if (version != schemaVersion) {
      throw const FormatException('Unknown version');
    }
    final players = [
      for (final p in json['players']! as List<Object?>)
        Player.fromJson((p! as Map).cast<String, Object?>()),
    ];
    final sessions = [
      for (final s in json['sessions']! as List<Object?>)
        Session.fromJson((s! as Map).cast<String, Object?>()),
    ];
    return _Document(players, sessions, json['nextId']! as int);
  }

  String _encode({bool pretty = false}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert({
            if (pretty) 'app': 'gelanggang',
            'version': schemaVersion,
            'nextId': _nextId,
            'players': [for (final p in _players) p.toJson()],
            'sessions': [for (final s in _sessions) s.toJson()],
          });

  /// Everything, as readable JSON the organiser can keep (message it to
  /// themselves, save it in notes) and restore on another phone.
  String exportBackup() => _encode(pretty: true);

  BackupSummary get summary =>
      (players: _players.length, sessions: _sessions.length);

  /// Checks [text] as a backup without changing anything; throws an
  /// [InputError] saying what is wrong.
  static BackupSummary checkBackup(String text) {
    final doc = _validate(text);
    return (players: doc.players.length, sessions: doc.sessions.length);
  }

  /// Replaces all players and sessions with the backup in [text]. Nothing
  /// changes unless the whole backup passes [checkBackup].
  Future<void> restoreBackup(String text) async {
    final doc = _validate(text);
    _players = [...doc.players]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _sessions = doc.sessions;
    _nextId = doc.nextId;
    await _save();
  }

  /// A backup is held to the same rules as the app's own changes, so a
  /// restored group behaves exactly like one entered by hand.
  static _Document _validate(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw const InputError('Paste a backup first');
    final _Document doc;
    try {
      doc = _parse(trimmed);
    } on InputError {
      rethrow;
    } on Object {
      throw const InputError(
        'This is not a gelanggang backup, or part of it is missing. Copy the '
        'whole backup and try again.',
      );
    }
    final ids = <int>{};
    final playerIds = <int>{};
    final names = <String>{};
    for (final p in doc.players) {
      final name = p.name;
      // Exactly as addPlayer would have saved it.
      if (name.isEmpty ||
          name.length > 40 ||
          name != name.trim().replaceAll(RegExp(r'\s+'), ' ')) {
        throw InputError('A player name in the backup is not valid: "$name"');
      }
      if (!names.add(name.toLowerCase())) {
        throw InputError('$name is in the backup twice');
      }
      if (!ids.add(p.id)) throw const InputError('The backup repeats an id');
      playerIds.add(p.id);
    }
    for (final s in doc.sessions) {
      if (!ids.add(s.id)) throw const InputError('The backup repeats an id');
      final where = 'Session ${s.date} (${s.venue})';
      try {
        _check(s);
      } on InputError catch (e) {
        throw InputError('$where: ${e.message}');
      }
      final present = <int>{};
      for (final a in s.attendance) {
        if (!playerIds.contains(a.playerId)) {
          throw InputError('$where lists a player who is not in the backup');
        }
        if (!present.add(a.playerId)) {
          throw InputError('$where lists a player twice');
        }
      }
      final gameIds = <int>{};
      final busyCourts = <int>{};
      final onCourt = <int>{};
      for (final g in s.games) {
        final a = g.scoreA, b = g.scoreB;
        final badScore =
            (a == null) != (b == null) ||
            (a != null &&
                b != null &&
                (a < 0 || a > 99 || b < 0 || b > 99 || a == b)) ||
            (!g.finished && a != null);
        if (!gameIds.add(g.id) ||
            g.court < 1 ||
            g.players.toSet().length != 4 ||
            badScore ||
            // Still on court: one game per court, one court per player.
            (!g.finished &&
                (!busyCourts.add(g.court) || !g.players.every(onCourt.add)))) {
          throw InputError('$where has a game that is not valid');
        }
      }
    }
    final top = ids.fold<int>(0, (m, id) => id > m ? id : m);
    // New players and sessions must never reuse an id from the backup.
    return _Document(
      doc.players,
      doc.sessions,
      doc.nextId > top ? doc.nextId : top + 1,
    );
  }

  Future<void> _save() async {
    notifyListeners();
    await _storage.write(_encode());
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

  /// Marks a player as a guest (or a regular) for their next check-ins.
  /// Sessions already recorded keep what they were.
  Future<void> setPlayerGuest(int id, bool guest) async {
    _players = [
      for (final p in _players) p.id == id ? p.copyWith(guest: guest) : p,
    ];
    await _save();
  }

  /// Marks [playerId] as paid (recording their share right now as the
  /// amount) or not paid at session [sessionId].
  Future<void> setPaid(int sessionId, int playerId, bool paid) async {
    final s = session(sessionId)!;
    final a = s.attendance.firstWhere((a) => a.playerId == playerId);
    await updateAttendance(
      sessionId,
      paid
          ? a.copyWith(paid: true, paidSen: sharesFor(s)[playerId] ?? 0)
          : a.copyWith(paid: false),
    );
  }

  /// Settles everything [playerId] still owes, in every session: each share
  /// with something due is recorded as paid in full at today's amount.
  Future<void> settleAll(int playerId) async {
    _sessions = [for (final s in _sessions) _settled(s, playerId)];
    await _save();
  }

  static Session _settled(Session s, int playerId) {
    final shares = sharesFor(s);
    return s.copyWith(
      attendance: [
        for (final a in s.attendance)
          a.playerId == playerId && dueSen(a, shares[playerId] ?? 0) > 0
              ? a.copyWith(paid: true, paidSen: shares[playerId] ?? 0)
              : a,
      ],
    );
  }

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
    int guestFeeSen = 0,
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
      guestFeeSen: guestFeeSen,
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
  /// there for the whole session until changed, and is a guest if the roster
  /// says so.
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
                  guest: _players.any((p) => p.id == playerId && p.guest),
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

  /// Whether [playerId] counts as a guest at this one session.
  Future<void> setAttendanceGuest(
    int sessionId,
    int playerId,
    bool guest,
  ) async {
    final s = session(sessionId)!;
    final a = s.attendance.firstWhere((a) => a.playerId == playerId);
    await updateAttendance(sessionId, a.copyWith(guest: guest));
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

  /// "2026-11-19" for ("2026-11-26", 7).
  static String _daysBefore(String date, int days) {
    final d = DateTime.utc(
      int.parse(date.substring(0, 4)),
      int.parse(date.substring(5, 7)),
      int.parse(date.substring(8, 10)) - days,
    );
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
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
    if (s.guestFeeSen < 0 || s.guestFeeSen > 10000) {
      throw const InputError('Guest fee must be between RM0 and RM100');
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
  /// Never after a launch that found saved data, even an empty or unreadable
  /// one: an organiser who cleared everything does not want the demo back.
  Future<void> seedDemo({required String today}) async {
    if (!isEmpty || _hadSavedDocument) return;
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
    final guest = _players.firstWhere((p) => p.name == 'Iskandar');
    await setPlayerGuest(guest.id, true);

    // Last week: one court, split equally, two players have not paid yet.
    final lastWeek = await createSession(
      date: _daysBefore(today, 7),
      venue: 'Demo Community Hall (synthetic)',
      startMinute: 20 * 60,
      endMinute: 22 * 60,
      courts: 1,
      courtRateSen: 2000,
      shuttles: 4,
      shuttlePriceSen: 450,
    );
    for (final p in _players.where((p) => !p.guest).take(6)) {
      await toggleAttendance(lastWeek.id, p.id);
    }
    final owing = {'Bee Ling', 'Farah'};
    final past = session(lastWeek.id)!;
    await updateSession(
      past.copyWith(
        attendance: [
          for (final a in past.attendance)
            a.copyWith(paid: !owing.contains(names[a.playerId])),
        ],
      ),
    );

    // Today: courts by time, shuttles by games, a guest on a flat fee.
    final s = await createSession(
      date: today,
      venue: 'Demo Sports Hall (synthetic)',
      startMinute: 20 * 60,
      endMinute: 22 * 60,
      courts: 2,
      courtRateSen: 2000,
      shuttles: 6,
      shuttlePriceSen: 450,
      guestFeeSen: 1500,
    );
    for (final p in _players) {
      await toggleAttendance(s.id, p.id);
    }
    final late = _players.firstWhere((p) => p.name == 'Hui Min');
    final early = _players.firstWhere((p) => p.name == 'Daniel');
    final current = session(s.id)!;
    await updateSession(
      current.copyWith(
        courtSplit: SplitMode.byMinutes,
        shuttleSplit: SplitMode.byGames,
        attendance: [
          for (final a in current.attendance)
            a.playerId == late.id
                ? a.copyWith(arriveMinute: 60)
                : a.playerId == early.id
                ? a.copyWith(leaveMinute: 90)
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
    // Daniel paid his share before leaving early (after the games, which
    // decide the shuttle split).
    await setPaid(s.id, early.id, true);
  }
}
