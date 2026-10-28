require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('./config/db');
const Rider = require('./models/Rider');

const sampleRiders = [
  {
    name: 'Sudalai',
    phone: '9363302266',
    isOnline: false,
    totalDeliveries: 42,
    totalEarnings: 1890,
  },
  {
    name: 'Syed Ibrahim',
    phone: '9876543211',
    isOnline: false,
    totalDeliveries: 31,
    totalEarnings: 1420,
  },
  {
    name: 'Abdul Rahman',
    phone: '9876543212',
    isOnline: false,
    totalDeliveries: 19,
    totalEarnings: 850,
  },
  {
    name: 'Sheik Dawood',
    phone: '9876543213',
    isOnline: true,
    totalDeliveries: 55,
    totalEarnings: 2450,
  },
];

const seedRiders = async () => {
  try {
    await connectDB();
    console.log('[Seed]: Clearing existing rider test data...');
    for (const r of sampleRiders) {
      await Rider.findOneAndUpdate({ phone: r.phone }, r, { upsert: true, new: true });
    }
    console.log(`[Seed]: Successfully pre-seeded ${sampleRiders.length} authorized riders in Melapalayam!`);
    process.exit(0);
  } catch (error) {
    console.error('[Seed Error]:', error);
    process.exit(1);
  }
};

seedRiders();
