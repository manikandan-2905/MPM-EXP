const express = require('express');
const router = express.Router();
const {
  loginRider,
  toggleOnlineStatus,
  getActiveRidersCount,
  getRiderProfile,
  getRiderActiveOrder,
} = require('../controllers/riderController');

// Public active riders count for Customer Top Bar
router.get('/active-count', getActiveRidersCount);

// Rider Authentication & Operations
router.post('/login', loginRider);
router.patch('/:riderId/online-status', toggleOnlineStatus);
router.get('/:riderId/profile', getRiderProfile);
router.get('/:riderId/active-order', getRiderActiveOrder);

module.exports = router;
