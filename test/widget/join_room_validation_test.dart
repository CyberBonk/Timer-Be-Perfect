import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:be_perfect/core/firebase/firebase_providers.dart';
import 'package:be_perfect/core/firebase/room_repository.dart';
import 'package:be_perfect/features/rooms/join_room_dialog.dart';

void main() {
  testWidgets('join validates PIN before contacting Firebase', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: JoinRoomDialog()),
    ));

    await tester.enterText(find.byKey(const ValueKey('room-pin-field')), '123');
    await tester.enterText(
        find.byKey(const ValueKey('participant-name-field')), 'Alpha');
    await tester.tap(find.byKey(const ValueKey('join-submit-button')));
    await tester.pump();

    expect(find.text('Join code must be exactly 6 numeric digits.'),
        findsOneWidget);
  });

  testWidgets('join validates participant name before contacting Firebase',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: JoinRoomDialog()),
    ));

    await tester.enterText(
        find.byKey(const ValueKey('room-pin-field')), '123456');
    await tester.tap(find.byKey(const ValueKey('join-submit-button')));
    await tester.pump();

    expect(find.text('Participant name must be between 1 and 30 characters.'),
        findsOneWidget);
  });

  testWidgets('sector dropdown is disabled with waiting placeholder and blocks joining when empty',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: JoinRoomDialog()),
    ));

    expect(
      find.text('Waiting for controller to create sectors...'),
      findsOneWidget,
    );

    // Verify sector selection is a dropdown and NEVER a text field
    expect(find.byKey(const ValueKey('sector-name-field')), findsNothing);
    expect(find.byKey(const ValueKey('sector-dropdown-field')), findsOneWidget);

    // Try joining with valid PIN and participant name but without sectors
    await tester.enterText(
        find.byKey(const ValueKey('room-pin-field')), '123456');
    await tester.enterText(
        find.byKey(const ValueKey('participant-name-field')), 'John Doe');
    await tester.tap(find.byKey(const ValueKey('join-submit-button')));
    await tester.pump();

    // Verify joining is blocked with error message
    expect(
      find.text('Waiting for controller to create sectors...'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets(
      'sector dropdown live syncs when controller adds sectors and ungreys',
      (tester) async {
    final sectorsController = StreamController<List<String>>.broadcast();

    final fakeRepo = _FakeJoinRoomRepository(
      sectorsStream: sectorsController.stream,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        roomRepositoryProvider.overrideWithValue(fakeRepo),
      ],
      child: const MaterialApp(home: JoinRoomDialog()),
    ));

    // Initially empty
    expect(
      find.text('Waiting for controller to create sectors...'),
      findsOneWidget,
    );

    // Enter 6-digit PIN to trigger real-time subscription
    await tester.enterText(
        find.byKey(const ValueKey('room-pin-field')), '654321');
    await tester.pump();

    // Stream emits sectors in real time (controller added them)
    sectorsController.add(['قطاع 1', 'المسرح']);
    await tester.pumpAndSettle();

    // Dropdown is ungreyed and shows first sector selected
    expect(find.text('قطاع 1'), findsOneWidget);

    await sectorsController.close();
  });
}

class _FakeJoinRoomRepository implements RoomRepository {
  final Stream<List<String>> sectorsStream;

  _FakeJoinRoomRepository({required this.sectorsStream});

  @override
  Stream<List<String>> watchRoomSectorsByCode(String code) {
    return sectorsStream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
