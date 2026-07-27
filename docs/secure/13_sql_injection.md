# แผนป้องกัน 13: SQL Injection

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P1 (regression control)
> **เกี่ยวข้องกับแผน:** 11 (Input Validation), 12 (Least Privilege)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S1 ลำดับ 1** ในรูปแบบ regression control ไม่ใช่ blocker ก่อนแก้ช่องโหว่ที่มีหลักฐานชัดกว่า
> **เหตุผล:** การตรวจสอบปัจจุบันพบการใช้ parameterized query สม่ำเสมอ จึงควรเน้น lint/code review สำหรับ dynamic identifiers, migration และ raw query ใหม่ แทนการเปลี่ยน data access layer ทั้งหมด

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่ทำได้ดีอยู่แล้ว ✅

| จุด | รายละเอียด |
|-----|------------|
| **websocket-server ใช้ parameterized query สม่ำเสมอ** | ทุก `pool.query()` ที่ตรวจสอบใช้ placeholder `$1, $2, ...` ไม่มีการต่อ string |
| **Supabase PostgREST client** | `.from().select().eq()` สร้าง query อย่างปลอดภัยโดย library ไม่ใช่ string concatenation |
| **Dart type safety** | ค่าที่ส่งเข้า query ผ่าน typed parameter |

ตัวอย่างที่ถูกต้อง:
```js
// websocket-server/middleware/auth.js
await pool.query('SELECT id, is_active, role FROM users WHERE id = $1', [rawId]);

// websocket-server/routes/admin.js
await pool.query(
  `UPDATE watermark_configs SET is_enabled = $1, type = $2, ... WHERE id = 1 RETURNING *`,
  [is_enabled, type, ...]
);
```

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| S1 | **ไม่มีกลไกป้องกันการถดถอย** | 🟡 กลาง | ไม่มี lint rule / CI check — โค้ดใหม่อาจใช้ string concatenation โดยไม่มีใครสังเกต |
| S2 | **Dynamic ORDER BY / filter** | 🟡 กลาง | ระบบ ERP ที่กำลังจะสร้าง (report, dashboard, KPI) มักต้องการ column/direction แบบ dynamic — จุดนี้ parameterize ไม่ได้ |
| S3 | **Supabase `.or()` / `.filter()` รับ raw string** | 🟡 กลาง | `.or('username.eq.X,phone.eq.X')` — ถ้า X มาจาก user input โดยตรงอาจแทรก filter เพิ่มได้ |
| S4 | **PL/pgSQL function ที่ใช้ EXECUTE** | 🟡 กลาง | ถ้ามี/จะมี dynamic SQL ใน function ต้องใช้ `format()` + `%I`/`%L` |
| S5 | **DB user มีสิทธิ์กว้าง** | 🟡 กลาง | ถ้า injection สำเร็จ ผลกระทบจะรุนแรงเพราะสิทธิ์ไม่จำกัด (ดูแผน 12) |
| S6 | **Error message เปิดเผยโครงสร้าง DB** | 🟢 ต่ำ | บาง route ส่ง `err.message` กลับไปหา client |
| S7 | **ไม่มี query logging/monitoring** | 🟢 ต่ำ | ตรวจจับพฤติกรรมผิดปกติไม่ได้ |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว

| ระบบ | ชั้นที่เข้าถึง DB | ความเสี่ยง | หมายเหตุ |
|------|-----------------|-----------|----------|
| Auth & Registration | Supabase client (`.eq()`, `.or()`) | 🟡 ต้องตรวจ `.or()` ใน `login()` | `user_repository.dart` ใช้ parallel query |
| Consultation | Supabase client | 🟢 | ใช้ `.eq()` เป็นหลัก |
| Chat & Video | Supabase + `pool.query` (video routes) | 🟢 | parameterized ครบ |
| Pharmacy & Drug Risk | Supabase client + RPC | 🟢 | ตรวจ RPC function ว่าไม่มี dynamic EXECUTE |
| Donation + Escrow | `pool.query` | 🟢 | parameterized ครบ |
| Emergency & Rescue | Supabase + socket service | 🟢 | |
| Health & Articles | Supabase client | 🟢 | |
| Admin & KPI | `pool.query` (admin routes) | 🟢 | มี `requireRole('admin')` ป้องกันชั้นแรก |

### 2.2 ระบบตามแผน — จุดเสี่ยงที่ต้องออกแบบล่วงหน้า

