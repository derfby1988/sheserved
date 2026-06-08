# ⚡ แผนยุทธศาสตร์การทำ Caching (Caching Strategy) สำหรับ Sheserved
## ขอบเขต: ครอบคลุมทุกระบบย่อย (Auth · Directory & Menu · Cart & Ordering · Booking · Escrow & Donation · Video · Sync) เพื่อการเติบโตที่ไร้รอยต่อ

เอกสารนี้วิเคราะห์ Caching Patterns จากสถาปัตยกรรมอ้างอิง และนำเสนอแนวทางการประยุกต์ใช้กับ **Sheserved** เพื่อรองรับการขยายตัวในอนาคต โดยมุ่งเน้นแนวทาง **ไม่มีค่าใช้จ่ายเพิ่มเติม (Zero-Cost)** ในช่วงพัฒนาและ Deploy เริ่มต้น

> [!NOTE]
> เอกสารนี้เป็น **operational companion** ของ [`architecture_analysis.md`](architecture_analysis.md) — เน้นรายละเอียด caching patterns, TTL, key schema และ queue-cache coordination ที่ใช้งานได้จริง ส่วน master plan, queue strategy และลำดับการ implement ดูที่ **architecture_analysis.md: Phase 2** (ข้อเสนอแนะที่ดีที่สุด)
>
> แผนงานนี้ครอบคลุมทุกระบบย่อยหลักทั้งหมดในแพลตฟอร์ม Sheserved เพื่อให้แน่ใจว่าระบบทั้งหมดทำงานผสานกันอย่างไร้รอยต่อโดยใช้ฐานข้อมูล Redis เดียวกันโดยไม่มีค่าใช้จ่ายเพิ่ม

---

## 1. ตารางเปรียบเทียบและการประยุกต์ใช้ Patterns กับ Sheserved

| หมวดหมู่ (ตามภาพ) | Pattern ที่เลือกใช้ | สถานะช่วงเริ่มต้น (Free) | การขยายตัวในอนาคต (Scale-up) |
|---|---|---|---|
| **1. Read Patterns** | **1.1 Cache-Aside (Lazy Loading)** | 🟢 **ใช้ทันที**: เช็ค Redis ก่อนเสมอ ถ้า Miss ค่อยดึงจาก PostgreSQL และเขียนลง Redis | **1.2 Read-Through**: ใช้เมื่อเปลี่ยนไปใช้ ORM/Data Mapper ที่มีระบบ Caching ในตัว |
| **2. Write Patterns** | **2.3 Write-Around** + **4.1 Cache Invalidation** | 🟢 **ใช้ทันที**: เขียนเข้า PostgreSQL ตรงๆ และใช้คำสั่งลบ Key ใน Redis (Invalidation) เมื่อข้อมูลอัปเดต | **2.2 Write-Behind**: สำหรับเก็บ Log/Analytics ทราฟฟิกสูงๆ ก่อนเขียนลง DB ทีหลังเพื่อลดโหลด |
| **3. Expiration Patterns** | **3.1 TTL (Time-To-Live)** + **3.2 Sliding Expiration** | 🟢 **ใช้ทันที**: <br>- **TTL**: สำหรับข้อมูลเมนูอาหาร/โปรโมชัน (เช่น 5-15 นาที)<br>- **Sliding**: สำหรับ Auth Session/WebSocket Token | ปรับเปลี่ยนระยะเวลา TTL ตามพฤติกรรมการใช้งานจริงของระบบ |
| **4. Consistency Patterns** | **4.1 Cache Invalidation (Delete on update)** | 🟢 **ใช้ทันที**: ลบ Cache ทันทีที่มีการแก้ไขเมนู/โปรไฟล์/การจอง | **4.2 Event-Driven Invalidation**: ใช้ BullMQ/Kafka ส่ง Event เพื่อลบ Cache ในแต่ละ Service |
| **5. Distributed Cache** | **5.1 Distributed Cache (Single Node)** | 🟢 **ใช้ทันที**: รัน Redis Localhost ตัวเดียวร่วมกับ Node.js server | **5.1 Redis Cluster / Replica**: แยก Node เมื่อต้องทำ Multi-instance auto scaling |
## 2. เจาะลึกการออกแบบระบบสำหรับ Sheserved (ช่วงเริ่มต้น - ไม่มีค่าใช้จ่าย 🟢)

