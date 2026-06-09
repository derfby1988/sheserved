# Human Resources (ระบบทรัพยากรบุคคล)

## ภาพรวม (Overview)
ระบบบริหารจัดการบุคคลากรที่ออกแบบมาเพื่อรองรับทั้ง **การใช้งานภายในขององค์กร Sheserved** และ **การใช้งานขององค์กรภายนอก (Partner Clinics/Centers)** โดยองค์กรภายนอกแต่ละแห่งจะได้รับสิทธิ์ในการบริหารจัดการบุคลากร (HRM) ของตนเองได้อย่างอิสระ (Tenant-based HRM)

## ฟีเจอร์หลัก (Core Features)
- **External HRM Flag:** แยกสถานะกลุ่มอาชีพว่าเป็นองค์กรภายนอกที่มีระบบบริหารบุคลากรของตนเอง
- **Employee Profiles & Branch Assignment:** ฐานข้อมูลพนักงาน ตำแหน่ง ประวัติการทำงาน และใบอนุญาตประกอบวิชาชีพ โดยพนักงานสามารถถูกระบุให้ทำงานเฉพาะสาขาหรือดูแลรวมทุกสาขาในองค์กร (HQ)
- **Shift & Roster Management:** จัดตารางเวร (Shift) และตารางนัดหมายของพนักงาน/แพทย์ แยกรายสาขาได้
- **Time Attendance:** ระบบลงเวลาเข้า-ออกงาน รองรับทั้งการกรอกด้วยตนเอง (manual) และเครื่องสแกน (device)
- **Flexible Hours:** แอดมินองค์กรสามารถกำหนด flexible hours ล่วงหน้าได้
- **Commission & Incentives:** คำนวณค่าคอมมิชชั่นจากข้อมูล POS sales data และสามารถแก้ไข/กรอก manual ได้
- **Payroll:** รวบรวมข้อมูลการทำงาน วันลา Commission เพื่อคำนวณเงินเดือนสุทธิ รันแยก (per-employee detail) ส่งข้อมูลไป Accounting ผ่าน Outbox
- **Leave Management:** ระบบขอลา อนุมัติ และติดตามวันลาคงเหลือ

## Workflow การเปิดใช้งานระบบ HR ขององค์กรภายนอก
1. **Registration:** ตัวแทนองค์กรสมัครสมาชิกและขอสร้าง Profession
2. **Platform Admin Verification:** แอดมินกลางตรวจสอบความถูกต้อง
3. **HRM Activation:** แอดมินเปิด Toggle `has_external_hrm = true`
4. **Onboarding:** Admin ขององค์กรเข้าถึงระบบ HR และส่งคำเชิญให้ผู้ใช้งานอื่นๆ โดยผู้ถูกเชิญสามารถ Accept หรือ Reject ได้

## การเชื่อมโยงกับระบบอื่น (Integrations)
- **POS:** ดึงข้อมูล `served_by` จากออเดอร์มาคำนวณ Commission
- **Accounting:** ข้อมูล Payroll ส่งไปตั้งเบิกและตัดบัญชีเป็นค่าใช้จ่ายบริษัท ผ่าน Outbox Events
- **External HRM:** หาก `has_external_hrm = true` เปิด Sync API ให้ external HRM push ข้อมูลเข้ามา แต่ Payroll ภายในปิดการใช้งาน

---

## สถาปัตยกรรมและหลักการกำกับข้อมูล (Architecture & Data Governance)

### Multi-Tenant Isolation
- ทุกตารางมี `profession_id UUID NOT NULL REFERENCES professions(id)` แยกข้อมูลตามองค์กร
- Application Layer ใช้ `ServiceLocator.instance.currentUser?.professionId` กรองข้อมูล (ไม่ใช้ PostgreSQL RLS `auth.uid()`)

### Multi-Branch Support
- `branch_id` = สาขาที่พนักงานประจำ
- `employee_branches` (junction) รองรับพนักงาน 1 คนทำงานหลายสาขา
- พนักงานระดับ HQ ดูรวมทุกสาขาได้ สาขาย่อยเห็นเฉพาะสาขาตนเอง

### ระดับสิทธิ์ 3 ขั้น (Per-Module Permission)
- **Admin/Manager:** อนุมัติ Payroll, ตั้งค่า benefit policies, จัดการสิทธิพนักงาน
- **Editor:** สร้าง/แก้ไข Shift, Roster, คำนวณ Commission, แก้ไข Attendance
- **Viewer:** ดูรายงาน, ประวัติพนักงาน, Payroll summary

