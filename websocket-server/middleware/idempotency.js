/**
 * Idempotency Middleware + Duplicate Check Helper
 * ─────────────────────────────────────────────────────────────
 * ป้องกัน 2 สถานการณ์หลัก:
 *
 * 1. Idempotency Key (x-idempotency-key header)
 *    Flutter ส่ง UUID พร้อมกับ request — ถ้า key เดิมเคยประมวลผลแล้ว
 *    จะตอบกลับด้วยผลลัพธ์เดิมทันที (ไม่สร้าง record ซ้ำ)
 *    → ใช้กับ: POST /api/bookings, POST /api/orders, POST /api/donations
 *
 * 2. Duplicate Check (ป้องกันส่งซ้ำในเวลาสั้น)
 *    ป้องกัน user กดปุ่มเร็วเกินไป / network retry โดยไม่มี key
 *    → ใช้กับ endpoint ที่ยังไม่ได้ใช้ idempotency key
 *
 * Phase 1 — architecture_analysis.md §1.2 และ §1.3
 */

'use strict';

const { redis } = require('./redis-client');

// ──────────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────────
const IDEM_TTL_SEC = 86400;   // เก็บ idempotency result 24 ชั่วโมง
const DUP_TTL_SEC  = 300;     // ป้องกัน duplicate ใน 5 นาที

// ──────────────────────────────────────────────────────────────
// 1. Idempotency Key Middleware
// ──────────────────────────────────────────────────────────────

/**
 * Middleware ที่ตรวจสอบ Header `x-idempotency-key`
 *
 * วิธีใช้ใน Flutter:
 *   headers: { 'x-idempotency-key': uuid.v4() }
 *
 * Flow:
 *   → มี key + เคยประมวลผลแล้ว  → ตอบกลับผลเดิม (ไม่ผ่าน handler)
 *   → มี key + ยังไม่เคยทำ      → ผ่านไปยัง handler + บันทึกผลลัพธ์ไว้
 *   → ไม่มี key                 → ผ่านไปยัง handler ปกติ (ไม่บังคับ)
 *
 * @example
 * app.post('/api/bookings', idempotencyMiddleware, bookingHandler);
 */
async function idempotencyMiddleware(req, res, next) {
  const idempotencyKey = req.headers['x-idempotency-key'];

  // ถ้าไม่มี key → ไม่บังคับ ผ่านไปตามปกติ
  if (!idempotencyKey) {
    return next();
  }

  // Validate: key ต้องไม่ยาวเกินไป (ป้องกัน abuse)
  if (idempotencyKey.length > 128) {
    return res.status(400).json({
      error: 'Invalid idempotency key',
      message: 'x-idempotency-key ต้องมีความยาวไม่เกิน 128 ตัวอักษร',
    });
  }

  const redisKey = `idem:${idempotencyKey}`;

  try {
    // ─── ตรวจสอบว่า key นี้เคยประมวลผลแล้วหรือยัง ─────────────
    const cached = await redis.get(redisKey);

    if (cached) {
      // เคยทำแล้ว → ตอบกลับด้วยผลเดิมทันที
      const parsed = JSON.parse(cached);
      console.log(`[Idempotency] ♻️  Key ซ้ำ: ${idempotencyKey.slice(0, 16)}… → ตอบกลับผลเดิม`);
      return res
        .status(parsed.statusCode || 200)
        .setHeader('X-Idempotency-Replayed', 'true')
        .json(parsed.body);
    }

    // ─── Key ใหม่ → ผ่านไปยัง handler ────────────────────────
    // Patch res.json เพื่อดักจับ response และบันทึกลง Redis
    const originalJson = res.json.bind(res);

    res.json = async function (body) {
      try {
        const toStore = JSON.stringify({
          statusCode: res.statusCode,
          body,
          storedAt: new Date().toISOString(),
        });
        // บันทึกผลลัพธ์ไว้ใน Redis พร้อม TTL
        await redis.set(redisKey, toStore, 'EX', IDEM_TTL_SEC);
        console.log(
          `[Idempotency] 💾 บันทึก key: ${idempotencyKey.slice(0, 16)}… (TTL: ${IDEM_TTL_SEC}s)`
        );
      } catch (storeErr) {
        // Log เท่านั้น ไม่ block response
        console.warn('[Idempotency] ⚠️  บันทึก key ล้มเหลว:', storeErr.message);
      }
      return originalJson(body);
    };

    next();
  } catch (err) {
    // Redis error → ผ่านไปปกติ (Fail Open)
    console.warn('[Idempotency] ⚠️  Redis error:', err.message);
    next();
  }
}

