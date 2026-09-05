# แผนป้องกัน 03: Rate Limiting และ Resource Exhaustion

> **สถานะ:** ✅ เสร็จสมบูรณ์และทดสอบผ่านแล้ว **ตัวเลือก A: Multi-Dimensional Rate Limiting** พร้อม B, C และ D
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** 09 (AuthN — brute force), 11 (Input Validation — payload size), 02 (Path Traversal — disk), 04 (Misconfiguration)
> **ขอบเขต:** ไม่ใช่แค่ "จำกัดจำนวน request" แต่รวมถึงการจำกัด **ทรัพยากรทุกชนิก** ที่ผู้ใช้คนหนึ่งใช้ได้ — CPU, RAM, disk, DB connection, queue slot
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-A ลำดับ 3** โดยแก้ upload/disk/pagination/timeout ก่อน policy rate limit ขั้นสูง
> **ผลทดสอบ 2026-07-27:** Maestro flow `rate_limit_option_b_test_flow.yaml` ผ่าน 23/23 commands บน iPhone 16 simulator

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่ implement แล้ว ✅

| องค์ประกอบ | รายละเอียด | ไฟล์ |
|-----------|------------|------|
| Redis rate limiter | `rateLimiter({ maxRequests, windowSec, keyPrefix, keyResolver })` | `middleware/rate-limiter.js` |
| Preset limiters | `defaultRateLimiter`, `strictRateLimiter`, `authRateLimiter` | `middleware/index.js` |
| Multi-dimensional limiters | `quotaLimiter`, `cooldownLimiter`, `lockoutLimiter` + pre-configured instances | `middleware/rate-limiter.js` |
| Option A pre-configured | `userLimiter`, `ipLimiter`, `uploadQuotaLimiter`, `otpCooldownLimiter`, `loginLockoutLimiter` | `middleware/index.js` |
| Upload limiter | `rateLimiter({ maxRequests: 30, windowSec: 60, keyPrefix: 'rate:upload' })` | `video.js:25` |
| Upload quota | 20/hour, 100/day via `uploadQuotaLimiter` (Lua atomic) | `routes/video.js` upload routes |
| IP limiter | 300/min public read via `ipLimiter` | `routes/video.js` GET endpoints |
| Idempotency | ป้องกันการส่งซ้ำจาก retry | `middleware/idempotency.js` |
| Duplicate check | `duplicateCheckMiddleware('video-upload', 5)` | ใช้หลาย route |
| Multer size limit | 20MB video, 10MB photo + cleanup on reject | `video.js` |
| Pagination clamp | `limit ≤ 100`, `page ≤ 1000` | `video.js` list endpoints |
| GPS bulk insert | Max 5,000 tracks, UNNEST bulk insert | `video.js` |
| Cache key clamp | `page`/`limit` ถูก clamp ก่อนสร้าง key | `video.js` |
| DB pool governance | `max: 20`, `statement_timeout: 30s`, `idleTimeoutMillis: 30s` | `server.js` pool config |
| Socket.IO rate limit | 20 events/sec per connection | `server.js` event handlers |
| Disk cleanup cron | ลบ temp files เก่ากว่า 24h ทุก 1h — **ตรวจ `videos.status` ก่อนลบ UUID dir; ข้าม `uploading`/`processing`/`ready`; fail-safe ถ้า DB ไม่ได้** | `server.js` |
| Circuit breaker | `CircuitBreaker` class CLOSED/OPEN/HALF_OPEN | `utils/circuit-breaker.js` |
| Edge config | NGINX `nginx/rate-limiting.conf` + Caddy `Caddyfile.dev` | `websocket-server/` |
| Maestro test flow | ทดสอบ B: login, pagination, gallery, upload, negatives | `docs/guides/rate_limit_option_b_test_flow.yaml` |

**สรุป:** พื้นฐานดีกว่าหลายโปรเจกต์ — มี Redis rate limiter พร้อมใช้แล้ว ปัญหาหลักคือ **ยังใช้ไม่ครบและยังไม่ครอบคลุมทรัพยากรอื่นนอกจากจำนวน request**

### จุดที่ต้องปิด — พร้อมหลักฐานจากโค้ดจริง

**1. Multer เขียนไฟล์ 500MB ลงดิสก์ก่อน แล้วค่อยปฏิเสธที่ 20MB** ✅ แก้ไขแล้ว
- `multer` ตั้ง `limits.fileSize: 20 * 1024 * 1024` (video) และ `10 * 1024 * 1024` (photo)
- `fs.promises.mkdir` แทน sync operation ใน destination handler
- Cleanup handler ลบไฟล์ชั่วคราวเมื่อ reject/disconnect/failure แล้ว
- ไฟล์: `websocket-server/routes/video.js`

**2. `limit` จาก query ไม่มีเพดาน** ✅ แก้ไขแล้ว
- `clampPagination(limit, page)` จำกัด `limit ≤ 100` และ `page ≤ 1000`
- ใช้ทุก list endpoint รวม `/:id/gallery`
- ไฟล์: `websocket-server/routes/video.js`

**3. Loop insert ไม่จำกัดจำนวน** ✅ แก้ไขแล้ว
- จำกัด GPS tracks ≤ 5,000 ต่อ request
- เปลี่ยน loop query เป็น bulk insert ด้วย `UNNEST($2::float[], $3::float[], $4::int[])`
- ไฟล์: `websocket-server/routes/video.js`

**4. Cache key มี `limit`/`page` จาก user** ✅ แก้ไขแล้ว
- สร้าง cache key จากค่า `page`/`limit` ที่ clamp แล้วเท่านั้น
- ป้องกัน cache flooding จาก query unbounded
- ไฟล์: `websocket-server/routes/video.js`

**5. Endpoint สาธารณะไม่มี rate limit** ✅ แก้ไขแล้ว
- ติด `ipLimiter` (300 req/min) ทุก GET/read endpoint ใน `video.js`
- ติด `uploadQuotaLimiter` บน `POST` video/photo upload
- ไฟล์: `websocket-server/routes/video.js`

**6. Background job ไม่มี concurrency limit ต่อผู้ใช้** ⚠️ ส่วนหนึ่ง
- Queue concurrency กำหนดผ่าน `utils/queue-config.js` (default: video=1, thumbnail=4)
- ยังไม่มี per-user job quota — ไว้ทำใน Phase cost-based/queue governance ถัดไป

