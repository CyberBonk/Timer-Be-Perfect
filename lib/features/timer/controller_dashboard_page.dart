import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../core/firebase/server_clock.dart';
import '../../core/localization/app_locale.dart';
import '../../core/models/room_model.dart';
import '../../core/models/member_model.dart';
import '../../core/models/run_model.dart';
import '../../core/timer/schedule_engine.dart';
import 'timer_display_widget.dart';
import 'sector_cards_widget.dart';
import 'sector_management_card.dart';

class ControllerDashboardPage extends ConsumerStatefulWidget {
  const ControllerDashboardPage({super.key});

  @override
  ConsumerState<ControllerDashboardPage> createState() =>
      _ControllerDashboardPageState();
}

class _ControllerDashboardPageState
    extends ConsumerState<ControllerDashboardPage> {
  int _rounds = 6;
  int _durationMinutes = 20;
  int _cooldownSeconds = 0;
  bool _notifyDevices = true;
  bool _isSubmitting = false;

  Timer? _localTicker;
  int _nowMs = ServerClock().nowMs();

  @override
  void initState() {
    super.initState();
    _localTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) {
        setState(() {
          _nowMs = ServerClock().nowMs();
        });
      }
    });
  }

  @override
  void dispose() {
    _localTicker?.cancel();
    super.dispose();
  }

  Future<int?> _showNumberPickerDialog({
    required BuildContext context,
    required String title,
    required int initialValue,
    required int minValue,
    required int maxValue,
    required String suffix,
    int step = 1,
  }) async {
    int selected = initialValue;
    return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    selected == 0
                        ? context.tr('None (0s)', 'لا شيء (0 ث)')
                        : '$selected $suffix',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.remove),
                      onPressed: selected > minValue
                          ? () => setDialogState(() {
                                selected =
                                    (selected - step).clamp(minValue, maxValue);
                              })
                          : null,
                    ),
                    Expanded(
                      child: Slider(
                        value: selected
                            .toDouble()
                            .clamp(minValue.toDouble(), maxValue.toDouble()),
                        min: minValue.toDouble(),
                        max: maxValue.toDouble(),
                        divisions:
                            max(1, ((maxValue - minValue) / step).round()),
                        label: '$selected $suffix',
                        onChanged: (val) => setDialogState(() {
                          selected = (val / step).round() * step;
                          selected = selected.clamp(minValue, maxValue);
                        }),
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add),
                      onPressed: selected < maxValue
                          ? () => setDialogState(() {
                                selected =
                                    (selected + step).clamp(minValue, maxValue);
                              })
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('Cancel', 'إلغاء')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selected),
                child: Text(context.tr('Set', 'تعيين')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickRounds() async {
    final selected = await _showNumberPickerDialog(
      context: context,
      title: context.tr('Select Number of Rounds', 'اختر عدد الجولات'),
      initialValue: _rounds,
      minValue: 1,
      maxValue: 30,
      suffix: context.tr('rounds', 'جولات'),
    );
    if (selected != null) {
      setState(() => _rounds = selected);
    }
  }

  Future<void> _pickDurationMinutes() async {
    final maxDuration = ref.read(maxRoundDurationProvider);
    final selected = await _showNumberPickerDialog(
      context: context,
      title: context.tr('Select Round Duration', 'اختر مدة الجولة'),
      initialValue: _durationMinutes.clamp(1, maxDuration),
      minValue: 1,
      maxValue: maxDuration,
      suffix: context.tr('mins', 'دقائق'),
    );
    if (selected != null) {
      setState(() => _durationMinutes = selected);
    }
  }

  Future<void> _pickCooldownSeconds() async {
    final maxCooldown = ref.read(maxCooldownSecondsProvider);
    final step = ref.read(cooldownStepSecondsProvider);
    final selected = await _showNumberPickerDialog(
      context: context,
      title: context.tr('Select Cooldown', 'اختر مدة الراحة'),
      initialValue: _cooldownSeconds.clamp(0, maxCooldown),
      minValue: 0,
      maxValue: maxCooldown,
      suffix: context.tr('seconds', 'ثوانٍ'),
      step: step,
    );
    if (selected != null) {
      setState(() => _cooldownSeconds = selected);
    }
  }

  Future<void> _startRun(Room room, List<Member> members) async {
    if (room.sectors.isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            context.tr('Warning', 'تحذير'),
          ),
          content: Text(
            context.tr(
              'Warning: Creating a sectorless session. The event will run in legacy single-tier mode.',
              'تحذير: إنشاء جلسة بدون قطاعات. ستعمل الفعالية في الوضع الفردي التقليدي.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.tr('Add Sectors', 'إضافة قطاعات')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.tr('Proceed', 'متابعة')),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    if (!mounted) return;

    final unreadyMembers = members.where(
      (m) =>
          m.uid != room.ownerUid &&
          (!m.notificationReadiness || !m.exactAlarmReadiness),
    );

    if (unreadyMembers.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            context.tr(
                'Participant Readiness Warning', 'تحذير جاهزية المشاركين'),
          ),
          content: Text(
            context.tr(
              '${unreadyMembers.length} joined participant(s) do not have full notification or exact alarm readiness.\n\nAre you sure you want to start the event run?',
              '${unreadyMembers.length} من المشاركين المنضمين ليست أجهزتهم جاهزة بالكامل للإشعارات أو التنبيهات الدقيقة.\n\nهل تريد بدء الجولات؟',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.tr('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.tr('Start Anyway', 'البدء على أي حال')),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(roomRepositoryProvider);
      await repo.startRun(
        roomId: room.roomId,
        expectedRevision: room.revision,
        roundCount: _rounds,
        standardRoundDurationMinutes: _durationMinutes,
        cooldownSeconds: _cooldownSeconds,
        notifyDevices: _notifyDevices,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.tr('Could not start the event', 'تعذر بدء الفعالية')}: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _sendQuickCommand(Room room, String action,
      {int? adjustmentMinutes}) async {
    final useArabic = context.isArabic;
    // Confirmation required for destructive actions
    if (action == 'end_round' || action == 'end_event') {
      final bool isEndEvent = action == 'end_event';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isEndEvent
              ? context.tr('End Event?', 'هل تريد إنهاء الفعالية؟')
              : context.tr('Skip Round?', 'هل تريد تخطّي الجولة؟')),
          content: Text(
            isEndEvent
                ? context.tr(
                    'This will permanently end the event run for all participants. Are you sure?',
                    'سيؤدي ذلك إلى إنهاء الفعالية لجميع المشاركين. هل أنت متأكد؟',
                  )
                : context.tr(
                    'This will immediately skip the current round. Are you sure?',
                    'سيتم تخطّي الجولة الحالية فورًا. هل أنت متأكد؟',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.tr('Cancel', 'إلغاء')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isEndEvent ? Colors.red : null,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(isEndEvent
                  ? context.tr('End Event', 'إنهاء الفعالية')
                  : context.tr('Skip Round', 'تخطّي الجولة')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final repo = ref.read(roomRepositoryProvider);
      await repo.applyRoomCommand(
        roomId: room.roomId,
        expectedRevision: room.revision,
        action: action,
        adjustmentMinutes: adjustmentMinutes,
        notifyDevices: _notifyDevices,
        isArabic: useArabic,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.tr('Command failed', 'تعذر تنفيذ الأمر')}: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pin = ref.watch(activeRoomPinProvider) ?? '123456';
    final roomAsync = ref.watch(roomStreamProvider);
    final activeRunAsync = ref.watch(activeRunStreamProvider);
    final membersAsync = ref.watch(membersStreamProvider);
    final connectionAsync = ref.watch(firebaseConnectionProvider);

    return roomAsync.when(
      data: (room) {
        if (room == null) {
          return Center(
            child: Text(
              context.tr(
                'Room does not exist or was closed.',
                'الغرفة غير موجودة أو تم إغلاقها.',
              ),
            ),
          );
        }

        final members = membersAsync.asData?.value ?? [];
        final isFirebaseConnected = connectionAsync.asData?.value;
        final activeRun = activeRunAsync.asData?.value;
        final isLocked = activeRun != null &&
            (activeRun.status == RunStatus.running ||
                activeRun.status == RunStatus.paused);

        return SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 12.0,
            bottom: 48.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isFirebaseConnected == false) ...[
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: Icon(
                      Icons.cloud_off,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    title: Text(
                      context.tr('Offline', 'غير متصل'),
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      context.tr(
                        'This Controller is not connected to Firebase. Changes will not sync until the connection returns.',
                        'المتحكّم غير متصل بـ Firebase. لن تُزامن التغييرات حتى عودة الاتصال.',
                      ),
                      style:
                          TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Centered Portrait Header Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final bool isPortrait =
                          MediaQuery.of(context).orientation ==
                              Orientation.portrait;
                      final double qrSize = isPortrait ? 130.0 : 96.0;

                      final qrWidget = Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data:
                              '{"v":1,"type":"be-perfect-room","code":"$pin"}',
                          version: QrVersions.auto,
                          size: qrSize,
                        ),
                      );

                      final detailsWidget = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isPortrait
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('Room PIN Code', 'رمز الغرفة'),
                            textAlign:
                                isPortrait ? TextAlign.center : TextAlign.start,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            child: Text(
                              pin,
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.tr(
                              'Participants joined: ${members.length}',
                              'المشاركون المنضمون: ${members.length}',
                            ),
                            textAlign:
                                isPortrait ? TextAlign.center : TextAlign.start,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );

                      if (isPortrait) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              qrWidget,
                              const SizedBox(height: 14),
                              detailsWidget,
                            ],
                          ),
                        );
                      }

                      return Row(
                        children: [
                          qrWidget,
                          const SizedBox(width: 16),
                          Expanded(child: detailsWidget),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectorManagementCard(
                room: room,
                members: members,
                isLocked: isLocked,
              ),
              const SizedBox(height: 16),

              activeRunAsync.when(
                data: (run) {
                  if (run != null &&
                      (run.status == RunStatus.running ||
                          run.status == RunStatus.paused)) {
                    final derived = ScheduleEngine.deriveState(run, _nowMs);
                    return Column(
                      children: [
                        TimerDisplayWidget(derivedState: derived),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 4 Small Quick Adjustment Buttons always beside each other (-5, -1, +1, +5)
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () => _sendQuickCommand(
                                            room, 'adjust_time',
                                            adjustmentMinutes: -5),
                                        child: const Text('-5m',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () => _sendQuickCommand(
                                            room, 'adjust_time',
                                            adjustmentMinutes: -1),
                                        child: const Text('-1m',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () => _sendQuickCommand(
                                            room, 'adjust_time',
                                            adjustmentMinutes: 1),
                                        child: const Text('+1m',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () => _sendQuickCommand(
                                            room, 'adjust_time',
                                            adjustmentMinutes: 5),
                                        child: const Text('+5m',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Main Action Controls Row (Pause/Resume, Skip, End)
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              run.status == RunStatus.running
                                                  ? theme.colorScheme.tertiary
                                                  : theme.colorScheme.primary,
                                        ),
                                        onPressed: () => _sendQuickCommand(
                                          room,
                                          run.status == RunStatus.running
                                              ? 'pause'
                                              : 'resume',
                                        ),
                                        icon: Icon(
                                            run.status == RunStatus.running
                                                ? Icons.pause
                                                : Icons.play_arrow),
                                        label: Text(
                                          run.status == RunStatus.running
                                              ? context.tr(
                                                  'Pause', 'إيقاف مؤقت')
                                              : context.tr('Resume', 'استئناف'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: OutlinedButton.icon(
                                        onPressed: () => _sendQuickCommand(
                                            room, 'end_round'),
                                        icon: const Icon(Icons.skip_next),
                                        label: Text(
                                          context.tr('Skip', 'تخطي'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filled(
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            theme.colorScheme.error,
                                        foregroundColor:
                                            theme.colorScheme.onError,
                                      ),
                                      onPressed: () =>
                                          _sendQuickCommand(room, 'end_event'),
                                      icon: const Icon(Icons.stop),
                                      tooltip: context.tr(
                                        'End Event',
                                        'إنهاء الفعالية',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  // Native Android Stock Option Selector Cards
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr(
                              'Event Configuration',
                              'إعدادات الفعالية',
                            ),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.repeat,
                                color: theme.colorScheme.primary),
                            title: Text(context.tr('Rounds', 'الجولات')),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                context.tr(
                                  '$_rounds rounds',
                                  '$_rounds جولات',
                                ),
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            onTap: _pickRounds,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.timer_outlined,
                                color: theme.colorScheme.primary),
                            title: Text(
                              context.tr('Round Duration', 'مدة الجولة'),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                context.tr(
                                  '$_durationMinutes mins',
                                  '$_durationMinutes دقيقة',
                                ),
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            onTap: _pickDurationMinutes,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.snooze_outlined,
                                color: theme.colorScheme.primary),
                            title: Text(
                              context.tr('Cooldown', 'فترة الراحة'),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _cooldownSeconds == 0
                                    ? context.tr(
                                        'None (0s)',
                                        'لا شيء (0 ث)',
                                      )
                                    : context.tr(
                                        '${_cooldownSeconds}s',
                                        '$_cooldownSeconds ث',
                                      ),
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            onTap: _pickCooldownSeconds,
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: _notifyDevices,
                            onChanged: (v) =>
                                setState(() => _notifyDevices = v ?? true),
                            title: Text(
                              context.tr('Notify Devices', 'إشعار الأجهزة'),
                            ),
                            subtitle: Text(
                              context.tr(
                                'Send push notifications for start and adjustments',
                                'إرسال إشعارات عند البدء والتعديلات',
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _startRun(room, members),
                              icon: const Icon(Icons.play_arrow, size: 24),
                              label: Text(
                                context.tr(
                                  'Start Event Run',
                                  'بدء جولات الفعالية',
                                ),
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (err, stack) => Text(
                  '${context.tr('Error', 'خطأ')}: $err',
                ),
              ),
              const SizedBox(height: 24),
              SectorCardsWidget(
                room: room,
                members: members,
                isController: true,
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Text(
          '${context.tr('Error loading dashboard', 'تعذر تحميل لوحة التحكم')}: $err',
        ),
      ),
    );
  }
}
