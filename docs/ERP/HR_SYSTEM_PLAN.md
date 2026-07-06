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

### 2. การคำนวณ Payroll (Payroll Calculation Logic)

> **สถานะปัจจุบัน:** RPC `run_payroll_calculation` มีอยู่แล้วใน `20260701120000_hr_settings_rpc_seed.sql` แต่คำนวณพื้นฐานเท่านั้น (เงินเดือน + OT + เบี้ยขยัน + คอมมิชชั่น + ประกันสังคม) ยังขาดภาษีเงินได้หัก ณ ที่จ่าย, กองทุนสำรองเลี้ยงชีพ, OT วันหยุด, และการหักขาด/ลา

#### 2.1 สูตรคำนวณ Payroll ไทย (Thai Payroll Formula)

```
Gross Earnings = Base Salary + Overtime + Commission + Diligence Allowance + Bonus + Allowance
Deductions = Social Security + Provident Fund (Employee) + Tax Withholding + Other Deductions + Late/Absent Penalty
Net Pay = Gross Earnings - Deductions
Employer Cost = Gross Earnings + Social Security (Employer) + Provident Fund (Employer)
```

#### 2.2 รายการที่ต้องคำนวณเพิ่ม

| รายการ | ประเภท | วิธีคำนวณ | สถานะปัจจุบัน |
|--------|--------|-----------|---------------|
| `base_salary` | Earning | `employees.base_salary` | ✅ มีแล้ว |
| `overtime` | Earning | ชั่วโมงล่วงเวลา × ค่าจ้างต่อชั่วโมง × multiplier | ⚠️ ใช้แต่ weekday multiplier |
| `commission` | Earning | `SUM(approved commissions)` | ✅ มีแล้ว |
| `diligence_allowance` | Earning | ไม่ late/absent → ได้เต็ม | ✅ มีแล้ว |
| `bonus` | Earning | จาก `benefit_policies` หรือ manual | ⏳ ยังไม่ implement |
| `social_security` | Deduction | `MIN(base_salary * rate, 750.00)` | ✅ มีแล้ว |
| `social_security_employer` | Employer Cost | `MIN(base_salary * rate, 750.00)` — นายจ้างจ่ายเท่ากับลูกจ้าง | ⏳ ยังไม่ implement |
| `provident_fund_employee` | Deduction | `MIN(base_salary, pf_wage_cap) * employee_pf_rate` — ฐานสูงสุด 100,000 THB/เดือน | ⏳ ยังไม่ implement |
| `provident_fund_employer` | Employer Cost | `MIN(base_salary, pf_wage_cap) * employer_pf_rate` — ฐานสูงสุด 100,000 THB/เดือน | ⏳ ยังไม่ implement |
| `tax` | Deduction | หัก ณ ที่จ่ายตาม progressive rate | ⏳ ยังไม่ implement |
| `late_penalty` | Deduction | ตาม `benefit_policies` หรือ `hr_settings` | ⏳ ยังไม่ implement |
| `absent_penalty` | Deduction | หักเป็นวัน/ชั่วโมง | ⏳ ยังไม่ implement |

#### 2.3 Schema เพิ่มเติมที่จำเป็น

**เพิ่ม columns ใน `hr_settings`:**
```sql
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS provident_fund_employee_rate DECIMAL(5,4) DEFAULT 0.03;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS provident_fund_employer_rate DECIMAL(5,4) DEFAULT 0.03;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS provident_fund_wage_cap DECIMAL(12,2) DEFAULT 100000.00; -- ฐานสูงสุดสำหรับคำนวณ PF
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS tax_calculation_enabled BOOLEAN DEFAULT false;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS late_deduction_per_minute DECIMAL(12,4) DEFAULT 0;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS absent_deduction_per_day DECIMAL(12,2) DEFAULT 0;
```

**เพิ่ม columns ใน `employees`:**
```sql
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS tax_deductible_expenses DECIMAL(12,2) DEFAULT 0;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS personal_allowance DECIMAL(12,2) DEFAULT 60000;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS provident_fund_rate DECIMAL(5,4) DEFAULT 0.03;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'bank_transfer' CHECK (payment_method IN ('bank_transfer','cash','check'));
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS bank_account_number TEXT;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS bank_name TEXT;
```

**เพิ่มตาราง `thai_holidays` (สำหรับตรวจสอบวันหยุดนักขัตฤกษ์ในการคำนวณ OT):**
```sql
CREATE TABLE IF NOT EXISTS public.thai_holidays (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    holiday_date    DATE NOT NULL UNIQUE,
    holiday_name_th TEXT NOT NULL,
    holiday_name_en TEXT,
    holiday_type    TEXT NOT NULL DEFAULT 'public'
        CHECK (holiday_type IN ('public','religious','substitution','special')),
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_thai_holidays_date ON public.thai_holidays(holiday_date) WHERE is_active = true;
```
> **หมายเหตุ:** ต้องมี cron job หรือ manual seed วันหยุดประจำปีของกรมปกครอง (เช่น วันปีใหม่, วันสงกรานต์, วันเฉลิมพระชนมพรรษา, เป็นต้น) ก่อนรอบ payroll แรกของปี

**เพิ่ม columns ใน `payroll_runs` (สำหรับ Employer Cost):**
```sql
ALTER TABLE public.payroll_runs ADD COLUMN IF NOT EXISTS employer_social_security DECIMAL(12,2) DEFAULT 0;
ALTER TABLE public.payroll_runs ADD COLUMN IF NOT EXISTS employer_provident_fund DECIMAL(12,2) DEFAULT 0;
ALTER TABLE public.payroll_runs ADD COLUMN IF NOT EXISTS total_employer_cost DECIMAL(12,2) DEFAULT 0; -- Gross + Employer SS + Employer PF
```

**เพิ่มตาราง `employee_tax_allowances` (สำหรับค่าลดหย่อนภาษี):**
```sql
CREATE TABLE IF NOT EXISTS employee_tax_allowances (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
    employee_id     UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    allowance_type  TEXT NOT NULL,
        CHECK (allowance_type IN ('personal','spouse','child','parent','insurance','donation','housing','education','disability','other')),
    amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    description     TEXT,
    effective_year  INTEGER NOT NULL DEFAULT EXTRACT(YEAR FROM CURRENT_DATE),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

#### 2.4 อัปเดต RPC `run_payroll_calculation`

**สิ่งที่ต้องเพิ่มใน RPC:**
1. **Overtime multiplier ตามวัน:**
   - ตรวจสอบ `EXTRACT(DOW FROM clock_in_time)` + ตารางวันหยุดนักขัตฤกษ์
   - ใช้ `ot_multiplier_weekday` / `ot_multiplier_weekend` / `ot_multiplier_holiday`

2. **Social Security (Employer):**
   - นายจ้างจ่ายส่วนเท่ากับลูกจ้าง: `MIN(base_salary * social_security_rate, 750.00)`
   - สร้าง `payroll_item` ประเภท `social_security_employer` (is_earning = false, เป็น employer cost ไม่ใช่ deduction ของพนักงาน)
   - อัปเดต `payroll_runs.employer_social_security`

3. **Provident Fund:**
   - ใช้ฐานสูงสุด `provident_fund_wage_cap` (ค่าเริ่มต้น 100,000 THB/เดือน)
   - `pf_base = LEAST(base_salary, provident_fund_wage_cap)`
   - คำนวณ `provident_fund_employee` = `pf_base * employee_pf_rate`
   - คำนวณ `provident_fund_employer` = `pf_base * employer_pf_rate`
   - สร้าง `payroll_items` ทั้ง 2 ประเภท
   - อัปเดต `payroll_runs.employer_provident_fund`

4. **Tax Withholding (PIT):**
   - คำนวณเงินได้ประมาณการรายปี (Estimated Annual Income):
     `annual_income = (base_salary * 12) + (overtime * 12) + (commission * 12) + (bonus * 12) + (allowance * 12)`
   - หักค่าใช้จ่ายตามจริง (ถ้าเป็นค่าจ้างไม่มีใบเสร็จ): `annual_income - tax_deductible_expenses`
   - หักค่าลดหย่อนส่วนบุคคล: `personal_allowance` (60,000)
   - หักค่าลดหย่อนอื่นๆ จาก `employee_tax_allowances` (spouse, child, parent, insurance, donation, housing, education, disability)
   - หักประกันสังคมรายปี: `social_security * 12`
   - หักกองทุนสำรองเลี้ยงชีพรายปี: `provident_fund_employee * 12`
   - เงินได้สุทธิประมาณการ = `annual_income - tax_deductible_expenses - personal_allowance - SUM(tax_allowances) - social_security_annual - pf_employee_annual`
   - ใช้ progressive tax rate ไทย (5% → 35%) ตามเงินได้สุทธิประมาณการ:
     - 0 – 150,000: 0% (ยกเว้น)
     - 150,001 – 300,000: 5%
     - 300,001 – 500,000: 10%
     - 500,001 – 750,000: 15%
     - 750,001 – 1,000,000: 20%
     - 1,000,001 – 2,000,000: 25%
     - 2,000,001 – 5,000,000: 30%
     - 5,000,001 ขึ้นไป: 35%
   - หารด้วย 12 ได้ tax ประจำเดือน
   - สร้าง `payroll_item` ประเภท `tax`
   - ถ้า `tax_calculation_enabled = false` ให้ skip หรือคำนวณเป็น 0

5. **Late/Absent Deduction:**
   - late minutes → หักตาม `late_deduction_per_minute`
   - absent days → หักตาม `absent_deduction_per_day` (หรือ prorate base_salary)
   - สร้าง `payroll_item` ประเภท `deduction`

6. **Accounting Integration:**
   - ตอน approve สร้าง outbox event `accounting.payroll_expense_posted` พร้อม GL entry details
   - รวม `employer_social_security` และ `employer_provident_fund` ใน GL entries

#### 2.5 Flow การคำนวณ Payroll

```
WHEN HR กด "Run Payroll" สำหรับ period:
  1. CREATE payroll_runs (status = 'calculating')
  2. DELETE payroll_items เก่าของ run นี้ (idempotency)
  3. FOR EACH active employee:
     a. base_salary = prorated ตามวันทำงาน
     b. overtime = แยกตาม weekday/weekend/holiday
     c. commission = SUM approved commissions
     d. diligence = ไม่ late/absent → ได้เต็ม
     e. bonus/allowance = จาก benefit_policies
     f. social_security_employee = MIN(base_salary * rate, 750)
     g. social_security_employer = MIN(base_salary * rate, 750) — นายจ้างจ่ายเท่ากัน
     h. pf_base = LEAST(base_salary, pf_wage_cap)
     i. provident_fund_employee = pf_base * employee_pf_rate
     j. provident_fund_employer = pf_base * employer_pf_rate
     k. tax = คำนวณ progressive PIT (เงินได้สุทธิประมาณการรายปี / 12)
     l. late_penalty = late_minutes × rate
     m. absent_penalty = absent_days × rate
  4. INSERT payroll_items ทั้ง earning, deduction และ employer_cost
  5. UPDATE payroll_runs:
     - total_gross = SUM(earning items)
     - total_deductions = SUM(deduction items)
     - total_net = total_gross - total_deductions
     - employer_social_security = SUM(social_security_employer items)
     - employer_provident_fund = SUM(provident_fund_employer items)
     - total_employer_cost = total_gross + employer_social_security + employer_provident_fund
     - status = 'pending_approval'
  6. INSERT outbox_event: 'hr.payroll_calculated'