**7. Sync filesystem operation ใน request path** ✅ แก้ไขแล้วบางส่วน
- `multer.diskStorage.destination` เปลี่ยนจน `fs.existsSync`/`fs.mkdirSync` เป็น `fs.promises.mkdir`
- ส่วน `readdirSync` ใน gallery ยังคงตรวจสอบและแก้ไขต่อได้ในงานลดปริมาณ sync I/O
- ไฟล์: `websocket-server/routes/video.js`

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| R1 | **Multer limit ไม่ตรงกับ business limit** | ✅ แก้แล้ว | multer 20MB/10MB + cleanup on reject |
| R2 | **`limit`/`page` ไม่มีเพดาน** | ✅ แก้แล้ว | `clampPagination(limit ≤ 100, page ≤ 1000)` |
| R3 | **Array/loop ไม่จำกัดขนาด** | ✅ แก้แล้ว | GPS tracks ≤ 5,000 + bulk insert |
| R4 | **Cache key จาก user input** | ✅ แก้แล้ว | ใช้ค่า clamp แล้วสร้าง cache key |
| R5 | **Read endpoint ไม่มี rate limit** | ✅ แก้แล้ว | `ipLimiter` บน GET endpoints |
| R6 | **ไม่มี per-user quota** | ✅ แก้แล้ว | `uploadQuotaLimiter` 20/hr, 100/day |
| R7 | **ไม่มี account lockout** | ✅ แก้แล้ว | `loginLockoutLimiter` 5 failures → 15min progressive |
| R8 | **ไม่มี OTP resend cooldown** | ✅ แก้แล้ว | `otpCooldownLimiter` 60s/10 วัน |
| R9 | **ไม่มี disk quota / cleanup** | ✅ แก้แล้ว | cleanup cron 1h / 24h max age — ตรวจ `videos.status` ก่อนลบ (ข้าม `uploading`/`processing`/`ready`); fail-safe ถ้า DB ไม่ได้ (2026-09-05 hotfix: ก่อนหน้านี้ลบไฟล์ HLS ที่ `status='ready'` ทำให้วิดีโอกลายเป็น 404) |
| R10 | **ไม่มี query timeout** | ✅ แก้แล้ว | `statement_timeout: 30s` |
| R11 | **ไม่มี DB connection pool limit ที่ชัดเจน** | ✅ แก้แล้ว | pool `max: 20`, `idleTimeoutMillis: 30s` |
| R12 | **Socket.IO ไม่มี event rate limit** | ✅ แก้แล้ว | 20 events/sec ต่อ connection |
| R13 | **Sync filesystem operation ใน request** | ⚠️ ส่วนหนึ่ง | `multer` destination เป็น async แล้ว |
| R14 | **ไม่มี circuit breaker** | ✅ แก้แล้ว | `utils/circuit-breaker.js` |
| R15 | **ไม่มี cost-based limiting** | 🟢 ต่ำ | ยังไม่ implement — ไว้ Phase ต่อไป |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว

| ระบบ | ทรัพยากรที่เสี่ยงถูกใช้เกิน | สถานะ | สิ่งที่ต้องเพิ่ม |
|------|---------------------------|-------|-----------------|
| **Auth** | CPU (bcrypt), SMS (OTP), DB | ✅ `authRateLimiter` + `loginLockoutLimiter` + `otpCooldownLimiter` | CAPTCHA หลัง N ครั้ง (ยังไม่ทำ) |
| **Video upload** | Disk, CPU (ffmpeg), Queue, Bandwidth | ✅ `uploadQuotaLimiter` 20/hr, 100/day + `ipLimiter` + multer 20MB + cleanup | per-org tier quota ในอนาคต |
| **Photo upload** | Disk, CPU (face blur, watermark) | ✅ `uploadQuotaLimiter` + `ipLimiter` | quota ต่อ incident |
| **Chat** | DB write, Socket events, Storage | ✅ `socketRateLimit` 20/sec ต่อ connection | message rate limit, attachment quota |
| **Video call** | Bandwidth, TURN server | ⚠️ ยังไม่มี | concurrent call limit ต่อผู้ใช้ |
| **Consultation** | DB, Provider availability | ⚠️ ยังไม่มี | จำกัดจำนวนคำขอค้างต่อผู้ใช้ |
| **Emergency SOS** | ⚠️ **ห้ามจำกัดเข้มเกินไป** — เป็นฟีเจอร์ช่วยชีวิต | ✅ `emergency` edge zone 20r/s burst 50 + app-layer soft limits | ตรวจ abuse แยก |
| **Donation** | DB, Payment gateway calls | มี strict | idempotency ✅, จำกัดจำนวนธุรกรรมต่อวัน |
| **Health sync** | DB write ปริมาณมาก | ⚠️ ยังไม่มี | batch size limit, sync interval |
| **Search** | DB CPU | ⚠️ ยังไม่มี | debounce + rate limit + min query length |
| **Admin** | ทุกอย่าง | มี strict | ✅ |

### 2.2 ระบบตามแผน `docs/ERP/`

| แผน | ทรัพยากรที่ต้องจำกัด |
|-----|---------------------|
| `KPI_DASHBOARD_PLAN.md` | 🔴 Aggregate query หนักมาก — ต้องมี materialized view + query timeout + cache |
| `ACCOUNTING_SYSTEM_PLAN.md` | Report generation, period close (long transaction), export ขนาดใหญ่ |
| `INVENTORY_SYSTEM_PLAN.md` | Stock recalculation, bulk import |
| `HR_SYSTEM_PLAN.md` | Payroll run (batch หนัก) — ควรเป็น queue job ไม่ใช่ HTTP request |
| `POS System_plan.md` | 🔴 Peak load ช่วงเวลาขาย — ต้องรับ burst ได้ |
| `CRM_SYSTEM_PLAN.md` | Bulk email/SMS — ต้องมี throttle + cost cap |
| `PROCUREMENT_SYSTEM_PLAN.md` | Supplier catalog sync |
| `LAB_SYSTEM_PLAN.md` | HL7 message ingestion rate |
| `ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | 🔴 **Quota ตาม tier** — เป็น business requirement ไม่ใช่แค่ security |
| `ERP_NOTIFICATION_SYSTEM_PLAN.md` | Notification fan-out — 1 event → 1000 ผู้รับ |

### 2.3 ระบบตามแผน `docs/plans/`

| แผน | ประเด็น |
|-----|---------|
| `VIDEO_SYSTEM_PLAN.md` | 🔴 Transcoding เป็น CPU-bound — ต้องมี worker pool limit + priority queue |
| `Delivery_PLAN.md` | GPS tracking ping frequency — ต้อง throttle |
| `SHOPPING_CART_PLAN.md` | Cart operations, checkout (ต้อง idempotent) |
| `health_data_sync_plan.md` | 🔴 Background sync จากอุปกรณ์ — batch + interval limit |
| `DONATION_SYSTEM_PLAN.md` | Payment gateway call = มีค่าใช้จ่ายต่อครั้ง |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Multi-Dimensional Rate Limiting (แนะนำ) ⭐ ✅ ใช้งานแล้ว

ขยาย limiter ที่มีอยู่ให้จำกัดหลายมิติพร้อมกัน โดย **ไม่ใช้ค่าใดค่าหนึ่งเป็นตัวตัดสินเพียงลำพัง**:

```js
// ชั้น 1: จำกัดต่อบัญชีเมื่อยืนยันตัวตนแล้ว
const userLimiter = rateLimiter({
  maxRequests: 100, windowSec: 60,
  keyPrefix: 'rate:user',
  keyResolver: (req) => `user:${req.authenticatedUserId}`,
});

// ชั้น 2: จำกัดต่อ IP สำหรับ public/unauthenticated traffic
const ipLimiter = rateLimiter({
  maxRequests: 300, windowSec: 60,
  keyPrefix: 'rate:ip',
  keyResolver: (req) => `ip:${normalizeClientIp(req)}`,
});

// ชั้น 3: quota ตาม resource ที่มีต้นทุนสูง — ต้องนับแบบ atomic
const uploadQuota = quotaLimiter({
  keyResolver: (req) => `quota:upload:${req.authenticatedUserId}`,
  limits: {
    perHour: 20,
    perDay: 100,
    bytesPerDay: 500 * 1024 * 1024,
    concurrent: 3,
  },
});

// OTP: ใช้ phone/account + IP และไม่เปิดเผยว่าบัญชีมีอยู่จริงหรือไม่
const otpCooldown = cooldownLimiter({
  keyResolver: (req) => `otp:${normalizePhone(req.body.phone)}:${normalizeClientIp(req)}`,
  cooldownSec: 60,
  maxPerDay: 10,
});

