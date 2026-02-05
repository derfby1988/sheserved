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
          // Check if user exists (UUID-based schema v2.1)
          const userCheck = await pool.query(
            'SELECT id FROM users WHERE id = $1',
            [userId]
          );
          
          if (userCheck.rows.length === 0) {
            // Create user if not exists (with required fields)
            await pool.query(
              `INSERT INTO users (id, first_name, username, created_at) 
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (id) DO NOTHING`,
              [userId, 'Guest', `guest_${userId.substring(0, 8)}`, new Date()]
            );
          }
          
          // Save location to database
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
  res.json({ 
    status: 'ok', 
    connectedUsers: connectedUsers.size,
    database: pool ? 'connected' : 'not connected'
  });
});

// ============ PROFESSIONS API ============

// Get all professions
app.get('/api/professions', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const result = await pool.query(
      `SELECT id, name, name_en, description, icon_name, category, 
              is_built_in, is_active, requires_verification, display_order,
              created_at, updated_at
       FROM professions 
       WHERE is_active = true 
       ORDER BY display_order ASC`
    );
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching professions:', error);
    res.status(500).json({ error: 'Failed to fetch professions' });
  }
});

// Get profession by ID
app.get('/api/professions/:id', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { id } = req.params;
    const result = await pool.query(
      `SELECT * FROM professions WHERE id = $1`,
      [id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Profession not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching profession:', error);
    res.status(500).json({ error: 'Failed to fetch profession' });
  }
});

// Get registration fields for a profession
app.get('/api/professions/:id/fields', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { id } = req.params;
    const result = await pool.query(
      `SELECT id, field_id, label, hint, field_type, is_required, 
              field_order, icon_name, dropdown_options, validation_regex,
              validation_message, is_active
       FROM registration_field_configs 
       WHERE profession_id = $1 AND is_active = true
       ORDER BY field_order ASC`,
      [id]
    );
    
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching fields:', error);
    res.status(500).json({ error: 'Failed to fetch fields' });
  }
});

// ============ USERS API ============

// Create user
app.post('/api/users', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { 
      professionId, firstName, lastName, username, email, 
      phone, passwordHash, socialProvider, socialId 
    } = req.body;
    
    const result = await pool.query(
      `INSERT INTO users (profession_id, first_name, last_name, username, email, 
                          phone, password_hash, social_provider, social_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *`,
      [professionId, firstName, lastName, username, email, 
       phone, passwordHash, socialProvider, socialId]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating user:', error);
    if (error.code === '23505') { // Unique violation
      res.status(409).json({ error: 'Username already exists' });
    } else {
      res.status(500).json({ error: 'Failed to create user' });
    }
  }
});

// Get user by ID
app.get('/api/users/:id', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { id } = req.params;
    const result = await pool.query(
      `SELECT u.*, p.name as profession_name, p.category as profession_category
       FROM users u
       LEFT JOIN professions p ON u.profession_id = p.id
       WHERE u.id = $1`,
      [id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching user:', error);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

// Update user
app.put('/api/users/:id', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { id } = req.params;
    const updates = req.body;
    
    // Build dynamic update query
    const fields = [];
    const values = [];
    let paramIndex = 1;
    
    const allowedFields = ['first_name', 'last_name', 'email', 'phone', 'profile_image_url'];
    for (const [key, value] of Object.entries(updates)) {
      const snakeKey = key.replace(/([A-Z])/g, '_$1').toLowerCase();
      if (allowedFields.includes(snakeKey)) {
        fields.push(`${snakeKey} = $${paramIndex}`);
        values.push(value);
        paramIndex++;
      }
    }
    
    if (fields.length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    
    values.push(id);
    const result = await pool.query(
      `UPDATE users SET ${fields.join(', ')} WHERE id = $${paramIndex} RETURNING *`,
      values
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error updating user:', error);
    res.status(500).json({ error: 'Failed to update user' });
  }
});

// ============ REGISTRATION APPLICATIONS API ============

// Submit registration application
app.post('/api/applications', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { 
      userId, professionId, firstName, lastName, username, 
      phone, profileImageUrl, registrationData 
    } = req.body;
    
    const result = await pool.query(
      `INSERT INTO registration_applications 
       (user_id, profession_id, first_name, last_name, username, phone, 
        profile_image_url, registration_data, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
       RETURNING *`,
      [userId, professionId, firstName, lastName, username, phone, 
       profileImageUrl, JSON.stringify(registrationData || {})]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating application:', error);
    res.status(500).json({ error: 'Failed to create application' });
  }
});

// Get applications (with optional status filter)
app.get('/api/applications', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { status } = req.query;
    let query = `
      SELECT a.*, p.name as profession_name, p.category as profession_category
      FROM registration_applications a
      LEFT JOIN professions p ON a.profession_id = p.id
    `;
    const params = [];
    
    if (status) {
      query += ' WHERE a.status = $1';
      params.push(status);
    }
    
    query += ' ORDER BY a.created_at DESC';
    
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching applications:', error);
    res.status(500).json({ error: 'Failed to fetch applications' });
  }
});

