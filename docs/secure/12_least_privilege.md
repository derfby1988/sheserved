# แผนป้องกัน 12: Principle of Least Privilege

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-C
> **เกี่ยวข้องกับแผน:** 09 (AuthN/AuthZ), 13 (SQL Injection), 07 (Secrets)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-C ลำดับ 1** หลัง signed identity และ server authorization พร้อมใช้งานจริง
> **เหตุผล:** RLS/tenant/branch policy ต้องอาศัย identity ที่ verify แล้ว; ให้ rollout เป็นกลุ่มตารางและทดสอบ deny/allow matrix ก่อน ไม่เปิด RLS ครบทุกตารางแบบ migration เดียว เพราะอาจทำให้ flow ที่ใช้งานอยู่ล้มเหลวหรือเกิด bypass ผ่าน service role

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่มีอยู่แล้ว ✅

| ระดับ | สิ่งที่ implement | ไฟล์/ตำแหน่ง |
|------|------------------|-------------|
| Application role | `consumer` / `provider` / `admin` ใน `users.role` | `UserModel`, migrations |
| Category attributes | `user_categories.is_consumer` / `is_provider` เป็น source of truth + sync trigger | `role_management_refactor_plan.md` Phase 2 (เสร็จแล้ว) |
| Route guard | `AuthGuardWidget(requiredRole:)` | `lib/core/guards/auth_guard_widget.dart` |
| Backend RBAC | `requireRole('admin')` บน admin routes | `websocket-server/middleware/auth.js` |
| Domain permission | `can_manage_drug_risk`, `unblurred_profession_ids` | `UserModel`, drug risk plan |
| Group roles | `user_group_roles` table | `GroupRoleRepository` |
| ERP permission pages | `PermissionManagementPage`, `RoleManagementPage`, `MyPermissionsPage`, `EmployeeRoleAssignmentPage` | ERP pages (UI พร้อม) |
| Feature flags | `FeatureFlagsPage` | ERP HR |

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| L1 | **Role หยาบเกินไป** | 🔴 สูง | `admin` เดียวเข้าถึงได้ทุกอย่าง — payroll, GL, patient data, platform settings |
| L2 | **RLS ไม่ครบทุกตาราง** | 🔴 วิกฤต | anon key + RLS ไม่ครบ = client เข้าถึงข้อมูลที่ไม่ควรเห็นได้ (เชื่อมโยงกับแผน 07 K2) |
| L3 | **DB user มีสิทธิ์เต็ม** | 🟡 กลาง | `websocket-server` เชื่อม DB ด้วย user เดียวที่มีสิทธิ์ทุกตาราง ทุก operation |
| L4 | **ไม่มี multi-tenant isolation บังคับ** | 🔴 สูง | ERP ต้องแยก `organization_id` — ถ้าลืม filter ในโค้ดเดียว = ข้อมูลข้ามองค์กร |
| L5 | **ไม่มี branch-level scoping** | 🟡 กลาง | ERP หลายสาขา — พนักงานสาขา A ไม่ควรเห็นข้อมูลสาขา B |
| L6 | **Supabase Storage bucket policy** | 🟡 กลาง | ต้องยืนยันว่าไฟล์ (เอกสารสมัคร, ภาพผู้ป่วย, สลิป) ไม่เป็น public |
| L7 | **ไม่มี field-level permission** | 🟡 กลาง | HR: บาง field (เงินเดือน, เลขบัตรประชาชน) ควรเห็นเฉพาะบางคน |
| L8 | **ไม่มี time-bound / just-in-time access** | 🟢 ต่ำ | Break-glass access สำหรับ clinical emergency |
| L9 | **ไม่มี separation of duties** | 🟡 กลาง | Accounting: คนสร้าง PO ไม่ควรอนุมัติ PO เอง |
| L10 | **ไม่มี permission audit** | 🟡 กลาง | ไม่รู้ว่าใครมีสิทธิ์อะไร เปลี่ยนเมื่อไหร่ ใครให้ |
| L11 | **Service account ไม่แยก** | 🟡 กลาง | Background job (escrow release, sync, queue) ใช้สิทธิ์เดียวกับ app |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว — สิทธิ์ที่ควรเป็น