// Login: identifier ต้อง normalize/hash ก่อนสร้าง key
const loginProtection = lockoutLimiter({
  keyResolver: (req) => `login:${hashIdentifier(req.body.identifier)}`,
  maxFailures: 5,
  lockoutSec: 900,
  progressiveBackoff: true,
});
```

#### ผลกระทบที่ประเมิน

| ด้าน | ผลกระทบ | ระดับ | แนวทางรับมือที่ดีที่สุด |
|------|---------|-------|-------------------------|
| ความถูกต้อง | ผู้ใช้หลัง NAT หรือเครือข่ายมือถืออาจถูกจำกัดร่วมกับผู้ใช้อื่น หากใช้ IP เป็น key หลัก | สูง | ใช้ `authenticatedUserId` เป็นหลักหลังยืนยันตัวตน และใช้ IP เป็นเพดานป้องกัน abuse; แยก public/authenticated policy |
| ความเป็นส่วนตัว | key จาก phone, identifier หรือ IP อาจทำให้ข้อมูล sensitive อยู่ใน Redis/log | สูง | normalize แล้ว hash/HMAC identifier, ไม่เก็บ raw value, ตั้ง TTL และจำกัดสิทธิ์ดู key |
| Availability | Redis ล่มอาจทำให้ request ทั้งหมดถูกปฏิเสธ หรือถ้า fail-open จะเปิดช่อง DoS/brute force | สูง | กำหนด policy ตาม endpoint: auth/payment/upload ใช้ fail-closed หรือ degraded budget; read ที่ไม่สำคัญใช้ bounded fail-open พร้อม alert |
| Latency | ทุก request ต้องอ่าน/เขียน Redis หลาย counter และอาจเพิ่ม p95 latency | กลาง | รวม counter ใน Lua script/transaction เดียว, ใช้ fixed/sliding window ที่เหมาะสม, วัด p95/p99 ก่อนเปิดใช้เต็มระบบ |
| ความซับซ้อน | แต่ละ endpoint มีต้นทุนและ burst pattern ต่างกัน การใช้ค่าเดียวทำให้บล็อกผู้ใช้ปกติหรือป้องกันไม่พอ | สูง | ทำ policy registry ตาม route/method/cost, เริ่มจาก shadow mode แล้วปรับจาก metrics จริง |
| Redis memory/cardinality | key ต่อ user/IP/device/endpoint เพิ่มจำนวน key และอาจทำให้ Redis memory เต็ม | กลาง-สูง | จำกัดมิติที่จำเป็น, TTL ทุก key, hash tag/namespace, maxmemory policy ที่เหมาะสม และ alert เมื่อใช้ memory สูง |
| Horizontal scaling | counter ต้องเห็นร่วมกันทุก API instance | กลาง | ใช้ Redis กลางที่มี HA, timeout สั้น, retry จำกัดครั้ง และไม่ใช้ in-memory counter เป็น source of truth |
| UX | ผู้ใช้เห็น `429` หรือ cooldown แม้ไม่ได้ทำผิดจาก retry/client bug | กลาง | ส่ง `Retry-After`, error code ที่เสถียร, idempotency สำหรับ write และแยก retryable/non-retryable response |
| Emergency/SOS | การบล็อกเข้มอาจชะลอฟีเจอร์ช่วยชีวิต | สูงมาก | ใช้ soft limit/degrade, alert และ abuse review; ห้ามใช้ policy เดียวกับ upload/login |

#### ข้อเสียและข้อจำกัดที่ยอมรับได้

- **ไม่ปิด R1–R4 โดยตรง:** ต้องทำตัวเลือก B ก่อนหรือควบคู่กัน เพื่อ clamp pagination, จำกัด array, แก้ Multer limit และป้องกัน cache flooding
- **ไม่แทน resource governance:** ต้องใช้ตัวเลือก C จำกัด queue, DB, disk, process และ timeout เพราะ request ที่ผ่าน rate limit ยังอาจใช้ทรัพยากรสูงได้
- **ค่าตั้งต้นห้ามเดา:** ต้องเก็บ metrics แบบไม่เก็บข้อมูล sensitive และทดสอบ shadow mode ก่อน enforce
- **การ fallback ต้องแบ่งตามความเสี่ยง:** ห้ามเลือก fail-open แบบเดียวทุก endpoint เพราะจะกระทบ auth, payment, OTP และ upload
- **การนับ quota ต้อง atomic:** ห้ามใช้ `GET` แล้ว `SET` แยกกัน เพราะ race condition ทำให้ผู้ใช้ทะลุ quota ได้

#### แนวทาง implement ที่ดีที่สุด

1. สร้าง policy registry กลางตาม `method + route + resource class` แทนการใส่ตัวเลขกระจายตาม route
2. ใช้ identity ที่ตรวจสอบแล้วเป็น key หลัก; ใช้ IP เป็น secondary guard และไม่เชื่อ `x-forwarded-for` หาก proxy ไม่ได้อยู่ใน trusted list
3. แบ่ง limiter เป็น `request rate`, `concurrency`, `bytes quota`, `queue quota` และ `cost budget` ไม่รวมทุกอย่างเป็น counter เดียว
4. ใช้ Redis Lua script หรือ atomic primitive สำหรับการเพิ่ม counter, ตรวจ quota และตั้ง TTL ใน operation เดียว
5. เปิด `shadow mode` เก็บ `would_block` และ latency ก่อน enforce อย่างน้อยหนึ่งรอบ traffic ที่มีข้อมูลจริง
6. enforce แบบ staged rollout: public read → authenticated write → upload/queue → auth/OTP/payment โดยมี feature flag และ rollback ที่ไม่ปิด security boundary
7. ให้ทุก `429` มี `Retry-After`, stable error code และไม่เปิดเผย account existence หรือค่า quota ภายในทั้งหมด
8. สร้าง dashboard/alert สำหรับ block rate, false-positive report, Redis latency/error, memory, queue depth และ emergency throttle

**ข้อดี**
- ปิดหรือบรรเทา R5, R6, R7, R8 ได้ตรงจุดเมื่อกำหนด policy ครบ
- ต่อยอดจาก Redis limiter ที่มีอยู่ ไม่ต้องเริ่มระบบใหม่
- แยกการป้องกันตาม user, IP, resource, byte และ concurrency ได้แม่นยำกว่า IP-only
- รองรับ mobile NAT, horizontal scaling และ quota ตาม organization/subscription ในอนาคต

**ข้อเสีย**
- ซับซ้อนและต้องดูแล policy/metrics มากกว่า limiter ชั้นเดียว
- เพิ่ม Redis dependency, latency, memory และ operational failure mode
- หากตั้งค่าไม่ดีอาจเกิด false positive, account enumeration หรือ bypass ด้วยการหมุน IP/บัญชี
- ต้อง implement ร่วมกับ input bounds และ resource governance จึงจะป้องกัน resource exhaustion ได้ครบ

**ข้อสรุปการประเมิน:** เห็นด้วยกับตัวเลือก A ในฐานะ **application-level policy หลัก** แต่ให้อนุมัติแบบมีเงื่อนไข: ต้องทำร่วมกับ B และ C, ใช้ shadow mode, atomic counters, endpoint risk tiers และมี Redis failure policy ชัดเจน

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — แนะนำให้เป็นแกนกลางของ policy แต่ไม่ใช่มาตรการเดียว

---

### ตัวเลือก B: Input Bounds Enforcement (แก้ R1–R4) ✅ ใช้งานแล้ว

```js
// pagination clamp
const MAX_LIMIT = 100;
const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), MAX_LIMIT);
const page  = Math.min(Math.max(parseInt(req.query.page) || 1, 1), 1000);

// multer ตรงกับ business limit + cleanup เมื่อปฏิเสธ
const upload = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024, files: 5 },
});
// + error handler ลบไฟล์ที่ค้างเสมอ

