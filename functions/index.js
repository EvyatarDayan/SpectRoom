const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {onRequest, onCall, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {defineSecret} = require('firebase-functions/params');
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const path = require('path');

const SPECTROOM_LOGO_PATH = path.join(__dirname, 'assets', 'Logo1.png');
const SPECTROOM_LOGO_CID = 'spectroom-logo';
/** Reserved sender id for official SpectRoom inbox messages (admin warnings, etc.). */
const SPECTROOM_SYSTEM_UID = 'spectroom-official';

admin.initializeApp();

// Gmail (or Google Workspace) account used to send transactional mail.
// Set with:
//   firebase functions:secrets:set WELCOME_EMAIL_USER
//   firebase functions:secrets:set WELCOME_EMAIL_PASS
// Use a Gmail App Password if 2FA is enabled on the account.
const welcomeEmailUser = defineSecret('WELCOME_EMAIL_USER');
const welcomeEmailPass = defineSecret('WELCOME_EMAIL_PASS');

function spectRoomLogoAttachment() {
  if (!require('fs').existsSync(SPECTROOM_LOGO_PATH)) {
    console.warn(`spectRoomLogoAttachment: missing ${SPECTROOM_LOGO_PATH}`);
    return null;
  }
  return {
    filename: 'Logo1.png',
    path: SPECTROOM_LOGO_PATH,
    cid: SPECTROOM_LOGO_CID,
    contentDisposition: 'inline',
  };
}

function spectRoomEmailAttachments() {
  const logo = spectRoomLogoAttachment();
  return logo ? [logo] : [];
}

function createSpectRoomTransporter() {
  return nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: welcomeEmailUser.value(),
      pass: welcomeEmailPass.value(),
    },
  });
}

function wrapSpectRoomEmailHtml({pageTitle, heading, bodyHtml}) {
  const year = new Date().getFullYear();
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${pageTitle}</title>
</head>
<body style="margin:0;padding:0;background-color:#f2f2f7;-webkit-text-size-adjust:100%;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#f2f2f7;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;background-color:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e5e5ea;">
          <tr>
            <td align="center" style="padding:28px 24px 20px;border-bottom:1px solid #e5e5ea;">
              <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
                <tr>
                  <td valign="middle" style="padding:0 10px 0 0;">
                    <img src="cid:${SPECTROOM_LOGO_CID}"
                         width="40"
                         height="40"
                         alt="SpectRoom"
                         style="display:block;width:40px;height:40px;border:0;border-radius:8px;outline:none;">
                  </td>
                  <td valign="middle" style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:28px;font-weight:700;letter-spacing:-0.4px;color:#1c1c1e;line-height:40px;">
                    SpectRoom
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:32px 28px 8px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1c1c1e;">
              <h1 style="margin:0 0 20px;font-size:24px;line-height:1.3;font-weight:700;color:#1c1c1e;">
                ${heading}
              </h1>
              ${bodyHtml}
            </td>
          </tr>
          <tr>
            <td style="padding:20px 28px 28px;border-top:1px solid #e5e5ea;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;color:#8e8e93;text-align:center;">
              © ${year} SpectRoom. All rights reserved.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();
}

function spectRoomCtaButton(href, label) {
  return `
              <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin:0 auto 28px;">
                <tr>
                  <td align="center" bgcolor="#007AFF" style="border-radius:12px;">
                    <a href="${href}"
                       style="display:inline-block;padding:14px 32px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:16px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:12px;">
                      ${label}
                    </a>
                  </td>
                </tr>
              </table>`;
}

function escapeHtml(value) {
  return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
}

/**
 * Deliver an official SpectRoom warning into the user's Messages inbox.
 * Uses noticeId as the document id so client + Cloud Function writes stay idempotent.
 */
async function writeSpectRoomSystemWarningMessage({userId, content, noticeId, reportId}) {
  const messageId = String(noticeId || `warning-${userId}-${Date.now()}`);
  const timestamp = Date.now() / 1000;
  await admin.firestore()
      .collection('users')
      .doc(userId)
      .collection('incomingMessages')
      .doc(messageId)
      .set({
        id: messageId,
        senderId: SPECTROOM_SYSTEM_UID,
        recipientId: userId,
        content: String(content || ''),
        type: 'text',
        createdAt: timestamp,
        isRead: false,
        readAt: null,
        kind: 'admin_warning',
        notice_id: messageId,
        report_id: reportId || null,
      }, {merge: true});
  console.log(`✅ SpectRoom system warning message written for ${userId} (${messageId})`);
  return messageId;
}

/** Routes email action links to our hosted page (no Firebase CONTINUE button). */
function toSpectRoomAuthActionLink(oobLink) {
  try {
    const parsed = new URL(oobLink);
    parsed.pathname = '/auth/action.html';
    parsed.searchParams.delete('continueUrl');
    return parsed.toString();
  } catch (error) {
    return String(oobLink || '').replace('/__/auth/action', '/auth/action.html');
  }
}

function firstNameFromUserData(userData = {}, email = '') {
  const displayName = String(userData.name || userData.displayName || '').trim();
  if (displayName) {
    return displayName.split(/\s+/)[0];
  }
  const local = String(email || '').split('@')[0].trim();
  return local || 'there';
}

async function resolveUserEmail(userId, userData = {}) {
  const fromDoc = String(userData.email || '').trim();
  if (fromDoc.includes('@')) {
    return fromDoc;
  }
  try {
    const authUser = await admin.auth().getUser(userId);
    const fromAuth = String(authUser.email || '').trim();
    return fromAuth.includes('@') ? fromAuth : null;
  } catch (error) {
    console.warn(`resolveUserEmail: no Auth email for ${userId}:`, error.message);
    return null;
  }
}

function moderationBodyHtml(paragraphs, {includeContactSupport = false} = {}) {
  const parts = (paragraphs || [])
      .map((text) => String(text || '').trim())
      .filter(Boolean)
      .map((text) => {
        const safe = escapeHtml(text).replace(/\n/g, '<br>');
        return `
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                ${safe}
              </p>`;
      });

  if (includeContactSupport) {
    parts.push(`
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                If you have questions, you can contact SpectRoom support:
              </p>`);
    parts.push(spectRoomCtaButton('mailto:spectroom.support@gmail.com', 'Contact support'));
  }

  parts.push(`
              <p style="margin:0 0 8px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                The SpectRoom team
              </p>`);

  return parts.join('\n');
}

/**
 * Branded moderation email (warn / freeze / unfreeze / ban / unban).
 * Uses the same SpectRoom card template as welcome + password reset.
 */
async function sendSpectRoomModerationEmail({
  userId,
  userData,
  subject,
  heading,
  paragraphs,
  includeContactSupport = false,
}) {
  const to = await resolveUserEmail(userId, userData);
  if (!to) {
    console.log(`sendSpectRoomModerationEmail: skip ${subject} — no email for ${userId}`);
    return false;
  }

  const firstName = firstNameFromUserData(userData, to);
  const year = new Date().getFullYear();
  const fromAddress = welcomeEmailUser.value();
  const bodyParagraphs = [
    `Hi ${firstName},`,
    ...(paragraphs || []),
  ];

  const mailOptions = {
    from: `"SpectRoom" <${fromAddress}>`,
    to,
    subject,
    attachments: [spectRoomLogoAttachment()],
    text: [
      'SpectRoom',
      '',
      heading,
      '',
      ...bodyParagraphs,
      ...(includeContactSupport
        ? [
          '',
          'If you have questions, you can contact SpectRoom support:',
          'Contact support: spectroom.support@gmail.com',
        ]
        : []),
      '',
      'The SpectRoom team',
      '',
      `© ${year} SpectRoom. All rights reserved.`,
    ].join('\n'),
    html: wrapSpectRoomEmailHtml({
      pageTitle: subject,
      heading,
      bodyHtml: moderationBodyHtml(bodyParagraphs, {includeContactSupport}),
    }),
  };

  try {
    await createSpectRoomTransporter().sendMail(mailOptions);
    console.log(`✅ Moderation email (${subject}) sent to ${to} (uid=${userId})`);
    return true;
  } catch (error) {
    console.error(`❌ Failed moderation email (${subject}) to ${to}:`, error);
    return false;
  }
}

