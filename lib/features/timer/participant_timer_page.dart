import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../core/firebase/server_clock.dart';
import '../../core/localization/app_locale.dart';
import '../../core/models/room_model.dart';
import '../../core/notifications/ringer_service.dart';
import '../../core/timer/schedule_engine.dart';

import 'timer_display_widget.dart';
import 'sector_cards_widget.dart';

class ParticipantTimerPage extends ConsumerStatefulWidget {
  const ParticipantTimerPage({super.key});

  @override
  ConsumerState<ParticipantTimerPage> createState() =>
      _ParticipantTimerPageState();
}

class _ParticipantTimerPageState extends ConsumerState<ParticipantTimerPage> {
  Timer? _localTicker;
  int _nowMs = ServerClock().nowMs();
  TimerDerivedState? _lastDerivedState;
  int? _activeAlarmRound;
  String? _checkedActiveAlarmRunId;
  bool _isAudible = true;
  int _audioCheckCounter = 0;

  @override
  void initState() {
    super.initState();
    _checkAudioReadiness();
    // Repaint more frequently than once per second so both devices cross a
    // shared server-timestamp boundary without a whole-second visual lag.
    _localTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;

      final nowMs = ServerClock().nowMs();
      final run = ref.read(activeRunStreamProvider).asData?.value;
      int? endedRound;

      if (run != null) {
        final derived = ScheduleEngine.deriveState(run, nowMs);
        final previous = _lastDerivedState;
        if (previous?.state == DerivedPhaseState.runningRound &&
            (derived.state != DerivedPhaseState.runningRound ||
                derived.currentRoundIndex > previous!.currentRoundIndex)) {
          endedRound = previous!.currentRoundIndex;
        }
        _lastDerivedState = derived;
      } else {
        _lastDerivedState = null;
        _activeAlarmRound = null;
        _checkedActiveAlarmRunId = null;
      }

      _audioCheckCounter++;
      if (_audioCheckCounter % 8 == 0) {
        _checkAudioReadiness();
      }

      setState(() {
        _nowMs = nowMs;
        if (endedRound != null) _activeAlarmRound = endedRound;
      });
    });
  }

  Future<void> _checkAudioReadiness() async {
    final audible = await RingerService().isSoundModeAudible();
    if (mounted && _isAudible != audible) {
      setState(() => _isAudible = audible);
    }
  }

  Future<void> _enableSoundAndMaxVolume() async {
    await RingerService().forceSoundMode();
    await _checkAudioReadiness();
  }

  @override
  void dispose() {
    _localTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roomAsync = ref.watch(roomStreamProvider);
    final activeRunAsync = ref.watch(activeRunStreamProvider);
    final connectionAsync = ref.watch(firebaseConnectionProvider);
    final memberAsync = ref.watch(currentMemberStreamProvider);
    final membersAsync = ref.watch(membersStreamProvider);

    ref.listen(roomStreamProvider, (prev, next) {
      final room = next.asData?.value;
      if (room != null) {
        final currentMember =
            ref.read(currentMemberStreamProvider).asData?.value;
        if (currentMember != null &&
            currentMember.acknowledgedRevision < room.revision) {
          unawaited(ref.read(roomRepositoryProvider).acknowledgeRevision(
                roomId: room.roomId,
                revision: room.revision,
              ));
        }
      }
    });

    ref.listen(currentMemberStreamProvider, (prev, next) {
      final currentMember = next.asData?.value;
      final room = ref.read(roomStreamProvider).asData?.value;
      if (room != null &&
          currentMember != null &&
          currentMember.acknowledgedRevision < room.revision) {
        unawaited(ref.read(roomRepositoryProvider).acknowledgeRevision(
              roomId: room.roomId,
              revision: room.revision,
            ));
      }
    });
    return roomAsync.when(
      data: (room) {
        if (room == null) {
          return Center(
            child: Text(
              context.tr(
                'Room closed or not found.',
                'الغرفة مغلقة أو غير موجودة.',
              ),
            ),
          );
        }

        if (room.state == RoomState.closed) {
          return Center(
            child: Text(
              context.tr(
                'This room has been closed by the Controller.',
                'أغلق المتحكّم هذه الغرفة.',
              ),
            ),
          );
        }

        final heartbeatFresh = (() {
          final seen = memberAsync.asData?.value?.lastSeenAt ?? 0;
          return seen > 0 &&
              DateTime.now().millisecondsSinceEpoch - seen < 45 * 1000;
        })();
        final isConnected =
            connectionAsync.asData?.value == true || heartbeatFresh;
        final isOffline =
            connectionAsync.asData?.value == false || connectionAsync.hasError;

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: isOffline
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  Icon(
                    isConnected
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    size: 16,
                    color: isOffline
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isConnected
                          ? context.tr(
                              'Connected — Live sync active (Rev ${room.revision})',
                              'متصل — المزامنة المباشرة فعّالة (رقم المراجعة ${room.revision})',
                            )
                          : context.tr(
                              'Offline — Live sync unavailable. Changes will not sync until connection returns.',
                              'غير متصل — المزامنة المباشرة غير متاحة. لن تُزامن التغييرات حتى عودة الاتصال.',
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isOffline
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight:
                            isOffline ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_isAudible)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                color: theme.colorScheme.errorContainer,
                child: Row(
                  children: [
                    Icon(
                      Icons.volume_off,
                      size: 16,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr(
                          'Device sound is low or muted.',
                          'صوت الجهاز منخفض أو مكتوم.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: _enableSoundAndMaxVolume,
                      child: Text(
                        context.tr('Max Volume', 'أقصى صوت'),
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: activeRunAsync.when(
                    data: (run) {
                      if (run == null) {
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.hourglass_empty,
                              size: 64,
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.tr(
                                'Waiting for Controller to start run...',
                                'في انتظار المتحكّم لبدء الجولات...',
                              ),
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 24),
                            membersAsync.when(
                              data: (members) => SectorCardsWidget(
                                room: room,
                                members: members,
                                isController: false,
                              ),
                              loading: () => const CircularProgressIndicator(),
                              error: (err, _) => const SizedBox.shrink(),
                            ),
                          ],
                        );
                      }

                      final derivedState =
                          ScheduleEngine.deriveState(run, _nowMs);

                      if (_checkedActiveAlarmRunId != run.runId) {
                        _checkedActiveAlarmRunId = run.runId;
                        Future.microtask(() async {
                          final activeRound = await ref
                              .read(notificationServiceProvider)
                              .findActiveRoundAlarm(
                                room.roomId,
                                run.roundCount,
                              );
                          if (mounted && activeRound != null) {
                            setState(() => _activeAlarmRound = activeRound);
                          }
                        });
                      }

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TimerDisplayWidget(
                            derivedState: derivedState,
                            isOffline: isOffline,
                          ),
                          if (_activeAlarmRound != null) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () async {
                                final round = _activeAlarmRound!;
                                await ref
                                    .read(notificationServiceProvider)
                                    .dismissRoundAlarm(room.roomId, round);
                                if (mounted) {
                                  setState(() => _activeAlarmRound = null);
                                }
                              },
                              icon: const Icon(Icons.alarm_off),
                              label: Text(
                                context.tr(
                                  'Dismiss Round $_activeAlarmRound Alarm',
                                  'إيقاف تنبيه الجولة $_activeAlarmRound',
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          membersAsync.when(
                            data: (members) => SectorCardsWidget(
                              room: room,
                              members: members,
                              isController: false,
                            ),
                            loading: () => const CircularProgressIndicator(),
                            error: (err, _) => const SizedBox.shrink(),
                          ),
                        ],
                      );
                    },
                    loading: () => const CircularProgressIndicator(),
                    error: (err, stack) => Text(
                      '${context.tr('Error loading run', 'تعذر تحميل الجولات')}: $err',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Text(
          '${context.tr('Error loading room', 'تعذر تحميل الغرفة')}: $err',
        ),
      ),
    );
  }
}
