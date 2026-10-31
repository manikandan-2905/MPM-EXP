const mongoose = require('mongoose');

const orderSchema = new mongoose.Schema(
  {
    orderNumber: {
      type: String,
      unique: true,
      required: true,
      index: true,
    },
    customerName: {
      type: String,
      required: [true, 'Customer name is required'],
      trim: true,
    },
    customerPhone: {
      type: String,
      required: [true, 'Customer phone number is required'],
      trim: true,
    },
    pickupPhone: {
      type: String,
      trim: true,
    },
    dropPhone: {
      type: String,
      trim: true,
    },
    orderType: {
      type: String,
      enum: ['PICKUP_DROP', 'BUY_FOR_ME'],
      required: true,
    },
    category: {
      type: String,
      enum: ['Food', 'Meat', 'Medicines', 'Documents', 'Tailoring', 'Custom', 'BuyForMe'],
      default: 'Custom',
    },
    itemsList: {
      type: [String],
      default: [],
    },
    shopName: {
      type: String,
      trim: true,
    },
    budget: {
      type: Number,
      default: 0,
    },
    isUrgent: {
      type: Boolean,
      default: false,
    },
    pickupAddress: {
      type: String,
      required: [true, 'Pickup landmark/address is required'],
    },
    pickupCoords: {
      lat: { type: Number, default: null },
      lng: { type: Number, default: null },
    },
    dropAddress: {
      type: String,
      required: [true, 'Drop landmark/address is required'],
    },
    dropCoords: {
      lat: { type: Number, default: null },
      lng: { type: Number, default: null },
    },
    status: {
      type: String,
      enum: ['ORDER_PLACED', 'RIDER_ASSIGNED', 'ITEM_PURCHASED', 'ON_THE_WAY', 'DELIVERED', 'CANCELLED'],
      default: 'ORDER_PLACED',
      index: true,
    },
    assignedRider: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Rider',
      default: null,
      index: true,
    },
    deliveryPin: {
      type: String,
      required: true,
      length: 4,
    },
    isOtpBypassed: {
      type: Boolean,
      default: false,
    },
    fare: {
      type: Number,
      required: true,
    },
    estimatedDistanceKm: {
      type: Number,
      default: 2.0,
    },
    customerFcmToken: {
      type: String,
      default: null,
    },
    paymentMode: {
      type: String,
      enum: ['Cash', 'UPI'],
      default: 'Cash',
    },
    completedAt: {
      type: Date,
      default: null,
    },
    cancelledAt: {
      type: Date,
      default: null,
    },
    cancellationReason: {
      type: String,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

// Auto-generate human-readable order number if not supplied
orderSchema.pre('validate', function (next) {
  if (!this.orderNumber) {
    const randomSuffix = Math.floor(1000 + Math.random() * 9000);
    const dateCode = new Date().toISOString().slice(2, 10).replace(/-/g, '');
    this.orderNumber = `ZIPPO-${dateCode}-${randomSuffix}`;
  }
  if (!this.deliveryPin) {
    this.deliveryPin = Math.floor(1000 + Math.random() * 9000).toString();
  }
  next();
});

module.exports = mongoose.model('Order', orderSchema);