| ระบบ | ใครควรเข้าถึงอะไร | สถานะปัจจุบัน |
|------|-------------------|--------------|
| **Auth** | ทุกคนอ่านโปรไฟล์ตัวเอง; admin จัดการ user | ไม่มี RLS บังคับ |
| **Consultation** | Provider เห็นเฉพาะเคสที่ตนรับ; consumer เห็นเคสตนเอง | client-side เท่านั้น |
| **Chat** | เฉพาะ participant ของห้อง | client-side เท่านั้น |
| **Video** | Public video ทุกคน; unblurred เฉพาะ profession ที่กำหนด; admin ทุกอย่าง | มี logic แต่บังคับที่ client |
| **Pharmacy Drug Risk** | Personal override: เจ้าของ; Org override: `can_manage_drug_risk` ในองค์กรนั้น; System: admin | permission model ดี ✅ แต่บังคับที่ UI |
| **Donation + Escrow** | ผู้บริจาคเห็นของตน; leader verify; admin approve; **escrow release ต้องแยก role** | admin รวมทุกอย่าง |
| **Emergency** | Volunteer/responder ในรัศมี; ผู้แจ้งเห็นของตน | filter ที่ client |
| **Health** | เจ้าของข้อมูล + ผู้ที่ได้รับ consent (`HealthDataPermissionRepository`) | model มี ✅ แต่ต้อง RLS |
| **Profile** | เจ้าของแก้ไขได้ | ไม่มี RLS |
| **Admin & KPI** | admin เท่านั้น | มี guard ✅ |

### 2.2 ระบบตามแผน `docs/ERP/` — ความต้องการเฉพาะ

| แผน | ความต้องการด้านสิทธิ์ |
|-----|---------------------|
| `ERP_CORE_ARCHITECTURE.md` | 🔴 **Multi-tenant** — ทุกตาราง ERP ต้องมี `organization_id` + RLS บังคับ |
| `HR_SYSTEM_PLAN.md` | 🔴 Payroll = ข้อมูลอ่อนไหวสูงสุด; field-level (เงินเดือนของคนอื่น); พนักงานเห็นข้อมูลตนเองเท่านั้น |
| `ACCOUNTING_SYSTEM_PLAN.md` | 🔴 Separation of duties: maker ≠ checker; period close เฉพาะ controller; GL immutable |
| `PROCUREMENT_SYSTEM_PLAN.md` | 🔴 Approval limit ตามวงเงิน; requester ≠ approver |
| `POS System_plan.md` | Cashier: ขายได้ แต่ refund ต้อง supervisor; ดูรายงานยอดขายเฉพาะกะตนเอง |
| `INVENTORY_SYSTEM_PLAN.md` | Stock adjust ต้อง approval; transfer ต้องยืนยันทั้งสองสาขา |
| `HIS_SYSTEM_PLAN.md` | 🔴 PHI — เข้าถึงเฉพาะผู้ให้การรักษาที่เกี่ยวข้อง; break-glass + audit |
| `LAB_SYSTEM_PLAN.md` | 🔴 ผล lab — technician บันทึก, pathologist อนุมัติ, แพทย์เจ้าของไข้ดู |
| `CRM_SYSTEM_PLAN.md` | Sales เห็นเฉพาะ territory/ลูกค้าของตน |
| `KPI_DASHBOARD_PLAN.md` | Aggregate ข้ามแผนกได้ แต่ห้าม drill-down ถึง row ที่ไม่มีสิทธิ์ |
| `ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | Feature access ตาม tier — บังคับฝั่ง server |
| `ERP_NOTIFICATION_SYSTEM_PLAN.md` | Notification ต้อง filter ตามสิทธิ์ผู้รับ (ห้ามรั่วข้อมูลผ่าน notification preview) |

### 2.3 ระบบตามแผน `docs/plans/`

| แผน | ความต้องการ |
|-----|------------|
| `Delivery_PLAN.md` | Courier เห็นที่อยู่เฉพาะออเดอร์ที่รับ และเฉพาะช่วงเวลาที่ส่ง (time-bound) |
| `DONATION_SYSTEM_PLAN.md` | แยก role: `donation_reviewer`, `donation_approver`, `escrow_releaser` |
| `VIDEO_SYSTEM_PLAN.md` | `unblurred_profession_ids` ต้องบังคับที่ server ไม่ใช่ blur ที่ client |
| `health_data_sync_plan.md` | Device token เข้าถึงได้เฉพาะ health data ของเจ้าของอุปกรณ์ |
| `CHAT_CONSULTATION_IMPROVEMENT_PLAN.md` | Quick reply template: personal vs organization scope |
| `DRUG_RISK_OVERRIDE_PLAN.md` | 3 ระดับ override — model ดีอยู่แล้ว ต้องบังคับที่ DB |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: RBAC + Permission Matrix ครบวงจร (แนะนำ) ⭐

```
users
  └─ user_roles (many-to-many)
       └─ roles
            └─ role_permissions (many-to-many)
                 └─ permissions   (เช่น 'erp.hr.payroll.read')

