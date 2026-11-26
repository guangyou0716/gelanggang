/// Every text the app shows or writes (screens, errors and the messages the
/// organiser pastes into the group chat) in English, Bahasa Melayu and
/// Simplified Chinese.
///
/// Each [K] carries its English text; `ms.dart` and `zh.dart` hold the
/// translations. Placeholders are `{name}`; a test checks that every key has
/// a translation in every language with exactly the same placeholders.
library;

import 'ms.dart';
import 'zh.dart';

enum AppLanguage {
  en('en', 'English'),
  ms('ms', 'Bahasa Melayu'),
  zh('zh', '简体中文');

  const AppLanguage(this.code, this.nativeName);

  /// Language code, as in a [Locale] and in saved settings.
  final String code;

  /// The language's name in that language, as shown in the picker.
  final String nativeName;

  /// Null for a code the app has no translation for.
  static AppLanguage? fromCode(String? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return null;
  }
}

/// Text that is turned into words only when shown, in the reader's language
/// (an error raised by the store, for example).
abstract interface class Localizable {
  String localize(Strings strings);
}

/// The texts of one language.
class Strings {
  const Strings(this.language);

  static const en = Strings(AppLanguage.en);

  final AppLanguage language;

  static final _placeholder = RegExp(r'\{(\w+)\}');

  /// The placeholder names in [text], e.g. {"name", "amount"}.
  static Set<String> placeholdersOf(String text) => {
    for (final m in _placeholder.allMatches(text)) m.group(1)!,
  };

  /// The raw text for [key] in [language] (with its placeholders).
  static String template(AppLanguage language, K key) => switch (language) {
    AppLanguage.en => key.en,
    AppLanguage.ms => msStrings[key] ?? key.en,
    AppLanguage.zh => zhStrings[key] ?? key.en,
  };

  /// [key]'s text with each `{name}` replaced by `args['name']`. An argument
  /// that is itself a [K] or [Localizable] is put into this language too.
  String call(K key, [Map<String, Object> args = const {}]) =>
      template(language, key).replaceAllMapped(_placeholder, (m) {
        final value = args[m.group(1)];
        if (value == null) {
          throw ArgumentError('No value for {${m.group(1)}} in ${key.name}');
        }
        return switch (value) {
          final K k => call(k),
          final Localizable l => l.localize(this),
          _ => '$value',
        };
      });

  /// [one] when [n] is 1, else [other]; both get `{n}`.
  String count(K one, K other, int n, [Map<String, Object> args = const {}]) =>
      call(n == 1 ? one : other, {...args, 'n': n});

  String players(int n) => count(K.playersOne, K.playersOther, n);
  String sessions(int n) => count(K.sessionsOne, K.sessionsOther, n);
  String games(int n) => count(K.gamesOne, K.gamesOther, n);

  /// A session date ("2026-11-26") for reading. English keeps the ISO date
  /// the app has always shown; Malay and Chinese get the weekday and month
  /// spelled out. Anything that is not a real date is returned unchanged.
  String date(String iso) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (match == null) return iso;
    final y = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    final day = DateTime.utc(y, m, d);
    if (day.month != m || day.day != d) return iso;
    return switch (language) {
      AppLanguage.en => iso,
      AppLanguage.ms =>
        '${msWeekdays[day.weekday - 1]}, $d ${msMonths[m - 1]} $y',
      AppLanguage.zh => '$y年$m月$d日（${zhWeekdays[day.weekday - 1]}）',
    };
  }
}

/// Keys, each with its English text.
enum K {
  // Shared
  cancel('Cancel'),
  save('Save'),
  delete('Delete'),
  remove('Remove'),
  copied('Copied.'),
  copiedForChat('Copied. Paste it into your group chat.'),
  guest('Guest'),
  nameGuest('{name} (guest)'),
  playersOne('{n} player'),
  playersOther('{n} players'),
  sessionsOne('{n} session'),
  sessionsOther('{n} sessions'),
  gamesOne('{n} game'),
  gamesOther('{n} games'),
  courtsOne('{n} court'),
  courtsOther('{n} courts'),
  shuttlesOne('{n} shuttle'),
  shuttlesOther('{n} shuttles'),
  useClock('Use HH:MM, like {example}'),
  scoresWhole('Scores are whole numbers, like 21'),
  thisPlayer('This player'),
  aPlayer('A player'),

