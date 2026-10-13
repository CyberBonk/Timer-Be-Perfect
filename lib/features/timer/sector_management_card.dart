import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../core/localization/app_locale.dart';
import '../../core/models/member_model.dart';
import '../../core/models/room_model.dart';

class SectorManagementCard extends ConsumerWidget {
  final Room room;
  final List<Member> members;
  final bool isLocked;

  const SectorManagementCard({
    super.key,
    required this.room,
    required this.members,
    required this.isLocked,
  });

  Future<void> _showAddSectorDialog(BuildContext context, WidgetRef ref) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogStateContext, setDialogState) {
          return AlertDialog(
            title: Text(context.tr('Add Sector', 'إضافة قطاع')),
            content: TextField(
              key: const ValueKey('sector-name-input'),
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.tr('Sector Name', 'اسم القطاع'),
                hintText: context.tr(
                  'e.g. قطاع 1, المسرح, الصوت',
                  'مثال: قطاع 1، المسرح، الصوت',
                ),
                errorText: errorText,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (errorText != null) {
                  setDialogState(() => errorText = null);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.tr('Cancel', 'إلغاء')),
              ),
              FilledButton(
                key: const ValueKey('submit-add-sector-button'),
                onPressed: () async {
                  final name = controller.text.trim();
                  if (name.isEmpty) {
                    setDialogState(() {
                      errorText = context.tr(
                        'Sector name cannot be empty',
                        'لا يمكن أن يكون اسم القطاع فارغاً',
                      );
                    });
                    return;
                  }
                  if (room.sectors.any((s) => s.toLowerCase() == name.toLowerCase())) {
                    setDialogState(() {
                      errorText = context.tr(
                        'Sector already exists',
                        'القطاع موجود بالفعل',
                      );
                    });
                    return;
                  }
                  final addErrorPrefix = context.tr(
                    'Error adding sector',
                    'خطأ في إضافة القطاع',
                  );
                  Navigator.of(dialogContext).pop();
                  try {
                    final updated = [...room.sectors, name];
                    await ref
                        .read(roomRepositoryProvider)
                        .updateRoomSectors(room.roomId, updated);
                  } catch (e) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('$addErrorPrefix: $e'),
                      ),
                    );
                  }
                },
                child: Text(context.tr('Add', 'إضافة')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showRenameSectorDialog(
    BuildContext context,
    WidgetRef ref,
    String oldSector,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: oldSector);
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogStateContext, setDialogState) {
          return AlertDialog(
            title: Text(context.tr('Rename Sector', 'إعادة تسمية القطاع')),
            content: TextField(
              key: const ValueKey('rename-sector-input'),
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.tr('Sector Name', 'اسم القطاع'),
                errorText: errorText,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (errorText != null) {
                  setDialogState(() => errorText = null);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.tr('Cancel', 'إلغاء')),
              ),
              FilledButton(
                key: const ValueKey('submit-rename-sector-button'),
                onPressed: () async {
                  final newName = controller.text.trim();
                  if (newName.isEmpty) {
                    setDialogState(() {
                      errorText = context.tr(
                        'Sector name cannot be empty',
                        'لا يمكن أن يكون اسم القطاع فارغاً',
                      );
                    });
                    return;
                  }
                  if (newName == oldSector) {
                    Navigator.of(dialogContext).pop();
                    return;
                  }
                  if (room.sectors.any((s) =>
                      s.toLowerCase() != oldSector.toLowerCase() &&
                      s.toLowerCase() == newName.toLowerCase())) {
                    setDialogState(() {
                      errorText = context.tr(
                        'Sector already exists',
                        'القطاع موجود بالفعل',
                      );
                    });
                    return;
                  }
                  final renameErrorPrefix = context.tr(
                    'Error renaming sector',
                    'خطأ في إعادة تسمية القطاع',
                  );
                  Navigator.of(dialogContext).pop();
                  try {
                    final updated = room.sectors
                        .map((s) => s == oldSector ? newName : s)
                        .toList();
                    await ref
                        .read(roomRepositoryProvider)
                        .updateRoomSectors(room.roomId, updated);
                  } catch (e) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('$renameErrorPrefix: $e'),
                      ),
                    );
                  }
                },
                child: Text(context.tr('Save', 'حفظ')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteSector(
    BuildContext context,
    WidgetRef ref,
    String sector,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final deleteErrorPrefix = context.tr(
      'Error deleting sector',
      'خطأ في حذف القطاع',
    );
    final sectorMembers = members
        .where((m) =>
            m.sectorName.trim().toLowerCase() == sector.trim().toLowerCase() ||
            m.normalizedSectorName == sector.trim().toLowerCase())
        .toList();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Delete Sector', 'حذف القطاع')),
        content: Text(
          sectorMembers.isNotEmpty
              ? context.tr(
                  'Warning: Sector "$sector" currently has ${sectorMembers.length} joined participant(s). Deleting this sector will not remove the participants, but they will belong to an unconfigured sector.\n\nAre you sure you want to delete this sector?',
                  'تحذير: القطاع "$sector" يحتوي حالياً على ${sectorMembers.length} من المشاركين المنضمين. حذف هذا القطاع لن يزيل المشاركين لكنهم سينتمون إلى قطاع غير مسجل.\n\nهل أنت متأكد من حذف هذا القطاع؟',
                )
              : context.tr(
                  'Are you sure you want to delete sector "$sector"?',
                  'هل أنت متأكد من حذف قطاع "$sector"؟',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('Cancel', 'إلغاء')),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-sector-button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('Delete', 'حذف')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final updated = room.sectors.where((s) => s != sector).toList();
        await ref
            .read(roomRepositoryProvider)
            .updateRoomSectors(room.roomId, updated);
      } catch (e) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('$deleteErrorPrefix: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      key: const ValueKey('sector-management-card'),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(
                      'Sector Management',
                      'إدارة القطاعات',
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!isLocked)
                  FilledButton.tonalIcon(
                    key: const ValueKey('add-sector-button'),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.tr('Add Sector', 'إضافة قطاع')),
                    onPressed: () => _showAddSectorDialog(context, ref),
                  ),
              ],
            ),
            if (isLocked) ...[
              const SizedBox(height: 10),
              Container(
                key: const ValueKey('sectors-locked-indicator'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr(
                          'Sectors cannot be modified during an active event',
                          'لا يمكن تعديل القطاعات أثناء فعالية نشطة',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (room.sectors.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  context.tr(
                    'No sectors configured yet. Add sectors for participant registration.',
                    'لم يتم إعداد أي قطاعات بعد. أضف قطاعات لتسجيل المشاركين.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: room.sectors.map((sector) {
                  return InputChip(
                    key: ValueKey('sector-chip-$sector'),
                    label: Text(sector),
                    tooltip: isLocked
                        ? null
                        : context.tr(
                            'Tap to rename, X to delete',
                            'اضغط لإعادة التسمية، X للحذف',
                          ),
                    onPressed: isLocked
                        ? null
                        : () =>
                            _showRenameSectorDialog(context, ref, sector),
                    onDeleted: isLocked
                        ? null
                        : () =>
                            _confirmDeleteSector(context, ref, sector),
                    deleteIcon:
                        isLocked ? null : const Icon(Icons.close, size: 16),
                    deleteButtonTooltipMessage: isLocked
                        ? null
                        : context.tr('Delete sector', 'حذف القطاع'),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
