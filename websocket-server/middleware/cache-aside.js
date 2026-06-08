/**
 * Cache-Aside Helper (Lazy Loading Pattern)
 * ─────────────────────────────────────────────────────────────
 * ใช้รูปแบบ: ตรวจสอบ Redis ก่อน → ถ้า Miss ดึงจาก DB → เขียนลง Redis
 *
 * Features:
 *  - Cache-Aside (get/set/del)
 *  - Cache Stampede Protection (Mutex Lock ด้วย SETNX)
 *  - Batch Invalidation (ลบหลาย key ด้วย pattern)
 *
 * Phase 1 — caching_strategy.md §2.1, §2.2, §2.3, §2.4
 */

'use strict';

const { redis } = require('./redis-client');

// ──────────────────────────────────────────────────────────────
// Default TTL values (วินาที)
// ──────────────────────────────────────────────────────────────
const TTL = {
  MENU:       600,   // เมนูอาหาร: 10 นาที
  RESTAURANT: 1800,  // ข้อมูลร้าน: 30 นาที
  BOOKING:    300,   // ตารางจอง: 5 นาที
  DONATION:   120,   // ยอดรวมบริจาค: 2 นาที (อัปเดตบ่อย)
  SESSION:    7200,  // Session: 2 ชั่วโมง (Sliding Expiration)
  DEFAULT:    600,   // ค่า default: 10 นาที
};

const LOCK_TTL_SEC = 5; // Mutex lock อายุ 5 วินาที

// ──────────────────────────────────────────────────────────────
// 1. Cache-Aside: Get with DB Fallback
// ──────────────────────────────────────────────────────────────

/**
 * ดึงข้อมูลจาก Cache (Redis) หรือ DB (fallback)
 * พร้อมป้องกัน Cache Stampede ด้วย Mutex Lock
 *
 * @param {string}   key       - Redis cache key
 * @param {function} fetchFn   - async function ที่ดึงข้อมูลจาก DB
 * @param {number}   [ttl]     - TTL ในวินาที
 * @returns {Promise<any>}     - ข้อมูลที่ได้ (parsed จาก cache หรือดึงจาก DB)
 *
 * @example
 * const menu = await cacheAside(
 *   `menu:restaurant:${restaurantId}`,
 *   () => db.query('SELECT * FROM menus WHERE restaurant_id = $1', [restaurantId]),
 *   TTL.MENU
 * );
 */
async function cacheAside(key, fetchFn, ttl = TTL.DEFAULT) {
  // ─── Step 1: ตรวจสอบ Cache ──────────────────────────────────
  try {
    const cached = await redis.get(key);
    if (cached !== null) {
      return JSON.parse(cached); // ✅ Cache Hit
    }
  } catch (err) {
    console.warn(`[Cache] ⚠️  Redis get error (key: ${key}):`, err.message);
    // ถ้า Redis error → ข้ามไปดึงจาก DB โดยตรง (Fail Open)
    return fetchFn();
  }

  // ─── Step 2: Cache Miss → ใช้ Mutex Lock ป้องกัน Stampede ──
  const lockKey = `lock:${key}`;

  try {
    const acquiredLock = await redis.set(lockKey, '1', 'NX', 'EX', LOCK_TTL_SEC);

    if (acquiredLock !== null) {
      // ✅ ได้ lock → ดึงข้อมูลจาก DB และเขียนลง Cache
      try {
        const data = await fetchFn();

        if (data !== null && data !== undefined) {
          await redis.set(key, JSON.stringify(data), 'EX', ttl);
          console.log(`[Cache] 💾 Cache set: ${key} (TTL: ${ttl}s)`);
        }

        return data;
      } finally {
        // ปลดล็อกเสมอ (แม้ fetchFn throw)
        await redis.del(lockKey).catch(() => {});
      }
    } else {
      // ⏳ ไม่ได้ lock → Request อื่นกำลังดึงอยู่ → รอแล้วลองใหม่
      await new Promise((resolve) => setTimeout(resolve, 100));

      const retryCache = await redis.get(key).catch(() => null);
      if (retryCache !== null) {
        return JSON.parse(retryCache);
      }

      // ถ้ายังไม่มี cache หลังรอ → ดึงจาก DB โดยตรง
      return fetchFn();
    }
  } catch (err) {
    console.warn(`[Cache] ⚠️  Cache-Aside error (key: ${key}):`, err.message);
    return fetchFn(); // Fallback ไปยัง DB เสมอ
  }
}

