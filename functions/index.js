const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();

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
      
      // Check if conversation with this sender is currently open
      const openConversationUserId = recipientData.openConversationUserId;
      if (openConversationUserId === senderId) {
        console.log(`Conversation with ${senderId} is currently open for recipient, skipping push notification`);
        return null;
      }
      
      // Get sender's name
      const senderDoc = await admin.firestore()
        .collection('users')
        .doc(senderId)
        .get();
      
      const senderName = senderDoc.exists ? (senderDoc.data().name || 'Someone') : 'Someone';
      
      // Prepare notification payload
      const messageBody = messageType === 'image' ? '📷 Photo' : (content.length > 50 ? content.substring(0, 50) + '...' : content);
      
      const payload = {
        notification: {
          title: `New message from ${senderName}`,
          body: messageBody,
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
          type: 'message',
          senderId: senderId,
          messageId: params.messageId,
        },
        token: fcmToken,
      };
      
      // Send notification
      try {
        await admin.messaging().send(payload);
        console.log('✅ Message notification sent successfully');
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
      
      // Check if app is active - don't send push notification if app is open
      const appIsActive = userData.appIsActive;
      if (appIsActive === true) {
        console.log(`App is active for user ${userId}, skipping push notification (in-app popup will show instead)`);
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

