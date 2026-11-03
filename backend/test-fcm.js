/**
 * Quick FCM Test Script for ZIPPO Delivery
 * Usage: node test-fcm.js <FCM_DEVICE_TOKEN>
 */
const { sendMilestoneNotification } = require('./services/fcmService');

const token = process.argv[2];

if (!token) {
  console.log('--------------------------------------------------');
  console.log('Usage: node test-fcm.js <YOUR_FCM_DEVICE_TOKEN>');
  console.log('Example: node test-fcm.js e8d39f...xyz');
  console.log('--------------------------------------------------');
  process.exit(1);
}

console.log('🚀 Sending Test High-Priority Notification to token...');

sendMilestoneNotification({
  token: token,
  title: '⚡ ZIPPO Test Notification',
  body: 'Congratulations! FCM Push Notification is working perfectly in Melapalayam!',
  data: {
    status: 'TEST',
    callerPhone: '7639483476',
  },
  recipientPhone: '7639483476',
})
  .then((res) => {
    console.log('✅ Result:', res);
    process.exit(0);
  })
  .catch((err) => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