```

#### 2.6 UI ที่ต้องอัปเดต

> **หลักการ:** ทุกหน้า UI ที่เกี่ยวกับ Payroll ต้องมีปุ่ม "ดูสูตรคำนวณ" (Formula Viewer) เพื่อให้ผู้ใช้เข้าใจและตรวจสอบสูตรที่ใช้ โดยแสดงเป็น BottomSheet หรือ Dialog พร้อมตัวอย่างการคำนวณ

---

##### 2.6.1 Formula Viewer (สูตรคำนวณ) — ใช้ร่วมทุกหน้า

**Widget:** `PayrollFormulaViewerSheet` (Reusable BottomSheet)

**โครงสร้าง:**
```
┌─────────────────────────────────────────────┐
│  📐 สูตรคำนวณ Payroll                    [×] │
├─────────────────────────────────────────────┤
│                                             │
│  ── รายได้ (Earnings) ──                     │
│                                             │
│  1. เงินเดือนพื้นฐาน (Base Salary)            │
│     สูตร: employees.base_salary             │
│     ตัวอย่าง: 30,000.00 × 1 = 30,000.00     │
│     [ดูรายละเอียด ▼]                         │
│                                             │
│  2. ค่าล่วงเวลา (Overtime)                   │
│     สูตร: OT_count × hourly_rate × multiplier│
│     - hourly_rate = base_salary / (work_hours × 30) │
│     - multiplier ตามวัน:                     │
│       · วันธรรมดา × 1.5                      │
│       · วันหยุด (เสาร์-อาทิตย์) × 2.0          │
│       · วันหยุดนักขัตฤกษ์ × 3.0               │
│     ตัวอย่าง: 5 × 125.00 × 1.5 = 937.50     │
│     [ดูรายละเอียด ▼]                         │
│                                             │
│  3. คอมมิชชั่น (Commission)                  │
│     สูตร: SUM(approved commissions)          │
│     ตัวอย่าง: 2,500.00 + 1,800.00 = 4,300.00│
│     [ดูรายละเอียด ▼]                         │
│                                             │
│  4. เบี้ยขยัน (Diligence Allowance)          │
│     เงื่อนไข: late_count = 0 AND absent = 0  │
│     สูตร: hr_settings.diligence_allowance    │
│     ตัวอย่าง: 1,000.00                       │
│     [ดูรายละเอียด ▼]                         │
│                                             │
│  ── การหัก (Deductions) ──                   │
│                                             │
│  5. ประกันสังคม (Social Security)           │
│     สูตร: MIN(base_salary × rate, 750.00)   │
│     ตัวอย่าง: MIN(30,000 × 0.05, 750) = 750 │
│     [ดูรายละเอียด ▼]                         │
│                                             │
│  6. กองทุนสำรองเลี้ยงชีพ (Provident Fund)    │
│     สูตร: LEAST(base_salary, 100,000) × rate│
│     ตัวอย่าง: 30,000 × 0.03 = 900.00        │
│     [ดูรายละเอียด ▼]                         │
│                                             │
│  7. ภาษีเงินได้หัก ณ ที่จ่าย (Tax)            │
│     สูตร: Progressive PIT / 12              │
│     ─ คำนวณเงินได้สุทธิประมาณการรายปี ─       │
│     annual_income = (base+OT+comm+bonus)×12 │
│     - หัก personal_allowance (60,000)        │
│     - หัก tax_allowances (spouse, child...)  │
│     - หัก SS×12, PF×12                       │
│     ─ Progressive Rate ─                     │
│     0-150K: 0% | 150-300K: 5% | ...→35%     │
│     ตัวอย่าง: ดู [รายละเอียดภาษี ▼]           │
│                                             │
│  8. หักสาย/ขาด (Late/Absent Penalty)        │
│     สูตร: late_minutes × rate_per_minute    │
│     สูตร: absent_days × rate_per_day        │
│     ตัวอย่าง: 30 นาที × 5.00 = 150.00       │
│     [ดูรายละเอียด ▼]                         │
│                                             │
│  ── สรุป ──                                 │
│  Gross = 30,000 + 937.50 + 4,300 + 1,000   │
│        = 36,237.50                          │
│  Deductions = 750 + 900 + 1,200 + 150      │
│             = 3,000.00                      │
│  Net Pay = 36,237.50 - 3,000 = 33,237.50   │
│  ─────────────────────────────────          │
│  Employer Cost = 36,237.50 + 750 + 900     │
│               = 37,887.50                   │
│                                             │
└─────────────────────────────────────────────┘
```

**การใช้งาน:**
- ทุกหน้าที่เกี่ยวกับ Payroll มีปุ่ม `IconButton(icon: Icons.calculate)` ใน AppBar หรือใน Card
- กดแล้วเปิด `PayrollFormulaViewerSheet` แสดงสูตรทั้งหมด
- แต่ละรายการมี ExpansionTile สำหรับดูรายละเอียดเพิ่มเติม
- รองรับ Theme (light/dark mode)
- ข้อมูลสูตรเก็บใน `PayrollFormulaData` class (static) เพื่อ reuse

**ไฟล์ที่ต้องสร้าง:**
- `lib/features/erp/presentation/widgets/payroll_formula_viewer_sheet.dart`
- `lib/features/erp/presentation/widgets/payroll_formula_data.dart`

---

##### 2.6.2 PayrollPage (หน้าหลัก Payroll)

**ไฟล์:** `lib/features/erp/presentation/pages/payroll_page.dart`

**โครงสร้างหน้า:**
```
┌─────────────────────────────────────────────┐
│ AppBar: "ระบบเงินเดือน"  [📐สูตร]  [⚙️]     │
├─────────────────────────────────────────────┤
│                                             │
│  ── Payroll Run ปัจจุบัน ──                  │
│  ┌─────────────────────────────────────┐    │
│  │ 📋 รอบเงินเดือน: ก.ค. 2026          │    │
│  │ สถานะ: 🟡 pending_approval          │    │
│  │ พนักงาน: 15 คน                      │    │
│  │ Gross: 450,000.00                   │    │
│  │ Deductions: 45,000.00               │    │
│  │ Net: 405,000.00                     │    │
│  │ Employer Cost: 456,000.00           │    │
│  │ [ดูสูตรคำนวณ] [อนุมัติ] [ยกเลิก]    │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ── รายการพนักงาน ──                        │
│  ┌─────────────────────────────────────┐    │
│  │ 👤 สมชาย ใจดี (EMP001)              │    │
│  │ Base: 30,000 | OT: 937.50           │    │
│  │ Commission: 4,300 | Diligence: 1,000│    │
│  │ SS: 750 | PF: 900 | Tax: 1,200      │    │
│  │ Net: 33,237.50                      │    │
│  │ [ดูรายละเอียด] [ดูสูตร]             │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │ 👤 สมหญิง รักงาน (EMP002)            │    │
│  │ ...                                 │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ── ประวัติ Payroll Runs ──                 │
│  [รอบ มิ.ย. 2026] [✅ approved]              │
│  [รอบ พ.ค. 2026] [✅ approved]              │
│                                             │
│  FAB: [+] สร้าง Payroll Run ใหม่            │
└─────────────────────────────────────────────┘
```

**ฟีเจอร์:**
- **AppBar**: ปุ่ม "ดูสูตร" (Icons.calculate) → เปิด `PayrollFormulaViewerSheet`
- **Payroll Run Card**: แสดงสรุปยอด + ปุ่ม "ดูสูตรคำนวณ" ระดับ Run
- **Employee Payroll Item Card**: แสดงรายการย่อยทั้ง earning/deduction
  - แต่ละรายการมี icon แสดงประเภท (💰 earning, ➖ deduction, 🏢 employer cost)
  - ปุ่ม "ดูสูตร" ระดับพนักงาน → เปิด `PayrollFormulaViewerSheet` พร้อมค่าจริงของพนักงานนั้น
- **Payroll Run Detail Dialog**: แสดง breakdown ทุก payroll_item
- **Actions**: "Run Payroll", "Approve", "Cancel", "Re-run"
- **Status Badge**: แสดงสถานะด้วยสี (draft=เทา, calculating=ฟ้า, pending_approval=เหลือง, approved=เขียว, cancelled=แดง)
- **History List**: รายการ Payroll Runs ที่ผ่านมา พร้อมสถานะ

**ฟิลด์ที่ต้องเพิ่มใน PayrollRun model:**
- `employerSocialSecurity`, `employerProvidentFund`, `totalEmployerCost`
- `employeeCount`

**ฟิลด์ที่ต้องเพิ่มใน PayrollItem model:**
- รองรับ `item_type` ใหม่: `social_security_employer`, `provident_fund_employer`, `late_penalty`, `absent_penalty`
- เพิ่ม `isEmployerCost` flag (แยกจาก `isEarning` และ `isDeduction`)

---

##### 2.6.3 PayrollRunCreateDialog (สร้าง Payroll Run ใหม่)

**ไฟล์:** `lib/features/erp/presentation/widgets/payroll_run_create_dialog.dart`

**โครงสร้าง:**
```
┌─────────────────────────────────────────────┐
│  สร้าง Payroll Run ใหม่              [×]    │
├─────────────────────────────────────────────┤
│                                             │
│  ชื่อรอบ: [เช่น "เงินเดือน กรกฎาคม 2026"]    │
│                                             │
│  วันที่เริ่มต้น: [01/07/2026] 📅             │
│  วันที่สิ้นสุด:  [31/07/2026] 📅             │
│                                             │
│  สาขา: [ทุกสาขา ▼]                          │
│                                             │
│  ── ตัวเลือกการคำนวณ ──                     │
│  ☑ คำนวณภาษี (ถ้าเปิดใน Settings)           │
│  ☑ คำนวณกองทุนสำรองเลี้ยงชีพ               │
│  ☑ คำนวณ OT แยกตามวัน                       │
│  ☐ รวม bonus/allowance จาก benefit_policies │
│                                             │
│  ── พรีวิวพนักงานที่จะคำนวณ ──              │
│  พบ 15 พนักงานที่ active                     │
│  [ดูรายชื่อ ▼]                               │
│                                             │
│  [ดูสูตรคำนวณที่จะใช้]                       │
│                                             │
│           [ยกเลิก]  [เริ่มคำนวณ]             │
└─────────────────────────────────────────────┘
```

**ฟีเจอร์:**
- เลือกช่วงเวลา, สาขา, ตัวเลือกการคำนวณ
- พรีวิวจำนวนพนักงานที่จะถูกคำนวณ
- ปุ่ม "ดูสูตรคำนวณที่จะใช้" → เปิด `PayrollFormulaViewerSheet`
- หลังกด "เริ่มคำนวณ" แสดง progress indicator ระหว่างคำนวณ

---

##### 2.6.4 PayrollItemDetailPage (รายละเอียดรายการพนักงาน)

**ไฟล์:** `lib/features/erp/presentation/pages/payroll_item_detail_page.dart`

**โครงสร้าง:**
```
┌─────────────────────────────────────────────┐
│  AppBar: "สมชาย ใจดี - ก.ค. 2026"  [📐สูตร] │
├─────────────────────────────────────────────┤
│                                             │
│  ── ข้อมูลพนักงาน ──                         │
│  รหัส: EMP001 | ตำแหน่ง: พนักงานขาย         │
│  เงินเดือนพื้นฐาน: 30,000.00                │
│  อัตรา PF: 3% | วิธีจ่าย: โอนธนาคาร         │
│                                             │
│  ── รายได้ (Earnings) ──          [ดูสูตร]   │
│  ┌─────────────────────────────────────┐    │
│  │ 💰 เงินเดือนพื้นฐาน     30,000.00   │    │
│  │    สูตร: base_salary               │    │
│  ├─────────────────────────────────────┤    │
│  │ 💰 ค่าล่วงเวลา           937.50    │    │
│  │    สูตร: 5 ชม × 125.00 × 1.5       │    │
│  │    [ดูรายละเอียด OT ▼]              │    │
│  │    - วันจันทร์ 3 ชม × 1.5 = 562.50  │    │
│  │    - วันเสาร์ 2 ชม × 2.0 = 375.00   │    │
│  ├─────────────────────────────────────┤    │
│  │ 💰 คอมมิชชั่น          4,300.00    │    │
│  │    สูตร: SUM(approved)             │    │
│  │    [ดูรายการคอมมิชชั่น ▼]           │    │
│  │    - INV-001: 2,500.00             │    │
│  │    - INV-002: 1,800.00             │    │
│  ├─────────────────────────────────────┤    │
│  │ 💰 เบี้ยขยัน            1,000.00    │    │
│  │    เงื่อนไข: ไม่สาย/ไม่ขาด          │    │
│  ├─────────────────────────────────────┤    │
│  │ รวมรายได้              36,237.50   │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ── การหัก (Deductions) ──       [ดูสูตร]   │
│  ┌─────────────────────────────────────┐    │
│  │ ➖ ประกันสังคม            750.00    │    │
│  │    สูตร: MIN(30,000×0.05, 750)     │    │
│  ├─────────────────────────────────────┤    │
│  │ ➖ กองทุนสำรองเลี้ยงชีพ    900.00   │    │
│  │    สูตร: 30,000 × 0.03             │    │
│  ├─────────────────────────────────────┤    │
│  │ ➖ ภาษีเงินได้          1,200.00    │    │
│  │    สูตร: Progressive PIT / 12      │    │
│  │    [ดูรายละเอียดภาษี ▼]             │    │
│  │    - เงินได้ประมาณการรายปี: 434,850 │    │
│  │    - หัก personal: 60,000           │    │
│  │    - หัก SS×12: 9,000               │    │
│  │    - หัก PF×12: 10,800              │    │
│  │    - เงินได้สุทธิ: 355,050           │    │
│  │    - ภาษีรายปี: 14,400              │    │
│  │    - ภาษี/เดือน: 1,200              │    │
│  ├─────────────────────────────────────┤    │
│  │ ➖ หักสาย                150.00     │    │
│  │    สูตร: 30 นาที × 5.00            │    │
│  ├─────────────────────────────────────┤    │
│  │ รวมการหัก               3,000.00   │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ── สรุป ──                                 │
│  ┌─────────────────────────────────────┐    │
│  │ รายได้รวม (Gross)     36,237.50    │    │
│  │ การหักรวม           (3,000.00)    │    │
│  │ ─────────────────────────────────── │    │
│  │ เงินสุทธิ (Net Pay)   33,237.50    │    │
│  │                                     │    │
│  │ ── ส่วนนายจ้าง ──                   │    │
│  │ ประกันสังคม (นายจ้าง)   750.00     │    │
│  │ กองทุน (นายจ้าง)       900.00      │    │
│  │ ต้นทุนรวม (Employer) 37,887.50     │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  [ดูสูตรคำนวณทั้งหมด]                       │
└─────────────────────────────────────────────┘
```

**ฟีเจอร์:**
- แสดง breakdown ทุก payroll_item พร้อมสูตรและค่าจริง
- ExpansionTile สำหรับ OT รายวัน, Commission รายบิล, Tax breakdown
- ปุ่ม "ดูสูตร" ในแต่ละส่วน (Earnings, Deductions, Summary)
- ปุ่ม "ดูสูตรคำนวณทั้งหมด" ด้านล่าง → เปิด `PayrollFormulaViewerSheet`
- แสดงส่วนนายจ้าง (Employer Cost) แยกจากส่วนพนักงาน

---

##### 2.6.5 HrSettingsPage (ตั้งค่า HR/Payroll)

**ไฟล์:** `lib/features/erp/presentation/pages/hr_settings_page.dart`

**โครงสร้าง:**
```
┌─────────────────────────────────────────────┐
│  AppBar: "ตั้งค่า HR"               [📐สูตร] │
├─────────────────────────────────────────────┤
│                                             │
│  ── การลงเวลา ──                            │
│  โหมด: [Manual ▼]                           │
│  Flexible Hours: [☐]                        │
│  ชั่วโมงทำงาน/วัน: [8.00]                   │
│                                             │
│  ── ค่าล่วงเวลา (OT) ──          [ดูสูตร]   │
│  OT วันธรรมดา (×): [1.50]                   │
│  OT วันหยุด (×): [2.00]                     │
│  OT วันหยุดนักขัตฤกษ์ (×): [3.00]           │
│  💡 สูตร: OT = count × hourly_rate × mult   │
│                                             │
│  ── ประกันสังคม ──              [ดูสูตร]   │
│  อัตรา (%): [5.00]                          │
│  สูงสุด/เดือน (THB): [750.00]               │
│  💡 สูตร: MIN(salary × rate, max)           │
│                                             │
│  ── เบี้ยขยัน ──                  [ดูสูตร]   │
│  จำนวน (THB): [1,000.00]                    │
│  💡 เงื่อนไข: ไม่สาย/ไม่ขาด → ได้เต็ม         │
│                                             │
│  ── กองทุนสำรองเลี้ยงชีพ ──      [ดูสูตร]   │
│  อัตราพนักงาน (%): [3.00]                   │
│  อัตรานายจ้าง (%): [3.00]                   │
│  ฐานสูงสุด (THB): [100,000.00]              │
│  💡 สูตร: LEAST(salary, cap) × rate         │
│                                             │
│  ── ภาษีเงินได้ ──                [ดูสูตร]   │
│  เปิดใช้การคำนวณภาษี: [☐]                   │
│  💡 สูตร: Progressive PIT (0%-35%) / 12     │
│  [ดูตารางอัตราภาษี ▼]                       │
│  ┌─────────────────────────────────┐        │
│  │ 0 - 150,000      → 0% (ยกเว้น)  │        │
│  │ 150,001 - 300,000 → 5%         │        │
│  │ 300,001 - 500,000 → 10%        │        │
│  │ 500,001 - 750,000 → 15%        │        │
│  │ 750,001 - 1M     → 20%         │        │
│  │ 1M - 2M          → 25%         │        │
│  │ 2M - 5M          → 30%         │        │
│  │ 5M+              → 35%         │        │
│  └─────────────────────────────────┘        │
│                                             │
│  ── การหักสาย/ขาด ──             [ดูสูตร]   │
│  หักสาย/นาที (THB): [5.00]                  │
│  หักขาด/วัน (THB): [500.00]                 │
│  💡 สูตร: late_min × rate + absent × rate   │
│                                             │
│  ── วันหยุดนักขัตฤกษ์ ──                    │
│  [จัดการวันหยุด] → ไปยัง ThaiHolidaysPage  │
│  ปี 2026: 13 วันหยุด                        │
│                                             │
│           [บันทึก]                          │
└─────────────────────────────────────────────┘
```

**ฟีเจอร์:**
- ทุกส่วนมีปุ่ม "ดูสูตร" แสดงสูตรที่ใช้คำนวณ
- แสดง `💡 สูตร:` แบบ inline ใต้แต่ละฟิลด์
- ตารางอัตราภาษีแบบ ExpansionTile
- ลิงก์ไปยัง ThaiHolidaysPage สำหรับจัดการวันหยุด
- Validation: rate ต้อง 0-100%, cap ต้อง > 0

---

##### 2.6.6 EmployeeFormPage (เพิ่ม/แก้ไขพนักงาน)

**ไฟล์:** `lib/features/erp/presentation/pages/employee_form_page.dart`

**ฟิลด์ใหม่ที่ต้องเพิ่ม:**
```
── ข้อมูลการจ่ายเงิน ──            [ดูสูตร]
  วิธีจ่าย: [โอนธนาคาร ▼]
  ธนาคาร: [กสิกรไทย ▼]
  เลขบัญชี: [xxx-xxx-xxxx]

