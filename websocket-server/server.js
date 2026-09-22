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

// File system module (used by disk cleanup cron and other fs.promises calls)
const fs = require('fs');

// Phase 13.0 — Validate environment before any service initializes
const { validateEnv } = require('./config/validate-env');
validateEnv();

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

// Service-role client for sync operations (bypass RLS)
// Phase 13.0: No silent fallback to anon key — fail loud if service key missing
const supabaseServiceKey = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
let supabaseForSync = null;
if (supabaseUrl && supabaseServiceKey) {
  supabaseForSync = createClient(supabaseUrl, supabaseServiceKey);
  console.log('✅ Supabase service-role client initialized for sync');
} else {
  console.error('❌ FATAL: SUPABASE_SERVICE_KEY (or SUPABASE_SERVICE_ROLE_KEY) is required for sync client. Sync will not work.');
  if (process.env.NODE_ENV === 'production') process.exit(1);
}

// Video System Services & Routes
const socketService = require('./services/socket-service');
const videoRoutes = require('./routes/video');
const adminRoutes = require('./routes/admin');
const consultationRoutes = require('./routes/consultation');
const victimsRoutes = require('./routes/victims');
// Phase 13.2 — Auth routes
const authRoutes = require('./routes/auth');
const { shutdown: shutdownConsultationQueue } = require('./services/consultation-queue');
const victimRetentionCountdownStarter = require('./jobs/victim-retention-countdown-starter');
const victimRetentionAnonymizer = require('./jobs/victim-retention-anonymizer');

// Phase 1 — Route Security Middleware
const { verifyToken, requireRole, requireAuth, strictRouteGuard, assertActorMatches, whenStrictRoute } = require('./middleware/auth');
const { socketAuthMiddleware, isVerifiedSocket, checkEventIdentity, claimedActorMismatch } = require('./middleware/socket-auth');
const { isStrictSocketEvent, strictSocketAuthEnabled, strictRoomAuthEnabled } = require('./config/rollout-flags');
const { authorizeRoomJoin } = require('./services/room-authorization');
const { requestContext } = require('./middleware/request-context');
const donationQueueService = require('./services/donation-queue');

// Escrow Services
const escrowReleaseService = require('./services/escrow-release-service');
const escrowDeadlineChecker = require('./services/escrow-deadline-checker');
const emergencyHealthReleaseChecker = require('./services/emergency-health-release-checker');
const emergencyHealthSessionService = require('./services/emergency-health-session-service');
const emergencyHealthMonitorService = require('./services/emergency-health-monitor-service');
const inventoryAlertChecker = require('./services/inventory-alert-checker');
const { archiveChatMessages } = require('./services/chat-archive-service');
const { notificationsRoutes, professionChangeRoute } = require('./routes/notifications');
const { sportsRoutes } = require('./routes/sports');
const { chatApiRoutes } = require('./routes/chat-api');
const { healthRoutes } = require('./routes/health');
const { emergencyHealthRoutes } = require('./routes/emergency-health');
const { professionsRoutes } = require('./routes/professions');
const { mediaRoutes } = require('./routes/media');
const { usersRoutes } = require('./routes/users');
const { applicationsRoutes } = require('./routes/applications');
const { locationsRoutes } = require('./routes/locations');
const { syncRoutes } = require('./routes/sync');
const queueRegistry = require('./queues');

// Sync Service
const { reconcileLocalToCloud } = require('./services/sync-service');
const syncQueueService = require('./services/sync-queue');
const notificationQueueService = require('./services/notification-queue');

const app = express();
const server = http.createServer(app);

// CORS configuration
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
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

// Phase 13.3 Step 7 — revocation propagation (Redis Pub/Sub → force-disconnect)
const { initSocketRevocation } = require('./services/socket-revocation');
initSocketRevocation(io);

// ── Phase 13.3 — Socket.IO Connection-Level Auth ──
// Signed Backend access token = the only trusted actor (signature, kid,
// iss, aud, exp, session revoke, active user — middleware/socket-auth.js).
// Legacy auth.userId / x-user-id handshakes = compatibility identity
// (not a trusted actor) until STRICT_SOCKET_AUTH cuts over.
io.use(
  socketAuthMiddleware({
    getPool: () => pool,
    supabaseForSync,
  })
);

// Database configuration (optional - can work without database)
let pool = null;
let fitnessBookingNotificationListenerClient = null;
let fitnessBookingNotificationListenerStarted = false;
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
        syncQueueService.init(pool, supabaseForSync);
        startFitnessBookingNotificationListener().catch(err => {
          console.error('[FitnessBuddies] Failed to start booking notification listener:', err.message);
        });
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
  invalidateCachePattern,
  getSession,
  setSession,
  deleteSession,
  TTL,
  isHealthy: isRedisHealthy,
} = require('./middleware');

