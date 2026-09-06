/**
 * Rate Limiter Middleware (Redis-based)
 * ─────────────────────────────────────────────────────────────
 * ป้องกัน DDoS / Brute Force โดยใช้ Redis Counter per IP
 *
 * กลยุทธ์: Sliding Window Counter
 *   - นับจำนวน request ต่อ IP ใน window 60 วินาที
 *   - ถ้าเกิน limit → ตอบกลับ 429 Too Many Requests
 *   - ถ้า Redis ไม่พร้อม → อนุญาตผ่านทั้งหมด (Fail Open) เพื่อไม่ให้ระบบล่ม
 *
 * Phase 1 — architecture_analysis.md §1.1
 */

'use strict';

const { redis } = require('./redis-client');

/**
 * สร้าง Rate Limiter Middleware แบบ configurable
 *
 * @param {object} options
 * @param {number} [options.windowSec=60]   - ขนาด window (วินาที)
 * @param {number} [options.maxRequests=60] - จำนวน request สูงสุดใน window
 * @param {string} [options.keyPrefix='rate'] - prefix ของ Redis key
 * @param {boolean} [options.skipOnRedisError=true] - ถ้า Redis error → อนุญาตผ่าน
 * @returns {function} Express middleware
 *
 * @example
 * // ใช้ค่า default: 60 req/min
 * app.use(rateLimiter());
 *
 * // Strict: 10 req/min สำหรับ login endpoint
 * app.post('/api/login', rateLimiter({ maxRequests: 10 }), loginHandler);
 */
function rateLimiter(options = {}) {
  const {
    windowSec = 60,
    maxRequests = 60,
    keyPrefix = 'rate',
    keyResolver = null,
    skipOnRedisError = true,
  } = options;

  return async function rateLimiterMiddleware(req, res, next) {
    // ─── ระบุตัวตน: ใช้ keyResolver ถ้ามี, fallback ด้วย User ID หรือ IP ─────
    const identifier = keyResolver
      ? keyResolver(req)
      : (req.headers['x-user-id'] || req.ip || req.connection.remoteAddress || 'unknown');

    const redisKey = `${keyPrefix}:${identifier}`;

    try {
      // ─── Atomic increment + expire ──────────────────────────────
      const current = await redis.incr(redisKey);

      if (current === 1) {
        // Key ใหม่ → ตั้งเวลาหมดอายุ
        await redis.expire(redisKey, windowSec);
      }

      // ─── ใส่ header ให้ Client รู้สถานะ ────────────────────────
      const remaining = Math.max(0, maxRequests - current);
      res.setHeader('X-RateLimit-Limit', maxRequests);
      res.setHeader('X-RateLimit-Remaining', remaining);
      res.setHeader('X-RateLimit-Window', `${windowSec}s`);

      if (current > maxRequests) {
        console.warn(
          `[RateLimiter] 🚫 Blocked: ${identifier} — ${current}/${maxRequests} req ใน ${windowSec}s`
        );
        return res.status(429).json({
          error: 'Too Many Requests',
          message: `เกินจำนวน request ที่อนุญาต (${maxRequests} ครั้งใน ${windowSec} วินาที)`,
          retryAfter: windowSec,
        });
      }

      next();
    } catch (err) {
      console.warn('[RateLimiter] ⚠️  Redis error:', err.message);
      if (skipOnRedisError) {
        // Fail Open — ให้ผ่านเพื่อไม่ให้ระบบล่ม
        return next();
      }
      return res.status(503).json({ error: 'Service temporarily unavailable' });
    }
  };
}

/**
 * Quota Limiter — จำกัดตาม resource ที่มีต้นทุนสูง (upload, video, payment)
 * ใช้ atomic Lua script เพื่อนับหลายมิติพร้อมกัน (perHour, perDay, concurrent)
 *
 * @param {object} options
 * @param {function} options.keyResolver - function(req) → string key suffix
 * @param {object} options.limits - { perHour, perDay, bytesPerDay, concurrent }
 * @param {boolean} [options.skipOnRedisError=true]
 * @returns {function} Express middleware
 */
