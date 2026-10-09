import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/firebase/firebase_providers.dart';
import '../core/firebase/server_clock.dart';
import '../core/firebase/room_authorization.dart';
import '../core/localization/app_locale.dart';
import '../core/notifications/notification_service.dart';
import '../core/notifications/ringer_service.dart';
import '../core/timer/schedule_engine.dart';
import '../core/models/room_model.dart';
import '../core/models/run_model.dart';
import '../core/models/sound_mode.dart';
import '../features/home/home_page.dart';
import '../features/timer/controller_dashboard_page.dart';
import '../features/timer/participant_timer_page.dart';
import '../features/announcements/announcements_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/about_page.dart';

class NavigationHostPage extends ConsumerStatefulWidget {
  const NavigationHostPage({super.key});

  @override
  ConsumerState<NavigationHostPage> createState() => _NavigationHostPageState();
}

class _NavigationHostPageState extends ConsumerState<NavigationHostPage> {
  int _currentIndex = 0;

  // Feed deduplication
  final Set<String> _seenFeedEventIds = {};
  bool _feedInitialized = false;

  // 1-second ticker for ongoing notification (prevents negative countdown)
  Timer? _notifTicker;

  String? _presenceRoomId;
  String? _presenceUid;

  // Round-phase tracking for natural round and cooldown announcements.
  RoomRun? _lastRun;
  TimerDerivedState? _lastDerivedState;
  String? _scheduledAlarmKey;
  bool _audioSessionInitialized = false;
  bool _returningViewerHome = false;

  bool _isController() {
    final room = ref.read(roomStreamProvider).asData?.value;
    if (room != null) {
      return isRoomController(
        ownerUid: room.ownerUid,
        currentUid: ref.read(roomRepositoryProvider).currentUid,
      );
    }
    // Keep the persisted role only while the authoritative room is loading.
    return ref.read(activeRoomPinProvider) != null;
  }

  Future<void> _prepareAudioSession() async {
    if (ref.read(soundModeProvider) == SoundMode.vibrationOnly) return;
    await RingerService().forceSoundMode();
  }