ในช่วงแรก เราจะพึ่งพา **Redis Local Instance** ที่มีอยู่แล้วในระบบ และ **Node.js (Express/Socket.io)** โดยใช้ Library พื้นฐานที่ไม่เสียค่าใช้จ่าย โดยจัดลำดับการดำเนินงานตามเฟสที่สอดคล้องกับ [แผนโครงสร้างพื้นฐานหลัก](file:///Users/dave_macmini/sheserved/docs/infrastructure/architecture_analysis.md) และไม่ขัดแย้งกับแผนพัฒนาระบบย่อยอื่น ๆ ดังนี้:

---

### ✅ Phase 1 — Redis Middleware (Implemented)
> สถานะ: **เสร็จสิ้นแล้ว** — middleware (`rate-limiter`, `idempotency`, `cache-aside`, `redis-client`) ถูก implement ใน `websocket-server/middleware/` และ wire เข้า `server.js` แล้ว

เน้นการจัดการความปลอดภัย ทราฟฟิก และ Cache สำหรับอ่าน-เขียนข้อมูลทั่วไป ผ่าน Caddy Reverse Proxy (`:8080`)

#### 2.1 Read Pattern: Cache-Aside (Lazy Loading) + Query Result & Object Cache
*   **แนวทางปฏิบัติ:** ตรวจสอบคีย์ใน Redis ก่อนเสมอ หากไม่มีค่อยดึงจาก PostgreSQL และเขียนลง Redis พร้อม TTL
*   **ความเชื่อมโยงกับแผนย่อยอื่น:**
    *   **[SHOPPING_CART_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/SHOPPING_CART_PLAN.md):** เก็บข้อมูลตะกร้าสินค้าชั่วคราว (`cart:user:${userId}`) ด้วยเทคนิค Object Cache บน Redis เพื่อเลี่ยงการเขียนลง DB ทุกครั้งที่ผู้ใช้กดยืนยันหรือเพิ่มสินค้า
    *   **[DONATION_SYSTEM_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/DONATION_SYSTEM_PLAN.md):** แคชยอดเงินบริจาครวมของแต่ละแคมเปญ (`donation:total:${campaignId}`) แบบมี TTL สั้น (1-2 นาที) สำหรับแสดงบน Dashboard/หน้าแรกแบบ Real-time โดยไม่ดึง DB ถี่เกินไป

```javascript
// ตัวอย่างโค้ดจริงใน websocket-server/middleware/cache-aside.js
const { cacheAside, TTL } = require('./middleware');

// ใช้ Cache-Aside กับ Menu
const menu = await cacheAside(
  `menu:restaurant:${restaurantId}`,
  () => db.query('SELECT * FROM menus WHERE restaurant_id = $1', [restaurantId]),
  TTL.MENU  // 600 วินาที
);
```

#### 2.2 Write Pattern: Write-Around + Cache Invalidation (ลบเมื่อเปลี่ยน)
*   **แนวทางปฏิบัติ:** เขียนลง PostgreSQL ตรงๆ และตามไปลบ Cache ที่เกี่ยวข้องทันที เพื่อบังคับการอ่านรอบถัดไปให้ดึงค่าล่าสุด
*   **ความเชื่อมโยงกับแผนย่อยอื่น:**
    *   **[ERP_CORE_ARCHITECTURE.md](file:///Users/dave_macmini/sheserved/docs/ERP/ERP_CORE_ARCHITECTURE.md):** การอัปเดตราคาหรือสต็อกสินค้าในฝั่ง POS/Inventory จะกระทำตรงเข้า PostgreSQL และสั่งลบคีย์แคชหน้าเมนู เพื่อคงความแม่นยำ 100%

```javascript
async function updateMenuItem(itemId, restaurantId, newData) {
  // 1. อัปเดต PostgreSQL
  await db.query('UPDATE menus SET price = $1 WHERE id = $2', [newData.price, itemId]);
  
  // 2. Invalidate Cache (ลบ Cache เมนูของร้านนี้ทิ้งทันที)
  const cacheKey = `menu:restaurant:${restaurantId}`;
  await redis.del(cacheKey);
}
```

#### 2.3 Expiration Pattern: ผสมผสาน TTL และ Sliding Expiration
*   **แนวทางปฏิบัติ:** ใช้ TTL ธรรมดาสำหรับข้อมูลที่เปลี่ยนแปลงได้ ส่วน Sliding Expiration ใช้สำหรับการอัปเดตอายุกิจกรรมเซสชัน
*   **ความเชื่อมโยงกับแผนย่อยอื่น:**
    *   **[CHAT_CONSULTATION_IMPROVEMENT_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md):** การจัดเก็บสถานะสิทธิ์การเข้าใช้ห้องแชทและ Token ในช่วงเวลาตอบคำถามที่แพทย์และคนไข้อยู่ในเซสชัน (`auth:session:${sessionId}`) ใช้ Sliding Expiration เพื่อให้เซสชันมีอายุยาวตราบเท่าที่มีความเคลื่อนไหว

```javascript
// ตัวอย่างการต่ออายุ Session (Sliding Expiration) เมื่อมีการเรียกใช้งาน
async function verifySession(sessionId) {
  const sessionData = await redis.get(`session:${sessionId}`);
  if (!sessionData) return null;
  
  // รีเซ็ตเวลาหมดอายุเป็น 2 ชั่วโมง (7200 วินาที) ทุกครั้งที่มีการใช้งาน
  await redis.expire(`session:${sessionId}`, 7200);
  return JSON.parse(sessionData);
}
```

#### 2.4 Advanced Pattern: Cache Stampede Protection (ป้องกันระบบล่มตอนคนรุม)
*   **แนวทางปฏิบัติ:** ใช้ Redis Mutex Lock (`SETNX`) กั้นไม่ให้ Requests หลายพันรายการเจาะเข้า Database พร้อมกันเมื่อ Cache Miss
*   **ความเชื่อมโยงกับแผนย่อยอื่น:**
    *   **[DONATION_SYSTEM_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/DONATION_SYSTEM_PLAN.md):** ใช้ป้องกันคอขวดเมื่อมีแคมเปญบริจาคด่วนฉุกเฉิน (Emergency Donation) ที่ได้รับความนิยมสูง เพื่อไม่ให้ Query หน้ารายการบริจาคเข้า DB ตรงๆ

```javascript
async function getHotPromotion() {
  const cacheKey = "promo:hot";
  const lockKey = "lock:promo:hot";
  
  let data = await redis.get(cacheKey);
  if (data) return JSON.parse(data);
  
  // ถ้า Cache Miss: พยายามดึงสิทธิ์เพื่อเข้าเขียน DB (Lock 5 วินาที)
  const acquiredLock = await redis.set(lockKey, "1", "NX", "EX", 5);
  
  if (acquiredLock) {
    // ได้รับสิทธิ์เข้าไปดึง DB
    const freshData = await db.query('SELECT * FROM promotions WHERE is_hot = true');
    await redis.set(cacheKey, JSON.stringify(freshData), 'EX', 300); // แคช 5 นาที
    await redis.del(lockKey); // ปลดล็อก
    return freshData;
  } else {
    // ไม่ได้ล็อก: รอสักครู่แล้วเช็ค Cache อีกรอบ หรือส่งข้อมูลเดิมกลับไปก่อน
    await new Promise(resolve => setTimeout(resolve, 100));
    return getHotPromotion();
  }
}
```

---

### ✅ Phase 2 — BullMQ Queue System + Event-Driven Caching (Documented, รอ implement)

> สถานะ: **Document complete** — เอกสาร + code examples + checklist ครบ รอ implement queue files จริงใน `websocket-server/queues/`

เน้นการประมวลผลคำขอแบบอะซิงโครนัส (Async Processing) ผ่าน Redis Queue และประสานกับ **Cache Invalidation / Warming** แบบ Event-Driven เพื่อลดภาระโหลดและรับประกันความสอดคล้องของข้อมูลระหว่าง Cache กับ Database

#### 2.5 Cache-Queue Coordination Patterns

เมื่อใช้ BullMQ ร่วมกับ Redis Cache ต้องจัดการความสอดคล้องระหว่าง Worker กับ Cache ให้ถูกต้อง:

| Pattern | ใช้เมื่อไหร่ | ตัวอย่างใน Sheserved |
|---------|-------------|----------------------|
| **Invalidate-on-Complete** | Worker ประมวลผลเสร็จ → ลบ Cache ที่เกี่ยวข้อง | Booking worker เสร็จ → `del booking:slots:*` |
| **Warm-on-Complete** | Worker เสร็จ → คำนวณผลลัพธ์ใหม่แล้วเขียน Cache ทันที | Donation total คำนวณใหม่ → `set donation:total:${id}` |
| **Invalidate-on-Start** | Worker เริ่มทำงาน → ลบ Cache เพื่อป้องกัน stale read ระหว่างประมวลผล | Order worker เริ่ม → `del order:status:${id}` |
| **Event Broadcast** | Worker ส่ง Event ผ่าน BullMQ → ให้ทุก node ลบ local cache พร้อมกัน | Menu ถูกแก้ไข → broadcast `invalidate:menu:${id}` |

#### 2.6 Event-Driven Cache Invalidation ด้วย BullMQ

แทนการลบ Cache ตรงๆ ใน endpoint ให้ส่ง invalidation event เข้า queue แล้วให้ worker จัดการ:

```javascript
// websocket-server/queues/notification-queue.js
const { invalidateCacheMany } = require('../middleware/cache-aside');

const cacheInvalidationWorker = new Worker('notification', async (job) => {
  if (job.name === 'invalidate-cache') {
    const { keys, pattern } = job.data;

    if (keys) {
      await invalidateCacheMany(keys);
      console.log(`[CacheInvalidation] Cleared keys: ${keys.join(', ')}`);
    }

    if (pattern) {
      // ใช้ Redis SCAN ลบ key ตาม pattern (e.g. "menu:restaurant:42:*")
      const stream = redis.scanStream({ match: pattern, count: 100 });
      const keysToDelete = [];
      stream.on('data', (keys) => keysToDelete.push(...keys));
      await new Promise((resolve, reject) => {
        stream.on('end', resolve);
        stream.on('error', reject);
      });
      if (keysToDelete.length) await redis.del(...keysToDelete);
    }
  }

  // ... notification logic
}, { connection });

// ── ใช้ใน API Endpoint ───────────────────────────────────
async function updateMenuItem(req, res) {
  const { itemId, restaurantId } = req.body;

  // 1. Write ลง DB ตรงๆ
  await db.query('UPDATE menus SET ... WHERE id = $1', [itemId]);

  // 2. Enqueue invalidation event (ไม่ block response)
  await notificationQueue.add('invalidate-cache', {
    pattern: `menu:restaurant:${restaurantId}*`,
    source: 'menu-update',
    timestamp: Date.now(),
  });

  res.json({ success: true });
}
```

**ข้อดีของ Event-Driven Invalidation:**
- API response เร็วขึ้น (ไม่ต้องรอ SCAN + DEL บน Redis)
- ถ้า invalidate ล้มเหลว → BullMQ retry ได้อัตโนมัติ
- รองรับ **multi-instance** ในอนาคต (หลาย Node.js process ได้รับ invalidation event พร้อมกัน)

#### 2.7 Cache Warming จาก Worker

Worker สามารถเติม Cache ล่วงหน้า (warm cache) หลังจากประมวลผลเสร็จ:

```javascript
// websocket-server/queues/order-queue.js
const { cacheAside } = require('../middleware/cache-aside');

const orderWorker = new Worker('order', async (job) => {
  const { userId, orderId } = job.data;

  // 1. ประมวลผล order → DB
  await pool.query('UPDATE orders SET status = $1 WHERE id = $2', ['confirmed', orderId]);

  // 2. Warm cache — เติมสถานะ order ใหม่ลง Redis ทันที
  const freshOrder = await pool.query('SELECT * FROM orders WHERE id = $1', [orderId]);
  await redis.setex(
    `order:status:${orderId}`,
    TTL.ORDER_STATUS,
    JSON.stringify(freshOrder.rows[0])
  );

  // 3. ลบ cart cache (เพราะสั่งเสร็จแล้ว)
  await redis.del(`cart:user:${userId}`);

  // 4. Warm booking slots ถ้าเป็น order ที่เกี่ยวข้องกับการจอง
  await cacheAside(
    `booking:slots:${freshOrder.rows[0].restaurant_id}:${today}`,
    () => pool.query('SELECT * FROM booking_slots WHERE ...'),
    TTL.BOOKING_SLOT
  );
}, { connection });
```

#### 2.8 TTL Configuration สำหรับ Queue + Cache

```javascript
// websocket-server/middleware/cache-aside.js (ขยายเพิ่มจาก Phase 1)
const TTL = {
  // Phase 1 — Existing
  MENU: 600,           // 10 นาที
  RESTAURANT: 900,     // 15 นาที
  SESSION: 7200,       // 2 ชั่วโมง (Sliding)

  // Phase 2 — Queue-related
  ORDER_STATUS: 300,   // 5 นาที (อัปเดตบ่อย)
  BOOKING_SLOT: 60,    // 1 นาที (real-time critical)
  DONATION_TOTAL: 120, // 2 นาที (dashboard)
  VIDEO_META: 3600,    // 1 ชั่วโมง (เปลี่ยนน้อย)
  DELIVERY_STATUS: 30, // 30 วินาที (tracking)
  NOTIFICATION_LOG: 86400, // 24 ชั่วโมง
};
```

#### 2.9 Redis Key Schema สำหรับ Phase 2

```
# Queue metadata (BullMQ internal — อย่าแก้ไขตรง)
bull:booking:id
bull:booking:wait
bull:booking:active
bull:booking:completed
bull:booking:failed

# Cache keys — Queue-processed data
order:status:${orderId}
booking:slots:${restaurantId}:${date}
booking:confirmation:${jobId}
donation:total:${campaignId}
donation:leaderboard:${campaignId}
video:meta:${videoId}
video:thumbnail:${videoId}
delivery:status:${orderId}
sync:checkpoint:user:${userId}

# Locks — Distributed mutex สำหรับ queue-sensitive operations
lock:slot:${restaurantId}:${date}:${time}
lock:order:pos-inject:${orderId}
lock:sync:user:${userId}
lock:donation:consensus:${requestId}
```

#### 2.10 รายละเอียดการประยุกต์ใช้รายระบบย่อย (Sheserved Subsystems)

ตารางด้านล่างแสดงการจัดการ Caching และ Queue สำหรับแต่ละระบบย่อย โดยสอดคล้องและได้รับการตรวจสอบแล้วว่าไม่ขัดแย้งกับแผนงานหลัก:

| ระบบย่อย (Subsystem) | วิธีการจัดการ Caching / Queue | ตัวอย่างการตั้งชื่อคีย์ (Redis Key Schema) | ความเชื่อมโยงและจุดประสานตามแผนหลัก |
|---|---|---|---|
| **1. ระบบสมาชิกและเซสชัน (Auth & Session)** | - Sliding Expiration (3.2)<br>- Invalidation (4.1) เมื่อ logout | `auth:session:${sessionId}`<br>`auth:token:${userId}` | สอดคล้องกับ **[CHAT_CONSULTATION_IMPROVEMENT_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md)**: ใช้จัดการสิทธิ์เข้าใช้งานห้องสนทนาของแพทย์และคนไข้โดยไม่ละเมิดสิทธิ์ RLS (เนื่องจากระบบใช้ Custom Auth ของตนเอง) |
| **2. ระบบข้อมูลร้านและเมนู (Directory & Menu)** | - Cache-Aside (1.1)<br>- Object Cache (7.3)<br>- Write-Around (2.3) เมื่อแก้ไข<br>- **Event-Driven Invalidation** ผ่าน notification-queue | `menu:restaurant:${restaurantId}`<br>`restaurant:profile:${restaurantId}` | สอดคล้องกับ **[ERP_CORE_ARCHITECTURE.md](file:///Users/dave_macmini/sheserved/docs/ERP/ERP_CORE_ARCHITECTURE.md)**: จัดเตรียมเมนูและข้อมูลหน้าร้านให้อ่านเร็วที่สุดสำหรับ POS |
| **3. ระบบสั่งอาหารและตะกร้า (Ordering & Cart)** | - Cache-Aside (1.1) สำหรับอ่านเมนู<br>- Object Cache (7.3) สำหรับตะกร้าสินค้า<br>- BullMQ Queue (Phase 2) สำหรับออร์เดอร์<br>- **Warm-on-Complete** หลัง POS Injection | `cart:user:${userId}`<br>`order:status:${orderId}` | สอดคล้องกับ **[SHOPPING_CART_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/SHOPPING_CART_PLAN.md)**: ตะกร้าพักไว้ใน Redis แล้วจึงยิง API (POS Injection) ข้ามไปสร้างบิลใน **POS System** ของคลินิกผ่าน `order-queue` |
| **4. ระบบจองโต๊ะและคิว (Booking & Reservation)** | - Cache-Aside (1.1) สำหรับดูตารางเวลา<br>- Mutex Lock (`SETNX`) กันจองซ้ำ<br>- BullMQ Queue (Phase 2) สำหรับส่งงาน<br>- **Invalidate-on-Complete** slot cache | `booking:slots:${restaurantId}:${date}`<br>`lock:slot:${restaurantId}:${date}:${time}` | สอดคล้องกับ **[CHAT_CONSULTATION_IMPROVEMENT_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md)**: ใช้ `SETNX` ล็อกจังหวะเริ่ม Session การนัดหมายแพทย์ ป้องกันไม่ให้ชนกับคิวอื่นของแพทย์ |
| **5. ระบบบริจาคและเงินประกัน (Donation & Escrow)** | - Write-Around (2.3) ตรงเข้า DB<br>- Cache-Aside (1.1) สำหรับดูยอดรวมโชว์หน้าแรก<br>- **Warm-on-Complete** หลัง escrow release | `donation:total:${campaignId}`<br>`escrow:status:${escrowId}` | สอดคล้องกับ **[DONATION_SYSTEM_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/DONATION_SYSTEM_PLAN.md)**: ใช้การบันทึกระดับ DB ในการลงทะเบียนบริจาค/โหวตอนุมัติเพื่อป้องกัน Race Condition โดยระบบ Caching จะกรองข้อมูลแบบ Read-only เท่านั้น |
| **6. ระบบประมวลผลวิดีโอ (Video Processing)** | - Cloudflare Free CDN (8.1) แคชรูปภาพ/วิดีโอ<br>- BullMQ Queue (Phase 2) สำหรับรันงานหลังบ้าน<br>- **Warm-on-Complete** thumbnail URL + meta | `video:meta:${videoId}`<br>`job:thumbnail:${videoId}` | สอดคล้องกับ **[VIDEO_SYSTEM_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/VIDEO_SYSTEM_PLAN.md)**: ใช้ BullMQ จัดการลำดับคิวการประมวลผล (Priority Queue) โดย Emergency alerts จะถูกขยับขึ้นมาประมวลผลก่อน |
| **7. ระบบจัดส่งและติดตามพิกัด (Delivery & Logistics)** | - GPS cache ชั่วคราวบน Client<br>- BullMQ Queue (Phase 2) อัปเดตพัสดุ<br>- **Warm-on-Complete** delivery status | `delivery:status:${orderId}` | สอดคล้องกับ **[Delivery_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/Delivery_PLAN.md)**: เก็บพิกัดและ tracking ไว้ที่ฝั่ง Mobile SDK เป็นหลัก (เพื่อควบคุมงบ Google Maps API) และซิงค์สถานะจัดส่งผ่าน queue |
| **8. ระบบซิงค์ข้อมูล (Local-Cloud Sync)** | - Distributed Lock (`SETNX`) ป้องกันการซิงค์ซ้อน<br>- BullMQ Queue (Phase 2) สำหรับ reconcile<br>- **Invalidate-on-Complete** sync checkpoint | `sync:lock:user:${userId}`<br>`sync:checkpoint:user:${userId}` | สอดคล้องกับ **[ERP_CORE_ARCHITECTURE.md](file:///Users/dave_macmini/sheserved/docs/ERP/ERP_CORE_ARCHITECTURE.md)**: ควบคุมการ Sync คิวสำหรับ Local Database ↔ Supabase Cloud ของคลินิกไม่ให้เกิดการเรียกชนกัน |

---

## 3. แผนการขยายตัวในอนาคตเพื่อรองรับการเติบโต (Scalability)

เมื่อระบบมีผู้ใช้งานเพิ่มขึ้นอย่างมหาศาล และงบประมาณเริ่มขยายตัว เราสามารถยกระดับจากจุดเริ่มต้นได้ดังนี้:

### 3.1 CDN & Edge Caching (สอดคล้องกับหัวข้อ 8 ของภาพ)
*   **Cloudflare Free Tier / Pro:** 
    *   ใช้สำหรับแคช Static Assets เช่น รูปภาพร้านค้า, รูปเมนูอาหาร ที่เก็บใน Bunny.net หรือ Supabase Storage
    *   ตั้งค่า **Edge Cache HTML/JSON APIs** ที่เป็นสาธารณะ (ไม่เจาะจงรายคน) ไว้บนเซิร์ฟเวอร์กระจายทั่วโลกของ Cloudflare ช่วยลดโหลดที่จะวิ่งมาถึงเซิร์ฟเวอร์หลัก (Mac Mini หรือ Cloud VPS) ลงได้ถึง 70-80%

### 3.2 Multi-Level Cache (สอดคล้องกับหัวข้อ 6.1 ของภาพ)
เมื่อโหลดเพิ่มขึ้น เราจะไม่ยิงหา Redis ทุกรอบ แต่จะวางระบบเก็บข้อมูลซ้อนกันหลายชั้น:
```
[📱 Flutter App Memory] 
     ↓ (ถ้าไม่มี)
[🌐 Cloudflare CDN Edge Cache] 
     ↓ (ถ้าไม่มี)
[🔌 Node.js Memory Cache (In-Memory / Near Cache)] 
     ↓ (ถ้าไม่มี)
[🔴 Redis Distributed Cache (Shared Cluster)] 
     ↓ (ถ้าไม่มี)
[🐘 PostgreSQL (Read Replica)]
```

### 3.3 Event-Driven Invalidation (สอดคล้องกับหัวข้อ 4.2 ของภาพ)
*   เมื่อย้ายระบบไปเป็น Microservices หรือทำ Backend Cluster
*   การประสานงานจะใช้ **BullMQ (หรือ Apache Kafka)**: เมื่อเกิดการแก้ไขข้อมูลที่ Service A -> ส่ง Event แจ้งเตือนไปยังทุก Node -> ทุก Node ลบ Cache ท้องถิ่นของตัวเองทันที รับประกันว่าข้อมูลจะสอดคล้องกันตลอดเวลา (Consistency)

---

## 4. ข้อแนะนำสำหรับทีมพัฒนาในการเริ่มต้นใช้กับ Sheserved

1.  **เริ่มจากจุดที่ง่ายและเห็นผลที่สุดก่อน:** ทำ **Cache-Aside** กับหน้าแสดงรายการร้านอาหารและหน้าเมนู เนื่องจากเป็นหน้าที่มีคนเรียกดูซ้ำมากที่สุด (Read-Heavy)
2.  **จัดการการจองและสั่งซื้อด้วย Queue:** สำหรับการบันทึกข้อมูลสำคัญ (Write-Heavy) เช่น การทำจอง (Booking) หรือ สั่งอาหาร (Order) ให้ใช้ระบบ Queue (BullMQ) ใน Phase 2 เพื่อทำ **Async Processing** แทนการทำ Write-Behind แคชตรงๆ เพื่อป้องกันปัญหาเรื่องความสอดคล้องของสถานะเงินและสต็อกสินค้า
3.  **ติดตามประสิทธิภาพ (Monitoring):** เก็บสถิติ Cache Hit / Miss Ratio เพื่อนำมาปรับปรุงระยะเวลา TTL ให้เหมาะสม

---

## 5. แผนการทดสอบในแต่ละเฟส (Testing & Verification Checklist)

เพื่อตรวจสอบว่าระบบ Caching และ Queue ที่วางโครงสร้างไว้ใน Phase 1 และ Phase 2 ทำงานได้อย่างถูกต้องและปลอดภัย ให้ทำตามรายการตรวจสอบการทดสอบดังนี้:

### ✅ รายการตรวจสอบสำหรับ Phase 1 (Redis Middleware & Caching) — Deployed

#### 1. การจำกัดคำขอ (Rate Limiting Middleware Check)
* [x] **การบล็อกคำขอเกินพิกัด:** `defaultRateLimiter` ทำงานบน `/api` ทุก endpoint → เกิน 60 req/min ตอบ `429`
* [x] **การเริ่มนับใหม่เมื่อพ้นเวลา (Reset window):** Sliding Window Counter ใน Redis รีเซ็ตตาม windowSec
* [x] **ความถูกต้องของคีย์:** Redis keys ใช้รูปแบบ `rate:{ip}:{window}` มี TTL อัตโนมัติ

#### 2. ระบบป้องกันคำขอซ้ำ (Idempotency & Duplicate Check)
* [x] **Idempotency Key:** `idempotencyMiddleware` อ่าน header `x-idempotency-key` → เก็บผลลัพธ์ใน Redis 24 ชม.
* [x] **Duplicate Check:** `duplicateCheckMiddleware` / `checkDuplicate()` ใช้ `SET NX EX` ล็อกชั่วคราว 5 นาที

#### 3. ระบบอ่าน-เขียนแบบ Cache-Aside (Lazy Loading)
* [x] **Cache-Aside + Stampede Protection:** `cacheAside()` ใน `cache-aside.js` ใช้ `SET NX` lock ก่อน query DB → ป้องกันคนรุมดึงพร้อมกัน
* [x] **Cache Invalidation:** `invalidateCache()` / `invalidateCacheMany()` ลบ key ทันทีที่ข้อมูลเปลี่ยน
* [x] **Sliding Expiration:** `setSession()` / `verifySession()` รีเซ็ต TTL ทุกครั้งที่ใช้งาน

> **ไฟล์ที่เกี่ยวข้อง:**
> - `websocket-server/middleware/rate-limiter.js` — Rate limiting (Sliding Window)
> - `websocket-server/middleware/idempotency.js` — Idempotency & Duplicate check
> - `websocket-server/middleware/cache-aside.js` — Cache-Aside, Stampede lock, Session helpers
> - `websocket-server/middleware/redis-client.js` — Shared ioredis client
> - `websocket-server/middleware/index.js` — Unified exports
> - `websocket-server/server.js` — Wired ที่บรรทัด 119-135, 143, 1175-1188

---

### 🟢 รายการตรวจสอบสำหรับ Phase 2 (BullMQ Queue System + Event-Driven Caching)

#### 1. การทำงานพื้นฐานของ Queue (Job Processing)
* [ ] **การบันทึก Job อะซิงโครนัส:** ยื่นคำร้องของาน (เช่น สร้างการจอง) → ระบบต้องตอบกลับสถานะ `202 Accepted` พร้อมส่ง `jobId` กลับมาให้ผู้ใช้งานทันทีโดยไม่ต้องรอให้ DB ทำงานเสร็จ
* [ ] **ความสำเร็จของการประมวลผล:** ตรวจสอบหลังบ้านว่า Worker สามารถดึงงานจาก Queue ออกไปเขียนข้อมูลลง PostgreSQL สำเร็จ และส่งข้อความยืนยันผ่าน WebSocket กลับหาผู้ใช้
* [ ] **สถานะงานใน Redis:** ใช้ Redis CLI ตรวจสอบว่ามีโครงสร้างข้อมูลของ BullMQ บันทึกอยู่ (เช่น คีย์ `bull:booking:active` หรือ `bull:booking:completed`)

#### 2. ลำดับความสำคัญและคิวงานด่วน (Priority Queue Check)
* [ ] **การแทรกคิวฉุกเฉิน (Emergency Alert):**
  1. ยิงวิดีโอทั่วไป (Normal) เข้าคิวจ่อไว้ 10 รายการ และหยุดการทำงานของ Worker ชั่วคราว
  2. ยิงคำร้องเหตุฉุกเฉิน (Emergency Alert Video) เข้ามาในคิว
  3. เปิดระบบให้ Worker ทำงาน → ตรวจสอบลำดับการทำงาน ต้องพบว่าวิดีโอเหตุฉุกเฉินถูกนำมาแปลงไฟล์และดึงข้อมูลก่อนวิดีโอปกติที่จ่ออยู่ก่อนหน้า (Emergency Priority First)

#### 3. ระบบจัดการงานล้มเหลว (Failure & Retry Logic)
* [ ] **การพยายามใหม่เมื่อระบบมีปัญหา (Auto-Retry):** จำลองกรณีที่ส่งอีเมลแจ้งเตือนไม่สำเร็จ (Network timeout) → ตรวจสอบว่า BullMQ พยายามส่งใหม่อีกครั้งตามรอบดีเลย์ที่ตั้งไว้ (เช่น retry 3 ครั้ง ห่างกันครั้งละ 5 วินาที)
* [ ] **การคัดแยกงานเสีย (Failed Jobs Queue):** หากพยายามครบจำนวนแล้วยังไม่สำเร็จ → ตรวจสอบว่าสถานะย้ายไปอยู่ที่หมวด `failed` เพื่อรอให้ผู้ดูแลระบบเข้ามาสั่งรันซ้ำแบบแมนนวล (Manual Retry)

#### 4. Event-Driven Cache Invalidation
* [ ] **Invalidate-on-Complete:** สร้าง booking ผ่าน queue → ตรวจสอบว่า Worker ลบ `booking:slots:*` ออกจาก Redis หลังประมวลผลเสร็จ
* [ ] **Invalidate-on-Start:** สั่ง order ผ่าน queue → ตรวจสอบว่า Worker ลบ `order:status:${id}` ก่อนเริ่มประมวลผล (ป้องกัน stale read)
* [ ] **Pattern-based Invalidation:** แก้ไขเมนูร้าน → ส่ง invalidation event ผ่าน notification-queue → ใช้ `SCAN` ลบ key ตาม pattern `menu:restaurant:${id}:*` → ตรวจสอบว่า key ถูกลบจริง
* [ ] **Retry on Invalidation Failure:** ปิด Redis ชั่วคราวแล้วส่ง invalidation event → ตรวจสอบว่า BullMQ retry อัตโนมัติ และ invalidation สำเร็จหลัง Redis กลับมา

#### 5. Cache Warming จาก Worker
* [ ] **Warm-on-Complete (Order):** Worker ประมวลผล order เสร็จ → ตรวจสอบว่า `order:status:${orderId}` ถูกเติมลง Redis ทันทีด้วยข้อมูลล่าสุดจาก DB
* [ ] **Warm-on-Complete (Donation):** Worker คำนวณยอดบริจาคใหม่ → ตรวจสอบว่า `donation:total:${campaignId}` ถูกเติมลง Redis พร้อม TTL 120 วินาที
* [ ] **Cross-Key Invalidation:** Worker สร้าง order เสร็จ → ตรวจสอบว่า `cart:user:${userId}` ถูกลบออกจาก Redis ด้วย

#### 6. TTL Compliance & Cache Consistency
* [ ] **TTL ตรงตาม spec:** ตรวจสอบ TTL ของแต่ละ key type ด้วย `TTL` command:
  - `booking:slots:*` ≈ 60 วินาที
  - `order:status:*` ≈ 300 วินาที
  - `donation:total:*` ≈ 120 วินาที
  - `video:meta:*` ≈ 3600 วินาที
* [ ] **Sliding Expiration สำหรับ Session:** เรียก API ที่ต้องใช้ session → ตรวจสอบว่า `TTL auth:session:*` ถูกรีเซ็ตเป็น 7200 วินาทีทุกครั้งที่ใช้งาน
* [ ] **Cache Hit / Miss Monitoring:** บันทึกสถิติการอ่าน Cache ในแต่ละ endpoint:
  - Cache Hit Rate ของ `menu:restaurant:*` ควร ≥ 80%
  - Cache Miss ของ `booking:slots:*` ควรต่ำเมื่อใช้ Warm-on-Complete

#### 7. Distributed Lock สำหรับ Queue-Sensitive Operations
* [ ] **Mutex Lock (Booking Slot):** ยิงจอง slot เดียวกันพร้อมกัน 2 รายการ → ตรวจสอบว่า `SETNX lock:slot:*` อนุญาติให้ผ่านแค่รายการเดียว อีกรายการติด `409 Conflict`
* [ ] **Mutex Lock (POS Injection):** ยิง order เดียวกันซ้ำ → ตรวจสอบว่า `lock:order:pos-inject:*` ป้องกันการ inject ซ้ำ
* [ ] **Sync Lock:** เรียก sync จาก 2 อุปกรณ์พร้อมกัน → ตรวจสอบว่า `sync:lock:user:*` อนุญาติให้ sync ได้ทีละอุปกรณ์

#### 8. Graceful Shutdown & Connection Reuse
* [ ] **Worker Pause on Shutdown:** ส่ง `SIGTERM` → ตรวจสอบ log ว่า worker หยุดรับ job ใหม่ (`pause`) ก่อนปิด connection
* [ ] **Shared Connection:** ตรวจสอบว่า `queues/index.js` ใช้ connection config reuse จาก `redis-client.js` ไม่สร้าง ioredis instance ใหม่สำหรับ BullMQ
* [ ] **Redis Connection Count:** ใช้ `CLIENT LIST` ใน Redis → connection count ไม่เพิ่มเกิน expected (singleton + BullMQ blocking connection)

