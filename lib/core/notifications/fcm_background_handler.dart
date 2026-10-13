import 'dart:convert';
import 'package:alarm/alarm.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import '../models/phase_model.dart';
import '../models/run_model.dart';
import '../models/sound_mode.dart';
import '../timer/schedule_engine.dart';
import 'notification_service.dart';

/// Top-level background message handler invoked by FirebaseMessaging background isolate.
/// Must be annotated with `@pragma('vm:entry-point')` to prevent tree-shaking.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {}
  }

  try {
    await Alarm.init();
  } catch (_) {}

  try {
    await NotificationService().initialize();
  } catch (_) {}

  await handleBackgroundDataMessage(message.data);
}

RunStatus _parseRunStatus(String? status) {
  switch (status) {
    case 'starting':
      return RunStatus.starting;
    case 'paused':
      return RunStatus.paused;
    case 'completed':
      return RunStatus.completed;
    case 'ended':
      return RunStatus.ended;
    case 'running':
    default:
      return RunStatus.running;
  }
}

/// Pure, decoupled processing function for high-priority FCM data pushes.
/// Used directly by the background isolate and unit tests.
Future<bool> handleBackgroundDataMessage(
  Map<String, dynamic> data, {
  NotificationService? notificationService,
  SharedPreferences? prefs,
  int? mockNowMs,
}) async {
  final notifService = notificationService ?? NotificationService();
  final preferences = prefs ?? await SharedPreferences.getInstance();

  final roomId = data['roomId'] as String?;
  if (roomId == null || roomId.trim().isEmpty) {
    return false;
  }

  final action = data['action'] as String?;

  final activeRoomId = preferences.getString('active_room_id');
  // If the device is not bound to this room (or bound to a different room), ignore events.
  if (activeRoomId != roomId) {
    if (action == 'close_room' || action == 'end_event') {
      await notifService.cancelRoomNotifications(roomId);
    }
    return false;
  }

  final eventId = data['eventId'] as String?;
  if (eventId != null && eventId.isNotEmpty) {
    final handledKey = 'fcm_handled_${roomId}_$eventId';
    if (preferences.getBool(handledKey) == true) {
      return true; // Already processed, avoid duplicate notifications
    }
    await preferences.setBool(handledKey, true);
  }
  final runId = data['runId'] as String?;
  final revisionStr = data['revision'] as String?;
  final runStatusStr = data['runStatus'] as String?;
  final scheduleJson = data['schedule'] as String?;
  final roundCountStr = data['roundCount'] as String?;
  final startsAtStr = data['startsAt'] as String?;
  final pausedPhaseId = data['pausedPhaseId'] as String?;
  final pausedRemainingMsStr =
      data['pausedRemainingMs'] as String? ?? data['remainingMs'] as String?;
  final pausedAtStr = data['pausedAt'] as String?;
  final title = data['title'] as String?;
  final body = data['body'] as String?;
  final targetUid = data['targetUid'] as String?;
  final targetSectorName = data['targetSectorName'] as String?;
  final type = data['type'] as String?;

  // 1. Handle room closure
  if (action == 'close_room') {
    await notifService.cancelRoomNotifications(roomId);
    await preferences.remove('active_room_id');
    await preferences.remove('active_room_pin');
    await preferences.remove('cached_schedule_$roomId');
    await preferences.remove('cached_revision_$roomId');
    await preferences.remove('cached_status_$roomId');
    await preferences.remove('cached_run_id_$roomId');
    await preferences.remove('cached_round_count_$roomId');
    await preferences.remove('cached_paused_state_$roomId');
    if (title != null && title.isNotEmpty) {
      await notifService.showActionNotification(
        title: title,
        body: body ?? '',
      );
    }
    return true;
  }

  // 2. Handle event ended
  if (action == 'end_event' || runStatusStr == 'ended') {
    await notifService.cancelRoomNotifications(roomId);
    await preferences.remove('cached_schedule_$roomId');
    await preferences.remove('cached_status_$roomId');
    await preferences.remove('cached_paused_state_$roomId');
    if (title != null && title.isNotEmpty) {
      await notifService.showActionNotification(
        title: title,
        body: body ?? '',
      );
    }
    return true;
  }

  // 3. Handle targeted or broadcast announcements
  if (action == 'announcement' || type == 'announcement') {
    final currentUid = preferences.getString('current_user_uid');
    final mySector = preferences.getString('user_sector_name');

    if (targetUid != null && currentUid != null && targetUid != currentUid) {
      return false; // Targeted to a different participant
    }

    if (targetSectorName != null &&
        mySector != null &&
        targetSectorName.toLowerCase() != mySector.toLowerCase()) {
      return false; // Targeted to a different sector
    }

    if (title != null && title.isNotEmpty) {
      await notifService.showActionNotification(
        title: title,
        body: body ?? '',
      );
    }
    return true;
  }

  // 4. Handle schedule updates (start_run, pause, resume, adjust_time, end_round)
  if (scheduleJson != null && scheduleJson.isNotEmpty) {
    try {
      final List<dynamic> decodedList = jsonDecode(scheduleJson) as List<dynamic>;
      final phases = decodedList
          .map((item) => Phase.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();

      final int revision = int.tryParse(revisionStr ?? '') ?? 1;
      final int roundCount = int.tryParse(roundCountStr ?? '') ??
          phases.where((p) => p.type == PhaseType.round).length;
      final runStatus = _parseRunStatus(runStatusStr ??
          (action == 'pause'
              ? 'paused'
              : action == 'start_run'
                  ? 'starting'
                  : 'running'));

      final nowMs = mockNowMs ?? DateTime.now().millisecondsSinceEpoch;

      final startsAt = int.tryParse(startsAtStr ?? '') ??
          (phases.isNotEmpty ? phases.first.startsAt : nowMs);

      // Determine accurate paused state
      int? remainingMs = int.tryParse(pausedRemainingMsStr ?? '');
      final activePhase = phases.firstWhere(
        (p) => pausedPhaseId != null ? p.phaseId == pausedPhaseId : p.endsAt > nowMs,
        orElse: () => phases.first,
      );
      if (remainingMs == null && runStatus == RunStatus.paused) {
        remainingMs = (activePhase.endsAt - nowMs).clamp(0, activePhase.durationMs);
      }

      final pausedState = runStatus == RunStatus.paused
          ? PausedState(
              pausedAt: int.tryParse(pausedAtStr ?? '') ?? nowMs,
              pausedPhaseId: pausedPhaseId ?? activePhase.phaseId,
              remainingMs: remainingMs ?? 0,
            )
          : null;

      final run = RoomRun(
        runId: runId ?? 'run_$revision',
        status: runStatus,
        revision: revision,
        roundCount: roundCount > 0 ? roundCount : 1,
        standardRoundDurationMs:
            phases.isNotEmpty ? phases.first.durationMs : 60000,
        cooldownMs: 0,
        startsAt: startsAt,
        schedule: phases,
        pausedState: pausedState,
        createdAt: nowMs,
        updatedAt: nowMs,
      );

      // Cache updated schedule and revision locally in SharedPreferences
      await preferences.setString('cached_schedule_$roomId', scheduleJson);
      await preferences.setInt('cached_revision_$roomId', revision);
      await preferences.setString('cached_status_$roomId', runStatus.name);
      if (runId != null) {
        await preferences.setString('cached_run_id_$roomId', runId);
      }
      await preferences.setInt('cached_round_count_$roomId', roundCount);
      if (pausedState != null) {
        await preferences.setString(
          'cached_paused_state_$roomId',
          jsonEncode({
            'pausedAt': pausedState.pausedAt,
            'pausedPhaseId': pausedState.pausedPhaseId,
            'remainingMs': pausedState.remainingMs,
          }),
        );
      } else {
        await preferences.remove('cached_paused_state_$roomId');
      }

      final soundModeStr = preferences.getString('selected_sound_mode');
      final soundMode = SoundMode.fromString(soundModeStr);

      final locale = preferences.getString('app_locale_code') ?? 'en';
      final isArabic = locale.toLowerCase().startsWith('ar');

      // Reschedule exact Android OS AlarmManager alarms to updated timestamps
      await notifService.scheduleBoundaryAlarms(
        roomId: roomId,
        run: run,
        soundMode: soundMode,
        nowMs: nowMs,
        isArabic: isArabic,
      );

      // Update ongoing countdown timer notification
      final derived = ScheduleEngine.deriveState(run, nowMs);
      await notifService.updateOngoingTimerNotification(
        roomId: roomId,
        run: run,
        derivedState: derived,
        isArabic: isArabic,
      );

      // Show alert notification for control adjustments (pause, adjust, skipped round, start)
      if (title != null && title.isNotEmpty) {
        await notifService.showActionNotification(
          title: title,
          body: body ?? '',
        );
      }

      return true;
    } catch (e) {
      debugPrint('Error processing background FCM schedule payload: $e');
      return false;
    }
  }

  return false;
}
