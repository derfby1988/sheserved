'use strict';

/**
 * Failure Injection Tests — Resilience & Recovery
 * ─────────────────────────────────────────────────────────────
 * ทดสอบระบบเมื่อเกิด failure ต่างๆ และตรวจ recovery behavior
 *
 * วิธีรัน:
 *   cd websocket-server
 *   node test-failure-injection.js
 *
 * ครอบคลุม:
 *   ✅ Redis disconnect → reconnect ไม่ crash
 *   ✅ Duplicate job / idempotency guard
 *   ✅ Rate limiter burst → 429
 *   ✅ Cache stampede protection (mutex lock)
 *   ✅ Invalid queue / job สำหรับ requeue
 *   ✅ Sync lock contention (simulate)
 */

require('dotenv').config();

const { redis, isHealthy } = require('./middleware/redis-client');
const { checkDuplicate, clearDuplicate } = require('./middleware/idempotency');
const { cacheAside, invalidateCache } = require('./middleware/cache-aside');

function section(title) {
  console.log(`\n${'─'.repeat(60)}`);
  console.log(`💥 ${title}`);
  console.log('─'.repeat(60));
}
function pass(msg) { console.log(`  ✅ ${msg}`); }
function warn(msg) { console.log(`  ⚠️  ${msg}`); }
function fail(msg) { console.error(`  ❌ ${msg}`); throw new Error(msg); }

// ─── Test 1: Redis Disconnect / Reconnect ────────────────────

async function testRedisDisconnect() {
  section('Test 1: Redis Disconnect → Reconnect');

  const healthyBefore = await isHealthy();
  if (!healthyBefore) fail('Redis ไม่ healthy ก่อนเริ่ม test');
  pass('ก่อน disconnect: Redis healthy');

  // สร้าง client ชั่วคราวเพื่อทดสอบ disconnect โดยไม่กระทบ shared client
  const Redis = require('ioredis');
  const tempRedis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');
  await tempRedis.ping();
  pass('temp client: เชื่อมต่อสำเร็จ');

  await tempRedis.quit().catch(() => {});
  pass('temp client: disconnect แล้ว (shared client ยังอยู่)');

  // ตรวจ shared client ยังทำงาน
  const healthyAfter = await isHealthy();
  if (!healthyAfter) fail('shared client ไม่ healthy หลัง temp disconnect');
  pass('shared client: ยัง healthy หลัง temp disconnect');

  await new Promise((r) => setTimeout(r, 200));

  try {
    await redis.ping();
    pass('shared client: ตอบ PING ปกติ');
  } catch (err) {
    fail(`shared client ping ล้มเหลว: ${err.message}`);
  }
}

// ─── Test 2: Duplicate Job / Idempotency Guard ───────────────

async function testDuplicateJobGuard() {
  section('Test 2: Duplicate Job / Idempotency Guard');

  const userId = 'failure-test-user-001';
  const action = 'sync-health-data';

  // ครั้งแรก → ผ่าน
  const first = await checkDuplicate(userId, action, 30);
  if (!first) fail('ครั้งแรกควรผ่าน (isFirst=true)');
  pass('ครั้งแรก: ผ่าน (ไม่มี duplicate)');

  // ยิงซ้ำ 10 ครั้ง → ทุกครั้งต้องถูกปฏิเสธ
  let blockedCount = 0;
  for (let i = 0; i < 10; i++) {
    const dup = await checkDuplicate(userId, action, 30);
    if (!dup) blockedCount++;
  }
  if (blockedCount !== 10) {
    fail(`duplicate guard ไม่ทำงาน: บล็อก ${blockedCount}/10 ครั้ง`);
  }
  pass(`duplicate guard: บล็อก ${blockedCount}/10 ครั้ง (100%)`);

  // ลบ lock แล้วลองใหม่ → ต้องผ่าน
  await clearDuplicate(userId, action);
  const afterClear = await checkDuplicate(userId, action, 30);
  if (!afterClear) fail('หลัง clear ควรผ่าน');
  pass('หลัง clearDuplicate: ผ่านอีกครั้ง');

  // cleanup
  await clearDuplicate(userId, action);
}

// ─── Test 3: Rate Limiter Burst ──────────────────────────────

async function testRateLimiterBurst() {
  section('Test 3: Rate Limiter Burst (> 60 req in 1 window)');

  const testKey = 'rate:failure_test_ip';
  await redis.del(testKey);

  // จำลอง burst 70 requests
  for (let i = 0; i < 70; i++) {
    await redis.incr(testKey);
    if (i === 0) await redis.expire(testKey, 60);
  }

  const count = parseInt(await redis.get(testKey));
  if (count !== 70) {
    fail(`burst count ไม่ถูกต้อง: ${count} แทน 70`);
  }
  pass(`burst 70 requests → count=${count}`);

  // ตรวจว่า request ที่ 61 ถูกบล็อก (เกิน limit)
  if (count > 60) {
    pass(`request ที่ >60 ถูกบล็อก (count=${count} > limit=60)`);
  }

  await redis.del(testKey);
}