── ข้อมูลภาษี ──                  [ดูสูตร]
  ค่าลดหย่อนส่วนบุคคล (THB): [60,000.00]
  ค่าใช้จ่ายตามจริง (THB): [0.00]
  อัตรากองทุนสำรองเลี้ยงชีพ (%): [3.00]
  [จัดการค่าลดหย่อนภาษี] → ไปยัง TaxAllowancePage

── สูตรที่ใช้กับพนักงานนี้ ──
  💡 PF = LEAST(salary, cap) × 3%
  💡 Tax = Progressive PIT / 12
  💡 SS = MIN(salary × 5%, 750)
  [ดูสูตรเต็ม]
```

---

##### 2.6.7 TaxAllowancePage (ค่าลดหย่อนภาษีพนักงาน)

**ไฟล์:** `lib/features/erp/presentation/pages/tax_allowance_page.dart`

**โครงสร้าง:**
```
┌─────────────────────────────────────────────┐
│  AppBar: "ค่าลดหย่อนภาษี - สมชาย" [📐สูตร]  │
├─────────────────────────────────────────────┤
│                                             │
│  ── สูตรการคำนวณภาษี ──                     │
│  เงินได้สุทธิ = รายได้ประมาณการรายปี        │
│    - ค่าลดหย่อนส่วนบุคคล (60,000)           │
│    - ค่าลดหย่อนอื่นๆ (ด้านล่าง)             │
│    - ประกันสังคม × 12                       │
│    - กองทุน × 12                            │
│  ภาษี = Progressive Rate (0%-35%)           │
│  ภาษี/เดือน = ภาษีรายปี / 12               │
│                                             │
│  ── รายการค่าลดหย่อน ──                     │
│  ┌─────────────────────────────────────┐    │
│  │ คู่สมรส              60,000.00     │    │
│  │ บุตร (2 คน × 30,000) 60,000.00     │    │
│  │ ประกันชีวิต           50,000.00    │    │
│  │ เบี้ยประกันสุขภาพ     25,000.00    │    │
│  │ บริจาค                10,000.00    │    │
│  └─────────────────────────────────────┘    │
│  รวมค่าลดหย่อน: 205,000.00                  │
│                                             │
│  ── พรีวิวภาษีโดยประมาณ ──                 │
│  รายได้ประมาณการรายปี: 434,850.00          │
│  - หักส่วนบุคคล: (60,000)                  │
│  - หักค่าลดหย่อน: (205,000)                 │
│  - หัก SS×12: (9,000)                       │
│  - หัก PF×12: (10,800)                      │
│  เงินได้สุทธิ: 150,050.00                   │
│  ภาษีรายปี: 50.00 (150,050 - 150,000 × 5%) │
│  ภาษี/เดือน: 4.17                           │
│                                             │
│  FAB: [+] เพิ่มค่าลดหย่อน                   │
└─────────────────────────────────────────────┘
```

**ฟีเจอร์:**
- แสดงสูตรการคำนวณภาษีด้านบน
- CRUD ค่าลดหย่อน (เพิ่ม/แก้ไข/ลบ)
- พรีวิวภาษีโดยประมาณแบบ real-time
- ปุ่ม "ดูสูตร" → เปิด `PayrollFormulaViewerSheet` ส่วนภาษี
- เลือกปีภาษี (effective_year)

---

##### 2.6.8 ThaiHolidaysPage (จัดการวันหยุดนักขัตฤกษ์)

**ไฟล์:** `lib/features/erp/presentation/pages/thai_holidays_page.dart`

**โครงสร้าง:**
```
┌─────────────────────────────────────────────┐
│  AppBar: "วันหยุดนักขัตฤกษ์"        [📅]    │
├─────────────────────────────────────────────┤
│  ปี: [2026 ▼]                               │
│                                             │
│  ── วันหยุดที่ใช้คำนวณ OT ──                 │
│  💡 OT วันหยุดนักขัตฤกษ์ × 3.0              │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │ 📅 1 ม.ค. 2026  วันปีใหม่           │    │
│  │ 📅 13 ม.ค. 2026 วันเด็กแห่งชาติ      │    │
│  │ 📅 16 ม.ค. 2026 วันครูแห่งชาติ       │    │
│  │ 📅 ...                              │    │
│  │ 📅 31 ธ.ค. 2026 วันสิ้นปี           │    │
│  └─────────────────────────────────────┘    │
│  รวม: 13 วัน                                │
│                                             │
│  FAB: [+] เพิ่มวันหยุด                       │
│  [Seed วันหยุดประจำปี] (auto-fill)         │
└─────────────────────────────────────────────┘
```

**ฟีเจอร์:**
- แสดงรายการวันหยุดตามปี
- CRUD วันหยุด (เพิ่ม/แก้ไข/ลบ)
- ปุ่ม "Seed วันหยุดประจำปี" — auto-fill วันหยุดมาตรฐานของไทย
- แสดงประเภทวันหยุด (public, religious, substitution, special)
- ใช้สำหรับ RPC ตรวจสอบ OT multiplier

---

##### 2.6.9 ข้อเสนอเพิ่มเติม (Additional UI Considerations)

> **หมายเหตุ:** ข้อเสนอเหล่านี้ควร implement ใน Phase นี้หรือ Phase ถัดไป ขึ้นอยู่กับ priority

**1. สิทธิ์การเข้าถึง (Permission-Based UI)**

ตามระดับสิทธิ์ 3 ขั้น (ดูจากหัวข้อ "ระดับสิทธิ์ 3 ขั้น"):

| ระดับ | สิทธิ์ใน Payroll UI | ที่ต้องแสดง |
|-------|---------------------|-------------|
| **Admin/Manager** | Run, Approve, Cancel, Re-run, ตั้งค่า HR, ดู Employer Cost | ปุ่ม "อนุมัติ", "ยกเลิก", "Re-run", "ตั้งค่า" |
| **Editor** | Run Payroll, แก้ไขข้อมูล Attendance/Commission, ดูสูตร | ปุ่ม "Run Payroll", "แก้ไขข้อมูล", ไม่มีปุ่ม "อนุมัติ" |
| **Viewer** | ดู Payroll summary, สูตร, ประวัติ | ไม่มี action buttons ใดๆ นอกจาก "ดูสูตร" |
| **Employee (self)** | ดูสลิปเงินเดือนตัวเอง | หน้า `MyPaySlipPage` แยก |

**2. Error Handling + Loading States**

- **Calculation Loading:** แสดง `LinearProgressIndicator` หรือ `CircularProgressIndicator` ระหว่าง RPC คำนวณ (อาจใช้เวลานานถ้าพนักงานเยอะ)
- **Error Snackbar:** แสดง error message เมื่อ RPC คำนวณล้มเหลว (เช่น HR settings ไม่มี, ไม่มีพนักงาน active, ไม่มีวันหยุด)
- **Validation Dialog:** ก่อน Run Payroll ถ้าพบพนักงานที่ไม่มี `base_salary` ให้แสดง warning list
- **Retry Button:** หากคำนวณล้มเหลว ให้กด "ลองใหม่" ได้ทันที

**3. สลิปเงินเดือน (Pay Slip) — สำคัญตามกฎหมายไทย**

**หน้า:** `MyPaySlipPage` / `PaySlipPrintPage`

**ฟีเจอร์:**
- แสดงสลิปเงินเดือนพร้อมรายละเอียดทั้ง earning/deduction
- ปุ่ม **ดาวน์โหลด PDF** และ **ส่งอีเมล** ให้พนักงาน
- แสดง QR code หรือ reference number สำหรับตรวจสอบ
- รองรับการพิมพ์ (Print)
- แสดงสูตรคำนวณใน pay slip (optional footer: "สูตรคำนวณ: ...")

**ไฟล์ที่ต้องสร้าง:**
- `pay_slip_page.dart`
- `pay_slip_pdf_generator.dart`
- `pay_slip_email_sender.dart`

**4. Approval Workflow + Audit Trail**

**หน้า:** `PayrollApprovalPage` หรือ dialog ใน `PayrollPage`

**ฟีเจอร์:**
- แสดงประวัติการอนุมัติ:
  - ใครอนุมัติ
  - เวลาไหน
  - IP address / device
  - หมายเหตุ (notes)
- แสดง diff หากมีการ re-run (เปลี่ยนแปลงค่าใดบ้าง)
- ปุ่ม "Approve with note" บังคับใส่หมายเหตุ (optional)
- ส่ง notification ไปยังพนักงานเมื่อ payroll approved

**5. Employee Self-Service (My Payroll)**

**หน้า:** `MyPayrollPage` (เข้าจากเมนูพนักงาน)

**ฟีเจอร์:**
- ดูประวัติเงินเดือนตัวเอง (12 เดือนล่าสุด)
- ดู/ดาวน์โหลด pay slip
- ดูสูตรคำนวณ (read-only) — ช่วยให้พนักงานเข้าใจเงินเดือน
- ไม่สามารถแก้ไขหรือคำนวณ payroll ได้

**6. Routes & Navigation**

**ไฟล์:** `lib/main.dart` หรือ `lib/router.dart`

**Routes ที่ต้องเพิ่ม:**
```dart
'/erp/payroll': PayrollPage(professionId: professionId)
'/erp/payroll/create': PayrollRunCreateDialog()
'/erp/payroll/:runId': PayrollItemDetailPage()
'/erp/hr-settings': HrSettingsPage(professionId: professionId)
'/erp/employees/:employeeId/tax-allowances': TaxAllowancePage()
'/erp/thai-holidays': ThaiHolidaysPage(professionId: professionId)
'/erp/my-payroll': MyPayrollPage()
'/erp/my-pay-slip/:runId': PaySlipPage()
```

**7. Search, Filter และ Sorting**

**ใน `PayrollPage`:**
- ค้นหาพนักงานจากชื่อ/รหัส
- Filter ตามสาขา
- Filter ตามสถานะ Payroll Run
- Sort ตาม Net Pay, Employee Code, ชื่อ

**ใน `PayrollHistoryPage`:**
- Filter ตามปี/เดือน
- เปรียบเทียบ payroll รอบปัจจุบันกับรอบก่อน (YoY/MoM)

**8. Payroll Dashboard / Analytics**

**หน้า:** `PayrollDashboardPage` (อาจ integrate กับ ERP Dashboard)

**ฟีเจอร์:**
- กราฟแสดงยอด payroll รายเดือน (Gross, Net, Employer Cost)
- กราฟเปรียบเทียบค่าใช้จ่ายประเภทต่างๆ (SS, PF, Tax, OT)
- Top 10 คนที่มี OT สูงสุด
- Top 10 คนที่มี Commission สูงสุด
- สรุปจำนวนวันหยุดที่ใช้คำนวณ OT

**9. Empty States**

| หน้า | กรณี Empty | ข้อความ + Action |
|------|-----------|-------------------|
| `PayrollPage` | ยังไม่มี Payroll Run | "ยังไม่มีรอบเงินเดือน" + ปุ่ม "สร้าง Payroll Run แรก" |
| `PayrollPage` (employee list) | Run มีแต่ไม่มีพนักงาน active | "ไม่พบพนักงานที่ active ในสาขานี้" |
| `TaxAllowancePage` | ยังไม่มีค่าลดหย่อน | "ยังไม่มีค่าลดหย่อนภาษี" + ปุ่ม "เพิ่มค่าลดหย่อน" |
| `ThaiHolidaysPage` | ยังไม่มีวันหยุดของปีนี้ | "ยังไม่มีวันหยุดปี 2026" + ปุ่ม "Seed วันหยุดประจำปี" |
| `MyPayrollPage` | พนักงานยังไม่เคยได้รับเงินเดือน | "ยังไม่มีประวัติเงินเดือน" |

**10. Confirmation Dialog สำหรับ Action ที่ไม่สามารถย้อนกลับได้ (Irreversible Actions)**

| Action | Dialog ที่ต้องแสดง |
|--------|---------------------|
| **Approve Payroll** | "ยืนยันการอนุมัติ Payroll รอบ [ชื่อรอบ]? หลังอนุมัติจะไม่สามารถแก้ไขได้ และจะสร้างรายการบัญชีอัตโนมัติ" |
| **Cancel Payroll Run** | "ยืนยันการยกเลิก Payroll Run นี้? ข้อมูลที่คำนวณไว้จะถูกลบทั้งหมด" |
| **Re-run Payroll** | "การคำนวณใหม่จะลบรายการเดิมทั้งหมดและคำนวณใหม่ ต้องการดำเนินการต่อหรือไม่?" |
| **ลบวันหยุด/ค่าลดหย่อน** | "ยืนยันการลบ [รายการ]? การกระทำนี้ไม่สามารถย้อนกลับได้" |
| **เปลี่ยน tax_calculation_enabled** | "การเปิด/ปิดการคำนวณภาษีจะมีผลกับ Payroll Run รอบถัดไป ต้องการดำเนินการต่อหรือไม่?" |

**11. Responsive Layout (Mobile / Tablet / Desktop)**

- **Mobile:** แสดง Card แบบ List เต็มความกว้าง, Formula Viewer เป็น full-screen BottomSheet
- **Tablet/Desktop:** แสดง `PayrollItemDetailPage` แบบ side-by-side (รายชื่อพนักงานด้านซ้าย, รายละเอียดด้านขวา) ด้วย `LayoutBuilder`/`MediaQuery` ตาม breakpoint ที่ใช้อยู่ในระบบ ERP ปัจจุบัน
- **Formula Viewer:** บน Desktop ใช้ Dialog แทน BottomSheet (กว้างพอสำหรับตาราง progressive tax rate)

##### 2.6.10 สรุปไฟล์ Flutter ที่ต้องสร้าง/แก้ไข

| ไฟล์ | สถานะ | รายละเอียด |
|------|--------|------------|
| `payroll_formula_viewer_sheet.dart` | 🆕 สร้างใหม่ | Reusable BottomSheet แสดงสูตรทั้งหมด |
| `payroll_formula_data.dart` | 🆕 สร้างใหม่ | Static data ของสูตรทั้งหมด (สำหรับ reuse) |
| `payroll_page.dart` | ✏️ แก้ไข | เพิ่ม Formula button, employer cost, item breakdown |
| `payroll_run_create_dialog.dart` | 🆕 สร้างใหม่ | Dialog สร้าง payroll run พร้อมตัวเลือก |
| `payroll_item_detail_page.dart` | 🆕 สร้างใหม่ | รายละเอียดรายการพนักงาน + สูตร |
| `hr_settings_page.dart` | ✏️ แก้ไข | เพิ่ม PF, tax, late/absent settings + สูตร inline |
| `employee_form_page.dart` | ✏️ แก้ไข | เพิ่ม tax info, bank account, PF rate |
| `tax_allowance_page.dart` | 🆕 สร้างใหม่ | CRUD ค่าลดหย่อนภาษี + พรีวิวภาษี |
| `thai_holidays_page.dart` | 🆕 สร้างใหม่ | CRUD วันหยุดนักขัตฤกษ์ |
| `payroll_approval_page.dart` | 🆕 สร้างใหม่ (optional) | Audit trail + approval workflow |
| `my_payroll_page.dart` | 🆕 สร้างใหม่ (optional) | Employee self-service payroll history |
| `pay_slip_page.dart` | 🆕 สร้างใหม่ (optional) | Pay slip viewer + PDF print |
| `pay_slip_pdf_generator.dart` | 🆕 สร้างใหม่ (optional) | PDF generation for pay slip |
| `payroll_dashboard_page.dart` | 🆕 สร้างใหม่ (optional) | Analytics dashboard |
| `payroll_run.dart` (model) | ✏️ แก้ไข | เพิ่ม employer cost fields |
| `payroll_item.dart` (model) | ✏️ แก้ไข | เพิ่ม item types + isEmployerCost |
| `hr_settings.dart` (model) | ✏️ แก้ไข | เพิ่ม PF rates, tax flag, late/absent rates |
| `employee.dart` (model) | ✏️ แก้ไข | เพิ่ม tax fields, bank info, PF rate |
| `phase_three_provider.dart` | ✏️ แก้ไข | รองรับคำนวณใหม่ + formula data |
| `phase_three_repository.dart` | ✏️ แก้ไข | รองรับ RPC ใหม่ + tax allowance CRUD |
| `main.dart` / `router.dart` | ✏️ แก้ไข | เพิ่ม routes ใหม่ |

#### 2.7 การทดสอบ (Test Plan)

1. **Test script:** `test_payroll_calculation.sql`
2. **Cases ที่ต้องทดสอบ:**
   - Employee ได้แค่เงินเดือน + ประกันสังคม
   - Employee มี OT วันธรรมดา + วันหยุด
   - Employee มี commission approved
   - Employee ได้ diligence allowance
   - Employee มี late → ไม่ได้ diligence + ถูกหัก late
   - Employee มี provident fund (ตรวจสอบ wage cap 100,000)
   - Employee มี tax (เลือกเปิด tax_calculation_enabled)
   - Employee มี tax allowances (spouse, child, insurance)
   - ตรวจสอบ employer_social_security + employer_provident_fund คำนวณถูก
   - ตรวจสอบ total_employer_cost = total_gross + employer_ss + employer_pf
   - OT วันหยุดนักขัตฤกษ์ (ต้องมีข้อมูลใน `thai_holidays`)
   - Re-run payroll ต้อง idempotent
   - Approve payroll แล้วสร้าง outbox event ทั้ง `hr.payroll_approved` และ `accounting.payroll_expense_posted`

### 3. การอนุมัติ Payroll

```
WHEN Manager/Admin กด "Approve Payroll":
  1. CHECK permission: user มีสิทธิ์ Full ใน module 'hr'
  2. CHECK payroll_runs.status = 'pending_approval'
  3. UPDATE payroll_runs:
     - status = 'approved'
     - approved_by = current_user.id
     - approved_at = now()
  4. INSERT outbox_event:
     - event_type = 'hr.payroll_approved'
     - payload = { payroll_run_id, approved_by, approved_at, total_net }
  5. INSERT outbox_event:
     - event_type = 'accounting.payroll_expense_posted'
     - payload = {
         payroll_run_id,
         total_gross, total_deductions, total_net,
         employer_social_security, employer_provident_fund,
         gl_entries: [
           { account_code: '6101', debit: total_gross, credit: 0 },        // ค่าใช้จ่ายเงินเดือน
           { account_code: '2191', debit: 0, credit: total_net },          // เงินสด/ธนาคารที่จ่าย
           { account_code: '2192', debit: 0, credit: social_security_employee + pf_employee + tax }, // ภาษี+ประกันสังคม+กองทุนหัก
           { account_code: '6102', debit: employer_social_security + employer_pf, credit: 0 }        // ค่าใช้จ่ายนายจ้างส่วนเพิ่ม
         ]
       }
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
- UI: `MyLeavePage`, `LeaveApprovalPage`, `LeaveCalendarPage`, `EmployeeRolePage`, `EmployeeRoleAssignmentPage`, `MyPermissionsPage`, `FeatureTogglePage`
- Business Logic: Leave approval workflow, Permission checks

