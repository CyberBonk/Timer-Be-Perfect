import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/run_model.dart';
import '../models/phase_model.dart';
import '../models/sound_mode.dart';
import '../timer/schedule_engine.dart';
import 'notification_channels.dart';

class BoundaryAlarmSpec {
  final String roomId;
  final Phase phase;

  const BoundaryAlarmSpec({required this.roomId, required this.phase});

  int get roundIndex => phase.roundIndex ?? 1;
  int get notificationId {
    var hash = 0;
    for (final codeUnit in roomId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return (hash % 20000000) * 100 + roundIndex + 1;
  }
}

class NotificationService {
  static const _testAlarmId = 2147483000;
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  NotificationService.custom();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {},
    );

    if (Platform.isAndroid) {
      await NotificationChannels.setupNotificationChannels(
          _notificationsPlugin);
    }

    _initialized = true;
  }

  Future<bool> areNotificationsEnabled() async {
    final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  Future<bool> canScheduleExactNotifications() async {
    final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  int getNotificationId(String roomId) {
    return roomId.hashCode.abs() % 100000;
  }

  int getRoundAlarmNotificationId(String roomId, int roundIndex) {
    var hash = 0;
    for (final codeUnit in roomId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return (hash % 20000000) * 100 + roundIndex + 1;
  }

  Future<void> updateOngoingTimerNotification({
    required String roomId,
    required RoomRun run,
    required TimerDerivedState derivedState,
    bool isArabic = false,
  }) async {
    String text(String english, String arabic) => isArabic ? arabic : english;
    final notificationId = getNotificationId(roomId);

    if (derivedState.state == DerivedPhaseState.completed ||
        derivedState.state == DerivedPhaseState.ended) {
      await _notificationsPlugin.cancel(id: notificationId);
      await _notificationsPlugin.show(
        id: notificationId + 1,
        title: text(
          'Timer Be Perfect — Event Completed',
          'Timer Be Perfect — اكتملت الفعالية',
        ),
        body: text('All rounds have concluded!', 'انتهت جميع الجولات!'),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            NotificationChannels.announcementsChannelId,
            'Event Completion',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      return;
    }

    if (derivedState.state == DerivedPhaseState.paused) {
      await _notificationsPlugin.show(
        id: notificationId,
        title: text(
          'Timer Be Perfect (Paused)',
          'Timer Be Perfect (متوقف مؤقتًا)',
        ),
        body: text(
          'Round ${derivedState.currentRoundIndex} of ${run.roundCount} — ${derivedState.formattedTime} remaining',
          'الجولة ${derivedState.currentRoundIndex} من ${run.roundCount} — متبقي ${derivedState.formattedTime}',
        ),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            NotificationChannels.timerChannelId,
            NotificationChannels.timerChannelName,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            silent: true,
            playSound: false,
            visibility: NotificationVisibility.public,
            usesChronometer: false,
          ),
        ),
      );
      return;
    }

    String title = 'Timer Be Perfect';
    String content =
        'Round ${derivedState.currentRoundIndex} of ${run.roundCount}';

    if (derivedState.state == DerivedPhaseState.starting) {
      title = text(
        'Timer Be Perfect (Starting Soon)',
        'Timer Be Perfect (سيبدأ قريبًا)',
      );
      content = text(
        'Starting in ${derivedState.startingCountdownSeconds}s',
        'يبدأ خلال ${derivedState.startingCountdownSeconds} ث',
      );
    } else if (derivedState.state == DerivedPhaseState.cooldown) {
      title = text(
        'Timer Be Perfect (Cooldown)',
        'Timer Be Perfect (فترة راحة)',
      );
      content = text(
        'Next round starts soon',
        'ستبدأ الجولة التالية قريبًا',
      );
    } else {
      content = text(
        content,
        'الجولة ${derivedState.currentRoundIndex} من ${run.roundCount}',
      );
    }

    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.timerChannelId,
      NotificationChannels.timerChannelName,
      channelDescription: NotificationChannels.timerChannelDesc,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      silent: true,
      playSound: false,
      visibility: NotificationVisibility.public,
      usesChronometer: true,
      chronometerCountDown: true,
      when: derivedState.targetEndTimestampMs,
    );

    await _notificationsPlugin.show(
      id: notificationId,
      title: title,
      body: content,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  Future<void> scheduleBoundaryAlarms({
    required String roomId,
    required RoomRun run,
    required SoundMode soundMode,
    required int nowMs,
    bool isArabic = false,
  }) async {
    // Keep the final boundary alarm alive: the run can become completed
    // before Android delivers the already-scheduled participant alarm.
    if (run.status == RunStatus.completed || run.status == RunStatus.ended) {
      return;
    }

    await _stopRoomAlarms(roomId);

    if (run.status == RunStatus.paused) return;

    for (final spec in buildBoundaryAlarmPlan(
      roomId: roomId,
      run: run,
      nowMs: nowMs,
    )) {
      final phase = spec.phase;
      final title = isArabic
          ? 'اكتملت الجولة ${phase.roundIndex}'
          : 'Round ${phase.roundIndex} Completed';
      final body = phase.roundIndex == run.roundCount
          ? (isArabic
              ? 'انتهت الجولة الأخيرة واكتملت الفعالية.'
              : 'Final round finished! Event completed.')
          : (isArabic
              ? 'انتهت الجولة ${phase.roundIndex}.'
              : 'Round ${phase.roundIndex} has ended.');

      await Alarm.set(
        alarmSettings: _alarmSettings(
          id: spec.notificationId,
          dateTime: DateTime.fromMillisecondsSinceEpoch(phase.endsAt),
          soundMode: soundMode,
          title: title,
          body: body,
          stopButton: isArabic ? 'إيقاف التنبيه' : 'Stop alarm',
          payload: '$roomId:${spec.roundIndex}',
        ),
      );
    }
  }

  /// Pure schedule projection used by the Android alarm path and tests.
  List<BoundaryAlarmSpec> buildBoundaryAlarmPlan({
    required String roomId,
    required RoomRun run,
    required int nowMs,
  }) {
    if (run.status == RunStatus.completed || run.status == RunStatus.ended) {
      return const [];
    }
    return [
      for (final phase in run.schedule)
        if (phase.type == PhaseType.round && phase.endsAt > nowMs)
          BoundaryAlarmSpec(roomId: roomId, phase: phase),
    ];
  }

  Future<void> dismissRoundAlarm(String roomId, int roundIndex) async {
    await Alarm.stop(getRoundAlarmNotificationId(roomId, roundIndex));
  }

  Future<int?> findActiveRoundAlarm(String roomId, int roundCount) async {
    for (var round = 1; round <= roundCount; round++) {
      if (await Alarm.isRinging(
        getRoundAlarmNotificationId(roomId, round),
      )) {
        return round;
      }
    }
    return null;
  }

  Future<void> testRoundAlarm({
    required SoundMode soundMode,
    required bool isArabic,
  }) async {
    await Alarm.stop(_testAlarmId);
    await Alarm.set(
      alarmSettings: _alarmSettings(
        id: _testAlarmId,
        dateTime: DateTime.now().add(const Duration(seconds: 2)),
        soundMode: soundMode,
        title: isArabic ? 'تجربة تنبيه Be Perfect' : 'Be Perfect alarm test',
        body: isArabic
            ? 'اضغط إيقاف لإغلاق التنبيه.'
            : 'Tap Stop alarm to dismiss.',
        stopButton: isArabic ? 'إيقاف التنبيه' : 'Stop alarm',
        payload: 'test',
      ),
    );
  }

  AlarmSettings _alarmSettings({
    required int id,
    required DateTime dateTime,
    required SoundMode soundMode,
    required String title,
    required String body,
    required String stopButton,
    required String payload,
  }) {
    final vibrationOnly = soundMode == SoundMode.vibrationOnly;
    return AlarmSettings(
      id: id,
      dateTime: dateTime,
      assetAudioPath: soundMode == SoundMode.deviceDefault
          ? null
          : 'assets/audio/be_perfect_round_alarm.mp3',
      // A round alert must always stop by itself if Android or an OEM skin
      // fails to surface the notification action.
      loopAudio: false,
      vibrate: true,
      warningNotificationOnKill: false,
      androidFullScreenIntent: true,
      androidStopAlarmOnTermination: false,
      allowAlarmOverlap: false,
      payload: payload,
      volumeSettings: VolumeSettings.fixed(
        volume: vibrationOnly ? 0 : 1,
        volumeEnforced: !vibrationOnly,
        showSystemUI: false,
      ),
      notificationSettings: NotificationSettings(
        title: title,
        body: body,
        stopButton: stopButton,
      ),
    );
  }

  Future<void> _stopRoomAlarms(String roomId) async {
    final alarms = await Alarm.getAlarms();
    for (final alarm in alarms) {
      if (alarm.payload?.startsWith('$roomId:') == true) {
        await Alarm.stop(alarm.id);
      }
    }
  }

  Future<void> showActionNotification({
    required String title,
    required String body,
    String? channelId,
  }) async {
    final targetChannel =
        channelId ?? NotificationChannels.announcementsChannelId;
    final id = DateTime.now().millisecondsSinceEpoch % 100000;
    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          targetChannel,
          NotificationChannels.announcementsChannelName,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound:
              const RawResourceAndroidNotificationSound('be_perfect_round_alarm'),
          enableVibration: true,
        ),
      ),
    );
  }

  Future<void> cancelRoomNotifications(String roomId) async {
    await _stopRoomAlarms(roomId);
    await _notificationsPlugin.cancel(id: getNotificationId(roomId));
  }
}
