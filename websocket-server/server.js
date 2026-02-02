/**
 * WebSocket Server for Real-time Location Tracking
 * Self-hosted WebSocket Server using Node.js + Socket.io
 * 
 * Installation:
 * npm install socket.io express cors pg
 * 
 * Run:
 * node server.js
 */

// Load environment variables
require('dotenv').config();

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const { Pool } = require('pg');

const app = express();
const server = http.createServer(app);

// CORS configuration
const io = new Server(server, {
  cors: {
    origin: '*', // Change this to your Flutter app URL in production
    methods: ['GET', 'POST'],
    credentials: true,
  },
});

// Database configuration (optional - can work without database)
let pool = null;
const USE_DATABASE = process.env.USE_DATABASE !== 'false'; // Default to true

if (USE_DATABASE) {
  try {
    pool = new Pool({
      host: process.env.DB_HOST || 'localhost',
      database: process.env.DB_NAME || 'sheserved',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'password',
      port: process.env.DB_PORT || 5432,
    });
    
    // Test database connection
    pool.query('SELECT NOW()', (err, res) => {
      if (err) {
        console.warn('⚠️  Database connection failed. Server will work without database.');
        console.warn('   Error:', err.message);
        console.warn('   Install PostgreSQL or set USE_DATABASE=false in .env');
        pool = null;
      } else {
        console.log('✅ Database connected successfully');
      }
    });
  } catch (error) {
    console.warn('⚠️  Database not available. Server will work without database.');
    pool = null;
  }
} else {
  console.log('ℹ️  Database disabled (USE_DATABASE=false)');
}

// In-memory storage for locations (fallback when database is not available)
const locationsCache = new Map();

// Middleware
app.use(cors());
app.use(express.json());

// Store connected users
const connectedUsers = new Map();

// WebSocket Connection Handler
io.on('connection', (socket) => {
  console.log(`User connected: ${socket.id}`);
  
  // User connected event
  socket.on('user-connected', async (data) => {
    const { userId } = data;
    connectedUsers.set(socket.id, userId);
    socket.userId = userId;
    
    console.log(`User ${userId} connected (socket: ${socket.id})`);
    
    // Join user's personal room
    socket.join(`user-${userId}`);
    
    // Notify others that user is online
    socket.broadcast.emit('user-online', { userId });
  });
  
  // Location update event
  socket.on('location-update', async (data) => {
    const { userId, latitude, longitude, timestamp, accuracy, speed, heading } = data;
    
    const locationData = {
      userId,
      latitude,
      longitude,
      timestamp: timestamp || new Date().toISOString(),
      accuracy,
      speed,
      heading,
    };
    
    try {
      // Save to database if available
      if (pool) {
        try {
          // Ensure user exists in database (create if not exists)
          await pool.query(
            `INSERT INTO users (id, created_at) 
             VALUES ($1, $2)
             ON CONFLICT (id) DO NOTHING`,
            [userId, new Date()]
          );
          
          // Save to database
          await pool.query(
            `INSERT INTO locations (user_id, latitude, longitude, accuracy, speed, heading, created_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7)`,
            [
              userId,
              latitude,
              longitude,
              accuracy || null,
              speed || null,
              heading || null,
              timestamp || new Date(),
            ]
          );
        } catch (dbError) {
          console.warn('Database save failed, using cache:', dbError.message);
          // Fallback to in-memory storage
          if (!locationsCache.has(userId)) {
            locationsCache.set(userId, []);
          }
          locationsCache.get(userId).push(locationData);
        }
      } else {
        // Use in-memory storage when database is not available
        if (!locationsCache.has(userId)) {
          locationsCache.set(userId, []);
        }
        const userLocations = locationsCache.get(userId);
        userLocations.push(locationData);
        // Keep only last 100 locations per user
        if (userLocations.length > 100) {
          userLocations.shift();
        }
      }
      
      // Broadcast to all clients (or specific subscribers)
      // Send to user's personal room
      io.to(`user-${userId}`).emit('location-updated', locationData);
      
      // Also broadcast to all connected clients (optional)
      socket.broadcast.emit('location-updated', locationData);
      
      console.log(`✅ Location updated for user ${userId}: ${latitude}, ${longitude}`);
    } catch (error) {
      console.error('Error processing location:', error);
      socket.emit('error', { message: 'Failed to process location' });
    }
  });
  
  // Subscribe to specific user's location
  socket.on('subscribe-user', (data) => {
    const { userId } = data;
    socket.join(`user-${userId}`);
    console.log(`Socket ${socket.id} subscribed to user ${userId}`);
  });
  
  // Unsubscribe from user's location
  socket.on('unsubscribe-user', (data) => {
    const { userId } = data;
    socket.leave(`user-${userId}`);
    console.log(`Socket ${socket.id} unsubscribed from user ${userId}`);
  });
  
  // Join a room (for group tracking)
  socket.on('join-room', (data) => {
    const { roomId } = data;
    socket.join(`room-${roomId}`);
    console.log(`Socket ${socket.id} joined room ${roomId}`);
  });
  
  // Leave a room
  socket.on('leave-room', (data) => {
    const { roomId } = data;
    socket.leave(`room-${roomId}`);
    console.log(`Socket ${socket.id} left room ${roomId}`);
  });
  
  // Disconnect handler
  socket.on('disconnect', () => {
    const userId = connectedUsers.get(socket.id);
    if (userId) {
      console.log(`User ${userId} disconnected (socket: ${socket.id})`);
      connectedUsers.delete(socket.id);
      
      // Notify others that user is offline
      socket.broadcast.emit('user-offline', { userId });
    }
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', connectedUsers: connectedUsers.size });
});

// Get user's recent locations (REST API)
app.get('/api/locations/:userId', async (req, res) => {
  const { userId } = req.params;
  const limit = parseInt(req.query.limit) || 100;
  
  try {
    if (pool) {
      // Get from database
      const result = await pool.query(
        `SELECT * FROM locations 
         WHERE user_id = $1 
         ORDER BY created_at DESC 
         LIMIT $2`,
        [userId, limit]
      );
      res.json(result.rows);
    } else {
      // Get from in-memory cache
      const userLocations = locationsCache.get(userId) || [];
      const recentLocations = userLocations
        .slice(-limit)
        .reverse()
        .map((loc, index) => ({
          id: index + 1,
          ...loc,
        }));
      res.json(recentLocations);
    }
  } catch (error) {
    console.error('Error fetching locations:', error);
    res.status(500).json({ error: 'Failed to fetch locations' });
  }
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`WebSocket Server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});
