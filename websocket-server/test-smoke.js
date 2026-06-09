'use strict';

/**
 * Smoke / E2E Tests — Post-Deploy Verification
 * ─────────────────────────────────────────────────────────────
 * ทดสอบ flow สำคัญที่สุดหลัง deploy บน server จริง
 * รันเร็ว (< 10 วินาที) และไม่พังเมื่อ dependency บางตัวไม่พร้อม
 *
 * วิธีรัน:
 *   cd websocket-server
 *   node test-smoke.js
 *
 * ต้องการ:
 *   - Server รันอยู่ (localhost:3000 หรือผ่าน Caddy :8080)
 *   - Redis, PostgreSQL พร้อม
 */

require('dotenv').config();

const http = require('http');

const API_HOST = process.env.TEST_API_HOST || 'localhost';
const API_PORT = process.env.TEST_API_PORT || 3000;
const BASE_URL = `http://${API_HOST}:${API_PORT}`;

function section(title) {
  console.log(`\n${'─'.repeat(60)}`);
  console.log(`🔥 ${title}`);
  console.log('─'.repeat(60));
}
function pass(msg) { console.log(`  ✅ ${msg}`); }
function warn(msg) { console.log(`  ⚠️  ${msg}`); }
function fail(msg) { console.error(`  ❌ ${msg}`); throw new Error(msg); }

function request(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: API_HOST,
      port: API_PORT,
      path,
      method,
      headers: { 'Content-Type': 'application/json', ...headers },
      timeout: 5000,
    };
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch { resolve({ status: res.statusCode, body: data }); }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// ─── Checklist 1: Server Reachable ───────────────────────────

async function checkServerReachable() {
  section('Check 1: Server Reachable');
  const res = await request('GET', '/health');
  if (res.status !== 200) fail(`server ไม่ตอบ 200 ได้ status ${res.status}`);
  pass(`server ตอบ ${res.status} ภายใน 5 วินาที`);
}

// ─── Checklist 2: Database Connected ───────────────────────

async function checkDatabase() {
  section('Check 2: Database Connection');
  const res = await request('GET', '/health');
  if (res.body.database !== 'connected') {
    fail(`database=${res.body.database} (ต้องเป็น 'connected')`);
  }
  pass('database=connected');
}

// ─── Checklist 3: Redis Connected ────────────────────────────

async function checkRedis() {
  section('Check 3: Redis Connection');
  const res = await request('GET', '/health');
  if (res.body.redis !== 'connected') {
    fail(`redis=${res.body.redis} (ต้องเป็น 'connected')`);
  }
  pass('redis=connected');
}

// ─── Checklist 4: Phase 1 Middleware Active ──────────────────

async function checkMiddleware() {
  section('Check 4: Phase 1 Middleware');
  const res = await request('GET', '/health');
  const mw = res.body.middleware;
  if (!mw) { fail('ไม่มี middleware status ใน /health'); }

  const required = ['rateLimiter', 'idempotency', 'cacheAside'];
  for (const key of required) {
    if (mw[key] === 'active') {
      pass(`${key}=active`);
    } else {
      fail(`${key}=${mw[key]} (ต้องเป็น 'active')`);
    }
  }
}

// ─── Checklist 5: Queue Health ───────────────────────────────

async function checkQueueHealth() {
  section('Check 5: Queue Health (/health/queues)');
  const res = await request('GET', '/health/queues');
  if (res.status !== 200) fail(`queue health ตอบ ${res.status}`);

  const queueNames = Object.keys(res.body.queues || {});
  if (queueNames.length === 0) fail('ไม่พบ queue ใดๆ');

  pass(`ตรวจพบ ${queueNames.length} queue`);
  pass(`healthy=${res.body.healthy}`);
  pass(`timestamp=${res.body.timestamp}`);

  for (const [name, q] of Object.entries(res.body.queues)) {
    if (q.failed > 10) {
      warn(`${name}: failed=${q.failed} (เกิน threshold ปกติ)`);
    }
  }
}

// ─── Checklist 6: Key API Endpoints ────────────────────────

async function checkApiEndpoints() {
  section('Check 6: Key API Endpoints');

  const endpoints = [
    { method: 'GET', path: '/api/videos/emergency/list', minStatus: 200, maxStatus: 200 },
    { method: 'GET', path: '/api/professions', minStatus: 200, maxStatus: 503 },
    { method: 'GET', path: '/api/users/test-user-001', minStatus: 200, maxStatus: 404 },
  ];

  for (const ep of endpoints) {
    try {
      const res = await request(ep.method, ep.path);
      if (res.status >= ep.minStatus && res.status <= ep.maxStatus) {
        pass(`${ep.method} ${ep.path} → ${res.status}`);
      } else {
        warn(`${ep.method} ${ep.path} → ${res.status} (นอกช่วง ${ep.minStatus}-${ep.maxStatus})`);
      }
    } catch (err) {
      warn(`${ep.method} ${ep.path} → ${err.message}`);
    }
  }
}

// ─── Checklist 7: Caddy Proxy (ถ้ามี) ──────────────────────

async function checkCaddyProxy() {
  section('Check 7: Caddy Reverse Proxy (ถ้ามี)');

  const caddyPort = process.env.CADDY_PORT || 8080;
  if (API_PORT === caddyPort) {
    pass(`ตรวจสอบผ่าน Caddy port ${caddyPort}`);
    return;
  }

  // ลองตรวจ Caddy แยก
  try {
    const res = await new Promise((resolve, reject) => {
      const req = http.request({ hostname: API_HOST, port: caddyPort, path: '/health', method: 'GET', timeout: 3000 },
        (res) => { let d = ''; res.on('data', c => d += c); res.on('end', () => resolve({ status: res.statusCode, body: d })); }
      );
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
      req.end();
    });
    if (res.status === 200) {
      pass(`Caddy proxy ที่ port ${caddyPort} ตอบกลับปกติ`);
    } else {
      warn(`Caddy proxy ตอบ ${res.status} (อาจไม่ได้รัน)`);
    }
  } catch {
    warn(`Caddy proxy ที่ port ${caddyPort} ไม่ตอบ (อาจไม่ได้รัน)`);
  }
}

// ─── Main Runner ─────────────────────────────────────────────

async function run() {
  console.log('\n🔥 Smoke / E2E Tests — Post-Deploy Verification');
  console.log(`   Target: ${BASE_URL}`);

  const checks = [
    checkServerReachable,
    checkDatabase,
    checkRedis,
    checkMiddleware,
    checkQueueHealth,
    checkApiEndpoints,
    checkCaddyProxy,
  ];

  let passed = 0;
  let failed = 0;

  for (const check of checks) {
    try {
      await check();
      passed++;
    } catch (err) {
      failed++;
      console.error(`\n  ❌ ${check.name} failed: ${err.message}`);
    }
  }

  console.log('\n' + '═'.repeat(60));
  if (failed === 0) {
    console.log(`🎉 Smoke Check ผ่านทั้งหมด: ${passed}/${checks.length}`);
    console.log('   ระบบพร้อมใช้งาน');
  } else {
    console.log(`⚠️  Smoke Check: ${passed} passed, ${failed} failed`);
    console.log('   ตรวจสอบ log ด้านบนก่อนเปิดใช้งาน');
    process.exitCode = 1;
  }
  console.log('═'.repeat(60) + '\n');
}

run();
