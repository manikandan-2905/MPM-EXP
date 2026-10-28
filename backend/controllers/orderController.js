const Order = require('../models/Order');
const Rider = require('../models/Rider');
const { sendMilestoneNotification } = require('../services/fcmService');

/**
 * Calculates fare according to the Melapalayam fare engine:
 * Base: ₹30 (first 2 km)
 * Incremental: ₹10/km beyond 2 km
 * Urgent surcharge: +₹15
 */
const calculateFare = (distanceKm = 2.0, isUrgent = false) => {
  const baseFare = 30;
  const extraKm = Math.max(0, distanceKm - 2.0);
  const distanceFare = Math.round(extraKm * 10);
  const urgentSurcharge = isUrgent ? 15 : 0;
  return baseFare + distanceFare + urgentSurcharge;
};

/**
 * Creates formatted WhatsApp Dispatch Ticket for sharing via native WhatsApp group
 */
const formatWhatsAppTicket = (order) => {
  const isPickup = order.orderType === 'PICKUP_DROP';
  const categoryIcon = isPickup ? '📦' : '🛒';
  const urgentTag = order.isUrgent ? '⚡ *URGENT ORDER* ⚡\n' : '';

  let body = '';
  if (isPickup) {
    body = `📍 *Pickup Landmark:* ${order.pickupAddress}
📞 *Sender Contact:* ${order.pickupPhone || order.customerPhone}
🏁 *Drop Landmark:* ${order.dropAddress}
📞 *Receiver Contact:* ${order.dropPhone || order.customerPhone}
📋 *Items / Note:* ${order.itemsList.join(', ') || 'N/A'}`;
  } else {
    body = `🏬 *Shop / Market:* ${order.shopName || 'Melapalayam Bazar'}
📝 *Items Checklist:*
${order.itemsList.map((item, idx) => `   ${idx + 1}. ${item}`).join('\n')}
💵 *Estimated Budget:* ₹${order.budget}
🏁 *Delivery Address:* ${order.dropAddress}
📞 *Customer Contact:* ${order.customerPhone}`;
  }

  return `🛵 *MELAPALAYAM DISPATCH ALERT* 🛵
${urgentTag}*Order ID:* ${order.orderNumber}
*Type:* ${categoryIcon} ${order.orderType === 'PICKUP_DROP' ? `Pickup & Drop (${order.category})` : 'Buy For Me'}
*Fare:* ₹${order.fare} (${order.estimatedDistanceKm} km est.)

${body}

*Customer:* ${order.customerName} (${order.customerPhone})
*Status:* 🟢 ORDER PLACED (Open for Riders)
_Tap below or open Rider APK to accept!_`;
};