### Phase 5: Advanced Features
- Attendance device integration (fingerprint, face recognition)
- Geofencing for clock in/out
- Payroll batch export (bank transfer file)
- Employee self-service portal (view payslip, request leave, view commission)
- KPI integration (employee performance metrics)

---

## ภาคผนวก: แผนการดำเนินงานระบบการอนุมัติและตั้งค่าผู้ใช้รายแรก (Owner Onboarding) ขององค์กร

การพัฒนาระบบสมัคร การอนุมัติ และการผูกสิทธิ์บทบาทหน้าที่สำหรับผู้ใช้รายแรกที่เป็นเจ้าขององค์กร (Owner) ของอาชีพ/องค์กรที่สร้างขึ้นใหม่ (`profession_id`) ให้ครบถ้วนสมบูรณ์

### สิ่งที่ต้องให้ผู้ใช้งานพิจารณา (User Review Required)
- จะมีการสร้าง Database Trigger ในตาราง `registration_applications` เพื่อผูกผู้ใช้ที่ได้รับการอนุมัติรายแรกเข้ากับบทบาท `owner` ในตาราง `employee_roles` โดยอัตโนมัติ
- จะทำการปรับปรุง UI ในหน้าแก้ไขโปรไฟล์/สมัครอาชีพเพื่อเพิ่มตัวเลือกให้ผู้ใช้ระบุว่าต้องการ "จดทะเบียนสร้างองค์กรใหม่ในฐานะผู้ดูแลระบบรายแรก (Owner)"
- ปรับปรุง UI หน้า `ApplicationReviewPage` ของ Sheserved Admin เพื่อแสดงสัญลักษณ์ผู้สมัครบทบาท Owner และจำลองหน้าต่างแจ้งเตือนการอนุมัติที่สำเร็จอย่างชัดเจน

