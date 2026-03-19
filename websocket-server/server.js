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
const path = require('path');

// =====================================================
// SUPABASE CLIENT (Level 3 Best Fix)
// ใช้สำหรับ Emergency Alert Handler:
// query donation_categories + user_group_roles
// จาก Cloud Source of Truth แทน Local DB
// =====================================================
const { createClient } = require('@supabase/supabase-js');
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
let supabase = null;
if (supabaseUrl && supabaseAnonKey) {
  supabase = createClient(supabaseUrl, supabaseAnonKey);
  console.log('✅ Supabase client initialized for Emergency Alert (Level 3)');
} else {
  console.warn('⚠️  SUPABASE_URL or SUPABASE_ANON_KEY not set — Emergency Alert will use broadcast fallback');
}

// Video System Services & Routes
const socketService = require('./services/socket-service');
const videoRoutes = require('./routes/video');

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

// Initialize Socket Service
socketService.init(io);

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

// Serve static directory for fallback video playback
const videoDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, 'temp/videos');
app.use('/temp/videos', express.static(videoDir));

// Video Routes
if (pool) {
  app.use('/api/videos', videoRoutes(pool));
}

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

    // --- DEV AUTO-SEEDING ---
    // ⚠️  ทำงานเฉพาะ NODE_ENV=development เท่านั้น
    // ป้องกัน Security Risk: ไม่ให้ assign role กู้ภัยอัตโนมัติบน Production
    if (process.env.NODE_ENV === 'development' && pool) {
      try {
        const username = `user_${userId.substring(0, 5)}`;
        // 1. Ensure user exists
        await pool.query(
          `INSERT INTO users (id, first_name, username, verification_status) 
           VALUES ($1, $2, $3, 'verified')
           ON CONFLICT (id) DO NOTHING`,
          [userId, 'Dev User', username]
        );

        // 2. Ensure consumer profile exists (for volunteer_active status)
        await pool.query(
          `INSERT INTO consumer_profiles (user_id, is_volunteer_active) 
           VALUES ($1, true)
           ON CONFLICT (user_id) DO NOTHING`,
          [userId]
        );

        // 3. Ensure they have a volunteer role (use the first seeded profession 'กู้ภัย')
        await pool.query(
          `INSERT INTO user_group_roles (user_id, profession_id) 
           VALUES ($1, '00000000-0000-0000-0000-000000000001')
           ON CONFLICT DO NOTHING`,
          [userId]
        );
        console.log(`[Dev] Auto-seeded user ${userId} as Rescuer`);
      } catch (err) {
        console.warn('[Dev] Auto-seed failed (this is fine):', err.message);
      }
    }

    // Join user's personal room
    socket.join(`user-${userId}`);
    console.log(`User ${userId} joined room user-${userId}`);

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

  // Helper สำหรับนับ Unique Viewers (ป้องกันนับซ้ำถ้ายูสเซอร์เดิมเปิดหลาย tab/socket)
  const getUniqueViewerCount = (roomId) => {
    const roomSockets = io.sockets.adapter.rooms.get(roomId);
    if (!roomSockets) return 0;
    const uniqueUsers = new Set();
    for (const sid of roomSockets) {
      const uid = connectedUsers.get(sid);
      uniqueUsers.add(uid ? uid : sid); // ถ้ารู้ userId ให้นับเป็น 1, ถ้าไม่รู้ก็สมมติ 1 socket = 1 คน
    }
    return uniqueUsers.size;
  };

  // Helper: บันทึก Peak Concurrent Viewers ลง DB (อัปเดตเมื่อค่าปัจจุบันสูงกว่าเดิม)
  const updatePeakViewers = async (videoId, currentCount) => {
    if (!pool || !videoId || currentCount <= 0) return;
    try {
      await pool.query(
        `UPDATE videos SET peak_viewers = $2, peak_viewers_at = NOW()
         WHERE id = $1 AND (peak_viewers IS NULL OR peak_viewers < $2)`,
        [videoId, currentCount]
      );
    } catch (err) {
      console.error(`[PeakViewers] Failed to update for ${videoId}:`, err.message);
    }
  };

  // Join a room (for group tracking)
  socket.on('join-room', (data) => {
    const { roomId } = data;
    const fullRoom = `room-${roomId}`;
    socket.join(fullRoom);
    console.log(`Socket ${socket.id} joined room ${roomId}`);

    // ถ้าเป็น video room → broadcast viewer-count ให้ทุกคนในห้อง (Unique)
    if (roomId && roomId.startsWith('video-')) {
      const videoId = roomId.replace('video-', '');
      if (!socket._videoRooms) socket._videoRooms = new Set();
      socket._videoRooms.add(videoId);

      const count = getUniqueViewerCount(fullRoom);
      io.to(fullRoom).emit('viewer-count', { videoId, count });
      console.log(`[ViewerCount] ${videoId}: ${count} unique viewers`);
      
      // อัปเดตสถิติ Peak Concurrent Viewers (เฉพาะเวลาที่จำนวนเพิ่มขึ้น)
      updatePeakViewers(videoId, count);
    }
  });

  // Leave a room
  socket.on('leave-room', (data) => {
    const { roomId } = data;
    const fullRoom = `room-${roomId}`;
    socket.leave(fullRoom);
    console.log(`Socket ${socket.id} left room ${roomId}`);

    // ถ้าเป็น video room → broadcast viewer-count ให้ทุกคนในห้อง (Unique)
    if (roomId && roomId.startsWith('video-')) {
      const videoId = roomId.replace('video-', '');
      if (socket._videoRooms) socket._videoRooms.delete(videoId);

      // นับหลัง leave (socket ออกไปแล้ว)
      setImmediate(() => {
        const count = getUniqueViewerCount(fullRoom);
        io.to(fullRoom).emit('viewer-count', { videoId, count });
        console.log(`[ViewerCount] ${videoId}: ${count} unique viewers after leave`);
      });
    }
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

    // Broadcast updated viewer-count (Unique) สำหรับทุก video room ที่ socket นี้เคย join
    if (socket._videoRooms && socket._videoRooms.size > 0) {
      setImmediate(() => {
        for (const videoId of socket._videoRooms) {
          const fullRoom = `room-video-${videoId}`;
          const count = getUniqueViewerCount(fullRoom);
          io.to(fullRoom).emit('viewer-count', { videoId, count });
          console.log(`[ViewerCount] disconnect → ${videoId}: ${count} unique viewers`);
        }
      });
    }
  });

  // Handle Video Interactions
  socket.on('video-interaction', async (data) => {
    const { videoId, userId, type, value } = data;
    console.log(`[Video ${videoId}] Interaction from ${userId}: ${type} (${value})`);

    if (pool && videoId && userId) {
      try {
        await pool.query(
          `INSERT INTO video_interactions (video_id, user_id, type, value, created_at)
           VALUES ($1, $2, $3, $4, NOW())`,
          [videoId, userId, type, value || 0]
        );

        // Broadcast back to clients in the room
        socketService.broadcastInteraction(videoId, { videoId, userId, type, value });
      } catch (err) {
        console.error('Failed to save interaction:', err.message);
      }
    } else {
      // Demo mode / No DB: Broadcast blindly
      socketService.broadcastInteraction(videoId, { videoId, userId, type, value });
    }
  });

  // Handle Emergency Alerts (Level 3 Best Fix: Supabase Cloud Query)
  // -------------------------------------------------------------------
  // ดึง category + volunteer list จาก Supabase Cloud เป็น Source of Truth
  // แทนการ query Local PostgreSQL ที่อาจไม่ sync
  // ไม่ขัดกับ auth_data_guidelines: ใช้ Anon Key อ่าน public data เท่านั้น
  // ไม่ใช้ Supabase Auth / currentUser เลย
  // -------------------------------------------------------------------
  socket.on('emergency-alert', async (data) => {
    const { userId, categoryId, videoId, type, text, isThaiMhungEnabled } = data;
    console.log(`[Emergency] ====== ALERT RECEIVED ======`);
    console.log(`[Emergency] Sender: ${userId}`);
    console.log(`[Emergency] Category: ${categoryId}`);
    console.log(`[Emergency] VideoId: ${videoId}`);
    console.log(`[Emergency] Type: ${type}`);
    console.log(`[Emergency] ThaiMhung: ${isThaiMhungEnabled}`);

    // Build notification payload
    const notificationPayload = {
      userId: userId, // Added for reporter exclusion in Flutter
      senderId: userId,
      categoryId,
      categoryName: '',
      videoId,
      type,
      latitude: null,
      longitude: null,
      text: text || 'มีการแจ้งเหตุฉุกเฉินใหม่ที่คุณสามารถให้ความช่วยเหลือได้',
      isThaiMhungEnabled: isThaiMhungEnabled === true, // Added for Thai Mhung badge routing
      timestamp: new Date().toISOString()
    };

    // --- Step 1: ดึง GPS จาก Local DB (ถ้ามี) ---
    // GPS ยังใช้ Local DB ได้เพราะบันทึกจากเครื่องเดียวกัน
    if (pool && videoId) {
      try {
        const gpsRes = await pool.query(
          `SELECT latitude, longitude FROM video_gps_tracks
           WHERE video_id = $1 ORDER BY timestamp_offset DESC LIMIT 1`,
          [videoId]
        );
        if (gpsRes.rows.length > 0) {
          notificationPayload.latitude = gpsRes.rows[0].latitude;
          notificationPayload.longitude = gpsRes.rows[0].longitude;
        }
        console.log(`[Emergency] GPS: ${notificationPayload.latitude}, ${notificationPayload.longitude}`);
      } catch (gpsErr) {
        console.warn('[Emergency] GPS lookup failed (non-critical):', gpsErr.message);
      }
    }

    // --- Step 2: Query Supabase Cloud สำหรับ Category + Volunteers ---
    if (supabase && categoryId) {
      try {
        // 2a. ดึงข้อมูล category จาก Supabase (Source of Truth)
        const { data: category, error: catError } = await supabase
          .from('donation_categories')
          .select('name, volunteer_profession_ids')
          .eq('id', categoryId)
          .single();

        if (catError || !category) {
          console.warn(`[Emergency] ⚠️  Category ${categoryId} not found in Supabase → broadcast fallback`);
          // Fallback: broadcast ทุกคน (ยกเว้นผู้ส่ง) แล้วให้ Flutter client กรองเอง
          socket.broadcast.emit('emergency-notification', notificationPayload);
          console.log(`[Emergency] ====== FALLBACK BROADCAST sent (broadcast) ======`);
          return;
        }

        notificationPayload.categoryName = category.name || '';
        const volunteerProfIds = category.volunteer_profession_ids;
        console.log(`[Emergency] Category: "${category.name}", professions: ${JSON.stringify(volunteerProfIds)}`);

        // 2b. ถ้า category ไม่มี volunteerProfessionIds → แสดงว่าเปิดทั่วไป
        if (!volunteerProfIds || volunteerProfIds.length === 0) {
          console.log(`[Emergency] No profession mapping → broadcast to all (except sender)`);
          socket.broadcast.emit('emergency-notification', notificationPayload);
          console.log(`[Emergency] ====== BROADCAST sent (broadcast) ======`);
          return;
        }

        // 2c. ดึง user ที่มี profession ตรงและเปิด volunteer_active (แยก Query เพื่อเลี่ยงปัญหา Relationship และ RLS)
        const { data: roles, error: roleError } = await supabase
          .from('user_group_roles')
          .select('user_id')
          .in('profession_id', volunteerProfIds);

        if (roleError) {
          console.warn('[Emergency] ⚠️  Role query failed → broadcast fallback:', roleError.message);
          io.emit('emergency-notification', notificationPayload);
          return;
        }

        const potentialUserIds = (roles || []).map(r => r.user_id);
        if (potentialUserIds.length === 0) {
          console.warn('[Emergency] ⚠️  No users found with these professions');
          return;
        }

        const { data: activeProfiles, error: profileError } = await supabase
          .from('consumer_profiles')
          .select('user_id')
          .in('user_id', potentialUserIds)
          .eq('is_volunteer_active', true);

        if (profileError) {
          console.warn('[Emergency] ⚠️  Profile query failed → broadcast fallback:', profileError.message);
          io.emit('emergency-notification', notificationPayload);
          return;
        }

        const targetUserIds = (activeProfiles || []).map(p => p.user_id);
        console.log(`[Emergency] Target volunteers (${targetUserIds.length}): ${JSON.stringify(targetUserIds)}`);

        // 2d. ส่งเฉพาะ volunteer ที่เกี่ยวข้อง (และไม่ใช่ผู้แจ้งเหตุเอง)
        if (targetUserIds.length === 0) {
          console.warn('[Emergency] ⚠️  No active volunteers found for this category → silent (no broadcast)');
        } else {
          let sentCount = 0;
          targetUserIds.forEach(targetId => {
            // ✅ ไม่ส่งหาตัวเอง (ข้ามผู้แจ้งเหตุ)
            if (targetId.toString() !== userId.toString()) {
              io.to(`user-${targetId}`).emit('emergency-notification', notificationPayload);
              sentCount++;
            }
          });
          console.log(`[Emergency] ====== ALERT COMPLETE: sent to ${sentCount} volunteers (excluded self) ======`);
        }

      } catch (err) {
        console.error('[Emergency] Supabase query error → broadcast fallback:', err.message);
        // Safety fallback: ถ้า Supabase ล้มเหลว ให้ broadcast เพื่อไม่ให้ Alert หาย
        io.emit('emergency-notification', notificationPayload);
      }

    } else {
      // Supabase ไม่ได้ตั้งค่า หรือไม่มี categoryId
      // → broadcast ทุกคน (ยกเว้นผู้ส่ง) แล้วให้ Flutter client กรองเองตาม professionId + alertRadius
      console.warn(`[Emergency] ⚠️  Supabase not configured or no categoryId → broadcast fallback`);
      socket.broadcast.emit('emergency-notification', notificationPayload);
      console.log(`[Emergency] ====== FALLBACK BROADCAST sent (broadcast) ======`);
    }
  });

  // Handle Rescue Status Updates (Feedback Loop to Victim + DB Persistence)
  socket.on('rescue-status-update', async (data) => {
    const { videoId, volunteerId, status, victimId, responseId } = data;
    console.log(`[Rescue] Volunteer: ${volunteerId} updated status to ${status} for incident ${videoId}`);

    // 1. Persist to DB as single source of truth
    if (pool && responseId) {
      try {
        const updates = { status, updated_at: new Date().toISOString() };
        if (status === 'arrived') updates.arrived_at = new Date().toISOString();
        if (status === 'resolved' || status === 'cancelled') updates.resolved_at = new Date().toISOString();

        const setClauses = Object.entries(updates).map(([key, _], i) => `${key} = $${i + 1}`).join(', ');
        const values = Object.values(updates);
        values.push(responseId);

        await pool.query(
          `UPDATE incident_responses SET ${setClauses} WHERE id = $${values.length}`,
          values
        );
        console.log(`[Rescue] DB updated: response ${responseId} -> ${status}`);
      } catch (dbErr) {
        console.error('[Rescue] DB update failed:', dbErr.message);
      }
    }

    // 2. Notify the victim in real-time
    if (victimId) {
      io.to(`user-${victimId}`).emit('rescue-incoming', {
        videoId,
        volunteerId,
        status,
        timestamp: new Date().toISOString()
      });
      console.log(`[Rescue] Notified victim ${victimId} of status: ${status}`);
    }

    // 3. If cancelled, also notify other connected volunteers so they know the spot is open
    if (status === 'cancelled') {
      io.emit('rescue-cancelled', { videoId, volunteerId });
    }

    // 4. Archive chat if resolved or cancelled to save space in main tables
    if (pool && (status === 'resolved' || status === 'cancelled')) {
      await archiveChatMessages(videoId, status);
    }
  });

  // Handle UI Preference Updates
  socket.on('save-ui-preference', async (data) => {
    const { userId, key, value } = data;
    console.log(`[UI] Save preference for ${userId}: ${key} = ${value}`);
    if (pool && userId && key) {
      try {
        await pool.query(
          `INSERT INTO user_ui_preferences (user_id, preference_key, preference_value, updated_at)
           VALUES ($1, $2, $3, NOW())
           ON CONFLICT (user_id, preference_key) DO UPDATE SET preference_value = $3, updated_at = NOW()`,
          [userId, key, value]
        );
      } catch (err) {
        console.error('[UI] Failed to save preference:', err.message);
      }
    }
  });

  // Handle Emergency Live Chat
  // -------------------------
  socket.on('join-emergency-chat', (data) => {
    const { videoId, userId, role } = data;
    const roomName = `emergency-chat-${videoId}`;
    socket.join(roomName);
    console.log(`[Chat] User ${userId} (${role}) joined ${roomName}`);
    
    // Optionally notify others
    socket.to(roomName).emit('emergency-chat-presence', { userId, role, status: 'joined' });
  });

  socket.on('leave-emergency-chat', (data) => {
    const { videoId, userId } = data;
    const roomName = `emergency-chat-${videoId}`;
    socket.leave(roomName);
    console.log(`[Chat] User ${userId} left ${roomName}`);
  });

  socket.on('send-emergency-message', async (data) => {
    const { videoId, userId, role, userName, content, profileImageUrl } = data;
    console.log(`[Chat] Message in ${videoId} from ${userName} (${role}): ${content}`);

    const messagePayload = {
      id: require('crypto').randomUUID(), // ✅ UUID แทน Date.now() เพื่อป้องกัน ID ชนกัน
      videoId,
      userId,
      role,
      userName,
      content,
      profileImageUrl,
      timestamp: new Date().toISOString()
    };

    // 1. Broadcast to everyone in the room (including sender)
    socketService.broadcastEmergencyMessage(videoId, messagePayload);

    // 2. Persist to DB (using chat_rooms and chat_messages logic)
    if (pool && videoId && userId) {
      try {
        // Find or create a room for this video
        let roomId;
        const roomCheck = await pool.query(
          'SELECT id FROM chat_rooms WHERE video_id = $1',
          [videoId]
        );

        if (roomCheck.rows.length > 0) {
          roomId = roomCheck.rows[0].id;
        } else {
          // Create room. participant_ids will be updated as people join or just keep it open
          const newRoom = await pool.query(
            "INSERT INTO chat_rooms (video_id, participant_ids, created_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING id",
            [videoId, [userId]]
          );
          roomId = newRoom.rows[0].id;
        }

        // Save message
        await pool.query(
          `INSERT INTO chat_messages (id, room_id, sender_id, content, created_at, metadata)
           VALUES ($1, $2, $3, $4, NOW(), $5)`,
          [messagePayload.id, roomId, userId, content, JSON.stringify({ role, userName, profileImageUrl })]
        );

        // Update room's last message
        await pool.query(
          "UPDATE chat_rooms SET last_message = $1, updated_at = NOW() WHERE id = $2",
          [content, roomId]
        );
      } catch (err) {
        console.error('[Chat] Failed to persist message:', err.message);
      }
    }
  });
  // Manual Archive Trigger (optional use)
  socket.on('archive-chat', async (data) => {
    const { videoId } = data;
    if (pool && videoId) {
      console.log(`[Archive] Manual archiving requested for video ${videoId}`);
      await archiveChatMessages(videoId, 'manual');
    }
  });
});