function quotaLimiter(options = {}) {
  const {
    keyResolver,
    limits = {},
    skipOnRedisError = true,
  } = options;

  // Lua script: atomic check + increment for multiple windows
  const LUA_QUOTA = `
    local key = KEYS[1]
    local hourKey = key .. ':hour:' .. tonumber(ARGV[1])
    local dayKey = key .. ':day:' .. tonumber(ARGV[2])
    local perHour = tonumber(ARGV[3])
    local perDay = tonumber(ARGV[4])
    local hourTTL = tonumber(ARGV[5])
    local dayTTL = tonumber(ARGV[6])

    local hourCount = tonumber(redis.call('GET', hourKey) or '0')
    local dayCount = tonumber(redis.call('GET', dayKey) or '0')

    if perHour and hourCount >= perHour then
      return {0, hourCount, dayCount, 'hour'}
    end
    if perDay and dayCount >= perDay then
      return {0, hourCount, dayCount, 'day'}
    end

    redis.call('INCR', hourKey)
    redis.call('EXPIRE', hourKey, hourTTL)
    redis.call('INCR', dayKey)
    redis.call('EXPIRE', dayKey, dayTTL)

    return {1, hourCount + 1, dayCount + 1, 'ok'}
  `;

  return async function quotaLimiterMiddleware(req, res, next) {
    const identifier = keyResolver ? keyResolver(req) : (req.headers['x-user-id'] || req.ip || 'unknown');
    const baseKey = `quota:${identifier}`;
    const now = Math.floor(Date.now() / 1000);
    const hourBucket = Math.floor(now / 3600);
    const dayBucket = Math.floor(now / 86400);

    try {
      const result = await redis.eval(
        LUA_QUOTA, 1, baseKey,
        hourBucket, dayBucket,
        limits.perHour || 0, limits.perDay || 0,
        3600, 86400
      );

      const [allowed, hourCount, dayCount, reason] = result;

      if (limits.perHour) res.setHeader('X-Quota-Hour-Remaining', Math.max(0, limits.perHour - hourCount));
      if (limits.perDay) res.setHeader('X-Quota-Day-Remaining', Math.max(0, limits.perDay - dayCount));

      if (allowed === 0) {
        console.warn(`[QuotaLimiter] 🚫 Blocked: ${identifier} — ${reason} limit reached (hour: ${hourCount}, day: ${dayCount})`);
        return res.status(429).json({
          error: 'Quota Exceeded',
          message: `เกินโควต้า${reason === 'hour' ? 'รายชั่วโมง' : 'รายวัน'}ที่อนุญาต`,
          retryAfter: reason === 'hour' ? 3600 : 86400,
        });
      }

      next();
    } catch (err) {
      console.warn('[QuotaLimiter] ⚠️  Redis error:', err.message);
      if (skipOnRedisError) return next();
      return res.status(503).json({ error: 'Service temporarily unavailable' });
    }
  };
}

/**
 * Cooldown Limiter — ใช้สำหรับ OTP resend, ป้องกัน flooding
 *
 * @param {object} options
 * @param {function} options.keyResolver - function(req) → string key suffix
 * @param {number} options.cooldownSec - ระยะเวลา cooldown ระหว่าง request (วินาที)
 * @param {number} [options.maxPerDay] - จำนวนสูงสุดต่อวัน
 * @param {boolean} [options.skipOnRedisError=true]
 * @returns {function} Express middleware
 */
function cooldownLimiter(options = {}) {
  const {
    keyResolver,
    cooldownSec = 60,
    maxPerDay = 10,
    skipOnRedisError = true,
  } = options;

  return async function cooldownLimiterMiddleware(req, res, next) {
    const identifier = keyResolver ? keyResolver(req) : (req.ip || 'unknown');
    const cooldownKey = `cooldown:${identifier}`;
    const dayKey = `cooldown:day:${identifier}:${Math.floor(Date.now() / 86400000)}`;

    try {
      // Check cooldown
      const ttl = await redis.pttl(cooldownKey);
      if (ttl > 0) {
        const retryAfter = Math.ceil(ttl / 1000);
        console.warn(`[CooldownLimiter] 🚫 Blocked: ${identifier} — cooldown ${retryAfter}s remaining`);
        return res.status(429).json({
          error: 'Cooldown Active',
          message: `กรุณารอ ${retryAfter} วินาทีก่อนส่งซ้ำ`,
          retryAfter,
        });
      }

      // Check daily limit
      const dayCount = await redis.incr(dayKey);
      if (dayCount === 1) {
        await redis.expire(dayKey, 86400);
      }
      if (dayCount > maxPerDay) {
        console.warn(`[CooldownLimiter] 🚫 Blocked: ${identifier} — daily limit ${dayCount}/${maxPerDay}`);
        return res.status(429).json({
          error: 'Daily Limit Exceeded',
          message: `เกินจำนวนครั้งที่อนุญาตต่อวัน (${maxPerDay} ครั้ง)`,
          retryAfter: 86400,
        });
      }

      // Set cooldown
      await redis.set(cooldownKey, '1', 'EX', cooldownSec);

      next();
    } catch (err) {
      console.warn('[CooldownLimiter] ⚠️  Redis error:', err.message);
      if (skipOnRedisError) return next();
      return res.status(503).json({ error: 'Service temporarily unavailable' });
    }
  };
}