async function countUnreadIncomingMessages(userId) {
  const snapshot = await admin.firestore()
      .collection('users')
      .doc(userId)
      .collection('incomingMessages')
      .get();

  let unreadCount = 0;
  snapshot.forEach((doc) => {
    const data = doc.data();
    if (data.isRead !== true) {
      unreadCount += 1;
    }
  });
  return unreadCount;
}

/** Presence older than this is treated as stale (force-quit often skips background writes). */
const APP_PRESENCE_FRESH_SECONDS = 45;

function isAppPresenceFresh(userData, maxAgeSeconds = APP_PRESENCE_FRESH_SECONDS) {
  if (!userData || userData.appIsActive !== true) {
    return false;
  }

  const updatedAt = userData.appStateUpdatedAt || 0;
  const ageSeconds = (Date.now() / 1000) - updatedAt;
  return ageSeconds < maxAgeSeconds;
}

function isRecipientActivelyInConversation(recipientData, senderId) {
  const openConversationUserId = recipientData.openConversationUserId;
  if (openConversationUserId !== senderId) {
    return false;
  }

  return isAppPresenceFresh(recipientData);
}

function shouldSkipMessageNotification(recipientData, senderId) {
  // Only suppress when the recipient is *freshly* active in the right place.
  // Stale flags after force-quit must still deliver APNs + badge.
  if (isRecipientActivelyInConversation(recipientData, senderId)) {
    return true;
  }

  if (recipientData.messagesTabActive === true && isAppPresenceFresh(recipientData)) {
    return true;
  }

  return false;
}

// ✅ FIXED: sendMessageNotification function
exports.sendMessageNotification = onDocumentCreated(
  'users/{userId}/incomingMessages/{messageId}',
  async (event) => {
    try {
      // ✅ FIX: Get messageData from snapshot FIRST (before using it)
      // In v2, event.data is a QueryDocumentSnapshot, so we call .data() on it
      const messageData = event.data.data();
      const params = event.params;
      
      if (!messageData) {
        console.log('No message data found');
        return null;
      }

      const senderId = messageData.senderId;
      const recipientId = messageData.recipientId;
      const content = messageData.content || 'New message';
      const messageType = messageData.type || 'text';

      // Official SpectRoom messages already trigger moderation push + email.
      if (senderId === SPECTROOM_SYSTEM_UID) {
        console.log(`Skipping chat push for SpectRoom system message to ${recipientId}`);
        return null;
      }
      // Get recipient's FCM token and check if conversation is open
      const recipientDoc = await admin.firestore()
        .collection('users')
        .doc(recipientId)
        .get();
      
      if (!recipientDoc.exists) {
        console.log('Recipient not found');
        return null;
      }
      
      const recipientData = recipientDoc.data();
      const fcmToken = recipientData.fcmToken;
      
      if (!fcmToken) {
        console.log('No FCM token for recipient');
        return null;
      }
      
      // Skip when recipient is in the open chat or on the Messages tab
      if (shouldSkipMessageNotification(recipientData, senderId)) {
        console.log(`Skipping push notification for ${recipientId} (open chat or messages tab active)`);
        return null;
      }
      
      // Get sender's name
      const senderDoc = await admin.firestore()
        .collection('users')
        .doc(senderId)
        .get();
      
      const senderName = senderDoc.exists ? (senderDoc.data().name || 'Someone') : 'Someone';
      const senderFirstName = senderName.trim().split(/\s+/)[0] || 'Someone';
      
      const unreadCount = await countUnreadIncomingMessages(recipientId);
      
      // Keep badge count in Firestore so the app can recover if APNs badge is delayed
      await admin.firestore().collection('users').doc(recipientId).update({
        unreadBadgeCount: unreadCount,
      });
      
      // Prepare notification payload
      let messagePreview;
      if (messageType === 'image') {
        messagePreview = '📷 Photo';
      } else if (messageType === 'voice') {
        messagePreview = '🎤 Voice message';
      } else if (messageType === 'video') {
        messagePreview = '🎥 Video';
      } else {
        const text = content || 'New message';
        messagePreview = text.length > 50 ? text.substring(0, 50) + '...' : text;
      }
      const title = 'SpectRoom message!';
      const messageBody = `${senderFirstName}: ${messagePreview}`;
      
      const payload = {
        token: fcmToken,
        notification: {
          title: title,
          body: messageBody,
        },
        data: {
          type: 'message',
          senderId: senderId,
          messageId: params.messageId,
          badge: String(unreadCount),
          title: title,
          body: messageBody,
        },
        apns: {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
          },
          payload: {
            aps: {
              alert: {
                title: title,
                body: messageBody,
              },
              badge: unreadCount,
              sound: 'default',
            },
          },
        },
        android: {
          priority: 'high',
          notification: {
            title: title,
            body: messageBody,
            sound: 'default',
            notificationCount: unreadCount,
          },
        },
      };
      
      // Send notification
      try {
        await admin.messaging().send(payload);
        console.log(`✅ Message notification sent successfully (badge: ${unreadCount})`);
      } catch (error) {
        // If it's an APNs auth error, log helpful message
        if (error.code === 'messaging/third-party-auth-error') {
          console.error('❌ APNs authentication error. Please configure APNs key in Firebase Console.');
          console.error('   See: https://console.firebase.google.com/project/spectroom-553a0/settings/cloudmessaging');
        }
        throw error;
      }
      
      return null;
    } catch (error) {
      console.error('❌ Error sending message notification:', error);
      return null;
    }
  });

function latestPositiveSwipeAction(swipesSnapshot) {
  let latestAction = null;
  let latestCreatedAt = 0;

  swipesSnapshot.forEach((doc) => {
    const data = doc.data();
    const action = data.action;
    const createdAt = data.createdAt || 0;
    if (createdAt >= latestCreatedAt) {
      latestCreatedAt = createdAt;
      latestAction = action;
    }
  });

  if (latestAction === 'like' || latestAction === 'super_like') {
    return latestAction;
  }
  return null;
}

