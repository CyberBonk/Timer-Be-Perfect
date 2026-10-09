import * as admin from 'firebase-admin';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';
import { FeedEvent, Member, NotificationOutboxRecord, Room, SendAnnouncementRequest } from './types';

export async function handleSendAnnouncement(
  request: CallableRequest<SendAnnouncementRequest>
): Promise<{ eventId: string }> {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const uid = request.auth.uid;
  const { roomId, clientCommandId, body, notifyDevices = true } = request.data;

  if (!roomId || !body) {
    throw new HttpsError('invalid-argument', 'roomId and announcement body are required.');
  }

  const trimmedBody = body.trim();
  if (trimmedBody.length < 1 || trimmedBody.length > 500) {
    throw new HttpsError('invalid-argument', 'Announcement body must be between 1 and 500 characters.');
  }

  const db = admin.firestore();
  const roomRef = db.collection('rooms').doc(roomId);

  const eventId = clientCommandId || db.collection(`rooms/${roomId}/feed`).doc().id;

  await db.runTransaction(async (tx) => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) {
      throw new HttpsError('not-found', 'Room not found.');
    }
    const room = roomSnap.data() as Room;

    const isOwner = room.ownerUid === uid;
    const memberDocRef = db.doc(`rooms/${roomId}/members/${uid}`);
    const memberSnap = await tx.get(memberDocRef);

    if (!isOwner && !memberSnap.exists) {
      throw new HttpsError('permission-denied', 'Only room members or the controller can post announcements.');
    }

    if (room.state === 'closed') {
      throw new HttpsError('failed-precondition', 'Cannot send announcements in a closed room.');
    }

    const memberData = memberSnap.exists ? (memberSnap.data() as Member) : null;
    const senderName = memberData?.sectorName || 'Participant';
    const now = Date.now();

    const feedDoc: FeedEvent = {
      eventId,
      type: 'announcement',
      senderUid: uid,
      title: isOwner ? 'Controller Announcement' : `Message from ${senderName}`,
      body: trimmedBody,
      notifyDevices,
      timestamp: now,
      targetUid: request.data.targetUid,
      targetSectorName: request.data.targetSectorName,
    };

    tx.set(db.collection(`rooms/${roomId}/feed`).doc(eventId), feedDoc);

    if (notifyDevices) {
      let recipientUids: string[] = [];
      if (request.data.targetUid) {
        recipientUids = [request.data.targetUid];
      } else {
        const membersSnap = await tx.get(db.collection(`rooms/${roomId}/members`));
        recipientUids = membersSnap.docs.map(d => d.id).filter(id => id !== uid);
      }

      const outboxDoc: NotificationOutboxRecord = {
        eventId,
        roomId,
        runId: room.activeRunId || undefined,
        revision: room.revision,
        title: feedDoc.title,
        body: feedDoc.body,
        recipientUids,
        createdAt: now,
        processedAt: null,
      };

      tx.set(db.collection('notificationOutbox').doc(eventId), outboxDoc);
    }
  });

  return { eventId };
}