| แผน | จุดเสี่ยง |
|-----|----------|
| `docs/ERP/KPI_DASHBOARD_PLAN.md` | 🔴 **Dynamic aggregate query** — เลือก metric/dimension/period ตาม config → ต้องใช้ allowlist เข้ม |
| `docs/ERP/ACCOUNTING_SYSTEM_PLAN.md` | Report builder, GL query ตาม account range/period — dynamic WHERE |
| `docs/ERP/CRM_SYSTEM_PLAN.md` | Customer segmentation / dynamic filter builder |
| `docs/ERP/INVENTORY_SYSTEM_PLAN.md` | Stock report ตาม dimension ที่ผู้ใช้เลือก |
| `docs/ERP/PROCUREMENT_SYSTEM_PLAN.md` | `ProcurementReportPage` — export/filter แบบ dynamic |
| `docs/ERP/HR_SYSTEM_PLAN.md` | Payroll report, employee search แบบหลายเงื่อนไข |
| `docs/ERP/ERP_CORE_ARCHITECTURE.md` | Multi-tenant — `organization_id` ต้อง**บังคับ**ทุก query ไม่ให้หลุด |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | Video search/filter หลายเงื่อนไข |
| `docs/infrastructure/caching_strategy.md` | Cache key สร้างจาก query params — ต้อง sanitize ไม่ให้ collide ข้าม tenant |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Query Builder + Allowlist สำหรับ Dynamic SQL (แนะนำ) ⭐

```js
// websocket-server/utils/safe-query.js
const SORTABLE_COLUMNS = {
  videos: ['created_at', 'title', 'view_count'],
  gl_entries: ['entry_date', 'amount', 'account_code'],
};

function safeOrderBy(table, column, direction) {
  const allowed = SORTABLE_COLUMNS[table] || [];
  const col = allowed.includes(column) ? column : allowed[0];
  const dir = direction?.toUpperCase() === 'ASC' ? 'ASC' : 'DESC';
  return `ORDER BY ${col} ${dir}`;   // ปลอดภัยเพราะมาจาก allowlist เท่านั้น
}
```

หรือใช้ library: `knex` / `kysely` (มี identifier escaping ในตัว)

**ข้อดี**
- แก้ปัญหา S2 ซึ่งเป็นจุดเสี่ยงหลักของ ERP ที่กำลังจะสร้าง
- Allowlist บังคับให้คิดถึง column ที่เปิดให้ sort/filter ได้ (ดีต่อ least privilege ด้วย)
- ไม่กระทบโค้ดเดิมที่ปลอดภัยอยู่แล้ว

**ข้อเสีย**
- ต้องดูแล allowlist ให้ทันเมื่อเพิ่ม column
- ถ้าใช้ query builder เต็มรูป = refactor ใหญ่

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Static Analysis + CI Gate

