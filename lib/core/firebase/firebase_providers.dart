import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'room_repository.dart';
import 'presence_service.dart';
import '../notifications/notification_service.dart';
import '../models/room_model.dart';
import '../models/member_model.dart';
import '../models/run_model.dart';
import '../models/feed_event_model.dart';
import '../models/sound_mode.dart';

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  return RoomRepository();
});

final currentUidProvider = Provider<String?>((ref) {
  try {
    return ref.watch(roomRepositoryProvider).currentUid;
  } catch (_) {
    return null;
  }
});

final presenceServiceProvider = Provider<PresenceService>((ref) {
  return PresenceService();
});

// Restored anonymous auth can complete after the first widget build. Watching
// this stream lets presence registration retry as soon as the UID is ready.
final firebaseAuthStateProvider = StreamProvider.autoDispose<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

// --- Riverpod 3 Notifiers ---

const _activeRoomIdKey = 'active_room_id';
const _activeRoomPinKey = 'active_room_pin';
const _userSectorNameKey = 'user_sector_name';

class ActiveRoomIdNotifier extends Notifier<String?> {
  var _hasLocalUpdate = false;

  @override
  String? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_hasLocalUpdate) state = prefs.getString(_activeRoomIdKey);
  }

  Future<void> update(String? val) async {
    _hasLocalUpdate = true;
    state = val;
    await _persist(val);
  }

  Future<void> _persist(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_activeRoomIdKey);
    } else {
      await prefs.setString(_activeRoomIdKey, value);
    }
  }
}

final activeRoomIdProvider =
    NotifierProvider<ActiveRoomIdNotifier, String?>(ActiveRoomIdNotifier.new);

class ActiveRoomPinNotifier extends Notifier<String?> {
  var _hasLocalUpdate = false;

  @override
  String? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_hasLocalUpdate) state = prefs.getString(_activeRoomPinKey);
  }

  Future<void> update(String? val) async {
    _hasLocalUpdate = true;
    state = val;
    await _persist(val);
  }

  Future<void> _persist(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_activeRoomPinKey);
    } else {
      await prefs.setString(_activeRoomPinKey, value);
    }
  }
}

final activeRoomPinProvider =
    NotifierProvider<ActiveRoomPinNotifier, String?>(ActiveRoomPinNotifier.new);

class UserSectorNameNotifier extends Notifier<String?> {
  var _hasLocalUpdate = false;

  @override
  String? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_hasLocalUpdate) state = prefs.getString(_userSectorNameKey);
  }

  Future<void> update(String? val) async {
    _hasLocalUpdate = true;
    state = val;
    await _persist(val);
  }

  Future<void> _persist(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_userSectorNameKey);
    } else {
      await prefs.setString(_userSectorNameKey, value);
    }
  }
}

final userSectorNameProvider =
    NotifierProvider<UserSectorNameNotifier, String?>(
        UserSectorNameNotifier.new);

class SoundModeNotifier extends Notifier<SoundMode> {
  @override
  SoundMode build() => SoundMode.bePerfectSound;
  void update(SoundMode val) => state = val;
}

final soundModeProvider =
    NotifierProvider<SoundModeNotifier, SoundMode>(SoundModeNotifier.new);

// --- Live Streams ---

final roomStreamProvider = StreamProvider.autoDispose<Room?>((ref) {
  final roomId = ref.watch(activeRoomIdProvider);
  if (roomId == null) return Stream.value(null);
  return ref.watch(roomRepositoryProvider).watchRoom(roomId);
});

final activeRunStreamProvider = StreamProvider.autoDispose<RoomRun?>((ref) {
  final roomAsync = ref.watch(roomStreamProvider);
  final room = roomAsync.asData?.value;
  if (room == null ||
      room.state == RoomState.closed ||
      room.activeRunId == null) {
    return Stream.value(null);
  }
  return ref
      .watch(roomRepositoryProvider)
      .watchActiveRun(room.roomId, room.activeRunId!);
});

final membersStreamProvider = StreamProvider.autoDispose<List<Member>>((ref) {
  final roomId = ref.watch(activeRoomIdProvider);
  if (roomId == null) return Stream.value([]);
  return ref.watch(roomRepositoryProvider).watchMembers(roomId);
});

final currentMemberStreamProvider = StreamProvider.autoDispose<Member?>((ref) {
  final roomId = ref.watch(activeRoomIdProvider);
  final repo = ref.watch(roomRepositoryProvider);
  final uid = repo.currentUid;
  if (roomId == null || uid == null) return Stream.value(null);
  return repo.watchMember(roomId, uid);
});

final presenceStreamProvider =
    StreamProvider.autoDispose<Map<String, ConnectionStatus>>((ref) {
  final roomId = ref.watch(activeRoomIdProvider);
  if (roomId == null) return Stream.value({});
  return ref.watch(presenceServiceProvider).watchRoomPresence(roomId);
});

final firebaseConnectionProvider = StreamProvider.autoDispose<bool>((ref) {
  return ref.watch(presenceServiceProvider).watchConnectionState();
});

final feedStreamProvider = StreamProvider.autoDispose<List<FeedEvent>>((ref) {
  final roomId = ref.watch(activeRoomIdProvider);
  if (roomId == null) return Stream.value([]);
  return ref.watch(roomRepositoryProvider).watchFeed(roomId);
});
