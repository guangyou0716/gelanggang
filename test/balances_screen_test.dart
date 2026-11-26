import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/domain/costs.dart';
import 'package:gelanggang/src/domain/history.dart';
import 'package:gelanggang/src/domain/money.dart';
import 'package:gelanggang/src/ui/queue_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('session: split modes, a guest on a flat fee and what is still '
      'owed from last week', (tester) async {
    final store = await pumpApp(tester);
    await store.seedDemo(today: '2026-12-03');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();

    expect(
      find.text('Guests pay a flat RM 15.00; regulars share the rest.'),
      findsOneWidget,
    );
    String message() => tester
        .widget<SelectableText>(find.byKey(const Key('settle-text')))
        .data!;
    await reveal(tester, find.byKey(const Key('settle-text')));
    expect(
      message(),
      contains('Courts split by time played, shuttles by games played:'),
    );
    expect(message(), contains('- Iskandar (guest): RM 15.00'));
    final s = store.sessions.first;
    final farah = store.players.firstWhere((p) => p.name == 'Farah').id;
    final owedBefore = carriedOver(store.sessions, s)[farah]!;
    final share = sharesFor(s)[farah]!;
    expect(
      message(),
      contains(
        '- Farah: ${formatRm(share)} + ${formatRm(owedBefore)} from earlier '
        'sessions = ${formatRm(share + owedBefore)}',
      ),
    );
    await reveal(
      tester,
      find.text('${formatRm(owedBefore)} owed from earlier'),
    );

    // Count Iskandar as a regular for this session: no guest line any more.
    await reveal(tester, find.byTooltip('More for Iskandar'));
    await tester.tap(find.byTooltip('More for Iskandar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Count as a regular'));
    await tester.pumpAndSettle();
    expect(store.session(s.id)!.attendance.any((a) => a.guest), isFalse);
    await reveal(tester, find.byKey(const Key('settle-text')));
    expect(message(), isNot(contains('Guests pay')));
    expect(message(), contains('- Iskandar: '));

    // Shuttles equally too: one line for both.
    await reveal(tester, find.byKey(const Key('shuttle-split')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('shuttle-split')),
        matching: find.text('Equally'),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('court-split')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('court-split')),
        matching: find.text('Equally'),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('settle-text')));
    expect(message(), contains('Split equally:'));
  });

  testWidgets('players: balances across sessions, reminder, history and '
      'settle all', (tester) async {
    final store = await pumpApp(tester);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await store.seedDemo(today: '2026-12-03');
    await tester.pumpAndSettle();
    final records = playerRecords(store.sessions);
    final total = records.values.fold<int>(0, (a, r) => a + r.owedSen);

    await tester.tap(find.byTooltip('Players'));
    await tester.pumpAndSettle();
    expect(
      find.text('${formatRm(total)} to collect across sessions'),
      findsOneWidget,
    );
    expect(find.text('Iskandar (guest)'), findsOneWidget);
    await tester.tap(find.text('Copy reminder'));
    await tester.pumpAndSettle();
    expect(copied.single, balancesText(store.sessions, store.names));
    expect(copied.single, contains('Farah'));

    final farah = store.players.firstWhere((p) => p.name == 'Farah');
    final owed = records[farah.id]!.owedSen;
    expect(
      find.text(
        '2 sessions · ${gamesLabel(records[farah.id]!.games)} · owes '
        '${formatRm(owed)}',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Farah'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('2026-11-26 · Demo Community Hall'), findsOne);
    expect(find.textContaining('owed'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('settle-all')));
    await tester.pumpAndSettle();
    expect(find.text('${formatRm(owed)} over 2 sessions.'), findsOneWidget);
    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settle-all')), findsNothing);
    expect(find.textContaining(' owed'), findsNothing);
    expect(playerRecords(store.sessions)[farah.id]!.owedSen, 0);

    // The roster switch makes her a guest for future check-ins only.
    await tester.tap(find.byKey(const Key('player-guest')));
    await tester.pumpAndSettle();
    expect(store.players.firstWhere((p) => p.id == farah.id).guest, isTrue);
    expect(
      store.sessions.every(
        (s) => s.attendance.every((a) => a.playerId != farah.id || !a.guest),
      ),
      isTrue,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Farah (guest)'), findsOneWidget);
  });

  testWidgets('session form: the guest fee is edited and checked', (
    tester,
  ) async {
    final store = await pumpApp(tester);
    await store.seedDemo(today: '2026-12-03');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Demo Sports Hall'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit session'));
    await tester.pumpAndSettle();
    final fee = find.byKey(const Key('field-guestFee'));
    expect(tester.widget<TextFormField>(fee).controller!.text, '15.00');

    await reveal(tester, fee);
    await tester.enterText(fee, '150');
    await tester.tap(find.byKey(const Key('save-session')));
    await tester.pumpAndSettle();
    expect(
      find.text('Guest fee must be between RM0 and RM100'),
      findsOneWidget,
    );
    expect(store.sessions.first.guestFeeSen, 1500);

    await tester.enterText(fee, '20');
    await tester.tap(find.byKey(const Key('save-session')));
    await tester.pumpAndSettle();
    expect(store.sessions.first.guestFeeSen, 2000);
    expect(
      find.text('Guests pay a flat RM 20.00; regulars share the rest.'),
      findsOneWidget,
    );
  });
}