---

## ฐานข้อมูล (Database Schema)

> **คำเตือน:** ไม่มีนโยบาย RLS ใดๆ ที่ใช้ `auth.uid()` ในฐานข้อมูล PostgreSQL การเข้าถึงข้อมูลควบคุมที่ Application Layer ตาม [auth_data_guidelines.md](../../.agent/workflows/auth_data_guidelines.md)

### 1. ตาราง Master & Config

```sql
CREATE TABLE hr_settings (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id               UUID NOT NULL UNIQUE REFERENCES professions(id) ON DELETE CASCADE,
  attendance_mode             TEXT NOT NULL DEFAULT 'manual'
    CHECK (attendance_mode IN ('manual','device','both')),
  allow_flexible_hours        BOOLEAN DEFAULT false,
  default_work_hours_per_day  DECIMAL(4,2) DEFAULT 8.00,
  ot_multiplier_weekday       DECIMAL(3,2) DEFAULT 1.50,
  ot_multiplier_weekend       DECIMAL(3,2) DEFAULT 2.00,
  ot_multiplier_holiday       DECIMAL(3,2) DEFAULT 3.00,
  social_security_rate        DECIMAL(5,4) DEFAULT 0.0500,
  diligence_allowance_amount  DECIMAL(12,2) DEFAULT 0,
  external_hrm_api_url        TEXT,
  external_hrm_sync_enabled   BOOLEAN DEFAULT false,
  created_at                  TIMESTAMPTZ DEFAULT now(),
  updated_at                  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE benefit_policies (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  name                    TEXT NOT NULL,
  policy_type             TEXT NOT NULL
    CHECK (policy_type IN ('overtime','diligence','bonus','allowance','deduction','social_security','provident_fund')),
  amount                  DECIMAL(12,2),
  amount_type             TEXT NOT NULL DEFAULT 'fixed'
    CHECK (amount_type IN ('fixed','percentage_of_salary','percentage_of_base')),
  is_active               BOOLEAN DEFAULT true,
  created_by              UUID,
  updated_by              UUID,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now()
);
```

### 2. ตาราง Employee

```sql
CREATE TABLE employees (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  user_id                 UUID REFERENCES users(id) ON DELETE SET NULL,
  erp_user_id             UUID,
  employee_code           TEXT NOT NULL,
  first_name              TEXT NOT NULL,
  last_name               TEXT NOT NULL,
  email                   TEXT,
  phone                   TEXT,
  id_card_number          TEXT,
  date_of_birth           DATE,
  hire_date               DATE NOT NULL DEFAULT CURRENT_DATE,
  termination_date        DATE,
  base_salary             DECIMAL(12,2) NOT NULL DEFAULT 0,
  position                TEXT,
  department              TEXT,
  is_active               BOOLEAN DEFAULT true,
  license_number          TEXT,
  license_expiry          DATE,
  emergency_contact_name  TEXT,
  emergency_contact_phone TEXT,
  created_by              UUID,
  updated_by              UUID,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, employee_code)
);

CREATE TABLE employee_branches (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  employee_id     UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  branch_id       UUID NOT NULL REFERENCES organization_branches(id) ON DELETE CASCADE,
  is_primary      BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (employee_id, branch_id)
);
```

### 3. ตาราง Shift & Roster

```sql
CREATE TABLE shift_templates (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  name                TEXT NOT NULL,
  start_time          TIME NOT NULL,
  end_time            TIME NOT NULL,
  break_duration_minutes INTEGER DEFAULT 60,
  is_flexible         BOOLEAN DEFAULT false,
  is_active           BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE work_shifts (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id           UUID REFERENCES organization_branches(id),
  employee_id         UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  shift_template_id   UUID REFERENCES shift_templates(id),
  shift_date          DATE NOT NULL,
  scheduled_start     TIMESTAMPTZ,
  scheduled_end       TIMESTAMPTZ,
  status              TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled','completed','absent','cancelled')),
  notes               TEXT,
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);
```

### 4. ตาราง Time Attendance

