# แผนป้องกัน 01: Broken Object Level Authorization (BOLA / IDOR)

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** 09 (AuthN/AuthZ — ระดับ route/role), 12 (Least Privilege — ระดับ permission), 11 (Input Validation)
> **ความแตกต่างจากแผน 09/12:** แผน 09 ตอบว่า *"ผู้ใช้คนนี้เข้า endpoint นี้ได้ไหม"* · แผน 12 ตอบว่า *"มี permission อะไรบ้าง"* · **แผนนี้ตอบว่า "object ชิ้นนี้เป็นของเขาจริงหรือไม่"** ซึ่งเป็นคนละชั้นและ OWASP จัดเป็นช่องโหว่อันดับ 1 ของ API
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-A ลำดับ 1** เป็น containment แรก ก่อนการ refactor authentication ครั้งใหญ่
> **เหตุผล:** มีหลักฐานว่า endpoint รับ `userId` จาก request body ทั้งที่มี `req.userId` แล้ว จึงแก้ได้ทันทีด้วย ownership-scoped query และการตัด field ที่ client ควบคุมได้ โดยไม่ต้องรอ JWT migration

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

### ตัวเลือก A: Ownership-Scoped Query (แนะนำ) ⭐

**หลักการ:** ไม่ query ด้วย ID อย่างเดียว แต่ query ด้วย ID **+ เงื่อนไขความเป็นเจ้าของ** ในคำสั่งเดียว

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
- Atomic — ไม่มี race condition ระหว่าง check กับ act
- ไม่ต้องเพิ่ม dependency
- ทำทีละ endpoint ได้ (rollout แบบค่อยเป็นค่อยไป)

**ข้อเสีย**
- ต้องแก้ทุก endpoint (~100+) และทุก repository ฝั่ง Flutter ที่ยิง Supabase ตรง
- ลืมจุดเดียว = ยังรั่ว → ต้องมี checklist + code review

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
| 1 | **A (เลิกใช้ body userId + scoped query) → D → E → C ร่วมกับแผน 12** | แก้ต้นเหตุก่อน แล้วเพิ่มตาข่ายนิรภัยและ test |
| 2 | **A + B + E** | ถ้าต้องการความชัดเจนที่ระดับ route definition |
| 3 | **C (RLS) เป็นหลัก + A สำหรับ INSERT** | ถ้าตัดสินใจทำ RLS ครบตามแผน 12 อยู่แล้ว |
| 4 | **B อย่างเดียว** | ไม่พอ — ไม่ครอบคลุม list endpoint และ Supabase ตรง |

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

## 8. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติกฎ 10 ข้อ (section 5) เป็นมาตรฐานของโปรเจกต์
- [ ] เลือกแนวทาง: scoped query (A) / middleware (B) / RLS (C) / ผสม
- [ ] ตัดสินใจนโยบาย 403 vs 404 (แนะนำ: 404 เป็นค่าเริ่มต้น)
- [ ] อนุมัติการเพิ่ม DTO/field allowlist (D)
- [ ] ตัดสินใจว่าจะเพิ่ม BOLA test suite (E) หรือไม่
- [ ] กำหนดลำดับ endpoint ที่จะแก้ก่อน (แนะนำ: health → consultation → chat → donation → video)
- [ ] ตัดสินใจว่าจะแก้ `auth_data_guidelines.md` เพื่อระบุกฎ "server ไม่เชื่อ client identity" หรือไม่