/**
 * Lockout Limiter — ใช้สำหรับ login protection, ป้องกัน brute force
 * นับ failure ต่อ identifier เมื่อเกิน maxFailures → lockout
 *
 * @param {object} options
 * @param {function} options.keyResolver - function(req) → string key suffix
 * @param {number} [options.maxFailures=5] - จำนวน failure สูงสุดก่อน lockout
 * @param {number} [options.lockoutSec=900] - ระยะเวลา lockout (วินาที)
 * @param {boolean} [options.progressiveBackoff=true] - เพิ่ม lockout time ตามจำนวนครั้ง
 * @param {boolean} [options.skipOnRedisError=true]
 * @returns {function} Express middleware
 */
function lockoutLimiter(options = {}) {
  const {
    keyResolver,
    maxFailures = 5,
    lockoutSec = 900,
    progressiveBackoff = true,
    skipOnRedisError = true,
  } = options;

  const LUA_LOCKOUT_CHECK = `
    local lockoutKey = KEYS[1]
    local failKey = KEYS[2]
    local maxFailures = tonumber(ARGV[1])

    local lockoutTTL = tonumber(redis.call('PTTL', lockoutKey) or -2)
    if lockoutTTL > 0 then
      return {0, lockoutTTL}
    end

    local failures = tonumber(redis.call('GET', failKey) or '0')
    if failures >= maxFailures then
      return {0, 0}
    end

    return {1, failures}
  `;

  return async function lockoutLimiterMiddleware(req, res, next) {
    const identifier = keyResolver ? keyResolver(req) : (req.body.identifier || req.ip || 'unknown');
    const lockoutKey = `lockout:${identifier}`;
    const failKey = `loginfail:${identifier}`;

    try {
      const result = await redis.eval(LUA_LOCKOUT_CHECK, 2, lockoutKey, failKey, maxFailures);
      const [allowed, extra] = result;

      if (allowed === 0) {
        const ttlMs = extra;
        const retryAfter = ttlMs > 0 ? Math.ceil(ttlMs / 1000) : lockoutSec;
        console.warn(`[LockoutLimiter] 🚫 Locked: ${identifier} — retryAfter ${retryAfter}s`);
        return res.status(429).json({
          error: 'Account Locked',
          message: `บัญชีถูกล็อคชั่วคราว กรุณารอ ${retryAfter} วินาที`,
          retryAfter,
        });
      }

      // Attach helper to req for route handler to call on login failure
      req.recordLoginFailure = async function recordLoginFailure() {
        const failures = await redis.incr(failKey);
        if (failures === 1) {
          await redis.expire(failKey, lockoutSec);
        }
        if (failures >= maxFailures) {
          const lockTime = progressiveBackoff
            ? lockoutSec * Math.pow(2, failures - maxFailures)
            : lockoutSec;
          await redis.set(lockoutKey, '1', 'EX', Math.min(lockTime, 86400));
          console.warn(`[LockoutLimiter] 🔒 Locked out: ${identifier} — ${failures} failures, lock ${lockTime}s`);
        }
      };

      req.resetLoginFailures = async function resetLoginFailures() {
        await redis.del(failKey);
      };

      next();
    } catch (err) {
      console.warn('[LockoutLimiter] ⚠️  Redis error:', err.message);
      if (skipOnRedisError) return next();
      return res.status(503).json({ error: 'Service temporarily unavailable' });
    }
  };
}

