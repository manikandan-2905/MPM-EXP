const express = require('express');
const router = express.Router();
const notificationController = require('../controllers/notificationController');

// Device Token Registration & Preferences
router.post('/register', notificationController.registerDevice);
router.post('/toggle', notificationController.toggleNotificationPreference);

// Admin Broadcast Operations
router.get('/stats', notificationController.getNotificationStats);
router.post('/broadcast', notificationController.broadcastNotification);
router.post('/riders-online-alert', notificationController.notifyRidersAvailable);

module.exports = router;