// Creates a match for both users when a mutual like is detected server-side.
exports.createMatchOnMutualLike = onDocumentCreated(
    'users/{userId}/swipes/{swipeId}',
    async (event) => {
      try {
        const swipeData = event.data.data();
        const fromUserId = event.params.userId;
        const toUserId = swipeData?.toUserId;
        const action = swipeData?.action;

        if (!toUserId || (action !== 'like' && action !== 'super_like')) {
          return null;
        }

        const reciprocalSnapshot = await admin.firestore()
            .collection('users')
            .doc(toUserId)
            .collection('swipes')
            .where('toUserId', '==', fromUserId)
            .get();

        if (!latestPositiveSwipeAction(reciprocalSnapshot)) {
          console.log(`💕 No reciprocal like yet for ${fromUserId} <-> ${toUserId}`);
          return null;
        }

        const sortedIds = [fromUserId, toUserId].sort();
        const matchId = `${sortedIds[0]}_${sortedIds[1]}`;

        const matchData = {
          id: matchId,
          user1Id: sortedIds[0],
          user2Id: sortedIds[1],
          matchedAt: Date.now() / 1000,
          isActive: true,
          lastMessageAt: null,
          conversationId: admin.firestore().collection('_').doc().id,
        };

        for (const userId of sortedIds) {
          const matchRef = admin.firestore()
              .collection('users')
              .doc(userId)
              .collection('matches')
              .doc(matchId);
          const existing = await matchRef.get();
          if (!existing.exists) {
            await matchRef.set(matchData);
            console.log(`✅ Created match ${matchId} for user ${userId}`);
          }
        }

        return null;
      } catch (error) {
        console.error('❌ Error creating match on mutual like:', error);
        return null;
      }
    });

// ✅ FIXED: sendMatchNotification function
exports.sendMatchNotification = onDocumentCreated(
  'users/{userId}/matches/{matchId}',
  async (event) => {
    try {
      // ✅ FIX: Get matchData from snapshot FIRST
      // In v2, event.data is a QueryDocumentSnapshot, so we call .data() on it
      const matchData = event.data.data();
      const params = event.params;
      
      if (!matchData) {
        console.log('No match data found');
        return null;
      }

      const userId = params.userId;
      // Match data uses user1Id and user2Id (not userId1 and userId2)
      const otherUserId = matchData.user1Id === userId ? matchData.user2Id : matchData.user1Id;
      
      // Get user's FCM token
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(userId)
        .get();
      
      if (!userDoc.exists) {
        console.log('User not found');
        return null;
      }
      
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;
      
      if (!fcmToken) {
        console.log('No FCM token for user');
        return null;
      }
      
      // Check if app is freshly active - don't send push if in-app popup will show
      if (isAppPresenceFresh(userData)) {
        console.log(`App is freshly active for user ${userId}, skipping push notification (in-app popup will show instead)`);
        return null;
      }
      
      // Get other user's name
      const otherUserDoc = await admin.firestore()
        .collection('users')
        .doc(otherUserId)
        .get();
      
      const otherUserName = otherUserDoc.exists ? (otherUserDoc.data().name || 'Someone') : 'Someone';
      
      // Prepare notification payload
      const payload = {
        notification: {
          title: "It's a match! 💕",
          body: `You and ${otherUserName} like each other!`,
        },
        android: {
          notification: {
            sound: 'default',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
        data: {
          type: 'match',
          matchId: params.matchId,
          otherUserId: otherUserId,
        },
        token: fcmToken,
      };
      
      // Send notification
      try {
        await admin.messaging().send(payload);
        console.log('✅ Match notification sent successfully');
      } catch (error) {
        // If it's an APNs auth error, log helpful message
        if (error.code === 'messaging/third-party-auth-error') {
          console.error('❌ APNs authentication error. Please configure APNs key in Firebase Console.');
          console.error('   See: https://console.firebase.google.com/project/spectroom-553a0/settings/cloudmessaging');
        }
        throw error;
      }
      
      return null;
    } catch (error) {
      console.error('❌ Error sending match notification:', error);
      return null;
    }
  });

// Dev-only: wipe all match documents for every user.
exports.clearAllMatchesAdmin = onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Use POST');
    return;
  }

  const secret = req.query.secret || req.headers['x-admin-secret'];
  if (secret !== 'spectroom-dev-clear-matches') {
    res.status(403).send('Forbidden');
    return;
  }

  try {
    const db = admin.firestore();
    const usersSnapshot = await db.collection('users').get();
    let totalDeleted = 0;

    for (const userDoc of usersSnapshot.docs) {
      const matchesSnapshot = await userDoc.ref.collection('matches').get();
      if (matchesSnapshot.empty) {
        continue;
      }

      const batchSize = 450;
      const docs = matchesSnapshot.docs;
      for (let i = 0; i < docs.length; i += batchSize) {
        const batch = db.batch();
        docs.slice(i, i + batchSize).forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
      }

      totalDeleted += matchesSnapshot.size;
      console.log(`Deleted ${matchesSnapshot.size} match(es) for user ${userDoc.id}`);
    }

    console.log(`✅ Cleared ${totalDeleted} match document(s) total`);
    res.json({success: true, deleted: totalDeleted, users: usersSnapshot.size});
  } catch (error) {
    console.error('❌ Failed to clear matches:', error);
    res.status(500).json({success: false, error: error.message});
  }
});

/**
 * Hard-deletes accounts soft-deleted at least 14 days ago.
 * Soft-delete fields on users/{uid}: isDeleted, deletedAt, scheduledHardDeleteAt.
 * Soft-delete also writes deletedEmails/{email}.
 * Admin revive (within 14 days): remove isDeleted, deletedAt, and scheduledHardDeleteAt
 * from the Firestore user document, and delete deletedEmails/{email},
 * so the user can sign in again with the same credentials.
 */
async function hardDeleteUserAccount(userId) {
  const db = admin.firestore();
  const userRef = db.collection('users').doc(userId);
  const userSnap = await userRef.get();
  const userData = userSnap.exists ? (userSnap.data() || {}) : {};

  let normalizedEmail = String(userData.email || '').trim().toLowerCase();
  try {
    const authUser = await admin.auth().getUser(userId);
    if (authUser.email) {
      normalizedEmail = String(authUser.email).trim().toLowerCase();
    }
  } catch (error) {
    // Auth user may already be missing; continue with Firestore email if present.
  }

  // Best-effort Storage cleanup from known URL fields on the user doc.
  try {
    const bucket = admin.storage().bucket();
    const urls = [
      ...(Array.isArray(userData.photos) ? userData.photos : []),
      userData.profilePhotoURL,
    ].filter((url) => typeof url === 'string' && url.length > 0);

    await Promise.all(urls.map(async (url) => {
      try {
        const file = bucket.file(decodeURIComponent(
            url.split('/o/')[1]?.split('?')[0] || '',
        ));
        if (file.name) {
          await file.delete({ignoreNotFound: true});
        }
      } catch (error) {
        console.warn(`⚠️ Failed deleting storage object from ${url}:`, error.message);
      }
    }));
    console.log(`🗑️ Deleted ${urls.length} Storage URL(s) for ${userId}`);
  } catch (error) {
    console.warn(`⚠️ Storage cleanup skipped/failed for ${userId}:`, error.message);
  }

  if (normalizedEmail) {
    try {
      await db.collection('deletedEmails').doc(normalizedEmail).delete();
      console.log(`🗑️ Removed deletedEmails registry for ${normalizedEmail}`);
    } catch (error) {
      console.warn(`⚠️ Failed removing deletedEmails for ${normalizedEmail}:`, error.message);
    }
  }

  try {
    await admin.firestore().recursiveDelete(userRef);
    console.log(`🗑️ Deleted Firestore data for ${userId}`);
  } catch (error) {
    console.error(`❌ Failed Firestore recursive delete for ${userId}:`, error);
    throw error;
  }

  try {
    await admin.auth().deleteUser(userId);
    console.log(`🗑️ Deleted Auth user ${userId}`);
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      console.log(`ℹ️ Auth user ${userId} already missing`);
    } else {
      throw error;
    }
  }
}

