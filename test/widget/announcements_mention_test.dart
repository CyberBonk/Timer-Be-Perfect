import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:be_perfect/core/firebase/firebase_providers.dart';
import 'package:be_perfect/core/firebase/room_repository.dart';
import 'package:be_perfect/core/models/feed_event_model.dart';
import 'package:be_perfect/core/models/member_model.dart';
import 'package:be_perfect/features/announcements/announcements_page.dart';

class _FakeActiveRoomIdNotifier extends ActiveRoomIdNotifier {
  final String _id;
  _FakeActiveRoomIdNotifier(this._id);

  @override
  String? build() => _id;
}

class _MockAnnouncementRepository implements RoomRepository {
  @override
  final String? currentUid;

  String? lastRoomId;
  String? lastBody;
  String? lastTitle;
  bool? lastNotifyDevices;
  String? lastTargetUid;
  String? lastTargetSectorName;

  _MockAnnouncementRepository({this.currentUid = 'controller-1'});

  @override
  Future<void> sendAnnouncement({
    required String roomId,
    required String body,
    String title = 'Announcement',
    bool notifyDevices = true,
    String? targetUid,
    String? targetSectorName,
  }) async {
    lastRoomId = roomId;
    lastBody = body;
    lastTitle = title;
    lastNotifyDevices = notifyDevices;
    lastTargetUid = targetUid;
    lastTargetSectorName = targetSectorName;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.alternate_email_rounded));
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

  testWidgets(
      'AnnouncementsPage supports distinct participantName and sectorName mentions',
      (tester) async {
    final mockRepo = _MockAnnouncementRepository(currentUid: 'controller-1');
    final members = [
      Member.fromJson(const {
        'uid': 'user-abanoub',
        'participantName': 'Abanoub',
        'sectorName': 'مشورة',
        'joinedAt': 1000,
        'updatedAt': 1000,
      }),
      Member.fromJson(const {
        'uid': 'user-mina',
        'participantName': 'Mina',
        'sectorName': 'مشورة',
        'joinedAt': 1000,
        'updatedAt': 1000,
      }),
      Member.fromJson(const {
        'uid': 'user-stage',
        'participantName': 'Stage Lead',
        'sectorName': 'Stage',
        'joinedAt': 1000,
        'updatedAt': 1000,
      }),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('controller-1'),
          activeRoomIdProvider
              .overrideWith(() => _FakeActiveRoomIdNotifier('room-test-123')),
          roomRepositoryProvider.overrideWithValue(mockRepo),
          membersStreamProvider.overrideWith((ref) => Stream.value(members)),
          feedStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AnnouncementsPage(isController: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trigger @ mention suggestions
    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.alternate_email_rounded));
    await tester.pumpAndSettle();

    // Primary sector chips: @مشورة and @Stage
    expect(find.text('@مشورة'), findsOneWidget);
    expect(find.text('@Stage'), findsOneWidget);

    // Bonus participant chips with sector subtitle:
    expect(find.text('@Abanoub (مشورة)'), findsOneWidget);
    expect(find.text('@Mina (مشورة)'), findsOneWidget);

    // Scroll horizontal ListView to reveal the 5th chip
    await tester.drag(find.byType(ListView).last, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('@Stage Lead (Stage)'), findsOneWidget);

    // Tap @Abanoub (مشورة) participant chip
    await tester.tap(find.text('@Abanoub (مشورة)'));
    await tester.pumpAndSettle();

    // Verify targeting chip for specific person is active
    expect(find.textContaining('Targeting @Abanoub'), findsOneWidget);

    // Tap Send
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
    await tester.pumpAndSettle();

    // Verify that sendAnnouncement was called targeting Abanoub specifically
    expect(mockRepo.lastRoomId, 'room-test-123');
    expect(mockRepo.lastTargetUid, 'user-abanoub');
    expect(mockRepo.lastTargetSectorName, 'Abanoub');
    expect(mockRepo.lastTitle, contains('@Abanoub'));
  });

  testWidgets(
      'AnnouncementsPage sector mention targets all sector members with null targetUid',
      (tester) async {
    final mockRepo = _MockAnnouncementRepository(currentUid: 'controller-1');
    final members = [
      Member.fromJson(const {
        'uid': 'user-abanoub',
        'participantName': 'Abanoub',
        'sectorName': 'مشورة',
        'joinedAt': 1000,
        'updatedAt': 1000,
      }),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('controller-1'),
          activeRoomIdProvider
              .overrideWith(() => _FakeActiveRoomIdNotifier('room-test-123')),
          roomRepositoryProvider.overrideWithValue(mockRepo),
          membersStreamProvider.overrideWith((ref) => Stream.value(members)),
          feedStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AnnouncementsPage(isController: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trigger @ mention suggestions
    await tester
        .tap(find.widgetWithIcon(IconButton, Icons.alternate_email_rounded));
    await tester.pumpAndSettle();

    // Tap @مشورة sector chip
    await tester.tap(find.text('@مشورة'));
    await tester.pumpAndSettle();

    // Verify targeting chip for sector is active
    expect(find.textContaining('Targeting @مشورة'), findsOneWidget);

    // Tap Send
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
    await tester.pumpAndSettle();

    // TargetUid should be null so that the backend targets all members of that sector
    expect(mockRepo.lastTargetUid, isNull);
    expect(mockRepo.lastTargetSectorName, 'مشورة');
    expect(mockRepo.lastTitle, contains('@مشورة'));
  });

  testWidgets(
      'AnnouncementsPage auto-matches typed @ParticipantName in announcement text',
      (tester) async {
    final mockRepo = _MockAnnouncementRepository(currentUid: 'controller-1');
    final members = [
      Member.fromJson(const {
        'uid': 'user-abanoub',
        'participantName': 'Abanoub',
        'sectorName': 'مشورة',
        'joinedAt': 1000,
        'updatedAt': 1000,
      }),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('controller-1'),
          activeRoomIdProvider
              .overrideWith(() => _FakeActiveRoomIdNotifier('room-test-123')),
          roomRepositoryProvider.overrideWithValue(mockRepo),
          membersStreamProvider.overrideWith((ref) => Stream.value(members)),
          feedStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AnnouncementsPage(isController: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Manually type "@Abanoub please come to reception"
    await tester.enterText(
      find.byType(TextField),
      'Hello @Abanoub please come to reception',
    );
    await tester.pumpAndSettle();

    // Tap Send
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
    await tester.pumpAndSettle();

    // Auto-match should resolve user-abanoub
    expect(mockRepo.lastTargetUid, 'user-abanoub');
    expect(mockRepo.lastTargetSectorName, 'Abanoub');
  });
}