  // Language picker
  language('Language'),
  languageDevice('Same as this device ({language})'),

  // Home
  players('Players'),
  backupAndRestore('Backup and restore'),
  newSession('New session'),
  noSessions('No sessions yet. Add your players, then start a session.'),
  sessionListTitle('{date} · {venue}'),
  sessionListToCollect('{players} · {total} · {owed} to collect'),
  sessionListAllPaid('{players} · {total} · all paid'),

  // Player record summary (roster)
  noSessionsYet('No sessions yet'),
  owesAmount('owes {amount}'),
  paidUp('paid up'),

  // Session screen
  sessionDeleted('This session was deleted.'),
  editSession('Edit session'),
  deleteSession('Delete session'),
  deleteSessionConfirm('Delete this session?'),
  sessionSummary(
    '{start}-{end} · {courts} at {rate}/hour · {shuttles} at {price}',
  ),
  figCourts('Courts'),
  figShuttles('Shuttles'),
  figTotal('Total'),
  figToCollect('To collect'),
  courtCost('Court cost'),
  guestFeesCoverAll(
    'The guest fees come to the whole cost, so the guests share it and '
    'regulars pay nothing.',
  ),
  guestFeeApplies('Guests pay a flat {amount}; regulars share the rest.'),
  guestFeeWhen(
    'Guest fee {amount} applies when guests and regulars both come.',
  ),
  queueButton('Court queue · {onCourt} on court · {games} played'),
  whoCame('Who came ({n})'),
  addPlayersFirst('Add players first (Players, top right).'),
  messageForGroup('Message for the group'),
  copyMessage('Copy message'),
  splitEqually('Equally'),
  splitByTime('By time'),
  splitByGames('By games'),
  paid('Paid'),
  playerPaid('{name} paid'),
  moreFor('More for {name}'),
  countAsRegular('Count as a regular'),
  countAsGuest('Count as a guest'),
  markNotPaid('Mark as not paid'),
  playerCame('{name} came'),
  changeTimesFor('Change times for {name}, {arrive} to {leave}'),
  timesTapToChange('{arrive}-{leave} · tap to change'),
  shareWentUp('Paid {paid}; share went up, {due} more due'),
  shareWentDown('Paid {paid}; share went down, {over} to give back'),
  owedFromEarlier('{amount} owed from earlier'),
  timesTitle('{name}: time at the court'),
  arrivedLabel('Arrived (HH:MM)'),
  leftLabel('Left (HH:MM)'),

  // Settle-up message
  msgHeader('Badminton {date} {start}-{end}, {venue}'),
  msgCosts('Courts {courts} + shuttles {shuttles} = {total}'),
  msgGuestsShareAll('Guests share the whole cost.'),
  msgGuestsFlat('Guests pay a flat {amount}.'),
  msgSplit('Split {mode}:'),
  msgSplitEach('Courts split {court}, shuttles {shuttle}:'),
  modeEqually('equally'),
  modeByTime('by time played'),
  modeByGames('by games played'),
  msgLine('- {name}: {amount}'),
  msgLineGuest('- {name} (guest): {amount}'),
  msgPartPaid('{share} (paid {paid}, {due} more)'),
  msgPartPaidEarlier(
    '{share} (paid {paid}, {due} more + {earlier} from earlier sessions '
    '= {total})',
  ),
  msgPaidThanks('{share} (paid, thanks!)'),
  msgPaidGiveBack('{share} (paid, thanks! {over} to give back)'),
  msgStillOwedEarlier(' · {earlier} still owed from earlier sessions'),
  msgWithEarlier('{share} + {earlier} from earlier sessions = {total}'),

  // Balances reminder
  balHeader('Badminton balances ({amount} to collect):'),
  balLine('- {name}: {amount} ({sessions})'),