  @override
  void initState() {
    super.initState();
    // Tick every second to keep the ongoing notification in sync
    _notifTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickNotification();
    });
  }

  @override
  void dispose() {
    _notifTicker?.cancel();
    super.dispose();
  }

  void _tickNotification() {
    final run = _lastRun;
    final roomId = ref.read(activeRoomIdProvider);
    final isController = _isController();
    if (run == null || roomId == null) return;

    final nowMs = ServerClock().nowMs();
    final derived = ScheduleEngine.deriveState(run, nowMs);

    final previous = _lastDerivedState;
    if (previous != null) {
      final movedToNextRound =
          derived.currentRoundIndex > previous.currentRoundIndex;
      final enteredCooldown =
          previous.state == DerivedPhaseState.runningRound &&
              derived.state == DerivedPhaseState.cooldown;
      final startedAfterCooldown =
          previous.state == DerivedPhaseState.cooldown &&
              derived.state == DerivedPhaseState.runningRound &&
              movedToNextRound;

      // If the app was backgrounded through the entire cooldown, both phase
      // changes arrive in one tick. The configured cooldown still tells us to
      // emit both announcements exactly once.
      final skippedCooldown =
          previous.state == DerivedPhaseState.runningRound &&
              derived.state == DerivedPhaseState.runningRound &&
              movedToNextRound &&
              run.cooldownMs > 0;
      final directRoundChange =
          previous.state == DerivedPhaseState.runningRound &&
              derived.state == DerivedPhaseState.runningRound &&
              movedToNextRound &&
              run.cooldownMs == 0;

      if (enteredCooldown || skippedCooldown) {
        final round = previous.currentRoundIndex;
        _announceRoundEvent(
          roomId: roomId,
          isController: isController,
          title: context.tr(
            '⏱ Round $round Ended',
            '⏱ انتهت الجولة $round',
          ),
          body: run.cooldownMs > 0
              ? context.tr(
                  'Round $round completed. Cooldown started.',
                  'اكتملت الجولة $round. بدأت فترة الراحة.',
                )
              : context.tr(
                  'Round $round completed.',
                  'اكتملت الجولة $round.',
                ),
        );
      }

      if (startedAfterCooldown || skippedCooldown || directRoundChange) {
        final round = derived.currentRoundIndex;
        _announceRoundEvent(
          roomId: roomId,
          isController: isController,
          title: context.tr(
            '▶ Round $round Started',
            '▶ بدأت الجولة $round',
          ),
          body: context.tr(
            'Round $round of ${run.roundCount} has started.',
            'بدأت الجولة $round من ${run.roundCount}.',
          ),
        );
      }
    }

    _lastDerivedState = derived;

    NotificationService().updateOngoingTimerNotification(
      roomId: roomId,
      run: run,
      derivedState: derived,
      isArabic: context.isArabic,
    );
  }

  void _announceRoundEvent({
    required String roomId,
    required bool isController,
    required String title,
    required String body,
  }) {
    // The shared feed listener delivers this notification once to every
    // online device. A second local notification here would duplicate it.
    if (isController) {
      unawaited(ref.read(roomRepositoryProvider).postFeedEvent(
            roomId: roomId,
            title: title,
            body: body,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRoomId = ref.watch(activeRoomIdProvider);
    final activePin = ref.watch(activeRoomPinProvider);
    final userSectorName = ref.watch(userSectorNameProvider);
    ref.watch(firebaseAuthStateProvider);

    // Track active run for the ticker
    ref.listen(activeRunStreamProvider, (prev, next) {
      final run = next.asData?.value;
      final roomId = ref.read(activeRoomIdProvider);

      _lastRun = run;

      if (roomId == null) return;

      if (run == null) {
        // Run ended — cancel the ongoing notification. Keep the forced audio
        // session alive long enough for the boundary alarm to be delivered.
        NotificationService().cancelRoomNotifications(roomId);
        _lastDerivedState = null;
        _scheduledAlarmKey = null;
        return;
      }

      // A new run starts a fresh transition sequence.
      if (prev?.asData?.value?.runId != run.runId) {
        _lastDerivedState = null;
      }

      // Immediately update notification on Firestore change too
      final nowMs = ServerClock().nowMs();
      final derived = ScheduleEngine.deriveState(run, nowMs);
      final alarmKey = [
        run.runId,
        run.status.name,
        for (final phase in run.schedule)
          '${phase.phaseId}:${phase.startsAt}:${phase.endsAt}',
      ].join('|');
      if (_scheduledAlarmKey != alarmKey) {
        _scheduledAlarmKey = alarmKey;
        unawaited(NotificationService().scheduleBoundaryAlarms(
          roomId: roomId,
          run: run,
          soundMode: ref.read(soundModeProvider),
          nowMs: nowMs,
          isArabic: context.isArabic,
        ));
      }
      NotificationService().updateOngoingTimerNotification(
        roomId: roomId,
        run: run,
        derivedState: derived,
        isArabic: context.isArabic,
      );
    });

    ref.listen(feedStreamProvider, (prev, next) {
      final list = next.asData?.value ?? [];
      // On first load, seed seen IDs without triggering notifications
      if (!_feedInitialized) {
        _feedInitialized = true;
        for (final e in list) {
          _seenFeedEventIds.add(e.eventId);
        }
        return;
      }
      final currentUid = ref.read(roomRepositoryProvider).currentUid;
      for (final event in list) {
        if (!_seenFeedEventIds.contains(event.eventId)) {
          _seenFeedEventIds.add(event.eventId);
          if (event.notifyDevices) {
            if (event.targetUid != null) {
              // Targeted notification: only ring/notify the target participant!
              if (currentUid == event.targetUid) {
                NotificationService().showActionNotification(
                  title: event.title,
                  body: event.body,
                );
              }
            } else {
              // Global announcement: notify everyone except sender
              if (currentUid == null || currentUid != event.senderUid) {
                NotificationService().showActionNotification(
                  title: event.title,
                  body: event.body,
                );
              }
            }
          }
        }
      }
    });

    // A Controller can delete a viewer's member document. Keep the viewer's
    // local session in sync and explain why the timer disappeared.
    ref.listen(currentMemberStreamProvider, (prev, next) {
      final wasMember = prev?.asData?.value != null;
      final isMember = next.asData?.value != null;
      final isController = _isController();
      if (!isController && wasMember && !isMember) {
        final roomId = ref.read(activeRoomIdProvider);
        if (roomId == null) return;
        unawaited(_handleViewerRemoved(roomId));
      }
    });

    // Closed rooms and revoked access should return participants home rather
    // than leaving a permanent error/loading screen.
    ref.listen(roomStreamProvider, (prev, next) {
      if (_isController()) return;
      final roomId = ref.read(activeRoomIdProvider);
      final denied =
          next.hasError && next.error.toString().contains('permission-denied');
      if (roomId != null &&
          (denied || next.asData?.value?.state == RoomState.closed)) {
        unawaited(_returnViewerHome(roomId));
      }
    });

    if (activeRoomId == null) {
      if (_presenceRoomId != null) {
        ref.read(presenceServiceProvider).unregisterPresence();
        _presenceRoomId = null;
        _presenceUid = null;
      }
      if (_audioSessionInitialized) {
        _audioSessionInitialized = false;
      }
      return const HomePage();
    }

    // Re-register presence for sessions restored from local storage. Joining
    // used to register this only once, so a restarted participant looked
    // offline even though its Firestore room stream was healthy.
    final uid = ref.read(roomRepositoryProvider).currentUid;
    if (uid != null &&
        (_presenceRoomId != activeRoomId || _presenceUid != uid)) {
      ref.read(presenceServiceProvider).registerPresence(
            roomId: activeRoomId,
            uid: uid,
          );
      _presenceRoomId = activeRoomId;
      _presenceUid = uid;
    }

    // Make the room audible for both Controllers and Participants, including
    // sessions restored after the app was closed.
    if (!_audioSessionInitialized) {
      _audioSessionInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_prepareAudioSession());
      });
      if (activePin == null) {
        unawaited(_refreshParticipantReadiness(activeRoomId));
      }
    }

    final room = ref.watch(roomStreamProvider).asData?.value;
    final isController = room != null
        ? isRoomController(
            ownerUid: room.ownerUid,
            currentUid: ref.read(roomRepositoryProvider).currentUid,
          )
        : activePin != null;

    if (isController) {
      final pages = [
        const ControllerDashboardPage(),
        const AnnouncementsPage(isController: true),
      ];

      return Scaffold(
        appBar: AppBar(
          title: Text(_currentIndex == 0
              ? context.tr('Controller', 'المتحكّم')
              : context.tr('Announcements', 'التنويهات')),
          leading: IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.tr('Settings', 'الإعدادات'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: context.tr('About', 'حول التطبيق'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: context.tr('Exit to home', 'الخروج إلى الرئيسية'),
              onPressed: _exitControllerToHome,
            ),
          ],
        ),
        body: pages[_currentIndex.clamp(0, pages.length - 1)],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex.clamp(0, pages.length - 1),
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard),
              label: context.tr('Controller', 'المتحكّم'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.campaign_outlined),
              selectedIcon: const Icon(Icons.campaign),
              label: context.tr('Announcements', 'التنويهات'),
            ),
          ],
        ),
      );
    } else {
      final pages = [
        const ParticipantTimerPage(),
        const AnnouncementsPage(isController: false),
      ];

      return Scaffold(
        appBar: AppBar(
          title: Text(_currentIndex == 0
              ? '${context.tr('Participant', 'المشارك')} (${userSectorName ?? context.tr('Participant', 'المشارك')})'
              : context.tr('Announcements', 'التنويهات')),
          leading: IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.tr('Settings', 'الإعدادات'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: context.tr('About', 'حول التطبيق'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: context.tr('Leave room', 'مغادرة الغرفة'),
              onPressed: _leaveViewerRoom,
            ),
          ],
        ),
        body: pages[_currentIndex.clamp(0, pages.length - 1)],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex.clamp(0, pages.length - 1),
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.timer_outlined),
              selectedIcon: const Icon(Icons.timer),
              label: context.tr('Timer', 'المؤقت'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.campaign_outlined),
              selectedIcon: const Icon(Icons.campaign),
              label: context.tr('Announcements', 'التنويهات'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _refreshParticipantReadiness(String roomId) async {
    final notifications = await NotificationService().areNotificationsEnabled();
    final exactAlarm =
        await NotificationService().canScheduleExactNotifications();
    await ref.read(roomRepositoryProvider).updateMemberReadiness(
          roomId: roomId,
          notificationReadiness: notifications,
          exactAlarmReadiness: exactAlarm,
        );
  }

  Future<void> _handleViewerRemoved(String roomId) async {
    ref.read(notificationServiceProvider).showActionNotification(
          title: context.tr('Removed from room', 'تمت إزالتك من الغرفة'),
          body: context.tr(
            'The Controller removed this device from the room.',
            'أزال المتحكّم هذا الجهاز من الغرفة.',
          ),
        );
    await RingerService().restoreVolumes();
    ref.read(presenceServiceProvider).unregisterPresence();
    _presenceRoomId = null;
    _presenceUid = null;
    await ref.read(activeRoomIdProvider.notifier).update(null);
    await ref.read(activeRoomPinProvider.notifier).update(null);
    await ref.read(userSectorNameProvider.notifier).update(null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'You were removed from this room.',
              'تمت إزالتك من هذه الغرفة.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _returnViewerHome(String roomId) async {
    if (_returningViewerHome) return;
    _returningViewerHome = true;
    unawaited(
      ref.read(notificationServiceProvider).cancelRoomNotifications(roomId),
    );
    ref.read(presenceServiceProvider).unregisterPresence();
    _presenceRoomId = null;
    _presenceUid = null;
    await RingerService().restoreVolumes();
    await ref.read(activeRoomIdProvider.notifier).update(null);
    await ref.read(activeRoomPinProvider.notifier).update(null);
    await ref.read(userSectorNameProvider.notifier).update(null);
  }

  Future<void> _leaveViewerRoom() async {
    final roomId = ref.read(activeRoomIdProvider);
    if (roomId == null) return;

    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Leave room?', 'هل تريد مغادرة الغرفة؟')),
        content: Text(
          context.tr(
            'This device will stop receiving this room\'s timer and announcements.',
            'سيتوقف هذا الجهاز عن استقبال مؤقت الغرفة وتنويهاتها.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Leave', 'مغادرة')),
          ),
        ],
      ),
    );
    if (leave != true) return;

    await ref.read(roomRepositoryProvider).leaveRoom(roomId);
    ref.read(presenceServiceProvider).unregisterPresence();
    _presenceRoomId = null;
    _presenceUid = null;
    await RingerService().restoreVolumes();
    await ref.read(activeRoomIdProvider.notifier).update(null);
    await ref.read(activeRoomPinProvider.notifier).update(null);
    await ref.read(userSectorNameProvider.notifier).update(null);
  }

  Future<void> _exitControllerToHome() async {
    final roomId = ref.read(activeRoomIdProvider);
    if (roomId == null) return;

    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.tr('Close room and exit?', 'إغلاق الغرفة والخروج؟'),
        ),
        content: Text(
          context.tr(
            'This closes the room for all participants and returns this device to the home page.',
            'سيؤدي ذلك إلى إغلاق الغرفة لجميع المشاركين وإعادة هذا الجهاز إلى الصفحة الرئيسية.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Close and exit', 'إغلاق وخروج')),
          ),
        ],
      ),
    );
    if (exit != true) return;

    // Leave locally first. A slow/offline Firebase write must never trap the
    // controller on a loading screen or make exit look like a reload.
    await ref.read(notificationServiceProvider).cancelRoomNotifications(roomId);
    ref.read(presenceServiceProvider).unregisterPresence();
    _presenceRoomId = null;
    _presenceUid = null;
    await RingerService().restoreVolumes();
    await ref.read(activeRoomIdProvider.notifier).update(null);
    await ref.read(activeRoomPinProvider.notifier).update(null);
    await ref.read(userSectorNameProvider.notifier).update(null);

    // Best effort: close the shared room after the local navigation is done.
    // The direct Firestore fallback still handles projects without Functions.
    unawaited(
      ref.read(roomRepositoryProvider).closeRoom(roomId: roomId).catchError(
            (error, stack) =>
                debugPrint('Background room close failed: $error'),
          ),
    );
  }
}
