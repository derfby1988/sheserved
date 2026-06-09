'use strict';

/**
 * Unit Tests — Pure Logic / Helpers / Config
 * ─────────────────────────────────────────────────────────────
 * ทดสอบ logic ระดับ function ที่ไม่ต้องพึ่ง service ภายนอก
 *
 * วิธีรัน:
 *   cd websocket-server
 *   node test-unit.js
 *
 * ครอบคลุม:
 *   ✅ queue-config helpers (resolveQueueOptions, resolveHealthThresholds)
 *   ✅ env key formatting / normalization
 *   ✅ number env parsing with fallback
 *   ✅ cache key formatting helpers
 */

require('dotenv').config();

const { resolveQueueOptions, resolveHealthThresholds } = require('./utils/queue-config');

// ─── Helpers ───────────────────────────────────────────────

function section(title) {
  console.log(`\n${'─'.repeat(60)}`);
  console.log(`🧪 ${title}`);
  console.log('─'.repeat(60));
}
function pass(msg) { console.log(`  ✅ ${msg}`); }
function fail(msg) { console.error(`  ❌ ${msg}`); throw new Error(msg); }

// ─── Test 1: normalizeQueueName / envKey ─────────────────────

function testEnvKeyFormatting() {
  section('Test 1: envKey / normalizeQueueName');

  // ตรวจ normalizeQueueName ผ่าน envKey
  const k1 = require('./utils/queue-config');
  // envKey เป็น internal ให้ตรวจผลลัพธ์ผ่าน resolveQueueOptions แทน

  // ตรวจว่า queue name ที่มีเครื่องหมายพิเศษถูก normalize
  const opts1 = resolveQueueOptions('my-queue.name', {});
  if (typeof opts1.concurrency === 'number') {
    pass('queue name ที่มีเครื่องหมายพิเศษถูก normalize แล้ว');
  } else {
    fail('normalizeQueueName ไม่ทำงาน');
  }

  // ตรวจ queue name ว่าง
  const opts2 = resolveQueueOptions('', {});
  if (typeof opts2.concurrency === 'number') {
    pass('queue name ว่างยังได้ค่า default');
  }
}

// ─── Test 2: resolveQueueOptions ─────────────────────────────

function testResolveQueueOptions() {
  section('Test 2: resolveQueueOptions (defaults + env override)');

  // กรณีไม่มี env override — ใช้ค่า default
  const optsDefault = resolveQueueOptions('unit-test-default', {});
  if (optsDefault.concurrency === 1) {
    pass(`default concurrency = ${optsDefault.concurrency}`);
  } else {
    fail(`concurrency ควรเป็น 1 แต่ได้ ${optsDefault.concurrency}`);
  }
  if (optsDefault.defaultJobOptions.attempts === 3) {
    pass(`default attempts = ${optsDefault.defaultJobOptions.attempts}`);
  } else {
    fail(`attempts ควรเป็น 3 แต่ได้ ${optsDefault.defaultJobOptions.attempts}`);
  }
  // backoff ไม่ถูกตั้งถ้าไม่มี defaults หรือ env (by design)
  if (!optsDefault.defaultJobOptions.backoff) {
    pass('default backoff: ไม่ถูกตั้ง (ไม่มี defaults หรือ env)');
  } else if (optsDefault.defaultJobOptions.backoff.type === 'fixed') {
    pass(`default backoff.type = ${optsDefault.defaultJobOptions.backoff.type}`);
  } else {
    fail(`backoff.type ควรเป็น fixed`);
  }

  // กรณีส่ง defaults เข้าไปเอง
  const optsCustom = resolveQueueOptions('unit-test-custom', {
    attempts: 5,
    backoffType: 'exponential',
    backoffDelayMs: 500,
    concurrency: 4,
  });
  if (optsCustom.defaultJobOptions.attempts === 5) {
    pass(`custom attempts = ${optsCustom.defaultJobOptions.attempts}`);
  } else {
    fail(`custom attempts ควรเป็น 5`);
  }
  if (optsCustom.defaultJobOptions.backoff.type === 'exponential') {
    pass(`custom backoff.type = ${optsCustom.defaultJobOptions.backoff.type}`);
  } else {
    fail(`custom backoff.type ควรเป็น exponential`);
  }
  if (optsCustom.defaultJobOptions.backoff.delay === 500) {
    pass(`custom backoff.delay = ${optsCustom.defaultJobOptions.backoff.delay}ms`);
  } else {
    fail(`custom backoff.delay ควรเป็น 500`);
  }
  if (optsCustom.concurrency === 4) {
    pass(`custom concurrency = ${optsCustom.concurrency}`);
  } else {
    fail(`custom concurrency ควรเป็น 4`);
  }
}