### รายการแก้ไขที่เสนอ (Proposed Changes)

#### 1. ระดับฐานข้อมูล (Supabase Migrations)
- สร้าง Trigger Function ชื่อ `on_registration_application_approved_trigger()` ในตาราง `registration_applications`
- เมื่อสถานะใบสมัครเปลี่ยนเป็น `'approved'`:
  1. ไปค้นหา `id` ของบทบาท `'owner'` จากตาราง `organization_roles` ของ `profession_id` นั้นๆ
  2. ไปค้นหา `id` ของสาขาหลัก (MAIN) จากตาราง `organization_branches` ของ `profession_id` นั้นๆ
  3. เพิ่มข้อมูลการผูกบทบาทลงในตาราง `employee_roles` สำหรับผู้สมัคร (`user_id`)
  4. หากพบว่าเป็นองค์กรใหม่ ให้ทำการตั้งค่า Feature Flags และเปิดใช้งานโมดูลเบื้องต้นตามความเหมาะสม

#### 2. ระดับแอปพลิเคชัน (Dart Repositories & UI)
- **`registration_repository.dart`**: ปรับปรุงฟังก์ชัน `approveApplication` เพื่อรองรับการซิงค์ข้อมูลลง Local Database ให้รองรับข้อมูลการผูกบทบาท `employee_roles` ในกรณีที่ทำงานในโหมด Offline
- **`profile_page.dart`**: ในหน้าต่างเลือกเปลี่ยนอาชีพ/สมัครใช้งาน หากผู้ใช้งานเลือกหมวดหมู่กลุ่มบริการ (เช่น คลินิก/ศูนย์ หรือ ผู้เชี่ยวชาญ/ร้านค้า) ให้เพิ่มปุ่มสวิตช์: **"ต้องการสร้างและจดทะเบียนองค์กรใหม่ (สมัครเป็นผู้ดูแลระบบคนแรก/Owner)"**
  - หากเปิดสวิตช์ดังกล่าว ระบบจะแนบสถานะ `'is_owner_request': 'true'` ลงในข้อมูล `registration_data` JSON