// ──────────────────────────────────────────────────────────────
// 2. Duplicate Check Helper Function
// ──────────────────────────────────────────────────────────────

/**
 * ตรวจสอบว่า user เพิ่งทำ action นี้ไปแล้วในช่วง TTL หรือไม่
 * ใช้ SET NX (Set if Not Exists) เพื่อป้องกัน Race Condition
 *
 * @param {string} userId    - User ID
 * @param {string} action    - ประเภทการกระทำ เช่น 'booking', 'order', 'donation'
 * @param {number} [ttlSec]  - ระยะเวลาป้องกัน (วินาที) — default 5 นาที
 * @returns {Promise<boolean>} true = ครั้งแรก (อนุญาต), false = ซ้ำ (ปฏิเสธ)
 *
 * @example
 * const isFirst = await checkDuplicate(userId, 'booking');
 * if (!isFirst) return res.status(409).json({ error: 'Duplicate booking' });
 */
async function checkDuplicate(userId, action, ttlSec = DUP_TTL_SEC) {
  const key = `dup:${userId}:${action}`;
  try {
    // NX = set only if key Not eXists
    const result = await redis.set(key, '1', 'NX', 'EX', ttlSec);
    return result !== null; // null = key มีอยู่แล้ว (ซ้ำ)
  } catch (err) {
    console.warn('[DuplicateCheck] ⚠️  Redis error:', err.message);
    return true; // Fail Open — อนุญาตผ่านเมื่อ Redis ไม่พร้อม
  }
}

/**
 * ลบ duplicate lock ก่อนครบ TTL
 * ใช้เมื่อ: process ล้มเหลว และต้องการให้ user ลองใหม่ได้ทันที
 *
 * @param {string} userId
 * @param {string} action
 */
async function clearDuplicate(userId, action) {
  const key = `dup:${userId}:${action}`;
  try {
    await redis.del(key);
    console.log(`[DuplicateCheck] 🗑️  ลบ lock: ${key}`);
  } catch (err) {
    console.warn('[DuplicateCheck] ⚠️  ลบ lock ล้มเหลว:', err.message);
  }
}

/**
 * Middleware สำเร็จรูปสำหรับ Duplicate Check (ใช้ body.userId และ route path)
 * ใช้เมื่อต้องการ block แบบ middleware โดยไม่เขียนโค้ดซ้ำ
 *
 * @param {string} action - ชื่อ action เช่น 'booking', 'order'
 * @param {number} [ttlSec] - ระยะเวลาป้องกัน
 * @returns {function} Express middleware
 *
 * @example
 * app.post('/api/bookings', duplicateCheckMiddleware('booking'), handler);
 */
function duplicateCheckMiddleware(action, ttlSec = DUP_TTL_SEC) {
  return async function (req, res, next) {
    const userId =
      req.headers['x-user-id'] ||
      req.body?.userId ||
      req.body?.user_id;

    if (!userId) {
      // ถ้าไม่มี userId ไม่สามารถ check ได้ → ผ่านไป
      return next();
    }

    try {
      const isFirst = await checkDuplicate(userId, action, ttlSec);

      if (!isFirst) {
        console.warn(
          `[DuplicateCheck] 🚫 ซ้ำ: user=${userId} action=${action}`
        );
        return res.status(409).json({
          error: 'Duplicate Request',
          message: `คุณได้ทำรายการ "${action}" ไปแล้วเมื่อไม่นานนี้ กรุณารอสักครู่`,
          retryAfterSec: ttlSec,
        });
      }

      // บันทึก clear function ไว้ใน res เผื่อ handler ต้องการ rollback
      res.clearDuplicateLock = () => clearDuplicate(userId, action);
      next();
    } catch (err) {
      console.warn('[DuplicateCheck] ⚠️  Redis error:', err.message);
      next(); // Fail Open
    }
  };
}

module.exports = {
  idempotencyMiddleware,    // ใช้กับ endpoint ที่ Flutter ส่ง x-idempotency-key
  checkDuplicate,           // helper function ใช้ภายใน handler
  clearDuplicate,           // ใช้เมื่อต้องการ rollback lock
  duplicateCheckMiddleware, // middleware สำเร็จรูปสำหรับ route
};
