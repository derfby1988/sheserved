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
const adminRoutes = require('./routes/admin');
const consultationRoutes = require('./routes/consultation');
const { shutdown: shutdownConsultationQueue } = require('./services/consultation-queue');

// Phase 1 — Route Security Middleware
const { verifyToken, requireRole, requireAuth } = require('./middleware/auth');
const donationQueueService = require('./services/donation-queue');

// Escrow Services
const escrowReleaseService = require('./services/escrow-release-service');
const escrowDeadlineChecker = require('./services/escrow-deadline-checker');
const emergencyHealthReleaseChecker = require('./services/emergency-health-release-checker');
const emergencyHealthSessionService = require('./services/emergency-health-session-service');
const emergencyHealthMonitorService = require('./services/emergency-health-monitor-service');
const inventoryAlertChecker = require('./services/inventory-alert-checker');

// Sync Service
const { reconcileLocalToCloud } = require('./services/sync-service');
const syncQueueService = require('./services/sync-queue');
const notificationQueueService = require('./services/notification-queue');

const app = express();
const server = http.createServer(app);

// CORS configuration
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '*')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

const corsOptions = {
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl, server-to-server)
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes('*')) {
      console.warn('[Security] CORS is set to "*" — restrict ALLOWED_ORIGINS in production');
      return callback(null, true);
    }
    if (allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    callback(new Error(`CORS blocked: origin ${origin} not in ALLOWED_ORIGINS`));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  credentials: true,
};

const io = new Server(server, {
  cors: corsOptions,
});

// Initialize Socket Service
socketService.init(io);

