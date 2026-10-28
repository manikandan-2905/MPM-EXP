const mongoose = require('mongoose');

const notificationTempSchema = new mongoose.Schema(
  {
    orderId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Order',
      required: true,
      index: true,
    },
    recipientPhone: {
      type: String,
      required: true,
    },
    title: {
      type: String,
      required: true,
    },
    message: {
      type: String,
      required: true,
    },
    createdAt: {
      type: Date,
      default: Date.now,
      // MongoDB TTL Index: automatically purges documents after 48 hours (172800 seconds)
      expires: 172800,
    },
  },
  {
    timestamps: false,
  }
);

module.exports = mongoose.model('NotificationTemp', notificationTempSchema);
