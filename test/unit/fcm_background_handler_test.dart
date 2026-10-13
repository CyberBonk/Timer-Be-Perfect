import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:be_perfect/core/models/run_model.dart';
import 'package:be_perfect/core/models/sound_mode.dart';
import 'package:be_perfect/core/notifications/fcm_background_handler.dart';
import 'package:be_perfect/core/notifications/notification_service.dart';
import 'package:be_perfect/core/timer/schedule_engine.dart';

class FakeNotificationService extends NotificationService {
  FakeNotificationService() : super.custom();

  RoomRun? lastScheduledRun;
  String? lastScheduledRoomId;
  SoundMode? lastScheduledSoundMode;
  int? lastScheduledNowMs;

  RoomRun? lastOngoingRun;
  TimerDerivedState? lastDerivedState;
  String? lastOngoingRoomId;

  String? cancelledRoomId;
  final List<Map<String, String>> shownActionNotifications = [];

  @override
  Future<void> scheduleBoundaryAlarms({
    required String roomId,
    required RoomRun run,
    required SoundMode soundMode,
    required int nowMs,
    bool isArabic = false,
  }) async {
    lastScheduledRoomId = roomId;
    lastScheduledRun = run;
    lastScheduledSoundMode = soundMode;
    lastScheduledNowMs = nowMs;
  }

  @override
  Future<void> updateOngoingTimerNotification({
    required String roomId,
    required RoomRun run,
    required TimerDerivedState derivedState,
    bool isArabic = false,
  }) async {
    lastOngoingRoomId = roomId;
    lastOngoingRun = run;
    lastDerivedState = derivedState;
  }

  @override
  Future<void> cancelRoomNotifications(String roomId) async {
    cancelledRoomId = roomId;
  }

