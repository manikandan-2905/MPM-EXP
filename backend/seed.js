require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('./config/db');
const Rider = require('./models/Rider');

const sampleRiders = [
  {
    name: 'Sudalai',
    phone: '9363302266',
    password: '02266',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Mani',
    phone: '7639482476',
    password: '82476',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Mani',
    phone: '6379329930',
    password: '29930',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Hari',
    phone: '9344590818',
    password: '50818',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Mathan',
    phone: '9791766183',
    password: '76183',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Santhanam',
    phone: '7010710215',
    password: '10215',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'RAJA',
    phone: '7695807394',
    password: '07394',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
];

const seedRiders = async () => {
  try {
    await connectDB();
    console.log('[Seed]: Upserting authorized rider data with last-5-digit passwords...');
    for (const r of sampleRiders) {
      if (!r.password) {
        r.password = r.phone.slice(-5);
      }
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