// ──────────────────────────────────────────────────────────────
// 2. Cache Invalidation (ลบ Cache เมื่อข้อมูลเปลี่ยน)
// ──────────────────────────────────────────────────────────────

/**
 * ลบ Cache key เดียว (Write-Around + Invalidation pattern)
 *
 * @param {string} key - Redis key ที่ต้องการลบ
 *
 * @example
 * // หลังแก้ไขเมนูร้านอาหาร
 * await invalidateCache(`menu:restaurant:${restaurantId}`);
 */
async function invalidateCache(key) {
  try {
    const deleted = await redis.del(key);
    if (deleted > 0) {
      console.log(`[Cache] 🗑️  Invalidated: ${key}`);
    }
    return deleted;
  } catch (err) {
    console.warn(`[Cache] ⚠️  Invalidate error (key: ${key}):`, err.message);
    return 0;
  }
}

/**
 * ลบ Cache หลาย key พร้อมกัน (Batch Invalidation)
 *
 * @param {...string} keys - Redis keys ที่ต้องการลบ
 *
 * @example
 * // หลังแก้ไขร้านอาหาร → ลบทั้ง profile และ menu
 * await invalidateCacheMany(
 *   `restaurant:profile:${id}`,
 *   `menu:restaurant:${id}`
 * );
 */
async function invalidateCacheMany(...keys) {
  if (keys.length === 0) return;
  try {
    const pipeline = redis.pipeline();
    keys.forEach((key) => pipeline.del(key));
    await pipeline.exec();
    console.log(`[Cache] 🗑️  Batch invalidated: ${keys.join(', ')}`);
  } catch (err) {
    console.warn('[Cache] ⚠️  Batch invalidate error:', err.message);
  }
}

// ──────────────────────────────────────────────────────────────
// 3. Session Helper (Sliding Expiration)
// ──────────────────────────────────────────────────────────────

/**
 * ดึง Session และต่ออายุ (Sliding Expiration)
 * ทุกครั้งที่เรียก API → TTL ถูก reset ไปอีก 2 ชั่วโมง
 *
 * @param {string} sessionId
 * @returns {Promise<object|null>} session data หรือ null ถ้าหมดอายุ
 */
async function getSession(sessionId) {
  const key = `auth:session:${sessionId}`;
  try {
    const data = await redis.get(key);
    if (!data) return null;

    // ต่ออายุ TTL ทุกครั้งที่มีการใช้งาน (Sliding)
    await redis.expire(key, TTL.SESSION);
    return JSON.parse(data);
  } catch (err) {
    console.warn('[Cache] ⚠️  getSession error:', err.message);
    return null;
  }
}

/**
 * บันทึก Session ลง Redis
 *
 * @param {string} sessionId
 * @param {object} sessionData
 */
async function setSession(sessionId, sessionData) {
  const key = `auth:session:${sessionId}`;
  try {
    await redis.set(key, JSON.stringify(sessionData), 'EX', TTL.SESSION);
    console.log(`[Cache] 🔑 Session saved: ${sessionId.slice(0, 8)}…`);
  } catch (err) {
    console.warn('[Cache] ⚠️  setSession error:', err.message);
  }
}

/**
 * ลบ Session (logout / invalidate)
 *
 * @param {string} sessionId
 */
async function deleteSession(sessionId) {
  const key = `auth:session:${sessionId}`;
  try {
    await redis.del(key);
    console.log(`[Cache] 🔑 Session deleted: ${sessionId.slice(0, 8)}…`);
  } catch (err) {
    console.warn('[Cache] ⚠️  deleteSession error:', err.message);
  }
}

// ──────────────────────────────────────────────────────────────
// 4. Donation Total Cache
// ──────────────────────────────────────────────────────────────

/**
 * ดึงยอดบริจาครวม (cached 2 นาที) สำหรับแสดงบนหน้าแรก
 *
 * @param {string}   campaignId
 * @param {function} fetchFn - ดึงจาก DB
 */
async function getDonationTotal(campaignId, fetchFn) {
  return cacheAside(
    `donation:total:${campaignId}`,
    fetchFn,
    TTL.DONATION
  );
}

// ──────────────────────────────────────────────────────────────
// Export
// ──────────────────────────────────────────────────────────────

module.exports = {
  // Core
  cacheAside,
  invalidateCache,
  invalidateCacheMany,
  // Session
  getSession,
  setSession,
  deleteSession,
  // Helpers
  getDonationTotal,
  // TTL constants (ให้ import ไปตั้งค่าได้)
  TTL,
};