async function archiveChatMessages(videoId, status) {
  if (!pool) return;
  try {
    // Copy messages to archive
    await pool.query(
      `INSERT INTO chat_messages_archive (id, room_id, video_id, sender_id, content, created_at, metadata)
       SELECT m.id, m.room_id, r.video_id, m.sender_id, m.content, m.created_at, m.metadata
       FROM chat_messages m
       JOIN chat_rooms r ON m.room_id = r.id
       WHERE r.video_id = $1
       ON CONFLICT (id) DO NOTHING`,
      [videoId]
    );
    // Delete from active messages
    await pool.query(
      `DELETE FROM chat_messages WHERE room_id IN (SELECT id FROM chat_rooms WHERE video_id = $1)`,
      [videoId]
    );
    // Mark room as archived
    await pool.query(
      `UPDATE chat_rooms SET last_message = $1, updated_at = NOW() WHERE video_id = $2`,
      [`[Archived: ${status}]`, videoId]
    );
    console.log(`[Archive] Video ${videoId} archived successfully (${status})`);
  } catch (err) {
    console.error(`[Archive] Failed to archive video ${videoId}:`, err.message);
  }
}

// ============================================================
// Emergency Chat History API
// GET /api/videos/:videoId/chat  — โหลดประวัติแชท (active)
// GET /api/videos/:videoId/chat/archived — โหลดแชทที่ archive แล้ว
// ============================================================

