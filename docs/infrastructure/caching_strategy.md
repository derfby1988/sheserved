# ⚡ แผนยุทธศาสตร์การทำ Caching (Caching Strategy) สำหรับ Sheserved
## ขอบเขต: ครอบคลุมทุกระบบย่อย (Auth · Directory & Menu · Cart & Ordering · Booking · Escrow & Donation · Video · Sync) เพื่อการเติบโตที่ไร้รอยต่อ

เอกสารนี้วิเคราะห์ Caching Patterns จากสถาปัตยกรรมอ้างอิง และนำเสนอแนวทางการประยุกต์ใช้กับ **Sheserved** เพื่อรองรับการขยายตัวในอนาคต โดยมุ่งเน้นแนวทาง **ไม่มีค่าใช้จ่ายเพิ่มเติม (Zero-Cost)** ในช่วงพัฒนาและ Deploy เริ่มต้น

> [!NOTE]
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

### 🟢 Phase 1 — Redis Middleware (สัปดาห์ที่ 1-2)
เน้นการจัดการความปลอดภัย ทราฟฟิก และ Cache สำหรับอ่าน-เขียนข้อมูลทั่วไป

#### 2.1 Read Pattern: Cache-Aside (Lazy Loading) + Query Result & Object Cache
*   **แนวทางปฏิบัติ:** ตรวจสอบคีย์ใน Redis ก่อนเสมอ หากไม่มีค่อยดึงจาก PostgreSQL และเขียนลง Redis พร้อม TTL
*   **ความเชื่อมโยงกับแผนย่อยอื่น:**
    *   **[SHOPPING_CART_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/SHOPPING_CART_PLAN.md):** เก็บข้อมูลตะกร้าสินค้าชั่วคราว (`cart:user:${userId}`) ด้วยเทคนิค Object Cache บน Redis เพื่อเลี่ยงการเขียนลง DB ทุกครั้งที่ผู้ใช้กดยืนยันหรือเพิ่มสินค้า
    *   **[DONATION_SYSTEM_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/DONATION_SYSTEM_PLAN.md):** แคชยอดเงินบริจาครวมของแต่ละแคมเปญ (`donation:total:${campaignId}`) แบบมี TTL สั้น (1-2 นาที) สำหรับแสดงบน Dashboard/หน้าแรกแบบ Real-time โดยไม่ดึง DB ถี่เกินไป

