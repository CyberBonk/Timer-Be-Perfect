import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:be_perfect/core/models/feed_event_model.dart';
import 'package:be_perfect/core/models/member_model.dart';
import 'package:be_perfect/core/models/phase_model.dart';
import 'package:be_perfect/core/models/room_model.dart';
import 'package:be_perfect/core/models/run_model.dart';
import 'package:be_perfect/core/models/sound_mode.dart';

void main() {
  const timestamp = 1700000000123;

  group('Phase', () {
    test('round phase round-trips through JSON', () {
      const phase = Phase(
        phaseId: 'round-1',
        type: PhaseType.round,
        roundIndex: 1,
        startsAt: timestamp,
        endsAt: timestamp + 60000,
      );

      final restored = Phase.fromJson(phase.toJson());

      expect(restored.phaseId, 'round-1');
      expect(restored.type, PhaseType.round);
      expect(restored.roundIndex, 1);
      expect(restored.durationMs, 60000);
    });

    test('parses Firestore timestamps and cooldown phases', () {
      final phase = Phase.fromJson({
        'phaseId': 'cooldown-1',
        'type': 'cooldown',
        'roundIndex': 1,
        'startsAt': Timestamp.fromMillisecondsSinceEpoch(timestamp),
        'endsAt': Timestamp.fromMillisecondsSinceEpoch(timestamp + 5000),
      });

      expect(phase.type, PhaseType.cooldown);
      expect(phase.startsAt, timestamp);
      expect(phase.endsAt, timestamp + 5000);
    });
  });

  group('Room and RoomRun', () {
    test('room preserves nullable and enum fields', () {
      const room = Room(
        roomId: 'room-1',
        ownerUid: 'owner-1',
        state: RoomState.closed,
        sectors: ['Alpha', 'Beta'],
        sectorCapacity: null,
        activeRunId: null,
        revision: 3,
        createdAt: timestamp,
        updatedAt: timestamp + 1,
        closedAt: timestamp + 2,
      );

      final restored = Room.fromJson(room.toJson());

      expect(restored.roomId, 'room-1');
      expect(restored.ownerUid, 'owner-1');
      expect(restored.state, RoomState.closed);
      expect(restored.sectors, ['Alpha', 'Beta']);
      expect(restored.revision, 3);
      expect(restored.sectorCapacity, isNull);
      expect(restored.closedAt, timestamp + 2);
    });

    test('run and paused state preserve schedule data', () {
      const paused = PausedState(
        pausedAt: timestamp + 1000,
        pausedPhaseId: 'round-1',
        remainingMs: 120000,
      );
      const run = RoomRun(
        runId: 'run-1',
        status: RunStatus.paused,
        revision: 2,
        roundCount: 1,
        standardRoundDurationMs: 180000,
        cooldownMs: 0,
        startsAt: timestamp,
        schedule: [
          Phase(
            phaseId: 'round-1',
            type: PhaseType.round,
            roundIndex: 1,
            startsAt: timestamp,
            endsAt: timestamp + 180000,
          ),
        ],
        pausedState: paused,
        createdAt: timestamp,
        updatedAt: timestamp + 1,
      );

      final restored = RoomRun.fromJson(run.toJson());

      expect(restored.status, RunStatus.paused);
      expect(restored.schedule.single.phaseId, 'round-1');
      expect(restored.pausedState?.remainingMs, 120000);
    });
  });

  group('Member and FeedEvent', () {
    test('member derives a normalized name and round-trips tokens', () {
      final member = Member.fromJson({
        'uid': 'member-1',
        'participantName': 'Abanoub',
        'sectorName': '  Alpha  Team ',
        'acknowledgedRevision': 4,
        'joinedAt': timestamp,
        'updatedAt': timestamp,
        'lastSeenAt': null,
        'notificationReadiness': true,
        'exactAlarmReadiness': false,
        'selectedSoundMode': 'vibration_only',
        'fcmTokens': [123, 'token-2'],
      });

      expect(member.participantName, 'Abanoub');
      expect(member.acknowledgedRevision, 4);
      expect(member.normalizedSectorName, ' alpha team ');
      expect(member.lastSeenAt, 0);
      expect(member.selectedSoundMode, SoundMode.vibrationOnly);
      expect(member.toJson()['fcmTokens'], ['123', 'token-2']);
      expect(member.toJson()['participantName'], 'Abanoub');
      expect(member.toJson()['acknowledgedRevision'], 4);
    });

    test('feed events distinguish announcements from system events', () {
      final announcement = FeedEvent.fromJson({
        'eventId': 'event-1',
        'type': 'announcement',
        'senderUid': 'controller',
        'title': 'Ready',
        'body': 'Begin now',
        'notifyDevices': false,
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(timestamp),
        'data': {'source': 'test'},
      });
      final systemEvent = FeedEvent.fromJson({
        'eventId': 'event-2',
        'timestamp': timestamp,
      });

      expect(announcement.type, FeedEventType.announcement);
      expect(announcement.data?['source'], 'test');
      expect(announcement.toJson()['type'], 'announcement');
      expect(systemEvent.type, FeedEventType.systemControl);
      expect(systemEvent.title, 'Announcement');
      expect(systemEvent.notifyDevices, isTrue);
    });
  });

  test('sound modes support storage values and legacy aliases', () {
    expect(SoundMode.fromString('device_default'), SoundMode.deviceDefault);
    expect(SoundMode.fromString('be_perfect_round_system_v3'),
        SoundMode.deviceDefault);
    expect(SoundMode.fromString('vibration_only'), SoundMode.vibrationOnly);
    expect(SoundMode.fromString('be_perfect_round_custom_v1'),
        SoundMode.bePerfectSound);

    for (final mode in SoundMode.values) {
      expect(SoundMode.fromString(mode.toStorageString()), mode);
    }
  });
}
