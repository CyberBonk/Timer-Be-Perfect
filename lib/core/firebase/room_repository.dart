import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/room_model.dart';
import '../models/member_model.dart';
import '../models/run_model.dart';
import '../models/feed_event_model.dart';
import '../models/sound_mode.dart';
import 'server_clock.dart';
import 'room_authorization.dart';

int _parseTimestampMs(dynamic val) {
  if (val == null) return DateTime.now().millisecondsSinceEpoch;
  if (val is Timestamp) return val.millisecondsSinceEpoch;
  if (val is num) return val.toInt();
  if (val is String) {
    return int.tryParse(val) ?? DateTime.now().millisecondsSinceEpoch;
  }
  return DateTime.now().millisecondsSinceEpoch;
}

class RoomRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;

  /// Ensures installation is authenticated via Anonymous Auth
  Future<User> ensureAuthenticated() async {
    if (_auth.currentUser != null) {
      return _auth.currentUser!;
    }
    final userCredential = await _auth.signInAnonymously();
    return userCredential.user!;
  }

  /// Generates a secure random 6-digit numeric PIN
  String _generateRandomPin() {
    final random = Random.secure();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// Creates a Room (Tries Cloud Function first, falls back to direct Firestore transaction)
  Future<Map<String, String>> createRoom({int? sectorCapacity}) async {
    final user = await ensureAuthenticated();

    try {
      final result = await _functions.httpsCallable('createRoom').call({
        'sectorCapacity': sectorCapacity,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return {
        'roomId': data['roomId'] as String,
        'pin': data['pin'] as String,
      };
    } catch (e) {
      debugPrint(
          'Cloud Function createRoom unavailable ($e). Executing client-side room creation...');
      return _createRoomClientSide(user.uid, sectorCapacity);
    }
  }

  Future<Map<String, String>> _createRoomClientSide(
      String uid, int? sectorCapacity) async {
    final roomDocRef = _db.collection('rooms').doc();
    final roomId = roomDocRef.id;

    String pin = _generateRandomPin();
    bool pinUnique = false;

    for (int attempts = 0; attempts < 5; attempts++) {
      final pinSnap = await _db.collection('roomCodes').doc(pin).get();
      if (!pinSnap.exists) {
        pinUnique = true;
        break;
      }
      pin = _generateRandomPin();
    }

    if (!pinUnique) {
      pin = (100000 + Random().nextInt(900000)).toString();
    }

    final batch = _db.batch();

    // Create Room
    batch.set(roomDocRef, {
      'roomId': roomId,
      'pin': pin,
      'ownerUid': uid,
      'state': 'lobby',
      'sectorCapacity': sectorCapacity,
      'activeRunId': null,
      'revision': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Create Code Mapping
    batch.set(_db.collection('roomCodes').doc(pin), {
      'roomId': roomId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Add Owner Member
    batch.set(_db.collection('rooms/$roomId/members').doc(uid), {
      'uid': uid,
      'sectorName': 'Controller',
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
      'notificationReadiness': true,
      'exactAlarmReadiness': true,
      'selectedSoundMode': SoundMode.bePerfectSound.toStorageString(),
      'fcmToken': null,
    });

    await batch.commit();

    return {
      'roomId': roomId,
      'pin': pin,
    };
  }

  /// Joins a Room (Tries Cloud Function first, falls back to direct Firestore lookup)
  Future<Map<String, String>> joinRoom({
    required String code,
    required String sectorName,
    bool notificationReadiness = false,
    bool exactAlarmReadiness = false,
    SoundMode selectedSoundMode = SoundMode.bePerfectSound,
    String? fcmToken,
  }) async {
    final user = await ensureAuthenticated();
    const allowClientSideFallback = bool.fromEnvironment(
      'ALLOW_CLIENT_SIDE_FALLBACK',
      defaultValue: true,
    );

    try {
      final result = await _functions.httpsCallable('joinRoom').call({
        'code': code,
        'sectorName': sectorName,
        'notificationReadiness': notificationReadiness,
        'exactAlarmReadiness': exactAlarmReadiness,
        'selectedSoundMode': selectedSoundMode.toStorageString(),
        'fcmToken': fcmToken,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return {
        'roomId': data['roomId'] as String,
        'sectorName': data['sectorName'] as String,
      };
    } catch (e) {
      if (!allowClientSideFallback) {
        rethrow;
      }
      debugPrint(
          'Cloud Function joinRoom unavailable ($e). Executing client-side join...');
      return _joinRoomClientSide(
        uid: user.uid,
        code: code,
        sectorName: sectorName,
        notificationReadiness: notificationReadiness,
        exactAlarmReadiness: exactAlarmReadiness,
        selectedSoundMode: selectedSoundMode,
        fcmToken: fcmToken,
      );
    }
  }

  Future<Map<String, String>> _joinRoomClientSide({
    required String uid,
    required String code,
    required String sectorName,
    required bool notificationReadiness,
    required bool exactAlarmReadiness,
    required SoundMode selectedSoundMode,
    String? fcmToken,
  }) async {
    final codeSnap = await _db.collection('roomCodes').doc(code).get();
    if (!codeSnap.exists || codeSnap.data() == null) {
      throw Exception('Invalid room PIN code. Please verify the 6-digit PIN.');
    }

    final roomId = codeSnap.data()!['roomId'] as String;
    final roomSnap = await _db.collection('rooms').doc(roomId).get();

    if (!roomSnap.exists || roomSnap.data() == null) {
      throw Exception('Room no longer exists.');
    }

    final roomData = roomSnap.data()!;
    if (roomData['state'] == 'closed') {
      throw Exception('This room is closed.');
    }

    final memberRef = _db.collection('rooms/$roomId/members').doc(uid);
    await memberRef.set({
      'uid': uid,
      'sectorName': sectorName,
      'role': 'sector',
      'joinedAt': FieldValue.serverTimestamp(),
      'notificationReadiness': notificationReadiness,
      'exactAlarmReadiness': exactAlarmReadiness,
      'selectedSoundMode': selectedSoundMode.toStorageString(),
      'fcmToken': fcmToken,
    }, SetOptions(merge: true));

    return {
      'roomId': roomId,
      'sectorName': sectorName,
    };
  }

  /// Starts a Run (Tries Cloud Function, falls back to direct Firestore batch)
  Future<void> startRun({
    required String roomId,
    required int expectedRevision,
    int roundCount = 6,
    int standardRoundDurationMinutes = 20,
    int cooldownSeconds = 0,
    bool keepHistory = true,
    bool notifyDevices = true,
  }) async {
    try {
      final clientCommandId = _db.collection('rooms').doc().id;
      await _functions.httpsCallable('startRun').call({
        'roomId': roomId,
        'clientCommandId': clientCommandId,
        'expectedRevision': expectedRevision,
        'roundCount': roundCount,
        'standardRoundDurationMinutes': standardRoundDurationMinutes,
        'cooldownSeconds': cooldownSeconds,
        'keepHistory': keepHistory,
        'notifyDevices': notifyDevices,
      });
    } catch (e) {
      debugPrint(
          'Cloud Function startRun unavailable ($e). Executing client-side start...');
      await _startRunClientSide(
        roomId: roomId,
        roundCount: roundCount,
        standardRoundDurationMinutes: standardRoundDurationMinutes,
        cooldownSeconds: cooldownSeconds,
      );
    }
  }

  Future<void> _startRunClientSide({
    required String roomId,
    required int roundCount,
    required int standardRoundDurationMinutes,
    required int cooldownSeconds,
  }) async {
    final roomSnap = await _db.collection('rooms').doc(roomId).get();
    final ownerUid = roomSnap.data()?['ownerUid'] as String?;
    if (!isRoomController(ownerUid: ownerUid, currentUid: currentUid)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Only the room controller can start a run.',
      );
    }

    final nowMs = await ServerClock().syncedNowMs();
    final leadTimeMs = 5000; // 5s 3-2-1 lead time
    final roundMs = standardRoundDurationMinutes * 60 * 1000;
    final cooldownMs = cooldownSeconds * 1000;

    final List<Map<String, dynamic>> scheduleData = [];
    int cursorMs = nowMs + leadTimeMs;

    for (int i = 1; i <= roundCount; i++) {
      final roundStart = cursorMs;
      final roundEnd = roundStart + roundMs;
      scheduleData.add({
        'phaseId': 'phase_r$i',
        'type': 'round',
        'roundIndex': i,
        'startsAt': roundStart,
        'endsAt': roundEnd,
      });
      cursorMs = roundEnd;

      if (cooldownMs > 0 && i < roundCount) {
        final cooldownStart = cursorMs;
        final cooldownEnd = cooldownStart + cooldownMs;
        scheduleData.add({
          'phaseId': 'phase_c$i',
          'type': 'cooldown',
          'roundIndex': i,
          'startsAt': cooldownStart,
          'endsAt': cooldownEnd,
        });
        cursorMs = cooldownEnd;
      }
    }

    final runDocRef = _db.collection('rooms/$roomId/runs').doc();
    final runId = runDocRef.id;

    final batch = _db.batch();

    batch.set(runDocRef, {
      'runId': runId,
      'status': 'running',
      'revision': 1,
      'roundCount': roundCount,
      'standardRoundDurationMs': roundMs,
      'cooldownMs': cooldownMs,
      'startsAt': nowMs + leadTimeMs,
      'schedule': scheduleData,
      'pausedState': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('rooms').doc(roomId), {
      'state': 'running',
      'activeRunId': runId,
      'revision': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Applies a Room Command (pause, resume, adjust_time, end_round, end_event)
  Future<void> applyRoomCommand({
    required String roomId,
    required int expectedRevision,
    required String action,
    int? adjustmentMinutes,
    bool notifyDevices = true,
    bool isArabic = false,
  }) async {
    // The Cloud Function is authoritative: it validates the room revision,
    // writes the run/feed/outbox atomically, and prevents double application.
    try {
      final clientCommandId = _db.collection('rooms').doc().id;
      await _functions.httpsCallable('applyRoomCommand').call({
        'roomId': roomId,
        'clientCommandId': clientCommandId,
        'expectedRevision': expectedRevision,
        'action': action,
        'adjustmentMinutes': adjustmentMinutes,
        'notifyDevices': notifyDevices,
      }).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      rethrow;
    } catch (e) {
      debugPrint('Cloud Function applyRoomCommand unavailable ($e). Executing client-side fallback...');
      await _applyRoomCommandClientSide(
        roomId: roomId,
        action: action,
        adjustmentMinutes: adjustmentMinutes,
        isArabic: isArabic,
      );
    }
  }

  Future<void> postFeedEvent({
    required String roomId,
    required String title,
    required String body,
    bool notifyDevices = true,
  }) async {
    final docRef = _db.collection('rooms/$roomId/feed').doc();
    await docRef.set({
      'eventId': docRef.id,
      'type': 'system_control',
      'title': title,
      'body': body,
      'senderUid': currentUid ?? 'controller',
      'notifyDevices': notifyDevices,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _applyRoomCommandClientSide({
    required String roomId,
    required String action,
    int? adjustmentMinutes,
    bool isArabic = false,
  }) async {
    String text(String english, String arabic) => isArabic ? arabic : english;
    final roomSnap = await _db.collection('rooms').doc(roomId).get();
    if (!roomSnap.exists || roomSnap.data() == null) return;

    // Keep the offline fallback as strict as the Cloud Function. A
    // participant must never gain controller powers when Functions are down.
    final ownerUid = roomSnap.data()!['ownerUid'] as String?;
    if (!isRoomController(ownerUid: ownerUid, currentUid: currentUid)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Only the room controller can apply commands.',
      );
    }

    final activeRunId = roomSnap.data()!['activeRunId'] as String?;
    if (activeRunId == null) return;

    final runRef = _db.collection('rooms/$roomId/runs').doc(activeRunId);
    final runSnap = await runRef.get();
    if (!runSnap.exists || runSnap.data() == null) return;

    final runData = runSnap.data()!;
    final nowMs = await ServerClock().syncedNowMs();

    if (action == 'end_event') {
      final batch = _db.batch();
      batch.update(runRef, {
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.update(_db.collection('rooms').doc(roomId), {
        'state': 'idle',
        'activeRunId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      await postFeedEvent(
        roomId: roomId,
        title: text('Event Ended', 'انتهت الفعالية'),
        body: text(
          'Controller manually ended the event run.',
          'أنهى المتحكّم الفعالية يدويًا.',
        ),
      );
      return;
    }

    final String currentStatus = runData['status'] as String? ?? 'running';
    final List<dynamic> scheduleRaw =
        List<dynamic>.from(runData['schedule'] as List<dynamic>? ?? []);

    if (action == 'pause' && currentStatus == 'running') {
      int remainingMs = 0;
      String pausedPhaseId = '';
      for (final item in scheduleRaw) {
        final phase = Map<String, dynamic>.from(item as Map);
        final int endsAt = _parseTimestampMs(phase['endsAt']);
        if (endsAt > nowMs) {
          pausedPhaseId = phase['phaseId'] as String? ?? '';
          remainingMs = (endsAt - nowMs).clamp(0, 86400000);
          break;
        }
      }

      await runRef.update({
        'status': 'paused',
        'pausedState': {
          'pausedAt': nowMs,
          'pausedPhaseId': pausedPhaseId,
          'remainingMs': remainingMs,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await postFeedEvent(
        roomId: roomId,
        title: text('Timer Paused ⏸', 'تم إيقاف المؤقت مؤقتًا ⏸'),
        body: text(
          'Controller paused the timer.',
          'أوقف المتحكّم المؤقت مؤقتًا.',
        ),
      );
      return;
    }

    if (action == 'resume' && currentStatus == 'paused') {
      final pausedStateMap = runData['pausedState'] != null
          ? Map<String, dynamic>.from(runData['pausedState'] as Map)
          : null;
      final int remainingMs = pausedStateMap != null
          ? (pausedStateMap['remainingMs'] as num).toInt()
          : 60000;
      final String pausedPhaseId = pausedStateMap != null
          ? (pausedStateMap['pausedPhaseId'] as String? ?? '')
          : '';

      bool foundPaused = false;
      int cursorMs = nowMs + 3000; // 3s restart lead time

      for (int i = 0; i < scheduleRaw.length; i++) {
        final phase = Map<String, dynamic>.from(scheduleRaw[i] as Map);
        if (phase['phaseId'] == pausedPhaseId || foundPaused) {
          foundPaused = true;
          final int phaseDuration = (phase['phaseId'] == pausedPhaseId)
              ? remainingMs
              : (_parseTimestampMs(phase['endsAt']) -
                  _parseTimestampMs(phase['startsAt']));

          phase['startsAt'] = cursorMs;
          phase['endsAt'] = cursorMs + phaseDuration;
          cursorMs += phaseDuration;
        }
        scheduleRaw[i] = phase;
      }

      await runRef.update({
        'status': 'running',
        'pausedState': null,
        'schedule': scheduleRaw,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await postFeedEvent(
        roomId: roomId,
        title: text('Timer Resumed ▶', 'تم استئناف المؤقت ▶'),
        body: text(
          'Controller resumed the timer.',
          'استأنف المتحكّم المؤقت.',
        ),
      );
      return;
    }

    if (action == 'adjust_time' &&
        adjustmentMinutes != null &&
        adjustmentMinutes != 0) {
      final int deltaMs = adjustmentMinutes * 60 * 1000;
      bool activePhaseFound = false;

      for (int i = 0; i < scheduleRaw.length; i++) {
        final phase = Map<String, dynamic>.from(scheduleRaw[i] as Map);
        final int endsAt = _parseTimestampMs(phase['endsAt']);

        if (!activePhaseFound && endsAt > nowMs) {
          activePhaseFound = true;
          final int newEndsAt = max(nowMs + 5000, endsAt + deltaMs);
          phase['endsAt'] = newEndsAt;
          int nextCursor = newEndsAt;

          for (int j = i + 1; j < scheduleRaw.length; j++) {
            final nextPhase = Map<String, dynamic>.from(scheduleRaw[j] as Map);
            final int duration = _parseTimestampMs(nextPhase['endsAt']) -
                _parseTimestampMs(nextPhase['startsAt']);
            nextPhase['startsAt'] = nextCursor;
            nextPhase['endsAt'] = nextCursor + duration;
            nextCursor += duration;
            scheduleRaw[j] = nextPhase;
          }
          scheduleRaw[i] = phase;
          break;
        }
      }

      await runRef.update({
        'schedule': scheduleRaw,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final label = adjustmentMinutes > 0
          ? '+$adjustmentMinutes mins'
          : '$adjustmentMinutes mins';
      await postFeedEvent(
        roomId: roomId,
        title: text('Time Adjusted ⏱', 'تم تعديل الوقت ⏱'),
        body: text(
          'Controller adjusted time by $label.',
          'عدّل المتحكّم الوقت بمقدار $label.',
        ),
      );
      return;
    }

    if (action == 'end_round') {
      int skippedRoundNum = 1;
      for (int i = 0; i < scheduleRaw.length; i++) {
        final phase = Map<String, dynamic>.from(scheduleRaw[i] as Map);
        final int endsAt = _parseTimestampMs(phase['endsAt']);

        if (endsAt > nowMs) {
          skippedRoundNum = (phase['roundIndex'] as num?)?.toInt() ?? (i + 1);
          phase['endsAt'] = nowMs;
          int nextCursor = nowMs;

          for (int j = i + 1; j < scheduleRaw.length; j++) {
            final nextPhase = Map<String, dynamic>.from(scheduleRaw[j] as Map);
            final int duration = _parseTimestampMs(nextPhase['endsAt']) -
                _parseTimestampMs(nextPhase['startsAt']);
            nextPhase['startsAt'] = nextCursor;
            nextPhase['endsAt'] = nextCursor + duration;
            nextCursor += duration;
            scheduleRaw[j] = nextPhase;
          }
          scheduleRaw[i] = phase;
          break;
        }
      }

      await runRef.update({
        'schedule': scheduleRaw,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await postFeedEvent(
        roomId: roomId,
        title: text('Round Skipped ⏭', 'تم تخطي الجولة ⏭'),
        body: text(
          'Controller skipped Round $skippedRoundNum.',
          'تخطى المتحكّم الجولة $skippedRoundNum.',
        ),
      );
      return;
    }
  }

  /// Sends an Announcement (broadcast or targeted to a specific participant)
  Future<void> sendAnnouncement({
    required String roomId,
    required String body,
    String title = 'Announcement',
    bool notifyDevices = true,
    String? targetUid,
    String? targetSectorName,
  }) async {
    final docRef = _db.collection('rooms/$roomId/feed').doc();
    final data = <String, dynamic>{
      'eventId': docRef.id,
      'type': 'announcement',
      'title': title,
      'body': body,
      'timestamp': FieldValue.serverTimestamp(),
      'senderUid': currentUid ?? '',
      'authorUid': currentUid,
      'notifyDevices': notifyDevices,
    };
    if (targetUid != null) data['targetUid'] = targetUid;
    if (targetSectorName != null) data['targetSectorName'] = targetSectorName;
    await docRef.set(data);
  }

  /// Updates Member Readiness
  Future<void> updateMemberReadiness({
    required String roomId,
    bool? notificationReadiness,
    bool? exactAlarmReadiness,
    SoundMode? selectedSoundMode,
    String? fcmToken,
  }) async {
    final uid = currentUid;
    if (uid == null) return;

    final memberRef = _db.collection('rooms/$roomId/members').doc(uid);
    final Map<String, dynamic> updates = {};
    if (notificationReadiness != null) {
      updates['notificationReadiness'] = notificationReadiness;
    }
    if (exactAlarmReadiness != null) {
      updates['exactAlarmReadiness'] = exactAlarmReadiness;
    }
    if (selectedSoundMode != null) {
      updates['selectedSoundMode'] = selectedSoundMode.toStorageString();
    }
    if (fcmToken != null) updates['fcmToken'] = fcmToken;

    if (updates.isNotEmpty) {
      await memberRef.set(updates, SetOptions(merge: true));
    }
  }

  /// Leaves a Room
  Future<void> leaveRoom(String roomId) async {
    final uid = currentUid;
    if (uid != null) {
      await _db.collection('rooms/$roomId/members').doc(uid).delete();
    }
  }

  /// Removes a Member
  Future<void> removeMember(
      {required String roomId, required String targetUid}) async {
    await _db.collection('rooms/$roomId/members').doc(targetUid).delete();
  }

  /// Closes a Room. Use the callable when deployed, with a direct Firestore
  /// fallback for projects where Functions have not been deployed yet.
  Future<void> closeRoom(
      {required String roomId, bool notifyDevices = true}) async {
    try {
      await _functions.httpsCallable('closeRoom').call({
        'roomId': roomId,
        'notifyDevices': notifyDevices,
      });
      return;
    } catch (e) {
      debugPrint(
          'Cloud Function closeRoom unavailable ($e). Executing client-side room closure...');
    }

    await _db.collection('rooms').doc(roomId).update({
      'state': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // --- Real-time Subscriptions ---

  Stream<Room?> watchRoom(String roomId) {
    return _db.collection('rooms').doc(roomId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return Room.fromJson(snap.data()!);
    });
  }

  Stream<RoomRun?> watchActiveRun(String roomId, String runId) {
    return _db
        .collection('rooms/$roomId/runs')
        .doc(runId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return RoomRun.fromJson(snap.data()!);
    });
  }

  Stream<List<Member>> watchMembers(String roomId) {
    return _db.collection('rooms/$roomId/members').snapshots().map((snap) {
      return snap.docs.map((doc) => Member.fromJson(doc.data())).toList();
    });
  }

  /// Watches this device's membership so a controller removal is observable
  /// by the removed device and can end its local session immediately.
  Stream<Member?> watchMember(String roomId, String uid) {
    return _db.collection('rooms/$roomId/members').doc(uid).snapshots().map(
        (snap) => snap.exists && snap.data() != null
            ? Member.fromJson(snap.data()!)
            : null);
  }

  Stream<List<FeedEvent>> watchFeed(String roomId, {int limit = 100}) {
    return _db
        .collection('rooms/$roomId/feed')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) => FeedEvent.fromJson(doc.data())).toList();
    });
  }
}