- **`application_review_page.dart`**: บนการ์ดรายการผู้สมัคร หากพบว่ามีการร้องขอจดทะเบียนองค์กรใหม่ ให้แสดงป้ายสัญลักษณ์สุดหรู: `👑 ขอจดทะเบียน Owner`
  - ในหน้าละเอียดใบสมัคร (`ApplicationDetailPage`) ให้เน้นย้ำสัญลักษณ์ข้อมูลดังกล่าวอย่างชัดเจน
  - เมื่อแอดมินอนุมัติสำเร็จ ให้แสดงป๊อปอัปแจ้งผลการตั้งค่า: *"อนุมัติผู้ดูแลระบบ/Owner รายแรกขององค์กรสำเร็จ! ระบบได้เปิดใช้งานสิทธิ์จัดการองค์กรและผูกบทบาท 'Owner' เรียบร้อยแล้ว"*

### แผนการตรวจสอบความถูกต้อง (Verification Plan)
- ทำการรัน SQL migration ในฐานข้อมูล Supabase
- เปิดแอปพลิเคชัน Flutter -> ไปที่หน้าข้อมูลส่วนตัว (Profile Page) -> เลือกสมัครอาชีพ "คลินิก/ศูนย์" -> เปิดใช้งานตัวเลือกจดทะเบียนองค์กรใหม่ -> กดส่งคำขอสมัคร
- สลับหน้าจอมาที่ `ApplicationReviewPage` ในฐานะ Sheserved Admin
- ตรวจสอบว่ามีป้ายสถานะ `👑 ขอจดทะเบียน Owner` แสดงอยู่บนรายการหรือไม่
- กดอนุมัติ และดูป๊อปอัปแสดงผลลัพธ์
- ตรวจสอบในตารางฐานข้อมูลจริงว่าข้อมูลผู้ใช้ถูกเพิ่มเข้าไปยังตาราง `employee_roles` ในตำแหน่งบทบาท `owner` เรียบร้อยแล้วหรือไม่