```javascript
// ตัวอย่างโค้ดโครงสร้าง Cache-Aside สำหรับเมนูอาหาร
async function getRestaurantMenu(restaurantId) {
  const cacheKey = `menu:restaurant:${restaurantId}`;
  
  // 1. ตรวจสอบ Cache
  const cachedData = await redis.get(cacheKey);
  if (cachedData) {
    return JSON.parse(cachedData);
  }
  
  // 2. ดึงจาก PostgreSQL (Source of Truth)
  const menuItems = await db.query('SELECT * FROM menus WHERE restaurant_id = $1', [restaurantId]);
  
  // 3. เซฟเข้า Redis พร้อมตั้งเวลา TTL 10 นาที (600 วินาที)
  await redis.set(cacheKey, JSON.stringify(menuItems), 'EX', 600);
  
  return menuItems;
}
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

### 🟢 Phase 2 — BullMQ Queue System (สัปดาห์ที่ 2-4)
เน้นการประมวลผลคำขอแบบอะซิงโครนัส (Async Processing) ผ่าน Redis Queue เพื่อช่วยลดภาระโหลดและรับประกันความเสถียรของแอปพลิเคชัน

#### 2.5 รายละเอียดการประยุกต์ใช้รายระบบย่อย (Sheserved Subsystems)
ตารางด้านล่างแสดงการจัดการ Caching และ Queue สำหรับแต่ละระบบย่อย โดยสอดคล้องและได้รับการตรวจสอบแล้วว่าไม่ขัดแย้งกับแผนงานหลัก:

| ระบบย่อย (Subsystem) | วิธีการจัดการ Caching / Queue | ตัวอย่างการตั้งชื่อคีย์ (Redis Key Schema) | ความเชื่อมโยงและจุดประสานตามแผนหลัก |
|---|---|---|---|
| **1. ระบบสมาชิกและเซสชัน (Auth & Session)** | - Sliding Expiration (3.2)<br>- Invalidation (4.1) เมื่อ logout | `auth:session:${sessionId}`<br>`auth:token:${userId}` | สอดคล้องกับ **[CHAT_CONSULTATION_IMPROVEMENT_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md)**: ใช้จัดการสิทธิ์เข้าใช้งานห้องสนทนาของแพทย์และคนไข้โดยไม่ละเมิดสิทธิ์ RLS (เนื่องจากระบบใช้ Custom Auth ของตนเอง) |
| **2. ระบบข้อมูลร้านและเมนู (Directory & Menu)** | - Cache-Aside (1.1)<br>- Object Cache (7.3)<br>- Write-Around (2.3) เมื่อแก้ไข | `menu:restaurant:${restaurantId}`<br>`restaurant:profile:${restaurantId}` | สอดคล้องกับ **[ERP_CORE_ARCHITECTURE.md](file:///Users/dave_macmini/sheserved/docs/ERP/ERP_CORE_ARCHITECTURE.md)**: จัดเตรียมเมนูและข้อมูลหน้าร้านให้อ่านเร็วที่สุดสำหรับ POS |
| **3. ระบบสั่งอาหารและตะกร้า (Ordering & Cart)** | - Cache-Aside (1.1) สำหรับอ่านเมนู<br>- Object Cache (7.3) สำหรับตะกร้าสินค้า<br>- BullMQ Queue (Phase 2) สำหรับออร์เดอร์ | `cart:user:${userId}`<br>`order:status:${orderId}` | สอดคล้องกับ **[SHOPPING_CART_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/SHOPPING_CART_PLAN.md)**: ตะกร้าพักไว้ใน Redis แล้วจึงยิง API (POS Injection) ข้ามไปสร้างบิลใน **POS System** ของคลินิกผ่าน `order-queue` |
| **4. ระบบจองโต๊ะและคิว (Booking & Reservation)** | - Cache-Aside (1.1) สำหรับดูตารางเวลา<br>- Mutex Lock (6.2) กันจองซ้ำ<br>- BullMQ Queue (Phase 2) สำหรับส่งงาน | `booking:slots:${restaurantId}:${date}`<br>`lock:slot:${restaurantId}:${date}:${time}` | สอดคล้องกับ **[CHAT_CONSULTATION_IMPROVEMENT_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md)**: ใช้ `SETNX` ล็อกจังหวะเริ่ม Session การนัดหมายแพทย์ ป้องกันไม่ให้ชนกับคิวอื่นของแพทย์ |
| **5. ระบบบริจาคและเงินประกัน (Donation & Escrow)** | - Write-Around (2.3) ตรงเข้า DB<br>- Cache-Aside (1.1) สำหรับดูยอดรวมโชว์หน้าแรก | `donation:total:${campaignId}`<br>`escrow:status:${escrowId}` | สอดคล้องกับ **[DONATION_SYSTEM_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/DONATION_SYSTEM_PLAN.md)**: ใช้การบันทึกระดับ DB ในการลงทะเบียนบริจาค/โหวตอนุมัติเพื่อป้องกัน Race Condition โดยระบบ Caching จะกรองข้อมูลแบบ Read-only เท่านั้น |
| **6. ระบบประมวลผลวิดีโอ (Video Processing)** | - Cloudflare Free CDN (8.1) แคชรูปภาพ/วิดีโอ<br>- BullMQ Queue (Phase 2) สำหรับรันงานหลังบ้าน | `video:meta:${videoId}`<br>`job:thumbnail:${videoId}` | สอดคล้องกับ **[VIDEO_SYSTEM_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/VIDEO_SYSTEM_PLAN.md)**: ใช้ BullMQ จัดการลำดับคิวการประมวลผล (Priority Queue) โดย Emergency alerts จะถูกขยับขึ้นมาประมวลผลก่อน |
| **7. ระบบจัดส่งและติดตามพิกัด (Delivery & Logistics)** | - GPS cache ชั่วคราวบน Client<br>- BullMQ Queue (Phase 2) อัปเดตพัสดุ | `delivery:status:${orderId}` | สอดคล้องกับ **[Delivery_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/Delivery_PLAN.md)**: เก็บพิกัดและ tracking ไว้ที่ฝั่ง Mobile SDK เป็นหลัก (เพื่อควบคุมงบ Google Maps API) และซิงค์สถานะจัดส่งผ่าน queue |
| **8. ระบบซิงค์ข้อมูล (Local-Cloud Sync)** | - Distributed Lock (6.2) ป้องกันการซิงค์ซ้อน | `sync:lock:user:${userId}` | สอดคล้องกับ **[ERP_CORE_ARCHITECTURE.md](file:///Users/dave_macmini/sheserved/docs/ERP/ERP_CORE_ARCHITECTURE.md)**: ควบคุมการ Sync คิวสำหรับ Local Database ↔ Supabase Cloud ของคลินิกไม่ให้เกิดการเรียกชนกัน |

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

### 🟢 รายการตรวจสอบสำหรับ Phase 1 (Redis Middleware & Caching)

#### 1. การจำกัดคำขอ (Rate Limiting Middleware Check)
* [ ] **การบล็อกคำขอเกินพิกัด:** ยิงคำร้องขอถี่ยิบ (เช่น >60 ครั้งภายใน 1 นาที) ระบบต้องตอบกลับ HTTP Status `429 Too Many Requests`
* [ ] **การเริ่มนับใหม่เมื่อพ้นเวลา (Reset window):** เมื่อรอครบ 1 นาทีแล้วส่งคำขอใหม่ ระบบต้องยอมรับการเชื่อมต่อและตอบกลับ `200 OK`
* [ ] **ความถูกต้องของคีย์:** ตรวจสอบใน Redis CLI (`KEYS rate:*`) ต้องพบคีย์ที่เก็บ IP หรือ User ID ของผู้ใช้พร้อมเวลาหมดอายุ (TTL)

#### 2. ระบบป้องกันคำขอซ้ำ (Idempotency & Duplicate Check)
* [ ] **ป้องกันกดจอง/สั่งซื้อเบิ้ล (Idempotency Key):** ส่งคำสั่งชำระเงินที่แนบ Header `x-idempotency-key` ตัวเดิมเข้ามาพร้อมๆ กัน 2 รอบ ผลลัพธ์ต้องตอบกลับเหมือนกัน และข้อมูลใน PostgreSQL ต้องเกิดขึ้นเพียงเรคคอร์ดเดียว
* [ ] **Duplicate Check (ช่วงเวลาสั้น):** ส่งคำขอจองโต๊ะเวลาเดียวกันซ้ำสองภายใน 5 นาที ระบบต้องตอบกลับ `409 Conflict` และตรวจพบคีย์ล็อกชั่วคราวใน Redis (`dup:userId:booking`)

#### 3. ระบบอ่าน-เขียนแบบ Cache-Aside (Lazy Loading)
* [ ] **ตรวจสอบ Cache Miss:** ล้างคีย์ใน Redis และส่งคำขออ่านเมนูอาหาร -> ตรวจสอบ Log ของ PostgreSQL ต้องพบ SQL Query ทำงาน และพบว่าข้อมูลนั้นถูกเขียนบันทึกเข้า Redis
* [ ] **ตรวจสอบ Cache Hit:** เรียกอ่านเมนูเดิมรอบที่สอง -> ตรวจสอบ Log ของ PostgreSQL ต้อง **ไม่มี** SQL Query เกิดขึ้น และแอปได้รับข้อมูลอย่างรวดเร็ว (ดึงจาก Redis)
* [ ] **ตรวจสอบ Cache Invalidation:** ทำการแก้ไขราคาอาหารผ่าน POS -> ตรวจสอบใน Redis ว่าคีย์เมนูของร้านถูกลบไปอัตโนมัติ และการเรียกอ่านครั้งถัดไปกลับไปดึงจาก PostgreSQL อีกครั้ง
* [ ] **ตรวจสอบ Mutex Lock (ป้องกันคนรุมดึง):** จำลองโหลดระดับสูงรุมดึงหน้าเมนูที่ Cache Miss พร้อมกัน -> ตรวจสอบ Log ของ PostgreSQL ต้องพบ SQL Query วิ่งเข้ามาเพียง 1 ครั้ง (มีเพียง Request แรกที่ได้สิทธิ์เขียนลง Cache ส่วนรายการอื่นรอคอยและดึงจาก Cache ที่เขียนเสร็จ)

---

### 🟢 รายการตรวจสอบสำหรับ Phase 2 (BullMQ Queue System)

#### 1. การทำงานพื้นฐานของ Queue (Job Processing)
* [ ] **การบันทึก Job อะซิงโครนัส:** ยื่นคำร้องของาน (เช่น สร้างการจอง) -> ระบบต้องตอบกลับสถานะ `202 Accepted` พร้อมส่ง `jobId` กลับมาให้ผู้ใช้งานทันทีโดยไม่ต้องรอให้ DB ทำงานเสร็จ
* [ ] **ความสำเร็จของการประมวลผล:** ตรวจสอบหลังบ้านว่า Worker สามารถดึงงานจาก Queue ออกไปเขียนข้อมูลลง PostgreSQL สำเร็จ และส่งข้อความยืนยันผ่าน WebSocket กลับหาผู้ใช้
* [ ] **สถานะงานใน Redis:** ใช้ Redis CLI ตรวจสอบว่ามีโครงสร้างข้อมูลของ BullMQ บันทึกอยู่ (เช่น คีย์ `bull:booking:active` หรือ `bull:booking:completed`)

#### 2. ลำดับความสำคัญและคิวงานด่วน (Priority Queue Check)
* [ ] **การแทรกคิวฉุกเฉิน (Emergency Alert):** 
  1. ยิงวิดีโอทั่วไป (Normal) เข้าคิวจ่อไว้ 10 รายการ และหยุดการทำงานของ Worker ชั่วคราว
  2. ยิงคำร้องเหตุฉุกเฉิน (Emergency Alert Video) เข้ามาในคิว
  3. เปิดระบบให้ Worker ทำงาน -> ตรวจสอบลำดับการทำงาน ต้องพบว่าวิดีโอเหตุฉุกเฉินถูกนำมาแปลงไฟล์และดึงข้อมูลก่อนวิดีโอปกติที่จ่ออยู่ก่อนหน้า (Emergency Priority First)

#### 3. ระบบจัดการงานล้มเหลว (Failure & Retry Logic)
* [ ] **การพยายามใหม่เมื่อระบบมีปัญหา (Auto-Retry):** จำลองกรณีที่ส่งอีเมลแจ้งเตือนไม่สำเร็จ (Network timeout) -> ตรวจสอบว่า BullMQ พยายามส่งใหม่อีกครั้งตามรอบดีเลย์ที่ตั้งไว้ (เช่น retry 3 ครั้ง ห่างกันครั้งละ 5 วินาที)
* [ ] **การคัดแยกงานเสีย (Failed Jobs Queue):** หากพยายามครบจำนวนแล้วยังไม่สำเร็จ -> ตรวจสอบว่าสถานะย้ายไปอยู่ที่หมวด `failed` เพื่อรอให้ผู้ดูแลระบบเข้ามาสั่งรันซ้ำแบบแมนนวล (Manual Retry)