/**
 * Normalize client IP — จัดการ trusted proxy chain
 */
function normalizeClientIp(req) {
  const fwd = req.headers['x-forwarded-for'];
  if (fwd) {
    const ips = fwd.split(',').map(s => s.trim());
    return ips[0] || req.ip;
  }
  return req.ip || req.connection.remoteAddress || 'unknown';
}

/**
 * Rate Limiter สำหรับ Endpoints ที่ต้องการ limit เข้มงวดกว่า
 * ใช้กับ: POST /api/bookings, POST /api/orders, POST /api/donations
 */
const strictRateLimiter = rateLimiter({ maxRequests: 10, windowSec: 60 });

/**
 * Rate Limiter สำหรับ Auth endpoints (login / register)
 * ป้องกัน Brute Force
 *
 * maxRequests defaults to 5/min per identifier (IP during pre-auth).
 * Overridable via AUTH_RATE_LIMIT_MAX so dev/test suites (which legitimately
 * issue many auth calls per minute) are not blocked; production stays at 5.
 */
const authRateLimiter = rateLimiter({
  maxRequests: parseInt(process.env.AUTH_RATE_LIMIT_MAX, 10) || 5,
  windowSec: 60,
  keyPrefix: 'rate:auth',
});

/**
 * Rate Limiter ทั่วไป (API กลาง)
 */
const defaultRateLimiter = rateLimiter();

// ─── Pre-configured limiters for Option A (Multi-Dimensional) ──────────────

// ชั้น 1: จำกัดต่อบัญชีเมื่อยืนยันตัวตนแล้ว
const userLimiter = rateLimiter({
  maxRequests: 100, windowSec: 60,
  keyPrefix: 'rate:user',
  keyResolver: (req) => req.userId || req.headers['x-user-id'] || 'anon',
});

// ชั้น 2: จำกัดต่อ IP สำหรับ public/unauthenticated traffic
const ipLimiter = rateLimiter({
  maxRequests: 300, windowSec: 60,
  keyPrefix: 'rate:ip',
  keyResolver: (req) => normalizeClientIp(req),
});

// ชั้น 3: quota ตาม resource ที่มีต้นทุนสูง — upload
const uploadQuotaLimiter = quotaLimiter({
  keyResolver: (req) => `upload:${req.userId || req.headers['x-user-id'] || normalizeClientIp(req)}`,
  limits: { perHour: 20, perDay: 100 },
});

// OTP: ใช้ phone + IP และไม่เปิดเผยว่าบัญชีมีอยู่จริงหรือไม่
const otpCooldownLimiter = cooldownLimiter({
  keyResolver: (req) => `otp:${req.body.phone || 'unknown'}:${normalizeClientIp(req)}`,
  cooldownSec: 60,
  maxPerDay: 10,
});

// Login: identifier ต้อง normalize ก่อนสร้าง key
const loginLockoutLimiter = lockoutLimiter({
  keyResolver: (req) => req.body.identifier || req.body.username || req.body.phone || normalizeClientIp(req),
  maxFailures: 5,
  lockoutSec: 900,
  progressiveBackoff: true,
});

module.exports = {
  rateLimiter,              // factory สำหรับสร้าง custom limiter
  defaultRateLimiter,       // 60 req/min — ใช้กับ middleware ทั่วไป
  strictRateLimiter,        // 10 req/min — สำหรับ write endpoints สำคัญ
  authRateLimiter,          // 5 req/min  — สำหรับ auth endpoints

  // Option A: Multi-Dimensional Limiters
  quotaLimiter,             // factory สำหรับสร้าง quota limiter
  cooldownLimiter,          // factory สำหรับสร้าง cooldown limiter
  lockoutLimiter,           // factory สำหรับสร้าง lockout limiter
  normalizeClientIp,        // helper สำหรับ normalize IP

  // Pre-configured instances
  userLimiter,              // 100 req/min per user
  ipLimiter,                // 300 req/min per IP
  uploadQuotaLimiter,       // 20/hour, 100/day per user
  otpCooldownLimiter,       // 60s cooldown, 10/day
  loginLockoutLimiter,      // 5 failures → 15min lockout (progressive)
};
