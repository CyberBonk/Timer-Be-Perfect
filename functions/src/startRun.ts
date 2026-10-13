import * as admin from 'firebase-admin';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';
import { FeedEvent, NotificationOutboxRecord, Phase, Room, RoomRun, StartRunRequest } from './types';

export async function handleStartRun(
  request: CallableRequest<StartRunRequest>
): Promise<{ runId: string; revision: number }> {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const uid = request.auth.uid;
  const {
    roomId,
    clientCommandId,
    expectedRevision,
    roundCount = 6,
    standardRoundDurationMinutes = 20,
    cooldownSeconds = 0,
    notifyDevices = true,
  } = request.data;

  if (!roomId) {
    throw new HttpsError('invalid-argument', 'roomId is required.');
  }

  if (roundCount < 1 || roundCount > 30) {
    throw new HttpsError('invalid-argument', 'Round count must be between 1 and 30.');
  }

  if (standardRoundDurationMinutes < 1 || standardRoundDurationMinutes > 180) {
    throw new HttpsError('invalid-argument', 'Standard round duration must be between 1 and 180 minutes.');
  }

  if (cooldownSeconds < 0 || cooldownSeconds > 600) {
    throw new HttpsError('invalid-argument', 'Cooldown must be between 0 and 600 seconds.');
  }

  const db = admin.firestore();
  const roomRef = db.collection('rooms').doc(roomId);

  let newRevision = 0;
  let runId = '';

  await db.runTransaction(async (tx) => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) {
      throw new HttpsError('not-found', 'Room not found.');
    }
    const room = roomSnap.data() as Room;

    if (room.ownerUid !== uid) {
      throw new HttpsError('permission-denied', 'Only the room owner can start an event run.');
    }

    if (room.state === 'closed') {
      throw new HttpsError('failed-precondition', 'Cannot start a run in a closed room.');
    }

    if (room.revision !== expectedRevision) {
      throw new HttpsError('aborted', `Schedule revision mismatch. Expected ${expectedRevision}, but current room revision is ${room.revision}.`);
    }

    newRevision = room.revision + 1;
    runId = db.collection(`rooms/${roomId}/runs`).doc().id;

    const now = Date.now();
    const leadTimeMs = 5000; // 5 seconds synchronized lead time
    const startsAt = now + leadTimeMs;
    const roundDurationMs = standardRoundDurationMinutes * 60 * 1000;
    const cooldownMs = cooldownSeconds * 1000;

    const schedule: Phase[] = [];
    let currentPhaseStart = startsAt;
    let phaseCounter = 0;

    for (let r = 1; r <= roundCount; r++) {
      // Round phase
      phaseCounter++;
      const roundEnd = currentPhaseStart + roundDurationMs;
      schedule.push({
        phaseId: `phase_${phaseCounter}_round_${r}`,
        type: 'round',
        roundIndex: r,
        startsAt: currentPhaseStart,
        endsAt: roundEnd,
      });
      currentPhaseStart = roundEnd;

      // Cooldown phase (if > 0 and not after final round)
      if (cooldownMs > 0 && r < roundCount) {
        phaseCounter++;
        const cooldownEnd = currentPhaseStart + cooldownMs;
        schedule.push({
          phaseId: `phase_${phaseCounter}_cooldown_${r}`,
          type: 'cooldown',
          roundIndex: r,
          startsAt: currentPhaseStart,
          endsAt: cooldownEnd,
        });
        currentPhaseStart = cooldownEnd;
      }
    }

    const runDoc: RoomRun = {
      runId,
      status: 'starting',
      revision: newRevision,
      roundCount,
      standardRoundDurationMs: roundDurationMs,
      cooldownMs,
      startsAt,
      schedule,
      pausedState: null,
      createdAt: now,
      updatedAt: now,
      endedAt: null,
    };

    tx.set(db.collection(`rooms/${roomId}/runs`).doc(runId), runDoc);

    tx.update(roomRef, {
      state: 'active',
      activeRunId: runId,
      revision: newRevision,
      updatedAt: now,
    });

    const eventId = clientCommandId || db.collection(`rooms/${roomId}/feed`).doc().id;
    const feedDoc: FeedEvent = {
      eventId,
      type: 'system_control',
      senderUid: uid,
      title: 'Event Started',
      body: `Run started: ${roundCount} rounds of ${standardRoundDurationMinutes} min.`,
      notifyDevices,
      timestamp: now,
      data: {
        action: 'start_run',
        runId,
        revision: newRevision.toString(),
        runStatus: 'starting',
        roundCount: roundCount.toString(),
        schedule: JSON.stringify(schedule),
        startsAt: startsAt.toString(),
      },
    };

    tx.set(db.collection(`rooms/${roomId}/feed`).doc(eventId), feedDoc);

    if (notifyDevices) {
      const membersSnap = await tx.get(db.collection(`rooms/${roomId}/members`));
      const recipientUids = membersSnap.docs.map(d => d.id).filter(id => id !== uid);

      const outboxDoc: NotificationOutboxRecord = {
        eventId,
        roomId,
        runId,
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

  return { runId, revision: newRevision };
}