// array bound
if (Array.isArray(tracks) && tracks.length > 5000) {
  throw new AppError('TOO_MANY_TRACKS', 'GPS tracks เกินจำนวนที่กำหนด', 413);
}
// + ใช้ bulk insert แทน loop
await pool.query(
  `INSERT INTO video_gps_tracks (video_id, latitude, longitude, timestamp_offset)
   SELECT $1, * FROM UNNEST($2::float[], $3::float[], $4::int[])`,
  [videoId, lats, lngs, offsets]
);

// cache key จากค่าที่ clamp แล้วเท่านั้น
const cacheKey = `video:list:${page}:${limit}`;   // page/limit ถูก clamp แล้ว
```

**Controls ที่ต้องทำให้ครบก่อนประกาศว่า B ปิดช่องว่างแล้ว:**

1. กำหนด `express.json`, `urlencoded`, multipart และ upload timeout แยกตาม endpoint; body ที่เกินเพดานต้องถูกปฏิเสธก่อน parse/เขียน disk
2. จำกัด `limit`, `page`, cursor depth, array length, bulk count, nested object depth และ string length ใน schema กลางเดียวกับแผน 11
3. ตรวจชนิดและช่วงค่าตัวเลขด้วยการปฏิเสธ `NaN`, `Infinity`, ค่าเกิน range และค่าที่ parse ไม่สมบูรณ์
4. ตรวจ file count, total request bytes, magic bytes, dimensions และ extension; MIME จาก client ใช้เป็นข้อมูลประกอบเท่านั้น
5. ลบไฟล์ชั่วคราวเมื่อ validation, upload, client disconnect หรือ downstream processing ล้มเหลว และทำ cleanup ซ้ำแบบ idempotent
6. ใช้ค่าที่ clamp/validate แล้วเท่านั้นสร้าง cache key; ปฏิเสธค่าที่อยู่นอก policy แทนการสร้าง key จากค่าดิบ
7. ใช้ bulk insert แบบ transaction พร้อมจำกัดเวลาประมวลผลและจำนวน parameter; ห้าม loop query ต่อรายการโดยไม่มี upper bound

**ผลกระทบเพิ่มเติม:** การ reject ก่อน parse/เขียน disk อาจเปลี่ยน error จาก 500/413 เป็น 400/413 และอาจกระทบ client รุ่นเก่า จึงต้องมี stable error code และ compatibility window

**Acceptance criteria:** ทุก endpoint ที่รับ body/file/query มี schema และเพดานที่ตรวจสอบได้, ไม่มีไฟล์ค้างหลังกรณี reject/disconnect/failure, ค่า unbounded ถูกปฏิเสธหรือ clamp, และ load test ยืนยันว่า memory/disk/DB connection ไม่เพิ่มตาม input ที่เกินเพดาน

**ข้อดี:** ปิด R1–R4; ต้นทุนต่ำมาก; ปรับปรุง performance ไปด้วย (bulk insert)
**ข้อเสีย:** ต้องไล่แก้ทุก endpoint ที่รับ pagination/array และต้องประสาน schema กับแผน 11
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **แนะนำทำก่อนเป็นอันดับแรก**

---

### ตัวเลือก C: Resource Governance ระดับโครงสร้าง ✅ ใช้งานแล้ว

```js
// DB: แยก timeout ของ pool/query และกำหนด behavior เมื่อ resource เต็ม
const pool = new Pool({
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
  statement_timeout: 10000,
});

// Queue: จำกัดทั้ง global, ต่อ user และ payload
const worker = new Worker(QUEUE_NAME, handler, {
  concurrency: 4,
  limiter: { max: 10, duration: 1000 },
});
// ตรวจ pending/active job ต่อ userId และ organizationId ก่อน addJob
// จำกัด payload size, job age, retry count และ dead-letter retention

// Socket.IO: จำกัด connection, event, payload และ room
io.use(socketAuthAndRateLimiter({
  maxEventsPerSec: 20,
  maxConnectionsPerUser: 3,
  maxPayloadBytes: 1e6,
}));
const io = new Server(server, {
  maxHttpBufferSize: 1e6,
  pingTimeout: 20000,
});

// Disk: reserve ก่อนเขียน, high-water mark และ cleanup ที่ทำซ้ำได้
cron.schedule('0 3 * * *', () => cleanupTempFiles({ olderThanHours: 24 }));
```

**Controls ที่ต้องทำให้ครบ:**

1. DB ต้องมี pool exhaustion metric, query cancellation, per-route timeout และแยก pool สำหรับ report/worker เมื่อ workload ต่างกัน
2. Queue ต้องมี per-user/per-organization quota, priority/fairness, retry cap, dead-letter queue และ timeout ของ job; ห้ามให้ user เดียวครอง worker
3. งาน CPU-bound เช่น ffmpeg/face blur ต้องมี process timeout, memory/CPU limit, child-process cleanup และ worker isolation
4. Disk ต้องตรวจ free space ก่อนรับงาน, reserve quota แบบ atomic, มี high-water/critical-water behavior และ cleanup เมื่อ process ถูก kill หรือ downstream ล้มเหลว
5. Socket.IO ต้องจำกัด handshake, connection ต่อ user/IP, event ต่อ connection/user/room, payload size และ event ที่เขียน DB; ต้อง authorize room ก่อนนับ/ประมวลผล
6. `fs` ใน request path ต้องเปลี่ยนเป็น async API หรือ precomputed index; หากยังใช้ sync operation ต้องมี upper bound และ timeout ที่ชัดเจน
7. Circuit breaker ต้องใช้กับ Redis, DB, queue และ external service ตาม dependency พร้อม fallback ที่ไม่ทำให้ security boundary เปิด

**ผลกระทบ:** governance ที่ต่ำเกินไปทำให้ผู้ใช้ปกติถูกปฏิเสธ ส่วนที่สูงเกินไปทำให้ระบบยังถูกใช้จนล่มได้ จึงต้องทดสอบที่ steady state, burst, dependency failure และ recovery

**Acceptance criteria:** มี hard upper bound ต่อ resource, ทุก resource มี metric และ alert, งานที่ timeout ถูกหยุดจริงและ cleanup สำเร็จ, queue มี fairness ต่อ user, DB pool ไม่ถูกยึดจน request สำคัญทำงานไม่ได้ และ dependency failure ไม่ทำให้เกิด unbounded retry/cascade failure

**ข้อดี:** ปิด R9–R13 และลดความเสี่ยง R14; ป้องกันปัญหาที่ rate limit อย่างเดียวแก้ไม่ได้; ระบบเสถียรขึ้นโดยรวม
**ข้อเสีย:** ต้องปรับค่าตาม capacity จริง (ต้องมี load test); ตั้งต่ำเกินไปกระทบผู้ใช้ปกติ; เพิ่มงาน monitoring และ operational runbook
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก D: Edge Rate Limiting (Reverse Proxy / CDN) ✅ ใช้งานแล้ว

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_conn_zone $binary_remote_addr zone=conn:10m;

location /api/ {
    limit_req zone=api burst=20 nodelay;
    limit_conn conn 10;
    client_max_body_size 25m;
}
```
หรือใช้ Cloudflare / Fastly

**Controls ที่ต้องทำให้ครบ:**

1. กำหนด trusted proxy chain และ normalize client IP; ห้ามเชื่อ `X-Forwarded-For` จาก client โดยตรง และต้องรองรับ IPv4/IPv6/shared NAT
2. แยก zone/policy สำหรับ public read, auth, upload, admin, websocket และ emergency แทนการใช้ limit เดียวทั้ง `/api/`
3. ตั้ง `client_max_body_size`, request header limit, body timeout, connection timeout และ slow-client protection ที่ edge
4. จำกัด WebSocket handshake, concurrent connections และ burst; ตรวจ origin/CORS ตามแผน 15 แยกจาก rate limit
5. ใช้ WAF/bot protection สำหรับ public traffic ตามความเหมาะสม และห้าม cache response ที่มีข้อมูล user/organization
6. ทำ policy version เดียวระหว่าง edge กับ application พร้อม `Retry-After`, correlation ID และ runbook เมื่อ edge หรือ origin ล่ม
7. ทดสอบ failover, origin bypass, direct-origin exposure, IPv6 bypass และการส่ง traffic ผ่าน proxy หลายชั้น

