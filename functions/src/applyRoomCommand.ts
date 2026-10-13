import * as admin from 'firebase-admin';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';
import { ApplyRoomCommandRequest, FeedEvent, NotificationOutboxRecord, Phase, Room, RoomRun } from './types';

export async function handleApplyRoomCommand(
  request: CallableRequest<ApplyRoomCommandRequest>
): Promise<{ revision: number }> {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const uid = request.auth.uid;
  const {
    roomId,
    clientCommandId,
    expectedRevision,
    action,
    adjustmentMinutes,
    notifyDevices = true,
  } = request.data;

  if (!roomId || !action) {
    throw new HttpsError('invalid-argument', 'roomId and action are required.');
  }

  const db = admin.firestore();
  const roomRef = db.collection('rooms').doc(roomId);

  let newRevision = 0;

  await db.runTransaction(async (tx) => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) {
      throw new HttpsError('not-found', 'Room not found.');
    }
    const room = roomSnap.data() as Room;

    if (room.ownerUid !== uid) {
      throw new HttpsError('permission-denied', 'Only the room owner can control the event.');
    }

    if (room.state === 'closed') {
      throw new HttpsError('failed-precondition', 'Cannot issue commands in a closed room.');
    }

    if (room.revision !== expectedRevision) {
      throw new HttpsError('aborted', `Schedule revision mismatch. Expected ${expectedRevision}, current room revision is ${room.revision}.`);
    }

    if (!room.activeRunId) {
      throw new HttpsError('failed-precondition', 'No active run found for room.');
    }

    const runRef = db.collection(`rooms/${roomId}/runs`).doc(room.activeRunId);
    const runSnap = await tx.get(runRef);
    if (!runSnap.exists) {
      throw new HttpsError('not-found', 'Active run document not found.');
    }
    const run = runSnap.data() as RoomRun;

    const now = Date.now();
    newRevision = room.revision + 1;

    let updatedSchedule: Phase[] = [...run.schedule];
    let newStatus = run.status;
    let newPausedState = run.pausedState;
    let eventTitle = '';
    let eventBody = '';

    if (action === 'pause') {
      if (run.status === 'paused') {
        throw new HttpsError('failed-precondition', 'Run is already paused.');
      }
      if (run.status === 'completed' || run.status === 'ended') {
        throw new HttpsError('failed-precondition', 'Cannot pause a finished run.');
      }

      // Find active phase
      const currentPhase = updatedSchedule.find(p => p.startsAt <= now && now < p.endsAt)
        || updatedSchedule.find(p => p.startsAt > now); // fallback to next phase

      const phaseId = currentPhase ? currentPhase.phaseId : updatedSchedule[0]?.phaseId || 'phase_1';
      const remainingMs = currentPhase ? Math.max(0, currentPhase.endsAt - now) : 0;

      newPausedState = {
        pausedAt: now,
        pausedPhaseId: phaseId,
        remainingMs,
      };
      newStatus = 'paused';
      eventTitle = 'Event Paused';
      eventBody = 'Controller paused the timer.';
    } else if (action === 'resume') {
      if (run.status !== 'paused' || !run.pausedState) {
        throw new HttpsError('failed-precondition', 'Run is not currently paused.');
      }

      const leadTimeMs = 5000;
      const newStartsAt = now + leadTimeMs;
      const pausedPhaseId = run.pausedState.pausedPhaseId;
      const remainingMs = run.pausedState.remainingMs;

      const pausedIndex = updatedSchedule.findIndex(p => p.phaseId === pausedPhaseId);
      if (pausedIndex !== -1) {
        const oldEndsAt = updatedSchedule[pausedIndex].endsAt;
        const newEndsAt = newStartsAt + remainingMs;
        const delta = newEndsAt - oldEndsAt;

        updatedSchedule[pausedIndex] = {
          ...updatedSchedule[pausedIndex],
          startsAt: newStartsAt,
          endsAt: newEndsAt,
        };

        for (let i = pausedIndex + 1; i < updatedSchedule.length; i++) {
          updatedSchedule[i] = {
            ...updatedSchedule[i],
            startsAt: updatedSchedule[i].startsAt + delta,
            endsAt: updatedSchedule[i].endsAt + delta,
          };
        }
      }

      newPausedState = null;
      newStatus = 'running';
      eventTitle = 'Event Resumed';
      eventBody = 'Controller resumed the timer.';
    } else if (action === 'adjust_time') {
      if (!adjustmentMinutes || ![-5, -1, 1, 5].includes(adjustmentMinutes)) {
        throw new HttpsError('invalid-argument', 'adjustmentMinutes must be -5, -1, +1, or +5.');
      }

      // Valid only while a round phase is active
      const activePhaseIndex = updatedSchedule.findIndex(p => p.startsAt <= now && now < p.endsAt);
      if (activePhaseIndex === -1 || updatedSchedule[activePhaseIndex].type !== 'round') {
        throw new HttpsError('failed-precondition', 'Time adjustments can only be applied during an active round.');
      }

      const deltaMs = adjustmentMinutes * 60 * 1000;
      const activePhase = updatedSchedule[activePhaseIndex];
      const newEndsAt = activePhase.endsAt + deltaMs;

      // Keep a short future boundary so every participant can schedule the
      // same alarm even when the controller adjusts the round to its edge.
      const effectiveEndsAt = Math.max(now + 5000, newEndsAt);
      const actualDelta = effectiveEndsAt - activePhase.endsAt;

      updatedSchedule[activePhaseIndex] = {
        ...activePhase,
        endsAt: effectiveEndsAt,
      };

      for (let i = activePhaseIndex + 1; i < updatedSchedule.length; i++) {
        updatedSchedule[i] = {
          ...updatedSchedule[i],
          startsAt: updatedSchedule[i].startsAt + actualDelta,
          endsAt: updatedSchedule[i].endsAt + actualDelta,
        };
      }

      const sign = adjustmentMinutes > 0 ? `+${adjustmentMinutes}` : `${adjustmentMinutes}`;
      eventTitle = 'Timer Adjusted';
      eventBody = `Controller adjusted active round duration by ${sign} minute(s).`;
    } else if (action === 'end_round') {
      const activePhaseIndex = updatedSchedule.findIndex(p => p.startsAt <= now && now < p.endsAt);
      if (activePhaseIndex === -1) {
        throw new HttpsError('failed-precondition', 'No active phase running.');
      }

      const activePhase = updatedSchedule[activePhaseIndex];
      const delta = now - activePhase.endsAt;

      updatedSchedule[activePhaseIndex] = {
        ...activePhase,
        endsAt: now,
      };

      for (let i = activePhaseIndex + 1; i < updatedSchedule.length; i++) {
        updatedSchedule[i] = {
          ...updatedSchedule[i],
          startsAt: updatedSchedule[i].startsAt + delta,
          endsAt: updatedSchedule[i].endsAt + delta,
        };
      }

      eventTitle = 'Round Ended Early';
      eventBody = 'Controller ended the active round.';
    } else if (action === 'end_event') {
      newStatus = 'ended';
      eventTitle = 'Event Ended';
      eventBody = 'Controller ended the event.';
    } else {
      throw new HttpsError('invalid-argument', `Unknown action: ${action}`);
    }

    tx.update(runRef, {
      status: newStatus,
      revision: newRevision,
      schedule: updatedSchedule,
      pausedState: newPausedState,
      updatedAt: now,
      endedAt: action === 'end_event' ? now : null,
    });

    tx.update(roomRef, {
      revision: newRevision,
      updatedAt: now,
      state: action === 'end_event' ? 'completed' : room.state,
    });

    const eventId = clientCommandId || db.collection(`rooms/${roomId}/feed`).doc().id;
    const feedDoc: FeedEvent = {
      eventId,
      type: 'system_control',
      senderUid: uid,
      title: eventTitle,
      body: eventBody,
      notifyDevices,
      timestamp: now,
      data: {
        action,
        runId: room.activeRunId!,
        revision: newRevision.toString(),
        runStatus: newStatus,
        roundCount: run.roundCount.toString(),
        schedule: JSON.stringify(updatedSchedule),
        startsAt: run.startsAt.toString(),
        ...(newPausedState
          ? {
              pausedPhaseId: newPausedState.pausedPhaseId,
              pausedRemainingMs: newPausedState.remainingMs.toString(),
              pausedAt: newPausedState.pausedAt.toString(),
            }
          : {}),
      },
    };

    tx.set(db.collection(`rooms/${roomId}/feed`).doc(eventId), feedDoc);

    if (notifyDevices) {
      const membersSnap = await tx.get(db.collection(`rooms/${roomId}/members`));
      const recipientUids = membersSnap.docs.map(d => d.id).filter(id => id !== uid);

      const outboxDoc: NotificationOutboxRecord = {
        eventId,
        roomId,
        runId: room.activeRunId!,
        revision: newRevision,
        title: feedDoc.title,
        body: feedDoc.body,
        data: feedDoc.data,
        recipientUids,
        createdAt: now,
        processedAt: null,
      };

      tx.set(db.collection('notificationOutbox').doc(eventId), outboxDoc);
    }
  });

  return { revision: newRevision };
}
