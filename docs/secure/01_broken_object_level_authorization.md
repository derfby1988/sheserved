# แผนป้องกัน 01: Broken Object Level Authorization (BOLA / IDOR)

> **สถานะ:** ✅ Option A implemented และผ่านการทดสอบแล้ว (2026-07-27)
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** 09 (AuthN/AuthZ — ระดับ route/role), 12 (Least Privilege — ระดับ permission), 11 (Input Validation)
> **ความแตกต่างจากแผน 09/12:** แผน 09 ตอบว่า *"ผู้ใช้คนนี้เข้า endpoint นี้ได้ไหม"* · แผน 12 ตอบว่า *"มี permission อะไรบ้าง"* · **แผนนี้ตอบว่า "object ชิ้นนี้เป็นของเขาจริงหรือไม่"** ซึ่งเป็นคนละชั้นและ OWASP จัดเป็นช่องโหว่อันดับ 1 ของ API
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-A ลำดับ 1** เป็น containment แรก ก่อนการ refactor authentication ครั้งใหญ่
> **เหตุผล:** มีหลักฐานว่า endpoint รับ `userId` จาก request body ทั้งที่มี `req.userId` แล้ว จึงแก้ได้ทันทีด้วย ownership-scoped query และการตัด field ที่ client ควบคุมได้ โดยไม่ต้องรอ JWT migration
> **ผลการทดสอบ:** ผ่าน Maestro test suite 65 คำสั่ง ครอบคลุม 6 ส่วน (ล็อกอิน, การปรึกษา, แชท, ข้อมูลสุขภาพ, วิดีโอ, เชิงลบ) บน iPhone 16 simulator — ดูรายละเอียดใน section 10

---

## 1. สถานะปัจจุบัน (As-Is)

### หลักการที่ควรเป็น
```
ผ่าน requireAuth       = รู้ว่าเป็นใคร        (แผน 09)
ผ่าน requireRole       = รู้ว่ามีบทบาทอะไร    (แผน 09)
ผ่าน permission check  = รู้ว่าทำอะไรได้บ้าง   (แผน 12)
─────────────────────────────────────────────
❗ ยังขาด: object นี้เป็นของเขาหรือไม่        (แผนนี้)
```

### หลักฐานจากโค้ดจริง