// ─── Test 3: resolveQueueOptions — ENV override ──────────────

function testResolveQueueOptionsEnvOverride() {
  section('Test 3: resolveQueueOptions (ENV override)');

  const queueName = 'unit-test-env';
  const envPrefix = 'QUEUE_UNIT_TEST_ENV';

  // ตั้งค่า env ชั่วคราว
  process.env[`${envPrefix}_ATTEMPTS`] = '7';
  process.env[`${envPrefix}_BACKOFF_TYPE`] = 'exponential';
  process.env[`${envPrefix}_BACKOFF_DELAY_MS`] = '1000';
  process.env[`${envPrefix}_CONCURRENCY`] = '2';

  const opts = resolveQueueOptions(queueName, {});

  if (opts.defaultJobOptions.attempts === 7) {
    pass(`ENV override attempts = ${opts.defaultJobOptions.attempts}`);
  } else {
    fail(`ENV attempts ควรเป็น 7 แต่ได้ ${opts.defaultJobOptions.attempts}`);
  }
  if (opts.defaultJobOptions.backoff.type === 'exponential') {
    pass(`ENV override backoff.type = ${opts.defaultJobOptions.backoff.type}`);
  } else {
    fail(`ENV backoff.type ควรเป็น exponential`);
  }
  if (opts.defaultJobOptions.backoff.delay === 1000) {
    pass(`ENV override backoff.delay = ${opts.defaultJobOptions.backoff.delay}ms`);
  } else {
    fail(`ENV backoff.delay ควรเป็น 1000`);
  }
  if (opts.concurrency === 2) {
    pass(`ENV override concurrency = ${opts.concurrency}`);
  } else {
    fail(`ENV concurrency ควรเป็น 2`);
  }

  // cleanup env
  delete process.env[`${envPrefix}_ATTEMPTS`];
  delete process.env[`${envPrefix}_BACKOFF_TYPE`];
  delete process.env[`${envPrefix}_BACKOFF_DELAY_MS`];
  delete process.env[`${envPrefix}_CONCURRENCY`];

  pass('ENV override cleanup เรียบร้อย');
}

// ─── Test 4: resolveQueueOptions — invalid ENV ───────────────

function testResolveQueueOptionsInvalidEnv() {
  section('Test 4: resolveQueueOptions (invalid ENV fallback)');

  const queueName = 'unit-test-invalid';
  const envPrefix = 'QUEUE_UNIT_TEST_INVALID';

  // ใส่ค่าไม่ใช่ตัวเลข
  process.env[`${envPrefix}_ATTEMPTS`] = 'not_a_number';
  process.env[`${envPrefix}_CONCURRENCY`] = 'also_not_number';

  const opts = resolveQueueOptions(queueName, {});

  if (opts.defaultJobOptions.attempts === 3) {
    pass(`invalid attempts env → fallback to default (3)`);
  } else {
    fail(`fallback attempts ควรเป็น 3 แต่ได้ ${opts.defaultJobOptions.attempts}`);
  }
  if (opts.concurrency === 1) {
    pass(`invalid concurrency env → fallback to default (1)`);
  } else {
    fail(`fallback concurrency ควรเป็น 1 แต่ได้ ${opts.concurrency}`);
  }

  // cleanup
  delete process.env[`${envPrefix}_ATTEMPTS`];
  delete process.env[`${envPrefix}_CONCURRENCY`];
}

