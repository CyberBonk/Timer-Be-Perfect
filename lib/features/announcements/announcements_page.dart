import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../core/localization/app_locale.dart';
import '../../core/models/feed_event_model.dart';
import '../../core/models/member_model.dart';

enum _SystemEventKind { roundStarted, timerAdjusted, other }

String _eventText(FeedEvent event) =>
    '${event.title} ${event.body}'.toLowerCase();

_SystemEventKind _systemEventKind(FeedEvent event) {
  final text = _eventText(event);
  if (text.contains('adjust') || text.contains('تعديل')) {
    return _SystemEventKind.timerAdjusted;
  }
  if (text.contains('round') &&
          (text.contains('started') || text.contains('start')) ||
      text.contains('بدأت الجولة') ||
      text.contains('الجولة التالية')) {
    return _SystemEventKind.roundStarted;
  }
  return _SystemEventKind.other;
}

int? _roundNumber(FeedEvent event) {
  final source = '${event.title} ${event.body}';
  final match = RegExp(
    r'(?:round|الجولة)\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(source);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String? _adjustmentLabel(FeedEvent event) {
  final source = '${event.title} ${event.body}';
  final match = RegExp(r'([+-]\s?\d+)').firstMatch(source);
  return match?.group(1)?.replaceAll(' ', '');
}

String _systemSummary(BuildContext context, FeedEvent event) {
  final text = _eventText(event);
  final round = _roundNumber(event);

  if (_systemEventKind(event) == _SystemEventKind.timerAdjusted) {
    final delta = _adjustmentLabel(event);
    if (delta != null) {
      return context.tr(
        'Controller $delta min',
        'المتحكّم $delta دقيقة',
      );
    }
    return context.tr('Timer adjusted', 'تم تعديل المؤقت');
  }

  if (_systemEventKind(event) == _SystemEventKind.roundStarted) {
    return round == null
        ? context.tr('Next round started', 'بدأت الجولة التالية')
        : context.tr('Round $round started', 'بدأت الجولة $round');
  }

  if (text.contains('skip') || text.contains('تخط')) {
    return round == null
        ? context.tr('Round skipped', 'تم تخطّي الجولة')
        : context.tr('Round $round skipped', 'تم تخطّي الجولة $round');
  }
  if (text.contains('pause') || text.contains('إيقاف')) {
    return context.tr('Timer paused', 'تم إيقاف المؤقت');
  }
  if (text.contains('resume') || text.contains('استئناف')) {
    return context.tr('Timer resumed', 'تم استئناف المؤقت');
  }
  if (text.contains('end') ||
      text.contains('completed') ||
      text.contains('اكتملت')) {
    return round == null
        ? context.tr('Round completed', 'اكتملت الجولة')
        : context.tr('Round $round completed', 'اكتملت الجولة $round');
  }

  return event.title;
}

class _AnnouncementTarget {
  final Member? member;
  final String? sectorName;
  final String label;

  _AnnouncementTarget.member(Member m)
      : member = m,
        sectorName = m.sectorName,
        label = m.participantName.isNotEmpty ? m.participantName : m.sectorName;

  _AnnouncementTarget.sector(String s)
      : member = null,
        sectorName = s,
        label = s;

  String? get targetUid => member?.uid;
  String get targetSectorName => label;
  bool get isMember => member != null;
}

class AnnouncementsPage extends ConsumerStatefulWidget {
  final bool isController;
  const AnnouncementsPage({super.key, this.isController = false});

  @override
  ConsumerState<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends ConsumerState<AnnouncementsPage> {
  final _messageController = TextEditingController();
  bool _notifyDevices = true;
  bool _isSending = false;
  String? _mentionQuery;
  _AnnouncementTarget? _selectedTarget;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos =
        selection.baseOffset >= 0 ? selection.baseOffset : text.length;
    final textBeforeCursor = text.substring(0, cursorPos);
    final lastAt = textBeforeCursor.lastIndexOf('@');

    if (lastAt != -1) {
      final candidate = textBeforeCursor.substring(lastAt + 1);
      if (!candidate.contains(' ')) {
        if (_mentionQuery != candidate) {
          setState(() => _mentionQuery = candidate);
        }
        return;
      }
    }

    if (_mentionQuery != null) {
      setState(() => _mentionQuery = null);
    }

    if (_selectedTarget != null &&
        !text.toLowerCase().contains('@${_selectedTarget!.label.toLowerCase()}')) {
      setState(() => _selectedTarget = null);
    }
  }

  void _insertMentionTrigger() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos =
        selection.baseOffset >= 0 ? selection.baseOffset : text.length;

    final newText =
        '${text.substring(0, cursorPos)}@${text.substring(cursorPos)}';
    final newCursor = cursorPos + 1;

    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    setState(() => _mentionQuery = '');
  }

  void _selectMentionSector(String sector) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos =
        selection.baseOffset >= 0 ? selection.baseOffset : text.length;
    final textBeforeCursor = text.substring(0, cursorPos);
    final lastAt = textBeforeCursor.lastIndexOf('@');
    final afterCursor = text.substring(cursorPos);

    String newText;
    int newCursor;
    if (lastAt != -1) {
      newText = '${text.substring(0, lastAt)}@$sector $afterCursor';
      newCursor = lastAt + sector.length + 2;
    } else {
      if (text.isEmpty) {
        newText = '@$sector ';
      } else {
        newText = '@$sector $text';
      }
      newCursor = sector.length + 2;
    }

    setState(() {
      _selectedTarget = _AnnouncementTarget.sector(sector);
      _mentionQuery = null;
    });

    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  void _selectMentionMember(Member member) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos =
        selection.baseOffset >= 0 ? selection.baseOffset : text.length;
    final textBeforeCursor = text.substring(0, cursorPos);
    final lastAt = textBeforeCursor.lastIndexOf('@');
    final afterCursor = text.substring(cursorPos);

    final insertName = member.participantName.isNotEmpty
        ? member.participantName
        : member.sectorName;

    String newText;
    int newCursor;
    if (lastAt != -1) {
      newText = '${text.substring(0, lastAt)}@$insertName $afterCursor';
      newCursor = lastAt + insertName.length + 2;
    } else {
      if (text.isEmpty) {
        newText = '@$insertName ';
      } else {
        newText = '@$insertName $text';
      }
      newCursor = insertName.length + 2;
    }

    setState(() {
      _selectedTarget = _AnnouncementTarget.member(member);
      _mentionQuery = null;
    });

    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  Future<void> _sendAnnouncement() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || text.length > 500) return;

    final roomId = ref.read(activeRoomIdProvider);
    if (roomId == null) return;
    final sectorName = ref.read(userSectorNameProvider);
    final members = ref.read(membersStreamProvider).asData?.value ?? [];
    final currentUid = ref.read(roomRepositoryProvider).currentUid;
    final room = ref.read(roomStreamProvider).asData?.value;

    String? targetUid = _selectedTarget?.targetUid;
    String? targetSectorName = _selectedTarget?.targetSectorName;

    // If target was not chosen via tap, auto-resolve by matching @Name in text
    if (targetUid == null && targetSectorName == null) {
      final textLower = text.toLowerCase();
      final roomSectors = room?.sectors ?? <String>[];
      final memberSectors =
          members.map((m) => m.sectorName).where((s) => s.isNotEmpty);
      final allSectors = {...roomSectors, ...memberSectors};

      // 1. Check sectors first (primary)
      for (final s in allSectors) {
        if (s.isNotEmpty && textLower.contains('@${s.toLowerCase()}')) {
          targetSectorName = s;
          break;
        }
      }

      // 2. Check participant names next (bonus)
      if (targetSectorName == null) {
        for (final m in members) {
          if (m.uid != currentUid && m.participantName.isNotEmpty) {
            if (textLower.contains('@${m.participantName.toLowerCase()}')) {
              targetUid = m.uid;
              targetSectorName = m.participantName;
              break;
            }
          }
        }
      }
    }

    setState(() => _isSending = true);

    try {
      final repo = ref.read(roomRepositoryProvider);
      final title = targetSectorName != null
          ? context.tr(
              'To @$targetSectorName',
              'إلى @$targetSectorName',
            )
          : (widget.isController
              ? context.tr('Announcement', 'تنويه')
              : context.tr(
                  'Message from ${sectorName ?? 'Participant'}',
                  'رسالة من ${sectorName ?? 'مشارك'}',
                ));

      await repo.sendAnnouncement(
        roomId: roomId,
        body: text,
        title: title,
        notifyDevices: _notifyDevices,
        targetUid: targetUid,
        targetSectorName: targetSectorName,
      );
      _messageController.clear();
      setState(() {
        _selectedTarget = null;
        _mentionQuery = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(e.toString().replaceAll(RegExp(r'\[.*?\]'), '').trim()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feedAsync = ref.watch(feedStreamProvider);
    final membersAsync = ref.watch(membersStreamProvider);
    final currentUid = ref.watch(currentUidProvider);
    final roomAsync = ref.watch(roomStreamProvider);
    final userSectorName = ref.watch(userSectorNameProvider);
    final room = roomAsync.asData?.value;
    final allMembers = membersAsync.asData?.value ?? [];
    final eligibleMembers =
        allMembers.where((m) => m.uid != currentUid).toList();

    final roomSectors = room?.sectors ?? <String>[];
    final memberSectors =
        eligibleMembers.map((m) => m.sectorName).where((s) => s.isNotEmpty);
    final allSectors = {...roomSectors, ...memberSectors}.toList();

    List<String> matchingSectors = [];
    List<Member> matchingMembers = [];

    if (_mentionQuery != null) {
      final q = _mentionQuery!.trim().toLowerCase();
      if (q.isEmpty) {
        matchingSectors = allSectors.take(6).toList();
        matchingMembers = eligibleMembers
            .where((m) =>
                m.participantName.toLowerCase() != m.sectorName.toLowerCase())
            .take(6)
            .toList();
      } else {
        // Sectors (Primary)
        final startsWithSectors =
            allSectors.where((s) => s.toLowerCase().startsWith(q)).toList();
        final containsSectors = allSectors
            .where((s) =>
                !s.toLowerCase().startsWith(q) && s.toLowerCase().contains(q))
            .toList();
        matchingSectors =
            [...startsWithSectors, ...containsSectors].take(6).toList();

        // Participants (Bonus)
        final startsWithMembers = eligibleMembers
            .where((m) =>
                m.participantName.toLowerCase().startsWith(q) ||
                (m.participantName.toLowerCase() != m.sectorName.toLowerCase() &&
                    m.sectorName.toLowerCase().startsWith(q)))
            .toList();
        final containsMembers = eligibleMembers
            .where((m) =>
                !startsWithMembers.contains(m) &&
                (m.participantName.toLowerCase().contains(q) ||
                    (m.participantName.toLowerCase() !=
                            m.sectorName.toLowerCase() &&
                        m.sectorName.toLowerCase().contains(q))))
            .toList();
        matchingMembers =
            [...startsWithMembers, ...containsMembers].take(6).toList();
      }
    }

    return Column(
      children: [
        Expanded(
          child: feedAsync.when(
            data: (events) {
              if (events.isEmpty) {
                return Center(
                  child: Text(
                    context.tr(
                      'No announcements yet.',
                      'لا توجد تنويهات حتى الآن.',
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  final timeStr = DateFormat('hh:mm a').format(
                    DateTime.fromMillisecondsSinceEpoch(event.timestamp),
                  );
                  final isAnnouncement =
                      event.type == FeedEventType.announcement;
                  final systemKind = _systemEventKind(event);

                  if (isAnnouncement || event.title.contains('Event Ended')) {
                    final currentUid = ref.watch(currentUidProvider);
                    final isTargetedToMe = (event.targetUid != null &&
                            event.targetUid == currentUid) ||
                        (event.targetUid == null &&
                            event.targetSectorName != null &&
                            userSectorName != null &&
                            event.targetSectorName!.toLowerCase() ==
                                userSectorName.toLowerCase());
                    final isTargeted = event.targetSectorName != null;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: isTargetedToMe
                          ? theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.85)
                          : (isAnnouncement
                              ? theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.5)
                              : theme.colorScheme.secondaryContainer
                                  .withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isTargetedToMe
                            ? BorderSide(
                                color: theme.colorScheme.primary,
                                width: 2,
                              )
                            : (isTargeted
                                ? BorderSide(
                                    color: theme.colorScheme.tertiary
                                        .withValues(alpha: 0.35),
                                    width: 1,
                                  )
                                : BorderSide.none),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isTargetedToMe
                                      ? Icons.alternate_email_rounded
                                      : (isAnnouncement
                                          ? Icons.campaign
                                          : Icons.notifications_active),
                                  size: 18,
                                  color: isTargetedToMe
                                      ? theme.colorScheme.primary
                                      : (isAnnouncement
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.secondary),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          event.title,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: isAnnouncement
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.secondary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (event.targetSectorName != null) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isTargetedToMe
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme
                                                    .tertiaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            isTargetedToMe
                                                ? context.tr('@You', '@أنت')
                                                : '@${event.targetSectorName}',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: isTargetedToMe
                                                  ? theme.colorScheme.onPrimary
                                                  : theme.colorScheme
                                                      .onTertiaryContainer,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Text(
                                  timeStr,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (event.body.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                event.body,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  if (systemKind == _SystemEventKind.roundStarted) {
                    final accent = theme.colorScheme.primary;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.72,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.skip_next_rounded,
                              size: 20,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr(
                                    'Next round',
                                    'الجولة التالية',
                                  ),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _systemSummary(context, event),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeStr,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(
                      left: 4,
                      right: 4,
                      bottom: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 7,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _systemSummary(context, event),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(
              child: Text(
                '${context.tr('Error loading announcements', 'تعذر تحميل التنويهات')}: $err',
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_mentionQuery != null &&
                  (matchingSectors.isNotEmpty || matchingMembers.isNotEmpty)) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.6),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.alternate_email_rounded,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            context.tr(
                              'Mention sector or participant',
                              'إشارة إلى قطاع أو مشارك',
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 38,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              matchingSectors.length + matchingMembers.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            if (index < matchingSectors.length) {
                              final sector = matchingSectors[index];
                              return ActionChip(
                                avatar: CircleAvatar(
                                  radius: 11,
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.groups_rounded,
                                    size: 13,
                                    color:
                                        theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                label: Text(
                                  '@$sector',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: theme.colorScheme.surface,
                                side: BorderSide(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.35),
                                ),
                                onPressed: () => _selectMentionSector(sector),
                              );
                            }
                            final member =
                                matchingMembers[index - matchingSectors.length];
                            final hasDistinctSector = member
                                    .sectorName.isNotEmpty &&
                                member.sectorName.toLowerCase() !=
                                    member.participantName.toLowerCase();
                            final chipLabel = hasDistinctSector
                                ? '@${member.participantName} (${member.sectorName})'
                                : '@${member.participantName}';
                            return ActionChip(
                              avatar: CircleAvatar(
                                radius: 11,
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                                child: Text(
                                  member.participantName.isNotEmpty
                                      ? member.participantName[0].toUpperCase()
                                      : '?',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                              label: Text(
                                chipLabel,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: theme.colorScheme.surface,
                              side: BorderSide(
                                color: theme.colorScheme.secondary
                                    .withValues(alpha: 0.35),
                              ),
                              onPressed: () => _selectMentionMember(member),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_mentionQuery != null &&
                  matchingSectors.isEmpty &&
                  matchingMembers.isEmpty &&
                  _mentionQuery!.isNotEmpty) ...[
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                  child: Text(
                    context.tr(
                      'No participants match "@$_mentionQuery"',
                      'لا يوجد مشاركون يطابقون "@$_mentionQuery"',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
              if (_selectedTarget != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InputChip(
                    avatar: CircleAvatar(
                      radius: 10,
                      backgroundColor: theme.colorScheme.primary,
                      child: Icon(
                        Icons.alternate_email_rounded,
                        size: 12,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                    label: Text(
                      context.tr(
                        'Targeting @${_selectedTarget!.label} (Exclusive sound alert)',
                        'موجه إلى @${_selectedTarget!.label} (تنبيه صوتي حصري)',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () {
                      setState(() => _selectedTarget = null);
                    },
                  ),
                ),
              ],
              if (widget.isController)
                Row(
                  children: [
                    Checkbox(
                      value: _notifyDevices,
                      onChanged: (v) =>
                          setState(() => _notifyDevices = v ?? true),
                    ),
                    Text(context.tr('Notify Devices', 'إشعار الأجهزة')),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLength: 500,
                      decoration: InputDecoration(
                        prefixIcon: IconButton(
                          tooltip: context.tr(
                            'Mention participant (@)',
                            'إشارة لمشارك (@)',
                          ),
                          icon: Icon(
                            Icons.alternate_email_rounded,
                            color: _mentionQuery != null ||
                                    _selectedTarget != null
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                          onPressed: _insertMentionTrigger,
                        ),
                        hintText: widget.isController
                            ? context.tr(
                                'Type announcement...',
                                'اكتب تنويهًا...',
                              )
                            : context.tr(
                                'Send a message to the room...',
                                'أرسل رسالة إلى الغرفة...',
                              ),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendAnnouncement,
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
