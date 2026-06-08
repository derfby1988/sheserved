/**
 * Shared Redis Client (Singleton)
 * ─────────────────────────────────────────────────────────────
 * ใช้ ioredis เชื่อมต่อ Redis instance เดียวกับที่ BullMQ ใช้
 * Export client นี้ให้ middleware ทุกตัวใช้ร่วมกัน
 * ไม่มีค่าใช้จ่ายเพิ่มเติม — ใช้ Redis ที่มีอยู่แล้วใน .env
 *
 * Phase 1 — Infrastructure Plan (architecture_analysis.md)
 */

'use strict';

const Redis = require('ioredis');

const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';

const redis = new Redis(REDIS_URL, {
  // Reconnect อัตโนมัติสูงสุด 10 ครั้ง ห่างกันทวีคูณ (1s, 2s, 4s, …)
  maxRetriesPerRequest: 3,
  retryStrategy(times) {
    if (times > 10) {
      console.error('[Redis] ❌ เกินจำนวน retry สูงสุด — หยุดพยายามเชื่อมต่อ');
      return null; // หยุด retry
    }
    const delay = Math.min(times * 1000, 8000);
    console.warn(`[Redis] ⚠️  Reconnect ครั้งที่ ${times} — รอ ${delay}ms`);
    return delay;
  },
  // ไม่ให้ throw error เมื่อ Redis ไม่พร้อม — ระบบยังทำงานต่อได้
  enableOfflineQueue: false,
  lazyConnect: false,
});

redis.on('connect', () => {
  console.log('[Redis] ✅ เชื่อมต่อสำเร็จ:', REDIS_URL);
});

redis.on('error', (err) => {
  // Log เป็น warning เท่านั้น ไม่ crash server
  console.warn('[Redis] ⚠️  Connection error:', err.message);
});

redis.on('close', () => {
  console.warn('[Redis] 🔌 การเชื่อมต่อปิดแล้ว');
});

/**
 * ตรวจสอบสถานะ Redis แบบ safe (ไม่ throw)
 * รอให้ connection พร้อมก่อนส่ง ping
 * @returns {Promise<boolean>}
 */
async function isHealthy() {
  try {
    // ถ้า status ยังไม่ ready ให้รอสูงสุด 3 วินาที
    if (redis.status !== 'ready') {
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('connect timeout')), 3000);
        redis.once('ready', () => { clearTimeout(timeout); resolve(); });
        redis.once('error', (e) => { clearTimeout(timeout); reject(e); });
      });
    }
    const pong = await redis.ping();
    return pong === 'PONG';
  } catch {
    return false;
  }
}

module.exports = { redis, isHealthy };