  @override
  Future<void> showActionNotification({
    required String title,
    required String body,
    String? channelId,
  }) async {
    shownActionNotifications.add({'title': title, 'body': body});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationService fakeNotif;
  const roomId = 'room_999';

  setUp(() {
    fakeNotif = FakeNotificationService();
    SharedPreferences.setMockInitialValues({
      'active_room_id': roomId,
      'current_user_uid': 'user_123',
      'user_sector_name': 'Sector A',
      'selected_sound_mode': 'be_perfect_sound',
    });
  });

  test('Layer 2 FCM: start_run payload reschedules boundary alarms and caches schedule', () async {
    final nowMs = 1700000000000;
    final schedule = [
      {
        'phaseId': 'p1',
        'type': 'round',
        'roundIndex': 1,
        'startsAt': nowMs + 5000,
        'endsAt': nowMs + 1205000,
      },
      {
        'phaseId': 'p2',
        'type': 'cooldown',
        'roundIndex': 1,
        'startsAt': nowMs + 1205000,
        'endsAt': nowMs + 1265000,
      },
      {
        'phaseId': 'p3',
        'type': 'round',
        'roundIndex': 2,
        'startsAt': nowMs + 1265000,
        'endsAt': nowMs + 2465000,
      },
    ];

    final payload = {
      'eventId': 'ev_1',
      'roomId': roomId,
      'runId': 'run_alpha',
      'revision': '2',
      'action': 'start_run',
      'runStatus': 'starting',
      'roundCount': '2',
      'schedule': jsonEncode(schedule),
      'title': 'Event Started',
      'body': 'Run started with 2 rounds.',
    };

    final result = await handleBackgroundDataMessage(
      payload,
      notificationService: fakeNotif,
      mockNowMs: nowMs,
    );

    expect(result, isTrue);
    expect(fakeNotif.lastScheduledRoomId, roomId);
    expect(fakeNotif.lastScheduledRun, isNotNull);
    expect(fakeNotif.lastScheduledRun!.runId, 'run_alpha');
    expect(fakeNotif.lastScheduledRun!.revision, 2);
    expect(fakeNotif.lastScheduledRun!.roundCount, 2);
    expect(fakeNotif.lastScheduledRun!.schedule.length, 3);
    expect(fakeNotif.lastScheduledSoundMode, SoundMode.bePerfectSound);

    // Verify local cache persistence for deep sleep / offline restarts
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cached_schedule_$roomId'), isNotNull);
    expect(prefs.getInt('cached_revision_$roomId'), 2);

    // Verify ongoing notification was updated
    expect(fakeNotif.lastOngoingRoomId, roomId);
    expect(fakeNotif.lastDerivedState, isNotNull);

    // Verify action notification was displayed
    expect(fakeNotif.shownActionNotifications.length, 1);
    expect(fakeNotif.shownActionNotifications.first['title'], 'Event Started');
  });

  test('Layer 2 FCM: adjust_time payload (+1m) updates timestamps and alarm plan', () async {
    final nowMs = 1700000000000;
    final initialEnd = nowMs + 600000;
    final adjustedEnd = initialEnd + 60000; // +1 min

    final schedule = [
      {
        'phaseId': 'p1',
        'type': 'round',
        'roundIndex': 1,
        'startsAt': nowMs - 60000,
        'endsAt': adjustedEnd,
      },
    ];

    final payload = {
      'eventId': 'ev_2',
      'roomId': roomId,
      'runId': 'run_alpha',
      'revision': '3',
      'action': 'adjust_time',
      'runStatus': 'running',
      'roundCount': '1',
      'schedule': jsonEncode(schedule),
      'title': 'Timer Adjusted',
      'body': 'Controller adjusted active round duration by +1 minute(s).',
    };

    final result = await handleBackgroundDataMessage(
      payload,
      notificationService: fakeNotif,
      mockNowMs: nowMs,
    );

    expect(result, isTrue);
    expect(fakeNotif.lastScheduledRun!.schedule.first.endsAt, adjustedEnd);

    final plan = fakeNotif.buildBoundaryAlarmPlan(
      roomId: roomId,
      run: fakeNotif.lastScheduledRun!,
      nowMs: nowMs,
    );
    expect(plan.length, 1);
    expect(plan.first.phase.endsAt, adjustedEnd);
  });

  test('Layer 2 FCM: pause payload pauses run and clears pending alarms', () async {
    final nowMs = 1700000000000;
    final schedule = [
      {
        'phaseId': 'p1',
        'type': 'round',
        'roundIndex': 1,
        'startsAt': nowMs - 60000,
        'endsAt': nowMs + 500000,
      },
    ];

    final payload = {
      'eventId': 'ev_3',
      'roomId': roomId,
      'runId': 'run_alpha',
      'revision': '4',
      'action': 'pause',
      'runStatus': 'paused',
      'roundCount': '1',
      'schedule': jsonEncode(schedule),
      'title': 'Event Paused',
      'body': 'Controller paused the timer.',
    };

    final result = await handleBackgroundDataMessage(
      payload,
      notificationService: fakeNotif,
      mockNowMs: nowMs,
    );

    expect(result, isTrue);
    expect(fakeNotif.lastScheduledRun!.status, RunStatus.paused);
    expect(fakeNotif.lastDerivedState!.state, DerivedPhaseState.paused);
    expect(fakeNotif.lastDerivedState!.remainingMs, 500000);
    expect(fakeNotif.lastDerivedState!.formattedTime, '08:20');
  });

  test('Layer 2 FCM: resume payload restores running state and reschedules alarm plan', () async {
    final nowMs = 1700000000000;
    final resumeEnd = nowMs + 450000;
    final schedule = [
      {
        'phaseId': 'p1',
        'type': 'round',
        'roundIndex': 1,
        'startsAt': nowMs,
        'endsAt': resumeEnd,
      },
    ];

    final payload = {
      'eventId': 'ev_resume',
      'roomId': roomId,
      'runId': 'run_alpha',
      'revision': '5',
      'action': 'resume',
      'runStatus': 'running',
      'roundCount': '1',
      'schedule': jsonEncode(schedule),
      'title': 'Event Resumed',
      'body': 'Controller resumed the timer.',
    };

    final result = await handleBackgroundDataMessage(
      payload,
      notificationService: fakeNotif,
      mockNowMs: nowMs,
    );

    expect(result, isTrue);
    expect(fakeNotif.lastScheduledRun!.status, RunStatus.running);
    expect(fakeNotif.lastDerivedState!.state, DerivedPhaseState.runningRound);

    final plan = fakeNotif.buildBoundaryAlarmPlan(
      roomId: roomId,
      run: fakeNotif.lastScheduledRun!,
      nowMs: nowMs,
    );
    expect(plan.length, 1);
    expect(plan.first.phase.endsAt, resumeEnd);
  });

  test('Layer 2 FCM: end_round payload updates boundary and transitions active phase', () async {
    final nowMs = 1700000000000;
    final schedule = [
      {
        'phaseId': 'p1',
        'type': 'round',
        'roundIndex': 1,
        'startsAt': nowMs - 120000,
        'endsAt': nowMs,
      },
      {
        'phaseId': 'p2',
        'type': 'cooldown',
        'roundIndex': 1,
        'startsAt': nowMs,
        'endsAt': nowMs + 60000,
      },
      {
        'phaseId': 'p3',
        'type': 'round',
        'roundIndex': 2,
        'startsAt': nowMs + 60000,
        'endsAt': nowMs + 1260000,
      },
    ];

    final payload = {
      'eventId': 'ev_end_round',
      'roomId': roomId,
      'runId': 'run_alpha',
      'revision': '6',
      'action': 'end_round',
      'runStatus': 'running',
      'roundCount': '2',
      'schedule': jsonEncode(schedule),
      'title': 'Round Ended Early',
      'body': 'Controller ended the active round.',
    };

    final result = await handleBackgroundDataMessage(
      payload,
      notificationService: fakeNotif,
      mockNowMs: nowMs,
    );

    expect(result, isTrue);
    expect(fakeNotif.lastDerivedState!.state, DerivedPhaseState.cooldown);
    final plan = fakeNotif.buildBoundaryAlarmPlan(
      roomId: roomId,
      run: fakeNotif.lastScheduledRun!,
      nowMs: nowMs,
    );
    // Only round 2 is in the future
    expect(plan.length, 1);
    expect(plan.first.roundIndex, 2);
  });

  test('Layer 2 FCM: duplicate eventId delivery is deduplicated safely', () async {
    final nowMs = 1700000000000;
    final payload = {
      'eventId': 'ev_duplicate_1',
      'roomId': roomId,
      'action': 'announcement',
      'title': 'Unique Notice',
      'body': 'First and only popup.',
    };

    final firstResult = await handleBackgroundDataMessage(
      payload,
      notificationService: fakeNotif,
      mockNowMs: nowMs,
    );
    expect(firstResult, isTrue);
    expect(fakeNotif.shownActionNotifications.length, 1);

    // Second delivery of exact same event
    final secondResult = await handleBackgroundDataMessage(
      payload,
      notificationService: fakeNotif,
      mockNowMs: nowMs,
    );
    expect(secondResult, isTrue);
    // Should NOT have shown a second action notification
    expect(fakeNotif.shownActionNotifications.length, 1);
  });

  test('Layer 2 FCM: message is ignored when device has not joined any room', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_room_id');

    final payload = {
      'eventId': 'ev_unjoined',
      'roomId': roomId,
      'action': 'start_run',
      'schedule': jsonEncode([
        {'phaseId': 'p1', 'type': 'round', 'roundIndex': 1, 'startsAt': 100, 'endsAt': 200}
      ]),
    };

    final result = await handleBackgroundDataMessage(
      payload,
      notificationService: fakeNotif,
    );

    expect(result, isFalse);
    expect(fakeNotif.lastScheduledRun, isNull);
  });