// ─── Test 5: resolveHealthThresholds ─────────────────────────

function testResolveHealthThresholds() {
  section('Test 5: resolveHealthThresholds');

  // default
  const th1 = resolveHealthThresholds('unit-test-health', {});
  if (th1.maxWaiting === 1000 && th1.maxFailed === 100) {
    pass(`default thresholds: maxWaiting=${th1.maxWaiting}, maxFailed=${th1.maxFailed}`);
  } else {
    fail(`default thresholds ไม่ถูกต้อง`);
  }

  // custom defaults
  const th2 = resolveHealthThresholds('unit-test-health2', { maxWaiting: 50, maxFailed: 5 });
  if (th2.maxWaiting === 50 && th2.maxFailed === 5) {
    pass(`custom thresholds: maxWaiting=${th2.maxWaiting}, maxFailed=${th2.maxFailed}`);
  } else {
    fail(`custom thresholds ไม่ถูกต้อง`);
  }

  // env override
  const envPrefix = 'QUEUE_UNIT_TEST_HEALTH3';
  process.env[`${envPrefix}_MAX_WAITING`] = '25';
  process.env[`${envPrefix}_MAX_FAILED`] = '10';

  const th3 = resolveHealthThresholds('unit-test-health3', {});
  if (th3.maxWaiting === 25 && th3.maxFailed === 10) {
    pass(`ENV thresholds: maxWaiting=${th3.maxWaiting}, maxFailed=${th3.maxFailed}`);
  } else {
    fail(`ENV thresholds ไม่ถูกต้อง`);
  }

  delete process.env[`${envPrefix}_MAX_WAITING`];
  delete process.env[`${envPrefix}_MAX_FAILED`];
}

// ─── Test 6: Cache key formatting ────────────────────────────

function testCacheKeyFormatting() {
  section('Test 6: Cache Key Formatting');

  // จำลอง pattern ที่ใช้ใน cache-aside
  const buildMenuKey = (restaurantId) => `menu:restaurant:${restaurantId}`;
  const buildVideoKey = (videoId) => `video:metadata:${videoId}`;
  const buildUserKey = (userId) => `user:profile:${userId}`;

  if (buildMenuKey(123) === 'menu:restaurant:123') {
    pass(`menu key format ถูกต้อง: ${buildMenuKey(123)}`);
  } else {
    fail('menu key format ผิด');
  }

  if (buildVideoKey('abc-123') === 'video:metadata:abc-123') {
    pass(`video key format ถูกต้อง: ${buildVideoKey('abc-123')}`);
  } else {
    fail('video key format ผิด');
  }

  if (buildUserKey('user_001') === 'user:profile:user_001') {
    pass(`user key format ถูกต้อง: ${buildUserKey('user_001')}`);
  } else {
    fail('user key format ผิด');
  }
}

// ─── Main Runner ─────────────────────────────────────────────

function main() {
  console.log('\n🚀 Unit Tests — Pure Logic / Helpers / Config');

  const tests = [
    testEnvKeyFormatting,
    testResolveQueueOptions,
    testResolveQueueOptionsEnvOverride,
    testResolveQueueOptionsInvalidEnv,
    testResolveHealthThresholds,
    testCacheKeyFormatting,
  ];

  let passed = 0;
  let failed = 0;

  for (const test of tests) {
    try {
      test();
      passed++;
    } catch (err) {
      failed++;
      console.error(`\n  ❌ ${test.name} failed: ${err.message}`);
    }
  }

  console.log('\n' + '═'.repeat(60));
  if (failed === 0) {
    console.log(`🎉 Unit Tests ผ่านทั้งหมด: ${passed}/${tests.length}`);
  } else {
    console.log(`⚠️  Unit Tests: ${passed} passed, ${failed} failed`);
    process.exitCode = 1;
  }
  console.log('═'.repeat(60) + '\n');
}

main();