/**
 * Used during sign-up to block emails that belong to soft-deleted accounts
 * still within the 14-day retention window.
 * Must be publicly invokable because sign-up happens while logged out.
 */
exports.checkEmailPendingDeletion = onCall({invoker: 'public'}, async (request) => {
  const email = String(request.data?.email || '').trim().toLowerCase();
  if (!email.includes('@')) {
    throw new HttpsError('invalid-argument', 'Valid email required');
  }

  const db = admin.firestore();

  function unixSeconds(value) {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    if (value && typeof value.toMillis === 'function') {
      return value.toMillis() / 1000;
    }
    if (value && typeof value._seconds === 'number') {
      return value._seconds;
    }
    if (value && typeof value.seconds === 'number') {
      return value.seconds;
    }
    return null;
  }

  function pendingDeletionPayload(data = {}) {
    return {
      pendingDeletion: true,
      deletedAt: unixSeconds(data.deletedAt),
      scheduledHardDeleteAt: unixSeconds(data.scheduledHardDeleteAt),
    };
  }

  // 1) Fast path: deletedEmails registry written during soft-delete.
  const registry = await db.collection('deletedEmails').doc(email).get();
  if (registry.exists) {
    return pendingDeletionPayload(registry.data() || {});
  }

  // 2) Auth user still exists and Firestore marks that uid as soft-deleted.
  try {
    const authUser = await admin.auth().getUserByEmail(email);
    const userDoc = await db.collection('users').doc(authUser.uid).get();
    if (userDoc.exists && userDoc.data()?.isDeleted === true) {
      // Backfill registry for older soft-deletes.
      const data = userDoc.data() || {};
      await db.collection('deletedEmails').doc(email).set({
        uid: authUser.uid,
        email,
        deletedAt: data.deletedAt || Date.now() / 1000,
        scheduledHardDeleteAt: data.scheduledHardDeleteAt || null,
      }, {merge: true});
      return pendingDeletionPayload({
        deletedAt: data.deletedAt || Date.now() / 1000,
        scheduledHardDeleteAt: data.scheduledHardDeleteAt || null,
      });
    }
  } catch (error) {
    if (error.code !== 'auth/user-not-found') {
      console.error('checkEmailPendingDeletion auth lookup failed:', error);
    }
  }

  // 3) Fallback for soft-deleted users that predate the deletedEmails registry.
  const snapshot = await db.collection('users')
      .where('isDeleted', '==', true)
      .get();

  const matchingDoc = snapshot.docs.find((doc) => {
    const userEmail = String(doc.data()?.email || '').trim().toLowerCase();
    return userEmail === email;
  });

  if (matchingDoc) {
    const data = matchingDoc.data() || {};
    await db.collection('deletedEmails').doc(email).set({
      uid: matchingDoc.id,
      email,
      deletedAt: data.deletedAt || Date.now() / 1000,
      scheduledHardDeleteAt: data.scheduledHardDeleteAt || null,
    }, {merge: true});
    return pendingDeletionPayload({
      deletedAt: data.deletedAt || Date.now() / 1000,
      scheduledHardDeleteAt: data.scheduledHardDeleteAt || null,
    });
  }

  return {pendingDeletion: false};
});

exports.purgeDeletedAccounts = onSchedule('every 24 hours', async () => {
  const now = Date.now() / 1000;
  const snapshot = await admin.firestore()
      .collection('users')
      .where('isDeleted', '==', true)
      .get();

  let purged = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const scheduledAt = data.scheduledHardDeleteAt;
    if (typeof scheduledAt !== 'number' || scheduledAt > now) {
      continue;
    }

    try {
      await hardDeleteUserAccount(doc.id);
      purged += 1;
    } catch (error) {
      console.error(`❌ Failed to purge account ${doc.id}:`, error);
    }
  }

  console.log(`✅ purgeDeletedAccounts finished. Purged ${purged} of ${snapshot.size} soft-deleted account(s).`);
});

/**
 * Custom SpectRoom password-reset email (Forgot password).
 * Uses Admin SDK generatePasswordResetLink, then branded mail via Gmail.
 */
exports.sendSpectRoomPasswordResetEmail = onCall(
    {
      invoker: 'public',
      secrets: [welcomeEmailUser, welcomeEmailPass],
    },
    async (request) => {
      const email = String(request.data?.email || '').trim().toLowerCase();
      if (!email.includes('@')) {
        throw new HttpsError('invalid-argument', 'Valid email required');
      }

      let resetLink;
      try {
        resetLink = await admin.auth().generatePasswordResetLink(email);
      } catch (error) {
        const code = String(error?.code || '');
        if (code === 'auth/user-not-found') {
          console.log(`sendSpectRoomPasswordResetEmail: no Auth user for ${email}`);
          return {ok: true};
        }
        console.error(`sendSpectRoomPasswordResetEmail: link failed for ${email}:`, error);
        throw new HttpsError('internal', 'Could not create password reset link');
      }

      const transporter = createSpectRoomTransporter();
      const fromAddress = welcomeEmailUser.value();
      const safeEmail = escapeHtml(email);
      const safeLink = escapeHtml(resetLink);
      const year = new Date().getFullYear();

      const mailOptions = {
        from: `"SpectRoom" <${fromAddress}>`,
        to: email,
        subject: 'Reset password for SpectRoom account',
        attachments: [spectRoomLogoAttachment()],
        text: [
          'SpectRoom',
          '',
          'Reset Your Password',
          '',
          'Hi there,',
          '',
          `We received a request to reset the password for your SpectRoom account (${email}).`,
          '',
          `Reset Password: ${resetLink}`,
          '',
          'This link will expire in 1 hour.',
          '',
          'If you didn\'t request a password reset, you can safely ignore this email, your account is secure.',
          '',
          `© ${year} SpectRoom. All rights reserved.`,
        ].join('\n'),
        html: wrapSpectRoomEmailHtml({
          pageTitle: 'Reset password for SpectRoom account',
          heading: 'Reset Your Password',
          bodyHtml: `
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                Hi there,
              </p>
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                We received a request to reset the password for your SpectRoom account
                (<a href="mailto:${safeEmail}" style="color:#007AFF;text-decoration:none;">${safeEmail}</a>).
              </p>
              ${spectRoomCtaButton(safeLink, 'Reset Password')}
              <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#8e8e93;">
                This link will expire in 1 hour.
              </p>
              <p style="margin:0 0 8px;font-size:14px;line-height:1.6;color:#8e8e93;">
                If you didn't request a password reset, you can safely ignore this email, your account is secure.
              </p>
          `,
        }),
      };

      try {
        await transporter.sendMail(mailOptions);
        console.log(`✅ Password reset email sent to ${email}`);
      } catch (error) {
        console.error(`❌ Failed sending password reset email to ${email}:`, error);
        throw new HttpsError('internal', 'Could not send password reset email');
      }

      return {ok: true};
    },
);

/**
 * Branded SpectRoom email-verification message (MFA prerequisite).
 * Uses Admin SDK generateEmailVerificationLink + the same card template as welcome mail.
 */
