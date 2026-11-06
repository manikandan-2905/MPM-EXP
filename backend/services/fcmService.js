const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const NotificationTemp = require('../models/NotificationTemp');

let isFirebaseInitialized = false;

// Attempt Firebase initialization from environment variable or serviceAccountKey.json
const initFirebase = () => {
  if (isFirebaseInitialized) return;

  try {
    let serviceAccount = null;

    if (process.env.FIREBASE_SERVICE_ACCOUNT_BASE64) {
      const decoded = Buffer.from(process.env.FIREBASE_SERVICE_ACCOUNT_BASE64.trim(), 'base64').toString('utf8');
      serviceAccount = JSON.parse(decoded);
    } else if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON.trim());
    } else {
      const keyPath = process.env.FIREBASE_SERVICE_ACCOUNT_KEY || path.join(__dirname, '../serviceAccountKey.json');
      if (fs.existsSync(keyPath)) {
        serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
      }
    }

    if (serviceAccount) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      isFirebaseInitialized = true;
      console.log('[FCM Service]: Firebase Admin SDK initialized successfully.');
    } else {
      console.warn(`[FCM Service]: No Firebase credentials found. FCM will run in simulation mode.`);
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
        channelId: data.isRider
          ? 'zippo_rider_dispatch_alerts'
          : data.isAdmin
          ? 'zippo_admin_supervisor_alerts'
          : 'melapalayam_delivery_milestones',
        sound: 'default',
        priority: 'max',
        visibility: 'public',
        defaultSound: true,
        ticker: title,
        color: data.isRider ? '#22C55E' : data.isAdmin ? '#F59E0B' : '#76C457',
        // Distinctive heavy double-vibration for riders so it wakes up pocket even in silence/motion!
        defaultVibrateTimings: !data.isRider,
        ...(data.isRider
          ? { vibrateTimingsMillis: [0, 600, 200, 600, 200, 600, 400, 800] }
          : {}),
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

/**
 * Broadcasts a high-priority push notification to multiple FCM tokens in batches of 500.
 * Works even when the app is completely closed or screen is locked.
 *
 * @param {Object} params
 * @param {string[]} params.tokens - Array of FCM device tokens
 * @param {string} params.title - Notification title
 * @param {string} params.body - Notification body
 * @param {Object} params.data - Custom payload data
 * @param {string} params.actionUrl - Optional link to launch (e.g. APK update URL or shop link)
 */
const sendBroadcastNotification = async ({
  tokens = [],
  title,
  body,
  data = {},
  actionUrl = '',
}) => {
  if (!tokens || tokens.length === 0) {
    console.log(`[FCM Broadcast Simulated (No Tokens)]: [${title}] -> ${body}`);
    return { success: true, totalRecipients: 0, successCount: 0, failureCount: 0 };
  }

  // Deduplicate and filter empty tokens
  const uniqueTokens = [...new Set(tokens.filter(Boolean))];

  if (!isFirebaseInitialized) {
    console.log(`[FCM Broadcast Simulated (No Firebase Config)]: [${title}] -> ${body} to ${uniqueTokens.length} devices.`);
    return {
      success: true,
      simulated: true,
      totalRecipients: uniqueTokens.length,
      successCount: uniqueTokens.length,
      failureCount: 0,
    };
  }

  let totalSuccess = 0;
  let totalFailure = 0;
  const BATCH_SIZE = 500;

  for (let i = 0; i < uniqueTokens.length; i += BATCH_SIZE) {
    const batchTokens = uniqueTokens.slice(i, i + BATCH_SIZE);

    const message = {
      tokens: batchTokens,
      notification: {
        title,
        body,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        action_url: actionUrl || '',
        type: data.type || 'BROADCAST',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'melapalayam_delivery_milestones',
          sound: 'default',
          priority: 'max',
          visibility: 'public',
          defaultSound: true,
          defaultVibrateTimings: true,
          ticker: title,
        },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      totalSuccess += response.successCount;
      totalFailure += response.failureCount;
      console.log(`[FCM Batch Broadcast]: ${response.successCount} sent, ${response.failureCount} failed out of ${batchTokens.length}`);
    } catch (err) {
      console.error(`[FCM Batch Broadcast Error]: ${err.message}`);
      totalFailure += batchTokens.length;
    }
  }

  return {
    success: true,
    totalRecipients: uniqueTokens.length,
    successCount: totalSuccess,
    failureCount: totalFailure,
  };
};

/**
 * Sends a supervisor push notification to all logged-in Admin devices.
 * Clearly differentiated with 👑 [ADMIN] badge and gold color so it never conflicts with rider or customer alerts.
 */
const sendAdminSupervisorAlert = async ({ title, body, data = {} }) => {
  try {
    const Device = require('../models/Device');
    const adminDevices = await Device.find({ role: 'ADMIN', notificationsEnabled: true }).select('fcmToken');
    const tokens = [...new Set(adminDevices.map((d) => d.fcmToken).filter(Boolean))];

    if (tokens.length === 0) {
      console.log(`[Admin Alert Simulated (No Admin Devices)]: [👑 ADMIN: ${title}] -> ${body}`);
      return { success: true, simulated: true };
    }

    return await sendBroadcastNotification({
      tokens,
      title: `👑 [ADMIN] ${title}`,
      body,
      data: {
        ...data,
        isAdmin: 'true',
        role: 'ADMIN',
      },
      actionUrl: 'https://zippo-mpm.onrender.com',
    });
  } catch (err) {
    console.error('[Admin Alert Error]:', err.message);
    return { success: false, error: err.message };
  }
};

module.exports = {
  sendMilestoneNotification,
  sendBroadcastNotification,
  sendAdminSupervisorAlert,
};