// Middleware
const helmet = require('helmet');
app.use(helmet()); // Phase 13.2 — security headers
// Phase 13.2 — force-update policy: reject below MIN_APP_VERSION (426)
const { minAppVersionMiddleware } = require('./middleware/app-version');
app.use(minAppVersionMiddleware);
app.use(cors(corsOptions));
app.use(express.json({ limit: '10mb' })); // R8: body size limit
app.use(requestContext);

// ✅ Rate Limiter: ใช้กับ API ทั้งหมด (60 req/min per IP)
// ยกเว้น Static Files ที่ express.static จัดการเอง
app.use('/api', defaultRateLimiter);

// Phase 13.2 — Auth routes (login, refresh, logout, me, sessions)
// Auth endpoints use their own rate limiting (loginLockout/authRateLimiter)
// applied per-endpoint below.
const { loginLockoutLimiter, otpCooldownLimiter } = require('./middleware/rate-limiter');

// Login: strict rate limit + lockout on repeated failures
app.post('/api/auth/login', authRateLimiter, loginLockoutLimiter);
// Register: strict rate limit (spam / account-creation abuse)
app.post('/api/auth/register', authRateLimiter);
// Refresh: rate limit to prevent token spraying
app.post('/api/auth/refresh', authRateLimiter);
// Social login: rate limit
app.post('/api/auth/social/:provider', authRateLimiter);
// OTP endpoints (when added): otpCooldownLimiter

// Protected auth endpoints require a verified identity (JWT path verifies
// against Supabase via gateway pool).  Public endpoints (login/register/
// refresh/social) are exempt — they are pre-auth.
app.use('/api/auth/me', verifyToken(pool));
app.use('/api/auth/logout-all', verifyToken(pool));
app.use('/api/auth/sessions', verifyToken(pool));
app.use('/api/auth', authRoutes);

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

  // Triage System — victims routes (verifyToken for identity, requireAuth per-route inside)
  app.use('/api', verifyToken(pool));
  app.use('/api', victimsRoutes(pool));

  // Start victim retention cron jobs
  victimRetentionCountdownStarter.start(pool);
  victimRetentionAnonymizer.start(pool);

}

// Phase 13.3 — STRICT_AUTH_ROUTES opt-in guard (rollback unit per wave).
// Mounted unconditionally so that strict prefixes also fail closed when
// the DB pool is absent (no verifyToken ran → req.userId == null → 401).
app.use('/api', strictRouteGuard());

// Custom-auth notification and profession-change APIs.
// Supabase is the source of truth for users/applications/notifications, so
// ── Phase 13.3 P1-3: route extraction — inline handlers moved to routes/ ──
app.use('/api/notifications', verifyToken(pool), notificationsRoutes({ supabaseForSync, socketService }));
app.use('/api/profession-change', verifyToken(pool), professionChangeRoute({ supabaseForSync, socketService }));
// Sport-type proposals: the DB trigger persists notifications; the route may
// additionally broadcast those same rows through websocket-server.
app.use(
  '/api/sports/propose',
  verifyToken(pool),
  sportsRoutes({ supabaseForSync, socketService }),
);
// PDPA face blur for clients without on-device ML Kit (Flutter Web).
// Reuses services/face-blur-service.js (deface/CenterFace) — fail-closed.
app.use('/api/media', verifyToken(pool), mediaRoutes());
app.use('/api', chatApiRoutes({ pool }));
app.use('/api/emergency-health', emergencyHealthRoutes({ verifyTokenMw: verifyToken(pool) }));
app.use('/api/professions', professionsRoutes({ pool }));
app.use('/api/users', usersRoutes({ pool, verifyTokenMw: verifyToken(pool) }));
app.use('/api/applications', applicationsRoutes({ pool, verifyTokenMw: verifyToken(pool) }));
app.use('/api/locations', locationsRoutes({ pool, locationsCache, verifyTokenMw: verifyToken(pool) }));
app.use('/api', syncRoutes({ pool }));


// Store connected users
const connectedUsers = new Map();

// Health + queue-inspection routes (needs connectedUsers — defined above)
app.use(healthRoutes({ getPool: () => pool, connectedUsers }));

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

