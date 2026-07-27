# แผนป้องกัน 03: Rate Limiting และ Resource Exhaustion

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** 09 (AuthN — brute force), 11 (Input Validation — payload size), 02 (Path Traversal — disk), 04 (Misconfiguration)
> **ขอบเขต:** ไม่ใช่แค่ "จำกัดจำนวน request" แต่รวมถึงการจำกัด **ทรัพยากรทุกชนิด** ที่ผู้ใช้คนหนึ่งใช้ได้ — CPU, RAM, disk, DB connection, queue slot
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-A ลำดับ 3** โดยแก้ upload/disk/pagination/timeout ก่อน policy rate limit ขั้นสูง
> **เหตุผล:** multer ที่ยอมรับ 500MB ก่อน business check 20MB ทำให้ resource ถูกใช้ไปแล้ว; ต้อง reject ก่อนเขียน disk, cleanup เมื่อ fail และจำกัด queue/DB/response size เพื่อป้องกัน DoS จริง ไม่ใช่เพียงนับ request

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่ implement แล้ว ✅

| องค์ประกอบ | รายละเอียด | ไฟล์ |
|-----------|------------|------|
| Redis rate limiter | `rateLimiter({ maxRequests, windowSec, keyPrefix })` | `middleware/rate-limiter.js` |
| Preset limiters | `defaultRateLimiter`, `strictRateLimiter`, `authRateLimiter` | `middleware/index.js` |
| Upload limiter | `rateLimiter({ maxRequests: 30, windowSec: 60, keyPrefix: 'rate:upload' })` | `video.js:25` |
| Idempotency | ป้องกันการส่งซ้ำจาก retry | `middleware/idempotency.js` |
| Duplicate check | `duplicateCheckMiddleware('video-upload', 5)` | ใช้หลาย route |
| Multer size limit | 500MB (video), 5MB (watermark) | `video.js:44`, `admin.js:33` |
| Pagination | `LIMIT $1 OFFSET $2` ใน list endpoints | `video.js:520` |
| Cache-aside | ลดภาระ DB | `middleware/cache-aside.js` |
| Queue-based processing | BullMQ สำหรับ video/thumbnail/notification | `services/*-queue.js` |

**สรุป:** พื้นฐานดีกว่าหลายโปรเจกต์ — มี Redis rate limiter พร้อมใช้แล้ว ปัญหาหลักคือ **ยังใช้ไม่ครบและยังไม่ครอบคลุมทรัพยากรอื่นนอกจากจำนวน request**

### จุดที่ต้องปิด — พร้อมหลักฐานจากโค้ดจริง

**1. Multer เขียนไฟล์ 500MB ลงดิสก์ก่อน แล้วค่อยปฏิเสธที่ 20MB** 🔴
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:42-45
const upload = multer({
    storage,
    limits: { fileSize: 500 * 1024 * 1024 } // 500MB limit
});
```
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:96-102
            // 1. File Size Validation (Enforced by Multer limits as well, but double check)
            const maxMB = 20;
            if (file.size > maxMB * 1024 * 1024) {
                return res.status(413).json({
                    error: `File too large. Max allowed: ${maxMB}MB`
                });
            }
```
ไฟล์ถูกเขียนลงดิสก์เต็ม 500MB ก่อน แล้วจึงตรวจว่าเกิน 20MB — **และไม่มีการลบไฟล์ทิ้งเมื่อปฏิเสธ** → disk เต็มได้ด้วยการอัปโหลดซ้ำ ๆ

**2. `limit` จาก query ไม่มีเพดาน** 🟡
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:489-491
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 20;
        const offset = (page - 1) * limit;
```
`?limit=1000000` ทำได้ — query หนัก + response ใหญ่ + cache memory บวม
รูปแบบเดียวกันที่ `/:id/gallery` (บรรทัด 592-593)

**3. Loop insert ไม่จำกัดจำนวน** 🟡
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:117-129
            if (gpsTracks) {
                try {
                    const tracks = JSON.parse(req.body.gpsTracks);
                    if (Array.isArray(tracks)) {
                        for (const track of tracks) {
                            await pool.query(
                                `INSERT INTO video_gps_tracks (video_id, latitude, longitude, timestamp_offset)
                                 VALUES ($1, $2, $3, $4)`,
                                [videoId, track.latitude, track.longitude, track.timestampOffset || 0]
                            );
```
GPS tracks 100,000 จุด = 100,000 query แยกกัน ถือครอง connection ยาว

