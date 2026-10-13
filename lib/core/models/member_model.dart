import 'package:cloud_firestore/cloud_firestore.dart';
import 'sound_mode.dart';

class Member {
  final String uid;
  final String participantName;
  final String sectorName;
  final String normalizedSectorName;
  final int acknowledgedRevision;
  final int joinedAt;
  final int updatedAt;
  final int lastSeenAt;
  final bool notificationReadiness;
  final bool exactAlarmReadiness;
  final SoundMode selectedSoundMode;
  final List<String> fcmTokens;

  const Member({
    required this.uid,
    this.participantName = '',
    required this.sectorName,
    required this.normalizedSectorName,
    this.acknowledgedRevision = 1,
    required this.joinedAt,
    required this.updatedAt,
    required this.lastSeenAt,
    required this.notificationReadiness,
    required this.exactAlarmReadiness,
    required this.selectedSoundMode,
    required this.fcmTokens,
  });

  static int _parseTimestampMs(dynamic val) {
    if (val is Timestamp) {
      return val.millisecondsSinceEpoch;
    } else if (val is num) {
      return val.toInt();
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  factory Member.fromJson(Map<String, dynamic> json) {
    final name = json['sectorName'] as String? ?? 'Participant';
    final pName = json['participantName'] as String? ?? '';
    return Member(
      uid: json['uid'] as String? ?? '',
      participantName: pName.isNotEmpty ? pName : name,
      sectorName: name,
      normalizedSectorName: json['normalizedSectorName'] as String? ??
          name.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
      acknowledgedRevision:
          (json['acknowledgedRevision'] as num?)?.toInt() ?? 1,
      joinedAt: _parseTimestampMs(json['joinedAt']),
      updatedAt: _parseTimestampMs(json['updatedAt']),
      lastSeenAt: json['lastSeenAt'] == null
          ? 0
          : _parseTimestampMs(json['lastSeenAt']),
      notificationReadiness: json['notificationReadiness'] as bool? ?? false,
      exactAlarmReadiness: json['exactAlarmReadiness'] as bool? ?? false,
      selectedSoundMode:
          SoundMode.fromString(json['selectedSoundMode'] as String?),
      fcmTokens: (json['fcmTokens'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['fcmToken'] != null && json['fcmToken'].toString().isNotEmpty
              ? [json['fcmToken'].toString()]
              : []),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'participantName': participantName,
        'sectorName': sectorName,
        'normalizedSectorName': normalizedSectorName,
        'acknowledgedRevision': acknowledgedRevision,
        'joinedAt': joinedAt,
        'updatedAt': updatedAt,
        'lastSeenAt': lastSeenAt,
        'notificationReadiness': notificationReadiness,
        'exactAlarmReadiness': exactAlarmReadiness,
        'selectedSoundMode': selectedSoundMode.toStorageString(),
        'fcmTokens': fcmTokens,
      };
}
