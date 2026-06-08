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
    skipOnRedisError = true,
  } = options;

  return async function rateLimiterMiddleware(req, res, next) {
    // ─── ระบุตัวตน: ใช้ User ID ถ้า authed, fallback ด้วย IP ─────
    const identifier =
      req.headers['x-user-id'] ||   // Flutter ส่ง userId ใน header
      req.ip ||
      req.connection.remoteAddress ||
      'unknown';

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
 * Rate Limiter สำหรับ Endpoints ที่ต้องการ limit เข้มงวดกว่า
 * ใช้กับ: POST /api/bookings, POST /api/orders, POST /api/donations
 */
const strictRateLimiter = rateLimiter({ maxRequests: 10, windowSec: 60 });

/**
 * Rate Limiter สำหรับ Auth endpoints (login / register)
 * ป้องกัน Brute Force
 */
const authRateLimiter = rateLimiter({ maxRequests: 5, windowSec: 60, keyPrefix: 'rate:auth' });

/**
 * Rate Limiter ทั่วไป (API กลาง)
 */
const defaultRateLimiter = rateLimiter();

module.exports = {
  rateLimiter,          // factory สำหรับสร้าง custom limiter
  defaultRateLimiter,   // 60 req/min — ใช้กับ middleware ทั่วไป
  strictRateLimiter,    // 10 req/min — สำหรับ write endpoints สำคัญ
  authRateLimiter,      // 5 req/min  — สำหรับ auth endpoints
};
