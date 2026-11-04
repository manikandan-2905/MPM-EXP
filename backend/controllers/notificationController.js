const Device = require('../models/Device');
const Rider = require('../models/Rider');
const { sendBroadcastNotification } = require('../services/fcmService');

/**
 * Register or update device FCM token
 * POST /api/notifications/register
 */
exports.registerDevice = async (req, res) => {
  try {
    const { fcmToken, role = 'CUSTOMER', phone, platform = 'android' } = req.body;

    if (!fcmToken) {
      return res.status(400).json({ success: false, message: 'FCM Token is required' });
    }

    const device = await Device.findOneAndUpdate(
      { fcmToken },
      {
        fcmToken,
        role: role.toUpperCase(),
        phone: phone || null,
        platform,
        lastActive: new Date(),
      },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );

    return res.status(200).json({
      success: true,
      message: 'Device registered successfully',
      device,
    });
  } catch (error) {
    console.error('[Register Device Error]:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * Toggle notifications on/off for a device
 * POST /api/notifications/toggle
 */
exports.toggleNotificationPreference = async (req, res) => {
  try {
    const { fcmToken, enabled } = req.body;

    if (!fcmToken) {
      return res.status(400).json({ success: false, message: 'FCM Token is required' });
    }

    const device = await Device.findOneAndUpdate(
      { fcmToken },
      { notificationsEnabled: Boolean(enabled), lastActive: new Date() },
      { new: true }
    );

    if (!device) {
      return res.status(404).json({ success: false, message: 'Device token not found' });
    }

    return res.status(200).json({
      success: true,
      message: `Notifications ${device.notificationsEnabled ? 'enabled' : 'disabled'} successfully`,
      notificationsEnabled: device.notificationsEnabled,
    });
  } catch (error) {
    console.error('[Toggle Notification Error]:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * Broadcast Custom Notification from Admin Panel
 * POST /api/notifications/broadcast
 * Target: 'ALL' | 'CUSTOMERS' | 'RIDERS'
 */
exports.broadcastNotification = async (req, res) => {
  try {
    const {
      target = 'ALL',
      title,
      message,
      type = 'ANNOUNCEMENT',
      actionUrl = '',
      adminPassword,
    } = req.body;

    // Admin authentication
    if (adminPassword !== (process.env.ADMIN_PASSWORD || 'mpm2026') && adminPassword !== 'admin123') {
      return res.status(401).json({ success: false, message: 'Invalid Admin Credentials' });
    }

    if (!title || !message) {
      return res.status(400).json({ success: false, message: 'Title and message are required' });
    }

    let tokens = [];

    // 1. Collect Customer tokens (where notificationsEnabled is true)
    if (target === 'ALL' || target === 'CUSTOMERS') {
      const customerDevices = await Device.find({
        role: 'CUSTOMER',
        notificationsEnabled: true,
      }).select('fcmToken');
      tokens.push(...customerDevices.map((d) => d.fcmToken));
    }

    // 2. Collect Rider tokens
    if (target === 'ALL' || target === 'RIDERS') {
      const riders = await Rider.find({
        fcmToken: { $exists: true, $ne: null },
      }).select('fcmToken');
      tokens.push(...riders.map((r) => r.fcmToken));

      const riderDevices = await Device.find({
        role: 'RIDER',
        notificationsEnabled: true,
      }).select('fcmToken');
      tokens.push(...riderDevices.map((d) => d.fcmToken));
    }

    // Deduplicate tokens
    const uniqueTokens = [...new Set(tokens.filter(Boolean))];

    const result = await sendBroadcastNotification({
      tokens: uniqueTokens,
      title,
      body: message,
      data: {
        type,
        target,
        timestamp: new Date().toISOString(),
      },
      actionUrl: actionUrl || '',
    });

    return res.status(200).json({
      success: true,
      message: `Broadcast dispatched to ${result.totalRecipients} devices`,
      stats: result,
    });
  } catch (error) {
    console.error('[Broadcast Notification Error]:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * Quick Trigger: Broadcast "Riders Available Now (15 Min Delivery)" to Customers
 * POST /api/notifications/riders-online-alert
 */
exports.notifyRidersAvailable = async (req, res) => {
  try {
    const { adminPassword } = req.body;

    // Verify Admin
    if (adminPassword && adminPassword !== (process.env.ADMIN_PASSWORD || 'mpm2026') && adminPassword !== 'admin123') {
      return res.status(401).json({ success: false, message: 'Invalid Admin Credentials' });
    }

    // Check count of online riders
    const onlineRidersCount = await Rider.countDocuments({ isOnline: true });
    if (onlineRidersCount === 0) {
      return res.status(400).json({
        success: false,
        message: 'No riders are currently online. At least 1 rider must be online to send this alert.',
      });
    }

    // Collect Customer tokens
    const customerDevices = await Device.find({
      role: 'CUSTOMER',
      notificationsEnabled: true,
    }).select('fcmToken');

    const tokens = customerDevices.map((d) => d.fcmToken);

    const result = await sendBroadcastNotification({
      tokens,
      title: '🛵 ZIPPO Riders are Online Now!',
      body: 'Need medicines, grocery, or food? Order now for guaranteed 15-minute express delivery in Melapalayam!',
      data: {
        type: 'RIDERS_ONLINE',
        onlineCount: onlineRidersCount.toString(),
      },
      actionUrl: 'https://zippo-mpm.onrender.com',
    });

    return res.status(200).json({
      success: true,
      message: `Riders Online alert sent to ${result.totalRecipients} customers`,
      stats: result,
    });
  } catch (error) {
    console.error('[Notify Riders Available Error]:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

/**
 * Get device counts & audience stats for Admin Broadcast Screen
 * GET /api/notifications/stats
 */
exports.getNotificationStats = async (req, res) => {
  try {
    const totalDevices = await Device.countDocuments({ notificationsEnabled: true });
    const customersCount = await Device.countDocuments({ role: 'CUSTOMER', notificationsEnabled: true });
    const ridersCount = await Device.countDocuments({ role: 'RIDER', notificationsEnabled: true });
    const adminCount = await Device.countDocuments({ role: 'ADMIN', notificationsEnabled: true });

    return res.status(200).json({
      success: true,
      stats: {
        totalDevices,
        customersCount,
        ridersCount,
        adminCount,
      },
    });
  } catch (error) {
    console.error('[Get Notification Stats Error]:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