async function startFitnessBookingNotificationListener() {
  if (!pool || fitnessBookingNotificationListenerStarted) return;

  const client = await pool.connect();
  fitnessBookingNotificationListenerClient = client;

  client.on('error', (error) => {
    console.error('[FitnessBuddies] Booking notification listener error:', error.message);
    fitnessBookingNotificationListenerStarted = false;
    if (fitnessBookingNotificationListenerClient === client) {
      fitnessBookingNotificationListenerClient = null;
    }
  });

  client.on('notification', (msg) => {
    if (!msg || msg.channel !== 'fitness_booking_status_updates' || !msg.payload) return;

    let payload;
    try {
      payload = JSON.parse(msg.payload);
    } catch (error) {
      console.warn('[FitnessBuddies] Ignoring invalid booking notification payload:', error.message);
      return;
    }

    const recipientUserIds = Array.isArray(payload.recipientUserIds)
      ? payload.recipientUserIds
      : Array.isArray(payload.recipient_user_ids)
        ? payload.recipient_user_ids
        : payload.userId || payload.user_id
          ? [payload.userId || payload.user_id]
          : [];

    socketService.broadcastFitnessBookingStatus(recipientUserIds, payload);
  });

  await client.query('LISTEN fitness_booking_status_updates');
  fitnessBookingNotificationListenerStarted = true;
  console.log('✅ Fitness booking notification listener initialized');
}