```yaml
# .github/workflows/security.yml
- name: SQL Injection Lint
  run: |
    npx eslint websocket-server --rule 'security/detect-sql-injection: error'
    # ตรวจหา template literal ที่มี ${} ภายใน query
    ! grep -rnE 'pool\.query\(`[^`]*\$\{' websocket-server/
```

เพิ่ม `eslint-plugin-security` + custom rule

**ข้อดี**
- ป้องกันการถดถอย (S1) อัตโนมัติ ต้นทุนต่ำมาก
- ทำได้ภายใน 1–2 วัน

**ข้อเสีย**
- False positive/negative มีบ้าง
- ไม่แก้ปัญหา dynamic SQL ที่จำเป็นจริง ๆ (S2)

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **ควรทำแน่นอน ต้นทุนต่ำ ผลตอบแทนสูง**

---

### ตัวเลือก C: Stored Procedures เท่านั้น

บังคับให้ทุก write operation ผ่าน PostgreSQL function

**ข้อดี:** ควบคุมได้เต็มที่; รวม validation + business rule; app user ไม่ต้องมีสิทธิ์ตารางตรง
**ข้อเสีย:** พัฒนาช้า; version control/migration ยุ่งยาก; test ลำบาก; ทีมต้องเชี่ยว PL/pgSQL
**ความเหมาะสมระยะยาว:** ⭐⭐ — ไม่เหมาะกับความเร็วการพัฒนาที่ Sheserved ต้องการ

---

### ตัวเลือก D: DB Least Privilege (Defense in Depth)

```sql
CREATE ROLE app_readonly;
CREATE ROLE app_readwrite;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
GRANT SELECT, INSERT, UPDATE ON specific_tables TO app_readwrite;
-- ไม่ให้ DROP, TRUNCATE, ALTER
REVOKE ALL ON SCHEMA pg_catalog FROM app_readwrite;
```

**ข้อดี:** จำกัดผลกระทบถ้ามีช่องโหว่หลุดรอด; สอดคล้องกับแผน 12
**ข้อเสีย:** ต้องจัดการ role/permission เพิ่ม; migration ต้องใช้ role แยก
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ควรทำร่วมกับแผน 12

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **B (ทำทันที) + A (ก่อนเริ่ม ERP report) + D (ร่วมแผน 12)** | สถานะปัจจุบันดีอยู่แล้ว — เน้นรักษาระดับ + เตรียมรับ dynamic query ของ ERP |
| 2 | **B อย่างเดียว** | ถ้ายังไม่เริ่ม ERP report ในระยะสั้น |
| 3 | **A + B + C เฉพาะ operation การเงิน** | ถ้าต้องการความมั่นใจสูงสุดสำหรับ accounting/escrow |
| 4 | **C ทั้งระบบ** | ไม่แนะนำ — ต้นทุนสูงเกินประโยชน์ |

---

## 5. กฎการเขียน Query ที่เสนอ (Sheserved SQL Standard)

```
✅ ทำได้
  pool.query('SELECT * FROM users WHERE id = $1', [userId])
  supabase.from('users').select().eq('id', userId)
  supabase.rpc('get_user_stats', { p_user_id: userId })
  `ORDER BY ${safeOrderBy('videos', req.query.sort, req.query.dir)}`

❌ ห้าม
  pool.query(`SELECT * FROM users WHERE id = '${userId}'`)
  pool.query('SELECT * FROM ' + tableName)
  supabase.or(`username.eq.${rawInput}`)          // ต้อง escape ก่อน
  EXECUTE 'SELECT * FROM ' || table_name;         // ใน PL/pgSQL ใช้ format('%I') แทน

📋 กฎเสริม
  1. Table/column name ที่เป็น dynamic → allowlist เท่านั้น ห้าม parameterize
  2. LIMIT/OFFSET → parseInt + clamp ช่วงค่า
  3. IN (...) → ใช้ = ANY($1) พร้อม array แทนการต่อ string
  4. LIKE pattern → escape %, _ ก่อนใช้
  5. PL/pgSQL dynamic SQL → format() + %I (identifier) / %L (literal) เสมอ
  6. Error ที่ส่งกลับ client → ข้อความทั่วไป, log รายละเอียดฝั่ง server เท่านั้น
```

### จุดที่ต้อง audit เป็นพิเศษ
- [ ] `user_repository.dart` — การใช้ `.or()` ใน `login()`
- [ ] ทุก `supabase.rpc()` — ตรวจ function body ว่าไม่มี dynamic EXECUTE ที่ไม่ปลอดภัย
- [ ] `websocket-server/routes/*.js` — grep หา template literal ใน query
- [ ] Migration scripts — ตรวจว่าไม่รับ input จากภายนอก

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/infrastructure/SETUP_DATABASE_SERVER.md` | ตัวเลือก D ต้องเพิ่มขั้นตอนสร้าง DB role แยก |
| `docs/infrastructure/caching_strategy.md` | Cache key ต้อง sanitize + prefix ด้วย tenant/user |
| `docs/ERP/KPI_DASHBOARD_PLAN.md` | ต้องระบุ allowlist ของ metric/dimension ในแผนนั้นด้วย |
| `docs/ERP/ERP_CORE_ARCHITECTURE.md` | Multi-tenant scoping ต้องบังคับที่ query builder ไม่ใช่ที่ caller |
| `docs/guides/TEST_PLAN.md` | ควรเพิ่ม scenario SEC-06: SQL injection attempt → ต้องได้ 400 ไม่ใช่ 500 |

---

## 7. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติการเพิ่ม ESLint security rule + CI gate (แนะนำ: ใช่ ต้นทุนต่ำ)
- [ ] ตัดสินใจว่าจะใช้ query builder (`knex`/`kysely`) หรือเขียน allowlist helper เอง
- [ ] กำหนด allowlist ของ sortable/filterable columns ต่อตาราง
- [ ] ตัดสินใจเรื่อง DB role แยกสิทธิ์ (ร่วมกับแผน 12)
- [ ] Audit จุดที่ระบุใน section 5 ก่อนตัดสินใจขอบเขตงาน
