import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/firebase/firebase_providers.dart';
import '../../core/localization/app_locale.dart';
import '../../core/models/sound_mode.dart';
import '../../core/notifications/ringer_service.dart';
import '../../core/theme/app_theme.dart';
import 'about_page.dart';
import 'developer_info_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Future<void> _openAndroidSettings({required bool exactAlarm}) async {
    if (!Platform.isAndroid) return;

    final info = await PackageInfo.fromPlatform();
    final packageName = info.packageName;
    final intent = AndroidIntent(
      action: exactAlarm
          ? 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM'
          : 'android.settings.APP_NOTIFICATION_SETTINGS',
      data: exactAlarm ? 'package:$packageName' : null,
      arguments: exactAlarm
          ? null
          : <String, dynamic>{
              'android.provider.extra.APP_PACKAGE': packageName,
            },
    );

    try {
      await intent.launch();
    } catch (_) {
      await AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$packageName',
      ).launch();
    }
  }

  Future<void> _testSound(SoundMode soundMode) async {
    await ref.read(notificationServiceProvider).testRoundAlarm(
          soundMode: soundMode,
          isArabic: context.isArabic,
        );
  }

  Future<void> _maximizeVolume() async {
    await RingerService().forceSoundMode();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Sound mode enabled and volume set to maximum.',
              'تم تفعيل وضع الصوت وضبط مستوى الصوت على الحد الأقصى.',
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openDndSettings() async {
    await RingerService().openDndSettings();
  }

  Future<void> _selectLanguage(String? languageCode) async {
    if (languageCode == null) return;
    await ref.read(appLocaleProvider.notifier).setLanguage(languageCode);
  }

  String _soundLabel(SoundMode mode) => switch (mode) {
        SoundMode.bePerfectSound =>
          context.tr('Be Perfect sound', 'صوت Be Perfect'),
        SoundMode.deviceDefault =>
          context.tr('Device default', 'الصوت الافتراضي للجهاز'),
        SoundMode.vibrationOnly => context.tr('Vibration only', 'اهتزاز فقط'),
      };

  String _soundDescription(SoundMode mode) => switch (mode) {
        SoundMode.bePerfectSound => context.tr(
            'Bundled sound plus vibration',
            'الصوت المرفق مع الاهتزاز',
          ),
        SoundMode.deviceDefault => context.tr(
            'Default notification/alarm sound plus vibration',
            'صوت التنبيه الافتراضي مع الاهتزاز',
          ),
        SoundMode.vibrationOnly => context.tr(
            'Vibration without audio',
            'اهتزاز من دون صوت',
          ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedSoundMode = ref.watch(soundModeProvider);
    final selectedThemeSeed = ref.watch(themeSeedColorProvider);
    final locale = ref.watch(appLocaleProvider);
    final roomId = ref.watch(activeRoomIdProvider);
    final isController = ref.watch(activeRoomPinProvider) != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Settings', 'الإعدادات')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Theme Color Picker (Derived from Beacon reference)
          Text(
            context.tr('App Color Scheme', 'ألوان التطبيق'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: AppTheme.seeds.map((seedOption) {
                  final isSelected = seedOption.color.toARGB32() ==
                      selectedThemeSeed.toARGB32();
                  return Expanded(
                    child: Tooltip(
                      message: seedOption.name,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => ref
                            .read(themeSeedColorProvider.notifier)
                            .update(seedOption.color),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: seedOption.color,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(context.tr('Language', 'اللغة')),
              trailing: DropdownButton<String>(
                value: locale.languageCode,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(
                    value: 'en',
                    child: Text('English'),
                  ),
                  DropdownMenuItem(
                    value: 'ar',
                    child: Text('العربية'),
                  ),
                ],
                onChanged: _selectLanguage,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sound & Alarm Settings
          Text(
            context.tr('Sound & Alarm Settings', 'إعدادات الصوت والتنبيه'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: SoundMode.values.map((mode) {
                final isSelected = mode == selectedSoundMode;
                return ListTile(
                  leading: Radio<SoundMode>(
                    value: mode,
                    // ignore: deprecated_member_use
                    groupValue: selectedSoundMode,
                    // ignore: deprecated_member_use
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(soundModeProvider.notifier).update(val);
                        if (roomId != null) {
                          ref
                              .read(roomRepositoryProvider)
                              .updateMemberReadiness(
                                roomId: roomId,
                                selectedSoundMode: val,
                              );
                        }
                      }
                    },
                  ),
                  title: Text(_soundLabel(mode)),
                  subtitle: Text(_soundDescription(mode)),
                  selected: isSelected,
                  onTap: () {
                    ref.read(soundModeProvider.notifier).update(mode);
                    if (roomId != null) {
                      ref.read(roomRepositoryProvider).updateMemberReadiness(
                            roomId: roomId,
                            selectedSoundMode: mode,
                          );
                    }
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _testSound(selectedSoundMode),
                  icon: const Icon(Icons.volume_up),
                  label: Text(
                    context.tr('Test Sound', 'تجربة الصوت'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _maximizeVolume,
                  icon: const Icon(Icons.volume_up_outlined),
                  label: Text(
                    context.tr('Max Volume', 'أقصى صوت'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            context.tr(
              'Android Permissions & Readiness',
              'أذونات Android والاستعداد',
            ),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(
                    context.tr(
                      'Notification Channel Settings',
                      'إعدادات قناة الإشعارات',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      'Inspect or configure Android notification permissions',
                      'مراجعة أذونات إشعارات Android أو ضبطها',
                    ),
                  ),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: () => _openAndroidSettings(exactAlarm: false),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.alarm_outlined),
                  title: Text(
                    context.tr('Exact Alarm Access', 'إذن التنبيهات الدقيقة'),
                  ),
                  subtitle: Text(
                    context.tr(
                      'Allow exact round completion alarm triggers',
                      'السماح بتنبيهات دقيقة عند انتهاء الجولات',
                    ),
                  ),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: () => _openAndroidSettings(exactAlarm: true),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.do_not_disturb_on_outlined),
                  title: Text(
                    context.tr(
                      'Do Not Disturb Access',
                      'إذن تجاوز عدم الإزعاج',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      'Allow auto-enabling sound mode & max volume on OEM skins',
                      'السماح بضبط وضع الصوت والحد الأقصى تلقائيًا',
                    ),
                  ),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: _openDndSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_pin_circle_outlined),
              title: Text(
                context.tr('Developer Information', 'معلومات المطوّر'),
              ),
              subtitle: Text(
                context.tr(
                  'Developed by CyberBonk (@CyberBonk)',
                  'طُوّر بواسطة CyberBonk (@CyberBonk)',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeveloperInfoPage()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(
                context.tr('About Timer Be Perfect', 'حول Timer Be Perfect'),
              ),
              subtitle: Text(
                context.tr(
                  'Version details & system status',
                  'تفاصيل الإصدار وحالة النظام',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
          ),
          if (roomId != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final repo = ref.read(roomRepositoryProvider);
                final remoteExit = isController
                    ? repo.closeRoom(roomId: roomId)
                    : repo.leaveRoom(roomId);
                // Local exit must not wait for a slow/offline Firebase write.
                unawaited(remoteExit.catchError(
                  (error, stack) =>
                      debugPrint('Background room exit failed: $error'),
                ));
                ref.read(presenceServiceProvider).unregisterPresence();
                await ref
                    .read(notificationServiceProvider)
                    .cancelRoomNotifications(roomId);
                await RingerService().restoreVolumes();
                await ref.read(activeRoomIdProvider.notifier).update(null);
                await ref.read(activeRoomPinProvider.notifier).update(null);
                await ref.read(userSectorNameProvider.notifier).update(null);
                if (mounted) {
                  navigator.popUntil((route) => route.isFirst);
                }
              },
              icon: const Icon(Icons.exit_to_app),
              label: Text(
                isController
                    ? context.tr('Close Room', 'إغلاق الغرفة')
                    : context.tr('Leave Room', 'مغادرة الغرفة'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
