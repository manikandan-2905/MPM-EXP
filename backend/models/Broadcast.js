const mongoose = require('mongoose');

const broadcastSchema = new mongoose.Schema(
  {
    title: {
      type: String,
      required: true,
      trim: true,
    },
    message: {
      type: String,
      required: true,
      trim: true,
    },
    target: {
      type: String,
      enum: ['ALL', 'CUSTOMERS', 'RIDERS'],
      default: 'ALL',
    },
    type: {
      type: String,
      default: 'ANNOUNCEMENT',
    },
    actionUrl: {
      type: String,
      default: '',
    },
    totalRecipients: {
      type: Number,
      default: 0,
    },
    successCount: {
      type: Number,
      default: 0,
    },
    failureCount: {
      type: Number,
      default: 0,
    },
    sentBy: {
      type: String,
      default: 'ADMIN',
    },
  },
  {
    timestamps: true,
  }
);

// Index for fast query of recent broadcasts
broadcastSchema.index({ createdAt: -1 });

module.exports = mongoose.model('Broadcast', broadcastSchema);

