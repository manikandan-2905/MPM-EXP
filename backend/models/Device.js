const mongoose = require('mongoose');

const deviceSchema = new mongoose.Schema(
  {
    fcmToken: {
      type: String,
      required: true,
      unique: true,
      trim: true,
    },
    role: {
      type: String,
      enum: ['CUSTOMER', 'RIDER', 'ADMIN'],
      default: 'CUSTOMER',
    },
    phone: {
      type: String,
      trim: true,
      default: null,
    },
    platform: {
      type: String,
      enum: ['android', 'ios', 'web'],
      default: 'android',
    },
    notificationsEnabled: {
      type: Boolean,
      default: true,
    },
    lastActive: {
      type: Date,
      default: Date.now,
    },
  },
  {
    timestamps: true,
  }
);

deviceSchema.index({ role: 1, notificationsEnabled: 1 });

module.exports = mongoose.model('Device', deviceSchema);

