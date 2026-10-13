import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { NotificationOutboxRecord } from './types';

export const handleOutboxCreated = onDocumentCreated(
  {
    document: 'notificationOutbox/{eventId}',
    region: 'europe-west1',
    maxInstances: 5,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const record = snap.data() as NotificationOutboxRecord;
    if (record.processedAt) return; // Already processed

    const db = admin.firestore();
    const messaging = admin.messaging();

    const { roomId, runId, revision, eventId, title, body, data, recipientUids } = record;

    if (!recipientUids || recipientUids.length === 0) {
      await snap.ref.update({ processedAt: Date.now(), notes: 'No recipients' });
      return;
    }

    // Collect all valid FCM tokens for recipient members
    const seenTokens = new Set<string>();
    const tokensWithUids: { uid: string; token: string }[] = [];

    for (const uid of recipientUids) {
      const memberSnap = await db.collection(`rooms/${roomId}/members`).doc(uid).get();
      if (memberSnap.exists) {
        const memberData = memberSnap.data();
        let tokens: string[] = memberData?.fcmTokens || [];
        if (tokens.length === 0 && memberData?.fcmToken) {
          tokens = [memberData.fcmToken];
        }
        for (const rawToken of tokens) {
          const token = typeof rawToken === 'string' ? rawToken.trim() : '';
          if (token.length > 0 && !seenTokens.has(token)) {
            seenTokens.add(token);
            tokensWithUids.push({ uid, token });
          }
        }
      }
    }

    if (tokensWithUids.length === 0) {
      await snap.ref.update({ processedAt: Date.now(), notes: 'No tokens found' });
      return;
    }

    const payloadData: Record<string, any> = {
      eventId,
      roomId,
      runId: runId || '',
      revision: revision.toString(),
      title: title || '',
      body: body || '',
      priority: 'high',
      ...(data || {}),
    };

    // Ensure all values in the data dictionary are strings
    const safeData: Record<string, string> = {};
    for (const [k, v] of Object.entries(payloadData)) {
      if (v !== undefined && v !== null) {
        safeData[k] = typeof v === 'string' ? v : String(v);
      }
    }

    let totalSuccess = 0;
    let totalFailure = 0;
    const invalidTokensByUid = new Map<string, string[]>();
    const batchSize = 500;

    for (let i = 0; i < tokensWithUids.length; i += batchSize) {
      const chunk = tokensWithUids.slice(i, i + batchSize);
      const tokens = chunk.map(t => t.token);

      // Data-only payload with high priority ensures onBackgroundMessage runs immediately
      // even when participant devices are in Android Doze mode or deep sleep.
      const response = await messaging.sendEachForMulticast({
        tokens,
        data: safeData,
        android: {
          priority: 'high',
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'background',
          },
          payload: {
            aps: {
              'content-available': 1,
            },
          },
        },
      });

      totalSuccess += response.successCount;
      totalFailure += response.failureCount;

      response.responses.forEach((resp, idx) => {
        if (!resp.success && resp.error) {
          const code = resp.error.code;
          if (
            code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered'
          ) {
            const item = chunk[idx];
            const list = invalidTokensByUid.get(item.uid) || [];
            list.push(item.token);
            invalidTokensByUid.set(item.uid, list);
          }
        }
      });
    }

    for (const [uid, badTokens] of invalidTokensByUid.entries()) {
      const memberRef = db.collection(`rooms/${roomId}/members`).doc(uid);
      const mSnap = await memberRef.get();
      if (mSnap.exists) {
        const memberData = mSnap.data();
        const currentTokens: string[] = memberData?.fcmTokens || [];
        const filtered = currentTokens.filter(t => !badTokens.includes(t));
        const updates: Record<string, any> = { fcmTokens: filtered };
        if (badTokens.includes(memberData?.fcmToken)) {
          updates.fcmToken = admin.firestore.FieldValue.delete();
        }
        await memberRef.update(updates);
      }
    }

    await snap.ref.update({
      processedAt: Date.now(),
      successCount: totalSuccess,
      failureCount: totalFailure,
    });
  }
);
