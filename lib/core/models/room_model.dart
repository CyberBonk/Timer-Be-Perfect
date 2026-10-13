import 'package:cloud_firestore/cloud_firestore.dart';

enum RoomState { lobby, active, completed, closed }

class Room {
  final String roomId;
  final String ownerUid;
  final RoomState state;

  /// Optional sector list configured for the room.
  final List<String> sectors;
  final int? sectorCapacity;
  final String? activeRunId;
  final int revision;
  final int createdAt;
  final int updatedAt;
  final int? closedAt;

  const Room({
    required this.roomId,
    required this.ownerUid,
    required this.state,
    this.sectors = const [],
    required this.sectorCapacity,
    this.activeRunId,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
  });

  static int _parseTimestampMs(dynamic val) {
    if (val is Timestamp) {
      return val.millisecondsSinceEpoch;
    } else if (val is num) {
      return val.toInt();
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      roomId: json['roomId'] as String? ?? '',
      ownerUid: json['ownerUid'] as String? ?? '',
      state: _parseState(json['state'] as String?),
      sectors: (json['sectors'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      sectorCapacity: (json['sectorCapacity'] as num?)?.toInt(),
      activeRunId: json['activeRunId'] as String?,
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      createdAt: _parseTimestampMs(json['createdAt']),
      updatedAt: _parseTimestampMs(json['updatedAt']),
      closedAt:
          json['closedAt'] != null ? _parseTimestampMs(json['closedAt']) : null,
    );
  }

  static RoomState _parseState(String? state) {
    switch (state) {
      case 'active':
        return RoomState.active;
      case 'completed':
        return RoomState.completed;
      case 'closed':
        return RoomState.closed;
      case 'lobby':
      default:
        return RoomState.lobby;
    }
  }

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'ownerUid': ownerUid,
        'state': state.name,
        'sectors': sectors,
        'sectorCapacity': sectorCapacity,
        'activeRunId': activeRunId,
        'revision': revision,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'closedAt': closedAt,
      };
}
