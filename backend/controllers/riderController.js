const Rider = require('../models/Rider');
const Order = require('../models/Order');

// 1. Rider Login (Pre-seeded phone & password authentication)
exports.loginRider = async (req, res) => {
  try {
    const { phone, password, fcmToken } = req.body;

    if (!password) {
      return res.status(400).json({ success: false, message: 'Password is required' });
    }

    const cleanPass = password.toString().trim();
    let rider;

    // Special alias check for V Mani (supporting assigned passcode 83476 or legacy 82476)
    if (cleanPass === '83476' || cleanPass === '82476') {
      rider = await Rider.findOne({
        $or: [{ phone: '7639483476' }, { phone: '7639482476' }, { name: 'V Mani' }, { password: '83476' }],
      });
    }

    if (!rider) {
      if (phone && phone.trim()) {
        const cleanPhone = phone.trim();
        rider = await Rider.findOne({
          phone: cleanPhone,
          $or: [{ password: cleanPass }, { phone: { $regex: cleanPass + '$' } }],
        });
      } else {
        // Direct login by password (e.g. 5-digit rider pass)
        rider = await Rider.findOne({
          $or: [{ password: cleanPass }, { phone: { $regex: cleanPass + '$' } }],
        });
      }
    }

    if (!rider) {
      return res.status(401).json({
        success: false,
        message: 'Access Denied: Invalid rider password. Please check your assigned 5-digit code.',
      });
    }

    // Update FCM token if provided
    if (fcmToken) {
      rider.fcmToken = fcmToken;
      await rider.save();
    }

    return res.status(200).json({
      success: true,
      message: `Welcome back, ${rider.name}!`,
      rider,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 2. Toggle Online/Offline Status
exports.toggleOnlineStatus = async (req, res) => {
  try {
    const { riderId } = req.params;
    const { isOnline } = req.body;

    const rider = await Rider.findByIdAndUpdate(
      riderId,
      { isOnline: Boolean(isOnline) },
      { new: true }
    );

    if (!rider) {
      return res.status(404).json({ success: false, message: 'Rider not found' });
    }

    return res.status(200).json({
      success: true,
      message: `Status updated: Rider is now ${rider.isOnline ? 'ONLINE 🟢' : 'OFFLINE 🔴'}`,
      isOnline: rider.isOnline,
      rider,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 3. Get Active Online Riders Count (for Customer Top Bar Counter)
exports.getActiveRidersCount = async (req, res) => {
  try {
    const activeCount = await Rider.countDocuments({ isOnline: true });
    return res.status(200).json({
      success: true,
      activeRidersCount: activeCount,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 4. Get Rider Dashboard Stats & Profile
exports.getRiderProfile = async (req, res) => {
  try {
    const { riderId } = req.params;
    const rider = await Rider.findById(riderId);

    if (!rider) {
      return res.status(404).json({ success: false, message: 'Rider not found' });
    }

    return res.status(200).json({
      success: true,
      rider,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 5. Get Rider Current Active Order
exports.getRiderActiveOrder = async (req, res) => {
  try {
    const { riderId } = req.params;
    const activeOrder = await Order.findOne({
      assignedRider: riderId,
      status: { $in: ['RIDER_ASSIGNED', 'ITEM_PURCHASED', 'ON_THE_WAY'] },
    }).populate('assignedRider', 'name phone');

    return res.status(200).json({
      success: true,
      hasActiveOrder: !!activeOrder,
      order: activeOrder,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