```sql
CREATE TABLE attendance_devices (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id           UUID NOT NULL REFERENCES organization_branches(id),
  device_name         TEXT NOT NULL,
  device_serial       TEXT NOT NULL,
  device_type         TEXT NOT NULL DEFAULT 'fingerprint'
    CHECK (device_type IN ('fingerprint','face_recognition','card','mobile_app')),
  last_sync_at        TIMESTAMPTZ,
  is_active           BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE time_attendances (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id               UUID REFERENCES organization_branches(id),
  employee_id             UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  shift_id                UUID REFERENCES work_shifts(id),
  attendance_device_id    UUID REFERENCES attendance_devices(id),
  clock_in_time           TIMESTAMPTZ,
  clock_out_time          TIMESTAMPTZ,
  clock_in_location       JSONB,
  clock_out_location      JSONB,
  attendance_status       TEXT NOT NULL DEFAULT 'on_time'
    CHECK (attendance_status IN ('on_time','late','early_leave','absent','overtime')),
  is_manual_override      BOOLEAN DEFAULT false,
  override_by             UUID,
  override_reason         TEXT,
  source                  TEXT NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual','device','mobile_app','admin_entry')),
  notes                   TEXT,
  created_by              UUID,
  updated_by              UUID,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now()
);
```

### 5. ตาราง Commission

```sql
CREATE TABLE commission_rules (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id           UUID REFERENCES organization_branches(id),
  name                TEXT NOT NULL,
  rule_type           TEXT NOT NULL DEFAULT 'percentage_of_sale'
    CHECK (rule_type IN ('percentage_of_sale','fixed_per_sale','tiered')),
  rate_or_amount      DECIMAL(12,4) NOT NULL,
  applies_to          TEXT NOT NULL DEFAULT 'all_services'
    CHECK (applies_to IN ('all_services','specific_service','specific_category','medication_only')),
  service_category_id UUID,
  is_active           BOOLEAN DEFAULT true,
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE commissions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id           UUID REFERENCES organization_branches(id),
  employee_id         UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  commission_rule_id  UUID REFERENCES commission_rules(id),
  sale_transaction_id UUID,
  sale_amount         DECIMAL(12,2) NOT NULL,
  calculated_amount   DECIMAL(12,2) NOT NULL,
  adjusted_amount     DECIMAL(12,2),
  adjustment_reason   TEXT,
  status              TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','paid','rejected')),
  period_start        DATE NOT NULL,
  period_end          DATE NOT NULL,
  approved_by         UUID,
  approved_at         TIMESTAMPTZ,
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);
```

### 6. ตาราง Payroll

```sql
CREATE TABLE payroll_runs (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id           UUID REFERENCES organization_branches(id),
  run_name            TEXT NOT NULL,
  period_start        DATE NOT NULL,
  period_end          DATE NOT NULL,
  pay_date            DATE,
  status              TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','calculating','pending_approval','approved','paid','cancelled')),
  total_gross         DECIMAL(12,2) DEFAULT 0,
  total_deductions    DECIMAL(12,2) DEFAULT 0,
  total_net           DECIMAL(12,2) DEFAULT 0,
  approved_by         UUID,
  approved_at         TIMESTAMPTZ,
  notes               TEXT,
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE payroll_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  payroll_run_id      UUID NOT NULL REFERENCES payroll_runs(id) ON DELETE CASCADE,
  employee_id         UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  item_type           TEXT NOT NULL
    CHECK (item_type IN ('base_salary','commission','overtime','diligence_allowance','bonus','allowance','deduction','social_security','provident_fund_employee','provident_fund_employer','tax','other')),
  amount              DECIMAL(12,2) NOT NULL,
  is_earning          BOOLEAN NOT NULL DEFAULT true,
  notes               TEXT,
  reference_id        UUID,
  reference_type      TEXT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE payroll_item_details (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  payroll_item_id     UUID NOT NULL REFERENCES payroll_items(id) ON DELETE CASCADE,
  detail_date         DATE,
  description         TEXT NOT NULL,
  quantity            DECIMAL(10,2) DEFAULT 1,
  unit_amount         DECIMAL(12,2),
  total_amount        DECIMAL(12,2) NOT NULL,
  source_type         TEXT,
  source_id           UUID,
  created_at          TIMESTAMPTZ DEFAULT now()
);
```

### 7. ตาราง Leave

```sql
CREATE TABLE leave_requests (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id           UUID REFERENCES organization_branches(id),
  employee_id         UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  leave_type          TEXT NOT NULL
    CHECK (leave_type IN ('sick','annual','personal','maternity','paternity','bereavement','unpaid','other')),
  start_date          DATE NOT NULL,
  end_date            DATE NOT NULL,
  days_requested      DECIMAL(4,1) NOT NULL,
  reason              TEXT,
  status              TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  approved_by         UUID,
  approved_at         TIMESTAMPTZ,
  approval_notes      TEXT,
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);
```

