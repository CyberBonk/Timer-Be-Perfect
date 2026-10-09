import 'package:cloud_firestore/cloud_firestore.dart';

enum FeedEventType { announcement, systemControl }

class FeedEvent {
  final String eventId;
  final FeedEventType type;
  final String senderUid;
  final String title;
  final String body;
  final bool notifyDevices;
  final int timestamp;
  final Map<String, String>? data;
  final String? targetUid;
  final String? targetSectorName;

  const FeedEvent({
    required this.eventId,
    required this.type,
    required this.senderUid,
    required this.title,
    required this.body,
    required this.notifyDevices,
    required this.timestamp,
    this.data,
    this.targetUid,
    this.targetSectorName,
  });

  static int _parseTimestampMs(dynamic val) {
    if (val is Timestamp) {
      return val.millisecondsSinceEpoch;
    } else if (val is num) {
      return val.toInt();
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  factory FeedEvent.fromJson(Map<String, dynamic> json) {
    return FeedEvent(
      eventId: json['eventId'] as String? ?? '',
      type: (json['type'] as String?) == 'announcement'
          ? FeedEventType.announcement
          : FeedEventType.systemControl,
      senderUid: json['senderUid'] as String? ?? '',
      title: json['title'] as String? ?? 'Announcement',
      body: json['body'] as String? ?? '',
      notifyDevices: json['notifyDevices'] as bool? ?? true,
      timestamp: _parseTimestampMs(json['timestamp']),
      data: json['data'] != null
          ? Map<String, String>.from(json['data'] as Map)
          : null,
      targetUid: json['targetUid'] as String?,
      targetSectorName: json['targetSectorName'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'type': type == FeedEventType.announcement
            ? 'announcement'
            : 'system_control',
        'senderUid': senderUid,
        'title': title,
        'body': body,
        'notifyDevices': notifyDevices,
        'timestamp': timestamp,
        'data': data,
        if (targetUid != null) 'targetUid': targetUid,
        if (targetSectorName != null) 'targetSectorName': targetSectorName,
      };
}
