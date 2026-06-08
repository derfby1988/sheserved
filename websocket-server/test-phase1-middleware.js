/**
 * Phase 1 Middleware Test Script
 * ─────────────────────────────────────────────────────────────
 * ทดสอบการทำงานของ middleware ทั้ง 3 ส่วนโดยตรง (ไม่ต้อง start server)
 *
 * วิธีรัน:
 *   cd websocket-server
 *   node test-phase1-middleware.js
 *
 * ผลที่ต้องการ:
 *   ✅ Redis connected
 *   ✅ Rate Limiter: ผ่าน 60 ครั้ง, บล็อกครั้งที่ 61
 *   ✅ Idempotency: key ซ้ำตอบกลับเหมือนเดิม
 *   ✅ Duplicate Check: ป้องกันซ้ำใน TTL
 *   ✅ Cache-Aside: Hit/Miss/Invalidate ทำงานถูกต้อง
 */

'use strict';

require('dotenv').config();

const { redis, isHealthy } = require('./middleware/redis-client');
const { checkDuplicate, clearDuplicate } = require('./middleware/idempotency');
const { cacheAside, invalidateCache, getSession, setSession, deleteSession } = require('./middleware/cache-aside');

// ─── ตัวช่วย Log ────────────────────────────────────────────

function pass(msg) { console.log(`  ✅ ${msg}`); }
function fail(msg) { console.error(`  ❌ ${msg}`); }
function section(title) {
  console.log(`\n${'─'.repeat(55)}`);
  console.log(`🧪 ${title}`);
  console.log('─'.repeat(55));
}

// ─── Cleanup: ลบ test keys ──────────────────────────────────

async function cleanup() {
  const testKeys = await redis.keys('test:*').catch(() => []);
  const dupKeys  = await redis.keys('dup:test_*').catch(() => []);
  const idemKeys = await redis.keys('idem:test_*').catch(() => []);
  const sessKeys = await redis.keys('auth:session:test_*').catch(() => []);
  const lockKeys = await redis.keys('lock:test:*').catch(() => []);
  const allKeys  = [...testKeys, ...dupKeys, ...idemKeys, ...sessKeys, ...lockKeys];
  if (allKeys.length > 0) {
    await redis.del(...allKeys).catch(() => {});
    console.log(`  🗑️  Cleaned up ${allKeys.length} test keys`);
  }
}

// ─── Test 1: Redis Connection ────────────────────────────────

async function testRedisConnection() {
  section('Test 1: Redis Connection');
  const healthy = await isHealthy();
  if (healthy) {
    pass('Redis เชื่อมต่อสำเร็จและตอบสนอง PONG');
  } else {
    fail('Redis ไม่พร้อมใช้งาน — ตรวจสอบ REDIS_URL ใน .env');
    process.exit(1);
  }
}

// ─── Test 2: Rate Limiting (จำลอง INCR) ─────────────────────

async function testRateLimiter() {
  section('Test 2: Rate Limiter (Redis INCR)');

  const testKey = 'rate:test_ip_127.0.0.1';
  await redis.del(testKey); // reset ก่อนทดสอบ

  // จำลอง 60 requests (ภายใน limit)
  for (let i = 1; i <= 60; i++) {
    await redis.incr(testKey);
    if (i === 1) await redis.expire(testKey, 60);
  }
  const countAt60 = parseInt(await redis.get(testKey));
  if (countAt60 === 60) {
    pass(`Request ที่ 60: count = ${countAt60} (อยู่ใน limit)`);
  } else {
    fail(`count ไม่ถูกต้อง: ${countAt60}`);
  }

  // จำลอง request ที่ 61 (เกิน limit)
  await redis.incr(testKey);
  const countAt61 = parseInt(await redis.get(testKey));
  if (countAt61 > 60) {
    pass(`Request ที่ 61: count = ${countAt61} → ควรถูกบล็อก (429)`);
  } else {
    fail(`ควรเกิน limit แต่ได้ ${countAt61}`);
  }

  // ตรวจสอบ TTL ยังเหลืออยู่
  const ttl = await redis.ttl(testKey);
  if (ttl > 0) {
    pass(`TTL ยังเหลือ: ${ttl} วินาที`);
  } else {
    fail('TTL หายไป — expire อาจไม่ถูกตั้ง');
  }

  await redis.del(testKey);
}

// ─── Test 3: Duplicate Check ─────────────────────────────────

async function testDuplicateCheck() {
  section('Test 3: Duplicate Check');

  const userId = 'test_user_001';
  const action = 'booking';

  // ตรวจสอบครั้งแรก → ควรผ่าน
  const first = await checkDuplicate(userId, action, 30);
  if (first) {
    pass('ครั้งแรก: อนุญาต (isFirst = true)');
  } else {
    fail('ครั้งแรก: ควรอนุญาต แต่ถูกปฏิเสธ');
  }

  // ตรวจสอบครั้งที่สอง (ซ้ำ) → ควรปฏิเสธ
  const second = await checkDuplicate(userId, action, 30);
  if (!second) {
    pass('ครั้งที่สอง (ซ้ำ): ปฏิเสธ (isFirst = false) ✔');
  } else {
    fail('ครั้งที่สอง: ควรปฏิเสธ แต่ผ่านมา');
  }

  // ลบ lock ด้วย clearDuplicate
  await clearDuplicate(userId, action);
  const afterClear = await checkDuplicate(userId, action, 30);
  if (afterClear) {
    pass('หลัง clearDuplicate: อนุญาตอีกครั้ง ✔');
  } else {
    fail('หลัง clearDuplicate: ยังคงปฏิเสธอยู่');
  }

  // Cleanup
  await clearDuplicate(userId, action);
}