+ scope: organization_id, branch_id[] ต่อ role assignment
```

**Permission naming convention ที่เสนอ**
```
<domain>.<module>.<resource>.<action>[.<scope>]

ตัวอย่าง:
  core.user.profile.read.self
  core.user.profile.write.any
  erp.hr.payroll.read.own
  erp.hr.payroll.read.department
  erp.hr.payroll.approve
  erp.finance.gl.post
  erp.finance.period.close
  erp.inventory.stock.adjust
  erp.procurement.po.approve.under_100k
  erp.procurement.po.approve.unlimited
  clinical.emr.read.assigned
  clinical.emr.read.break_glass
  clinical.lab.result.approve
  donation.escrow.release
  drug_risk.override.personal
  drug_risk.override.organization
  drug_risk.override.system
  pos.refund.under_1000
  pos.refund.unlimited
```

**ข้อดี**
- ยืดหยุ่นครบทุกความต้องการที่วิเคราะห์ไว้
- ต่อยอดจาก `role_management_refactor_plan.md` Phase 3 ได้ตรง
- UI มีอยู่แล้ว (`PermissionManagementPage`, `RoleManagementPage`)
- Permission เข้า JWT claims ได้ (แผน 08)

**ข้อเสีย**
- ออกแบบ permission taxonomy ใช้เวลา (ประเมิน 2–3 สัปดาห์)
- Migration จาก role เดิม
- Permission list ยาว → ต้องมี UI จัดการที่ดี

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Row Level Security ครบทุกตาราง

```sql
ALTER TABLE consultation_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY consumer_own_requests ON consultation_requests
  FOR SELECT USING (user_id = current_user_id());

CREATE POLICY provider_assigned_requests ON consultation_requests
  FOR SELECT USING (provider_id = current_user_id());

CREATE POLICY org_isolation ON gl_entries
  FOR ALL USING (organization_id = current_org_id());
```

**ข้อดี**
- ✅ **บังคับที่ชั้นสุดท้าย** — client ยิง Supabase ตรงก็ข้ามไม่ได้; ปิด L2, L4 อย่างสมบูรณ์
- ป้องกันได้แม้โค้ดมี bug
- ทำงานได้ทั้ง Supabase และ local PostgreSQL

**ข้อเสีย**
- ต้องเขียน policy ~80+ ตาราง (งานใหญ่)
- Policy ซับซ้อนกระทบ performance (ต้อง index ให้ดี)
- ต้องมีวิธีส่ง identity เข้า DB (`current_setting('app.user_id')` หรือ JWT claims — แผน 08)
- Debug ยาก: "ทำไมไม่เห็นข้อมูล" → policy หรือ bug?

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **จำเป็นตราบใดที่ client ยังยิง Supabase ตรง**

---

### ตัวเลือก C: Backend Gateway เท่านั้น (ไม่ใช้ RLS)

Client ไม่แตะ DB ตรง — authorization ทั้งหมดอยู่ที่ backend

**ข้อดี:** ไม่ต้องเขียน RLS policy; logic authorization อ่านง่ายใน JS; test ง่าย
**ข้อเสีย:** ลืม check จุดเดียว = รั่ว; ไม่มีตาข่ายนิรภัย; ต้อง refactor ใหญ่ (แผน 09 ตัวเลือก A)
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ดี **ถ้ามี code review เข้มและ test ครบ**

---

### ตัวเลือก D: DB Role Separation

```sql
CREATE ROLE sheserved_app     LOGIN;  -- CRUD ปกติ
CREATE ROLE sheserved_readonly LOGIN; -- report/analytics
CREATE ROLE sheserved_worker   LOGIN; -- background job
CREATE ROLE sheserved_migrate  LOGIN; -- DDL เท่านั้น