// Get application by ID
app.get('/api/applications/:id', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { id } = req.params;
    const result = await pool.query(
      `SELECT a.*, p.name as profession_name
       FROM registration_applications a
       LEFT JOIN professions p ON a.profession_id = p.id
       WHERE a.id = $1`,
      [id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Application not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching application:', error);
    res.status(500).json({ error: 'Failed to fetch application' });
  }
});

// Approve application
app.post('/api/applications/:id/approve', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { id } = req.params;
    const { note, reviewedBy } = req.body;
    
    // Update application status
    const result = await pool.query(
      `UPDATE registration_applications 
       SET status = 'approved', review_note = $1, reviewed_by = $2, reviewed_at = NOW()
       WHERE id = $3 AND status = 'pending'
       RETURNING *`,
      [note, reviewedBy, id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Application not found or already processed' });
    }
    
    // Update user verification status
    await pool.query(
      `UPDATE users SET verification_status = 'verified' WHERE id = $1`,
      [result.rows[0].user_id]
    );
    
    res.json({ message: 'Application approved', application: result.rows[0] });
  } catch (error) {
    console.error('Error approving application:', error);
    res.status(500).json({ error: 'Failed to approve application' });
  }
});

// Reject application
app.post('/api/applications/:id/reject', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }
    
    const { id } = req.params;
    const { note, reviewedBy } = req.body;
    
    if (!note) {
      return res.status(400).json({ error: 'Rejection note is required' });
    }
    
    const result = await pool.query(
      `UPDATE registration_applications 
       SET status = 'rejected', review_note = $1, reviewed_by = $2, reviewed_at = NOW()
       WHERE id = $3 AND status = 'pending'
       RETURNING *`,
      [note, reviewedBy, id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Application not found or already processed' });
    }
    
    // Update user verification status
    await pool.query(
      `UPDATE users SET verification_status = 'rejected' WHERE id = $1`,
      [result.rows[0].user_id]
    );
    
    res.json({ message: 'Application rejected', application: result.rows[0] });
  } catch (error) {
    console.error('Error rejecting application:', error);
    res.status(500).json({ error: 'Failed to reject application' });
  }
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

// ============ SYNC API ============

// Sync professions from Supabase
app.post('/api/professions/sync', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }

    const { data } = req.body;
    if (!Array.isArray(data)) {
      return res.status(400).json({ error: 'Data must be an array' });
    }

    let synced = 0;
    for (const item of data) {
      await pool.query(
        `INSERT INTO professions (id, name, name_en, description, icon_name, category, 
                                  is_built_in, is_active, requires_verification, display_order,
                                  created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
         ON CONFLICT (id) DO UPDATE SET
           name = EXCLUDED.name,
           name_en = EXCLUDED.name_en,
           description = EXCLUDED.description,
           icon_name = EXCLUDED.icon_name,
           category = EXCLUDED.category,
           is_built_in = EXCLUDED.is_built_in,
           is_active = EXCLUDED.is_active,
           requires_verification = EXCLUDED.requires_verification,
           display_order = EXCLUDED.display_order,
           updated_at = EXCLUDED.updated_at`,
        [
          item.id, item.name, item.name_en, item.description, item.icon_name,
          item.category, item.is_built_in, item.is_active, item.requires_verification,
          item.display_order, item.created_at, item.updated_at
        ]
      );
      synced++;
    }

    console.log(`✅ Synced ${synced} professions`);
    res.json({ message: `Synced ${synced} professions` });
  } catch (error) {
    console.error('Error syncing professions:', error);
    res.status(500).json({ error: 'Failed to sync professions' });
  }
});