### 8. Indexes & Performance

```sql
CREATE INDEX idx_employee_active ON employees(profession_id, is_active)
  WHERE is_active = true;
CREATE INDEX idx_work_shift_date ON work_shifts(profession_id, branch_id, shift_date);
CREATE INDEX idx_attendance_date ON time_attendances(profession_id, employee_id, clock_in_time);
CREATE INDEX idx_commission_period ON commissions(profession_id, employee_id, period_start, period_end)
  WHERE status = 'pending';
CREATE INDEX idx_payroll_run_status ON payroll_runs(profession_id, status)
  WHERE status IN ('draft','calculating','pending_approval');
CREATE INDEX idx_leave_pending ON leave_requests(profession_id, employee_id, status)
  WHERE status = 'pending';

CREATE INDEX idx_employee_branches_emp ON employee_branches(employee_id);
CREATE INDEX idx_employee_branches_branch ON employee_branches(branch_id);
CREATE INDEX idx_work_shifts_employee ON work_shifts(employee_id);
CREATE INDEX idx_time_attendances_shift ON time_attendances(shift_id);
CREATE INDEX idx_commissions_employee ON commissions(employee_id);
CREATE INDEX idx_payroll_items_run ON payroll_items(payroll_run_id);
CREATE INDEX idx_payroll_items_employee ON payroll_items(employee_id);
CREATE INDEX idx_payroll_item_details_item ON payroll_item_details(payroll_item_id);
CREATE INDEX idx_leave_requests_employee ON leave_requests(employee_id);
```

### 9. Trigger อัปเดต updated_at

```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'hr_settings','benefit_policies',
    'employees','employee_branches',
    'shift_templates','work_shifts',
    'attendance_devices','time_attendances',
    'commission_rules','commissions',
    'payroll_runs','payroll_items','payroll_item_details',
    'leave_requests'
  ]
  LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%I_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();',
      tbl, tbl
    );
  END LOOP;
END $$;
```

---

## ER Diagram (Textual)

```
professions (ERP Core)
  | profession_id
  v
+-----------------+    +------------------------+    +---------------------+
|   hr_settings   |    |   benefit_policies     |    |organization_branches|
|     (Config)    |    |      (Config)          |    |     (ERP Core)      |
+-----------------+    +------------------------+    +---------------------+
         |                                                      |
         | profession_id                                          | branch_id
         v                                                      v
+---------------------+    +-----------------------------+
|      employees      |<---+     employee_branches       |
|   - user_id (FK)    |    |   - employee_id (FK)        |
|   - erp_user_id     |    |   - branch_id (FK)          |
|   - profession_id   |    +-----------------------------+
+---------+-----------+
          | employee_id
          |
    +-----+------+---------------+---------------+---------------+
    v            v               v               v               v
+--------+ +------------+ +-------------+ +----------+ +-------------+
|work_   | | time_      | | commissions | | payroll_ | | leave_      |
|shifts  | |attendances | |             | |items     | |requests     |
|        | |            | |             | |          | |             |
+--------+ +------------+ +-------------+ +----------+ +-------------+
    |            |               |               |
    v            v               v               v
+----------+ +------------+ +-------------+ +-------------+
|shift_    | | attendance_| | commission_ | |payroll_item_|
|templates | | _devices    | | _rules      | | _details    |
+----------+ +------------+ +-------------+ +-------------+

+---------------------+
|      payroll_runs   |
|   - profession_id   |
|   - branch_id       |
|   - status          |
+---------------------+
```

**Key Relationships:**
- `employees.profession_id` → `professions` (N:1)
- `employees.user_id` → `users` (N:1, nullable)
- `employee_branches.employee_id` → `employees` (N:1)
- `employee_branches.branch_id` → `organization_branches` (N:1)
- `work_shifts.employee_id` → `employees` (N:1)
- `work_shifts.shift_template_id` → `shift_templates` (N:1)
- `time_attendances.employee_id` → `employees` (N:1)
- `time_attendances.shift_id` → `work_shifts` (N:1)
- `commissions.employee_id` → `employees` (N:1)
- `commissions.commission_rule_id` → `commission_rules` (N:1)
- `payroll_items.payroll_run_id` → `payroll_runs` (N:1)
- `payroll_items.employee_id` → `employees` (N:1)
- `payroll_item_details.payroll_item_id` → `payroll_items` (N:1)
- `leave_requests.employee_id` → `employees` (N:1)