exports.sendSpectRoomEmailVerificationEmail = onCall(
    {
      invoker: 'public',
      secrets: [welcomeEmailUser, welcomeEmailPass],
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'Sign in required');
      }

      let authUser;
      try {
        authUser = await admin.auth().getUser(request.auth.uid);
      } catch (error) {
        console.error('sendSpectRoomEmailVerificationEmail: getUser failed', error);
        throw new HttpsError('not-found', 'User not found');
      }

      const email = String(authUser.email || '').trim();
      if (!email.includes('@')) {
        throw new HttpsError('failed-precondition', 'Account has no email');
      }
      if (authUser.emailVerified) {
        return {ok: true, alreadyVerified: true};
      }

      let verifyLink;
      try {
        verifyLink = await admin.auth().generateEmailVerificationLink(email, {
          url: 'https://spectroom-553a0.firebaseapp.com/auth/action.html',
          handleCodeInApp: false,
        });
        verifyLink = toSpectRoomAuthActionLink(verifyLink);
      } catch (error) {
        const code = String(error?.code || '');
        console.error(`sendSpectRoomEmailVerificationEmail: link failed for ${email}:`, error);
        if (code === 'auth/too-many-requests') {
          throw new HttpsError(
              'resource-exhausted',
              'Too many verification emails. Wait a few minutes and try again.',
          );
        }
        throw new HttpsError('internal', 'Could not create verification link');
      }

      const displayName = String(authUser.displayName || '').trim();
      const firstName = displayName.split(/\s+/)[0] || email.split('@')[0] || 'there';
      const safeFirstName = escapeHtml(firstName);
      const safeLink = escapeHtml(verifyLink);
      const fromAddress = welcomeEmailUser.value();
      const year = new Date().getFullYear();
      const transporter = createSpectRoomTransporter();

      const mailOptions = {
        from: `"SpectRoom" <${fromAddress}>`,
        to: email,
        subject: 'Verify your email for SpectRoom',
        attachments: spectRoomEmailAttachments(),
        text: [
          'SpectRoom',
          '',
          'Verify your email',
          '',
          `Hi ${firstName},`,
          '',
          'Please verify your email to complete your SpectRoom registration. Once verified, we’ll secure your account with two-factor authentication via your phone number.',
          '',
          `Confirm My Email: ${verifyLink}`,
          '',
          'If you didn\'t create a SpectRoom account, you can safely ignore this email.',
          '',
          'The SpectRoom team',
          '',
          `© ${year} SpectRoom. All rights reserved.`,
        ].join('\n'),
        html: wrapSpectRoomEmailHtml({
          pageTitle: 'Verify your email for SpectRoom',
          heading: 'Verify your email',
          bodyHtml: `
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                Hi ${safeFirstName},
              </p>
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                Please verify your email to complete your SpectRoom registration. Once verified, we’ll secure your account with two-factor authentication via your phone number.
              </p>
              ${spectRoomCtaButton(safeLink, 'Confirm My Email')}
              <p style="margin:0 0 16px;font-size:14px;line-height:1.6;color:#8e8e93;">
                If you didn't create a SpectRoom account, you can safely ignore this email.
              </p>
              <p style="margin:0 0 8px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                The SpectRoom team
              </p>
          `,
        }),
      };

      try {
        await transporter.sendMail(mailOptions);
        console.log(`✅ Email verification sent to ${email} (uid=${request.auth.uid})`);
      } catch (error) {
        console.error(`❌ Failed sending email verification to ${email}:`, error);
        throw new HttpsError('internal', 'Could not send verification email');
      }

      return {ok: true};
    },
);

/**
 * Sends the branded welcome email after email verification + SMS MFA enrollment.
 * Idempotent via users/{uid}.welcomeEmailSentAt.
 *
 * Replaces the old Auth onCreate trigger (sendWelcomeEmail), which fired too early.
 *
 * Deploy:
 *   firebase deploy --only functions:sendSpectRoomWelcomeEmail
 * and delete the old trigger if it still exists:
 *   firebase functions:delete sendWelcomeEmail --region us-central1
 */
async function deliverSpectRoomWelcomeEmail(authUser) {
  const email = String(authUser.email || '').trim();
  if (!email.includes('@')) {
    throw new HttpsError('failed-precondition', 'Account has no email');
  }

  const displayName = String(authUser.displayName || '').trim();
  const firstName = displayName.split(/\s+/)[0] || email.split('@')[0] || 'there';
  const safeFirstName = escapeHtml(firstName);
  const fromAddress = welcomeEmailUser.value();
  const year = new Date().getFullYear();
  const transporter = createSpectRoomTransporter();

  const mailOptions = {
    from: `"SpectRoom" <${fromAddress}>`,
    to: email,
    subject: 'Welcome to SpectRoom',
    attachments: [spectRoomLogoAttachment()],
    text: [
      'SpectRoom',
      '',
      'Welcome to SpectRoom',
      '',
      `Hi ${firstName},`,
      '',
      'Welcome to SpectRoom :)',
      '',
      'Complete your profile, set your energy level, and start discovering people nearby.',
      '',
      'If you have any questions you can contact SpectRoom support in this link:',
      'Contact support: spectroom.support@gmail.com',
      '',
      'The SpectRoom team',
      '',
      `© ${year} SpectRoom. All rights reserved.`,
    ].join('\n'),
    html: wrapSpectRoomEmailHtml({
      pageTitle: 'Welcome to SpectRoom',
      heading: 'Welcome to SpectRoom',
      bodyHtml: `
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                Hi ${safeFirstName},
              </p>
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                Welcome to SpectRoom :)
              </p>
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                Complete your profile, set your energy level, and start discovering people nearby.
              </p>
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                If you have any questions you can contact SpectRoom support in this link:
              </p>
              ${spectRoomCtaButton('mailto:spectroom.support@gmail.com', 'Contact support')}
              <p style="margin:0 0 8px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                The SpectRoom team
              </p>
          `,
    }),
  };

  await transporter.sendMail(mailOptions);
  console.log(`✅ Welcome email sent to ${email} (uid=${authUser.uid})`);
}


/**
 * Branded "2-step verification is on" email (same card template as welcome).
 * Firebase Auth still sends its own system MFA notice (cannot be disabled);
 * this is the SpectRoom-branded security confirmation.
 */
async function deliverSpectRoomMfaEnrolledEmail(authUser, {phoneE164} = {}) {
  const email = String(authUser.email || '').trim();
  if (!email.includes('@')) {
    throw new HttpsError('failed-precondition', 'Account has no email');
  }

  const displayName = String(authUser.displayName || '').trim();
  const firstName = displayName.split(/\s+/)[0] || email.split('@')[0] || 'there';
  const safeFirstName = escapeHtml(firstName);

  let phone = String(phoneE164 || '').trim();
  if (!phone) {
    const factors = authUser.multiFactor?.enrolledFactors || [];
    const phoneFactor = factors.find((f) => f.phoneNumber) || factors[0];
    phone = String(phoneFactor?.phoneNumber || '').trim();
  }
  const digits = phone.replace(/\D/g, '');
  const last4 = digits.slice(-4) || '••••';
  const safeLast4 = escapeHtml(last4);

  const fromAddress = welcomeEmailUser.value();
  const year = new Date().getFullYear();
  const transporter = createSpectRoomTransporter();

  const mailOptions = {
    from: `"SpectRoom" <${fromAddress}>`,
    to: email,
    subject: '2-step verification is on for SpectRoom',
    attachments: [spectRoomLogoAttachment()],
    text: [
      'SpectRoom',
      '',
      '2-step verification is on',
      '',
      `Hi ${firstName},`,
      '',
      `SMS 2-step verification is now enabled on your SpectRoom account for the phone number ending in ${last4}.`,
      '',
      'If you did not enable this, contact SpectRoom support right away:',
      'Contact support: spectroom.support@gmail.com',
      '',
      'The SpectRoom team',
      '',
      `© ${year} SpectRoom. All rights reserved.`,
    ].join('\n'),
    html: wrapSpectRoomEmailHtml({
      pageTitle: '2-step verification is on for SpectRoom',
      heading: '2-step verification is on',
      bodyHtml: `
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                Hi ${safeFirstName},
              </p>
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                SMS 2-step verification is now enabled on your SpectRoom account for the phone number ending in <strong>${safeLast4}</strong>.
              </p>
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                If you did not enable this, contact SpectRoom support right away:
              </p>
              ${spectRoomCtaButton('mailto:spectroom.support@gmail.com', 'Contact support')}
              <p style="margin:0 0 8px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                The SpectRoom team
              </p>
          `,
    }),
  };

  await transporter.sendMail(mailOptions);
  console.log(`✅ MFA enrolled email sent to ${email} (uid=${authUser.uid})`);
}

