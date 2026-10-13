import * as admin from 'firebase-admin';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

export interface UpdateMemberRequest {
  roomId: string;
  notificationReadiness?: boolean;
  exactAlarmReadiness?: boolean;
  selectedSoundMode?: string;
  fcmToken?: string;
}

export async function handleUpdateMember(
  request: CallableRequest<UpdateMemberRequest>
): Promise<{ success: boolean }> {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const uid = request.auth.uid;
  const { roomId, notificationReadiness, exactAlarmReadiness, selectedSoundMode, fcmToken } = request.data;

  if (!roomId) {
    throw new HttpsError('invalid-argument', 'roomId is required.');
  }

  const db = admin.firestore();
  const memberRef = db.collection(`rooms/${roomId}/members`).doc(uid);

  const snap = await memberRef.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Member doc not found in room.');
  }

  const updates: Record<string, any> = {
    updatedAt: Date.now(),
  };

  if (notificationReadiness !== undefined) updates.notificationReadiness = notificationReadiness;
  if (exactAlarmReadiness !== undefined) updates.exactAlarmReadiness = exactAlarmReadiness;
  if (selectedSoundMode !== undefined) updates.selectedSoundMode = selectedSoundMode;

  if (fcmToken) {
    updates.fcmToken = fcmToken;
    const existingTokens: string[] = snap.data()?.fcmTokens || [];
    if (!existingTokens.includes(fcmToken)) {
      updates.fcmTokens = [...existingTokens, fcmToken];
    }
  }

  await memberRef.update(updates);
  return { success: true };
}