  // Session form
  required('Required'),
  amountHint('Enter an amount like 20 or 4.50'),
  numberRange('Enter a number from {min} to {max}'),
  dateField('Date (YYYY-MM-DD)'),
  venue('Venue'),
  venueHint('e.g. Dewan Badminton Taman Jaya'),
  start('Start'),
  end('End'),
  courtRateField('Court rate (RM/hour)'),
  shuttlesUsed('Shuttles used'),
  shuttlePrice('Price per shuttle (RM)'),
  guestFeeField('Guest fee (RM, 0 = guests share like regulars)'),
  guestFeeHint('e.g. 15'),
  createSession('Create session'),

  // Roster
  name('Name'),
  add('Add'),
  noPlayers('No players yet.'),
  toCollectAcross('{amount} to collect across sessions'),
  everyonePaidUp('Everyone is paid up'),
  copyReminder('Copy reminder'),
  removeName('Remove {name}'),

  // Backup
  replaceTitle('Replace everything with this backup?'),
  replaceBody(
    'The backup has {inPlayers} and {inSessions}. It replaces the '
    '{nowPlayers} and {nowSessions} on this phone, which cannot be undone. '
    'Copy a backup of them first if you may need them.',
  ),
  replace('Replace'),
  backupRestored('Backup restored.'),
  unreadableTitle('Some saved data could not be read'),
  unreadableBody(
    'It may be damaged or come from a newer version of the app. It was kept '
    'aside, untouched. Copy it and keep it until you have checked it.',
  ),
  copyIt('Copy it'),
  throwAwayConfirm('Throw away the unreadable data?'),
  keepIt('Keep it'),
  throwAway('Throw away'),
  throwItAway('Throw it away'),
  backUp('Back up'),
  backUpBody(
    'Everything stays on this phone. Copy a backup now and then and keep it '
    'somewhere safe, such as a message to yourself. This phone has {players} '
    'and {sessions}.',
  ),
  backupCopied('Backup copied. Paste it somewhere safe.'),
  copyBackup('Copy backup'),
  restore('Restore'),
  restoreBody('Paste a backup to replace everything on this phone with it.'),
  backupText('Backup text'),

  // Player screen
  playerRemoved('This player was removed.'),
  statSessions('Sessions'),
  statGames('Games'),
  statWins('Wins'),
  statOwes('Owes'),
  guestSwitchBody(
    'New check-ins count as a guest. Past sessions stay as they were.',
  ),
  markAmountPaid('Mark {amount} as paid'),
  settleAllTitle("Mark all of {name}'s sessions as paid?"),
  settleAllBody('{amount} over {sessions}.'),
  markPaid('Mark paid'),
  history('History'),
  notAtAnySession('Not at any session yet.'),
  historyGuest('{games} · guest'),
  sharePaid('{amount} paid'),
  dueOfShare('{due} of {share} owed'),
  shareOwed('{amount} owed'),

  // Court queue
  courtQueue('Court queue'),
  insteadOf('Instead of {name}'),
  swapPlaces('{name} (swap places)'),
  keep('Keep'),
  takeOffCourt('Take this game off court?'),
  nextUp('Next up'),
  tickFour('Tick at least four players under "Who came" first.'),
  waitingForFour('Waiting for four free players ({n} free now).'),
  vs('vs'),
  changeName('Change {name}'),
  allCourtsBusy('All courts are busy.'),
  startOnCourt('Start on court {court}'),
  waiting('Waiting ({n})'),
  sitOut('Sit out'),
  sittingOut('{name} (sitting out)'),
  backIn('Back in'),
  gamesHeader('Games ({n})'),
  finishedShowHere('Finished games show up here.'),
  teamVs('{a} vs {b}'),
  court('Court {court}'),
  courtScore('Court {court} · {a}-{b}'),
  removeGame('Remove game'),
  removeGameConfirm('Remove this game from the log?'),
  free('Free'),
  cancelGameOn('Cancel game on court {court}'),
  finish('Finish'),
  gameFinished('Game finished'),
  scoreOptional('Score (optional)'),
  level('Level'),
  nameLevel('{name} · level {level}'),
  withLevel('{text} · level {level}'),
  levelOf('Level {level}'),
  noLevel('No level'),
  levelBody(
    'Balances teams in the court queue: 1 is a beginner, 5 the strongest.',
  ),
  levelNone('None'),
  doubles('Doubles'),
  singles('Singles'),
  gameTypeOn('Game on court {court}'),
  courtSingles('Court {court} · singles'),
  tickTwo('Tick at least two players under "Who came" first.'),
  waitingForTwo('Waiting for two free players ({n} free now).'),
  levelTotals('Levels {a} v {b}'),