exports.sendSpectRoomWelcomeEmail = onCall(
    {
      invoker: 'public',
      secrets: [welcomeEmailUser, welcomeEmailPass],
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'Sign in required');
      }

      const uid = request.auth.uid;
      const userRef = admin.firestore().collection('users').doc(uid);

      let authUser;
      try {
        authUser = await admin.auth().getUser(uid);
      } catch (error) {
        console.error('sendSpectRoomWelcomeEmail: getUser failed', error);
        throw new HttpsError('not-found', 'User not found');
      }

      if (!authUser.emailVerified) {
        throw new HttpsError(
            'failed-precondition',
            'Verify your email before receiving the welcome email',
        );
      }

      const enrolledFactors = authUser.multiFactor?.enrolledFactors || [];
      const userSnap = await userRef.get();
      const userData = userSnap.exists ? (userSnap.data() || {}) : {};
      const mfaEnrolledInFirestore = userData.mfaEnrolled === true;
      if (enrolledFactors.length < 1 && !mfaEnrolledInFirestore) {
        throw new HttpsError(
            'failed-precondition',
            'Complete SMS 2FA before receiving the welcome email',
        );
      }

      const phoneE164 = String(userData.phoneE164 || '').trim();
      const updates = {};
      let welcomeSent = Boolean(userData.welcomeEmailSentAt);
      let mfaEmailSent = Boolean(userData.mfaEnrolledEmailSentAt);

      if (!mfaEmailSent) {
        try {
          await deliverSpectRoomMfaEnrolledEmail(authUser, {phoneE164});
          updates.mfaEnrolledEmailSentAt = Date.now();
          mfaEmailSent = true;
        } catch (error) {
          if (error instanceof HttpsError) throw error;
          console.error(`❌ Failed sending MFA enrolled email for uid=${uid}:`, error);
          throw new HttpsError('internal', 'Could not send 2-step verification email');
        }
      } else {
        console.log(`sendSpectRoomWelcomeEmail: MFA email already sent for uid=${uid}`);
      }

      if (!welcomeSent) {
        try {
          await deliverSpectRoomWelcomeEmail(authUser);
          updates.welcomeEmailSentAt = Date.now();
          welcomeSent = true;
        } catch (error) {
          if (error instanceof HttpsError) throw error;
          console.error(`❌ Failed sending welcome email for uid=${uid}:`, error);
          throw new HttpsError('internal', 'Could not send welcome email');
        }
      } else {
        console.log(`sendSpectRoomWelcomeEmail: welcome already sent for uid=${uid}`);
      }

      if (Object.keys(updates).length > 0) {
        await userRef.set(updates, {merge: true});
      }

      return {
        ok: true,
        welcomeAlreadySent: Boolean(userData.welcomeEmailSentAt),
        mfaEmailAlreadySent: Boolean(userData.mfaEnrolledEmailSentAt),
        welcomeSent,
        mfaEmailSent,
      };
    },
);

/**
 * Branded plan-change / cancellation email (same card template as welcome).
 *
 * Client payload:
 *   changeType: "changed" | "cancelled"
 *   fromPlan: "Free" | "Pro" | "Premium"
 *   fromInterval: "monthly" | "yearly" | "" (omit for Free)
 *   toPlan / toInterval: same (for changed)
 *   accessUntil: "dd/MM/yyyy" (for cancelled)
 *
 * Deploy:
 *   firebase deploy --only functions:sendSpectRoomPlanChangeEmail
 */
function formatPlanLabel(plan, interval) {
  const planName = String(plan || '').trim() || 'Free';
  const intervalName = String(interval || '').trim().toLowerCase();
  if (!intervalName || planName.toLowerCase() === 'free') {
    return planName;
  }
  return `${intervalName} ${planName}`;
}

async function deliverSpectRoomPlanChangeEmail(authUser, payload = {}) {
  const email = String(authUser.email || '').trim();
  if (!email.includes('@')) {
    throw new HttpsError('failed-precondition', 'Account has no email');
  }

  const changeType = String(payload.changeType || '').trim().toLowerCase();
  if (changeType !== 'changed' && changeType !== 'cancelled') {
    throw new HttpsError('invalid-argument', 'changeType must be changed or cancelled');
  }

  const displayName = String(authUser.displayName || '').trim();
  const firstName = displayName.split(/\s+/)[0] || email.split('@')[0] || 'there';
  const safeFirstName = escapeHtml(firstName);

  const fromLabel = formatPlanLabel(payload.fromPlan, payload.fromInterval);
  const toLabel = formatPlanLabel(payload.toPlan, payload.toInterval);
  const accessUntil = String(payload.accessUntil || '').trim();
  const safeFrom = escapeHtml(fromLabel);
  const safeTo = escapeHtml(toLabel);
  const safeAccessUntil = escapeHtml(accessUntil);

  const isCancel = changeType === 'cancelled';
  const subject = isCancel
    ? 'Your SpectRoom subscription was cancelled'
    : 'Your SpectRoom plan was updated';
  const heading = isCancel
    ? 'Subscription cancelled'
    : 'Plan updated';

  const textLines = isCancel
    ? [
      'SpectRoom',
      '',
      heading,
      '',
      `Hi ${firstName},`,
      '',
      `You cancelled your ${fromLabel} plan.`,
      accessUntil
        ? `You will keep access until ${accessUntil}. After that your plan will be set to Free.`
        : 'You will keep access until the end of the current period. After that your plan will be set to Free.',
      '',
      'If you did not make this change, contact SpectRoom support:',
      'Contact support: spectroom.support@gmail.com',
      '',
      'The SpectRoom team',
    ]
    : [
      'SpectRoom',
      '',
      heading,
      '',
      `Hi ${firstName},`,
      '',
      `Your SpectRoom plan was changed from ${fromLabel} to ${toLabel}.`,
      '',
      'If you did not make this change, contact SpectRoom support:',
      'Contact support: spectroom.support@gmail.com',
      '',
      'The SpectRoom team',
    ];

  const bodyHtml = isCancel
    ? `
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                Hi ${safeFirstName},
              </p>
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                You cancelled your <strong>${safeFrom}</strong> plan.
              </p>
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                ${
                  accessUntil
                    ? `You will keep access until <strong>${safeAccessUntil}</strong>. After that your plan will be set to Free.`
                    : 'You will keep access until the end of the current period. After that your plan will be set to Free.'
                }
              </p>
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                If you did not make this change, contact SpectRoom support:
              </p>
              ${spectRoomCtaButton('mailto:spectroom.support@gmail.com', 'Contact support')}
              <p style="margin:0 0 8px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                The SpectRoom team
              </p>
          `
    : `
              <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                Hi ${safeFirstName},
              </p>
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                Your SpectRoom plan was changed from <strong>${safeFrom}</strong> to <strong>${safeTo}</strong>.
              </p>
              <p style="margin:0 0 28px;font-size:16px;line-height:1.6;color:#3a3a3c;">
                If you did not make this change, contact SpectRoom support:
              </p>
              ${spectRoomCtaButton('mailto:spectroom.support@gmail.com', 'Contact support')}
              <p style="margin:0 0 8px;font-size:16px;line-height:1.6;color:#1c1c1e;">
                The SpectRoom team
              </p>
          `;

  const fromAddress = welcomeEmailUser.value();
  const year = new Date().getFullYear();
  const transporter = createSpectRoomTransporter();

  await transporter.sendMail({
    from: `"SpectRoom" <${fromAddress}>`,
    to: email,
    subject,
    attachments: spectRoomEmailAttachments(),
    text: [
      ...textLines,
      '',
      `© ${year} SpectRoom. All rights reserved.`,
    ].join('\n'),
    html: wrapSpectRoomEmailHtml({
      pageTitle: subject,
      heading,
      bodyHtml,
    }),
  });

  console.log(
      `✅ Plan change email (${changeType}) sent to ${email} (uid=${authUser.uid})`,
  );
}

