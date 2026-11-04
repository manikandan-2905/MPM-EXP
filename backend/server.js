require('dotenv').config();
const express = require('express');
const cors = require('cors');
const connectDB = require('./config/db');

// Connect to MongoDB Atlas
connectDB();

const app = express();

// Middlewares
app.use(cors());
app.use(express.json());

// Routes
const orderRoutes = require('./routes/orderRoutes');
const riderRoutes = require('./routes/riderRoutes');
const adminRoutes = require('./routes/adminRoutes');
const notificationRoutes = require('./routes/notificationRoutes');

app.use('/api/orders', orderRoutes);
app.use('/api/riders', riderRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/notifications', notificationRoutes);

// Root Welcome Endpoint
app.get('/', (req, res) => {
  res.status(200).send(`
    <!DOCTYPE html>
    <html>
      <head>
        <title>ZIPPO Express API</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background: #0f172a; color: #fff; text-align: center; }
          .card { background: #1e293b; padding: 36px; border-radius: 16px; border: 1px solid #334155; box-shadow: 0 10px 25px rgba(0,0,0,0.5); max-width: 440px; margin: 16px; }
          h1 { color: #76C457; margin: 8px 0; font-size: 24px; }
          p { color: #94a3b8; font-size: 14px; margin-bottom: 24px; line-height: 1.5; }
          .badge { display: inline-block; background: rgba(34, 197, 94, 0.15); color: #4ade80; border: 1px solid rgba(34, 197, 94, 0.3); padding: 6px 14px; border-radius: 999px; font-size: 13px; font-weight: 600; margin-bottom: 16px; }
          a { display: inline-block; background: #76C457; color: #0f172a; padding: 12px 24px; border-radius: 8px; font-weight: bold; text-decoration: none; }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="badge">● Server Live & Healthy</div>
          <h1>ZIPPO Express API</h1>
          <p>Melapalayam & Tirunelveli Hyper-Local 15-Minute Delivery Engine</p>
          <a href="https://zippo-mpm.onrender.com" target="_blank">Open Customer PWA</a>
        </div>
      </body>
    </html>
  `);
});

// Root & Health Check Endpoint
app.get('/api/health', (req, res) => {
  res.status(200).json({
    status: 'online',
    service: 'ZIPPO Express Backend',
    region: 'Melapalayam, Tirunelveli',
    timestamp: new Date().toISOString(),
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('[Unhandled Error]:', err.stack);
  res.status(500).json({
    success: false,
    message: err.message || 'Internal Server Error',
  });
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 [Melapalayam Server Running]: http://0.0.0.0:${PORT}`);
});