---

## รายละเอียด Business Logic เฉพาะ (Detailed Business Logic)

### 1. การคำนวณ Commission

```
WHEN sale transaction สร้าง/ปิด (POS):
  1. ดึง commission_rules ที่ is_active = true และ applies_to ตรงกับ service
  2. FOR EACH rule:
     IF rule.rule_type = 'percentage_of_sale':
       commission.calculated_amount = sale_amount * rule.rate_or_amount
     ELSE IF rule.rule_type = 'fixed_per_sale':
       commission.calculated_amount = rule.rate_or_amount
     ELSE IF rule.rule_type = 'tiered':
       (คำนวณตาม tier ที่กำหนด)
  3. INSERT commissions:
     - status = 'pending'
     - period_start/period_end = รอบ payroll ปัจจุบัน
  4. INSERT outbox_event:
     - event_type = 'hr.commission_calculated'

WHEN user แก้ไข commission (Manual Override):
  1. UPDATE commissions:
     - adjusted_amount = user_input
     - adjustment_reason = user_reason
     - updated_by = current_user
```

### 2. การคำนวณ Payroll

```
WHEN HR กด "Run Payroll" สำหรับ period:
  1. CREATE payroll_runs:
     - status = 'calculating'
     - period_start / period_end = รอบที่เลือก

  2. FOR EACH employee IN active employees:
     a. base_salary = employees.base_salary (prorated ตามวันทำงาน)
     b. คำนวณ OT จาก time_attendances:
        - ot_hours = SUM(overtime hours)
        - ot_amount = ot_hours * (base_salary / default_work_hours) * ot_multiplier
     c. คำนวณ Commission จาก commissions:
        - commission_amount = SUM(calculated_amount) WHERE status = 'approved'
     d. คำนวณ Diligence Allowance:
        - ตรวจสอบว่าในรอบนี้ไม่มี late/absent/unpaid leave
        - หากผ่าน → diligence_amount = hr_settings.diligence_allowance_amount
     e. คำนวณหักประกันสังคม:
        - social_security = MIN(base_salary * social_security_rate, 750.00)
     f. รวมรายการอื่นๆ จาก benefit_policies

  3. INSERT payroll_items (per-employee detail):
     - item_type = 'base_salary', 'overtime', 'commission', 'diligence_allowance', 'social_security', etc.
     - amount = ตามที่คำนวณ
     - is_earning = true/false
     - reference_id = อ้างอิงต้นทาง (เช่น commission_id, attendance_id)

  4. UPDATE payroll_runs:
     - total_gross = SUM(earning items)
     - total_deductions = SUM(deduction items)
     - total_net = total_gross - total_deductions
     - status = 'pending_approval'

  5. INSERT outbox_event:
     - event_type = 'hr.payroll_calculated'
     - payload = { payroll_run_id, total_gross, total_deductions, total_net, employee_count }
```

### 3. การอนุมัติ Payroll

```
WHEN Manager/Admin กด "Approve Payroll":
  1. CHECK permission: user มีสิทธิ์ Full ใน module 'hr'
  2. UPDATE payroll_runs:
     - status = 'approved'
     - approved_by = current_user.id
     - approved_at = now()
  3. INSERT outbox_event:
     - event_type = 'hr.payroll_approved'
     - event_type = 'accounting.payroll_expense_posted'
```

### 4. การลงเวลาเข้า-ออกงาน

```
WHEN employee กด "Clock In":
  1. INSERT time_attendances:
     - clock_in_time = now()
     - source = 'mobile_app' (หรือ 'device')
     - attendance_status = 'on_time' (default)
  2. IF hr_settings.allow_flexible_hours = false:
     - เปรียบเทียบกับ work_shifts.scheduled_start
     - หาก clock_in_time > scheduled_start → UPDATE attendance_status = 'late'

WHEN employee กด "Clock Out":
  1. UPDATE time_attendances:
     - clock_out_time = now()
  2. คำนวณเวลาทำงานจริง:
     - actual_hours = clock_out_time - clock_in_time
     - scheduled_hours = scheduled_end - scheduled_start
     - IF actual_hours > scheduled_hours + break_duration:
         UPDATE attendance_status = 'overtime'
     - IF clock_out_time < scheduled_end:
         UPDATE attendance_status = 'early_leave'

WHEN HR แก้ไขเวลา (Manual Override):
  1. UPDATE time_attendances:
     - clock_in_time / clock_out_time = user_input
     - is_manual_override = true
     - override_by = current_user.id
     - override_reason = user_reason
     - source = 'admin_entry'
```