exports.sendSpectRoomPlanChangeEmail = onCall(
    {
      invoker: 'public',
      secrets: [welcomeEmailUser, welcomeEmailPass],
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'Sign in required');
      }

      const uid = request.auth.uid;
      let authUser;
      try {
        authUser = await admin.auth().getUser(uid);
      } catch (error) {
        console.error('sendSpectRoomPlanChangeEmail: getUser failed', error);
        throw new HttpsError('not-found', 'User not found');
      }

      try {
        await deliverSpectRoomPlanChangeEmail(authUser, request.data || {});
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        console.error(`❌ Failed sending plan change email for uid=${uid}:`, error);
        throw new HttpsError('internal', 'Could not send plan change email');
      }

      return {ok: true};
    },
);

// ─── Support message email notification ───
exports.onSupportMessage = functions
    .runWith({secrets: [welcomeEmailUser, welcomeEmailPass]})
    .firestore.document('supportMessages/{docId}')
    .onCreate(async (snap) => {
      const data = snap.data();
      const {topic, message, userName, userEmail, userId, ticketId} = data;

      const fromAddress = welcomeEmailUser.value();
      const transporter = nodemailer.createTransport({
        service: 'gmail',
        auth: {
          user: fromAddress,
          pass: welcomeEmailPass.value(),
        },
      });

      const ticketLabel = ticketId || snap.id;
      const mailOptions = {
        from: `"SpectRoom Support" <${fromAddress}>`,
        to: 'spectroom.support@gmail.com',
        subject: `[${ticketLabel}] [${topic || 'General'}] New support message from ${userName || 'Unknown'}`,
        text: [
          `Ticket: ${ticketLabel}`,
          `Topic: ${topic}`,
          `From: ${userName} (${userEmail || 'no email'})`,
          `User ID: ${userId}`,
          '',
          'Message:',
          message,
        ].join('\n'),
        html: `
          <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;line-height:1.6;color:#1c1c1e;max-width:560px;">
            <h2 style="margin:0 0 16px;">New Support Message</h2>
            <table style="border-collapse:collapse;margin-bottom:16px;">
              <tr><td style="padding:4px 12px 4px 0;font-weight:600;">Ticket</td><td>${escapeHtml(ticketLabel)}</td></tr>
              <tr><td style="padding:4px 12px 4px 0;font-weight:600;">Topic</td><td>${escapeHtml(topic)}</td></tr>
              <tr><td style="padding:4px 12px 4px 0;font-weight:600;">From</td><td>${escapeHtml(userName)} (${escapeHtml(userEmail || 'no email')})</td></tr>
              <tr><td style="padding:4px 12px 4px 0;font-weight:600;">User ID</td><td style="font-size:13px;color:#6c6c70;">${escapeHtml(userId)}</td></tr>
            </table>
            <div style="background:#f5f5f5;border-radius:8px;padding:16px;white-space:pre-wrap;">${escapeHtml(message)}</div>
            <p style="color:#6c6c70;font-size:13px;margin-top:16px;">Reply directly to this email to respond to the user, or view in <a href="https://console.firebase.google.com/project/spectroom-553a0/firestore/data/supportMessages/${snap.id}">Firebase Console</a>.</p>
          </div>
        `,
        replyTo: userEmail || undefined,
      };

      try {
        await transporter.sendMail(mailOptions);
        console.log(`Support email sent for doc ${snap.id}`);
      } catch (error) {
        console.error('Failed to send support email:', error);
      }

      return null;
    });

// ─── Admin moderation warning push + email ───
exports.onUserModerationWarning = onDocumentUpdated(
  {
    document: 'users/{userId}',
    secrets: [welcomeEmailUser, welcomeEmailPass],
  },
  async (event) => {
    try {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      const beforeWarning = before.pendingSystemWarning || null;
      const afterWarning = after.pendingSystemWarning || null;

      // Fire only when a warning is newly set or replaced with a different report.
      if (!afterWarning) {
        return null;
      }
      const beforeReportId = beforeWarning && (beforeWarning.notice_id || beforeWarning.report_id);
      const afterReportId = afterWarning.notice_id || afterWarning.report_id;
      if (beforeReportId && beforeReportId === afterReportId) {
        return null;
      }

      const userId = event.params.userId;
      const fcmToken = after.fcmToken;
      const title = 'Notice: Community Guidelines';
      const body = afterWarning.message
        || 'Your account was recently reported for content or behavior that violates our guidelines. Please keep interactions respectful to ensure SpectRoom remains safe for everyone. Repeated violations may result in account suspension.';

      // Persist in Messages as a non-replyable SpectRoom conversation.
      try {
        await writeSpectRoomSystemWarningMessage({
          userId,
          content: body,
          noticeId: afterWarning.notice_id || afterReportId,
          reportId: afterWarning.report_id || afterReportId,
        });
      } catch (messageError) {
        console.error(`Failed writing SpectRoom warning message for ${userId}:`, messageError);
      }

      await sendSpectRoomModerationEmail({
        userId,
        userData: after,
        subject: title,
        heading: title,
        paragraphs: [body],
        includeContactSupport: true,
      });

      if (!fcmToken) {
        console.log(`No FCM token for warned user ${userId}`);
        return null;
      }

      const payload = {
        token: fcmToken,
        notification: {
          title,
          body,
        },
        data: {
          type: 'moderation_warning',
          reportId: String(afterReportId || ''),
          title,
          body,
        },
        apns: {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
          },
          payload: {
            aps: {
              alert: {
                title,
                body,
              },
              sound: 'default',
            },
          },
        },
        android: {
          priority: 'high',
          notification: {
            title,
            body,
            sound: 'default',
          },
        },
      };

      await admin.messaging().send(payload);
      console.log(`✅ Moderation warning push sent to ${userId}`);
      return null;
    } catch (error) {
      console.error('Error sending moderation warning notification:', error);
      return null;
    }
  }
);

