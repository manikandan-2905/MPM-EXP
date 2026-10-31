const Order = require('../models/Order');
const Rider = require('../models/Rider');

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'mani2006';

// 1. Admin Authentication
exports.loginAdmin = async (req, res) => {
  try {
    const { password } = req.body;

    if (!password) {
      return res.status(400).json({ success: false, message: 'Admin password is required' });
    }

    if (password.trim() !== ADMIN_PASSWORD) {
      return res.status(401).json({ success: false, message: 'Incorrect admin password' });
    }

    return res.status(200).json({
      success: true,
      message: 'Admin authenticated successfully',
      token: 'admin_token_' + Date.now(),
      admin: {
        role: 'SUPER_ADMIN',
        title: 'ZIPPO Head Administrator',
      },
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 2. Admin Dashboard High-Level Metrics
exports.getDashboardStats = async (req, res) => {
  try {
    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const [
      totalOrders,
      liveOrdersCount,
      deliveredOrdersCount,
      cancelledOrdersCount,
      totalRiders,
      onlineRidersCount,
      todayOrdersCount,
      todayDeliveredCount,
      revenueResult,
      todayRevenueResult,
      paymentSplitResult,
      todayPaymentSplitResult,
      riders,
    ] = await Promise.all([
      Order.countDocuments({}),
      Order.countDocuments({
        status: { $in: ['ORDER_PLACED', 'RIDER_ASSIGNED', 'ITEM_PURCHASED', 'ON_THE_WAY'] },
      }),
      Order.countDocuments({ status: 'DELIVERED' }),
      Order.countDocuments({ status: 'CANCELLED' }),
      Rider.countDocuments({}),
      Rider.countDocuments({ isOnline: true }),
      Order.countDocuments({ createdAt: { $gte: startOfToday } }),
      Order.countDocuments({ status: 'DELIVERED', updatedAt: { $gte: startOfToday } }),
      Order.aggregate([
        { $match: { status: 'DELIVERED' } },
        { $group: { _id: null, totalFare: { $sum: '$fare' } } },
      ]),
      Order.aggregate([
        { $match: { status: 'DELIVERED', updatedAt: { $gte: startOfToday } } },
        { $group: { _id: null, totalFare: { $sum: '$fare' } } },
      ]),
      Order.aggregate([
        { $match: { status: 'DELIVERED' } },
        { $group: { _id: '$paymentMode', total: { $sum: '$fare' }, count: { $sum: 1 } } },
      ]),
      Order.aggregate([
        { $match: { status: 'DELIVERED', updatedAt: { $gte: startOfToday } } },
        { $group: { _id: '$paymentMode', total: { $sum: '$fare' }, count: { $sum: 1 } } },
      ]),
      Rider.find({}).sort({ isOnline: -1, totalDeliveries: -1 }).lean(),
    ]);

    const totalRevenue = revenueResult.length > 0 ? revenueResult[0].totalFare : 0;
    const todayRevenue = todayRevenueResult.length > 0 ? todayRevenueResult[0].totalFare : 0;

    let cashRevenue = 0;
    let upiRevenue = 0;
    for (const split of paymentSplitResult) {
      if ((split._id || '').toUpperCase() === 'UPI') {
        upiRevenue += split.total;
      } else {
        cashRevenue += split.total;
      }
    }

    let todayCashRevenue = 0;
    let todayUpiRevenue = 0;
    for (const split of todayPaymentSplitResult) {
      if ((split._id || '').toUpperCase() === 'UPI') {
        todayUpiRevenue += split.total;
      } else {
        todayCashRevenue += split.total;
      }
    }

    // Attach active trip info to each rider if any
    const activeOrders = await Order.find({
      status: { $in: ['RIDER_ASSIGNED', 'ITEM_PURCHASED', 'ON_THE_WAY'] },
      assignedRider: { $ne: null },
    }).lean();

    const riderActiveTripMap = {};
    for (const ord of activeOrders) {
      if (ord.assignedRider) {
        riderActiveTripMap[ord.assignedRider.toString()] = {
          orderId: ord._id,
          orderNumber: ord.orderNumber,
          status: ord.status,
          customerName: ord.customerName,
          dropAddress: ord.dropAddress,
          fare: ord.fare,
        };
      }
    }

    const enhancedRiders = riders.map((r) => ({
      ...r,
      activeTrip: riderActiveTripMap[r._id.toString()] || null,
    }));

    return res.status(200).json({
      success: true,
      stats: {
        totalOrders,
        liveOrdersCount,
        deliveredOrdersCount,
        cancelledOrdersCount,
        totalRiders,
        onlineRidersCount,
        totalRevenue,
        cashRevenue,
        upiRevenue,
        todayOrdersCount,
        todayDeliveredCount,
        todayRevenue,
        todayCashRevenue,
        todayUpiRevenue,
      },
      riders: enhancedRiders,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 3. Admin Live Orders View (all ongoing orders with assigned rider tracking)
exports.getLiveOrders = async (req, res) => {
  try {
    const liveOrders = await Order.find({
      status: { $in: ['ORDER_PLACED', 'RIDER_ASSIGNED', 'ITEM_PURCHASED', 'ON_THE_WAY'] },
    })
      .populate('assignedRider', 'name phone isOnline totalDeliveries')
      .sort({ createdAt: -1 });

    return res.status(200).json({
      success: true,
      count: liveOrders.length,
      orders: liveOrders,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 4. Admin Rider History (Delivered & Cancelled closed orders with date/month filtering & collection analytics)
exports.getRiderHistory = async (req, res) => {
  try {
    const { riderId, status, timeRange, month, year } = req.query;

    const filter = {
      status: { $in: ['DELIVERED', 'CANCELLED'] },
    };

    if (riderId && riderId !== 'all') {
      filter.assignedRider = riderId;
    }

    if (status && status !== 'all') {
      filter.status = status;
    }

    const now = new Date();

    // Specific Month & Year filter (e.g. Month = 10, Year = 2026)
    if (month && year) {
      const m = parseInt(month, 10) - 1; // 0-indexed month
      const y = parseInt(year, 10);
      const startOfMonth = new Date(y, m, 1);
      const endOfMonth = new Date(y, m + 1, 0, 23, 59, 59, 999);
      filter.createdAt = { $gte: startOfMonth, $lte: endOfMonth };
    } else if (timeRange === 'today') {
      const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      filter.createdAt = { $gte: startOfToday };
    } else if (timeRange === 'yesterday') {
      const startOfYesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
      const endOfYesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, -1);
      filter.createdAt = { $gte: startOfYesterday, $lte: endOfYesterday };
    } else if (timeRange === 'week') {
      const startOfWeek = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      filter.createdAt = { $gte: startOfWeek };
    } else if (timeRange === 'month') {
      const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
      filter.createdAt = { $gte: startOfMonth };
    }

    const historyOrders = await Order.find(filter)
      .populate('assignedRider', 'name phone')
      .sort({ updatedAt: -1, createdAt: -1 });

    let totalRevenue = 0;
    let cashCollection = 0;
    let upiCollection = 0;
    let deliveredCount = 0;
    let cancelledCount = 0;

    for (const o of historyOrders) {
      if (o.status === 'DELIVERED') {
        deliveredCount++;
        totalRevenue += o.fare || 0;
        if ((o.paymentMode || '').toUpperCase() === 'UPI') {
          upiCollection += o.fare || 0;
        } else {
          cashCollection += o.fare || 0;
        }
      } else if (o.status === 'CANCELLED') {
        cancelledCount++;
      }
    }

    return res.status(200).json({
      success: true,
      count: historyOrders.length,
      orders: historyOrders,
      summary: {
        totalOrders: historyOrders.length,
        deliveredCount,
        cancelledCount,
        totalRevenue,
        cashCollection,
        upiCollection,
      },
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 5. Admin List of All Riders
exports.getAllRiders = async (req, res) => {
  try {
    const riders = await Rider.find({}).sort({ isOnline: -1, totalDeliveries: -1 });
    return res.status(200).json({ success: true, riders });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