### 5. State Transition Guard Matrix

**Payroll Run Status Transitions:**
| จากสถานะ | ไปยัง | เงื่อนไข | ผู้ทำได้ |
|---|---|---|---|
| `draft` | `calculating` | กด Run Payroll | Editor/Manager |
| `calculating` | `pending_approval` | คำนวณเสร็จ | System |
| `pending_approval` | `approved` | Manager อนุมัติ | Manager/Admin |
| `pending_approval` | `cancelled` | — | Manager/Admin |
| `approved` | `paid` | จ่ายเงินเดือนแล้ว | Manager/Admin |

**Leave Request Status Transitions:**
| จากสถานะ | ไปยัง | เงื่อนไข | ผู้ทำได้ |
|---|---|---|---|
| `pending` | `approved` | Manager อนุมัติ | Manager/Admin |
| `pending` | `rejected` | — | Manager/Admin |
| `pending` | `cancelled` | พนักงานยกเลิกเอง | Editor (ตัวเอง) |

### 6. Idempotency Keys

ทุก operation ที่มีผลต่อเงินหรือ stock ต้องมี idempotency key:

```dart
String generateIdempotencyKey({
  required String operation,
  required String entityId,
  required String userId,
}) {
  return '${operation}_${entityId}_${userId}_${DateTime.now().millisecondsSinceEpoch}';
}
```

**Operations ที่ต้องมี idempotency:**
- Create/Update Employee
- Create/Update Shift, Roster
- Clock In / Clock Out
- Run Payroll, Approve Payroll
- Create/Update Commission
- Approve/Reject Leave Request

---

## หน้าจอ Flutter UI (Flutter Pages)

### HR Dashboard
- `HrDashboardPage` — ภาพรวม: พนักงานทั้งหมด, ลงเวลาวันนี้, ลาค้างอนุมัติ, Payroll รออนุมัติ, Commission รออนุมัติ

### Employee Management
- `EmployeeDirectoryPage` — รายการพนักงาน, ค้นหา, filter ตามสาขา/ตำแหน่ง/สถานะ
- `EmployeeDetailPage` — ดูประวัติ, เอกสาร, ใบอนุญาต, สาขาที่ประจำ, เงินเดือนพื้นฐาน
- `EmployeeFormPage` — สร้าง/แก้ไขพนักงาน (รวมถึง assign user_id)
- `EmployeeInvitationPage` — ส่งคำเชิญให้ผู้ใช้งานเข้าร่วมเป็น Employee

### Shift & Roster Management
- `ShiftTemplatePage` — จัดการรูปแบบกะงาน (เช่น เช้า/บ่าย/ดึก)
- `RosterCalendarPage` — ปฏิทินกะงานรายสัปดาห์/เดือน, แยกตามสาขา
- `RosterAssignPage` — มอบหมายกะงานให้พนักงานแต่ละคน

### Time Attendance
- `MyAttendancePage` — พนักงานดูกะของตนเอง + ปุ่ม Clock In/Out
- `AttendanceDashboardPage` — HR/Manager ดูสรุปการเข้างานรายวัน, สาย, ขาด, OT
- `AttendanceEditPage` — แก้ไขเวลาเข้า-ออก (manual override)
- `AttendanceDevicePage` — จัดการเครื่องสแกน (เพิ่ม/ลบ/ตั้งค่า sync)

### Commission & Incentives
- `CommissionRulePage` — ตั้งค่ากฎคอมมิชชั่น (เปอร์เซ็นต์, จำนวนคงที่, tiered)
- `CommissionReportPage` — รายงานคอมมิชชั่นรายคน/รายเดือน, สถานะ pending/approved/paid
- `CommissionAdjustmentPage` — แก้ไข/ปรับคอมมิชชั่น manual