// WebSocket Connection Handler
io.on('connection', (socket) => {
  console.log(`User connected: ${socket.id}`);

  // User connected event
  socket.on('user-connected', async (data) => {
    const { userId, isThaiMhungEnabled, isYieldWayEnabled, yieldWayRadius, latitude, longitude } = data;

    // Phase 13.3 — verified socket → identity comes from socket.userId ONLY;
    // a claimed payload userId that disagrees is rejected (never re-binds).
    if (isVerifiedSocket(socket)) {
      if (claimedActorMismatch(socket, userId)) {
        console.warn(`[SocketAuth] user-connected mismatch: socket.userId=${socket.userId}, data.userId=${userId}`);
        socket.emit('error', { message: 'User identity mismatch' });
        return;
      }
    } else {
      // Compat window: strict flag can force verified identity for this event
      const denial = checkEventIdentity(socket, 'user-connected');
      if (denial) {
        console.warn(`[SocketAuth] user-connected rejected: ${denial.code} (source=${socket.identitySource})`);
        socket.emit('error', { message: denial.message });
        return;
      }
      // Legacy behavior: connection-level identity wins when set; otherwise
      // the claimed userId binds (compat — flagged 'legacy', not trusted).
      if (socket.userId && socket.userId !== userId) {
        console.warn(`[SocketAuth] user-connected mismatch: socket.userId=${socket.userId}, data.userId=${userId}`);
        socket.emit('error', { message: 'User identity mismatch' });
        return;
      }
    }

    const effectiveUserId = socket.userId || userId;
    if (!effectiveUserId) {
      socket.emit('error', { message: 'userId is required' });
      return;
    }

    // ✅ [Yield Way] เก็บข้อมูลครบถ้วนสำหรับการคัดกรองใน _broadcastYieldWayAlerts
    connectedUsers.set(effectiveUserId, {
      socketId: socket.id,
      userId: effectiveUserId,
      isThaiMhungEnabled: isThaiMhungEnabled === true,
      isYieldWayEnabled: isYieldWayEnabled === true,
      yieldWayRadius: yieldWayRadius || 1000,
      userLat: latitude || null,
      userLng: longitude || null,
    });
    // Compat: legacy/anonymous sockets still bind the claimed id so the
    // connection-level identity stays consistent for event guards below.
    // Verified sockets already have socket.userId set by socket-auth.
    if (!socket.userId) socket.userId = effectiveUserId;

    console.log(`User ${effectiveUserId} connected (socket: ${socket.id}, thaiMhung: ${isThaiMhungEnabled}, yieldWay: ${isYieldWayEnabled}, source=${socket.identitySource})`);

    // Join user's personal room — bound to verified socket.userId when jwt
    socket.join(`user-${effectiveUserId}`);
    console.log(`User ${effectiveUserId} joined room user-${effectiveUserId}`);

    // Notify others that user is online
    socket.broadcast.emit('user-online', { userId: effectiveUserId });
  });

  const relayFitnessBookingStatus = (data) => {
    if (!socketRateLimit(socket, 'fitness_booking_status')) return;
    if (!data || typeof data !== 'object' || Array.isArray(data)) return;

    const actorUserId = data.actorUserId || data.actor_user_id;
    if (!socket.userId || !actorUserId || `${actorUserId}` !== `${socket.userId}`) {
      console.warn(`[SocketAuth] fitness booking actor mismatch for socket ${socket.id}`);
      return;
    }

    const status = `${data.status || ''}`.toLowerCase();
    if (!['pending', 'confirmed', 'rejected', 'cancelled'].includes(status)) return;

    const rawRecipientIds = data.recipientUserIds || data.recipient_user_ids;
    const recipientUserIds = Array.isArray(rawRecipientIds)
      ? [...new Set(rawRecipientIds.map((id) => `${id}`.trim()).filter(Boolean))]
      : data.userId || data.user_id
        ? [`${data.userId || data.user_id}`.trim()]
        : [];
    if (recipientUserIds.length === 0) return;

    socketService.broadcastFitnessBookingStatus(recipientUserIds, {
      ...data,
      status,
      recipientUserIds,
      recipient_user_ids: recipientUserIds,
    });
  };

  socket.on('fitness_booking_status', relayFitnessBookingStatus);
  socket.on('fitness-booking-status', relayFitnessBookingStatus);

  // Admin review result notification. The server resolves the applicant and
  // current application status from Supabase; client payload is not trusted
  // for recipient identity or authorization.
  socket.on('application-review-notification', async (data) => {
    console.log('[AppReview] received event from socket.userId=', socket.userId, 'role=', socket.userRole);
    if (!socket.userId || socket.userRole !== 'admin') {
      console.warn('[AppReview] rejected: not admin or no userId');
      return;
    }
    const applicationId = data?.applicationId?.toString();
    const status = data?.status?.toString();
    if (!applicationId || !['approved', 'rejected'].includes(status)) {
      console.warn('[AppReview] rejected: invalid applicationId or status', { applicationId, status });
      return;
    }
    if (!supabaseForSync) {
      console.warn('[AppReview] rejected: supabaseForSync not configured');
      return;
    }

    try {
      const { data: application, error } = await supabaseForSync
        .from('registration_applications')
        .select('id, user_id, profession_id, status, profession:professions!profession_id(name)')
        .eq('id', applicationId)
        .maybeSingle();
      if (error || !application || application.status !== status) {
        console.warn('[AppReview] rejected: application not found or status mismatch', { error: error?.message, found: !!application, dbStatus: application?.status, expectedStatus: status });
        return;
      }

      console.log('[AppReview] application found for user:', application.user_id);

      const professionName = application.profession?.name || 'อาชีพที่ร้องขอ';
      const isApproved = status === 'approved';
      const payload = {
        application_id: application.id,
        profession_id: application.profession_id,
        status,
        route: '/profile',
      };
      const title = isApproved
        ? 'คำขอเปลี่ยนอาชีพได้รับการอนุมัติ'
        : 'คำขอเปลี่ยนอาชีพถูกปฏิเสธ';
      const body = isApproved
        ? `คำขออาชีพ ${professionName} ของคุณได้รับการอนุมัติแล้ว`
        : `คำขออาชีพ ${professionName} ของคุณถูกปฏิเสธ กรุณาตรวจสอบรายละเอียด`;

      const { data: notification, error: notificationError } = await supabaseForSync
        .from('app_notifications')
        .insert({
          profession_id: application.profession_id,
          recipient_id: application.user_id,
          category: 'system',
          event_type: `profession_application.${status}`,
          title,
          body,
          payload,
        })
        .select(NOTIFICATION_COLUMNS)
        .single();
      if (notificationError) {
        console.error('[Notifications] Review notification failed:', notificationError.message);
        return;
      }

      console.log('[AppReview] notification inserted, broadcasting to user:', application.user_id);
      socketService.broadcastApplicationNotification([application.user_id], notification);
    } catch (error) {
      console.error('[Notifications] Review event failed:', error.message);
    }
  });

  // Location update event
  socket.on('location-update', async (data) => {
    if (!socketRateLimit(socket, 'location-update')) return;
    const { latitude, longitude, timestamp, accuracy, speed, heading } = data;
    const claimedUserId = data.userId;

    // Phase 13.3 — actor = socket.userId only; payload userId mismatch → denied
    const denial = checkEventIdentity(socket, 'location-update');
    if (denial) {
      socket.emit('authz.denied', { event: 'location-update', code: denial.code });
      return;
    }
    if (claimedActorMismatch(socket, claimedUserId)) {
      console.warn(`[SocketAuth] location-update mismatch: socket.userId=${socket.userId}, data.userId=${claimedUserId}`);
      socket.emit('authz.denied', { event: 'location-update', code: 'ACTOR_MISMATCH' });
      return;
    }
    const userId = socket.userId;

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
  // Phase 13.3 — user-{id} carries private notifications; under strict flags
  // only a verified socket may subscribe, and only to its own channel.
  // (Cross-user location sharing moves to a dedicated channel in step 5.)
  socket.on('subscribe-user', (data) => {
    const { userId } = data;
    const denial = checkEventIdentity(socket, 'subscribe-user');
    if (denial) {
      console.warn(`[SocketAuth] subscribe-user rejected: ${denial.code} socket=${socket.id}`);
      socket.emit('error', { message: denial.message });
      return;
    }
    // ภายใต้ strict flag: verified socket subscribe ได้เฉพาะ channel ตัวเอง
    // (user-{id} พา private notifications — cross-user subscribe = รั่ว)
    if (isStrictSocketEvent('subscribe-user') && `${socket.userId}` !== `${userId}`) {
      console.warn(`[SocketAuth] subscribe-user cross-user rejected: ${socket.userId} -> ${userId}`);
      socket.emit('error', { message: 'Cannot subscribe to another user channel' });
      return;
    }
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
  socket.on('join-room', async (data) => {
    const { roomId } = data;
    const fullRoom = `room-${roomId}`;

    // Phase 13.3 Step 6+7 — room authorization (data model:
    // services/room-authorization.js). Under strict flags, non-public
    // rooms require verified identity + membership; compat keeps join open.
    if (isStrictSocketEvent('join-room') || strictSocketAuthEnabled() || strictRoomAuthEnabled()) {
      try {
        const verdict = await authorizeRoomJoin({ pool }, socket, fullRoom);
        if (!verdict.allowed) {
          console.warn(`[RoomAuth] join-room denied: ${socket.id} -> ${fullRoom} (${verdict.reason})`);
          socket.emit('authz.denied', { event: 'join-room', room: fullRoom, reason: verdict.reason });
          return;
        }
      } catch (err) {
        console.error('[RoomAuth] authorize error:', err.message);
        socket.emit('authz.denied', { event: 'join-room', room: fullRoom, reason: 'error' });
        return;
      }
    }

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
    const { videoId, type, value, requestId } = data;
    const claimedUserId = data.userId;

    // Phase 13.3 — actor = socket.userId only (verified or compat-legacy);
    // payload userId ที่ไม่ตรง → authz.denied
    const denial = checkEventIdentity(socket, 'video-interaction');
    if (denial) {
      socket.emit('authz.denied', { event: 'video-interaction', code: denial.code });
      return;
    }
    if (claimedActorMismatch(socket, claimedUserId)) {
      console.warn(`[SocketAuth] video-interaction mismatch: socket.userId=${socket.userId}, data.userId=${claimedUserId}`);
      socket.emit('authz.denied', { event: 'video-interaction', code: 'ACTOR_MISMATCH' });
      return;
    }
    const userId = socket.userId;

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

          if (type === 'view') {
            // The database trigger updates cached_view_count after the INSERT.
            // Do not increment it here, otherwise one view is counted twice.
            const countResult = await pool.query(
              `SELECT cached_view_count FROM videos WHERE id = $1`,
              [videoId]
            );
            const cumulativeCount = Number(countResult.rows[0]?.cached_view_count || 0);
            await invalidateCachePattern('video:emergency:list:*');
            io.emit('cumulative-viewer-count', { videoId, count: cumulativeCount });
            console.log(`[CumulativeViewers] ${videoId}: ${cumulativeCount}`);
          }
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
    const { videoId, count, liked } = data;
    const claimedUserId = data.userId;
    if (!videoId) return;
    // Phase 13.3 — log actor from socket, never payload
    const actorId = socket.userId || 'anonymous';
    console.log(`[Like] Video ${videoId}: ${liked ? '+1' : '-1'} by ${actorId}, total=${count}`);
    io.to(`room-video-${videoId}`).emit('like-count-updated', { videoId, count, liked });
  });

  // ✅ [Yield Way] รับ Route Polyline ของจิตอาสา — บันทึกลง DB เพื่อใช้คัดกรองผู้รับแจ้งเตือน
  socket.on('volunteer-route', async (data) => {
    const { videoId, responseId, encodedPolyline, fromLat, fromLng, toLat, toLng } = data;
    const claimedUserId = data.userId;

    // Phase 13.3 — actor = socket.userId only; payload mismatch → denied
    const denial = checkEventIdentity(socket, 'volunteer-route');
    if (denial) {
      socket.emit('authz.denied', { event: 'volunteer-route', code: denial.code });
      return;
    }
    if (claimedActorMismatch(socket, claimedUserId)) {
      console.warn(`[SocketAuth] volunteer-route mismatch: socket.userId=${socket.userId}, data.userId=${claimedUserId}`);
      socket.emit('authz.denied', { event: 'volunteer-route', code: 'ACTOR_MISMATCH' });
      return;
    }
    const userId = socket.userId;

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

        // ✅ กระจาย route_polyline ไปยังห้องวิดีโอแบบเรียลไทม์ (ไม่มี cost)
        io.to(`room-video-${videoId}`).emit('responder-route-updated', {
          videoId,
          responseId,
          volunteerId: userId || socket.userId,
          encodedPolyline,
        });
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
    const { categoryId, videoId, type, text, isThaiMhungEnabled } = data;
    const claimedUserId = data.userId;

    // Phase 13.3 — sender = socket.userId only; payload userId ไม่เชื่อ
    const denial = checkEventIdentity(socket, 'emergency-alert');
    if (denial) {
      socket.emit('authz.denied', { event: 'emergency-alert', code: denial.code });
      return;
    }
    if (claimedActorMismatch(socket, claimedUserId)) {
      console.warn(`[SocketAuth] emergency-alert mismatch: socket.userId=${socket.userId}, data.userId=${claimedUserId}`);
      socket.emit('authz.denied', { event: 'emergency-alert', code: 'ACTOR_MISMATCH' });
      return;
    }
    const userId = socket.userId;
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
  socket.on('rescue-status-update', async (data, callback) => {
    const { videoId, volunteerId, status, victimId, responseId } = data || {};
    const ack = (payload) => {
      if (typeof callback === 'function') callback(payload);
    };
    const RESCUE_STATUSES = ['accepted', 'en_route', 'arrived', 'resolved', 'cancelled'];

    // ✅ Authorization: ต้องมี responseId อ้างอิงได้ และตัวตนต้องตรงกัน
    // Phase 13.3 — actor = socket.userId only (verified or compat-legacy)
    if (!status || !RESCUE_STATUSES.includes(status)) {
      console.warn('[Rescue] Rejected: invalid status');
      return ack({ success: false, error: 'INVALID_STATUS' });
    }
    const denial = checkEventIdentity(socket, 'rescue-status-update');
    if (denial) {
      return ack({ success: false, error: denial.code });
    }
    if (claimedActorMismatch(socket, volunteerId)) {
      console.warn('[Rescue] Rejected: volunteer identity mismatch');
      return ack({ success: false, error: 'IDENTITY_MISMATCH' });
    }
    const actorId = socket.userId;
    if (!responseId || !actorId) {
      console.warn('[Rescue] Rejected: missing responseId/actor');
      return ack({ success: false, error: 'MISSING_RESPONSE_ID' });
    }

    console.log(`[Rescue] Volunteer: ${actorId} updated status to ${status} for incident ${videoId}`);

    // 1. Persist — เฉพาะ response ที่เป็นของ volunteer คนนี้เท่านั้น
    if (pool) {
      try {
        const owner = await pool.query(
          'SELECT status FROM incident_responses WHERE id = $1 AND volunteer_id = $2',
          [responseId, actorId]
        );
        if (owner.rows.length === 0) {
          console.warn('[Rescue] Rejected: response not found or not owned by volunteer');
          return ack({ success: false, error: 'NOT_FOUND' });
        }

        // ✅ Terminal-state guard: ห้ามเปิดภารกิจที่ปิดแล้วกลับมา
        // (ยัง idempotent เมื่อยิงซ้ำด้วยสถานะ terminal เดิม)
        const currentStatus = owner.rows[0].status;
        if (
          (currentStatus === 'resolved' || currentStatus === 'cancelled') &&
          status !== 'resolved' && status !== 'cancelled'
        ) {
          console.warn('[Rescue] Rejected: mission already closed');
          return ack({ success: false, error: 'MISSION_ALREADY_CLOSED' });
        }

        // ✅ Idempotent เหมือน POST /:id/status — arrived_at/resolved_at
        // ถูกตั้งเฉพาะเมื่อยังไม่มีค่า (ยิงซ้ำไม่ทำให้ timestamp เลื่อน)
        await pool.query(
          `UPDATE incident_responses
             SET status = $1,
                 updated_at = CURRENT_TIMESTAMP,
                 arrived_at = CASE WHEN $1 = 'arrived' AND arrived_at IS NULL THEN CURRENT_TIMESTAMP ELSE arrived_at END,
                 resolved_at = CASE WHEN $1 IN ('resolved', 'cancelled') AND resolved_at IS NULL THEN CURRENT_TIMESTAMP ELSE resolved_at END
           WHERE id = $2`,
          [status, responseId]
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
        volunteerId: actorId,
        status,
        timestamp: new Date().toISOString()
      });
      console.log(`[Rescue] Notified victim ${victimId} of status: ${status}`);
    }

    // 3. If cancelled, also notify other connected volunteers so they know the spot is open
    if (status === 'cancelled') {
      io.emit('rescue-cancelled', { videoId, volunteerId: actorId });
    }

    // 4. Archive chat if resolved or cancelled to save space in main tables
    if (pool && (status === 'resolved' || status === 'cancelled')) {
      await archiveChatMessages(pool, videoId, status);
    }

    // 5. Acknowledge caller if callback provided
    ack({ success: true, status, responseId });
  });


  // ── Donation Status Notification ──
  // ส่งจาก Flutter เมื่อ approveRequest() เปลี่ยนสถานะ → ส่งต่อให้เจ้าของคำร้อง
  socket.on('donation-request-status-updated', (data) => {
    const { userId, requestId, title, status } = data;
    // Phase 13.3 — sender must be an identified socket (userId ใน payload
    // คือ recipient ไม่ใช่ actor — ไม่ต้องเทียบ mismatch)
    const denial = checkEventIdentity(socket, 'donation-request-status-updated');
    if (denial) {
      socket.emit('authz.denied', { event: 'donation-request-status-updated', code: denial.code });
      return;
    }
    console.log(`[Donation] Status updated: requestId=${requestId} status=${status} -> notify userId=${userId} (sender=${socket.userId})`);
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
    const denial = checkEventIdentity(socket, 'donation-closed');
    if (denial) {
      socket.emit('authz.denied', { event: 'donation-closed', code: denial.code });
      return;
    }
    console.log(`[Donation] Requester ${socket.userId} closed request=${requestId} for video=${videoId} reason=${reason}`);
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
    const { requestId, canContinue, note } = data;
    const claimedResponderId = data.responderId;

    // Phase 13.3 — voter = socket.userId only
    const denial = checkEventIdentity(socket, 'donate-closure-vote');
    if (denial) {
      socket.emit('donate-closure-vote-result', { success: false, error: denial.code });
      return;
    }
    if (claimedActorMismatch(socket, claimedResponderId)) {
      socket.emit('donate-closure-vote-result', { success: false, error: 'IDENTITY_MISMATCH' });
      return;
    }
    const responderId = socket.userId;
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
    const { requestId } = data;
    const claimedAdminId = data.adminUserId;

    // Phase 13.3 — admin identity = socket.userId + server-side role check.
    // role มาจาก DB ตอน handshake (ทั้ง verified และ compat-legacy) — เชื่อได้
    const denial = checkEventIdentity(socket, 'admin-release-escrow');
    if (denial || socket.userRole !== 'admin') {
      console.warn(`[Escrow] admin-release-escrow rejected: role=${socket.userRole} source=${socket.identitySource}`);
      socket.emit('admin-release-escrow-result', { success: false, error: 'FORBIDDEN' });
      return;
    }
    if (claimedActorMismatch(socket, claimedAdminId)) {
      socket.emit('admin-release-escrow-result', { success: false, error: 'IDENTITY_MISMATCH' });
      return;
    }
    const adminUserId = socket.userId;
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
    const { key, value } = data;
    const claimedUserId = data.userId;

    // Phase 13.3 — actor = socket.userId only
    const denial = checkEventIdentity(socket, 'save-ui-preference');
    if (denial) {
      socket.emit('authz.denied', { event: 'save-ui-preference', code: denial.code });
      return;
    }
    if (claimedActorMismatch(socket, claimedUserId)) {
      socket.emit('authz.denied', { event: 'save-ui-preference', code: 'ACTOR_MISMATCH' });
      return;
    }
    const userId = socket.userId;
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
  socket.on('join-emergency-chat', async (data) => {
    const { videoId, role } = data;
    const roomName = `emergency-chat-${videoId}`;

    // Phase 13.3 Step 6+7 — membership room: under strict flags require
    // identity + membership (owner/active responder/admin)
    if (isStrictSocketEvent('join-emergency-chat') || strictSocketAuthEnabled() || strictRoomAuthEnabled()) {
      try {
        const verdict = await authorizeRoomJoin({ pool }, socket, roomName);
        if (!verdict.allowed) {
          console.warn(`[RoomAuth] join-emergency-chat denied: ${socket.id} -> ${roomName} (${verdict.reason})`);
          socket.emit('authz.denied', { event: 'join-emergency-chat', room: roomName, reason: verdict.reason });
          return;
        }
      } catch (err) {
        console.error('[RoomAuth] join-emergency-chat authorize error:', err.message);
        socket.emit('authz.denied', { event: 'join-emergency-chat', room: roomName, reason: 'error' });
        return;
      }
    }

    // Phase 13.3 — presence identity = socket.userId (anonymous allowed to
    // read public chat, presence shows 'anonymous' ไม่ใช่ claimed id)
    const userId = socket.userId || 'anonymous';
    socket.join(roomName);
    console.log(`[Chat] User ${userId} (${role}) joined ${roomName}`);

    // Optionally notify others
    socket.to(roomName).emit('emergency-chat-presence', { userId, role, status: 'joined' });
  });

  socket.on('leave-emergency-chat', (data) => {
    const { videoId } = data;
    const roomName = `emergency-chat-${videoId}`;
    socket.leave(roomName);
    console.log(`[Chat] User ${socket.userId || 'anonymous'} left ${roomName}`);
  });

  socket.on('send-emergency-message', async (data) => {
    if (!socketRateLimit(socket, 'send-emergency-message')) return;
    const { videoId, role, userName, content, profileImageUrl, professionName, replyToId, replyToContent, replyToUserName } = data;
    const claimedUserId = data.userId;

    // Phase 13.3 — sender = socket.userId only (persisted as sender_id)
    const denial = checkEventIdentity(socket, 'send-emergency-message');
    if (denial) {
      socket.emit('authz.denied', { event: 'send-emergency-message', code: denial.code });
      return;
    }
    if (claimedActorMismatch(socket, claimedUserId)) {
      socket.emit('authz.denied', { event: 'send-emergency-message', code: 'ACTOR_MISMATCH' });
      return;
    }
    const userId = socket.userId;
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
      replyToId: replyToId || null,
      replyToContent: replyToContent ?? null,
      replyToUserName: replyToUserName ?? null,
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
          [messagePayload.id, roomId, userId, content, JSON.stringify({ role, userName, profileImageUrl, professionName, replyToId, replyToContent, replyToUserName })]
        );

        // Update room's last message
        await pool.query(
          "UPDATE chat_rooms SET last_message = $1, updated_at = NOW() WHERE id = $2",
          [content, roomId]
        );

        // The history endpoint is cached by video and limit. Invalidate every
        // active-history page after persistence so reopening the chat cannot
        // restore a stale list that predates the new message.
        await invalidateCachePattern(`chat:active:${videoId}:*`);
      } catch (err) {
        console.error('[Chat] Failed to persist message:', err.message);
      }
    }
  });
  // Manual Archive Trigger (optional use)
  socket.on('archive-chat', async (data) => {
    const { videoId } = data;
    // Phase 13.3 — admin-only action (role จาก handshake/DB)
    const denial = checkEventIdentity(socket, 'archive-chat');
    if (denial || socket.userRole !== 'admin') {
      socket.emit('authz.denied', { event: 'archive-chat', code: denial?.code || 'FORBIDDEN' });
      return;
    }
    if (pool && videoId) {
      console.log(`[Archive] Manual archiving requested for video ${videoId}`);
      await archiveChatMessages(pool, videoId, 'manual');
    }
  });
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
  // ตรวจ videos.status ก่อนลบ: ข้ามโฟลเดอร์ที่ยัง 'ready' หรือกำลัง transcode ('uploading','processing')
  const tempDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, 'temp/videos');
  const CLEANUP_INTERVAL_MS = 60 * 60 * 1000;
  const CLEANUP_MAX_AGE_MS = 24 * 60 * 60 * 1000;
  const CLEANUP_ACTIVE_STATUSES = ['uploading', 'processing', 'ready'];
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  setInterval(async () => {
    try {
      const entries = await fs.promises.readdir(tempDir);
      const now = Date.now();
      for (const entry of entries) {
        const fullPath = path.join(tempDir, entry);
        try {
          const stat = await fs.promises.stat(fullPath);
          if (now - stat.mtimeMs <= CLEANUP_MAX_AGE_MS) continue;

          // ถ้าเป็น UUID dir → ตรวจสถานะใน DB ก่อนลบ
          if (stat.isDirectory() && UUID_RE.test(entry) && pool) {
            try {
              const result = await pool.query(
                'SELECT status FROM videos WHERE id = $1',
                [entry]
              );
              const status = result.rows[0]?.status;
              if (status && CLEANUP_ACTIVE_STATUSES.includes(status)) {
                console.log(`[Cleanup] ⏭️  Skipped active video dir: ${entry} (status=${status})`);
                continue;
              }
            } catch (dbErr) {
              console.warn(`[Cleanup] ⚠️  DB check failed for ${entry}, skipping:`, dbErr.message);
              continue; // fail-safe: ถ้า DB ไม่ได้ ไม่ลบ
            }
          }

          if (stat.isDirectory()) {
            await fs.promises.rm(fullPath, { recursive: true, force: true });
            console.log(`[Cleanup] 🗑️  Removed old temp dir: ${entry}`);
          } else {
            await fs.promises.unlink(fullPath);
            console.log(`[Cleanup] 🗑️  Removed old temp file: ${entry}`);
          }
        } catch (err) {
          // stat ล้มเหลว → ข้าม (อาจถูกลบไปแล้ว)
        }
      }
    } catch (err) {
      console.warn(`[Cleanup] ⚠️  readdir failed:`, err.message);
    }
  }, CLEANUP_INTERVAL_MS);
  console.log(`[Cleanup] ✅ Disk cleanup cron started — interval: ${CLEANUP_INTERVAL_MS / 60000}min, max age: ${CLEANUP_MAX_AGE_MS / 3600000}h (skips videos with status: ${CLEANUP_ACTIVE_STATUSES.join(', ')})`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[Server] SIGTERM received — shutting down gracefully');
  escrowDeadlineChecker.stop();
  inventoryAlertChecker.stop();
  emergencyHealthReleaseChecker.stop();
  emergencyHealthMonitorService.stop();
  victimRetentionCountdownStarter.stop();
  victimRetentionAnonymizer.stop();
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
  victimRetentionCountdownStarter.stop();
  victimRetentionAnonymizer.stop();
  queueRegistry.shutdownAll().catch((err) => {
    console.error('[Server] Queue registry shutdown failed:', err.message);
  }).finally(() => {
    server.close(() => process.exit(0));
  });
});