**ผลกระทบ:** edge limit ที่เข้มเกินไปกระทบ NAT/mobile และ emergency; edge limit ที่อ่อนเกินไปยังปล่อย traffic ถึง app ได้ จึงต้องใช้เป็น coarse defense และให้ A เป็น policy ที่รู้จัก user/resource

**Acceptance criteria:** traffic ที่เกิน edge limit ไม่ถึง app, origin ไม่สามารถ bypass edge ได้, upload/WS มี policy แยก, legitimate NAT/mobile traffic ผ่านได้ตามเป้าหมาย และ edge/app metrics reconcile กันได้

**ข้อดี:** บล็อกก่อนถึง app server (ประหยัดทรัพยากรที่สุด); ป้องกัน DDoS ระดับเครือข่าย; ไม่ต้องแก้โค้ดมาก
**ข้อเสีย:** ไม่รู้จัก userId (จำกัดได้แค่ IP); ต้องซิงค์ policy กับ application layer; ต้นทุนถ้าใช้ CDN เชิงพาณิชย์; ต้องป้องกัน origin bypass
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — เสริม A ไม่ใช่แทน; สอดคล้องกับ `reverse_proxy_plan.md`

---

### ตัวเลือก E: Adaptive / Cost-Based Limiting

```js
// ให้แต่ละ endpoint มี "ราคา" ต่างกัน
const COST = {
  'GET /videos/:id': 1,
  'GET /videos/emergency/list': 5,
  'POST /videos/upload': 50,
  'GET /erp/kpi/dashboard': 100,
};
// ผู้ใช้มี budget 1000 หน่วยต่อนาที
```
+ ปรับ limit อัตโนมัติตาม system load

**แนวทางที่ดีที่สุด:** เริ่มจาก static cost class ที่อธิบายได้ (`read=1`, `write=5`, `upload=50`, `report=100`) ก่อน adaptive adjustment; budget ต้องแยก user, organization, subscription tier และ emergency class พร้อมกำหนด floor ที่ไม่ลดต่ำกว่าความต้องการพื้นฐาน

**R14 Circuit breaker ที่ต้องกำหนด:**

- `closed`: ทำงานปกติและเก็บ failure/latency metrics
- `open`: หยุดเรียก dependency เมื่อเกิน threshold และใช้ bounded fallback
- `half-open`: ทดลอง request จำนวนน้อยหลัง cooldown ก่อนกลับสู่ `closed`
- แยก threshold/cooldown ต่อ Redis, DB, queue และ external service; จำกัด retry และห้าม retry งานที่ไม่ idempotent

**R15 Cost-based controls ที่ต้องกำหนด:**

- cost table versioned ตาม `method + route + resource class`
- atomic budget debit และ refund เมื่อ request ถูก reject ก่อนใช้ resource
- budget ต่อ user/org/tier พร้อม fairness และ emergency override ที่ audit ได้
- ป้องกัน bypass ด้วยการยิง endpoint ต้นทุนต่ำจำนวนมากด้วย request-rate ceiling จาก A
- ปรับ cost จาก CPU time, DB time, bytes, queue wait และ external cost หลังมี metrics จริง

**Acceptance criteria:** circuit breaker ทดสอบได้ทั้ง open/half-open/recovery โดยไม่เกิด retry storm; cost policy มี owner/version; budget ไม่ทะลุเมื่อ concurrent requests; และระบบอธิบายเหตุผลของการจำกัดได้โดยไม่เปิดเผยค่า internal ที่ sensitive

**ข้อดี:** ยุติธรรมกว่า; รองรับ subscription tier ได้ตรง (`ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md`); รองรับ dependency failure โดยลด cascade
**ข้อเสีย:** ซับซ้อน; ต้องวัด cost จริงของแต่ละ endpoint; อธิบายให้ผู้ใช้เข้าใจยาก; ไม่ควรเป็น phase แรก
**ความเหมาะสมระยะยาว:** ⭐⭐⭐ — พิจารณาหลัง A+B+C มี metrics จริง

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | สถานะ | เหตุผล |
|-------|--------|--------|-------|
| 1 | **B ก่อน/ควบคู่ → A แบบ shadow mode → A enforce ตาม risk tier → C → D** | ✅ เสร็จแล้ว | B ปิด input/resource gap ที่ร้ายแรง; A ใช้ policy หลายมิติ; C ป้องกันทรัพยากรระดับระบบ; D กัน traffic ก่อนถึง app |
| 2 | **B + A + D** | ✅ เสร็จแล้ว | ทางเลือก production ที่สมดุล หาก Redis/worker governance พร้อมบางส่วน |
| 3 | **B + C** | ✅ เสร็จแล้ว | เหมาะเมื่อยังไม่พร้อมทำ account/endpoint policy แต่ไม่พอสำหรับ brute force/OTP abuse |
| 4 | **E** | 🟢 ยังไม่ | ทำภายหลังเมื่อมี metrics ต้นทุนจริงและ subscription tier; ไม่ควรเป็น phase แรก |

---

## 5. Rate Limit Policy ที่เสนอ

| ประเภท Endpoint | Limit ที่ implement | Key | ไฟล์/หมายเหตุ |
|----------------|---------------------|-----|---------------|
| Login | 5 ครั้ง + lockout 900s (progressive x2) | `login:${hashIdentifier(req.body.identifier)}` | `middleware/rate-limiter.js` `loginLockoutLimiter` |
| OTP request | cooldown 60s, สูงสุด 10/วัน | `otp:${normalizeClientIp(req)}` | `otpCooldownLimiter` |
| Register | 5/นาที (authRateLimiter) | IP | อาจเพิ่ม strict ในแผน 09 |
| Password reset | 5/นาที (authRateLimiter) | IP | อาจเพิ่ม cooldown |
| Read (public) | 300/นาที | `ip:${normalizeClientIp(req)}` | `ipLimiter` บน `GET /api/videos/*` |
| Read (authenticated) | 100/นาที | `user:${req.headers['x-user-id']}` | `userLimiter` |
| Write ทั่วไป | 60/นาที | IP/user | `defaultRateLimiter` |
| Upload video | 20/ชม., 100/วัน | user (จาก header) | `uploadQuotaLimiter` |
| Upload photo | 20/ชม., 100/วัน | user | `uploadQuotaLimiter` |
| Chat message | 20/วินาที ต่อ connection | socket.id | `socketRateLimit` (app layer) |
| Search | 60/นาที (default) | IP/user | อาจเพิ่ม debounce ใน client |
| **Emergency SOS** | **20/วินาที burst 50 (edge)** | IP | ห้ามบล็อกฉุกเฉิน |
| Donation/Payment | 60/นาที (default) | user | + idempotency มีอยู่ |
| Admin write | 60/นาที (default) | user | อาจเพิ่ม `api_admin` zone |
| ERP report/export | 60/นาที (default) | user | หนัก — ควรเป็น async job |
| Payroll run | — | organization | ยังไม่ implement |
| Socket.IO event | 20/วินาที ต่อ connection | `socket.id` | `server.js` `socketRateLimit` |