### Payroll
- `PayrollRunListPage` — รายการรอบเงินเดือนทั้งหมด, สถานะ draft → paid
- `PayrollRunDetailPage` — ดูรายละเอียดรายได้/หัก ต่อพนักงาน
- `PayrollCalculatorPage` — กด Run Payroll → ระบบคำนวณ auto
- `PayrollApprovalPage` — Manager อนุมัติ Payroll run
- `PayslipPage` — สลิปเงินเดือนรายบุคคล (ดู/พิมพ์/ส่ง email)

### Leave Management
- `MyLeavePage` — พนักงานยื่นขอลา, ดูวันลาคงเหลือ
- `LeaveApprovalPage` — Manager อนุมัติ/ปฏิเสธคำขอลา
- `LeaveCalendarPage` — ปฏิทินลาขององค์กร/สาขา

### Benefit Policies
- `BenefitPolicyPage` — ตั้งค่านโยบายสวัสดิการ (OT rate, เบี้ยขยัน, ประกันสังคม, กองทุน)

### Employee Permission Management
- `EmployeeRolePage` — กำหนด Role และ Permission ต่อโมดูล (Full/Edit/View)
- `FeatureTogglePage` — เปิด/ปิดโมดูลเฉพาะขององค์กร

---

## ตัวอย่าง Outbox Payload (Outbox Payload Examples)

### 1. hr.commission_calculated

```json
{
  "event_id": "evt-calc-001",
  "event_type": "hr.commission_calculated",
  "aggregate_type": "commission",
  "aggregate_id": "comm-uuid-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T14:30:00Z",
  "payload": {
    "commission_id": "comm-uuid-001",
    "employee_id": "emp-uuid-456",
    "employee_name": "นพ. สมชาย ใจดี",
    "sale_transaction_id": "tx-uuid-789",
    "sale_amount": 2500.00,
    "rule_type": "percentage_of_sale",
    "rate": 0.10,
    "calculated_amount": 250.00,
    "period_start": "2026-06-01",
    "period_end": "2026-06-30",
    "status": "pending"
  }
}
```

### 2. hr.payroll_calculated

```json
{
  "event_id": "evt-pay-001",
  "event_type": "hr.payroll_calculated",
  "aggregate_type": "payroll_run",
  "aggregate_id": "pr-run-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T14:30:00Z",
  "payload": {
    "payroll_run_id": "pr-run-001",
    "run_name": "Payroll June 2026",
    "period_start": "2026-06-01",
    "period_end": "2026-06-30",
    "pay_date": "2026-07-05",
    "total_gross": 185000.00,
    "total_deductions": 18500.00,
    "total_net": 166500.00,
    "employee_count": 12,
    "status": "pending_approval"
  }
}
```

### 3. hr.payroll_approved

```json
{
  "event_id": "evt-pay-002",
  "event_type": "hr.payroll_approved",
  "aggregate_type": "payroll_run",
  "aggregate_id": "pr-run-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-10T09:00:00Z",
  "payload": {
    "payroll_run_id": "pr-run-001",
    "approved_by": "user-uuid-admin-001",
    "approved_by_name": "คุณมานี ผู้จัดการ",
    "approved_at": "2026-06-10T09:00:00Z",
    "total_net": 166500.00,
    "items": [
      {
        "employee_id": "emp-uuid-456",
        "employee_name": "นพ. สมชาย ใจดี",
        "base_salary": 45000.00,
        "overtime": 2500.00,
        "commission": 250.00,
        "diligence_allowance": 1000.00,
        "social_security": -750.00,
        "net_pay": 48000.00
      }
    ]
  }
}
```

### 4. accounting.payroll_expense_posted

```json
{
  "event_id": "evt-acct-001",
  "event_type": "accounting.payroll_expense_posted",
  "aggregate_type": "payroll_run",
  "aggregate_id": "pr-run-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-10T09:00:00Z",
  "payload": {
    "payroll_run_id": "pr-run-001",
    "gl_entries": [
      {
        "account_code": "6100",
        "account_name": "ค่าใช้จ่ายเงินเดือน",
        "debit": 166500.00,
        "credit": 0
      },
      {
        "account_code": "2120",
        "account_name": "เงินเดือนค้างจ่าย",
        "debit": 0,
        "credit": 166500.00
      }
    ],
    "period": "2026-06"
  }
}
```

### 5. hr.attendance_clocked_in

