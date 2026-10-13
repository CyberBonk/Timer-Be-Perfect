import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:be_perfect/core/firebase/firebase_providers.dart';
import 'package:be_perfect/core/notifications/notification_service.dart';
import 'package:be_perfect/core/notifications/ringer_service.dart';
import 'package:be_perfect/core/theme/app_theme.dart';
import 'package:be_perfect/core/models/sound_mode.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('room state notifiers update in memory and persist locally', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(activeRoomIdProvider.notifier).update('room-123');
    await container.read(activeRoomPinProvider.notifier).update('123456');
    await container.read(userSectorNameProvider.notifier).update('Alpha');

    expect(container.read(activeRoomIdProvider), 'room-123');
    expect(container.read(activeRoomPinProvider), '123456');
    expect(container.read(userSectorNameProvider), 'Alpha');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('active_room_id'), 'room-123');
    expect(prefs.getString('active_room_pin'), '123456');
    expect(prefs.getString('user_sector_name'), 'Alpha');
  });

  test('dynamic limits notifiers update in memory and persist locally', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(maxRoundDurationProvider.notifier).update(90);
    await container.read(maxCooldownSecondsProvider.notifier).update(600);
    await container.read(cooldownStepSecondsProvider.notifier).update(30);

    expect(container.read(maxRoundDurationProvider), 90);
    expect(container.read(maxCooldownSecondsProvider), 600);
    expect(container.read(cooldownStepSecondsProvider), 30);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('max_round_duration_minutes'), 90);
    expect(prefs.getInt('max_cooldown_seconds'), 600);
    expect(prefs.getInt('cooldown_step_seconds'), 30);
  });

  test('sound mode notifier changes without external dependencies', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(soundModeProvider), SoundMode.bePerfectSound);
    container.read(soundModeProvider.notifier).update(SoundMode.vibrationOnly);
    expect(container.read(soundModeProvider), SoundMode.vibrationOnly);
  });

  test('theme exposes Material 3 schemes for every seed', () {
    expect(AppTheme.seeds, isNotEmpty);
    for (final seed in AppTheme.seeds) {
      final light = AppTheme.lightThemeWithSeed(seed.color);
      final dark = AppTheme.darkThemeWithSeed(seed.color);
      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.colorScheme.primary, isNotNull);
      expect(dark.colorScheme.primary, isNotNull);
    }
  });

  test('notification IDs are stable and separate by purpose', () {
    final service = NotificationService();
    final roomId = 'room-123';

    expect(
        service.getNotificationId(roomId), service.getNotificationId(roomId));
    expect(service.getRoundAlarmNotificationId(roomId, 1),
        isNot(service.getRoundAlarmNotificationId(roomId, 2)));
    expect(service.getRoundAlarmNotificationId(roomId, 1), greaterThan(0));
  });

  test('ringer service handles fallback state cleanly in test environment', () async {
    final ringer = RingerService();
    expect(await ringer.isSoundModeEnabled(), isTrue);
    expect(await ringer.isSoundModeAudible(), isTrue);
    expect(await ringer.isDndAccessGranted(), isFalse);
    await ringer.forceSoundMode();
    await ringer.restoreVolumes();
  });
}