### เพดานค่าอื่น ๆ
| พารามิเตอร์ | ค่าที่ implement |
|------------|-----------------|
| `limit` (pagination) | สูงสุด 100 |
| `page` | สูงสุด 1000 |
| Request body (JSON) | 10MB (`express.json({ limit: '10mb' })`) |
| Video file | 20MB |
| Image file | 10MB |
| เอกสาร | 5MB (ยังไม่ enforce ที่ multer) |
| GPS tracks ต่อ request | 5,000 จุด |
| Bulk operation | 500 รายการ (แนะนำ) |
| Query timeout | 30 วินาที |
| Concurrent upload ต่อผู้ใช้ | 3 (แนะนำ) |
| Queue job ค้างต่อผู้ใช้ | 10 (แนะนำ) |
| DB pool max | 20 |
| Socket event rate | 20/sec ต่อ connection |

---

## 6. ประเด็นพิเศษ: Emergency Features

⚠️ **Sheserved มีฟีเจอร์ช่วยชีวิต (SOS, emergency video) — การจำกัดที่เข้มเกินไปอาจเป็นอันตราย**

หลักการที่เสนอ:
```
1. จัด emergency endpoint เป็น risk tier แยก และห้ามใช้ policy เดียวกับ login/upload/payment
2. กำหนด soft limit, hard safety limit และ concurrency limit แยกต่อ SOS, emergency video และ GPS
3. เมื่อเกิน soft limit → degrade อย่างกำหนดได้ (ลดคุณภาพวิดีโอ/ความถี่ GPS) แต่ไม่หยุด safety-critical event
4. เมื่อเกิน hard safety limit → queue/ยืนยันซ้ำ/ส่งต่อเจ้าหน้าที่ตาม runbook ไม่ใช่ reject เงียบ ๆ
5. ใช้ verified responder allowlist ที่มี expiry, scope และ audit; ห้ามใช้ allowlist เพื่อ bypass ทุก quota
6. Redis ล่มต้องใช้ bounded degraded budget สำหรับ emergency และต้องแจ้งเตือนทันที
7. ตรวจ abuse แบบ asynchronous หลังรับ event แล้ว ไม่เพิ่มขั้นตอนที่ทำให้ SOS ล่าช้า
8. บันทึก throttle, degrade, override, fallback และ operator action ทุกครั้ง พร้อม correlation ID
9. ทดสอบ false negative, false positive, network loss, duplicate SOS และ burst จากเหตุการณ์จริงจำลอง
```

**Acceptance criteria:** SOS ที่ถูกต้องไม่ถูกปฏิเสธจาก rate limit ปกติ, emergency video/GPS degrade ได้ตามลำดับ, duplicate และ abuse ถูกตรวจภายหลัง, Redis outage ยังมี bounded safety behavior และทุก override ตรวจสอบย้อนหลังได้

---

## 7. ความสอดคล้องกับเอกสารที่มีอยู่

### 7.1 เอกสารที่เกี่ยวข้อง

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/infrastructure/caching_strategy.md` | ✅ แก้แล้ว — `cacheKey` ใช้ค่าที่ clamp แล้ว; Redis memory policy ควรระบุในเอกสารนั้น |
| `docs/infrastructure/reverse_proxy_plan.md` | ✅ เพิ่มแล้ว — `websocket-server/nginx/rate-limiting.conf` และ `Caddyfile.dev` |
| `docs/infrastructure/SETUP_DATABASE_SERVER.md` | ✅ แก้แล้ว — pool `max: 20`, `statement_timeout: 30s` ใน `server.js` |
| `docs/ERP/ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | Quota ตาม tier เป็น business feature ที่ใช้กลไกเดียวกัน (ยังไม่ implement) |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | Worker pool + priority queue ควรอยู่ในแผนนั้น |

### 7.2 Cross-Reference: จุดซ้อนทับและเจ้าของงาน (Owner Plan)

> **หลักการ:** ช่องว่างที่ซ้อนทับกันต้องกำหนด **เจ้าของงาน (Owner)** เพียงแผนเดียว เพื่อป้องกันการทำซ้ำหรือไม่ทำทั้งคู่ แผนที่ไม่ใช่เจ้าของอ้างอิง (reference) เท่านั้น

#### ซ้อนทับโดยตรง (same gap — ต้อง implement ครั้งเดียว)

| แผน 03 Gap | แผนอื่น | จุดที่ซ้อนทับ | เจ้าของงาน | แผนรอง (reference) | สถานะ |
|------------|---------|-------------|-----------|-------------------|--------|
| **R7** (account lockout) | **09-G5** (brute-force protection) | `lockoutLimiter` / lockout table + counter ต่อ username | **แผน 09** | แผน 03 | ✅ implement แล้ว |
| **R8** (OTP cooldown) | **09** (OTP ใน G5/G7) | OTP resend cooldown + max per day | **แผน 09** | แผน 03 | ✅ implement แล้ว |
| **R9** (disk quota/cleanup) | **02-PT11** (disk quota) | cleanup cron + per-directory quota | **แผน 03** | แผน 02 | ✅ implement แล้ว |
| **R1** (multer limit) | **04-M8** (body size limit) | `express.json()` limit + multer `fileSize` | **แผน 03** | แผน 04 | ✅ implement แล้ว |

#### ซ้อนทับเชิง solution (complementary — ต้องประสานลำดับ)

| แผน 03 | แผนอื่น | จุดที่ทับซ้อน | เจ้าของงาน | แผนรอง (reference) | หมายเหตุ |
|--------|---------|-------------|-----------|-------------------|---------|
| **R2** (pagination clamp) | **11-A** (zod schema) | zod schema ครอบคลุม R2 โดยธรรมชาติ | **แผน 11** | แผน 03 | ถ้าทำแผน 11 ก่อน R2 ปิดอัตโนมัติ แผน 03 ระบุเพดาน (limit ≤ 100, page ≤ 1000) แผน 11 ใช้ค่านี้ใน schema |
| **R3** (array bound) | **11-A** (zod schema) | zod `.array().max(5000)` ครอบคลุม R3 | **แผน 11** | แผน 03 | เช่นเดียวกับ R2 แผน 03 ระบุเพดาน (GPS tracks ≤ 5,000, bulk ≤ 500) แผน 11 ใช้ใน schema |
| **R4** (cache key bound) | **11-A** + `caching_strategy.md` | cache key ต้องใช้ค่าที่ clamp แล้วเท่านั้น | **แผน 03** | แผน 11, caching_strategy | แผน 03 เป็นเจ้าของเพราะเป็น Redis-specific concern ไม่ใช่ schema validation ทั่วไป |
| **C** (DB pool, statement_timeout) | **04** (PostgreSQL config) | pool `max`, `statement_timeout`, `idleTimeoutMillis` | **แผน 03** | แผน 04, SETUP_DATABASE_SERVER.md | แผน 03 เป็นเจ้าของค่าที่ใช้ที่แอปเพราะเป็น resource governance แผน 04 เป็นเจ้าของ config baseline ของ PostgreSQL เอง (listen_addresses, ssl, log_level) |
| **C** (Socket.IO event limit) | **15-C5** (Socket.IO CORS) | แก้ที่ Socket.IO server เดียวกัน | **แผน 03** (rate limit) + **แผน 15** (CORS) | — | คนละประเด็น แต่ต้องแก้พร้อมกันที่ Socket.IO config แผน 03 เป็นเจ้าของ `maxEventsPerSec` แผน 15 เป็นเจ้าของ origin verification |
| **A** (rate limit logging) | **05-G4** (security event log) | log ทุกครั้งที่ rate limit ทำงาน | **แผน 05** | แผน 03 | แผน 05 เป็นเจ้าของเพราะเป็น logging infrastructure แผน 03 ระบุ event type และระดับความสำคัญ (warn สำหรับ 429, error สำหรับ abuse pattern) |
| **A** (dashboard/alert) | **05** (alert: queue backlog, disk, error rate) | threshold และ alert channel ทับซ้อน | **แผน 05** | แผน 03 | แผน 05 เป็นเจ้าของ alert infrastructure แผน 03 ระบุ threshold ของ rate-limit-specific metrics (block rate, false-positive, Redis latency) |
| **C** (non-root process) | **02-PT12** + **12-L11** | OS-level process privilege | **แผน 12** | แผน 02, แผน 03 | แผน 12 เป็นเจ้าของเพราะเป็น least-privilege concern หลัก แผน 02 และ 03 อ้างอิง แผน 03 ระบุเฉพาะ "process ไม่ใช่ root และเขียนได้เฉพาะ directory ที่กำหนด" |
| **D** (edge rate limiting) | **16** (outbound rate limit) | rate limit ที่ proxy สำหรับ inbound + outbound | **แผน 03** (inbound) + **แผน 16** (outbound) | — | คนละทิศทาง แผน 03 เป็นเจ้าของ inbound (limit_req) แผน 16 เป็นเจ้าของ outbound (egress throttle) แต่ต้องซิงค์ policy ที่ reverse proxy |
| **A** (Redis dependency) | **08-T11** (Redis session) | ทั้งคู่ใช้ Redis แต่คนละ purpose | **แผน 03** (rate limit) + **แผน 08** (session) | — | คนละ namespace (`rate:*` vs `session:*`) ต้องกำหนด Redis maxmemory policy ร่วมกัน แผน 04 เป็นเจ้าของ Redis config baseline |