// Sync registration_field_configs from Supabase
app.post('/api/registration_field_configs/sync', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }

    const { data } = req.body;
    if (!Array.isArray(data)) {
      return res.status(400).json({ error: 'Data must be an array' });
    }

    let synced = 0;
    for (const item of data) {
      await pool.query(
        `INSERT INTO registration_field_configs 
         (id, profession_id, field_id, label, hint, field_type, is_required, 
          field_order, icon_name, dropdown_options, validation_regex, 
          validation_message, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
         ON CONFLICT (id) DO UPDATE SET
           profession_id = EXCLUDED.profession_id,
           field_id = EXCLUDED.field_id,
           label = EXCLUDED.label,
           hint = EXCLUDED.hint,
           field_type = EXCLUDED.field_type,
           is_required = EXCLUDED.is_required,
           field_order = EXCLUDED.field_order,
           icon_name = EXCLUDED.icon_name,
           dropdown_options = EXCLUDED.dropdown_options,
           validation_regex = EXCLUDED.validation_regex,
           validation_message = EXCLUDED.validation_message,
           is_active = EXCLUDED.is_active,
           updated_at = EXCLUDED.updated_at`,
        [
          item.id, item.profession_id, item.field_id, item.label, item.hint,
          item.field_type, item.is_required, item.field_order, item.icon_name,
          item.dropdown_options, item.validation_regex, item.validation_message,
          item.is_active, item.created_at, item.updated_at
        ]
      );
      synced++;
    }

    console.log(`✅ Synced ${synced} field configs`);
    res.json({ message: `Synced ${synced} field configs` });
  } catch (error) {
    console.error('Error syncing field configs:', error);
    res.status(500).json({ error: 'Failed to sync field configs' });
  }
});

// Sync users from Supabase (non-sensitive data only)
app.post('/api/users/sync', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }

    const { data } = req.body;
    if (!Array.isArray(data)) {
      return res.status(400).json({ error: 'Data must be an array' });
    }

    let synced = 0;
    for (const item of data) {
      await pool.query(
        `INSERT INTO users (id, profession_id, first_name, last_name, username, 
                           verification_status, is_active, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (id) DO UPDATE SET
           profession_id = EXCLUDED.profession_id,
           first_name = EXCLUDED.first_name,
           last_name = EXCLUDED.last_name,
           verification_status = EXCLUDED.verification_status,
           is_active = EXCLUDED.is_active,
           updated_at = EXCLUDED.updated_at`,
        [
          item.id, item.profession_id, item.first_name, item.last_name, 
          item.username, item.verification_status, item.is_active,
          item.created_at, item.updated_at
        ]
      );
      synced++;
    }

    console.log(`✅ Synced ${synced} users`);
    res.json({ message: `Synced ${synced} users` });
  } catch (error) {
    console.error('Error syncing users:', error);
    res.status(500).json({ error: 'Failed to sync users' });
  }
});

// Get sync status
app.get('/api/sync/status', async (req, res) => {
  try {
    const tables = ['professions', 'users', 'registration_field_configs', 'registration_applications'];
    const counts = {};

    if (pool) {
      for (const table of tables) {
        const result = await pool.query(`SELECT COUNT(*) FROM ${table}`);
        counts[table] = parseInt(result.rows[0].count);
      }
    }

    res.json({
      status: pool ? 'connected' : 'disconnected',
      tables: counts,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error getting sync status:', error);
    res.status(500).json({ error: 'Failed to get sync status' });
  }
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`WebSocket Server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});
