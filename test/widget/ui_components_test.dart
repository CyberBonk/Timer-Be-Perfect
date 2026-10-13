import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:be_perfect/core/timer/schedule_engine.dart';
import 'package:be_perfect/features/home/home_page.dart';
import 'package:be_perfect/features/settings/about_page.dart';
import 'package:be_perfect/features/timer/timer_display_widget.dart';
import 'package:be_perfect/core/models/room_model.dart';
import 'package:be_perfect/core/models/member_model.dart';
import 'package:be_perfect/core/models/sound_mode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:be_perfect/features/timer/sector_cards_widget.dart';

Widget host(Widget child, {Locale? locale}) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    ),
  );
}

TimerDerivedState state(DerivedPhaseState phase) => TimerDerivedState(
      state: phase,
      currentRoundIndex: 2,
      totalRounds: 6,
      remainingMs: phase == DerivedPhaseState.completed ? 0 : 65000,
      targetEndTimestampMs: 0,
      isStartingCountdown: phase == DerivedPhaseState.starting,
      startingCountdownSeconds: 3,
    );

void main() {
  testWidgets('timer display renders running and offline state',
      (tester) async {
    await tester.pumpWidget(host(
      TimerDisplayWidget(derivedState: state(DerivedPhaseState.runningRound)),
    ));

    expect(find.text('Round 2 Running'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);

    await tester.pumpWidget(host(
      TimerDisplayWidget(
        derivedState: state(DerivedPhaseState.paused),
        isOffline: true,
      ),
    ));
    expect(find.text('Paused'), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);

    await tester.pumpWidget(host(
      TimerDisplayWidget(
        derivedState: state(DerivedPhaseState.cooldown),
      ),
    ));
    expect(find.text('Next Round'), findsOneWidget);
    expect(find.text('The next round starts soon'), findsOneWidget);
  });

  testWidgets('home page opens join room dialog and about page',
      (tester) async {
    await tester.pumpWidget(host(const HomePage()));

    expect(find.text('Create Room'), findsOneWidget);
    await tester.tap(find.text('Join as Participant'));
    await tester.pumpAndSettle();
    expect(find.text('Join as Participant').last, findsOneWidget);
    expect(find.text('6-Digit Room PIN'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text
                .toPlainText()
                .contains('Developed by Abanoub Samy (CyberBonk)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('about page renders Arabic attribution correctly',
      (tester) async {
    await tester.pumpWidget(host(
      const AboutPage(),
      locale: const Locale('ar'),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text
                .toPlainText()
                .contains('طُوّر بواسطة أبانوب سامي (CyberBonk)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SectorCardsWidget renders sector grouping and 4-state sync matrix badges',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final room = Room(
      roomId: 'room-1',
      ownerUid: 'owner-1',
      state: RoomState.active,
      sectors: const ['Alpha Sector', 'Beta Sector'],
      sectorCapacity: null,
      revision: 2,
      createdAt: now,
      updatedAt: now,
    );

    final members = <Member>[
      // 1. Synced + Online (Green)
      Member(
        uid: 'm-1',
        participantName: 'Alice',
        sectorName: 'Alpha Sector',
        normalizedSectorName: 'alpha sector',
        acknowledgedRevision: 2,
        joinedAt: now,
        updatedAt: now,
        lastSeenAt: now,
        notificationReadiness: true,
        exactAlarmReadiness: true,
        selectedSoundMode: SoundMode.bePerfectSound,
        fcmTokens: const [],
      ),
      // 2. Synced + Offline (Orange)
      Member(
        uid: 'm-2',
        participantName: 'Bob',
        sectorName: 'Alpha Sector',
        normalizedSectorName: 'alpha sector',
        acknowledgedRevision: 2,
        joinedAt: now,
        updatedAt: now,
        lastSeenAt: 0,
        notificationReadiness: true,
        exactAlarmReadiness: true,
        selectedSoundMode: SoundMode.bePerfectSound,
        fcmTokens: const [],
      ),
      // 3. Out of sync + Online (Amber)
      Member(
        uid: 'm-3',
        participantName: 'Charlie',
        sectorName: 'Beta Sector',
        normalizedSectorName: 'beta sector',
        acknowledgedRevision: 1,
        joinedAt: now,
        updatedAt: now,
        lastSeenAt: now,
        notificationReadiness: true,
        exactAlarmReadiness: true,
        selectedSoundMode: SoundMode.bePerfectSound,
        fcmTokens: const [],
      ),
      // 4. Out of sync + Offline (Red)
      Member(
        uid: 'm-4',
        participantName: 'David',
        sectorName: 'Beta Sector',
        normalizedSectorName: 'beta sector',
        acknowledgedRevision: 1,
        joinedAt: now,
        updatedAt: now,
        lastSeenAt: 0,
        notificationReadiness: false,
        exactAlarmReadiness: false,
        selectedSoundMode: SoundMode.bePerfectSound,
        fcmTokens: const [],
      ),
    ];

    await tester.pumpWidget(host(
      SingleChildScrollView(
        child: SectorCardsWidget(
          room: room,
          members: members,
          isController: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Verify sector cards headers
    expect(find.text('Alpha Sector'), findsOneWidget);
    expect(find.text('Beta Sector'), findsOneWidget);
    expect(find.text('2 joined'), findsNWidgets(2));

    // Verify participant names
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('David'), findsOneWidget);

    // Verify cell tower vs off icons (2 online, 2 offline)
    expect(find.byIcon(Icons.cell_tower), findsNWidgets(2));
    expect(find.byIcon(Icons.signal_cellular_off), findsNWidgets(2));

    // Verify sync text badges: 2 Synced, 2 Out of sync
    expect(find.text('Synced'), findsNWidgets(2));
    expect(find.text('Out of sync'), findsNWidgets(2));

    // Verify 4-state badge container colors:
    // Green (Synced + Online)
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.green.shade100,
      ),
      findsOneWidget,
    );
    // Orange (Synced + Offline)
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.orange.shade100,
      ),
      findsOneWidget,
    );
    // Amber (Out of sync + Online)
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.amber.shade200,
      ),
      findsOneWidget,
    );
    // Red (Out of sync + Offline)
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.red.shade100,
      ),
      findsOneWidget,
    );
  });
}
