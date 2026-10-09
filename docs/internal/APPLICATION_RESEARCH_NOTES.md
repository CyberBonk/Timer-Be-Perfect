# Application Research Notes: Be-Perfect Connection Resilience & Offline Handling

## 1. Connection Handling & Presence

### 1.1 Realtime Database and `PresenceService`
- **Mechanism**: The `PresenceService` leverages Firebase Realtime Database (RTDB) `.info/connected` to listen to device connection states.
- **`onDisconnect` Handlers**: When a device connects, it immediately registers an `onDisconnect().remove()` on its connection node and an `onDisconnect().set(ServerValue.timestamp)` on its `lastSeen` node. This ensures that even if the app crashes or the network drops abruptly, the Firebase server will gracefully clear the presence status.
- **Firestore Heartbeat Fallback**: Additionally, `PresenceService` sets up a periodic 20-second timer to write a heartbeat (`lastSeenAt`) to Firestore (`rooms/{roomId}/members/{uid}`).

### 1.2 Firestore Offline Persistence & Dual-Path Execution
- **Dual-Path Strategy**: The `RoomRepository` implements a highly resilient "dual-path" system. For operations like creating rooms, joining, and issuing timer commands, it first attempts to call a Cloud Function. If the function fails or times out (e.g., a 5-second timeout on `applyRoomCommand`), it gracefully degrades to executing direct Firestore document mutations locally (e.g., `_applyRoomCommandClientSide`).
- **Cache Behavior**: When operating offline, the local Firestore mutations are written directly to the local cache, allowing the UI to instantly reflect the updated state. Once the connection is re-established, the Firebase SDK automatically synchronizes these queued writes with the server.

### 1.3 Anonymous Authentication Lifecycle
- **Behavior**: `AuthService` (via `RoomRepository.ensureAuthenticated()`) gracefully handles signing in users anonymously if no active user session exists. 
- **Resilience**: Firebase Auth automatically manages token refreshes. Because Cloud Functions rely on the auth token, the dual-path execution allows users to remain functional even if a token refresh fails due to brief offline periods, as direct Firestore reads/writes can sometimes persist via local cache.

### 1.4 Audio/Exact Alarms & OEM Battery Savers
- **Alarm Mechanism**: The application heavily relies on the `alarm` package, pushing boundary alarms (using `BoundaryAlarmSpec`) for round completions via `NotificationService.scheduleBoundaryAlarms()`.
- **OEM Battery Restrictions**: Because Android devices (particularly Samsung, Xiaomi, and OnePlus) aggressively kill background processes, the app wisely uses `androidFullScreenIntent: true`, `warningNotificationOnKill: false`, and schedules the alarms directly with the OS's AlarmManager.
- **Timer derivation**: The timer UI state is entirely deterministic. `ScheduleEngine.deriveState()` relies entirely on UTC timestamps and local elapsed time, meaning the timer UI continues to tick perfectly even when the device is completely offline.

---

## 2. Identified Edge Cases & Potential Failures

### 2.1 The "Phantom Function" Double Execution Risk
- **Issue**: If the client is on a poor network, the Cloud Function (`applyRoomCommand`) may execute successfully on the server, but the response to the client times out.
- **Failure**: The client catches the `TimeoutException` and falls back to `_applyRoomCommandClientSide`. When connectivity is restored, the client pushes the local offline mutation to the server. Since the local fallback does not enforce the `expectedRevision` check transactionally like the Cloud Function does, it can overwrite the state, causing the same command to be applied twice.

### 2.2 Firestore Offline Heartbeat Flood
- **Issue**: The `PresenceService` writes a heartbeat to Firestore every 20 seconds.
- **Failure**: If a user is offline for 2 hours, the periodic timer keeps executing, writing roughly 360 updates to the offline Firestore cache. When the network is restored, all 360 writes are flushed to the server simultaneously. While the SDK coalesces some writes, this can still cause burst writes, wasting quota and potentially triggering rate limits.

### 2.3 Desynced Offline State Transitions
- **Issue**: If a controller pauses the timer while offline, the local cache reflects it. If a second controller (online) ends the round simultaneously, the server state diverges.
- **Failure**: When the first controller reconnects, their offline `pause` command will overwrite the server state based on their stale offline cache snapshot, potentially rolling back the `end_round` action.

### 2.4 Exact Alarms Permission Denial (Android 12+)
- **Issue**: Android 12+ requires explicit user permission for Exact Alarms (`SCHEDULE_EXACT_ALARM`). 
- **Failure**: While `NotificationService` checks `canScheduleExactNotifications()`, if the user revokes this permission, `Alarm.set()` may crash or silently fail.

---

## 3. Recommended Libraries & Prototype Patterns

### 3.1 Network State Awareness with `connectivity_plus`
Instead of blindly waiting 5 seconds for a Cloud Function to timeout, integrate the `connectivity_plus` package.
- **Pattern**: Check `Connectivity().checkConnectivity()`. If explicitly offline, bypass the Cloud Function entirely and immediately route to the offline Firestore fallback. This avoids hanging the UI for 5 seconds.

### 3.2 Idempotency Keys & Local Transaction Queues
To resolve the double execution risk, abandon raw offline Firestore batches for commands.
- **Pattern**: Implement a Command Queue using a local database like `isar` or `sqflite`. Assign a UUID to every room command. When online, a background worker syncs the queue. The Cloud Function and Firestore rules should validate the UUID to guarantee idempotency.

### 3.3 Heartbeat Queue Throttling
- **Pattern**: In `PresenceService`, check if the device is offline. If offline, pause the Firestore heartbeat timer and rely entirely on the RTDB `onDisconnect` which will have already fired on the server. Only resume the heartbeat when the connection returns.

### 3.4 Recommended Ecosystem Packages
- `connectivity_plus`: For proactive connection awareness.
- `internet_connection_checker_plus`: To verify actual internet access, not just Wi-Fi connection without internet.
- `flutter_background_service` or `workmanager`: For more resilient background task processing if exact alarms are heavily throttled by OEMs.
- `isar` or `drift`: For a reliable, ordered local command queue if you adopt the offline-first CQRS pattern.
