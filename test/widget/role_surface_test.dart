import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:be_perfect/core/firebase/firebase_providers.dart';
import 'package:be_perfect/core/models/feed_event_model.dart';
import 'package:be_perfect/core/models/member_model.dart';
import 'package:be_perfect/features/announcements/announcements_page.dart';

Widget roleHost({
  required bool isController,
  List<FeedEvent> events = const [],
}) {
  return ProviderScope(
    overrides: [
      feedStreamProvider.overrideWith((ref) => Stream.value(events)),
      membersStreamProvider.overrideWith((ref) => Stream.value(<Member>[])),
    ],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: AnnouncementsPage(isController: isController)),
    ),
  );
}

void main() {
  testWidgets('controller announcement surface exposes device notification',
      (tester) async {
    await tester.pumpWidget(roleHost(isController: true));

    expect(find.text('Notify Devices'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, 'Type announcement...');
  });

  testWidgets('participant announcement surface cannot notify devices',
      (tester) async {
    await tester.pumpWidget(roleHost(isController: false));

    expect(find.text('Notify Devices'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, 'Send a message to the room...');
  });

  testWidgets('system announcements use short summaries', (tester) async {
    await tester.pumpWidget(
      roleHost(
        isController: false,
        events: [
          FeedEvent(
            eventId: 'timer-1',
            type: FeedEventType.systemControl,
            senderUid: 'controller',
            title: 'Timer Adjusted',
            body: 'Controller adjusted active round duration by -5 minute(s).',
            notifyDevices: false,
            timestamp: 0,
          ),
          FeedEvent(
            eventId: 'round-2',
            type: FeedEventType.systemControl,
            senderUid: 'controller',
            title: 'Round 2 Started',
            body: 'Round 2 of 6 has started.',
            notifyDevices: false,
            timestamp: 0,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Controller -5 min'), findsOneWidget);
    expect(find.text('Next round'), findsOneWidget);
    expect(find.text('Round 2 started'), findsOneWidget);
    expect(
      find.text('Controller adjusted active round duration by -5 minute(s).'),
      findsNothing,
    );
  });
}