  test('Layer 2 FCM: announcement targeting delivers matching and filters non-matching', () async {
    // 1. Matching sector announcement
    final matchingSectorPayload = {
      'eventId': 'ev_sector_match',
      'roomId': roomId,
      'action': 'announcement',
      'title': 'Sector Notice',
      'body': 'Please assemble.',
      'targetSectorName': 'Sector A',
    };
    final res1 = await handleBackgroundDataMessage(
      matchingSectorPayload,
      notificationService: fakeNotif,
    );
    expect(res1, isTrue);
    expect(fakeNotif.shownActionNotifications.any((n) => n['title'] == 'Sector Notice'), isTrue);

    // 2. Non-matching sector announcement
    fakeNotif.shownActionNotifications.clear();
    final nonMatchingSectorPayload = {
      'eventId': 'ev_sector_miss',
      'roomId': roomId,
      'action': 'announcement',
      'title': 'Sector B Only',
      'body': 'Ignored by Sector A.',
      'targetSectorName': 'Sector B',
    };
    final res2 = await handleBackgroundDataMessage(
      nonMatchingSectorPayload,
      notificationService: fakeNotif,
    );
    expect(res2, isFalse);
    expect(fakeNotif.shownActionNotifications.isEmpty, isTrue);

    // 3. Matching UID announcement
    fakeNotif.shownActionNotifications.clear();
    final matchingUidPayload = {
      'eventId': 'ev_uid_match',
      'roomId': roomId,
      'action': 'announcement',
      'title': 'Direct Message',
      'body': 'Hello user_123',
      'targetUid': 'user_123',
    };
    final res3 = await handleBackgroundDataMessage(
      matchingUidPayload,
      notificationService: fakeNotif,
    );
    expect(res3, isTrue);
    expect(fakeNotif.shownActionNotifications.any((n) => n['title'] == 'Direct Message'), isTrue);

    // 4. Non-matching UID announcement
    fakeNotif.shownActionNotifications.clear();
    final nonMatchingUidPayload = {
      'eventId': 'ev_uid_miss',
      'roomId': roomId,
      'action': 'announcement',
      'title': 'Other User Message',
      'body': 'Not for user_123',
      'targetUid': 'user_other',
    };
    final res4 = await handleBackgroundDataMessage(
      nonMatchingUidPayload,
      notificationService: fakeNotif,
    );
    expect(res4, isFalse);
    expect(fakeNotif.shownActionNotifications.isEmpty, isTrue);
  });

  test('Layer 2 FCM: close_room and end_event cancel room notifications immediately', () async {
    final closePayload = {
      'eventId': 'ev_close',
      'roomId': roomId,
      'action': 'close_room',
      'title': 'Room Closed',
      'body': 'Access revoked by Controller.',
    };

    final result = await handleBackgroundDataMessage(
      closePayload,
      notificationService: fakeNotif,
    );

    expect(result, isTrue);
    expect(fakeNotif.cancelledRoomId, roomId);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('active_room_id'), isNull);
  });

  test('Layer 2 FCM: foreign room message is discarded when device is in a different active room', () async {
    final foreignPayload = {
      'eventId': 'ev_foreign',
      'roomId': 'foreign_room_888',
      'action': 'start_run',
      'schedule': jsonEncode([
        {'phaseId': 'p1', 'type': 'round', 'roundIndex': 1, 'startsAt': 100, 'endsAt': 200}
      ]),
    };

    final result = await handleBackgroundDataMessage(
      foreignPayload,
      notificationService: fakeNotif,
    );

    expect(result, isFalse);
    expect(fakeNotif.lastScheduledRoomId, isNull);
  });
}