// ─── Admin moderation freeze / extend / lift push + email ───
exports.onUserModerationFreeze = onDocumentUpdated(
  {
    document: 'users/{userId}',
    secrets: [welcomeEmailUser, welcomeEmailPass],
  },
  async (event) => {
    try {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      const userId = event.params.userId;
      const fcmToken = after.fcmToken;

      const beforeUnfreeze = before.pendingAccountUnfreeze || null;
      const afterUnfreeze = after.pendingAccountUnfreeze || null;
      const beforeFreeze = before.pendingAccountFreeze || null;
      const afterFreeze = after.pendingAccountFreeze || null;

      let title = null;
      let body = null;
      let type = null;
      let reportId = '';
      let hours = '';
      let includeContactSupport = false;

      // Freeze lifted by admin
      if (afterUnfreeze) {
        const beforeNoticeId = beforeUnfreeze && beforeUnfreeze.notice_id;
        const afterNoticeId = afterUnfreeze.notice_id;
        if (!beforeNoticeId || beforeNoticeId !== afterNoticeId) {
          title = 'Account freeze lifted';
          body = afterUnfreeze.message
            || 'Your SpectRoom account freeze has been lifted. You can log in again.';
          type = 'moderation_unfreeze';
          includeContactSupport = false;
        }
      }

      // New freeze or extended freeze
      if (!title && afterFreeze) {
        const beforeReportId = beforeFreeze && beforeFreeze.report_id;
        const afterReportId = afterFreeze.report_id;
        const beforeUntil = beforeFreeze && beforeFreeze.freeze_until;
        const afterUntil = afterFreeze.freeze_until;
        const changed =
          !beforeReportId
          || beforeReportId !== afterReportId
          || beforeUntil !== afterUntil;

        if (changed) {
          const kind = afterFreeze.kind || 'new';
          const isExtended = kind === 'extended';
          title = isExtended ? 'Account freeze extended' : 'Account Temporarily Suspended';
          body = afterFreeze.message
            || (isExtended
              ? 'Your account freeze has been extended. Open SpectRoom for details.'
              : `Your account has been temporarily frozen for ${afterFreeze.hours || 24} hours. Open SpectRoom for details.`);
          type = isExtended ? 'moderation_freeze_extended' : 'moderation_freeze';
          reportId = String(afterReportId || '');
          hours = String(afterFreeze.hours || 24);
          includeContactSupport = true;
        }
      }

      if (!title || !body || !type) {
        return null;
      }

      await sendSpectRoomModerationEmail({
        userId,
        userData: after,
        subject: title,
        heading: title,
        paragraphs: [body],
        includeContactSupport,
      });

      if (!fcmToken) {
        console.log(`No FCM token for moderation push (${type}) user ${userId}`);
        return null;
      }

      const payload = {
        token: fcmToken,
        notification: {
          title,
          body,
        },
        data: {
          type,
          reportId,
          hours,
          title,
          body,
        },
        apns: {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
          },
          payload: {
            aps: {
              alert: {
                title,
                body,
              },
              sound: 'default',
            },
          },
        },
        android: {
          priority: 'high',
          notification: {
            title,
            body,
            sound: 'default',
          },
        },
      };

      await admin.messaging().send(payload);
      console.log(`✅ Moderation push (${type}) sent to ${userId}`);
      return null;
    } catch (error) {
      console.error('Error sending moderation freeze/unfreeze notification:', error);
      return null;
    }
  }
);

/**
 * Skip moderation pushes when the recipient device token is the same as the
 * acting admin's token (common when testing multiple accounts on one device).
 * The affected user still gets the in-app pending notice on next login.
 */
async function shouldSkipModerationPushForActor({ userId, fcmToken, actorUserId, type }) {
  if (!fcmToken) {
    return true;
  }
  if (!actorUserId) {
    return false;
  }
  if (actorUserId === userId) {
    console.log(`Skipping ${type} push for ${userId}: actor is the same user`);
    return true;
  }
  try {
    const actorSnap = await admin.firestore().collection('users').doc(actorUserId).get();
    const actorToken = actorSnap.exists ? (actorSnap.data().fcmToken || null) : null;
    if (actorToken && actorToken === fcmToken) {
      console.log(
        `Skipping ${type} push for ${userId}: FCM token currently belongs to acting admin ${actorUserId}`
      );
      return true;
    }
  } catch (error) {
    console.error(`Unable to verify actor token for ${type} push:`, error);
  }
  return false;
}

// ─── Admin permanent ban / ban-lift push + email ───
exports.onUserModerationBan = onDocumentUpdated(
  {
    document: 'users/{userId}',
    secrets: [welcomeEmailUser, welcomeEmailPass],
  },
  async (event) => {
    try {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      const userId = event.params.userId;
      const fcmToken = after.fcmToken || before.fcmToken;

      const beforeBan = before.pendingAccountBan || null;
      const afterBan = after.pendingAccountBan || null;
      const beforeUnban = before.pendingAccountUnban || null;
      const afterUnban = after.pendingAccountUnban || null;

      let title = null;
      let body = null;
      let type = null;
      let actorUserId = null;
      let includeContactSupport = false;

      // Ban lifted by admin
      if (afterUnban) {
        const beforeNoticeId = beforeUnban && beforeUnban.notice_id;
        const afterNoticeId = afterUnban.notice_id;
        if (!beforeNoticeId || beforeNoticeId !== afterNoticeId) {
          title = 'Account ban lifted';
          body = afterUnban.message
            || 'Your SpectRoom account ban has been lifted. You can log in again.';
          type = 'moderation_unban';
          actorUserId = afterUnban.lifted_by || afterUnban.liftedBy || null;
          includeContactSupport = false;
        }
      }

      // New permanent ban
      if (!title) {
        const becameBanned = after.isBanned === true && before.isBanned !== true;
        const banNoticeChanged =
          afterBan
          && (
            !beforeBan
            || beforeBan.notice_id !== afterBan.notice_id
          );

        if (becameBanned || banNoticeChanged) {
          title = 'Account Permanently Banned';
          body = (afterBan && afterBan.message)
            || 'Your SpectRoom account has been permanently banned for violating our Community Guidelines.\n\nYou will no longer be able to access this account. If you believe this was done in error, you can submit an appeal to support.';
          type = 'moderation_ban';
          actorUserId = (afterBan && (afterBan.banned_by || afterBan.bannedBy)) || null;
          includeContactSupport = true;
        }
      }

      if (!title || !body || !type) {
        return null;
      }

      // Always email the moderated user (even if push is skipped for shared-device FCM).
      await sendSpectRoomModerationEmail({
        userId,
        userData: after.email ? after : {...after, email: before.email},
        subject: title,
        heading: title,
        paragraphs: [body],
        includeContactSupport,
      });

      if (!fcmToken) {
        console.log(`No FCM token for moderation push (${type}) user ${userId}`);
        return null;
      }

      if (await shouldSkipModerationPushForActor({ userId, fcmToken, actorUserId, type })) {
        return null;
      }

      const payload = {
        token: fcmToken,
        notification: {
          title,
          body,
        },
        data: {
          type,
          title,
          body,
        },
        apns: {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
          },
          payload: {
            aps: {
              alert: {
                title,
                body,
              },
              sound: 'default',
            },
          },
        },
        android: {
          priority: 'high',
          notification: {
            title,
            body,
            sound: 'default',
          },
        },
      };

      await admin.messaging().send(payload);
      console.log(`✅ Moderation push (${type}) sent to ${userId}`);
      return null;
    } catch (error) {
      console.error('Error sending moderation ban/unban notification:', error);
      return null;
    }
  }
);


