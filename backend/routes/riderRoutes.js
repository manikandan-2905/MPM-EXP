const express = require('express');
const router = express.Router();
const {
  loginRider,
  toggleOnlineStatus,
  getActiveRidersCount,
  getOnlineRiders,
  getRiderProfile,
  getRiderActiveOrder,
} = require('../controllers/riderController');

// Public active riders count & online riders list for Customer
router.get('/active-count', getActiveRidersCount);
router.get('/online-list', getOnlineRiders);

// Rider Authentication & Operations
router.post('/login', loginRider);
router.patch('/:riderId/online-status', toggleOnlineStatus);
router.get('/:riderId/profile', getRiderProfile);
router.get('/:riderId/active-order', getRiderActiveOrder);

module.exports = router;