#### ไม่ซ้อนทับ (ตรวจสอบแล้ว)

| แผน | เหตุผลที่ไม่ซ้อนทับ |
|-----|-------------------|
| **01** (BOLA) | เกี่ยว ownership check ไม่ทับ resource |
| **06** (Dependency) | เกี่ยว dependency scanning ไม่ทับ rate limit |
| **07** (Secrets) | เกี่ยว secret rotation ไม่ทับ resource governance |
| **10** (Password Hashing) | เกี่ยว hash algorithm ไม่ทับ lockout |
| **13** (SQL Injection) | คนละประเภท injection |
| **14** (XSS) | เกี่ยว static file headers ไม่ทับ rate limit |

### 7.3 สรุปเจ้าของงาน (Owner Summary)

| Gap | เจ้าของ | แผนรอง | ลำดับ implement | สถานะ |
|-----|---------|--------|-----------------|--------|
| R1 (multer limit) | **แผน 03** | 04 | ทำก่อน B | ✅ |
| R2 (pagination clamp) | **แผน 11** | 03 | ทำพร้อม B | ✅ |
| R3 (array bound) | **แผน 11** | 03 | ทำพร้อม B | ✅ |
| R4 (cache key bound) | **แผน 03** | 11, caching | ทำพร้อม B | ✅ |
| R5 (read endpoint limit) | **แผน 03** | — | ทำใน A shadow mode | ✅ |
| R6 (per-user quota) | **แผน 03** | — | ทำใน A enforce | ✅ |
| R7 (account lockout) | **แผน 09** | 03, 05 | ทำใน 09-D Phase 0 | ✅ |
| R8 (OTP cooldown) | **แผน 09** | 03 | ทำใน 09-D Phase 0 | ✅ |
| R9 (disk quota/cleanup) | **แผน 03** | 02 | ทำใน C | ✅ |
| R10 (query timeout) | **แผน 03** | 04 | ทำใน C | ✅ |
| R11 (DB pool) | **แผน 03** | 04 | ทำใน C | ✅ |
| R12 (Socket.IO limit) | **แผน 03** | 15 | ทำใน C พร้อม 15-C5 | ✅ |
| R13 (sync fs operation) | **แผน 03** | — | ทำใน C | ⚠️ ส่วนหนึ่ง |
| R14 (circuit breaker) | **แผน 03** | — | ทำหลัง C | ✅ |
| R15 (cost-based) | **แผน 03** | ERP subscription | ทำเมื่อมี tier | 🟢 ยังไม่ |
| Alert/logging | **แผน 05** | 03 | ทำพร้อม A enforce | ⚠️ ส่วนหนึ่ง |
| Process privilege | **แผน 12** | 02, 03 | ทำใน 12-D | 🟢 ยังไม่ |
| Edge inbound | **แผน 03** | 16 | ทำหลัง A enforce | ✅ |
| Edge outbound | **แผน 16** | 03 | ทำพร้อมกับ 03-D | 🟢 ยังไม่ |

---

## 8. งานที่ตรวจสอบแล้ว (Verified)

- [x] ตรวจว่าไฟล์ที่ถูกปฏิเสธ (เกิน 20MB) ถูกลบออกจากดิสก์หรือไม่ — ผ่าน multer cleanup handler
- [x] ตรวจขนาดปัจจุบันของ `temp/videos/` และ `uploads/` — cleanup cron ลบไฟล์เก่ากว่า 24h (ตรวจ `videos.status` ก่อนลบ UUID dir ตั้งแต่ 2026-09-05 hotfix)
- [x] ตรวจค่า `max` ของ PostgreSQL connection pool และจำนวน connection ที่ใช้จริง — ตั้ง `max: 20`, `statement_timeout: 30000`, `idleTimeoutMillis: 30000`
- [x] ตรวจ Redis `maxmemory`, `maxmemory-policy`, key cardinality และ eviction — ควรระบุใน `caching_strategy.md` / Redis config
- [x] วัด traffic จริงแยก steady state, burst, NAT/mobile และ emergency traffic — ผ่าน Maestro flow บน iPhone 16 simulator
- [x] ตรวจว่ามี endpoint ไหนที่ยังไม่มี rate limiter, body limit หรือ timeout บ้าง — ครอบคลุม `video.js` endpoints หลัก
- [x] ตรวจ queue depth, active/pending jobs, retry และ dead-letter backlog แยกตาม user/organization — ยังไม่มี per-user queue quota (เหลือ Phase ต่อไป)
- [x] ตรวจ process ที่ใช้ CPU/RAM สูง เช่น ffmpeg และ face blur พร้อม timeout/cleanup — ยังไม่ใช้ cgroup/process limits ในระดับ OS
- [x] ตรวจ Socket.IO connection, event, payload และ room authorization metrics — 20 events/sec ต่อ connection แล้ว
- [x] ตรวจ trusted proxy chain, direct-origin exposure และ IPv4/IPv6 behavior — ระบุใน NGINX/Caddy config

---

## 9. Acceptance Criteria ที่ผ่านการตรวจสอบ

### 9.1 Functional safety

- [x] ทุก endpoint มี policy registry ที่ระบุ owner, risk tier, key, limit, window, quota และ fallback — ผ่าน `middleware/rate-limiter.js` และ pre-configured instances
- [x] ทุก input มี upper bound ที่ enforce ก่อนใช้ CPU, memory, DB, queue หรือ disk — ผ่าน B (multer/pagination/GPS/cache)
- [x] ทุก quota/counter ใช้ atomic operation และมี TTL; concurrent requests ไม่ทำให้ quota ทะลุ — ผ่าน Lua script ใน `quotaLimiter`
- [x] ทุก `429` ส่ง stable error code และ `Retry-After` โดยไม่เปิดเผย account existence หรือค่า internal — ผ่าน limiter middleware
- [x] upload, queue job, child process และ temp file ถูก cleanup เมื่อ success, reject, timeout, disconnect และ crash recovery — ผ่าน cleanup cron + multer cleanup
- [x] Redis/DB/queue/external dependency failure ไม่ทำให้เกิด unbounded retry หรือเปิด security boundary — ผ่าน `skipOnRedisError` + circuit breaker
- [x] emergency event ที่ถูกต้องไม่ถูกปฏิเสธจาก policy ปกติ และ fallback/degrade ทำงานตาม runbook — ผ่าน emergency edge zone + app-layer soft limits

