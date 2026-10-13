import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../core/localization/app_locale.dart';
import '../../core/models/member_model.dart';
import '../../core/models/room_model.dart';

class SectorCardsWidget extends ConsumerWidget {
  final Room room;
  final List<Member> members;
  final bool isController;

  const SectorCardsWidget({
    super.key,
    required this.room,
    required this.members,
    required this.isController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentUid = ref.watch(currentUidProvider);
    final presenceMap = ref.watch(presenceStreamProvider).asData?.value ?? {};
    final isFirebaseConnected =
        ref.watch(firebaseConnectionProvider).asData?.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'Event Sectors & Participants (${members.length})',
            'قطاعات الفعالية والمشاركون (${members.length})',
          ),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              context.tr(
                'No participant devices have joined yet.',
                'لم تنضم أي أجهزة مشاركين حتى الآن.',
              ),
            ),
          )
        else ...[
          // Group members by sectorName preserving room.sectors order first
          Builder(
            builder: (context) {
              final sectorGroups = <String, List<Member>>{};
              for (final s in room.sectors) {
                sectorGroups[s] = [];
              }
              for (final m in members) {
                sectorGroups.putIfAbsent(m.sectorName, () => []).add(m);
              }

              return Column(
                children: sectorGroups.entries.map((entry) {
                  final sectorName = entry.key;
                  final sectorMembers = entry.value;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.group_work_outlined,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  sectorName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${sectorMembers.length} ${context.tr("joined", "منضم")}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          if (sectorMembers.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(
                                context.tr(
                                  'No participants in this sector yet.',
                                  'لا يوجد مشاركون في هذا القطاع بعد.',
                                ),
                                style: theme.textTheme.bodySmall,
                              ),
                            )
                          else
                            ...sectorMembers.map((member) {
                              final presence = presenceMap[member.uid];
                              final heartbeatOnline = member.lastSeenAt > 0 &&
                                  DateTime.now().millisecondsSinceEpoch -
                                          member.lastSeenAt <
                                      45 * 1000;
                              final isOnline = (presence?.isOnline ?? false) ||
                                  heartbeatOnline ||
                                  (member.uid == currentUid &&
                                      (isFirebaseConnected ?? false));

                              final isSynced = member.uid == room.ownerUid ||
                                  member.acknowledgedRevision >= room.revision;

                              // 4-State Sync Matrix Color Coding:
                              // 1. Green: Synced + Online
                              // 2. Amber/Orange: Synced + Offline (safe, has latest data)
                              // 3. Yellow/Warning: Out of sync + Online (lagging / slow network)
                              // 4. Red: Out of sync + Offline (needs physical notice)
                              final Color badgeBg;
                              final Color badgeText;
                              final String syncLabel = isSynced
                                  ? context.tr('Synced', 'متزامن')
                                  : context.tr('Out of sync', 'غير متزامن');

                              if (isSynced && isOnline) {
                                badgeBg = Colors.green.shade100;
                                badgeText = Colors.green.shade800;
                              } else if (isSynced && !isOnline) {
                                badgeBg = Colors.orange.shade100;
                                badgeText = Colors.orange.shade900;
                              } else if (!isSynced && isOnline) {
                                badgeBg = Colors.amber.shade200;
                                badgeText = Colors.amber.shade900;
                              } else {
                                badgeBg = Colors.red.shade100;
                                badgeText = Colors.red.shade900;
                              }

                              final isMe = member.uid == currentUid;
                              final displayName =
                                  member.participantName.isNotEmpty
                                      ? member.participantName
                                      : member.sectorName;

                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      isOnline
                                          ? Icons.cell_tower
                                          : Icons.signal_cellular_off,
                                      size: 16,
                                      color: isOnline
                                          ? Colors.green
                                          : theme.colorScheme.outline,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        isMe
                                            ? '$displayName (${context.tr("You", "أنت")})'
                                            : displayName,
                                        style: TextStyle(
                                          fontWeight: isMe
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: badgeBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        syncLabel,
                                        style: TextStyle(
                                          color: badgeText,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      member.notificationReadiness
                                          ? Icons.notifications_active
                                          : Icons.notifications_off,
                                      size: 15,
                                      color: member.notificationReadiness
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.error,
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      member.exactAlarmReadiness
                                          ? Icons.alarm_on
                                          : Icons.alarm_off,
                                      size: 15,
                                      color: member.exactAlarmReadiness
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.error,
                                    ),
                                    if (isController &&
                                        member.uid != room.ownerUid) ...[
                                      IconButton(
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.all(4),
                                        icon: const Icon(
                                          Icons.person_remove_outlined,
                                          size: 16,
                                        ),
                                        color: theme.colorScheme.error,
                                        onPressed: () async {
                                          final repo = ref.read(
                                            roomRepositoryProvider,
                                          );
                                          await repo.removeMember(
                                            roomId: room.roomId,
                                            targetUid: member.uid,
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ],
    );
  }
}