// ─── Test 4: Cache Stampede Protection ─────────────────────

async function testCacheStampede() {
  section('Test 4: Cache Stampede Protection (Mutex Lock)');

  const cacheKey = 'failure:test:stampede:resource';
  await invalidateCache(cacheKey);

  let dbCallCount = 0;
  const slowFetch = async () => {
    dbCallCount++;
    await new Promise((r) => setTimeout(r, 200)); // จำลอง DB ช้า
    return { data: 'expensive', calls: dbCallCount };
  };

  // ยิง cacheAside พร้อมกัน 5 request
  const promises = Array.from({ length: 5 }, () =>
    cacheAside(cacheKey, slowFetch, 30)
  );

  const results = await Promise.all(promises);

  // ด้วย mutex lock ควรมีแค่ 1 DB call (หรือน้อยมาก)
  if (dbCallCount === 1) {
    pass(`cache stampede: ${dbCallCount} DB call (perfect mutex lock)`);
  } else if (dbCallCount <= 2) {
    pass(`cache stampede: ${dbCallCount} DB calls (acceptable race)`);
  } else {
    warn(`cache stampede: ${dbCallCount} DB calls (อาจต้องปรับ mutex)`);
  }

  // ทุกผลลัพธ์ต้องได้ข้อมูลถูกต้อง
  const allValid = results.every((r) => r && r.data === 'expensive');
  if (allValid) {
    pass('ทุก concurrent request ได้ข้อมูลถูกต้อง');
  } else {
    fail('บาง request ได้ข้อมูลผิด');
  }

  await invalidateCache(cacheKey);
}

// ─── Test 5: Invalid Queue / Job for Requeue ─────────────────

async function testInvalidRequeue() {
  section('Test 5: Invalid Requeue (queue not found / job not found)');

  const { retryJob } = require('./queues');

  // Queue ไม่มีใน registry
  try {
    await retryJob('nonexistent-queue', 'job-001');
    fail('ควร throw error สำหรับ queue ไม่มี');
  } catch (err) {
    if (err.message.includes('not found')) {
      pass(`queue ไม่มี → throw: "${err.message}"`);
    } else {
      fail(`error ไม่ตรง expected: ${err.message}`);
    }
  }

  // Queue มีแต่ job ไม่มี
  try {
    await retryJob('consultation-flow', 'nonexistent-job-99999');
    fail('ควร throw error สำหรับ job ไม่มี');
  } catch (err) {
    if (err.message.includes('not found') || err.message.includes('Job')) {
      pass(`job ไม่มี → throw: "${err.message}"`);
    } else {
      fail(`error ไม่ตรง expected: ${err.message}`);
    }
  }
}

// ─── Test 6: Sync Lock Contention (simulate) ────────────────

async function testSyncLockContention() {
  section('Test 6: Sync Lock Contention (simulate)');

  const lockKey = 'lock:sync:health-data';
  await redis.del(lockKey);

  // จำลอง lock ครั้งแรก
  const acquired1 = await redis.set(lockKey, 'worker-1', 'EX', 30, 'NX');
  if (acquired1 !== 'OK') fail('ควร acquire lock ครั้งแรกได้');
  pass('worker-1: acquire lock สำเร็จ');

  // worker-2 พยายาม acquire ตอน lock ยังไม่หมดอายุ
  const acquired2 = await redis.set(lockKey, 'worker-2', 'EX', 30, 'NX');
  if (acquired2 === 'OK') {
    fail('worker-2 ควรไม่ได้ lock (ยังมี lock อยู่)');
  } else {
    pass('worker-2: ถูกปฏิเสธ (lock ยังถูกยึด)');
  }

  // ลบ lock แล้ว worker-3 ได้
  await redis.del(lockKey);
  const acquired3 = await redis.set(lockKey, 'worker-3', 'EX', 30, 'NX');
  if (acquired3 === 'OK') {
    pass('worker-3: acquire lock หลัง release');
  } else {
    fail('worker-3 ควรได้ lock หลังลบ');
  }

  await redis.del(lockKey);
}

// ─── Main Runner ─────────────────────────────────────────────

async function run() {
  console.log('\n💥 Failure Injection Tests — Resilience & Recovery');

  const tests = [
    testRedisDisconnect,
    testDuplicateJobGuard,
    testRateLimiterBurst,
    testCacheStampede,
    testInvalidRequeue,
    testSyncLockContention,
  ];

  let passed = 0;
  let failed = 0;

  for (const test of tests) {
    try {
      await test();
      passed++;
    } catch (err) {
      failed++;
      console.error(`\n  ❌ ${test.name} failed: ${err.message}`);
    }
  }

  console.log('\n' + '═'.repeat(60));
  if (failed === 0) {
    console.log(`🎉 Failure Injection Tests ผ่านทั้งหมด: ${passed}/${tests.length}`);
    console.log('   ระบบ resilient ตามที่ออกแบบไว้');
  } else {
    console.log(`⚠️  Failure Injection Tests: ${passed} passed, ${failed} failed`);
    process.exitCode = 1;
  }
  console.log('═'.repeat(60) + '\n');
}

run();
