const mongoose = require('mongoose');

const riderSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: [true, 'Rider name is required'],
      trim: true,
    },
    phone: {
      type: String,
      required: [true, 'Phone number is required'],
      unique: true,
      trim: true,
    },
    isOnline: {
      type: Boolean,
      default: false,
    },
    totalDeliveries: {
      type: Number,
      default: 0,
    },
    totalOrders: {
      type: Number,
      default: 0,
    },
    totalEarnings: {
      type: Number,
      default: 0,
    },
    todayOrders: {
      type: Number,
      default: 0,
    },
    todayEarnings: {
      type: Number,
      default: 0,
    },
    cashEarnings: {
      type: Number,
      default: 0,
    },
    upiEarnings: {
      type: Number,
      default: 0,
    },
    todayCashOrders: {
      type: Number,
      default: 0,
    },
    todayUpiOrders: {
      type: Number,
      default: 0,
    },
    lastActiveDate: {
      type: Date,
      default: Date.now,
    },
    fcmToken: {
      type: String,
      default: null,
    },
    password: {
      type: String,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model('Rider', riderSchema);
