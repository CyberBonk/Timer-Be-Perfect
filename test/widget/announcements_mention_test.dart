import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:be_perfect/core/firebase/firebase_providers.dart';
import 'package:be_perfect/core/models/feed_event_model.dart';
import 'package:be_perfect/core/models/member_model.dart';
import 'package:be_perfect/features/announcements/announcements_page.dart';

void main() {
  testWidgets('AnnouncementsPage @mention suggestion and selection works',
      (tester) async {
    final List<Member> members = [
      Member.fromJson(const {
        'uid': 'user-1',
        'sectorName': 'Alpha Sector',
        'joinedAt': 1000,
        'updatedAt': 1000,
      }),
      Member.fromJson(const {
        'uid': 'user-2',
        'sectorName': 'Beta Sector',
        'joinedAt': 1000,
        'updatedAt': 1000,
      }),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('user-self'),
          membersStreamProvider.overrideWith((ref) => Stream.value(members)),
          feedStreamProvider.overrideWith((ref) => Stream.value([
                FeedEvent.fromJson(const {
                  'eventId': 'event-targeted',
                  'type': 'announcement',
                  'title': 'To @Alpha Sector',
                  'body': 'Please wrap up',
                  'targetUid': 'user-self',
                  'targetSectorName': 'Alpha Sector',
                  'senderUid': 'controller-1',
                  'notifyDevices': true,
                  'timestamp': 1000,
                }),
              ])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AnnouncementsPage(isController: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify targeted feed card renders with @You badge for target recipient
    expect(find.text('To @Alpha Sector'), findsOneWidget);
    expect(find.text('@You'), findsOneWidget);

    // Tap the '@' prefix trigger button on the compose TextField
    await tester.tap(find.widgetWithIcon(IconButton, Icons.alternate_email_rounded));
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify autocomplete suggestion chips appear for active participants
    expect(find.text('@Alpha Sector'), findsWidgets);
    expect(find.text('@Beta Sector'), findsOneWidget);

    // Tap '@Alpha Sector' suggestion chip
    await tester.tap(find.text('@Alpha Sector').last);
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify target chip is active
    expect(find.textContaining('Targeting @Alpha Sector'), findsOneWidget);
  });
}