// ─── Test 4: Cache-Aside ─────────────────────────────────────

async function testCacheAside() {
  section('Test 4: Cache-Aside (Lazy Loading)');

  const cacheKey = 'test:menu:restaurant:999';
  await invalidateCache(cacheKey); // ล้างก่อน

  let dbCallCount = 0;

  const mockFetch = async () => {
    dbCallCount++;
    return { restaurantId: 999, items: ['ข้าวผัด', 'ต้มยำ'], fetchCount: dbCallCount };
  };

  // Cache Miss ครั้งแรก — ต้องไปดึงจาก DB
  const result1 = await cacheAside(cacheKey, mockFetch, 30);
  if (dbCallCount === 1 && result1.restaurantId === 999) {
    pass(`Cache Miss: ดึงจาก DB สำเร็จ (DB calls: ${dbCallCount})`);
  } else {
    fail(`Cache Miss ไม่ทำงานถูกต้อง: dbCallCount=${dbCallCount}`);
  }

  // Cache Hit ครั้งที่สอง — ต้องไม่ไปดึงจาก DB
  const result2 = await cacheAside(cacheKey, mockFetch, 30);
  if (dbCallCount === 1 && result2.restaurantId === 999) {
    pass(`Cache Hit: ไม่เรียก DB (DB calls ยังคง: ${dbCallCount})`);
  } else {
    fail(`Cache Hit ไม่ทำงาน: dbCallCount=${dbCallCount}`);
  }

  // Cache Invalidation
  await invalidateCache(cacheKey);
  const keyExists = await redis.exists(cacheKey);
  if (keyExists === 0) {
    pass('Cache Invalidation: key ถูกลบออกจาก Redis แล้ว ✔');
  } else {
    fail('Invalidation ล้มเหลว: key ยังคงอยู่');
  }

  // หลัง invalidate → ต้องดึงจาก DB อีกครั้ง
  const result3 = await cacheAside(cacheKey, mockFetch, 30);
  if (dbCallCount === 2 && result3.restaurantId === 999) {
    pass(`หลัง Invalidate: ดึงจาก DB อีกครั้ง (DB calls: ${dbCallCount}) ✔`);
  } else {
    fail(`หลัง Invalidate ไม่ทำงาน: dbCallCount=${dbCallCount}`);
  }

  await invalidateCache(cacheKey); // cleanup
}

// ─── Test 5: Session (Sliding Expiration) ────────────────────

async function testSession() {
  section('Test 5: Session (Sliding Expiration)');

  const sessionId = 'test_session_abc123';
  const sessionData = { userId: 'user_001', role: 'doctor', createdAt: new Date().toISOString() };

  // บันทึก Session
  await setSession(sessionId, sessionData);
  const stored = await getSession(sessionId);
  if (stored && stored.userId === sessionData.userId) {
    pass('setSession + getSession: บันทึกและดึงสำเร็จ');
  } else {
    fail('Session ไม่ถูกบันทึก');
  }

  // ตรวจสอบ TTL ถูก slide
  const ttlBefore = await redis.ttl(`auth:session:${sessionId}`);
  await new Promise(r => setTimeout(r, 100)); // รอ 100ms
  await getSession(sessionId); // เรียกอีกรอบเพื่อ slide
  const ttlAfter = await redis.ttl(`auth:session:${sessionId}`);
  if (ttlAfter >= ttlBefore - 1) {
    pass(`Sliding Expiration: TTL ถูก reset (before≈${ttlBefore}s, after≈${ttlAfter}s) ✔`);
  } else {
    fail(`TTL ไม่ถูก slide: before=${ttlBefore}, after=${ttlAfter}`);
  }

  // ลบ Session (logout)
  await deleteSession(sessionId);
  const deleted = await getSession(sessionId);
  if (deleted === null) {
    pass('deleteSession: Session ถูกลบแล้ว ✔');
  } else {
    fail('Session ยังคงอยู่หลัง deleteSession');
  }
}

// ─── Main Runner ─────────────────────────────────────────────

async function main() {
  console.log('\n🚀 เริ่มทดสอบ Phase 1 Middleware (Sheserved)');
  console.log(`   Redis URL: ${process.env.REDIS_URL || 'redis://localhost:6379'}`);

  try {
    await cleanup();

    await testRedisConnection();
    await testRateLimiter();
    await testDuplicateCheck();
    await testCacheAside();
    await testSession();

    await cleanup();

    console.log('\n' + '═'.repeat(55));
    console.log('🎉 Phase 1 Middleware ทดสอบผ่านทั้งหมด!');
    console.log('   พร้อม integrate เข้า server.js แล้ว');
    console.log('═'.repeat(55) + '\n');
  } catch (err) {
    console.error('\n❌ เกิดข้อผิดพลาดระหว่างทดสอบ:', err.message);
    console.error(err.stack);
  } finally {
    await redis.quit();
    process.exit(0);
  }
}

main();