app.get('/api/videos/:videoId/chat', async (req, res) => {
  const { videoId } = req.params;
  const limit = parseInt(req.query.limit) || 50;

  try {
    if (!pool) return res.status(503).json({ error: 'Database not available' });

    const result = await pool.query(
      `SELECT
         m.id,
         m.room_id,
         r.video_id           AS "videoId",
         m.sender_id          AS "userId",
         m.content,
         m.created_at         AS "timestamp",
         m.metadata->>'role'         AS role,
         m.metadata->>'userName'     AS "userName",
         m.metadata->>'profileImageUrl' AS "profileImageUrl"
       FROM chat_messages m
       JOIN chat_rooms r ON m.room_id = r.id
       WHERE r.video_id = $1
       ORDER BY m.created_at ASC
       LIMIT $2`,
      [videoId, limit]
    );

    res.json(result.rows);
  } catch (error) {
    console.error('[Chat History] Error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/videos/:videoId/chat/archived', async (req, res) => {
  const { videoId } = req.params;
  const limit = parseInt(req.query.limit) || 100;

  try {
    if (!pool) return res.status(503).json({ error: 'Database not available' });

    const result = await pool.query(
      `SELECT
         a.id,
         a.video_id           AS "videoId",
         a.sender_id          AS "userId",
         a.content,
         a.created_at         AS "timestamp",
         a.metadata->>'role'         AS role,
         a.metadata->>'userName'     AS "userName",
         a.metadata->>'profileImageUrl' AS "profileImageUrl"
       FROM chat_messages_archive a
       WHERE a.video_id = $1
       ORDER BY a.created_at ASC
       LIMIT $2`,
      [videoId, limit]
    );

    res.json(result.rows);
  } catch (error) {
    console.error('[Chat Archive History] Error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// POST /api/chat/archive/:videoId — Manual archive trigger via REST
app.post('/api/chat/archive/:videoId', async (req, res) => {
  const { videoId } = req.params;
  try {
    if (!pool) return res.status(503).json({ error: 'Database not available' });
    await archiveChatMessages(videoId, 'manual-api');
    res.json({ success: true, message: `Chat archived for video ${videoId}` });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    connectedUsers: connectedUsers.size,
    database: pool ? 'connected' : 'not connected'
  });
});

// UI Preferences API
app.get('/api/users/:userId/preferences/:key', async (req, res) => {
  const { userId, key } = req.params;
  try {
    if (!pool) return res.status(503).json({ error: 'Database not available' });
    const result = await pool.query(
      'SELECT preference_value FROM user_ui_preferences WHERE user_id = $1 AND preference_key = $2',
      [userId, key]
    );
    if (result.rows.length === 0) return res.json({ value: null });
    res.json({ value: result.rows[0].preference_value });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/users/:userId/preferences', async (req, res) => {
  const { userId } = req.params;
  const { key, value } = req.body;
  try {
    if (!pool) return res.status(503).json({ error: 'Database not available' });
    await pool.query(
      `INSERT INTO user_ui_preferences (user_id, preference_key, preference_value, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (user_id, preference_key) DO UPDATE SET preference_value = $3, updated_at = NOW()`,
      [userId, key, value]
    );
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
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
