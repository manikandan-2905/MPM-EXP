const express = require('express');
const router = express.Router();
const {
  createOrder,
  getOrderById,
  getCustomerOrders,
  getAvailableOrders,
  claimOrder,
  updateMilestone,
  completeDelivery,
  cancelOrder,
} = require('../controllers/orderController');

// Guest Customer Endpoints
router.post('/', createOrder);
router.get('/customer/:phone', getCustomerOrders);
router.get('/:id', getOrderById);
router.post('/:orderId/cancel', cancelOrder);

// Rider Order Operations
router.get('/pool/available', getAvailableOrders);
router.post('/:orderId/claim', claimOrder); // Atomic lock
router.patch('/:orderId/milestone', updateMilestone); // Sliding milestone progress
router.post('/:orderId/complete', completeDelivery); // OTP verify / bypass

module.exports = router;