GRANT SELECT, INSERT, UPDATE ON <tables> TO sheserved_app;
GRANT SELECT ON <tables> TO sheserved_readonly;
REVOKE DELETE ON audit_logs, gl_entries FROM sheserved_app;  -- immutable
```

**ข้อดี:** จำกัดผลกระทบเมื่อมีปัญหา; report query ใช้ readonly ไม่เสี่ยงเขียนผิด; ปิด L3, L11
**ข้อเสีย:** ต้องจัดการ connection pool หลายชุด; migration ต้องใช้ role แยก
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ต้นทุนไม่สูง คุ้มค่า

---

### ตัวเลือก E: Incremental — เริ่มจากข้อมูลอ่อนไหวสูงสุด

```
Wave 1: health_data, consultation_*, chat_*        (ข้อมูลส่วนบุคคล/การแพทย์)
Wave 2: donations, escrow_*, fees                  (การเงิน)
Wave 3: users, user_group_roles, professions       (identity)
Wave 4: ERP tables ทั้งหมด                          (ตอนสร้างใหม่ — ทำ RLS ตั้งแต่แรก)
Wave 5: ที่เหลือ
```

**ข้อดี:** ลดความเสี่ยงสูงสุดก่อน; เรียนรู้จาก wave แรกไปปรับ wave ถัดไป
**ข้อเสีย:** ระบบไม่สม่ำเสมอระหว่างทาง
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **เป็นวิธี rollout ที่ควรใช้กับ B**

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **A (permission model) + B (RLS) rollout แบบ E + D (DB roles)** | ครบทุกชั้น: application → database → connection; ERP ที่กำลังจะสร้างต้องการทั้งหมดนี้ |
| 2 | **A + C (gateway)** | ถ้าตัดสินใจทำ backend gateway ตามแผน 09 ตัวเลือก A — ไม่ต้องเขียน RLS แต่ต้องมี test ครบ |
| 3 | **B (wave 1–3) + D ก่อน แล้ว A ตอนเริ่ม ERP** | ถ้าทรัพยากรจำกัด — ปิดความเสี่ยงข้อมูลอ่อนไหวก่อน |
| 4 | **A อย่างเดียว** | ไม่พอ — permission ที่บังคับแค่ชั้น app ยังข้ามได้ผ่าน Supabase ตรง |

---

## 5. Permission Matrix ตั้งต้นที่เสนอ

| Role | ขอบเขต | ตัวอย่าง Permission |
|------|--------|-------------------|
| `consumer` | ข้อมูลตนเอง | `*.self.read/write`, `donation.create`, `consultation.request` |
| `provider` | เคสที่รับผิดชอบ | + `consultation.assigned.*`, `prescription.create`, `chat.assigned.*` |
| `provider_admin` | องค์กรตน | + `drug_risk.override.organization`, `org.settings.write` |
| `donation_reviewer` | คำขอบริจาค | `donation.review`, `donation.beneficiary.verify` |
| `donation_approver` | อนุมัติ | + `donation.approve` |
| `escrow_officer` | ปล่อยเงิน | `donation.escrow.release` (**แยกจาก approver — separation of duties**) |
| `erp_viewer` | ERP อ่านอย่างเดียว | `erp.*.read` (scoped by org/branch) |
| `erp_operator` | ปฏิบัติการ | + `erp.inventory.*`, `erp.pos.sale` |
| `erp_supervisor` | อนุมัติระดับต้น | + `erp.pos.refund`, `erp.inventory.adjust.approve` |
| `erp_manager` | อนุมัติระดับกลาง | + `erp.procurement.po.approve.under_100k` |
| `erp_controller` | การเงิน | + `erp.finance.gl.post`, `erp.finance.period.close` |
| `hr_officer` | HR ทั่วไป | `erp.hr.employee.*` (ไม่รวม payroll) |
| `hr_payroll` | เงินเดือน | + `erp.hr.payroll.*` |
| `clinician` | คลินิก | `clinical.emr.read.assigned`, `clinical.order.create` |
| `lab_tech` | แล็บ | `clinical.lab.result.enter` |
| `lab_approver` | อนุมัติผล | + `clinical.lab.result.approve` |
| `platform_admin` | ระบบ | `admin.platform.*`, `admin.user.*` (**ไม่รวม** payroll/PHI โดยอัตโนมัติ) |
| `security_auditor` | ตรวจสอบ | `audit.*.read` (read-only ทุก audit log) |

> **หลักการสำคัญ:** `platform_admin` **ไม่ควร**เห็น payroll และ PHI โดยอัตโนมัติ — ต้อง grant แยกและ log ทุกครั้ง

---

## 6. มาตรการเสริม

### 6.1 Break-Glass Access (สำหรับ Clinical)
```
1. ผู้ใช้กด "เข้าถึงฉุกเฉิน" + ระบุเหตุผล
2. ระบบให้สิทธิ์ชั่วคราว (เช่น 1 ชม.)
3. แจ้งเตือน security officer ทันที
4. Log ครบถ้วน + review บังคับภายใน 24 ชม.
```

### 6.2 Separation of Duties Matrix
| กระบวนการ | ห้ามเป็นคนเดียวกัน |
|-----------|-------------------|
| PO creation ↔ PO approval | ✅ |
| Journal entry ↔ Journal posting | ✅ |
| Payroll calculation ↔ Payroll approval | ✅ |
| Donation approval ↔ Escrow release | ✅ |
| Stock adjustment ↔ Adjustment approval | ✅ |
| Lab result entry ↔ Result approval | ✅ |
| User creation ↔ Permission grant | ⚠️ แนะนำ |

### 6.3 Permission Audit
```sql
CREATE TABLE permission_audit_log (
  id UUID PRIMARY KEY,
  actor_user_id UUID NOT NULL,
  target_user_id UUID NOT NULL,
  action VARCHAR(20),          -- grant | revoke | role_change
  permission VARCHAR(100),
  scope JSONB,                 -- { org_id, branch_ids }
  reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```
+ Access review รายไตรมาส: ตรวจว่าทุกคนยังต้องการสิทธิ์ที่มีอยู่

---

## 7. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด — แต่ RLS ต้องรู้จัก user ID ที่มาจาก custom AuthService → ต้องส่งผ่าน `SET LOCAL app.user_id` หรือ JWT claims (แผน 08) |
| `docs/infrastructure/role_management_refactor_plan.md` | ✅ **ต่อยอดโดยตรง** — Phase 1–2 เสร็จแล้ว แผนนี้คือ Phase 3 (permission granularity) |
| `docs/infrastructure/architecture_analysis.md` | เพิ่ม authorization layer ในผัง |
| `docs/infrastructure/caching_strategy.md` | ⚠️ **สำคัญ** — cache key ต้องรวม user/org/permission context ไม่งั้นข้อมูลรั่วข้ามผู้ใช้ |
| `docs/infrastructure/SETUP_DATABASE_SERVER.md` | ตัวเลือก D ต้องเพิ่มขั้นตอนสร้าง DB role |
| `docs/ERP/ERP_CORE_ARCHITECTURE.md` | ต้องระบุ multi-tenant strategy ให้ชัด (shared schema + org_id vs schema-per-tenant) |
| `docs/guides/TEST_PLAN.md` | GUARD-01..04 ครอบคลุมบางส่วน — ควรขยายเป็น permission-level test |

---

## 8. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] ตัดสินใจ multi-tenant strategy: shared schema + `organization_id` / schema-per-tenant / database-per-tenant
- [ ] อนุมัติ permission naming convention (section 3 ตัวเลือก A)
- [ ] อนุมัติ role list ตั้งต้น (ตาราง section 5)
- [ ] เลือกกลไกบังคับ: RLS (B) / Gateway (C) / ทั้งคู่
- [ ] อนุมัติ separation of duties matrix (section 6.2)
- [ ] ตัดสินใจเรื่อง break-glass access สำหรับ clinical
- [ ] ตัดสินใจเรื่อง DB role separation (D)
- [ ] กำหนดรอบ access review (แนะนำ: รายไตรมาส)