---

## ภาคผนวก: แผนการพัฒนา UI จัดการสิทธิ์ผู้ใช้ (User-Role & Permission Management)

> สอดคล้องกับ `ERP_CORE_ARCHITECTURE.md` Phase 0 (RBAC, Reliability Core, Feature Flags) และ Phase 4 ของเอกสารนี้

### 1. สถานะปัจจุบัน (Completed)
- ✅ `RoleManagementPage` (`/erp/roles`) สำหรับสร้าง/จัดการ `organization_roles` — พร้อม UI ใหม่แบบ glassmorphism + toggle เปิด/ระงับ role
- ✅ `PermissionManagementPage` สำหรับกำหนดสิทธิ์ module ของแต่ละ role
- ✅ `EmployeeRole` model (`employee_role.dart`) และ repository methods `assignEmployeeRole()`, `toggleEmployeeRole()` ใช้งานได้
- ✅ `EmployeeRoleAssignmentPage` (`/erp/settings/employee-roles`) สำหรับมอบ/ถอน role ให้ user
- ✅ `MyPermissionsPage` (`/erp/settings/my-permissions`) ให้ user ดูสิทธิ์ตัวเอง
- ✅ `PermissionDeniedWidget` reusable ใช้ใน `ProcurementPage` และ module อื่น
- ✅ Dashboard การ์ด `Role Management` ผูกกับ `/erp/settings/employee-roles` และมีปุ่ม "จัดการตำแหน่ง" ใน AppBar เพื่อสร้าง role ใหม่

> **หมายเหตุสำคัญ:** ตาราง `employee_roles` ใช้คอลัมน์ `user_id` (ไม่ใช่ `employee_id`) และไม่มีคอลัมน์ `is_hq` — การกำหนด HQ ใช้ `branch_id = NULL`

### 2. หลักการออกแบบ (Design Principles)
ตาม `ERP_CORE_ARCHITECTURE.md`:
1. **Tenant-based Isolation:** ข้อมูล role/permission แยกตาม `profession_id`
2. **Application Layer Permission Control:** ไม่ใช้ `auth.uid()` ใน RLS ตาม `auth_data_guidelines.md`
3. **User ID from `ServiceLocator`:** ไม่เรียก `Supabase.instance.client.auth.currentUser` โดยตรง
4. **Multi-Branch Support:** สิทธิ์สามารถกำหนดระดับสาขา (`branch_id` เฉพาะ) หรือส่วนกลาง (`branch_id = NULL` = HQ) ได้
5. **Audit Trail:** บันทึกการเปลี่ยนแปลงสิทธิ์ลงตาราง audit ที่มีอยู่แล้ว

### 3. หน้าจอที่ต้องเพิ่ม/ปรับ

#### 3.1 `EmployeeRoleAssignmentPage` (Admin/Manager)
- **Route:** `/erp/settings/employee-roles`
- **File:** `lib/features/erp/presentation/pages/employee_role_assignment_page.dart`
- **Features:**
  - รายการ user ทั้งหมดใน profession (พร้อม search/filter ตามชื่อ, username, email, phone) — รวม user ที่ยังไม่มี role ด้วย
  - Dialog มอบ role ให้ user เลือก role จาก active roles และกำหนด scope HQ/สาขา
  - ถอน role ด้วยการกด ❌ บน Chip
  - เปิด/ปิด (toggle) role assignment แบบ real-time
  - ปุ่ม "จัดการตำแหน่ง" ใน AppBar เพื่อไปสร้าง role ใหม่
- **Data Source:** RPC `get_users_with_roles` โหลด user พร้อม roles ทั้งหมด
- **Scope:** สาขาเฉพาะ (`branch_id`) หรือทั้งองค์กร (`branch_id = NULL` = HQ)
- **Filter:** แสดงเฉพาะ active roles ใน dropdown มอบ role

#### 3.2 `MyPermissionsPage` (Self-service)
- **Route:** `/erp/settings/my-permissions`
- **File:** `lib/features/erp/presentation/pages/my_permissions_page.dart`
- **Data Source:** ใช้ `get_user_roles_and_permissions` RPC ที่มีอยู่แล้ว (ผ่าน `loadCurrentUserRoles()` ใน `PhaseZeroNotifier`)
- **Features:**
  - แสดงรายการโมดูลทั้งหมด
  - แสดงระดับสิทธิ์ของตนเอง (None/View/Edit/Full) โดยรวมระดับสูงสุดจากทุก role
  - แสดง role ที่ถูกมอบหมาย พร้อม branch scope (HQ หรือสาขาใด)
  - ปุ่ม "ขอสิทธิ์เพิ่มเติม" และ "ติดต่อผู้ดูแลระบบ"

#### 3.3 `PermissionDeniedWidget`
- **File:** `lib/features/erp/presentation/widgets/permission_denied_widget.dart`
- **Type:** Reusable Widget (ไม่ใช่ Page) เพื่อนำไปใช้ซ้ำในหลาย module
- **Implemented in:** `ProcurementPage` (และสามารถใช้ใน module อื่นได้)
- **Features:**
  - แสดง module ที่ถูกปฏิเสธ
  - ปุ่ม "ขอสิทธิ์" → แสดง SnackBar แจ้งให้ติดต่อ admin
  - ปุ่ม "ติดต่อผู้ดูแลระบบ"
  - ปุ่ม "ย้อนกลับ"
- **Usage:** ใช้ภายใน `Scaffold` ของแต่ละ module page โดยรับ `moduleName`, `moduleLabel`, `onRequestPermission`

### 4. การแก้ไขระดับฐานข้อมูล (Supabase Migrations)

#### 4.1 Migrations ใหม่
- `20260701150000_user_role_management_ui_rpc.sql` — RPC `get_users_with_roles` + table `permission_requests`
- `20260702090000_add_is_active_to_organization_roles.sql` — เพิ่ม `is_active` ให้ `organization_roles` + trigger อัปเดต `updated_at`

#### 4.2 ตารางที่ใช้ (มีอยู่แล้ว + ปรับปรุง)
- `employee_roles` (ตาม migration `20260611140000_erp_phase_0_reliability_rbac_feature_flags.sql`)
  - คอลัมน์: `id`, `profession_id`, `branch_id` (NULL = HQ), `user_id`, `role_id`, `assigned_at`, `assigned_by`, `is_active`
  - UNIQUE: `(profession_id, user_id, role_id, branch_id)`
- `role_module_permissions` (ตาม Phase 0)
- `organization_roles` (ตาม Phase 0)
  - คอลัมน์: `id`, `profession_id`, `role_name`, `role_description`, `is_system_role`, `is_active` (เพิ่ม Phase 7), `created_at`, `updated_at`
  - System roles (`is_system_role = true`) ไม่ลบได้ แต่สามารถระงับ (`is_active = false`) ได้
- `EmployeeRole` model มีอยู่แล้วใน `employee_role.dart`

#### 4.3 RPC ใหม่
เพิ่ม RPC 1 ตัว (ดึงรายการ user ทั้งหมดใน profession พร้อม role):

```sql
-- ดึง user ทั้งหมดใน profession พร้อม role
-- รวม user ที่ยังไม่มี role เพื่อให้ admin มอบ role ได้
-- ใช้ user_id ไม่ใช่ employee_id, ไม่มี is_hq — branch_id = NULL หมายถึง HQ
-- users table มี first_name, last_name, username, email, phone
CREATE OR REPLACE FUNCTION public.get_users_with_roles(
    p_profession_id UUID
) RETURNS JSONB AS $$
    SELECT jsonb_agg(jsonb_build_object(
        'user_id', u.id,
        'full_name', COALESCE(
            NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''),
            u.username,
            u.email,
            u.phone
        ),
        'username', u.username,
        'email', u.email,
        'phone', u.phone,
        'roles', COALESCE(
            (SELECT jsonb_agg(jsonb_build_object(
                'employee_role_id', er.id,
                'role_id', er.role_id,
                'role_name', r.role_name,
                'branch_id', er.branch_id,
                'is_active', er.is_active,
                'assigned_at', er.assigned_at,
                'assigned_by', er.assigned_by
            ))
            FROM public.employee_roles er
            JOIN public.organization_roles r ON r.id = er.role_id
            WHERE er.user_id = u.id AND er.profession_id = p_profession_id),
            '[]'::jsonb
        )
    ))
    FROM public.users u
    WHERE u.profession_id = p_profession_id
$$ LANGUAGE sql STABLE SECURITY DEFINER;
```

> **หมายเหตุ:** ถ้าต้องการแสดง user ทั้งหมดใน profession (รวมที่ยังไม่มี employee record) อาจต้อง JOIN กับ `employees` หรือ `profession_members` แทน `users` โดยตรง ขึ้นอยู่กับ schema ที่มีอยู่