// 1. Create Order (Guest Customer)
exports.createOrder = async (req, res) => {
  try {
    const {
      customerName,
      customerPhone,
      pickupPhone,
      dropPhone,
      orderType,
      category,
      itemsList,
      shopName,
      budget,
      isUrgent,
      pickupAddress,
      pickupCoords,
      dropAddress,
      dropCoords,
      estimatedDistanceKm,
      customerFcmToken,
    } = req.body;

    if (!customerName || !customerPhone || !dropAddress) {
      return res.status(400).json({ success: false, message: 'Missing mandatory customer or drop details' });
    }

    if (orderType === 'PICKUP_DROP' && !pickupAddress) {
      return res.status(400).json({ success: false, message: 'Pickup address is required for Pickup & Drop' });
    }

    const distance = estimatedDistanceKm ? Number(estimatedDistanceKm) : 2.0;
    const computedFare = calculateFare(distance, Boolean(isUrgent));

    const order = new Order({
      customerName,
      customerPhone,
      pickupPhone: pickupPhone || customerPhone,
      dropPhone: dropPhone || customerPhone,
      orderType,
      category: category || (orderType === 'BUY_FOR_ME' ? 'BuyForMe' : 'Custom'),
      itemsList: Array.isArray(itemsList) ? itemsList : [itemsList].filter(Boolean),
      shopName: shopName || '',
      budget: budget ? Number(budget) : 0,
      isUrgent: Boolean(isUrgent),
      pickupAddress: pickupAddress || shopName || 'Melapalayam Center',
      pickupCoords: pickupCoords || { lat: null, lng: null },
      dropAddress,
      dropCoords: dropCoords || { lat: null, lng: null },
      fare: computedFare,
      estimatedDistanceKm: distance,
      customerFcmToken: customerFcmToken || null,
      status: 'ORDER_PLACED',
    });

    await order.save();

    const whatsappTicket = formatWhatsAppTicket(order);

    return res.status(201).json({
      success: true,
      message: 'Order placed successfully',
      order,
      whatsappTicket,
    });
  } catch (error) {
    console.error('[Create Order Error]:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 2. Get Order by ID
exports.getOrderById = async (req, res) => {
  try {
    const order = await Order.findById(req.params.id).populate('assignedRider', 'name phone isOnline');
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }
    return res.status(200).json({ success: true, order });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 3. Get Orders for Customer Phone
exports.getCustomerOrders = async (req, res) => {
  try {
    const { phone } = req.params;
    const orders = await Order.find({ customerPhone: phone })
      .populate('assignedRider', 'name phone')
      .sort({ createdAt: -1 });
    return res.status(200).json({ success: true, orders });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 4. Get Available Orders for Riders
exports.getAvailableOrders = async (req, res) => {
  try {
    const orders = await Order.find({
      status: 'ORDER_PLACED',
      assignedRider: null,
    }).sort({ createdAt: -1 });

    return res.status(200).json({ success: true, count: orders.length, orders });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 5. Atomic Order Lock (Claim Order)
exports.claimOrder = async (req, res) => {
  try {
    const { orderId } = req.params;
    const { riderId } = req.body;

    if (!riderId) {
      return res.status(400).json({ success: false, message: 'riderId is required' });
    }

    const rider = await Rider.findById(riderId);
    if (!rider) {
      return res.status(404).json({ success: false, message: 'Rider not found' });
    }

    // Atomic find-and-update to prevent race condition when two riders tap simultaneously
    const order = await Order.findOneAndUpdate(
      {
        _id: orderId,
        assignedRider: null,
        status: 'ORDER_PLACED',
      },
      {
        assignedRider: riderId,
        status: 'RIDER_ASSIGNED',
      },
      { new: true }
    ).populate('assignedRider', 'name phone');

    if (!order) {
      return res.status(409).json({
        success: false,
        message: 'Order has already been claimed by another rider or is no longer available.',
      });
    }

    // Trigger High-Priority FCM push notification to Customer with Direct Phone Call action
    await sendMilestoneNotification({
      token: order.customerFcmToken,
      title: '🛵 Rider Assigned!',
      body: `${rider.name} has accepted your order #${order.orderNumber} and is heading to the pickup spot.`,
      data: {
        orderId: order._id.toString(),
        orderNumber: order.orderNumber,
        status: 'RIDER_ASSIGNED',
        callerPhone: rider.phone,
      },
      orderId: order._id,
      recipientPhone: order.customerPhone,
    });

    return res.status(200).json({
      success: true,
      message: 'Order locked and assigned successfully',
      order,
    });
  } catch (error) {
    console.error('[Claim Order Error]:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 6. Update Milestone Status ('ITEM_PURCHASED' | 'ON_THE_WAY')
exports.updateMilestone = async (req, res) => {
  try {
    const { orderId } = req.params;
    const { status, riderId } = req.body;

    const validMilestones = ['ITEM_PURCHASED', 'ON_THE_WAY'];
    if (!validMilestones.includes(status)) {
      return res.status(400).json({ success: false, message: `Invalid status. Must be one of: ${validMilestones.join(', ')}` });
    }

    const order = await Order.findOne({ _id: orderId, assignedRider: riderId }).populate('assignedRider', 'name phone');
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found or not assigned to this rider' });
    }

    order.status = status;
    await order.save();

    const title = status === 'ITEM_PURCHASED' ? '🛍️ Item Picked / Purchased' : '🚀 Rider On The Way!';
    const body =
      status === 'ITEM_PURCHASED'
        ? `${order.assignedRider.name} has picked up/purchased your items and is packing them.`
        : `${order.assignedRider.name} is on the way to your delivery landmark. Please keep your 4-digit PIN ready: ${order.deliveryPin}`;

    await sendMilestoneNotification({
      token: order.customerFcmToken,
      title,
      body,
      data: {
        orderId: order._id.toString(),
        orderNumber: order.orderNumber,
        status,
        callerPhone: order.assignedRider.phone,
      },
      orderId: order._id,
      recipientPhone: order.customerPhone,
    });

    return res.status(200).json({
      success: true,
      message: `Status updated to ${status}`,
      order,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 7. Complete Delivery (with OTP Verification or Optional Emergency Bypass)
exports.completeDelivery = async (req, res) => {
  try {
    const { orderId } = req.params;
    const { riderId, deliveryPin, isBypass } = req.body;

    const order = await Order.findOne({ _id: orderId, assignedRider: riderId }).populate('assignedRider', 'name phone');
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found or unauthorized rider' });
    }

    if (order.status === 'DELIVERED') {
      return res.status(400).json({ success: false, message: 'Order is already marked as DELIVERED' });
    }

    // Verify PIN unless Emergency Bypass is flagged
    if (!isBypass) {
      if (!deliveryPin || deliveryPin.trim() !== order.deliveryPin) {
        return res.status(400).json({
          success: false,
          message: 'Incorrect 4-digit Delivery PIN. Please ask customer for their PIN.',
        });
      }
    }

    order.status = 'DELIVERED';
    order.isOtpBypassed = Boolean(isBypass);
    await order.save();

    // Increment Rider Stats (Total Deliveries + Earnings)
    await Rider.findByIdAndUpdate(riderId, {
      $inc: {
        totalDeliveries: 1,
        totalEarnings: order.fare,
      },
    });

    // Notify Customer of successful completion
    await sendMilestoneNotification({
      token: order.customerFcmToken,
      title: '✅ Order Delivered!',
      body: `Your order #${order.orderNumber} has been delivered successfully. Thank you for choosing Melapalayam Express!`,
      data: {
        orderId: order._id.toString(),
        orderNumber: order.orderNumber,
        status: 'DELIVERED',
        callerPhone: order.assignedRider.phone,
      },
      orderId: order._id,
      recipientPhone: order.customerPhone,
    });

    return res.status(200).json({
      success: true,
      message: isBypass ? 'Order completed via Emergency Bypass' : 'Order delivered successfully with verified PIN',
      order,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 8. Locked Cancellation Rules
exports.cancelOrder = async (req, res) => {
  try {
    const { orderId } = req.params;
    const { reason, phone } = req.body;

    const order = await Order.findById(orderId);
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    // Locked Cancellation Rules: Once items are purchased or out for delivery, cannot cancel!
    const nonCancellableStatuses = ['ITEM_PURCHASED', 'ON_THE_WAY', 'DELIVERED'];
    if (nonCancellableStatuses.includes(order.status)) {
      return res.status(400).json({
        success: false,
        message: 'Cancellation locked! The rider has already purchased/picked up items. Please contact rider directly.',
      });
    }

    order.status = 'CANCELLED';
    await order.save();

    return res.status(200).json({
      success: true,
      message: 'Order cancelled successfully',
      order,
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
