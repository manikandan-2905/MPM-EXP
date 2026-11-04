require('dotenv').config({ path: require('path').resolve(__dirname, '.env') });
const mongoose = require('mongoose');
const connectDB = require('./config/db');
const Rider = require('./models/Rider');

const sampleRiders = [
  // Newly Registered Fleet
  {
    name: 'muthu',
    phone: '9025484985',
    password: '84985',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'vishnu',
    phone: '6369022498',
    password: '22498',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'ragu',
    phone: '8807356221',
    password: '56221',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Alwa',
    phone: '9994831788',
    password: '31788',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'P S Raja',
    phone: '9344191990',
    password: '91990',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Doss',
    phone: '9787500702',
    password: '00702',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'karthick',
    phone: '9843391905',
    password: '31905',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'rohit',
    phone: '9790360616',
    password: '36061',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'saravana',
    phone: '7010710215',
    password: '10215',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Parthi',
    phone: '7540075106',
    password: '75106',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  // Core Support Fleet
  {
    name: 'V Mani',
    phone: '7639483476',
    password: '83476',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 3,
    totalEarnings: 105,
  },
  {
    name: 'MS Mani',
    phone: '6379329930',
    password: '29930',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Sudalai',
    phone: '9363302266',
    password: '02266',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Hari',
    phone: '9344590818',
    password: '50818',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'Mathan',
    phone: '9791766183',
    password: '76183',
    vehicleNumber: 'Melapalayam Patrol',
    isOnline: false,
    totalDeliveries: 0,
    totalEarnings: 0,
  },
  {
    name: 'RAJA',
    phone: '7695807394',
    password: '07394',
    vehicleNumber: 'Melapalayam Patrol',
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
      await Rider.findOneAndUpdate(
        { phone: r.phone },
        {
          name: r.name,
          phone: r.phone,
          password: r.password,
          vehicleNumber: r.vehicleNumber || 'Melapalayam Patrol',
        },
        { upsert: true, new: true }
      );
    }
    console.log(`[Seed]: Successfully pre-seeded ${sampleRiders.length} authorized riders in Melapalayam!`);
    process.exit(0);
  } catch (error) {
    console.error('[Seed Error]:', error);
    process.exit(1);
  }
};

seedRiders();