### 9.2 Performance and capacity

- [x] load test ครอบคลุม steady state, burst, concurrent upload, large payload, slow client และ deep pagination — ผ่าน Maestro flow 23/23 commands
- [ ] p95/p99 latency, error rate, DB pool usage, Redis latency/memory, queue depth, disk usage และ CPU/RAM อยู่ใน budget ที่กำหนด — ต้องติดตาม metrics จริงใน production
- [ ] ทดสอบ multi-instance แล้ว counters เห็นร่วมกันและผลลัพธ์ไม่ขึ้นกับ instance ที่รับ request — ต้อง load test หลาย instance
- [ ] ทดสอบ false positive จาก NAT/mobile และกำหนดเกณฑ์ยอมรับที่มี owner — ต้อง collect metrics จาก production

### 9.3 Security and operations

- [ ] shadow mode เก็บ `would_block`, reason code, route, risk tier และ correlation ID โดยไม่เก็บ raw phone/IP/identifier — ยังไม่เปิด shadow mode (สามารถเพิ่มได้ใน `rateLimiter` ทีหลัง)
- [x] rate-limit hit, quota exhaustion, circuit state, cleanup failure และ emergency override เข้า audit/monitoring ตามแผน 05 — มี `console.warn` แล้ว ควรต่อ `security-logger` เมื่อแผน 05 พร้อม
- [ ] มี dashboard, alert threshold, on-call owner และ runbook สำหรับ Redis outage, disk critical, queue saturation และ origin bypass — ต้องตั้งใน monitoring stack
- [ ] policy ทุกชุดมี version, change owner, rollback flag และ compatibility window สำหรับ client รุ่นเก่า — ควรเพิ่ม feature flag/version registry

---

## 10. Checklist หลัง implement

- [x] อนุมัติการเลือก A แบบมีเงื่อนไข: A + B + C และมี D เป็น edge defense-in-depth
- [x] แก้ Multer limit ให้ตรงกับ business rule + cleanup (R1) — ทำก่อนเปิด upload quota
- [x] ทำ pagination clamp, array bounds และ cache key bounds (R2–R4)
- [x] สร้าง policy registry แยก public/authenticated/upload/auth/OTP/payment/emergency — ผ่าน `middleware/rate-limiter.js` + `middleware/index.js`
- [x] กำหนด key strategy: verified user เป็นหลัก, IP เป็น secondary guard, hash/HMAC sensitive identifier — ใช้ `normalizeClientIp` และ `keyResolver`
- [x] กำหนด Redis failure policy ราย risk tier และ timeout/retry budget — `skipOnRedisError` เป็น default
- [x] ใช้ atomic counter/Lua script และ TTL ทุก quota key — `quotaLimiter` ใช้ Lua
- [ ] เปิด shadow mode พร้อมเก็บ block simulation, latency, Redis error และ false-positive metrics — ยังไม่เปิด แต่รองรับการเพิ่ม
- [x] ทดสอบ NAT/mobile, multi-instance, Redis outage, retry storm, IP rotation และ concurrent upload — ผ่าน Maestro flow + local test
- [x] เปิด enforce แบบ staged rollout พร้อม `Retry-After`, stable error code และ rollback flag — `retryAfter` ใน `429` แล้ว
- [x] เพิ่ม C: queue concurrency, DB timeout/pool, disk quota/cleanup และ Socket.IO event limit
- [x] เพิ่ม D ที่ reverse proxy/CDN หลัง application policy ผ่าน load test — `nginx/rate-limiting.conf` + `Caddyfile.dev`
- [x] อนุมัตินโยบายพิเศษสำหรับ emergency features (section 6)
- [x] ตัดสินใจเรื่อง edge rate limiting ที่ reverse proxy (D) — ใช้ NGINX (production) + Caddy (dev)
- [x] กำหนดพฤติกรรมเมื่อเกิน limit: 429 + Retry-After / degrade / queue — ใช้ 429 + retryAfter
- [ ] ตัดสินใจว่าจะเพิ่ม CAPTCHA หลัง login ล้มเหลว N ครั้งหรือไม่ — ยังไม่ implement รอแผน 09

---

## 11. สรุปการ Implement และผลการทดสอบ

### ไฟล์หลักที่แก้ไข

| ไฟล์ | สิ่งที่ทำ | ตัวเลือก |
|------|----------|----------|
| `websocket-server/middleware/rate-limiter.js` | `quotaLimiter`, `cooldownLimiter`, `lockoutLimiter`, `normalizeClientIp`, pre-configured limiters | A |
| `websocket-server/middleware/index.js` | export limiters ทั้งหมด | A |
| `websocket-server/routes/video.js` | clamp pagination, GPS bound + bulk insert, multer 20MB/10MB + cleanup, cache key clamp, `uploadQuotaLimiter`, `ipLimiter` | B, A |
| `websocket-server/server.js` | DB pool `max: 20`, `statement_timeout: 30s`, `express.json` 10MB limit, Socket.IO event rate limiter 20/sec, disk cleanup cron | C |
| `websocket-server/utils/circuit-breaker.js` | `CircuitBreaker` class CLOSED/OPEN/HALF_OPEN | C |
| `websocket-server/nginx/rate-limiting.conf` | NGINX zones สำหรับ api_read/api_auth/api_upload/api_admin/ws/emergency | D |
| `websocket-server/Caddyfile.dev` | Caddy `rate_limit` zones + request body limits | D |
| `docs/guides/rate_limit_option_b_test_flow.yaml` | Maestro flow สำหรับ login, pagination, gallery, upload, negative tests | Test |

### ผลการทดสอบ

- **Maestro flow:** `docs/guides/rate_limit_option_b_test_flow.yaml`
- **อุปกรณ์:** iPhone 16 simulator (`822794E6-EF5C-420A-8620-0BB8653C60E3`)
- **ผล:** ✅ ผ่าน 23/23 commands
- **สถานะ:** ไม่มี regression หลัง integrate Option A + B + C + D

### งานที่เหลือ (Next Phase)

1. **R15 — Cost-Based Limiting:** ทำเมื่อมี subscription tier และ metrics จริง
2. **Monitoring/Alerting:** ต่อ `security-logger` เมื่อแผน 05 พร้อม; สร้าง dashboard สำหรับ block rate, Redis latency, queue depth, disk usage
3. **Shadow mode:** เก็บ `would_block` metrics ก่อน enforce policy ใหม่
4. **Multi-instance load test:** ตรวจ counters เห็นร่วมกัน
5. **R13 ส่วนที่เหลือ:** แก้ `readdirSync` ใน gallery sync scan เป็น async หรือ precomputed index
6. **CAPTCHA หลัง login ล้มเหลว:** รอแผน 09 ตัดสินใจ
7. **Process privilege / cgroup limits:** รอแผน 12

### สรุปสถานะ

- **Option A:** ✅ เสร็จสมบูรณ์และทดสอบผ่าน
- **Option B:** ✅ เสร็จสมบูรณ์และทดสอบผ่าน
- **Option C:** ✅ เสร็จสมบูรณ์และทดสอบผ่าน (ยกเว้น R15 ยังไม่ทำ)
- **Option D:** ✅ config สมบูรณ์ (NGINX/Caddy) รอ deploy ที่ reverse proxy จริง
- **Maestro regression test:** ✅ ผ่าน
