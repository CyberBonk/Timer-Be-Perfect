export type RoomState = 'lobby' | 'active' | 'completed' | 'closed';
export type RunState = 'starting' | 'running' | 'paused' | 'completed' | 'ended';
export type PhaseType = 'round' | 'cooldown';

export interface Phase {
  phaseId: string;
  type: PhaseType;
  roundIndex?: number;
  startsAt: number; // UTC millis
  endsAt: number;   // UTC millis
}

export interface PausedState {
  pausedAt: number;
  pausedPhaseId: string;
  remainingMs: number;
}

export interface RoomRun {
  runId: string;
  status: RunState;
  revision: number;
  roundCount: number;
  standardRoundDurationMs: number;
  cooldownMs: number;
  startsAt: number;
  schedule: Phase[];
  pausedState?: PausedState | null;
  createdAt: number;
  updatedAt: number;
  endedAt?: number | null;
}

export interface Room {
  roomId: string;
  ownerUid: string;
  state: RoomState;
  sectorCapacity: number | null;
  activeRunId?: string | null;
  revision: number;
  createdAt: number;
  updatedAt: number;
  closedAt?: number | null;
}

export interface Member {
  uid: string;
  sectorName: string;
  normalizedSectorName: string;
  joinedAt: number;
  updatedAt: number;
  notificationReadiness: boolean;
  exactAlarmReadiness: boolean;
  selectedSoundMode: string;
  fcmTokens: string[];
}

export interface FeedEvent {
  eventId: string;
  type: 'announcement' | 'system_control';
  senderUid: string;
  title: string;
  body: string;
  notifyDevices: boolean;
  timestamp: number;
  data?: Record<string, string>;
  targetUid?: string;
  targetSectorName?: string;
}

export interface NotificationOutboxRecord {
  eventId: string;
  roomId: string;
  runId?: string;
  revision: number;
  title: string;
  body: string;
  data?: Record<string, string>;
  recipientUids: string[];
  createdAt: number;
  processedAt?: number | null;
}

export interface CreateRoomRequest {
  sectorCapacity?: number | null;
}

export interface CreateRoomResponse {
  roomId: string;
  pin: string;
}

export interface JoinRoomRequest {
  code: string;
  sectorName: string;
  notificationReadiness?: boolean;
  exactAlarmReadiness?: boolean;
  selectedSoundMode?: string;
  fcmToken?: string;
}

export interface JoinRoomResponse {
  roomId: string;
  sectorName: string;
}

export interface StartRunRequest {
  roomId: string;
  clientCommandId: string;
  expectedRevision: number;
  roundCount?: number;
  standardRoundDurationMinutes?: number;
  cooldownSeconds?: number;
  keepHistory?: boolean;
  notifyDevices?: boolean;
}

export type CommandAction =
  | 'pause'
  | 'resume'
  | 'adjust_time'
  | 'end_round'
  | 'end_event';

export interface ApplyRoomCommandRequest {
  roomId: string;
  clientCommandId: string;
  expectedRevision: number;
  action: CommandAction;
  adjustmentMinutes?: number; // -5, -1, +1, +5
  notifyDevices?: boolean;
}

export interface SendAnnouncementRequest {
  roomId: string;
  clientCommandId: string;
  body: string;
  notifyDevices?: boolean;
  targetUid?: string;
  targetSectorName?: string;
}