```json
{
  "event_id": "evt-att-001",
  "event_type": "hr.attendance_clocked_in",
  "aggregate_type": "time_attendance",
  "aggregate_id": "att-uuid-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T08:30:00Z",
  "payload": {
    "attendance_id": "att-uuid-001",
    "employee_id": "emp-uuid-456",
    "employee_name": "นพ. สมชาย ใจดี",
    "clock_in_time": "2026-06-09T08:30:00Z",
    "shift_id": "shift-uuid-001",
    "scheduled_start": "2026-06-09T08:00:00Z",
    "attendance_status": "late",
    "source": "mobile_app",
    "location": {
      "lat": 13.7563,
      "lng": 100.5018
    }
  }
}
```

### 6. hr.leave_approved

```json
{
  "event_id": "evt-leave-001",
  "event_type": "hr.leave_approved",
  "aggregate_type": "leave_request",
  "aggregate_id": "leave-uuid-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T10:00:00Z",
  "payload": {
    "leave_request_id": "leave-uuid-001",
    "employee_id": "emp-uuid-456",
    "employee_name": "นพ. สมชาย ใจดี",
    "leave_type": "sick",
    "start_date": "2026-06-10",
    "end_date": "2026-06-10",
    "days_requested": 1.0,
    "approved_by": "user-uuid-manager-001",
    "approved_at": "2026-06-09T10:00:00Z"
  }
}
```

---

## การเชื่อมโยงกับระบบอื่น (Integrations)

### POS System
- รับ event `pos.sale_completed` → ดึง `served_by` (employee_id) + sale_amount → คำนวณ commission ตาม commission_rules
- ส่ง event `hr.commission_calculated` → ให้ Read Model อัปเดตรายงาน

### Accounting System
- รับ event `hr.payroll_approved` → สร้าง GL entries:
  - Dr ค่าใช้จ่ายเงินเดือน / Cr เงินเดือนค้างจ่าย
  - Dr ค่าใช้จ่ายประกันสังคม / Cr ประกันสังคมค้างจ่าย
  - Dr ค่าใช้จ่ายกองทุนสำรองเลี้ยงชีพ / Cr กองทุนสำรองเลี้ยงชีพค้างจ่าย

### Notification System
- `hr.payroll_approved` → แจ้งเตือนพนักงานว่าเงินเดือนอนุมัติแล้ว
- `hr.leave_approved` → แจ้งเตือนพนักงานว่าลาอนุมัติแล้ว
- `hr.attendance_clocked_in` + late → แจ้งเตือน HR/Manager

### Read Model / Analytics
- อ่าน events จาก `outbox_events` → สร้าง dashboard snapshot:
  - ยอดเงินเดือนรวมต่อเดือน
  - จำนวนพนักงานต่อสาขา
  - อัตราการขาดงาน/สาย
  - ยอด Commission รายบุคคล

---

## แผนการพัฒนาเป็นระยะ (Phased Implementation)

### Phase 1: Core HR (Employee + Shift + Attendance)
- Schema: `employees`, `employee_branches`, `shift_templates`, `work_shifts`, `time_attendances`
- UI: `EmployeeDirectoryPage`, `EmployeeFormPage`, `ShiftTemplatePage`, `RosterCalendarPage`, `MyAttendancePage`, `AttendanceDashboardPage`
- Business Logic: Clock In/Out, Late/OT detection, Shift assignment

### Phase 2: Commission + External HRM
- Schema: `commission_rules`, `commissions`
- Integration: ดึง POS sales data มาคำนวณ commission
- External HRM: `hr_settings.external_hrm_sync_enabled`, Sync API
- UI: `CommissionRulePage`, `CommissionReportPage`

### Phase 3: Payroll + Benefits
- Schema: `payroll_runs`, `payroll_items`, `payroll_item_details`, `benefit_policies`
- Business Logic: Payroll calculation, OT, Diligence Allowance, Social Security
- Integration: Outbox → Accounting
- UI: `PayrollRunListPage`, `PayrollCalculatorPage`, `PayrollApprovalPage`, `PayslipPage`, `BenefitPolicyPage`

### Phase 4: Leave + Permission Management
- Schema: `leave_requests`
- UI: `MyLeavePage`, `LeaveApprovalPage`, `LeaveCalendarPage`, `EmployeeRolePage`, `FeatureTogglePage`
- Business Logic: Leave approval workflow, Permission checks

### Phase 5: Advanced Features
- Attendance device integration (fingerprint, face recognition)
- Geofencing for clock in/out
- Payroll batch export (bank transfer file)
- Employee self-service portal (view payslip, request leave, view commission)
- KPI integration (employee performance metrics)
