import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/costs.dart';
import '../domain/models.dart';
import '../domain/queue.dart';
import '../l10n/strings.dart';

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

/// Thrown for input the organiser can fix. The screens show it in the
/// organiser's language ([localize]); [message] is the English text.
class InputError implements Exception, Localizable {
  const InputError(this.key, [this.args = const {}]);
  final K key;
  final Map<String, Object> args;

  String get message => localize(Strings.en);

  @override
  String localize(Strings strings) => strings(key, args);

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

  /// Player id to level, for players with a level set.
  Map<int, int> get levels => {
    for (final p in _players)
      if (p.level != null) p.id: p.level!,
  };

  /// The latest session (by date, then the one made last), to repeat it.
  Session? get lastSession {
    final all = sessions;
    return all.isEmpty ? null : all.first;
  }

  /// Players at [s] who are still in the roster, in check-in order.
  List<int> rosterPlayersAt(Session s) {
    final roster = {for (final p in _players) p.id};
    return [
      for (final a in s.attendance)
        if (roster.contains(a.playerId)) a.playerId,
    ];
  }

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
      throw const InputError(K.errNewerBackup);
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
    if (trimmed.isEmpty) throw const InputError(K.errPasteFirst);
    final _Document doc;
    try {
      doc = _parse(trimmed);
    } on InputError {
      rethrow;
    } on Object {
      throw const InputError(K.errNotBackup);
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
        throw InputError(K.errBadName, {'name': name});
      }
      if (!names.add(name.toLowerCase())) {
        throw InputError(K.errNameTwice, {'name': name});
      }
      if (!ids.add(p.id)) throw const InputError(K.errRepeatsId);
      final level = p.level;
      if (level != null &&
          (level < Player.minLevel || level > Player.maxLevel)) {
        throw InputError(K.errBadLevel, {'name': name});
      }
      playerIds.add(p.id);
    }
    for (final s in doc.sessions) {
      if (!ids.add(s.id)) throw const InputError(K.errRepeatsId);
      final where = InputError(K.errWhere, {'date': s.date, 'venue': s.venue});
      try {
        _check(s);
      } on InputError catch (e) {
        throw InputError(K.errWhereReason, {'where': where, 'reason': e});
      }
      final present = <int>{};
      for (final a in s.attendance) {
        if (!playerIds.contains(a.playerId)) {
          throw InputError(K.errUnknownPlayer, {'where': where});
        }
        if (!present.add(a.playerId)) {
          throw InputError(K.errPlayerTwice, {'where': where});
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
            g.players.toSet().length != g.players.length ||
            badScore ||
            // Still on court: one game per court, one court per player.
            (!g.finished &&
                (!busyCourts.add(g.court) || !g.players.every(onCourt.add)))) {
          throw InputError(K.errBadGame, {'where': where});
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
    if (trimmed.isEmpty) throw const InputError(K.errEnterName);
    if (trimmed.length > 40) {
      throw const InputError(K.errNameLong);
    }
    if (_players.any((p) => p.name.toLowerCase() == trimmed.toLowerCase())) {
      throw InputError(K.errNameTaken, {'name': trimmed});
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

  /// Sets a player's level ([Player.minLevel] to [Player.maxLevel]), or
  /// clears it with null.
  Future<void> setPlayerLevel(int id, int? level) async {
    if (level != null && (level < Player.minLevel || level > Player.maxLevel)) {
      final name = names[id] ?? '?';
      throw InputError(K.errBadLevel, {'name': name});
    }
    _players = [for (final p in _players) p.id == id ? p.withLevel(level) : p];
    await _save();
  }

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
      throw const InputError(K.errInPastSession);
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
    SplitMode courtSplit = SplitMode.equal,
    SplitMode shuttleSplit = SplitMode.equal,
    List<int> singlesCourts = const [],
    Iterable<int> playerIds = const [],
  }) async {
    final duration = endMinute - startMinute;
    final roster = {for (final p in _players) p.id: p};
    final checkedIn = <int>{};
    final s = Session(
      id: _nextId,
      date: date,
      venue: venue.trim(),
      startMinute: startMinute,
      endMinute: endMinute,
      courts: courts,
      courtRateSen: courtRateSen,
      shuttles: shuttles,
      shuttlePriceSen: shuttlePriceSen,
      guestFeeSen: guestFeeSen,
      courtSplit: courtSplit,
      shuttleSplit: shuttleSplit,
      // A repeated session may have fewer courts than the one it copies.
      singlesCourts: List.unmodifiable(
        {...singlesCourts}.where((c) => c >= 1 && c <= courts).toList()..sort(),
      ),
      attendance: List.unmodifiable([
        // Players no longer in the roster (or listed twice) are skipped.
        for (final id in playerIds)
          if (roster.containsKey(id) && checkedIn.add(id))
            Attendance(
              playerId: id,
              arriveMinute: 0,
              leaveMinute: duration < 0 ? 0 : duration,
              guest: roster[id]!.guest,
            ),
      ]),
    );
    _check(s);
    _nextId++;
    _sessions = [..._sessions, s];
    await _save();
    return s;
  }

  /// Courts beyond the session's number of courts (after it was lowered)
  /// lose their singles setting.
  Future<void> updateSession(Session s) async {
    if (s.singlesCourts.any((c) => c > s.courts)) {
      s = s.copyWith(
        singlesCourts: List.unmodifiable(
          s.singlesCourts.where((c) => c <= s.courts),
        ),
      );
    }
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
      throw InputError(K.errHasGames, {
        'name': names[playerId] ?? K.thisPlayer,
      });
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

  /// Makes [court] suggest singles (or doubles again). A game already on it
  /// carries on as it is.
  Future<void> setCourtSingles(int sessionId, int court, bool singles) async {
    final s = session(sessionId)!;
    final courts = {...s.singlesCourts};
    if (singles) {
      courts.add(court);
    } else {
      courts.remove(court);
    }
    await updateSession(
      s.copyWith(singlesCourts: List.unmodifiable(courts.toList()..sort())),
    );
  }

  /// Puts [teamA] against [teamB] on [court]: two against two, or one on one
  /// for singles. Everyone must be present, not sitting out and not already
  /// on court, and the court must be free.
  Future<Game> startGame(
    int sessionId, {
    required int court,
    required List<int> teamA,
    required List<int> teamB,
  }) async {
    final s = session(sessionId)!;
    final players = [...teamA, ...teamB];
    if (teamA.length != teamB.length ||
        (teamA.length != 2 && teamA.length != 1)) {
      throw const InputError(K.errTeamSizes);
    }
    if (players.toSet().length != players.length) {
      throw InputError(
        players.length == 2 ? K.errTwoPlayers : K.errFourPlayers,
      );
    }
    if (!freeCourts(s).contains(court)) {
      throw InputError(K.errCourtNotFree, {'court': court});
    }
    final waiting = waitingOrder(s).toSet();
    for (final p in players) {
      if (!waiting.contains(p)) {
        throw InputError(K.errNotFree, {'name': names[p] ?? K.aPlayer});
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
    if (game.finished) throw const InputError(K.errAlreadyFinished);
    if ((scoreA == null) != (scoreB == null)) {
      throw const InputError(K.errBothScores);
    }
    if (scoreA != null && scoreB != null) {
      if (scoreA < 0 || scoreA > 99 || scoreB < 0 || scoreB > 99) {
        throw const InputError(K.errScoreRange);
      }
      if (scoreA == scoreB) {
        throw const InputError(K.errDraw);
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
      throw const InputError(K.errDate);
    }
    if (s.venue.isEmpty) throw const InputError(K.errVenue);
    if (s.venue.length > 60) {
      throw const InputError(K.errVenueLong);
    }
    if (s.endMinute <= s.startMinute) {
      throw const InputError(K.errEndAfterStart);
    }
    if (s.courts < 1 || s.courts > 20) {
      throw const InputError(K.errCourts);
    }
    if (s.courtRateSen < 0 || s.courtRateSen > 100000) {
      throw const InputError(K.errCourtRate);
    }
    if (s.shuttlePriceSen < 0 || s.shuttlePriceSen > 10000) {
      throw const InputError(K.errShuttlePrice);
    }
    if (s.shuttles < 0 || s.shuttles > 500) {
      throw const InputError(K.errShuttles);
    }
    if (s.guestFeeSen < 0 || s.guestFeeSen > 10000) {
      throw const InputError(K.errGuestFee);
    }
    final singles = <int>{};
    for (final c in s.singlesCourts) {
      if (c < 1 || c > s.courts || !singles.add(c)) {
        throw const InputError(K.errSinglesCourts);
      }
    }
    for (final a in s.attendance) {
      if (a.arriveMinute < 0 ||
          a.leaveMinute > s.durationMinutes ||
          a.leaveMinute < a.arriveMinute) {
        throw const InputError(K.errTimesWithin);
      }
    }
    final present = {for (final a in s.attendance) a.playerId};
    for (final g in s.games) {
      if (!g.finished && g.court > s.courts) {
        throw InputError(K.errCourtStillOn, {'court': g.court});
      }
      if (!g.players.every(present.contains)) {
        throw const InputError(K.errNotAtSession);
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
    // Levels for team balancing (set after the demo games, so the demo's
    // amounts stay the same); the guest has none, as levels are optional.
    const demoLevels = {
      'Aiman': 4,
      'Bee Ling': 3,
      'Chandran': 2,
      'Daniel': 3,
      'Farah': 5,
      'Ganesh': 2,
      'Hui Min': 1,
    };
    for (final p in [..._players]) {
      final level = demoLevels[p.name];
      if (level != null) await setPlayerLevel(p.id, level);
    }
  }
}