// ── Phase 1 — Socket.IO Connection-Level Auth ──
// Verifies identity on every new WebSocket connection before any events are handled.
// The client must provide { auth: { token: '...' } } or x-user-id header.
io.use(async (socket, next) => {
  try {
    // 1. Extract identity from handshake
    let userId = socket.handshake.auth?.token
      || socket.handshake.headers?.['x-user-id'];

    // 2. Try Bearer token payload (unsigned decode, same as HTTP middleware)
    if (!userId && socket.handshake.headers?.authorization) {
      const authHeader = socket.handshake.headers.authorization;
      if (authHeader.startsWith('Bearer ')) {
        const token = authHeader.slice(7);
        try {
          const parts = token.split('.');
          if (parts.length === 3) {
            const payload = Buffer.from(parts[1], 'base64url').toString('utf8');
            const claims = JSON.parse(payload);
            if (claims.sub) userId = claims.sub;
          }
        } catch (_) {
          // malformed token
        }
      }
    }

    // 3. Verify against DB (if pool available)
    if (pool && userId) {
      const result = await pool.query(
        'SELECT id, is_active, role FROM users WHERE id = $1',
        [userId]
      );
      if (result.rows.length === 0) {
        return next(new Error('Authentication failed: User not found'));
      }
      const userRow = result.rows[0];
      if (!userRow.is_active) {
        return next(new Error('Authentication failed: User is inactive'));
      }
      socket.user = {
        id: userRow.id,
        role: userRow.role || 'consumer',
      };
      socket.userId = userRow.id;
      socket.userRole = userRow.role || 'consumer';
    } else if (!userId) {
      // Anonymous connections allowed for public features (video viewing, etc.)
      socket.user = null;
      socket.userId = null;
      socket.userRole = null;
    }

    next();
  } catch (err) {
    console.error('[SocketAuth] Connection auth error:', err.message);
    next(new Error('Internal server error during authentication'));
  }
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
      max: parseInt(process.env.DB_POOL_MAX) || 20,           // R11: connection pool limit
      statement_timeout: parseInt(process.env.DB_STATEMENT_TIMEOUT_MS) || 30000,  // R10: 30s query timeout
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
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
        // ✅ init thumbnail queue worker ด้วย pool ที่ยืนยันแล้ว
        thumbnailQueue.init(pool);
        // --- 4. การจัดการ State ข้ามอุปกรณ์ ด้วย WebSocket / Local Sync ---
        // Phase 2: Init sync queue and enqueue startup reconcile job
        syncQueueService.init(pool, supabase);
        if (supabase) {
           syncQueueService.enqueueSync({ syncType: 'startup' }).catch(err => {
               console.error('[Sync] Startup sync enqueue failed:', err.message);
           });
        }
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

// =====================================================
// Phase 1 Middleware — Redis-based (ฟรี 100%)
// Rate Limiting · Idempotency · Cache-Aside
// ดูรายละเอียด: docs/infrastructure/architecture_analysis.md
// =====================================================
const {
  defaultRateLimiter,
  strictRateLimiter,
  authRateLimiter,
  idempotencyMiddleware,
  checkDuplicate,
  clearDuplicate,
  duplicateCheckMiddleware,
  cacheAside,
  invalidateCache,
  invalidateCacheMany,
  getSession,
  setSession,
  deleteSession,
  TTL,
  isHealthy: isRedisHealthy,
} = require('./middleware');

// Middleware
app.use(cors(corsOptions));
app.use(express.json({ limit: '10mb' })); // R8: body size limit

// ✅ Rate Limiter: ใช้กับ API ทั้งหมด (60 req/min per IP)
// ยกเว้น Static Files ที่ express.static จัดการเอง
app.use('/api', defaultRateLimiter);

// Serve static directory for fallback video playback
const videoDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, 'temp/videos');

// 🚨 ตรวจสอบ External Drive / TEMP_VIDEO_PATH
if (process.env.TEMP_VIDEO_PATH) {
  if (!require('fs').existsSync(process.env.TEMP_VIDEO_PATH)) {
    console.error('');
    console.error('  ══════════════════════════════════════════════════════════════');
    console.error('  ⚠️  [Storage] External Drive ไม่พบ หรือยังไม่ได้ Mount!');
    console.error(`  ❌  Path ที่ตั้งค่าไว้: ${process.env.TEMP_VIDEO_PATH}`);
    console.error('  ──────────────────────────────────────────────────────────────');
    console.error('  📌  วิธีแก้ไข:');
    console.error('      1. เสียบ External Drive และรอจนแสดงใน Finder');
    console.error('      2. หรือแก้ไข TEMP_VIDEO_PATH ใน websocket-server/.env');
    console.error(`  ⚡  กำลังใช้ Fallback Path: ${path.join(__dirname, 'temp/videos')}`);
    console.error('  ══════════════════════════════════════════════════════════════');
    console.error('');
  } else {
    console.log(`✅ [Storage] External Drive พร้อมใช้งาน: ${process.env.TEMP_VIDEO_PATH}`);
  }
}

app.use('/temp/videos', express.static(videoDir));

// ✅ Persistent thumbnail storage — ไม่ถูก cleanup เหมือน temp/videos
const thumbnailUploadDir = path.join(__dirname, 'uploads/thumbnails');
if (!require('fs').existsSync(thumbnailUploadDir)) {
  require('fs').mkdirSync(thumbnailUploadDir, { recursive: true });
}
app.use('/uploads/thumbnails', express.static(thumbnailUploadDir));

// ✅ Serve static watermarks
const watermarksUploadDir = path.join(__dirname, 'uploads/watermarks');
if (!require('fs').existsSync(watermarksUploadDir)) {
  require('fs').mkdirSync(watermarksUploadDir, { recursive: true });
}
app.use('/uploads/watermarks', express.static(watermarksUploadDir));

// Video Routes
const thumbnailQueue = require('./services/thumbnail-queue');
app.use('/api/consultations', verifyToken(pool));
app.use('/api/consultations', consultationRoutes());
if (pool) {
  // Phase 1 — Route Security: verify identity before protected routes
  app.use('/api/admin', verifyToken(pool));
  app.use('/api/admin', adminRoutes(pool));

  // Write endpoints on videos require auth; reads remain open
  app.use('/api/videos', verifyToken(pool));
  app.use('/api/videos', videoRoutes(pool));
}

// Phase 2: Health Check Endpoint for BullMQ Queues
const queueRegistry = require('./queues');
app.get('/health/queues', async (req, res) => {
  try {
    const snapshot = await queueRegistry.getHealthSnapshot();
    res.status(snapshot.healthy ? 200 : 503).json(snapshot);
  } catch (err) {
    console.error('[Health] Queue health check failed:', err.message);
    res.status(500).json({ error: 'Health check failed', detail: err.message });
  }
});

// Phase 2: DLQ / Failed Job Inspection Endpoint
app.get('/health/queues/:queueName/failed', async (req, res) => {
  try {
    const { queueName } = req.params;
    const { start = 0, end = 49 } = req.query;
    const jobs = await queueRegistry.getFailedJobs(queueName, parseInt(start, 10), parseInt(end, 10));
    res.json({ queue: queueName, failedJobs: jobs, count: jobs.length });
  } catch (err) {
    console.error(`[Health] Failed to fetch DLQ for ${req.params.queueName}:`, err.message);
    res.status(500).json({ error: 'DLQ inspection failed', detail: err.message });
  }
});

// Phase 2: Requeue failed job endpoint
app.post('/health/queues/:queueName/retry', async (req, res) => {
  try {
    const { queueName } = req.params;
    const { jobId } = req.body || {};
    if (!jobId) {
      return res.status(400).json({ error: 'jobId required' });
    }

    await queueRegistry.retryJob(queueName, jobId);
    res.json({ queue: queueName, jobId, retried: true });
  } catch (err) {
    console.error(`[Health] Failed to retry job ${req.params.queueName}:`, err.message);
    res.status(500).json({ error: 'Requeue failed', detail: err.message });
  }
});

// Store connected users
const connectedUsers = new Map();

// ============================================================
// ✅ [Yield Way] Helper: คัดกรองและส่งแจ้งเตือนให้ผู้ใช้บนเส้นทาง
// ============================================================

/**
 * แปลง Google Maps encoded polyline → array ของ {lat, lng}
 */
function _decodePolyline(encoded) {
  const result = [];
  let index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    let b, shift = 0, result2 = 0;
    do { b = encoded.charCodeAt(index++) - 63; result2 |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    lat += (result2 & 1) ? ~(result2 >> 1) : (result2 >> 1);
    shift = 0; result2 = 0;
    do { b = encoded.charCodeAt(index++) - 63; result2 |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    lng += (result2 & 1) ? ~(result2 >> 1) : (result2 >> 1);
    result.push({ lat: lat * 1e-5, lng: lng * 1e-5 });
  }
  return result;
}

/**
 * คำนวณระยะห่างระหว่าง 2 พิกัด (เมตร) — Haversine
 */
function _haversineDistance(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat/2) ** 2 + Math.cos(lat1 * Math.PI/180) * Math.cos(lat2 * Math.PI/180) * Math.sin(dLng/2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * ตรวจสอบว่าพิกัดผู้ใช้อยู่ใกล้เส้น polyline ภายใน tolerance (เมตร) หรือไม่
 */
function _isPointNearPolyline(userLat, userLng, polylinePoints, toleranceMeters = 80) {
  for (const pt of polylinePoints) {
    if (_haversineDistance(userLat, userLng, pt.lat, pt.lng) <= toleranceMeters) return true;
  }
  return false;
}

/**
 * ส่งการแจ้งเตือน 'yield-way-alert' ให้กับผู้ใช้ที่:
 * 1. เปิด isThaiMhungEnabled
 * 2. อยู่ในรัศมี yieldWayRadius จากจุดเกิดเหตุ
 * 3. ตำแหน่งปัจจุบันอยู่บนหรือใกล้เส้นทางของจิตอาสา
 */
async function _broadcastYieldWayAlerts(io, pool, videoId, encodedPolyline, incidentLat, incidentLng) {
  try {
    const polylinePoints = _decodePolyline(encodedPolyline);
    if (polylinePoints.length === 0) return;

    // ดึงข้อมูล video เพื่อรู้ชื่อหมวดหมู่
    let categoryName = 'เหตุฉุกเฉิน';
    try {
      const vRes = await pool.query(
        `SELECT vc.name as category_name FROM videos v
         LEFT JOIN video_categories vc ON v.category_id = vc.id
         WHERE v.id = $1`, [videoId]
      );
      if (vRes.rows.length > 0) categoryName = vRes.rows[0].category_name || categoryName;
    } catch (_) {}

    // ตรวจสอบผู้ใช้ที่ connected อยู่ในห้อง
    let notifiedCount = 0;
    for (const [userId, userData] of connectedUsers) {
      const { socketId, userLat, userLng, isYieldWayEnabled, yieldWayRadius, isVolunteer } = userData || {};
      if (!socketId || !userLat || !userLng) continue;
      if (!isYieldWayEnabled) continue; // ต้องเปิด is_yield_way_enabled

      // เงื่อนไข Type B: อยู่ในรัศมีจากจุดเกิดเหตุ
      const distToIncident = _haversineDistance(userLat, userLng, incidentLat, incidentLng);
      const radius = yieldWayRadius || 1000;
      if (distToIncident > radius) continue;

      // เงื่อนไข: อยู่บน/ใกล้เส้นทาง polyline
      if (!_isPointNearPolyline(userLat, userLng, polylinePoints)) continue;

      // ส่งแจ้งเตือนให้ socket นั้น
      io.to(socketId).emit('yield-way-alert', {
        videoId,
        categoryName,
        incidentLat,
        incidentLng,
        userLat,
        userLng,
        encodedPolyline,
        distanceMeters: Math.round(distToIncident),
      });
      notifiedCount++;
    }
    console.log(`[Yield Way] Notified ${notifiedCount} users on route for video ${videoId}`);
  } catch (err) {
    console.error('[Yield Way] _broadcastYieldWayAlerts error:', err.message);
  }
}

// R12: Socket.IO Event Rate Limiter — 20 events/sec per connection
const SOCKET_EVENT_RATE_LIMIT = 20;
const SOCKET_EVENT_WINDOW_MS = 1000;
const socketEventCounts = new Map();

function socketRateLimit(socket, eventName) {
  const now = Date.now();
  const key = `${socket.id}:${Math.floor(now / SOCKET_EVENT_WINDOW_MS)}`;
  const count = (socketEventCounts.get(key) || 0) + 1;
  socketEventCounts.set(key, count);

  if (count > SOCKET_EVENT_RATE_LIMIT) {
    console.warn(`[SocketRateLimit] 🚫 ${socket.id} — event '${eventName}' rate-limited (${count}/${SOCKET_EVENT_RATE_LIMIT} per sec)`);
    return false;
  }

  if (count === 1) {
    setTimeout(() => socketEventCounts.delete(key), SOCKET_EVENT_WINDOW_MS * 2);
  }
  return true;
}

// WebSocket Connection Handler
io.on('connection', (socket) => {
  console.log(`User connected: ${socket.id}`);

  // User connected event
  socket.on('user-connected', async (data) => {
    const { userId, isThaiMhungEnabled, isYieldWayEnabled, yieldWayRadius, latitude, longitude } = data;

    // Defense-in-depth: if connection-level auth resolved a user, the event userId must match
    if (socket.userId && socket.userId !== userId) {
      console.warn(`[SocketAuth] user-connected mismatch: socket.userId=${socket.userId}, data.userId=${userId}`);
      socket.emit('error', { message: 'User identity mismatch' });
      return;
    }

    // ✅ [Yield Way] เก็บข้อมูลครบถ้วนสำหรับการคัดกรองใน _broadcastYieldWayAlerts
    connectedUsers.set(userId, {
      socketId: socket.id,
      userId,
      isThaiMhungEnabled: isThaiMhungEnabled === true,
      isYieldWayEnabled: isYieldWayEnabled === true,
      yieldWayRadius: yieldWayRadius || 1000,
      userLat: latitude || null,
      userLng: longitude || null,
    });
    socket.userId = userId;

    console.log(`User ${userId} connected (socket: ${socket.id}, thaiMhung: ${isThaiMhungEnabled}, yieldWay: ${isYieldWayEnabled})`);

    // Join user's personal room
    socket.join(`user-${userId}`);
    console.log(`User ${userId} joined room user-${userId}`);

    // Notify others that user is online
    socket.broadcast.emit('user-online', { userId });
  });

  // Location update event
  socket.on('location-update', async (data) => {
    if (!socketRateLimit(socket, 'location-update')) return;
    const { userId, latitude, longitude, timestamp, accuracy, speed, heading } = data;

    // Defense-in-depth: validate userId matches pre-authenticated socket user
    if (socket.userId && socket.userId !== userId) {
      console.warn(`[SocketAuth] location-update mismatch: socket.userId=${socket.userId}, data.userId=${userId}`);
      socket.emit('error', { message: 'User identity mismatch' });
      return;
    }

    // ✅ [Yield Way] อัพเดตตำแหน่งใน connectedUsers เพื่อใช้คัดกรองแบบ Real-time
    if (userId && connectedUsers.has(userId)) {
      const existing = connectedUsers.get(userId);
      connectedUsers.set(userId, { ...existing, userLat: latitude, userLng: longitude });
    }

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
    if (!socketRateLimit(socket, 'video-interaction')) return;
    // ✅ รองรับ requestId เพื่อแยกยอดบริจาคตามคำร้องแต่ละใบในวิดีโอเดียวกัน
    const { videoId, userId, type, value, requestId } = data;

    // Defense-in-depth: validate userId matches pre-authenticated socket user
    if (socket.userId && socket.userId !== userId) {
      console.warn(`[SocketAuth] video-interaction mismatch: socket.userId=${socket.userId}, data.userId=${userId}`);
      socket.emit('error', { message: 'User identity mismatch' });
      return;
    }

    console.log(`[Video ${videoId}] Interaction from ${userId}: ${type} (${value}) requestId=${requestId}`);

    if (pool && videoId && userId) {
      try {
        // ✅ [Support Analytics] 'like' toggle is handled via HTTP API (POST /:id/interactions)
        // Skip DB insert here to avoid double-counting. Flutter emits 'like-toggled' for broadcast.
        if (type !== 'like') {
          await pool.query(
            `INSERT INTO video_interactions (video_id, user_id, type, value, created_at)
             VALUES ($1, $2, $3, $4, NOW())`,
            [videoId, userId, type, value || 0]
          );
        }

        // [Donation Integration]: ถ้าเป็นการบริจาค (gift) ให้อัปเดต donation_request ที่เกี่ยวข้อง
        if (type === 'gift') {
          try {
            let donationRes;
            if (requestId) {
              // ✅ มี requestId → อัปเดตเฉพาะคำร้องใบนั้น (Multi-request Support)
              donationRes = await pool.query(
                `UPDATE donation_requests 
                 SET current_amount = current_amount + $1, updated_at = NOW() 
                 WHERE id = $2 AND video_id = $3 AND approval_status = 'active'
                 RETURNING id, current_amount, target_amount, title`,
                [value || 0, requestId, videoId]
              );
            } else {
              // ✅ ไม่มี requestId → Fallback: อัปเดตคำร้องแรกที่ active ของวิดีโอนี้
              donationRes = await pool.query(
                `UPDATE donation_requests 
                 SET current_amount = current_amount + $1, updated_at = NOW() 
                 WHERE video_id = $2 AND approval_status = 'active'
                 ORDER BY created_at ASC
                 LIMIT 1
                 RETURNING id, current_amount, target_amount, title`,
                [value || 0, videoId]
              );
            }
            if (donationRes && donationRes.rows.length > 0) {
              const updatedDonation = donationRes.rows[0];
              console.log(`[Donation] Updated request ${updatedDonation.id} for video ${videoId}: ${updatedDonation.current_amount}/${updatedDonation.target_amount}`);
              // ✅ broadcast donation update พร้อม requestId เพื่อให้ Flutter แยกยอดได้ถูกต้อง
              io.to(`room-video-${videoId}`).emit('donation-progress-updated', {
                videoId,
                requestId: updatedDonation.id,
                donationTitle: updatedDonation.title,
                currentAmount: updatedDonation.current_amount,
                targetAmount: updatedDonation.target_amount,
              });
            }
          } catch (donErr) {
            console.error('[Donation] Failed to update current_amount:', donErr.message);
          }
        }

        // Broadcast interaction กลับไปยัง clients ในห้อง พร้อม requestId
        socketService.broadcastInteraction(videoId, { videoId, userId, type, value, requestId });

        // ✅ [Yield Way Integration]: คำนวณเปอร์เซ็นต์การให้ทาง
        if (type === 'yield-way') {
          try {
            // ✅ บันทึกลง yield_way_histories (ป้องกัน duplicate ด้วย ON CONFLICT)
            await pool.query(
              `INSERT INTO yield_way_histories (user_id, video_id)
               VALUES ($1, $2)
               ON CONFLICT DO NOTHING`,
              [userId, videoId]
            ).catch(() => {}); // ไม่ผิดพลาดถ้าตารางยังไม่มี

            // นับจำนวนผู้ให้ทางทั้งหมด (Unique Users) แบบ Raw Count
            const yieldRes = await pool.query(
              `SELECT COUNT(DISTINCT user_id) as count FROM video_interactions 
               WHERE video_id = $1 AND type = 'yield-way'`,
              [videoId]
            );
            const yieldCount = parseInt(yieldRes.rows[0].count);

            console.log(`[Yield Way] Video ${videoId}: ${yieldCount} users yielding`);

            // Broadcast yield-way-updated event พร้อม raw count + animation trigger
            io.to(`room-video-${videoId}`).emit('video-interaction', {
              videoId,
              type: 'yield-way-updated',
              count: yieldCount,
              triggerAnimation: true, // ✅ สัญญาณให้ Flutter เล่น animation บนแผนที่
              triggeredByUserId: userId,
            });
          } catch (yieldErr) {
            console.error('[Yield Way] Failed to save history:', yieldErr.message);
          }
        }
      } catch (err) {
        console.error('Failed to save interaction:', err.message);
      }
    } else {
      // Demo mode / No DB: Broadcast blindly
      socketService.broadcastInteraction(videoId, { videoId, userId, type, value, requestId });
    }
  });

  // ✅ [Support Analytics] like-toggled: Flutter emits this after HTTP toggle succeeds
  // Server broadcasts 'like-count-updated' to all clients in the video room
  socket.on('like-toggled', (data) => {
    if (!socketRateLimit(socket, 'like-toggled')) return;
    const { videoId, count, liked, userId } = data;
    if (!videoId) return;
    console.log(`[Like] Video ${videoId}: ${liked ? '+1' : '-1'} by ${userId}, total=${count}`);
    io.to(`room-video-${videoId}`).emit('like-count-updated', { videoId, count, liked });
  });

  // ✅ [Yield Way] รับ Route Polyline ของจิตอาสา — บันทึกลง DB เพื่อใช้คัดกรองผู้รับแจ้งเตือน
  socket.on('volunteer-route', async (data) => {
    const { videoId, responseId, encodedPolyline, fromLat, fromLng, toLat, toLng, userId } = data;

    // Defense-in-depth: validate userId matches pre-authenticated socket user
    if (socket.userId && socket.userId !== userId) {
      console.warn(`[SocketAuth] volunteer-route mismatch: socket.userId=${socket.userId}, data.userId=${userId}`);
      socket.emit('error', { message: 'User identity mismatch' });
      return;
    }

    console.log(`[Yield Way] Volunteer route received for video ${videoId}, response ${responseId}`);

    if (pool && responseId && encodedPolyline) {
      try {
        await pool.query(
          `UPDATE incident_responses 
           SET route_polyline = $1, route_from_lat = $2, route_from_lng = $3,
               route_to_lat = $4, route_to_lng = $5
           WHERE id = $6`,
          [encodedPolyline, fromLat, fromLng, toLat, toLng, responseId]
        );
        console.log(`[Yield Way] Route saved for response ${responseId}`);

        // ทันทีหลังบันทึก route → ส่งการแจ้งเตือนให้ผู้ใช้ที่อยู่บนเส้นทาง
        await _broadcastYieldWayAlerts(io, pool, videoId, encodedPolyline, toLat, toLng);
      } catch (err) {
        console.error('[Yield Way] Failed to save route:', err.message);
      }
    }
  });

  // ✅ [Yield Way] Request Notification — เรียกซ้ำเมื่อต้องการส่งแจ้งเตือนใหม่
  socket.on('request-yield-way-notification', async (data) => {
    const { videoId, responseId } = data;
    if (!pool || !videoId) return;
    try {
      const res = await pool.query(
        `SELECT route_polyline, route_to_lat, route_to_lng 
         FROM incident_responses WHERE id = $1`,
        [responseId]
      );
      if (res.rows.length > 0 && res.rows[0].route_polyline) {
        const { route_polyline, route_to_lat, route_to_lng } = res.rows[0];
        await _broadcastYieldWayAlerts(io, pool, videoId, route_polyline, route_to_lat, route_to_lng);
      }
    } catch (err) {
      console.error('[Yield Way] request-yield-way-notification error:', err.message);
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

        let potentialUserIds = (roles || []).map(r => r.user_id);
        
        // --- DEV FALLBACK: ดึงจาก Local DB ถ้า Supabase ไม่มีข้อมูล ---
        if (process.env.NODE_ENV === 'development' && potentialUserIds.length === 0 && pool) {
          console.log('[Emergency] [Dev] No potential users in Supabase, checking Local DB...');
          try {
            const localRoles = await pool.query(
              'SELECT user_id FROM user_group_roles WHERE profession_id = ANY($1)',
              [volunteerProfIds]
            );
            potentialUserIds = localRoles.rows.map(r => r.user_id);
            console.log(`[Emergency] [Dev] Found ${potentialUserIds.length} users in Local DB`);
          } catch (err) {
            console.warn('[Emergency] [Dev] Local roles query failed:', err.message);
          }
        }

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

        let targetUserIds = (activeProfiles || []).map(p => p.user_id);
        
        // --- DEV FALLBACK: ดึงจาก Local DB ถ้า Supabase ไม่มีข้อมูล ---
        if (process.env.NODE_ENV === 'development' && targetUserIds.length === 0 && pool) {
          console.log('[Emergency] [Dev] No active volunteers in Supabase, checking Local DB profiles...');
          try {
            const localProfiles = await pool.query(
              'SELECT user_id FROM consumer_profiles WHERE user_id = ANY($1) AND is_volunteer_active = true',
              [potentialUserIds]
            );
            targetUserIds = localProfiles.rows.map(p => p.user_id);
            console.log(`[Emergency] [Dev] Found ${targetUserIds.length} active volunteers in Local DB`);
          } catch (err) {
            console.warn('[Emergency] [Dev] Local profiles query failed:', err.message);
          }
        }

        console.log(`[Emergency] Target volunteers (${targetUserIds.length}): ${JSON.stringify(targetUserIds)}`);

        // 2d. ส่งเฉพาะ volunteer ที่เกี่ยวข้อง (และไม่ใช่ผู้แจ้งเหตุเอง)
        if (targetUserIds.length === 0) {
          console.warn('[Emergency] ⚠️  No active volunteers found for this category → silent (no broadcast)');
        } else {
          let sentCount = 0;
          targetUserIds.forEach(targetId => {
            // ✅ ไม่ส่งหาตัวเอง (ข้ามผู้แจ้งเหตุ) เวนแต่จะเป็นโหมดพัฒนาเพื่อทดสอบคนเดียว
            if (targetId.toString() !== userId.toString() || process.env.NODE_ENV === 'development') {
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


  // ── Donation Status Notification ──
  // ส่งจาก Flutter เมื่อ approveRequest() เปลี่ยนสถานะ → ส่งต่อให้เจ้าของคำร้อง
  socket.on('donation-request-status-updated', (data) => {
    const { userId, requestId, title, status } = data;
    console.log(`[Donation] Status updated: requestId=${requestId} status=${status} -> notify userId=${userId}`);
    if (userId) {
      const payload = {
        userId,
        requestId,
        title: title || 'คำร้องบริจาค',
        status,
        timestamp: new Date().toISOString(),
      };

      notificationQueueService
        .enqueueSocketToUser(userId, 'donation-request-status-updated', payload)
        .then((job) => {
          console.log(`[Notification] Queued donation status alert jobId=${job.id}`);
        })
        .catch((err) => {
          console.error('[Notification] Failed to enqueue donation alert, fallback emit:', err.message);
          io.to(`user-${userId}`).emit('donation-request-status-updated', payload);
        });
    }
  });

  // ── Donation Closed by Requester ──
  // ผู้ร้องขอปิดรับบริจาค (completed) → แจ้งผู้ดูไลฟ์ทุกคน
  socket.on('donation-closed', (data) => {
    const { videoId, requestId, title, currentAmount, reason } = data;
    console.log(`[Donation] Requester closed request=${requestId} for video=${videoId} reason=${reason}`);
    if (videoId) {
      io.to(`room-video-${videoId}`).emit('donation-closed', {
        videoId,
        requestId,
        title: title || 'คำร้องบริจาค',
        currentAmount: currentAmount || 0,
        reason: reason || 'completed_by_requester',
        timestamp: new Date().toISOString(),
      });
    }
  });

  // ── Donate Closure Vote (Consensus) ──
  // Responder โหวตว่าจะรับบริจาคต่อหรือไม่หลัง Mission Complete
  // event: { requestId, responderId, canContinue, note? }
  socket.on('donate-closure-vote', async (data) => {
    const { requestId, responderId, canContinue, note } = data;
    console.log(`[Escrow] donate-closure-vote: request=${requestId} responder=${responderId} canContinue=${canContinue}`);

    if (!requestId || !responderId) {
      socket.emit('donate-closure-vote-result', { success: false, error: 'Missing requestId or responderId' });
      return;
    }

    // Phase 2: Enqueue to BullMQ instead of blocking the WebSocket event loop
    try {
      const { jobId, queued } = await donationQueueService.enqueueConsensusVote(
        requestId,
        responderId,
        canContinue === true,
        note || null,
      );

      socket.emit('donate-closure-vote-result', {
        success: true,
        queued: true,
        jobId,
        message: 'Consensus vote queued for processing',
      });
      console.log(`[Escrow] Vote queued as job ${jobId} for request=${requestId}`);
    } catch (err) {
      console.error('[Escrow] Failed to enqueue consensus vote:', err.message);
      socket.emit('donate-closure-vote-result', { success: false, error: err.message });
    }
  });

  // ── Admin Manual Escrow Release ──
  // Admin บังคับ release escrow ด้วยตนเอง
  // event: { requestId, adminUserId }
  socket.on('admin-release-escrow', async (data) => {
    const { requestId, adminUserId } = data;
    console.log(`[Escrow] admin-release-escrow: request=${requestId} admin=${adminUserId}`);

    if (!requestId) {
      socket.emit('admin-release-escrow-result', { success: false, error: 'Missing requestId' });
      return;
    }

    // Phase 2: Enqueue to BullMQ instead of blocking the WebSocket event loop
    try {
      const { jobId, queued } = await donationQueueService.enqueueEscrowRelease(requestId, 'manual_admin');

      socket.emit('admin-release-escrow-result', {
        success: true,
        queued: true,
        jobId,
        message: 'Escrow release queued for processing',
      });
      console.log(`[Escrow] Admin release queued as job ${jobId} for request=${requestId}`);
    } catch (err) {
      console.error('[Escrow] Failed to enqueue escrow release:', err.message);
      socket.emit('admin-release-escrow-result', { success: false, error: err.message });
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
    if (!socketRateLimit(socket, 'send-emergency-message')) return;
    const { videoId, userId, role, userName, content, profileImageUrl, professionName } = data;
    console.log(`[Chat] Message in ${videoId} from ${userName} (${role}/${professionName || 'no-prof'}): ${content}`);

    const messagePayload = {
      id: require('crypto').randomUUID(), // ✅ UUID แทน Date.now() เพื่อป้องกัน ID ชนกัน
      videoId,
      userId,
      role,
      userName,
      content,
      profileImageUrl,
      professionName,
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
          [messagePayload.id, roomId, userId, content, JSON.stringify({ role, userName, profileImageUrl, professionName })]
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

    const data = await cacheAside(`chat:active:${videoId}:${limit}`, async () => {
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
           m.metadata->>'profileImageUrl' AS "profileImageUrl",
           m.metadata->>'professionName' AS "professionName"
         FROM chat_messages m
         JOIN chat_rooms r ON m.room_id = r.id
         WHERE r.video_id = $1
         ORDER BY m.created_at ASC
         LIMIT $2`,
        [videoId, limit]
      );
      return result.rows;
    }, TTL.SESSION);

    res.json(data);
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

    const data = await cacheAside(`chat:archived:${videoId}:${limit}`, async () => {
      const result = await pool.query(
        `SELECT
           a.id,
           a.video_id           AS "videoId",
           a.sender_id          AS "userId",
           a.content,
           a.created_at         AS "timestamp",
           a.metadata->>'role'         AS role,
           a.metadata->>'userName'     AS "userName",
           a.metadata->>'profileImageUrl' AS "profileImageUrl",
           a.metadata->>'professionName' AS "professionName"
         FROM chat_messages_archive a
         WHERE a.video_id = $1
         ORDER BY a.created_at ASC
         LIMIT $2`,
        [videoId, limit]
      );
      return result.rows;
    }, TTL.SESSION);

    res.json(data);
  } catch (error) {
    console.error('[Chat Archive History] Error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// POST /api/chat/archive/:videoId — Manual archive trigger via REST
app.post('/api/chat/archive/:videoId', strictRateLimiter, duplicateCheckMiddleware('chat-archive', 10), async (req, res) => {
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
app.get('/health', async (req, res) => {
  // ✅ Phase 1: เพิ่ม Redis health status
  const redisOk = await isRedisHealthy().catch(() => false);
  res.json({
    status: 'ok',
    connectedUsers: connectedUsers.size,
    database: pool ? 'connected' : 'not connected',
    redis: redisOk ? 'connected' : 'not connected',
    middleware: {
      rateLimiter: 'active',
      idempotency: 'active',
      cacheAside: 'active',
    },
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

// ============ EMERGENCY HEALTH API ============

app.post('/api/emergency-health/sessions', strictRateLimiter, duplicateCheckMiddleware('emergency-health-session', 10), async (req, res) => {
  try {
    const { patientId, incidentId, videoId } = req.body || {};
    const result = await emergencyHealthSessionService.createReleaseSession({
      patientId,
      incidentId,
      videoId,
    });

    if (!result.created) {
      return res.status(200).json(result);
    }

    return res.status(201).json(result);
  } catch (error) {
    console.error('[EmergencyHealth] create session error:', error.message);
    return res.status(500).json({ error: error.message });
  }
});

app.get('/api/emergency-health/:incidentId', async (req, res) => {
  try {
    const { incidentId } = req.params;
    const { responderId } = req.query;

    if (!responderId) {
      return res.status(400).json({ error: 'responderId is required' });
    }

    const data = await cacheAside(`emergency-health:${incidentId}:${responderId}`, async () => {
      const result = await emergencyHealthSessionService.getIncidentHealthData({
        incidentId,
        responderId,
      });
      return result;
    }, TTL.SESSION);

    if (!data.allowed) {
      return res.status(403).json(data);
    }

    return res.status(200).json(data);
  } catch (error) {
    console.error('[EmergencyHealth] get health data error:', error.message);
    return res.status(500).json({ error: error.message });
  }
});

app.post('/api/emergency-health/revoke', strictRateLimiter, duplicateCheckMiddleware('emergency-health-revoke', 10), async (req, res) => {
  try {
    const { patientId } = req.body || {};

    if (!patientId) {
      return res.status(400).json({ error: 'patientId is required' });
    }

    const result = await emergencyHealthSessionService.revokeActiveSessions({
      patientId,
    });

    return res.status(200).json(result);
  } catch (error) {
    console.error('[EmergencyHealth] revoke sessions error:', error.message);
    return res.status(500).json({ error: error.message });
  }
});

app.get('/api/emergency-health/settings/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const data = await cacheAside(`emergency-health:settings:${userId}`, async () => {
      const settings = await emergencyHealthSessionService.getEmergencyHealthSettings({ userId });
      return { settings };
    }, TTL.SESSION);
    return res.status(200).json(data);
  } catch (error) {
    console.error('[EmergencyHealth] get settings error:', error.message);
    return res.status(500).json({ error: error.message });
  }
});

app.post('/api/emergency-health/settings', strictRateLimiter, duplicateCheckMiddleware('emergency-health-settings', 10), async (req, res) => {
  try {
    const { userId, settings } = req.body || {};
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }

    const saved = await emergencyHealthSessionService.upsertEmergencyHealthSettings({
      userId,
      settings,
    });

    return res.status(200).json({ settings: saved });
  } catch (error) {
    console.error('[EmergencyHealth] save settings error:', error.message);
    return res.status(500).json({ error: error.message });
  }
});

app.get('/api/emergency-health/dead-man/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const data = await cacheAside(`emergency-health:dead-man:${userId}`, async () => {
      const checkin = await emergencyHealthSessionService.getDeadManCheckin({ userId });
      return { checkin };
    }, TTL.SESSION);
    return res.status(200).json(data);
  } catch (error) {
    console.error('[EmergencyHealth] get dead-man check-in error:', error.message);
    return res.status(500).json({ error: error.message });
  }
});

app.post('/api/emergency-health/dead-man', strictRateLimiter, duplicateCheckMiddleware('emergency-health-deadman', 10), async (req, res) => {
  try {
    const { userId, checkin } = req.body || {};
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }

    const saved = await emergencyHealthSessionService.upsertDeadManCheckin({
      userId,
      checkin,
    });

    return res.status(200).json({ checkin: saved });
  } catch (error) {
    console.error('[EmergencyHealth] save dead-man check-in error:', error.message);
    return res.status(500).json({ error: error.message });
  }
});

app.post('/api/emergency-health/dead-man/check-in', strictRateLimiter, duplicateCheckMiddleware('emergency-health-checkin', 5), async (req, res) => {
  try {
    const { userId, checkInAt } = req.body || {};
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }

    const saved = await emergencyHealthSessionService.updateDeadManCheckInTimestamp({
      userId,
      checkInAt: checkInAt ? new Date(checkInAt) : undefined,
    });

    return res.status(200).json({ checkin: saved });
  } catch (error) {
    console.error('[EmergencyHealth] dead-man check-in error:', error.message);
    return res.status(500).json({ error: error.message });
  }
});

// ============ PROFESSIONS API ============

// Get all professions
app.get('/api/professions', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database not available' });
    }

    const data = await cacheAside('professions:active', async () => {
      const result = await pool.query(
        `SELECT id, name, name_en, description, icon_name, category, 
                is_built_in, is_active, requires_verification, display_order,
                created_at, updated_at
         FROM professions 
         WHERE is_active = true 
         ORDER BY display_order ASC`
      );
      return result.rows;
    }, TTL.DEFAULT);
    res.json(data);
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
    const data = await cacheAside(`profession:${id}`, async () => {
      const result = await pool.query(
        `SELECT * FROM professions WHERE id = $1`,
        [id]
      );
      return result.rows[0] || null;
    }, TTL.DEFAULT);

    if (data === null) {
      return res.status(404).json({ error: 'Profession not found' });
    }

    res.json(data);
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
    const data = await cacheAside(`profession:fields:${id}`, async () => {
      const result = await pool.query(
        `SELECT id, field_id, label, hint, field_type, is_required, 
                field_order, icon_name, dropdown_options, validation_regex,
                validation_message, is_active
         FROM registration_field_configs 
         WHERE profession_id = $1 AND is_active = true
         ORDER BY field_order ASC`,
        [id]
      );
      return result.rows;
    }, TTL.DEFAULT);

    res.json(data);
  } catch (error) {
    console.error('Error fetching fields:', error);
    res.status(500).json({ error: 'Failed to fetch fields' });
  }
});

// ============ USERS API ============

// Create user
app.post('/api/users', strictRateLimiter, duplicateCheckMiddleware('user-create', 10), async (req, res) => {
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
    const data = await cacheAside(`user:${id}`, async () => {
      const result = await pool.query(
        `SELECT id, profession_id, first_name, last_name, username, email, 
                phone, profile_image_url, is_active, is_verified, created_at, updated_at
         FROM users 
         WHERE id = $1`,
        [id]
      );
      return result.rows[0] || null;
    }, TTL.DEFAULT);

    if (data === null) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(data);
  } catch (error) {
    console.error('Error fetching user:', error);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

// Update user
app.put('/api/users/:id', strictRateLimiter, duplicateCheckMiddleware('user-update', 10), async (req, res) => {
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
app.post('/api/applications', idempotencyMiddleware, strictRateLimiter, duplicateCheckMiddleware('application-submit', 10), async (req, res) => {
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
    const cacheKey = `applications:list:${status || 'all'}`;

    const data = await cacheAside(cacheKey, async () => {
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
      return result.rows;
    }, TTL.DEFAULT);

    res.json(data);
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
    const data = await cacheAside(`application:${id}`, async () => {
      const result = await pool.query(
        `SELECT a.*, p.name as profession_name
         FROM registration_applications a
         LEFT JOIN professions p ON a.profession_id = p.id
         WHERE a.id = $1`,
        [id]
      );
      return result.rows[0] || null;
    }, TTL.DEFAULT);

    if (data === null) {
      return res.status(404).json({ error: 'Application not found' });
    }

    res.json(data);
  } catch (error) {
    console.error('Error fetching application:', error);
    res.status(500).json({ error: 'Failed to fetch application' });
  }
});
// Approve application
app.post('/api/applications/:id/approve', strictRateLimiter, duplicateCheckMiddleware('application-approve', 10), async (req, res) => {
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

    // Update user profession and verification status
    await pool.query(
      `UPDATE users 
       SET profession_id = $1, 
           verification_status = 'verified',
           updated_at = NOW()
       WHERE id = $2`,
      [result.rows[0].profession_id, result.rows[0].user_id]
    );

    res.json({ message: 'Application approved', application: result.rows[0] });
  } catch (error) {
    console.error('Error approving application:', error);
    res.status(500).json({ error: 'Failed to approve application' });
  }
});

// Reject application
app.post('/api/applications/:id/reject', strictRateLimiter, duplicateCheckMiddleware('application-reject', 10), async (req, res) => {
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

    // Reset user profession to consumer and update verification status
    await pool.query(
      `UPDATE users 
       SET profession_id = '00000000-0000-0000-0000-000000000001',
           verification_status = 'rejected',
           updated_at = NOW()
       WHERE id = $1`,
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

// Handle server listen with automated IP detection
const PORT = process.env.PORT || 3000;
const os = require('os');

server.listen(PORT, '0.0.0.0', () => {
  const networkInterfaces = os.networkInterfaces();
  let localIp = 'localhost';

  // ตรวจหา IP ที่ไม่ใช่ 127.0.0.1 (Loopback)
  // ลำดับความสำคัญ: 1. LOCAL_API_URL (ถ้ามี), 2. 192.168.x.x, 3. 10.x.x.x, 4. อื่นๆ (ยกเว้น 169.254)
  if (process.env.LOCAL_API_URL) {
    try {
      const url = new URL(process.env.LOCAL_API_URL);
      localIp = url.hostname;
    } catch (e) {
      console.warn('⚠️  Invalid LOCAL_API_URL in .env');
    }
  }

  if (localIp === 'localhost') {
    Object.keys(networkInterfaces).forEach((ifname) => {
      networkInterfaces[ifname].forEach((iface) => {
        if ('IPv4' !== iface.family || iface.internal !== false) {
          return;
        }
        
        // ข้าม Self-assigned IP (169.254.x.x)
        if (iface.address.startsWith('169.254')) {
          return;
        }

        // ถ้าเจอ 192.168 หรือ 10. ให้ใช้ทันที (ส่วนใหญ่เป็น LAN IP จริง)
        if (iface.address.startsWith('192.168') || iface.address.startsWith('10.')) {
          localIp = iface.address;
        } else if (localIp === 'localhost') {
          localIp = iface.address;
        }
      });
    });
  }

  console.log(`
  ======================================================
  🚀 WebSocket Server (Sheserved) is READY!
  ======================================================
  📍 Local:    http://localhost:${PORT}
  🌍 Network:  http://${localIp}:${PORT}
  
  📱 กรุณาตรวจสอบ AppConfig.java หรือ AppConfig.dart
     และอัปเดต mainMachineIp ให้เป็น: ${localIp}
  ======================================================
  `);

  // 🔒 เริ่ม Escrow Deadline Checker (scheduled job ทุก 15 นาที)
  escrowDeadlineChecker.start();

  // � เริ่ม Inventory Alert Checker (scheduled job ทุก 24 ชั่วโมง)
  inventoryAlertChecker.start();

  // �🚨 เริ่ม Emergency Health Release Checker (scheduled job ทุก 30 วินาที)
  emergencyHealthReleaseChecker.start();

  // ⚠️ Phase 4 — Sensor Trigger + Dead Man's Switch monitor
  emergencyHealthMonitorService.start();

  // R9: Disk Cleanup Cron — ลบ temp files ที่เก่ากว่า 24h ทุก 1 ชั่วโมง
  const tempDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, 'temp/videos');
  const CLEANUP_INTERVAL_MS = 60 * 60 * 1000;
  const CLEANUP_MAX_AGE_MS = 24 * 60 * 60 * 1000;
  setInterval(() => {
    fs.promises.readdir(tempDir).then(entries => {
      const now = Date.now();
      for (const entry of entries) {
        const fullPath = path.join(tempDir, entry);
        fs.promises.stat(fullPath).then(stat => {
          if (now - stat.mtimeMs > CLEANUP_MAX_AGE_MS) {
            if (stat.isDirectory()) {
              fs.promises.rm(fullPath, { recursive: true, force: true })
                .then(() => console.log(`[Cleanup] 🗑️  Removed old temp dir: ${entry}`))
                .catch(err => console.warn(`[Cleanup] ⚠️  Failed to remove ${entry}:`, err.message));
            } else {
              fs.promises.unlink(fullPath)
                .then(() => console.log(`[Cleanup] 🗑️  Removed old temp file: ${entry}`))
                .catch(err => console.warn(`[Cleanup] ⚠️  Failed to remove ${entry}:`, err.message));
            }
          }
        }).catch(() => {});
      }
    }).catch(() => {});
  }, CLEANUP_INTERVAL_MS);
  console.log(`[Cleanup] ✅ Disk cleanup cron started — interval: ${CLEANUP_INTERVAL_MS / 60000}min, max age: ${CLEANUP_MAX_AGE_MS / 3600000}h`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[Server] SIGTERM received — shutting down gracefully');
  escrowDeadlineChecker.stop();
  inventoryAlertChecker.stop();
  emergencyHealthReleaseChecker.stop();
  emergencyHealthMonitorService.stop();
  queueRegistry.shutdownAll().catch((err) => {
    console.error('[Server] Queue registry shutdown failed:', err.message);
  }).finally(() => {
    server.close(() => process.exit(0));
  });
});

process.on('SIGINT', () => {
  console.log('[Server] SIGINT received — shutting down gracefully');
  escrowDeadlineChecker.stop();
  inventoryAlertChecker.stop();
  emergencyHealthReleaseChecker.stop();
  emergencyHealthMonitorService.stop();
  queueRegistry.shutdownAll().catch((err) => {
    console.error('[Server] Queue registry shutdown failed:', err.message);
  }).finally(() => {
    server.close(() => process.exit(0));
  });
});