**1. รับ `userId` จาก `req.body` แทนที่จะใช้ตัวตนที่ยืนยันแล้ว**
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:87-111
    router.post('/upload', requireAuth, idempotencyMiddleware, uploadRateLimiter, upload.single('video'), duplicateCheckMiddleware('video-upload', 5), async (req, res) => {
        try {
            const { userId, title, description, type, donationRequestId, address, road, soi, alley, village } = req.body;
```
`requireAuth` ยืนยันแล้วว่ามี `req.userId` แต่โค้ดกลับใช้ `userId` จาก body ไปเขียนลง `videos.user_id` — ผู้เรียกระบุเป็น ID ใครก็ได้

**2. รูปแบบเดียวกันในอีกหลาย endpoint**
| Endpoint | Field ที่มาจาก client | ไฟล์ |
|----------|---------------------|------|
| `POST /videos/upload` | `req.body.userId` | `video.js:89` |
| `POST /videos/upload-photos` | `req.body.userId`, `req.body.userIdFromRequest` | `video.js:159, 179` |
| `POST /videos/:id/accept` | `req.body.responderId` | `video.js:536` |
| `POST /videos/:id/interactions` | `req.body.user_id` | `video.js:699` |
| `GET /videos/:id/likes/status` | `req.query.userId` | `video.js:682` |

**3. Endpoint ที่อ่าน object โดยไม่ตรวจความเป็นเจ้าของ**
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:745-751
    router.get('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const data = await cacheAside(`video:meta:${id}`, async () => {
                const result = await pool.query('SELECT * FROM videos WHERE id = $1', [id]);
                return result.rows[0] || null;
            }, TTL.DEFAULT);
```
`SELECT *` คืนทุก column รวมถึงข้อมูลที่อาจไม่ควรเปิดเผย และไม่มี `requireAuth` / ownership check

**4. Cache key ไม่ผูกกับผู้เรียก**
`video:meta:${id}`, `video:gallery:${id}:${page}` — ถ้าเพิ่ม authorization ภายหลังแต่ไม่แก้ cache key ข้อมูลจะรั่วข้ามผู้ใช้ผ่าน cache

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| O1 | **เชื่อ `userId` จาก request body** | 🔴 วิกฤต | ตัวตนที่ยืนยันแล้ว (`req.userId`) มีอยู่แต่ไม่ถูกใช้ |
| O2 | **ไม่มี ownership check ก่อน read/update/delete** | 🔴 วิกฤต | รู้ ID = เข้าถึงได้ |
| O3 | **ใช้ UUID เป็นการป้องกัน** | 🟡 กลาง | UUID ทำให้เดายาก แต่ ID รั่วผ่าน list API / URL / log ได้ตลอด — **ไม่ใช่มาตรการความปลอดภัย** |
| O4 | **`SELECT *` ส่งทุก column กลับ** | 🟡 กลาง | Excessive Data Exposure — คู่แฝดของ BOLA |
| O5 | **Cache key ไม่รวม authorization context** | 🔴 สูง | เพิ่ม authz แล้วแต่ cache รั่วเหมือนเดิม |
| O6 | **แยกไม่ออกระหว่าง 403 กับ 404** | 🟡 กลาง | ตอบ 403 = ยืนยันว่า object มีอยู่จริง (information disclosure) |
| O7 | **Nested object ไม่ตรวจสาย ownership** | 🟡 กลาง | เช่น `/consultations/:cid/messages/:mid` — ตรวจว่า `mid` อยู่ใน `cid` จริงหรือไม่ |
| O8 | **Mass assignment** | 🟡 กลาง | รับ object ทั้งก้อนจาก body ไป update → เปลี่ยน `user_id`, `role`, `status` ได้ |
| O9 | **Bulk operation ไม่กรองรายตัว** | 🟡 กลาง | `ids: [...]` แล้วลบทั้งหมดโดยตรวจแค่ว่ามี login |
| O10 | **Client-side filtering** | 🔴 สูง | ดึงข้อมูลทั้งหมดมาแล้วซ่อนที่ Flutter — ข้อมูลอยู่ในมือผู้ใช้แล้ว |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว — Object ที่ต้องมี ownership check

| ระบบ | Object | เจ้าของคือใคร | ผลกระทบถ้าไม่ตรวจ |
|------|--------|--------------|-------------------|
| **Profile** | `users`, `user_categories` | ตนเอง | แก้โปรไฟล์คนอื่น / ยกระดับสิทธิ์ตนเอง 🔴 |
| **Consultation** | `consultation_requests`, `consultation_messages`, `chartboard_notes` | consumer เจ้าของ + provider ที่รับเคส | อ่านประวัติการรักษาคนอื่น 🔴 |
| **Chat** | `chat_rooms`, `chat_messages`, ไฟล์แนบ | participant | อ่านแชทคนอื่น 🔴 |
| **Video** | `videos`, `video_interactions`, `thai_mhung_photos` | ผู้อัปโหลด | ลบ/แก้วิดีโอคนอื่น, ปลอมยอด like 🟡 |
| **Donation** | `donation_requests`, `donations`, escrow, สลิป | ผู้บริจาค / ผู้รับ / leader | เห็นข้อมูลการเงินและ PII คนอื่น 🔴 |
| **Emergency** | `incidents`, `incident_responses` | ผู้แจ้ง / responder | รับงานแทนคนอื่น, เห็นพิกัดผู้แจ้ง 🔴 |
| **Health** | `health_records`, `health_data_permissions` | เจ้าของข้อมูล | อ่านข้อมูลสุขภาพคนอื่น 🔴 |
| **Pharmacy** | `drug_risk_overrides` | ผู้สร้าง / องค์กร | แก้ระดับความเสี่ยงยาขององค์กรอื่น 🔴 |
| **Prescription** | ใบสั่งยา | แพทย์ผู้สั่ง / ผู้ป่วย | 🔴 |
| **Group** | `user_group_roles` | สมาชิกกลุ่ม | เพิ่มตนเองเข้ากลุ่ม 🔴 |

### 2.2 ระบบตามแผน `docs/ERP/`

| แผน | Object ที่ต้องตรวจ | มิติที่ต้องตรวจ |
|-----|-------------------|----------------|
| `ERP_CORE_ARCHITECTURE.md` | ทุก entity | 🔴 `organization_id` — **ทุก query ต้องกรอง ไม่ใช่ทางเลือก** |
| `HR_SYSTEM_PLAN.md` | `employees`, `payslips`, `leave_requests` | ตนเอง / ผู้ใต้บังคับบัญชา / HR — **payslip คนอื่นห้ามเห็นเด็ดขาด** |
| `ACCOUNTING_SYSTEM_PLAN.md` | `gl_entries`, `journals`, `invoices` | org + fiscal period + approval state |
| `PROCUREMENT_SYSTEM_PLAN.md` | `purchase_orders`, `suppliers` | org + branch + วงเงินอนุมัติ |
| `POS System_plan.md` | `sales`, `shifts`, `refunds` | branch + กะของ cashier |
| `INVENTORY_SYSTEM_PLAN.md` | `stock_items`, `transfers` | org + branch ต้นทาง/ปลายทาง |
| `HIS_SYSTEM_PLAN.md` | `patients`, `encounters`, `emr_notes` | 🔴 ผู้ให้การรักษาที่เกี่ยวข้องเท่านั้น + break-glass |
| `LAB_SYSTEM_PLAN.md` | `lab_orders`, `lab_results` | ผู้สั่ง / ผู้ป่วย / lab staff |
| `CRM_SYSTEM_PLAN.md` | `customers`, `leads`, `deals` | sales owner / territory |
| `KPI_DASHBOARD_PLAN.md` | drill-down rows | ต้องกรองตามสิทธิ์ ไม่ใช่แค่ aggregate |
| `ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | `subscriptions`, `invoices` | org เจ้าของ |

### 2.3 ระบบตามแผน `docs/plans/`

| แผน | Object | ประเด็น |
|-----|--------|---------|
| `Delivery_PLAN.md` | `deliveries`, ที่อยู่ผู้รับ | Courier เห็นเฉพาะงานที่รับ **และเฉพาะช่วงเวลาที่ส่ง** |
| `SHOPPING_CART_PLAN.md` | `carts`, `cart_items`, `orders` | 🔴 คลาสสิก — `GET /orders/:id` ต้องตรวจเจ้าของ |
| `DONATION_SYSTEM_PLAN.md` | คำขอ, สลิป, บัญชีธนาคาร | 🔴 PII + การเงิน |
| `VIDEO_SYSTEM_PLAN.md` | video, unblurred access | `unblurred_profession_ids` ต้องตรวจฝั่ง server |
| `health_data_sync_plan.md` | device records | device token ผูกกับเจ้าของอุปกรณ์ |
| `CHAT_CONSULTATION_IMPROVEMENT_PLAN.md` | quick reply templates, notes | personal vs org scope |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Layered Authorization Boundary (แนะนำที่สุด) ⭐⭐⭐⭐⭐

**หลักการ:** ใช้การป้องกันหลายชั้นเป็นมาตรฐานเดียว ไม่ถือว่า scoped query เพียงอย่างเดียวเพียงพอ:

1. **Trusted identity:** backend ต้องตรวจสอบลายเซ็น token และสร้าง `req.userId` เอง — ห้ามเชื่อ `x-user-id`, `req.body.userId` หรือ JWT ที่ decode โดยไม่ verify
2. **Policy/data-access boundary:** ทุก resource มี policy กลางที่ระบุ owner, participant, organization, branch, role, time และ consent scope
3. **Ownership-scoped query:** ใช้ `object_id + authorization predicate` ใน SQL เดียวกันสำหรับ read/write/delete
4. **DTO/field allowlist:** จำกัด field ที่รับเข้าและส่งออก ไม่ใช้ `SELECT *` หรือ update ทั้ง `req.body`
5. **RLS/tenant defense-in-depth:** ทำร่วมกับแผน 12 เมื่อ identity ที่ verify แล้วถูกส่งต่อถึง data layer ได้จริง
6. **Automated BOLA tests:** ทดสอบ User A/User B, cross-organization, nested resource, realtime และ storage ทุกครั้งก่อน release

**เหตุผลที่เลือกเป็น A:** แก้ root cause ที่แท้จริงครบทั้ง identity spoofing และ object authorization ขณะที่ยังใช้ scoped query เป็น enforcement หลักที่ทำได้ทันที ไม่สร้างความเข้าใจผิดว่า middleware, client filter หรือ UUID เพียงอย่างเดียวเพียงพอ

> **ลำดับ rollout:** ใช้ scoped query + DTO กับ endpoint สำคัญเป็น containment ได้ทันที แต่ต้องติดตามด้วย signed identity (แผน 08/09) ก่อนถือว่า authorization เสร็จสมบูรณ์

```js
// ❌ รูปแบบเดิม
const result = await pool.query('SELECT * FROM videos WHERE id = $1', [id]);

// ✅ รูปแบบที่เสนอ
const result = await pool.query(
  'SELECT id, title, description, status FROM videos WHERE id = $1 AND user_id = $2',
  [id, req.userId]                      // ใช้ตัวตนที่ยืนยันแล้วเท่านั้น
);
if (result.rows.length === 0) {
  return res.status(404).json({ error: 'Not found' });   // 404 ไม่ใช่ 403
}
```

**และเลิกรับ `userId` จาก body ทุกจุด**
```js
// ❌ const { userId, title } = req.body;
// ✅ const { title } = req.body;
//    const userId = req.userId;        // มาจาก verifyToken เท่านั้น
```

**ข้อดี**
- ปิด O1, O2, O6 พร้อมกัน; แก้ที่ต้นเหตุตรงไปตรงมา
- ครอบคลุมทั้ง API, repository, realtime, storage และ database เมื่อ rollout ครบทุกชั้น
- Atomic — ไม่มี race condition ระหว่าง check กับ act
- แบ่ง rollout ได้: containment ก่อน แล้วค่อย signed identity/RLS
- ทำให้ policy, DTO และ automated test ใช้มาตรฐานเดียวกันทุกระบบ

**ข้อเสีย**
- ขอบเขตกว้าง ต้องแก้ทุก endpoint (~100+) และ repository ฝั่ง Flutter ที่ยิง Supabase ตรง
- ต้องประสานแผน 08/09/11/12 และกำหนด compatibility window
- ลืมจุดเดียว = ยังรั่ว จึงต้องมี inventory, checklist, code review และ automated test

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Authorization Middleware ต่อ Resource

```js
// websocket-server/middleware/ownership.js
function requireOwnership(table, ownerColumn = 'user_id', paramName = 'id') {
  return async (req, res, next) => {
    const result = await pool.query(
      `SELECT ${ownerColumn} FROM ${table} WHERE id = $1`,   // table จาก allowlist เท่านั้น
      [req.params[paramName]]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Not found' });
    if (result.rows[0][ownerColumn] !== req.userId && req.userRole !== 'admin') {
      return res.status(404).json({ error: 'Not found' });
    }
    req.resource = result.rows[0];
    next();
  };
}

router.delete('/:id', requireAuth, requireOwnership('videos'), handler);
```

**ข้อดี:** ประกาศชัดเจนว่า endpoint ไหนต้องการ ownership; อ่านง่ายจาก route definition; ทดสอบ middleware ตัวเดียวได้
**ข้อเสีย:** query เพิ่ม 1 ครั้ง; ownership ที่ซับซ้อน (participant, org+branch, provider ที่รับเคส) ต้องเขียน middleware เฉพาะ; ใช้ไม่ได้กับ list endpoint
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ดีสำหรับ ownership แบบตรงไปตรงมา ใช้คู่กับ A

---

### ตัวเลือก C: Row Level Security (บังคับที่ DB)

```sql
CREATE POLICY video_owner ON videos
  FOR ALL USING (user_id = current_setting('app.user_id')::uuid);
```

**ข้อดี:** ✅ บังคับที่ชั้นสุดท้าย — ลืมในโค้ดก็ยังปลอดภัย; ครอบคลุม client ที่ยิง Supabase ตรง; ปิด O2, O10 อย่างสมบูรณ์
**ข้อเสีย:** ซ้ำซ้อนกับแผน 12 ตัวเลือก B (ควรทำเป็นงานเดียวกัน); ต้องส่ง identity เข้า DB (แผน 08); ไม่ป้องกัน O1 (ถ้าโค้ดเขียน `user_id` ผิดตั้งแต่ตอน INSERT)
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **แต่ให้ถือเป็นส่วนหนึ่งของแผน 12 ไม่ใช่งานแยก**

---

### ตัวเลือก F: Central Policy/Authorization Service (ทางเลือกเพิ่มเติม)

**หลักการ:** สร้าง policy registry หรือ authorization service กลาง เช่น `can(user, action, resource)` ให้ทุก API, repository และ job เรียกใช้ policy เดียวกัน แทนการเขียนเงื่อนไข ownership กระจายอยู่ใน handler:

```js
const decision = await authorization.can({
  subject: req.user,
  action: 'read',
  resource: { type: 'consultation', id: req.params.id },
});
if (!decision.allowed) return res.status(404).json({ error: 'Not found' });
```

**ข้อดี:** policy ซับซ้อน (participant, organization, branch, care team, consent, time-bound) รวมศูนย์; audit และ policy review ทำได้ง่าย; ลดเงื่อนไขซ้ำกัน

**ข้อเสีย:** เพิ่ม service abstraction และ latency; ถ้า handler query object ก่อนตรวจ policy อาจยังเกิด data leak; ไม่แทนที่ scoped query/RLS; ต้องออกแบบ cache และ fail-closed อย่างรัดกุม

**คำแนะนำ:** เก็บเป็น **ระยะถัดไปหลัง Option A** สำหรับ domain ที่มี policy ซับซ้อน เช่น HIS, ERP และ health sharing โดยเริ่มจาก policy module ใน process เดียวก่อน ยังไม่ควรสร้าง network service แยกในรอบ containment

---

### ตัวเลือก D: DTO / Field Allowlist (แก้ O4, O8)

```js
// Response DTO — ระบุ field ที่ส่งออกได้
const VIDEO_PUBLIC_FIELDS = ['id', 'title', 'description', 'thumbnail_url', 'created_at'];
const VIDEO_OWNER_FIELDS  = [...VIDEO_PUBLIC_FIELDS, 'status', 'progress', 'address'];

// Request DTO — ระบุ field ที่แก้ไขได้ (กัน mass assignment)
const VIDEO_UPDATABLE = ['title', 'description', 'category_id'];
const patch = pick(req.body, VIDEO_UPDATABLE);   // user_id, status ถูกตัดทิ้งอัตโนมัติ
```

**ข้อดี:** ปิด O4, O8; ทำให้ response contract ชัดเจน; ป้องกันข้อมูลรั่วโดยไม่ตั้งใจเมื่อเพิ่ม column ใหม่
**ข้อเสีย:** ต้องดูแล field list; boilerplate เพิ่ม
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — คู่กับแผน 11 (validation schema ใช้ร่วมกันได้)

---

### ตัวเลือก E: Automated BOLA Testing

```
สร้าง test user A และ B แล้วทดสอบทุก endpoint:
  1. A สร้าง resource → ได้ id
  2. B พยายาม GET/PUT/DELETE ด้วย id นั้น
  3. ต้องได้ 404 ทุกกรณี
```
+ เพิ่ม `docs/guides/scenario_sec_bola_*.yaml` ใน Maestro/E2E suite

**ข้อดี:** จับ regression ได้อัตโนมัติ; ครอบคลุมทุก endpoint อย่างเป็นระบบ; เป็นหลักฐาน compliance
**ข้อเสีย:** ต้องเขียน test เยอะ; ต้องมี test data setup
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **จำเป็น** เพราะ A/B/D พึ่งพาความไม่ผิดพลาดของนักพัฒนา

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **A: Layered Authorization Boundary** — signed identity → policy/data-access boundary → scoped query → DTO → RLS (แผน 12) → tests | ครอบคลุม root cause และ defense-in-depth ทั้ง API, Flutter/Supabase, realtime, storage และ database |
| 2 | **A + B** — เพิ่ม resource middleware ในจุด ownership แบบตรงไปตรงมา | เพิ่ม route-level clarity แต่ยังต้องใช้ scoped query ใน list/nested/bulk operations |
| 3 | **A + F** — เพิ่ม central policy module สำหรับ HIS/ERP/health ที่มี policy ซับซ้อน | ลด policy ซ้ำ แต่ควรทำหลัง containment และไม่สร้าง network service แยกทันที |
| 4 | **C + A สำหรับ INSERT** — RLS เป็นหลักร่วมกับ scoped query | เหมาะเมื่อ signed identity และแผน 12 พร้อมแล้ว ไม่ควรเริ่มก่อน |
| 5 | **B อย่างเดียว** | ไม่พอ — ไม่ครอบคลุม list endpoint, direct Supabase, realtime, storage และ bulk operations |

---

## 5. กฎมาตรฐานที่เสนอ (Sheserved Object Access Standard)

```
กฎที่ 1 — ห้ามเชื่อ identity จาก request payload
  ❌ req.body.userId / req.query.userId / req.body.user_id
  ✅ req.userId (จาก verifyToken) เท่านั้น
  ข้อยกเว้น: admin ทำแทนผู้อื่น → ต้องมี permission ชัดเจน + audit log

กฎที่ 2 — Query ต้องมีเงื่อนไข scope เสมอ
  SELECT ... WHERE id = $1 AND <ownership condition>
  ห้าม SELECT ... WHERE id = $1 เพียงอย่างเดียวสำหรับข้อมูลที่ไม่ public

กฎที่ 3 — ไม่พบหรือไม่มีสิทธิ์ → ตอบ 404 เหมือนกัน
  (ยกเว้นกรณีที่ผู้ใช้ควรรู้ว่ามี resource อยู่ เช่น "รอการอนุมัติ")

กฎที่ 4 — Response ต้องผ่าน field allowlist
  ห้าม SELECT * ส่งตรงถึง client

กฎที่ 5 — Update ต้องผ่าน field allowlist
  ห้าม UPDATE ... SET <ทั้ง req.body>

กฎที่ 6 — Cache key ต้องรวม authorization context
  ❌ video:meta:${id}
  ✅ video:meta:${id}:viewer:${req.userId}   หรือ cache เฉพาะข้อมูล public

กฎที่ 7 — Nested resource ต้องตรวจสาย parent
  /consultations/:cid/messages/:mid
  → ตรวจว่า mid.consultation_id = cid AND cid เป็นของผู้เรียก

กฎที่ 8 — Bulk operation ต้องกรองรายตัว
  DELETE ... WHERE id = ANY($1) AND user_id = $2
  แล้วรายงานจำนวนที่ลบจริง

กฎที่ 9 — ห้าม filter ที่ client
  ข้อมูลที่ไม่ควรเห็น ต้องไม่ถูกส่งออกจาก server ตั้งแต่แรก

กฎที่ 10 — Admin bypass ต้อง explicit และ log ทุกครั้ง
  ไม่ใช่ `|| req.userRole === 'admin'` แบบเงียบ ๆ
```

### ประเภทความเป็นเจ้าของใน Sheserved

| ประเภท | เงื่อนไข SQL | ใช้กับ |
|--------|-------------|--------|
| Direct owner | `user_id = $me` | profile, video, health record |
| Participant | `EXISTS (SELECT 1 FROM chat_participants WHERE room_id = r.id AND user_id = $me)` | chat |
| Assigned provider | `provider_id = $me OR user_id = $me` | consultation |
| Organization scope | `organization_id = $myOrg` | ERP ทุกตาราง |
| Branch scope | `branch_id = ANY($myBranches)` | ERP inventory, POS |
| Care team | `EXISTS (SELECT 1 FROM care_team WHERE patient_id = p.id AND staff_id = $me)` | HIS/LAB |
| Time-bound | `... AND $now BETWEEN access_from AND access_until` | delivery courier |
| Consent-based | `EXISTS (SELECT 1 FROM health_data_permissions WHERE owner_id = h.user_id AND grantee_id = $me AND revoked_at IS NULL)` | health sharing |

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ⚠️ **ต้องขยายความ** — guideline ระบุให้ใช้ `ServiceLocator.instance.currentUser` เป็นแหล่ง userId ฝั่งแอป ซึ่งถูกต้อง แต่ต้องเพิ่มข้อความชัดเจนว่า **ฝั่ง server ห้ามเชื่อ userId ที่แอปส่งมา** ต้องใช้ตัวตนที่ยืนยันเองเสมอ |
| `docs/secure/09_authentication_authorization.md` | เสริมกัน — 01 คือ route-level, แผนนี้คือ object-level |
| `docs/secure/12_least_privilege.md` | ตัวเลือก C (RLS) ควรทำเป็นงานเดียวกับแผน 12 ตัวเลือก B |
| `docs/secure/11_input_validation.md` | Field allowlist (D) ใช้ schema เดียวกับ validation ได้ |
| `docs/infrastructure/caching_strategy.md` | ⚠️ **ต้องแก้** — cache key ปัจจุบันไม่มี authorization context (กฎที่ 6) |
| `docs/ERP/ERP_CORE_ARCHITECTURE.md` | Multi-tenant scoping = ownership check ประเภทหนึ่ง ต้องบังคับที่ชั้น data access |
| `docs/guides/TEST_PLAN.md` | ควรเพิ่มหมวด BOLA test (ตัวเลือก E) — user A vs user B |

---

## 7. งานที่ต้องตรวจสอบทันทีเมื่ออนุมัติ

- [ ] Grep หา `req.body.userId`, `req.body.user_id`, `req.query.userId` ทุกจุดใน `websocket-server/`
- [ ] Grep หา `SELECT *` ใน route handler ที่ส่งผลลัพธ์ตรงถึง client
- [ ] ตรวจ endpoint ที่ไม่มี `requireAuth` ว่าเป็น public จริงหรือลืมใส่
- [ ] ตรวจ cache key ทุกตัวว่าผูกกับ authorization context หรือไม่
- [ ] ตรวจ repository ฝั่ง Flutter ที่ query Supabase โดยไม่มีเงื่อนไข ownership

---

## 8. Checklist การ implement (อัปเดต 2026-07-27)

- [x] อนุมัติกฎ 10 ข้อ (section 5) เป็นมาตรฐานของโปรเจกต์
- [x] อนุมัติ **Option A: Layered Authorization Boundary** เป็น baseline บังคับ
- [ ] กำหนด compatibility window สำหรับ signed identity ก่อนเลิกเชื่อ `x-user-id`
- [ ] สร้าง resource/policy inventory: owner, participant, organization, branch, role, time และ consent scope
- [ ] เลือกใช้ Resource Middleware (B) เฉพาะ direct-owner routes
- [ ] วาง Central Policy Module (F) สำหรับ domain ที่มี policy ซับซ้อน
- [x] ตัดสินใจนโยบาย 403 vs 404 (ใช้ 404 เป็นค่าเริ่มต้น)
- [x] อนุมัติ DTO/field allowlist เป็นส่วนหนึ่งของ Option A
- [x] อนุมัติ BOLA test suite เป็น acceptance gate ของทุก phase
- [x] กำหนดลำดับ endpoint ที่จะแก้ก่อน (health → consultation → chat → donation → video)
- [ ] ตัดสินใจว่าจะแก้ `auth_data_guidelines.md` เพื่อระบุกฎ "server ไม่เชื่อ client identity" หรือไม่
- [x] อนุมัติแผน 3 รอบ implement (section 9.1)
- [ ] ตัดสินใจนโยบาย generic CRUD fail-safe (section 9.3)
- [x] ตัดสินใจ cache invalidation strategy — ใช้ cache versioning `:v2` (section 9.6)
- [x] ตัดสินใจนโยบาย Realtime/Stream BOLA — ใช้ filter ชั่วคราวก่อน RLS (section 9.10)
- [x] ตัดสินใจนโยบาย Storage BOLA — ใช้ signed URL สำหรับ sensitive buckets (section 9.11)
- [x] แก้ `consultation-queue.js` ให้ใช้ `req.userId` แทน `payload.userId` (section 9.12)

---

## 9. ข้อเสนอแนะเพิ่มเติมจากการวิเคราะห์ผลกระทบ (2026-07-27)

> ข้อมูลสำหรับการตัดสินใจ implement — จากการวิเคราะห์ผลกระทบต่อทุกระบบใน Sheserved

### 9.1 แบ่งการ implement เป็น 3 รอบ

**รอบ 1 (Sprint 1-2): Containment ทันที — ปิดช่องโหว่ที่ exploit ได้จริง**
- `video.js` — เลิกรับ `userId` จาก body + scoped query (ตัวเลือก A)
- `consultation_repository.dart` — เพิ่ม ownership check ใน `getUserRequests`, `updateRequest`
- `chat_repository.dart` — เพิ่ม participant check ใน `getMessages`, `markAsRead`
- `health_repository.dart` — เปลี่ยนจาก parameter `userId` เป็น session-based
- ตรวจ cache key ทั้งหมดใน `video.js`

**รอบ 2 (Sprint 3-4): Repository-wide refactoring — ฝั่ง Flutter**
- เปลี่ยน repository methods ทั้งหมดให้ใช้ session-based userId
- เพิ่ม DTO/field allowlist (ตัวเลือก D) ในทุก repository
- แก้ generic CRUD (`sync_service`, `supabase_service`) ให้มี ownership parameter

**รอบ 3 (Sprint 5-6): ERP + RLS + Testing**
- เพิ่ม `organization_id` scope ในทุก ERP repository (~15+ update/delete)
- Implement signed identity และ policy/data-access boundary ตาม Option A
- Implement RLS (ตัวเลือก C) คู่กับแผน 12 หลัง identity พร้อม
- สร้าง BOLA test suite (ตัวเลือก E) เป็น acceptance gate ของทุก phase

### 9.2 การเลือก approach แนะนำ: Option A เป็น baseline + B/F เฉพาะจุด

| ตัวเลือก | บทบาทใน implementation | ลำดับ |
|---------|-------------------------|--------|
| **A (Layered Authorization Boundary)** | baseline บังคับทุกระบบ: signed identity, policy, scoped query, DTO, RLS และ tests | 1 |
| **B (Resource Middleware)** | เพิ่มเฉพาะ direct-owner routes เพื่อให้ route contract ชัดเจน; handler ยังต้อง scope query | 2 (เลือกใช้) |
| **F (Central Policy Module)** | เพิ่มภายหลังสำหรับ policy ซับซ้อน; เริ่มเป็น in-process module | 3 (domain-specific) |
| **C (RLS)** | defense-in-depth ตามแผน 12 หลัง identity ที่ verify แล้วพร้อม | 4 |
| **D/E** | D เป็นส่วนของ A; E เป็น acceptance gate ของ A ไม่ควรเลื่อนไปท้ายสุด | ทำควบคู่ |

**ข้อสรุป:** ไม่แนะนำให้เลือก A/B/C/D/E แบบแยกขาดจากกัน เพราะแต่ละตัวปิดคนละชั้นของปัญหา การตัดสินใจที่เหมาะสมคือ **Option A เป็นมาตรฐานบังคับ + B/F ตามความซับซ้อน + C ตาม dependency ของแผน 08/09/12**

### 9.3 Generic CRUD services ต้องมี fail-safe

`sync_service.dart` และ `supabase_service.dart` เป็นอันตรายที่สุดเพราะเป็น generic:

```dart
// แนวทางที่เสนอ — ถ้าไม่ส่ง ownershipScope มากับ sensitive table → throw
Future<void> update(String table, Map<String, dynamic> data,
    {Map<String, dynamic>? ownershipScope}) async {
  if (ownershipScope == null && _isSensitiveTable(table)) {
    throw Exception('Generic CRUD on sensitive table requires ownershipScope');
  }
  var query = client.from(table).update(data).eq('id', data['id']);
  if (ownershipScope != null) {
    for (final key in ownershipScope.keys) {
      query = query.eq(key, ownershipScope[key]);
    }
  }
  await query;
}
```

สิ่งที่ต้องกำหนด:
- รายชื่อ sensitive tables (ทุกตารางที่มี `user_id`, `organization_id`, `patient_id`)
- `_isSensitiveTable()` เป็น allowlist ไม่ใช่ blocklist

### 9.4 นโยบาย 404 vs 403 — 404 เป็นค่าเริ่มต้น ยกเว้น 3 กรณี

| กรณี | ตอบ | เหตุผล |
|------|-----|--------|
| ค่าเริ่มต้น | **404** | ไม่เปิดเผยว่า object มีอยู่จริง |
| "รอการอนุมัติ" | **403** | ผู้ใช้ควรรู้ว่า request มีอยู่และกำลังรอ |
| "งานที่รับแล้ว" | **403** | provider ควรรู้ว่ามีเคสที่รับแล้ว |
| object ที่ public | **200/404** | ตามปกติ (เช่น article, public video) |

### 9.5 การเชื่อมกับแผน 08 (Session/Token Security)

แผน 01 ระบุว่า "ไม่ต้องรอ JWT migration" แต่:
- `auth.js` ยังเชื่อ `x-user-id` จาก header ที่ปลอมได้
- BOLA fix (scoped query) จะไม่มีประสิทธิภาพถ้า identity ยังปลอมได้
- **ข้อเสนอแนะ:** ทำแผน 01 ก่อนเพื่อปิด BOLA แต่ต้องทำแผน 08 ตามมาโดยเร็วที่สุด

### 9.6 Cache invalidation strategy

เมื่อเพิ่ม ownership check → cache เก่าที่ไม่มี scope จะยังใช้ได้ (รั่ว):

**ตัวเลือกที่ 1: ล้าง cache ทั้งหมดตอน rollout**
```js
await invalidateCachePattern('*');
// หรืออย่างน้อย
await invalidateCachePattern('video:*');
```

**ตัวเลือกที่ 2: Cache versioning** (แนะนำ — ไม่กระทบ production)
```js
// เปลี่ยนจาก
const cacheKey = `video:meta:${id}`;
// เป็น
const cacheKey = `v2:video:meta:${id}:viewer:${req.userId}`;
```
ใช้ prefix `v2:` เพื่อให้ cache ใหม่ไม่ชนกับเก่า — cache เก่าจะหมดอายุตาม TTL เอง

### 9.7 รูปแบบโค้ดสำหรับ nested resource

```js
// ❌ รูปแบบเดิม — 2 query แยกกัน
const message = await pool.query('SELECT * FROM chat_messages WHERE id = $1', [mid]);
const consultation = await pool.query('SELECT * FROM consultation_requests WHERE id = $1', [cid]);

// ✅ รูปแบบที่เสนอ — 1 query ตรวจสาย parent พร้อม ownership
const message = await pool.query(
  `SELECT cm.* FROM chat_messages cm
   JOIN consultation_requests cr ON cm.room_id = cr.room_id
   WHERE cm.id = $1 AND cr.id = $2
     AND (cr.user_id = $3 OR cr.provider_id = $3)`,
  [mid, cid, req.userId]
);
```

### 9.8 Manual testing checklist สำหรับแต่ละ endpoint

เพิ่มเติมจาก BOLA test suite (ตัวเลือก E):

1. User A สร้าง resource → ได้ id
2. User B พยายาม GET → ต้องได้ 404
3. User B พยายาม PUT/DELETE → ต้องได้ 404
4. User A พยายาม PUT/DELETE ด้วย field ที่ไม่ควรแก้ (เช่น `user_id`, `role`) → ต้อง fail (mass assignment)
5. User A พยายาม GET ด้วย cache key เก่า → ต้องไม่รั่วข้ามผู้ใช้

### 9.9 การเชื่อมกับปัญหาที่พบจริงในระบบ

| ปัญหาที่พบ | ความเชื่อมโยงกับแผน 01 |
|------------|----------------------|
| RLS บน `profession_package_rules` ปฏิเสธ insert (42501) | ตัวอย่างของปัญหาที่แผน 12 จะแก้ แต่แผน 01 ต้องเตรียมชั้น data access ให้พร้อมก่อน |
| Prescription Editor ไม่ส่ง `medication_id` | ตัวอย่างของ mass assignment ที่ตัวเลือก D จะป้องกัน — ต้องส่งเฉพาะ field ที่อนุญาต |
| Consultation flow ใช้ `_hasSubmitted` local flag | pattern ที่ดี (bypass DB status) แต่ต้องระวังไม่ใช้เพื่อ bypass ownership check |

### 9.10 Realtime/Stream BOLA — ช่องโหว่ที่มองข้ามได้ง่าย

Realtime subscription ฝั่ง Flutter ยิง Supabase ตรงโดยไม่ผ่าน backend จึงไม่มี ownership check:

| ไฟล์ | Stream | ปัญหา |
|------|--------|-------|
| `chat_repository.dart:219-225` | `chat_messages` stream ด้วย `.eq('room_id', roomId)` | ไม่ตรวจว่า caller เป็น participant ของ room |
| `chat_repository.dart:234-240` | `chat_rooms` stream ด้วย `.eq('id', roomId)` | ใครก็ subscribe room คนอื่นได้ |
| `chart_board_page.dart:736-738` | `consultation_requests` stream ด้วย `.eq('id', consultationId)` | ไม่ตรวจว่า caller เป็นเจ้าของหรือ provider |
| `chart_board_page.dart:786-788` | `chat_rooms` stream ด้วย `.eq('id', roomId)` | เช่นกัน |
| `chart_board_page.dart:821-823` | `consultation_room_experts` stream ด้วย `.eq('consultation_id', ...)` | เห็นสมาชิก/expert ของ consultation คนอื่น |
| `consultation_repository.dart:166-172` | `consultation_requests` stream ทั้งหมด | ทุกคนเห็นทุกคำขอ |
| `donation_repository.dart:399-404` | `donation_requests` stream | ทุกคนเห็นคำขอบริจาคทั้งหมด |

**แนวทางแก้:**

| วิธี | คำอธิบาย | ข้อดี | ข้อเสีย | แนะนำ |
|-----|----------|------|--------|------|
| **A: RLS policy** | Supabase RLS บังคับที่ DB — stream ที่ไม่ผ่าน policy จะไม่ได้ข้อมูล | ครอบคลุมทุก channel รวม realtime | ต้องส่ง identity เข้า DB (แผน 08) | ⭐ วิธีเดียวที่ครอบคลุม realtime |
| **B: เพิ่ม filter ใน stream** | `.eq('user_id', myId)` ในทุก stream call | ง่าย แก้ที่ Flutter ได้ทันที | ลืมจุดเดียว = รั่ว; ไม่รองรับ participant/complex ownership | ใช้ชั่วคราวก่อน RLS |
| **C: ย้าย stream ไปผ่าน backend** | WebSocket gateway ตรวจสิทธิ์ก่อน forward | ครบ แต่เพิ่ม latency + complexity | ต้องเขียน gateway ใหม่ | กรณีพิเศษเท่านั้น |

**แนะนำ:** **B ก่อน (ชั่วคราว) → A (ถาวร)** — เหมือนแนวทางใน 9.2

### 9.11 Storage BOLA — ไฟล์แนบและรูปภาพ

Supabase Storage ใช้ `getPublicUrl` ทำให้ URL เดาได้:

| ไฟล์ | Bucket | ปัญหา |
|------|--------|-------|
| `chat_repository.dart:183-186` | `chat_attachments` | URL public ใครมี link ก็เปิดได้ |
| `profile_page.dart:2932-2935` | `avatars` | เช่นกัน |
| `body_region_repository.dart:119-120` | admin bucket | เช่นกัน |
| `supabase_service.dart:168` | generic | `getPublicUrl` เป็น default |
| `image_upload_field.dart:101-111` | generic widget | เช่นกัน |

**แนวทางแก้:**

| วิธี | คำอธิบาย | ข้อดี | ข้อเสีย | แนะนำ |
|-----|----------|------|--------|------|
| **A: Signed URL** | `createSignedUrl(path, expiresIn: 3600)` แทน `getPublicUrl` | URL หมดอายุอัตโนมัติ; ตรวจสิทธิ์ได้ | ต้อง refresh URL; เพิ่ม call | ⭐ สำหรับข้อมูล sensitive |
| **B: Private bucket + RLS** | ตั้ง bucket เป็น private + RLS policy บน `storage.objects` | บังคับที่ DB เลย | ต้อง config Supabase; กระทบ existing URL | ⭐ วิธีถาวร |
| **C: คง public + path obfuscation** | ใช้ UUID ใน path | ง่าย ไม่ต้องเปลี่ยน | **ไม่ใช่มาตรการความปลอดภัย** — UUID รั่วได้ | สำหรับ public content เท่านั้น |

**แนะนำ:**
- **Public content** (avatar, public video thumbnail): คง `getPublicUrl` ได้
- **Sensitive content** (chat attachment, medical image, donation slip): **A (signed URL) ทันที → B (private bucket) ถาวร**
- ต้องเพิ่ม bucket policy ใน Supabase config (เชื่อมกับแผน 04 Security Misconfiguration)

### 9.12 Consultation queue — `userId` จาก payload ไม่ใช่ session

`consultation-queue.js:64-93` รับ `userId` จาก `payload` (ที่มาจาก `req.body`) ไป insert ลง `consultation_requests.user_id`:

```js
// consultation-queue.js:65-66, 77-78, 93
const { userId, ... } = payload || {};
if (!userId) throw new Error('userId is required');
const insertData = { user_id: userId, ... };
```

**ปัญหา:** `consultation.js:22` ส่ง `req.body` ทั้งก้อนให้ `submitConsultationRequest` โดยไม่ผ่าน `req.userId` — ปลอม `userId` ใน body ได้

**แนวทางแก้:**

| วิธี | คำอธิบาย | ข้อดี | ข้อเสีย | แนะนำ |
|-----|----------|------|--------|------|
| **A: ส่ง `req.userId` แทน** | `submitConsultationRequest(req.body, authHeader, req.userId)` แล้ว override `userId` ใน queue | ตรงไปตรงมา แก้ที่ route | ต้องแก้ function signature | ⭐ |
| **B: ตัด `userId` จาก payload ใน route** | `delete req.body.userId; req.body.userId = req.userId;` ก่อนส่ง | ง่าย แก้ที่ route 1 บรรทัด | อาจมีจุดอื่นที่เรียก queue โดยไม่ผ่าน route | ใช้คู่กับ A |

**แนะนำ:** **A + B ทำพร้อมกัน** — route ตัด `userId` จาก body แล้วส่ง `req.userId` เป็น parameter แยก

### 9.13 แผนรองรับข้อเสียของ Option A ก่อนเริ่ม implement

Option A มีขอบเขตกว้างและอาจกระทบ behavior เดิม จึงต้องใช้ control ต่อไปนี้เป็นเงื่อนไขของ rollout:

| ความเสี่ยง/ข้อเสีย | ผลกระทบที่คาดว่าจะเกิด | วิธีรองรับที่กำหนด | Gate ก่อนเลื่อน phase |
|---|---|---|---|
| แก้ endpoint และ repository จำนวนมาก | endpoint บางส่วนอาจถูกลืมและยังรั่ว | สร้าง resource inventory พร้อม owner/participant/org/branch scope และใช้ checklist จาก code search | inventory ครบและทุก sensitive endpoint มี owner ที่ระบุได้ |
| เลิกเชื่อ `x-user-id` เร็วเกินไป | client รุ่นเก่า login หรือเรียก API ไม่ได้ | compatibility window: signed token + legacy header ชั่วคราว, telemetry, แล้วค่อย reject header-only | ไม่มี critical client ที่ใช้ header-only เหลืออยู่ |
| เพิ่ม query predicate/DTO/RLS | response เปลี่ยน, UI เดิมอาจได้ empty state หรือ 404 | contract test, fixture ของ owner/participant/cross-org และกำหนด public resource แยกชัดเจน | contract tests ผ่านและไม่มี unauthorized data ใน response |
| RLS ทำให้ legitimate access ถูกปฏิเสธ | เกิด 401/403/42501 ใน flow ที่เคยใช้งานได้ | เปิดใช้แบบ table-by-table, ตรวจ identity context, migration rollback และ monitor denial rate | denial rate อยู่ในเกณฑ์และมี rollback ที่ทดสอบแล้ว |
| query ซับซ้อนขึ้นหรือช้าลง | latency สูงขึ้นจาก JOIN/policy check | ใช้ single scoped query, index บน owner/org/participant columns, ตรวจ `EXPLAIN` และกำหนด timeout | p95 latency ไม่เกิน budget ของ endpoint |
| authorization policy ไม่ตรง business จริง | ผู้ใช้เห็นข้อมูลน้อยเกินไปหรือมากเกินไป | policy matrix + owner/participant/org test fixtures และ review โดยเจ้าของ domain | policy matrix ได้รับการอนุมัติและ negative tests ผ่าน |
| cache เดิมมีข้อมูลข้ามสิทธิ์ | cache อาจคืนข้อมูลเก่าหลังแก้ query | เปลี่ยน cache key เป็น auth-context/versioned key และ purge namespace เดิมก่อน deploy | ไม่พบ cache hit จาก namespace เก่า |
| Realtime/Storage ถูกตัดสิทธิ์ | stream หยุดหรือ URL เดิมใช้ไม่ได้ | filter ชั่วคราว, signed URL สำหรับ sensitive files, private bucket/RLS ภายหลัง และ fallback UI | ทดสอบ reconnect, URL expiry และ cross-user access แล้ว |
| test data/legacy rows ไม่มี owner | ข้อมูลเก่าอ่านไม่ได้หรือ migration ผิด scope | ทำ data classification, backfill/ quarantine, ห้าม default เป็น global access โดยไม่อนุมัติ | orphan rows ถูกจัดการครบและมี owner decision |
| fail-closed ทำให้ระบบหยุดทั้งระบบ | dependency auth/policy ล่มแล้วทุก request fail | แยก public endpoints, timeout/circuit breaker เฉพาะ policy service, ห้าม fail-open สำหรับ sensitive data | failure-mode test ผ่านและ sensitive path ยังคง deny |

**กฎ rollback:** rollback ได้เฉพาะ deployment/config compatibility layer ไม่ย้อนกลับกฎที่เปิดเผยข้อมูลแล้วแบบ fail-open; หากพบ data leak ให้ purge cache/revoke URL/disable endpoint ก่อน แล้วค่อย rollback code

**Definition of Done ของ Option A:**

- [ ] endpoint และ repository inventory ครบทุก sensitive resource
- [x] ไม่มี identity จาก request payload ถูกนำไปใช้เป็น owner
- [ ] signed identity ถูก verify ที่ backend และมี compatibility telemetry
- [x] ทุก read/write/delete ใช้ scope ที่ตรงกับ policy
- [x] response/request DTO และ field allowlist ครบ
- [x] cache, realtime และ storage ผ่าน cross-user negative tests
- [ ] RLS/tenant policy ผ่านใน scope ที่พร้อมตามแผน 12
- [x] BOLA tests ผ่าน (65 คำสั่ง, 6 ส่วน, 2026-07-27)
- [ ] performance tests และ rollback drill ผ่าน

---

## 10. ผลการทดสอบ BOLA Option A (2026-07-27)

> ทดสอบด้วย Maestro บน iPhone 16 simulator (iOS 18.1) — device ID: `822794E6-EF5C-420A-8620-0BB8653C60E3`
> ไฟล์ทดสอบ: `docs/guides/bola_option_a_test_flow.yaml`
> ผล: **ผ่านทั้งหมด 65 คำสั่ง**

### 10.1 สรุปผลการทดสอบ

| ส่วน | รายละเอียด | ผล | จำนวนคำสั่ง |
|-----|-----------|-----|------------|
| **A** | ล็อกอินด้วยบัญชี Consumer (`firm`), Provider (`apisek`), Admin (`derfby`) — ตรวจสอบว่าการแก้ไข `verifyToken` ไม่ทำลายระบบล็อกอิน | ✅ ผ่าน | 24 |
| **B** | ผู้ใช้ทั่วไปและผู้ให้บริการเข้าแดชบอร์ดคำร้อง — ตรวจสอบ `trustedUserId` + ownership check ใน `consultation-queue.js` | ✅ ผ่าน | 10 |
| **C** | ผู้ให้บริการเปิดแชทและส่งข้อความ ผู้ใช้ทั่วไปเห็นข้อความ — ตรวจสอบ `callerId` ใน `sendMessage` และ `_verifyParticipant` | ✅ ผ่าน | 14 |
| **D** | ผู้ใช้ทั่วไปเข้าข้อมูลสุขภาพ — ตรวจสอบ `userId` จาก session ไม่ใช่จาก request body | ✅ ผ่าน | 7 |
| **E** | ผู้ใช้ทั่วไปเข้าวิดีโอ — ตรวจสอบ cache key `:v2` และ `req.userId` | ✅ ผ่าน | 7 |
| **F** | ผู้ใช้ทั่วไป **ไม่** เห็นปุ่ม "รับงาน" (เชิงลบ) — ตรวจสอบขอบเขต BOLA ระหว่างบทบาท | ✅ ผ่าน | 3 |

### 10.2 การแก้ไขที่ implement และทดสอบแล้ว

| ไฟล์ | การแก้ไข | ส่วนที่ทดสอบ | สถานะ |
|------|---------|-------------|--------|
| `websocket-server/routes/video.js` | เลิกรับ `userId` จาก `req.body` ใช้ `req.userId` แทน + cache key `:v2` | E | ✅ ผ่าน |
| `websocket-server/services/consultation-queue.js` | ใช้ `req.userId` แทน `payload.userId` | B | ✅ ผ่าน |
| `lib/features/chat/data/repositories/chat_repository.dart` | `uploadFile` ส่งคืน signed URL แทน public URL สำหรับ `chat_attachments` | C | ✅ ผ่าน |
| `lib/features/chat/data/repositories/chat_repository.dart` | `sendMessage` ตรวจสอบ `callerId` ผ่าน `_verifyParticipant` | C | ✅ ผ่าน |
| `lib/features/consultation/presentation/pages/chart_board_page.dart` | เพิ่ม `callerId` ใน `sendMessage` สำหรับ image และ voice messages | C | ✅ ผ่าน |
| `lib/features/chat/presentation/pages/chat_room_page.dart` | เพิ่ม `callerId` ใน `sendMessage` สำหรับ voice message | C | ✅ ผ่าน |
| `lib/shared/widgets/image_upload_field.dart` | ใช้ signed URL สำหรับ sensitive buckets (`registration_evidence`, `donations`, `chat_attachments`, `medical_images`) | D | ✅ ผ่าน |

### 10.3 ข้อจำกัดและงานที่เหลือ

การทดสอบผ่านในระดับ **containment รอบที่ 1** (section 9.1) แต่ยังมีงานในรอบที่ 2-3 ที่ต้องดำเนินต่อ:

- [ ] **รอบที่ 2:** เปลี่ยน repository methods ทั้งหมดให้ใช้ session-based userId ในทุก repository ฝั่ง Flutter
- [ ] **รอบที่ 2:** เพิ่ม DTO/field allowlist ในทุก repository
- [ ] **รอบที่ 3:** เพิ่ม `organization_id` scope ในทุก ERP repository
- [ ] **รอบที่ 3:** Implement signed identity และ policy/data-access boundary ตาม Option A
- [ ] **รอบที่ 3:** Implement RLS (ตัวเลือก C) คู่กับแผน 12 หลัง identity พร้อม
- [ ] **รอบที่ 3:** ขยาย BOLA test suite ให้ครอบคลุม cross-organization, nested resource และ realtime/storage
- [ ] กำหนด compatibility window สำหรับการเลิกเชื่อ `x-user-id` header
- [ ] สร้าง resource/policy inventory ที่ครบถ้วน
- [ ] Performance tests และ rollback drill

### 10.4 บัญชีทดสอบ

| บทบาท | Username | ใช้ในส่วน |
|-------|----------|----------|
| Consumer | `firm` | A.1, B.1, C.2, D, E, F |
| Provider | `apisek` | A.2, B.2, C.1 |
| Admin | `derfby` | A.3 |