**4. Cache key มี `limit`/`page` จาก user** 🟡
`video:emergency:list:${page}:${limit}`, `video:gallery:${id}:${page}:${limit}` — ผู้โจมตีสร้าง key ไม่ซ้ำได้ไม่จำกัด → Redis memory เต็ม (cache flooding)

**5. Endpoint สาธารณะไม่มี rate limit** 🟡
`GET /videos/`, `GET /videos/:id`, `GET /videos/:id/gallery`, `GET /videos/emergency/list`, `GET /videos/:id/interactions` — ไม่มี limiter

**6. Background job ไม่มี concurrency limit ต่อผู้ใช้** 🟡
`thumbnailQueue.addJob`, `videoService.addToQueue` — ผู้ใช้คนเดียวยึด worker ทั้งหมดได้

**7. `fs.readdirSync` แบบวนซ้ำใน request path** 🟡
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:249-268
                if (fs.existsSync(thaimhungBaseDir)) {
                    let allPhotos = [];
                    const videoDirs = fs.readdirSync(thaimhungBaseDir);
                    for (const vDir of videoDirs) {
```
Synchronous filesystem scan บล็อก event loop — ยิ่ง incident มีรูปมาก ยิ่งช้า

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| R1 | **Multer limit ไม่ตรงกับ business limit** | 🔴 สูง | เขียน 500MB ก่อนปฏิเสธที่ 20MB และไม่ลบไฟล์ทิ้ง |
| R2 | **`limit`/`page` ไม่มีเพดาน** | 🟡 กลาง | unbounded query |
| R3 | **Array/loop ไม่จำกัดขนาด** | 🟡 กลาง | GPS tracks, bulk operations |
| R4 | **Cache key จาก user input** | 🟡 กลาง | Redis memory exhaustion |
| R5 | **Read endpoint ไม่มี rate limit** | 🟡 กลาง | scraping, DB load |
| R6 | **ไม่มี per-user quota** | 🟡 กลาง | rate limit ตาม IP อย่างเดียว — NAT/มือถือใช้ IP ร่วมกัน |
| R7 | **ไม่มี account lockout** | 🔴 สูง | brute force รหัสผ่าน (ทับกับแผน 09 G5) |
| R8 | **ไม่มี OTP resend cooldown** | 🔴 สูง | OTP flooding = ค่าใช้จ่าย SMS + รบกวนผู้ใช้ |
| R9 | **ไม่มี disk quota / cleanup** | 🟡 กลาง | temp files สะสม |
| R10 | **ไม่มี query timeout** | 🟡 กลาง | slow query ถือครอง connection |
| R11 | **ไม่มี DB connection pool limit ที่ชัดเจน** | 🟡 กลาง | ต้องยืนยันค่า `max` ของ pool |
| R12 | **Socket.IO ไม่มี event rate limit** | 🟡 กลาง | client ยิง event ได้ไม่จำกัด |
| R13 | **Sync filesystem operation ใน request** | 🟡 กลาง | บล็อก event loop |
| R14 | **ไม่มี circuit breaker** | 🟢 ต่ำ | dependency ล่ม → cascade failure |
| R15 | **ไม่มี cost-based limiting** | 🟢 ต่ำ | query หนักกับเบาถูกนับเท่ากัน |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว

| ระบบ | ทรัพยากรที่เสี่ยงถูกใช้เกิน | สถานะ | สิ่งที่ต้องเพิ่ม |
|------|---------------------------|-------|-----------------|
| **Auth** | CPU (bcrypt), SMS (OTP), DB | มี `authRateLimiter` | account lockout, OTP cooldown, CAPTCHA หลัง N ครั้ง |
| **Video upload** | Disk, CPU (ffmpeg), Queue, Bandwidth | มี limiter | 🔴 แก้ R1, per-user quota, queue concurrency |
| **Photo upload** | Disk, CPU (face blur, watermark) | มี limiter | quota ต่อ incident |
| **Chat** | DB write, Socket events, Storage | ไม่มี | message rate limit, attachment quota |
| **Video call** | Bandwidth, TURN server | ไม่มี | concurrent call limit ต่อผู้ใช้ |
| **Consultation** | DB, Provider availability | ไม่มี | จำกัดจำนวนคำขอค้างต่อผู้ใช้ |
| **Emergency SOS** | ⚠️ **ห้ามจำกัดเข้มเกินไป** — เป็นฟีเจอร์ช่วยชีวิต | ไม่มี | จำกัดแบบผ่อนปรน + ตรวจจับ abuse แยก |
| **Donation** | DB, Payment gateway calls | มี strict | idempotency ✅, จำกัดจำนวนธุรกรรมต่อวัน |
| **Health sync** | DB write ปริมาณมาก | ไม่มี | batch size limit, sync interval |
| **Search** | DB CPU | ไม่มี | debounce + rate limit + min query length |
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

### ตัวเลือก A: Multi-Dimensional Rate Limiting (แนะนำ) ⭐

ขยาย limiter ที่มีอยู่ให้จำกัดหลายมิติพร้อมกัน

```js
// จำกัดตาม user เป็นหลัก, IP เป็นรอง
const limiterByUser = rateLimiter({
  maxRequests: 100, windowSec: 60,
  keyPrefix: 'rate:user',
  keyResolver: (req) => req.userId || req.ip,
});

// จำกัดทรัพยากรเฉพาะทาง
const uploadQuota = quotaLimiter({
  keyResolver: (req) => `quota:upload:${req.userId}`,
  limits: { perHour: 20, perDay: 100, bytesPerDay: 500 * 1024 * 1024 },
});

// OTP cooldown
const otpCooldown = cooldownLimiter({
  keyResolver: (req) => `otp:${req.body.phone}`,
  cooldownSec: 60, maxPerDay: 10,
});

// Account lockout
const loginProtection = lockoutLimiter({
  keyResolver: (req) => `login:${req.body.identifier}`,
  maxFailures: 5, lockoutSec: 900, progressiveBackoff: true,
});
```

**ข้อดี**
- ปิด R5, R6, R7, R8 พร้อมกัน
- ต่อยอดจาก Redis limiter ที่มีอยู่ — ไม่ต้องเริ่มใหม่
- จำกัดตาม user แม่นยำกว่า IP (สำคัญมากสำหรับมือถือที่ใช้ NAT)

**ข้อเสีย**
- ต้องออกแบบ limit ให้เหมาะกับแต่ละ endpoint (ต้องมีข้อมูล traffic จริง)
- Redis เป็น dependency ที่ critical มากขึ้น

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Input Bounds Enforcement (แก้ R1–R4)

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

**ข้อดี:** ปิด R1–R4; ต้นทุนต่ำมาก; ปรับปรุง performance ไปด้วย (bulk insert)
**ข้อเสีย:** ต้องไล่แก้ทุก endpoint ที่รับ pagination/array
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **แนะนำทำก่อนเป็นอันดับแรก**

---

### ตัวเลือก C: Resource Governance ระดับโครงสร้าง

```js
// DB
const pool = new Pool({
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
  statement_timeout: 10000,          // ยกเลิก query ที่นานเกิน
});

// Queue concurrency ต่อผู้ใช้
const worker = new Worker(QUEUE_NAME, handler, {
  concurrency: 4,
  limiter: { max: 10, duration: 1000 },
});
// + ตรวจจำนวน job ค้างต่อ userId ก่อน addJob

// Socket.IO
io.use(socketRateLimiter({ maxEventsPerSec: 20 }));
const io = new Server(server, { maxHttpBufferSize: 1e6 });

// Disk cleanup job
cron.schedule('0 3 * * *', () => cleanupTempFiles({ olderThanHours: 24 }));
```

**ข้อดี:** ปิด R9–R13; ป้องกันปัญหาที่ rate limit อย่างเดียวแก้ไม่ได้; ระบบเสถียรขึ้นโดยรวม
**ข้อเสีย:** ต้องปรับค่าตาม capacity จริง (ต้องมี load test); ตั้งต่ำเกินไปกระทบผู้ใช้ปกติ
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก D: Edge Rate Limiting (Reverse Proxy / CDN)

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

**ข้อดี:** บล็อกก่อนถึง app server (ประหยัดทรัพยากรที่สุด); ป้องกัน DDoS ระดับเครือข่าย; ไม่ต้องแก้โค้ด
**ข้อเสีย:** ไม่รู้จัก userId (จำกัดได้แค่ IP); ต้องซิงค์ policy กับ application layer; ต้นทุนถ้าใช้ CDN เชิงพาณิชย์
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

**ข้อดี:** ยุติธรรมกว่า; รองรับ subscription tier ได้ตรง (`ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md`)
**ข้อเสีย:** ซับซ้อน; ต้องวัด cost จริงของแต่ละ endpoint; อธิบายให้ผู้ใช้เข้าใจยาก
**ความเหมาะสมระยะยาว:** ⭐⭐⭐ — พิจารณาเมื่อระบบโตและมี tier แล้ว

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **B ทันที (1 สัปดาห์) → A → C → D ตอนวาง proxy** | B ต้นทุนต่ำที่สุดและปิดช่องว่างร้ายแรง (R1); A/C ใช้โครงสร้างที่มีอยู่แล้ว |
| 2 | **B + A + D** | ถ้ายังไม่พร้อมปรับ infrastructure |
| 3 | **B + C** | ถ้าเน้นความเสถียรมากกว่าการป้องกัน abuse |
| 4 | **E** | ยังเร็วเกินไป — ทำเมื่อมี subscription tier แล้ว |

---

## 5. Rate Limit Policy ที่เสนอ

| ประเภท Endpoint | Limit | Key | หมายเหตุ |
|----------------|-------|-----|----------|
| Login | 5 ครั้ง/15 นาที + lockout | username (ไม่ใช่ IP) | progressive backoff |
| OTP request | 1 ครั้ง/60 วินาที, 10/วัน | เบอร์โทร | มีค่าใช้จ่ายจริง |
| Register | 3 ครั้ง/ชม. | IP + device | |
| Password reset | 3 ครั้ง/ชม. | account | |
| Read (public) | 120 ครั้ง/นาที | user หรือ IP | |
| Read (authenticated) | 300 ครั้ง/นาที | user | |
| Write ทั่วไป | 60 ครั้ง/นาที | user | |
| Upload video | 10/ชม., 30/วัน, 500MB/วัน | user | |
| Upload photo | 30/ชม. | user | |
| Chat message | 30/นาที | user | |
| Search | 30/นาที | user | + min 2 ตัวอักษร |
| **Emergency SOS** | **20/ชม.** | user | ⚠️ ผ่อนปรน + alert แทนการบล็อก |
| Donation/Payment | 20/ชม. | user | + idempotency |
| Admin write | 60/นาที | user | |
| ERP report/export | 10/ชม. | user | หนัก — ควรเป็น async job |
| Payroll run | 5/วัน | organization | |
| Socket.IO event | 20/วินาที | connection | |

### เพดานค่าอื่น ๆ
| พารามิเตอร์ | ค่าที่แนะนำ |
|------------|------------|
| `limit` (pagination) | สูงสุด 100 |
| `page` | สูงสุด 1000 (ใช้ cursor pagination สำหรับข้อมูลลึก) |
| Request body (JSON) | 100KB (default), 1MB (endpoint เฉพาะ) |
| Video file | 20MB (ตาม business rule ปัจจุบัน) |
| Image file | 10MB |
| เอกสาร | 5MB |
| GPS tracks ต่อ request | 5,000 จุด |
| Bulk operation | 500 รายการ |
| Query timeout | 10 วินาที (30 วินาทีสำหรับ report) |
| Concurrent upload ต่อผู้ใช้ | 3 |
| Queue job ค้างต่อผู้ใช้ | 10 |
| DB pool max | 20 (ปรับตาม capacity) |

---

## 6. ประเด็นพิเศษ: Emergency Features

⚠️ **Sheserved มีฟีเจอร์ช่วยชีวิต (SOS, emergency video) — การจำกัดที่เข้มเกินไปอาจเป็นอันตราย**

หลักการที่เสนอ:
```
1. Emergency endpoint ต้องมี limit ที่ผ่อนปรนกว่าปกติมาก
2. เมื่อเกิน limit → ไม่บล็อกทันที แต่ degrade (ลดคุณภาพวิดีโอ, ลดความถี่ GPS)
3. แจ้งเตือน admin เมื่อพบพฤติกรรมผิดปกติ แทนการปฏิเสธอัตโนมัติ
4. มี allowlist สำหรับบัญชีที่ผ่านการยืนยัน (verified responder)
5. บันทึกทุกครั้งที่ถูก throttle เพื่อ review ภายหลัง
```

---

## 7. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/infrastructure/caching_strategy.md` | ⚠️ **สำคัญ** — cache key จาก user input (R4) ต้องแก้ในเอกสารนั้น; Redis memory policy ต้องระบุ |
| `docs/infrastructure/reverse_proxy_plan.md` | ตัวเลือก D ควรระบุใน plan นั้น |
| `docs/infrastructure/SETUP_DATABASE_SERVER.md` | ต้องระบุ connection pool + statement_timeout |
| `docs/secure/09_authentication_authorization.md` | R7 (lockout) = G5 ในแผน 09 — **implement ครั้งเดียว** |
| `docs/secure/11_input_validation.md` | R2, R3 คือ validation แบบหนึ่ง — ใช้ schema เดียวกันได้ |
| `docs/secure/02_path_traversal_command_injection.md` | R9 (disk quota) = PT10 |
| `docs/secure/05_logging_audit_monitoring.md` | ต้อง log ทุกครั้งที่ rate limit ทำงาน เพื่อแยก abuse จาก bug |
| `docs/ERP/ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | Quota ตาม tier เป็น business feature ที่ใช้กลไกเดียวกัน |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | Worker pool + priority queue ควรอยู่ในแผนนั้น |

---

## 8. งานที่ต้องตรวจสอบทันทีเมื่ออนุมัติ

- [ ] ตรวจว่าไฟล์ที่ถูกปฏิเสธ (เกิน 20MB) ถูกลบออกจากดิสก์หรือไม่
- [ ] ตรวจขนาดปัจจุบันของ `temp/videos/` และ `uploads/`
- [ ] ตรวจค่า `max` ของ PostgreSQL connection pool
- [ ] ตรวจ Redis `maxmemory` และ `maxmemory-policy`
- [ ] วัด traffic จริงเพื่อกำหนด limit ที่เหมาะสม (ไม่ควรเดา)
- [ ] ตรวจว่ามี endpoint ไหนที่ยังไม่มี rate limiter บ้าง

---

## 9. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติการแก้ Multer limit ให้ตรงกับ business rule + cleanup (R1) — แนะนำ: ใช่ ทำทันที
- [ ] อนุมัติ pagination clamp และเพดานค่าต่าง ๆ (section 5)
- [ ] อนุมัติ rate limit policy ต่อ endpoint (ตาราง section 5)
- [ ] ตัดสินใจเรื่อง key strategy: IP / user / ทั้งคู่
- [ ] อนุมัตินโยบายพิเศษสำหรับ emergency features (section 6)
- [ ] ตัดสินใจเรื่อง edge rate limiting ที่ reverse proxy (D)
- [ ] กำหนดพฤติกรรมเมื่อเกิน limit: 429 + Retry-After / degrade / queue
- [ ] ตัดสินใจว่าจะเพิ่ม CAPTCHA หลัง login ล้มเหลว N ครั้งหรือไม่