> **ไม่ต้องสร้าง RPC `assign_role_to_employee` หรือ `remove_role_from_employee`** เพราะ `phase_zero_repository.dart` มี `assignEmployeeRole()` และ `toggleEmployeeRole()` อยู่แล้ว ใช้ direct Supabase queries เหมือนที่มีอยู่

### 4.1 ตารางเพิ่มเติม (Optional): `permission_requests`
หากต้องการบันทึกคำขอสิทธิ์จาก user ผ่าน `PermissionDeniedWidget` หรือ `MyPermissionsPage`:

```sql
CREATE TABLE IF NOT EXISTS public.permission_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    module_name     TEXT NOT NULL,
    requested_level INTEGER NOT NULL CHECK (requested_level BETWEEN 1 AND 3),
    reason          TEXT,
    status          TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','approved','rejected')),
    reviewed_by     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    reviewed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_permission_requests_status
    ON public.permission_requests(profession_id, status);
```

> หากยังไม่ต้องการบันทึกคำขอสิทธิ์ลง DB ในตอนแรก ให้ใช้ปุ่ม "ติดต่อผู้ดูแลระบบ" แทนก่อน และ implement `permission_requests` ใน Phase ถัดไป

### 5. การแก้ไขระดับแอปพลิเคชัน (Flutter)

#### 5.1 Repository (`phase_zero_repository.dart`)
**มีอยู่แล้ว (ไม่ต้องเพิ่ม):**
- `assignEmployeeRole({professionId, userId, roleId, branchId, assignedBy})` — มอบ role ให้ user
- `toggleEmployeeRole(employeeRoleId, isActive)` — เปิด/ปิด role assignment

**เพิ่ม methods ใหม่:**
```dart
/// ดึงรายการ user ทั้งหมดใน profession พร้อม role (เรียก RPC get_users_with_roles)
Future<List<Map<String, dynamic>>> getUsersWithRoles(String professionId);

/// ถอน role จาก user (delete row จาก employee_roles)
Future<bool> removeEmployeeRole(String employeeRoleId);

/// เปลี่ยนสถานะ active/inactive ของ organization role
Future<bool> toggleOrganizationRoleActive(String roleId, bool isActive);
```

#### 5.2 Provider (`phase_zero_provider.dart`)
**State มีอยู่แล้ว:** `employeeRoles` (List<EmployeeRole>), `isSaving`, `errorMessage`

**เพิ่ม state:**
```dart
List<Map<String, dynamic>> usersWithRoles;  // รายการ user พร้อม role สำหรับหน้า Assignment
```

**เพิ่ม methods:**
```dart
Future<void> loadUsersWithRoles(String professionId); // เรียก get_users_with_roles RPC
Future<bool> assignRoleToUser({required String professionId, required String userId, required String roleId, String? branchId, String? assignedBy});  // wraps existing assignEmployeeRole()
Future<bool> revokeRoleFromUser(String employeeRoleId);  // delete row + reload
Future<bool> toggleOrganizationRoleActive(String roleId, bool isActive, {required String professionId}); // เปิด/ระงับ role
```

> **หมายเหตุ:** สำหรับ `MyPermissionsPage` ใช้ `loadCurrentUserRoles()` ที่มีอยู่แล้ว (เรียก `get_user_roles_and_permissions`) ไม่ต้องเพิ่ม method ใหม่

#### 5.3 Dashboard Integration
- ไฟล์ `lib/features/erp/data/models/dashboard_module_layout.dart`
  - การ์ด `role_management` เปลี่ยน `routeName` จาก `/erp/roles` → `/erp/settings/employee-roles`
  - `_ModuleTile` ส่ง `professionId` ผ่าน `arguments` โดยอัตโนมัติ
- `EmployeeRoleAssignmentPage` มีปุ่ม "จัดการตำแหน่ง" ใน AppBar ไปยัง `/erp/roles` เพื่อสร้าง role ใหม่

#### 5.4 Sync กับ `user_categories` (Optional / Future)
เมื่อ user เปลี่ยน category (เช่น จาก consumer เป็น provider) ควร sync กับ `employee_roles` โดยอัตโนมัติ:
- **Trigger:** `trigger_sync_role_from_category` ที่มีอยู่แล้ว (ตาม Phase 2 Role Management Refactor)
- **หรือ RPC:** สร้าง `sync_user_category_to_employee_role(p_user_id, p_profession_id)` ที่มอบ role `provider` หรือ `member` พื้นฐานเมื่อ user category เปลี่ยน
- **Flutter:** เรียก sync หลังจาก user สมัคร/อนุมัติเป็น provider ใน `registration_repository.dart` หรือ `profile_page.dart`

#### 5.5 Routes (`main.dart`)
```dart
'/erp/settings/employee-roles': EmployeeRoleAssignmentPage(professionId: professionId)
'/erp/settings/my-permissions': MyPermissionsPage(professionId: professionId)
'/erp/roles': RoleManagementPage(professionId: professionId)
```
ทั้งหมดอยู่ใน `ErpDashboardShell`

#### 5.6 ปรับ `ProcurementPage`
เปลี่ยน permission denied widget (จาก `Text` เป็น `PermissionDeniedWidget`):
```dart
if (accessLevel == 0) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('จัดซื้อจัดจ้าง / Procurement'),
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    body: PermissionDeniedWidget(
      moduleName: 'procurement',
      moduleLabel: 'จัดซื้อจัดจ้าง',
      onRequestPermission: () => _showPermissionRequestDialog(),
    ),
  );
}
```

### 6. แผนพัฒนา (Phased Implementation) ✅ ทั้งหมดเสร็จสิ้น
| Phase | งาน | ระยะเวลา | สถานะ |
|-------|-----|----------|--------|
| **Phase 1** | RPC `get_users_with_roles` + table `permission_requests` | 0.5 วัน | ✅ Completed |
| **Phase 2** | Repository + Provider methods (`getUsersWithRoles`, `removeEmployeeRole`, `assignRoleToUser`, `revokeRoleFromUser`) | 0.5 วัน | ✅ Completed |
| **Phase 3** | `EmployeeRoleAssignmentPage` UI | 2 วัน | ✅ Completed |
| **Phase 4** | `MyPermissionsPage` + `PermissionDeniedWidget` | 2 วัน | ✅ Completed |
| **Phase 5** | Routes + ผูกกับ `ProcurementPage` และ Dashboard | 0.5 วัน | ✅ Completed |
| **Phase 6** | Test + แก้ bug (RPC, migration, UI) | 1 วัน | ✅ Completed |
| **Phase 7** | เพิ่ม `is_active` ให้ `organization_roles` + UI toggle เปิด/ระงับ role | 0.5 วัน | ✅ Completed |

### 7. แผนทดสอบ (Verification Plan)
1. สร้าง role ที่มีสิทธิ์ `procurement` ระดับ 3
2. มอบ role ให้ user ที่ถูก block (ผ่าน `EmployeeRoleAssignmentPage`)
3. เข้าหน้า Procurement อีกครั้ง ต้องเข้าได้
4. ถอน role (revoke) ต้องถูก block อีกครั้ง
5. ทดสอบ `MyPermissionsPage` แสดงสิทธิ์ถูกต้อง (ใช้ `get_user_roles_and_permissions`)
6. ทดสอบ `PermissionDeniedWidget` แสดงปุ่มขอสิทธิ์และติดต่อ admin
7. ทดสอบ **branch-specific role**: มอบ role ที่มีสิทธิ์ `procurement` ระดับ 3 แต่ scope เฉพาะสาขา A → user เข้า Procurement ได้เฉพาะสาขา A ไม่เข้าได้ในสาขา B
8. ทดสอบ **HQ role**: มอบ role โดย `branch_id = NULL` → user เข้า Procurement ได้ในทุกสาขา
9. ทดสอบ **ระงับ role**: ระงับ role ใน `RoleManagementPage` → role ไม่แสดงใน dropdown มอบ role และ user ที่มี role นี้ถูก block จาก module ที่เกี่ยวข้อง
10. ทดสอบ **เปิดใช้ role อีกครั้ง**: เปิด `is_active` กลับมา → role กลับมาใช้งานได้

### 8. ความเสี่ยงและข้อควรระวัง
- **Lock-out risk:** ต้องมี default role `owner` ที่มีสิทธิ์ทุก module อัตโนมัติ
- **Role confusion:** ควรแสดง role name ชัดเจน ไม่ให้ admin สับสน
- **Branch scope:** `branch_id = NULL` หมายถึง HQ (ดูแลทุกสาขา) ไม่มีคอลัมน์ `is_hq` แยกต่างหาก
- **Auth guidelines:** ห้ามเรียก `auth.currentUser` โดยตรง ใช้ `AuthService.instance.currentUser` เสมอ (ตามที่ `phase_zero_provider.dart` ทำอยู่แล้ว)
- **Sync with user_categories:** สิทธิ์ module (`role_module_permissions`) แยกจาก user categories (`is_provider`, `is_admin`) แต่ควร sync ให้ user ที่เป็น provider ได้รับ role พื้นฐานอัตโนมัติ
- **Existing code reuse:** ใช้ `EmployeeRole` model, `assignEmployeeRole()`, `toggleEmployeeRole()` ที่มีอยู่แล้ว ไม่ต้องสร้างใหม่
- **RPC ใหม่เพียง 1 ตัว:** `get_users_with_roles` สำหรับโหลดรายการ user ทั้งหมดพร้อม role ในหน้า Assignment

