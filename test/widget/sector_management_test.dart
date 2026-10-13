import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:be_perfect/core/firebase/firebase_providers.dart';
import 'package:be_perfect/core/firebase/room_repository.dart';
import 'package:be_perfect/core/models/room_model.dart';
import 'package:be_perfect/core/models/member_model.dart';
import 'package:be_perfect/core/models/sound_mode.dart';
import 'package:be_perfect/features/timer/sector_management_card.dart';
import 'package:be_perfect/features/timer/controller_dashboard_page.dart';

class FakeRoomRepository implements RoomRepository {
  List<String>? lastUpdatedSectors;
  String? lastUpdatedRoomId;
  bool startRunCalled = false;

  @override
  Future<void> updateRoomSectors(String roomId, List<String> sectors) async {
    lastUpdatedRoomId = roomId;
    lastUpdatedSectors = sectors;
  }

  @override
  Future<void> startRun({
    required String roomId,
    required int expectedRevision,
    int roundCount = 6,
    int standardRoundDurationMinutes = 20,
    int cooldownSeconds = 0,
    bool keepHistory = true,
    bool notifyDevices = true,
  }) async {
    startRunCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Room createTestRoom({List<String> sectors = const ['قطاع 1', 'المسرح', 'الصوت']}) {
  return Room(
    roomId: 'room-123',
    ownerUid: 'owner-1',
    state: RoomState.lobby,
    sectors: sectors,
    sectorCapacity: null,
    revision: 1,
    createdAt: 1000,
    updatedAt: 1000,
  );
}

Member createTestMember({
  required String uid,
  required String sectorName,
  String participantName = 'Test User',
}) {
  return Member(
    uid: uid,
    participantName: participantName,
    sectorName: sectorName,
    normalizedSectorName: sectorName.toLowerCase(),
    joinedAt: 1000,
    updatedAt: 1000,
    lastSeenAt: 1000,
    notificationReadiness: true,
    exactAlarmReadiness: true,
    selectedSoundMode: SoundMode.bePerfectSound,
    fcmTokens: const [],
  );
}

void main() {
  testWidgets('renders existing sectors including Arabic UTF-8 text',
      (tester) async {
    final room = createTestRoom();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SectorManagementCard(
              room: room,
              members: const [],
              isLocked: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Sector Management'), findsOneWidget);
    expect(find.text('قطاع 1'), findsOneWidget);
    expect(find.text('المسرح'), findsOneWidget);
    expect(find.text('الصوت'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-sector-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('sectors-locked-indicator')), findsNothing);
  });

  testWidgets('add sector dialog adds sector and calls updateRoomSectors',
      (tester) async {
    final fakeRepo = FakeRoomRepository();
    final room = createTestRoom(sectors: ['قطاع 1']);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SectorManagementCard(
              room: room,
              members: const [],
              isLocked: false,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('add-sector-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sector-name-input')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('sector-name-input')), 'الكشافة');
    await tester.tap(find.byKey(const ValueKey('submit-add-sector-button')));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastUpdatedRoomId, 'room-123');
    expect(fakeRepo.lastUpdatedSectors, ['قطاع 1', 'الكشافة']);
  });

  testWidgets('rename sector flow updates sector via updateRoomSectors',
      (tester) async {
    final fakeRepo = FakeRoomRepository();
    final room = createTestRoom(sectors: ['قطاع 1', 'المسرح']);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SectorManagementCard(
              room: room,
              members: const [],
              isLocked: false,
            ),
          ),
        ),
      ),
    );

    // Tapping a sector chip opens rename dialog
    await tester.tap(find.byKey(const ValueKey('sector-chip-قطاع 1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('rename-sector-input')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('rename-sector-input')), 'قطاع أ');
    await tester.tap(find.byKey(const ValueKey('submit-rename-sector-button')));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastUpdatedRoomId, 'room-123');
    expect(fakeRepo.lastUpdatedSectors, ['قطاع أ', 'المسرح']);
  });

  testWidgets('delete sector with 0 members confirms and calls updateRoomSectors',
      (tester) async {
    final fakeRepo = FakeRoomRepository();
    final room = createTestRoom(sectors: ['قطاع 1', 'المسرح']);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SectorManagementCard(
              room: room,
              members: const [],
              isLocked: false,
            ),
          ),
        ),
      ),
    );

    // Find and tap delete on chip
    final chip = find.byKey(const ValueKey('sector-chip-قطاع 1'));
    final deleteIcon = find.descendant(of: chip, matching: find.byIcon(Icons.close));
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();

    expect(find.text('Are you sure you want to delete sector "قطاع 1"?'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-delete-sector-button')));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastUpdatedRoomId, 'room-123');
    expect(fakeRepo.lastUpdatedSectors, ['المسرح']);
  });

  testWidgets(
      'delete sector with existing members shows warning dialog with participant count',
      (tester) async {
    final fakeRepo = FakeRoomRepository();
    final room = createTestRoom(sectors: ['قطاع 1', 'المسرح']);
    final members = [
      createTestMember(uid: 'm1', sectorName: 'قطاع 1'),
      createTestMember(uid: 'm2', sectorName: 'قطاع 1'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SectorManagementCard(
              room: room,
              members: members,
              isLocked: false,
            ),
          ),
        ),
      ),
    );

    final chip = find.byKey(const ValueKey('sector-chip-قطاع 1'));
    final deleteIcon = find.descendant(of: chip, matching: find.byIcon(Icons.close));
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Warning: Sector "قطاع 1" currently has 2 joined participant(s)'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-delete-sector-button')));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastUpdatedSectors, ['المسرح']);
  });

  testWidgets(
      'locked state displays locked banner and disables modifications during active event',
      (tester) async {
    final room = createTestRoom(sectors: ['قطاع 1', 'المسرح']);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SectorManagementCard(
              room: room,
              members: const [],
              isLocked: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('sectors-locked-indicator')), findsOneWidget);
    expect(
        find.text('Sectors cannot be modified during an active event'),
        findsOneWidget);
    // Add sector button must not be visible when locked
    expect(find.byKey(const ValueKey('add-sector-button')), findsNothing);

    // Delete icons must not be present on chips
    expect(find.byIcon(Icons.close), findsNothing);

    // Tapping chip should not open rename dialog
    await tester.tap(find.byKey(const ValueKey('sector-chip-قطاع 1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rename-sector-input')), findsNothing);
  });

  testWidgets(
      'starting event with empty sectors shows warning dialog with Proceed and Add Sectors',
      (tester) async {
    final fakeRepo = FakeRoomRepository();
    final room = createTestRoom(sectors: []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomRepositoryProvider.overrideWithValue(fakeRepo),
          roomStreamProvider.overrideWith((ref) => Stream.value(room)),
          activeRunStreamProvider.overrideWith((ref) => Stream.value(null)),
          membersStreamProvider.overrideWith((ref) => Stream.value([])),
          firebaseConnectionProvider.overrideWith((ref) => Stream.value(true)),
          presenceStreamProvider.overrideWith((ref) => Stream.value({})),
          currentUidProvider.overrideWithValue('owner-1'),
        ],
        child: const MaterialApp(
          home: ControllerDashboardPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Verify empty sectors notice in SectorManagementCard
    expect(
      find.text(
        'No sectors configured yet. Add sectors for participant registration.',
      ),
      findsOneWidget,
    );

    // Tap Start Event Run
    final startButton = find.widgetWithText(FilledButton, 'Start Event Run');
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Warning dialog should appear
    expect(
      find.text(
        'Warning: Creating a sectorless session. The event will run in legacy single-tier mode.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add Sectors'), findsOneWidget);
    expect(find.text('Proceed'), findsOneWidget);

    // Tap Add Sectors -> dialog dismissed, run not started
    await tester.tap(find.text('Add Sectors'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fakeRepo.startRunCalled, isFalse);

    // Tap Start Event Run again
    await tester.tap(startButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap Proceed -> run starts
    await tester.tap(find.text('Proceed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fakeRepo.startRunCalled, isTrue);
  });

  testWidgets(
      'rename sector allows changing casing and ignores old sector in collision check',
      (tester) async {
    final fakeRepo = FakeRoomRepository();
    final room = createTestRoom(sectors: ['sector a', 'sector b']);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SectorManagementCard(
              room: room,
              members: const [],
              isLocked: false,
            ),
          ),
        ),
      ),
    );

    // Tap 'sector a' chip
    await tester.tap(find.byKey(const ValueKey('sector-chip-sector a')));
    await tester.pumpAndSettle();

    // Rename to 'Sector A' (only case changed)
    await tester.enterText(
        find.byKey(const ValueKey('rename-sector-input')), 'Sector A');
    await tester.tap(find.byKey(const ValueKey('submit-rename-sector-button')));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastUpdatedSectors, ['Sector A', 'sector b']);
  });

  testWidgets(
      'shows error snackbar when updateRoomSectors throws an error',
      (tester) async {
    final failingRepo = _FailingRoomRepository();
    final room = createTestRoom(sectors: ['sector a']);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomRepositoryProvider.overrideWithValue(failingRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SectorManagementCard(
              room: room,
              members: const [],
              isLocked: false,
            ),
          ),
        ),
      ),
    );

    // Open add sector dialog
    await tester.tap(find.byKey(const ValueKey('add-sector-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('sector-name-input')), 'new sector');
    await tester.tap(find.byKey(const ValueKey('submit-add-sector-button')));
    await tester.pumpAndSettle();

    // Verify error SnackBar is displayed to the user
    expect(find.textContaining('Error adding sector'), findsOneWidget);
    expect(find.textContaining('Network offline'), findsOneWidget);
  });

  testWidgets(
      'delete sector warning matches members with normalizedSectorName or different casing',
      (tester) async {
    final fakeRepo = FakeRoomRepository();
    final room = createTestRoom(sectors: ['Sector Alpha']);
    final members = [
      createTestMember(
        uid: 'm1',
        sectorName: 'sector alpha', // lowercase vs capitalized
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SectorManagementCard(
              room: room,
              members: members,
              isLocked: false,
            ),
          ),
        ),
      ),
    );

    final chip = find.byKey(const ValueKey('sector-chip-Sector Alpha'));
    final deleteIcon = find.descendant(of: chip, matching: find.byIcon(Icons.close));
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();

    // Must recognize member even with casing difference
    expect(
        find.textContaining('Warning: Sector "Sector Alpha" currently has 1 joined participant(s)'),
        findsOneWidget);
  });
}

class _FailingRoomRepository implements RoomRepository {
  @override
  Future<void> updateRoomSectors(String roomId, List<String> sectors) async {
    throw Exception('Network offline');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