  // Repeat last session
  repeatLast('Same as last time?'),
  repeatLastBody('{date} · {venue} · {players}'),
  repeatFill('Fill in'),
  repeatPlayers('Check in the same players ({players})'),
  repeatFilled(
    'Filled in from {date}. Enter the shuttles used once you know them.',
  ),

  // Season summary
  season('Season summary'),
  rangeThisMonth('This month'),
  rangeLastMonth('Last month'),
  rangeLast3Months('Last 3 months'),
  rangeThisYear('This year'),
  rangeAll('All time'),
  seasonPeriod('{from} to {to} · {sessions}'),
  seasonAllTime('All time · {sessions}'),
  seasonEmpty('No sessions in this period.'),
  seasonTotals('Asked {share} · paid {paid} · owed {owed}'),
  seasonPlayed('{sessions} ({percent}%) · {games} · {wins} won'),
  seasonPaid('Paid {paid} of {share}'),
  seasonPaidOwes('Paid {paid} of {share} · owes {owed}'),
  copyCsv('Copy as CSV'),
  csvCopied('Copied as CSV. Paste it into a spreadsheet.'),

  // Errors the organiser can fix
  errNewerBackup(
    'This backup is from a newer version of gelanggang. Update the app, then '
    'restore it.',
  ),
  errPasteFirst('Paste a backup first'),
  errNotBackup(
    'This is not a gelanggang backup, or part of it is missing. Copy the '
    'whole backup and try again.',
  ),
  errBadName('A player name in the backup is not valid: "{name}"'),
  errNameTwice('{name} is in the backup twice'),
  errRepeatsId('The backup repeats an id'),
  errWhere('Session {date} ({venue})'),
  errWhereReason('{where}: {reason}'),
  errUnknownPlayer('{where} lists a player who is not in the backup'),
  errPlayerTwice('{where} lists a player twice'),
  errBadGame('{where} has a game that is not valid'),
  errEnterName('Enter a name'),
  errNameLong('Keep the name under 40 characters'),
  errNameTaken('{name} is already on the list'),
  errInPastSession('This player is in a past session'),
  errHasGames('{name} has games in this session; remove those games first'),
  errFourPlayers('A game needs four different players'),
  errCourtNotFree('Court {court} is not free'),
  errNotFree('{name} is not free to play'),
  errAlreadyFinished('This game is already finished'),
  errBothScores('Enter both scores or neither'),
  errScoreRange('Scores must be between 0 and 99'),
  errDraw('A badminton game cannot end in a draw'),
  errDate('Enter the date as YYYY-MM-DD'),
  errVenue('Enter the venue'),
  errVenueLong('Keep the venue under 60 characters'),
  errEndAfterStart('The session must end after it starts'),
  errCourts('Courts must be between 1 and 20'),
  errCourtRate('Court rate must be between RM0 and RM1000'),
  errShuttlePrice('Shuttle price must be between RM0 and RM100'),
  errShuttles('Shuttles must be between 0 and 500'),
  errGuestFee('Guest fee must be between RM0 and RM100'),
  errTimesWithin('Arrival and leaving times must be within the session'),
  errCourtStillOn('Court {court} still has a game on; finish it first'),
  errNotAtSession('Everyone in a game must be at the session'),
  errTwoPlayers('A singles game needs two different players'),
  errTeamSizes('A game is two against two, or one against one for singles'),
  errBadLevel('The level for {name} must be from 1 to 5'),
  errSinglesCourts('Singles can only be set on this session\'s courts');

  const K(this.en);

  /// The English text.
  final String en;
}
