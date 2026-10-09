import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:be_perfect/core/timer/schedule_engine.dart';
import 'package:be_perfect/features/home/home_page.dart';
import 'package:be_perfect/features/settings/about_page.dart';
import 'package:be_perfect/features/timer/timer_display_widget.dart';

Widget host(Widget child) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: ProviderScope(child: child),
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
                .contains('Developed for Be Perfect by Abanoub Samy (CyberBonk)'),
      ),
      findsOneWidget,
    );
  });
}
