const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const NotificationTemp = require('../models/NotificationTemp');

let isFirebaseInitialized = false;

// Attempt Firebase initialization from environment variable or serviceAccountKey.json
const initFirebase = () => {
  if (isFirebaseInitialized) return;

  try {
    const keyPath = process.env.FIREBASE_SERVICE_ACCOUNT_KEY || path.join(__dirname, '../serviceAccountKey.json');
    if (fs.existsSync(keyPath)) {
      const serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      isFirebaseInitialized = true;
      console.log('[FCM Service]: Firebase Admin SDK initialized successfully.');
    } else {
      console.warn(`[FCM Service]: Service account file not found at ${keyPath}. FCM will run in simulation mode.`);
    }
  } catch (error) {
    console.error(`[FCM Service Init Error]: ${error.message}`);
  }
};

initFirebase();

/**
 * Sends a high-priority push notification to a recipient token,
 * including direct phone call actions and milestone data.
 * Also records a temporary notification in MongoDB with a 48h TTL index.
 *
 * @param {Object} params
 * @param {string} params.token - Recipient FCM device token
 * @param {string} params.title - Notification title
 * @param {string} params.body - Notification body
 * @param {Object} params.data - Custom payload (orderId, status, riderPhone, customerPhone)
 * @param {string} params.orderId - MongoDB Order ObjectId
 * @param {string} params.recipientPhone - Target user phone number
 */
const sendMilestoneNotification = async ({
  token,
  title,
  body,
  data = {},
  orderId = null,
  recipientPhone = '',
}) => {
  // 1. Record in temporary notifications collection (48-hour auto-purge TTL)
  if (orderId && recipientPhone) {
    try {
      await NotificationTemp.create({
        orderId,
        recipientPhone,
        title,
        message: body,
      });
    } catch (err) {
      console.error('[NotificationTemp Log Error]:', err.message);
    }
  }

  // 2. Dispatch FCM Push Notification
  if (!token) {
    console.log(`[FCM Simulated (No Token)]: [${title}] -> ${body}`);
    return { success: true, simulated: true };
  }

  if (!isFirebaseInitialized) {
    console.log(`[FCM Simulated (No Firebase Config)]: [${title}] -> ${body} to token: ${token.substring(0, 10)}...`);
    return { success: true, simulated: true };
  }

  const message = {
    token: token,
    notification: {
      title,
      body,
    },
    data: {
      ...data,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
      caller_phone: data.callerPhone || '',
      order_id: data.orderId ? data.orderId.toString() : '',
      status: data.status || '',
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'melapalayam_delivery_milestones',
        sound: 'default',
        priority: 'max',
        defaultVibrateTimings: true,
        // Direct Action: Call Rider or Call Customer
        ...(data.callerPhone
          ? {
              notificationActions: [
                {
                  action: 'ACTION_CALL_DIRECT',
                  title: `Call (${data.callerPhone})`,
                  icon: 'ic_call',
                },
              ],
            }
          : {}),
      },
    },
  };

  try {
    const response = await admin.messaging().send(message);
    console.log(`[FCM Sent Successfully]: ${response}`);
    return { success: true, messageId: response };
  } catch (error) {
    console.error(`[FCM Send Error]: ${error.message}`);
    return { success: false, error: error.message };
  }
};

module.exports = {
  sendMilestoneNotification,
};
