# KPI Dashboard Plan — Sheserved ERP

## ภาพรวม (Overview)

**KPI Dashboard** คือศูนย์กลาง Executive View สำหรับ Owner/Manager ติดตามยอดขาย กำไร และประสิทธิภาพพนักงาน (Actual vs Target)

### มาตรฐานสถาปัตยกรรม
- แยกข้อมูลตาม `profession_id` + `branch_id`
- ไม่ใช้ PostgreSQL RLS `auth.uid()` — ควบคุมที่ Application Layer (Repository + ServiceLocator)
- Read Model Pattern: `kpi_actuals` แยกจาก Source of Truth
- Outbox Pattern สำหรับ Alert/Notification

### ขอบเขต Phase 1 (Revenue Metric) ✓
- รองรับ metric: **Revenue** (ยอดขายรวม)
- Target: `kpi_targets` | Actual: `orders` → `kpi_actuals`
- Period: `daily`, `weekly`, `monthly`, `quarterly`, `yearly`
- Alert: warning/critical ตาม % เป้า

### ขอบเขต Phase 2 (Net Profit + Individual Employee Quota) ✓
- **Net Profit** — Actual จาก `journal_entries` + `chart_of_accounts` (account_type 4/5)
- **Individual Employee Revenue** — Actual จาก `orders.served_by` → `employees.user_id`
- `employees` table สร้างเป็น foundational layer
- `refresh_kpi_actuals()` รองรับ `p_target_type = 'net_profit'`
- `refresh_kpi_employee_actuals()` สำหรับ quota รายบุคคล

### ขอบเขต Phase 3 (Additional Metrics) ✓
- **Consultations** — Actual จาก `consultation_requests` (COUNT ที่ status = 'completed'/'assigned')
- **Appointments** — Actual จาก `clinic_appointments` (COUNT ที่ status = 'completed')
- **Gross Profit** — รอ `order_items.cost_price` หรือ `products` table (placeholder function สร้างแล้ว)
- **Inventory Turnover** — รอ `inventory_items` + `inventory_movements` tables (placeholder function สร้างแล้ว)

---

## ฟีเจอร์หลัก (Core Features)

1. **Revenue Target** — ตั้งเป้าหมายยอดขายตามช่วงเวลา (องค์กร/สาขา/พนักงาน)
2. **Actual vs Target** — Gauge/Bar/Trend chart แสดง `achievement_rate = actual/target*100`
3. **Alert & Notification** — แจ้งเตือนผ่าน `outbox_events` เมื่อต่ำกว่า threshold
4. **Multi-Branch & Multi-Period** — Filter สาขา สลับ period real-time
5. **Read Model Refresh** — `kpi_actuals` pre-aggregated รีเฟรชตาม schedule หรือ on-demand
6. **Net Profit Target** (Phase 2) — Actual จากบัญชีแยกประเภท (GL) คำนวณจาก รายได้ - ค่าใช้จ่าย
7. **Individual Employee Quota** (Phase 2) — เป้าหมาย + Actual รายพนักงาน จาก `orders.served_by`
8. **Consultation Count** (Phase 3) — นับจำนวนการปรึกษาที่สำเร็จจาก `consultation_requests`
9. **Appointment Count** (Phase 3) — นับจำนวนนัดหมายที่สำเร็จจาก `clinic_appointments` (status = 'completed')
10. **Gross Profit** (Phase 3 — Planned) — กำไรขั้นต้น (Revenue - COGS) รอ cost tracking
11. **Inventory Turnover** (Phase 3 — Planned) — อัตราการหมุนเวียนสินค้า รอ inventory system

---

## สถาปัตยกรรม (Architecture)

### Multi-Tenant / Multi-Branch
- ทุกตารางมี `profession_id` NOT NULL
- `branch_id` NULL = เป้าหมายรวมทุกสาขา
- Permission ที่ App Layer (owner → ทุกสาขา, manager → สาขาตน, staff → ตัวเอง)

### Read Model Pattern
- **Source of Truth:** `orders`, `journal_entries`, `appointments`
- **Read Model:** `kpi_actuals` (pre-aggregated)
- **Refresh:** `refresh_kpi_actuals()` function + cron
- **Why:** Dashboard query บ่อย ไม่ควร scan raw tables ทุกครั้ง

### Outbox Pattern
- ทุก target change / alert ส่ง event เข้า `outbox_events`
- Notification Worker อ่าน event → in-app / email

---

## Database Schema

> **คำเตือน:** ไม่มี RLS `auth.uid()` — ควบคุมที่ Application Layer ตาม auth_data_guidelines.md

### 1. kpi_targets (เป้าหมาย)

```sql
CREATE TABLE kpi_targets (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id     UUID REFERENCES organization_branches(id) ON DELETE CASCADE,
  employee_id   UUID REFERENCES employees(id) ON DELETE CASCADE,
  target_type   TEXT NOT NULL
    CHECK (target_type IN ('revenue','net_profit','gross_profit','appointments','consultations','inventory_turnover')),
  target_amount DECIMAL(15,2) NOT NULL CHECK (target_amount >= 0),
  period_type   TEXT NOT NULL
    CHECK (period_type IN ('daily','weekly','monthly','quarterly','yearly')),
  start_date    DATE NOT NULL,
  end_date      DATE NOT NULL,
  created_by    UUID, updated_by UUID,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT check_date_range CHECK (end_date >= start_date),
  CONSTRAINT check_scope CHECK (
    (branch_id IS NULL AND employee_id IS NULL) OR
    (branch_id IS NOT NULL AND employee_id IS NULL) OR
    (employee_id IS NOT NULL)
  )
);
```

### 2. kpi_actuals (Read Model)

```sql
CREATE TABLE kpi_actuals (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id    UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id        UUID REFERENCES organization_branches(id) ON DELETE CASCADE,
  employee_id      UUID REFERENCES employees(id) ON DELETE CASCADE,
  target_type      TEXT NOT NULL
    CHECK (target_type IN ('revenue','net_profit','gross_profit','appointments','consultations','inventory_turnover')),
  period_type      TEXT NOT NULL
    CHECK (period_type IN ('daily','weekly','monthly','quarterly','yearly')),
  period_start     DATE NOT NULL,
  period_end       DATE NOT NULL,
  actual_amount    DECIMAL(15,2) NOT NULL DEFAULT 0,
  target_amount    DECIMAL(15,2) NOT NULL DEFAULT 0,
  achievement_rate DECIMAL(5,2) GENERATED ALWAYS AS (
    CASE WHEN target_amount > 0 THEN (actual_amount/target_amount*100) ELSE 0 END
  ) STORED,
  data_source      TEXT NOT NULL DEFAULT 'orders'
    CHECK (data_source IN ('orders','journal_entries','appointments','consultations','manual')),
  refresh_count    INTEGER NOT NULL DEFAULT 1,
  last_refresh_at  TIMESTAMPTZ DEFAULT now(),
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id, employee_id, target_type, period_type, period_start)
);
```

### 3. kpi_alert_thresholds

```sql
CREATE TABLE kpi_alert_thresholds (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id          UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  target_type            TEXT NOT NULL
    CHECK (target_type IN ('revenue','net_profit','gross_profit','appointments','consultations','inventory_turnover')),
  warning_threshold_pct  DECIMAL(5,2) NOT NULL DEFAULT 80.00,
  critical_threshold_pct DECIMAL(5,2) NOT NULL DEFAULT 60.00,
  alert_enabled          BOOLEAN NOT NULL DEFAULT true,
  notify_roles           TEXT[] NOT NULL DEFAULT ARRAY['owner','manager'],
  created_by UUID, updated_by UUID,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, target_type)
);
```

### 4. kpi_refresh_log

```sql
CREATE TABLE kpi_refresh_log (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id    UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  refresh_type     TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (refresh_type IN ('scheduled','manual','triggered')),
  target_type      TEXT,
  period_type      TEXT,
  records_processed INTEGER NOT NULL DEFAULT 0,
  records_inserted  INTEGER NOT NULL DEFAULT 0,
  records_updated   INTEGER NOT NULL DEFAULT 0,
  started_at       TIMESTAMPTZ NOT NULL,
  completed_at     TIMESTAMPTZ,
  error_message    TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);
```

### 5. employees (Prerequisite for Phase 2 Individual Quota)

```sql
CREATE TABLE employees (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  branch_id     UUID REFERENCES organization_branches(id) ON DELETE SET NULL,
  employee_code TEXT,
  full_name     TEXT NOT NULL,
  position      TEXT,
  department    TEXT,
  phone         TEXT,
  email         TEXT,
  is_active     BOOLEAN DEFAULT true,
  hired_at      DATE,
  created_by UUID, updated_by UUID,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, user_id)
);

CREATE INDEX idx_employees_profession ON employees(profession_id, is_active) WHERE is_active = true;
CREATE INDEX idx_employees_user ON employees(user_id);
CREATE INDEX idx_employees_branch ON employees(branch_id);
```

### 6. Refresh Function (Revenue — Phase 1 / Net Profit — Phase 2)

```sql
CREATE OR REPLACE FUNCTION refresh_kpi_actuals(
  p_profession_id UUID,
  p_period_type TEXT DEFAULT 'daily',
  p_lookback_days INTEGER DEFAULT 30
)
RETURNS TABLE (inserted INTEGER, updated INTEGER) AS $$
DECLARE
  v_inserted INTEGER := 0; v_updated INTEGER := 0;
  v_now TIMESTAMPTZ := now(); v_start_date DATE;
BEGIN
  v_start_date := CURRENT_DATE - p_lookback_days;
  WITH computed AS (
    SELECT o.profession_id, o.branch_id, NULL::UUID AS employee_id,
      'revenue'::TEXT AS target_type, p_period_type AS period_type,
      CASE p_period_type
        WHEN 'daily' THEN o.created_at::DATE
        WHEN 'weekly' THEN DATE_TRUNC('week', o.created_at)::DATE
        WHEN 'monthly' THEN DATE_TRUNC('month', o.created_at)::DATE
        WHEN 'quarterly' THEN DATE_TRUNC('quarter', o.created_at)::DATE
        WHEN 'yearly' THEN DATE_TRUNC('year', o.created_at)::DATE
      END AS period_start,
      CASE p_period_type
        WHEN 'daily' THEN o.created_at::DATE
        WHEN 'weekly' THEN (DATE_TRUNC('week', o.created_at) + INTERVAL '6 days')::DATE
        WHEN 'monthly' THEN (DATE_TRUNC('month', o.created_at) + INTERVAL '1 month - 1 day')::DATE
        WHEN 'quarterly' THEN (DATE_TRUNC('quarter', o.created_at) + INTERVAL '3 months - 1 day')::DATE
        WHEN 'yearly' THEN (DATE_TRUNC('year', o.created_at) + INTERVAL '1 year - 1 day')::DATE
      END AS period_end,
      COALESCE(SUM(o.final_amount), 0) AS actual_amount
    FROM orders o
    WHERE o.profession_id = p_profession_id
      AND o.status IN ('paid', 'completed')
      AND o.created_at >= v_start_date
    GROUP BY o.profession_id, o.branch_id, period_start, period_end
  ), upserted AS (
    INSERT INTO kpi_actuals (profession_id, branch_id, employee_id, target_type, period_type,
      period_start, period_end, actual_amount, target_amount, data_source, refresh_count, last_refresh_at)
    SELECT c.profession_id, c.branch_id, c.employee_id, c.target_type, c.period_type,
      c.period_start, c.period_end, c.actual_amount, COALESCE(kt.target_amount, 0),
      'orders', 1, v_now
    FROM computed c
    LEFT JOIN kpi_targets kt ON kt.profession_id = c.profession_id
      AND kt.branch_id IS NOT DISTINCT FROM c.branch_id
      AND kt.employee_id IS NOT DISTINCT FROM c.employee_id
      AND kt.target_type = c.target_type AND kt.period_type = c.period_type
      AND kt.start_date <= c.period_end AND kt.end_date >= c.period_start
    ON CONFLICT (profession_id, branch_id, employee_id, target_type, period_type, period_start)
    DO UPDATE SET actual_amount = EXCLUDED.actual_amount, target_amount = EXCLUDED.target_amount,
      data_source = 'orders', refresh_count = kpi_actuals.refresh_count + 1,
      last_refresh_at = v_now, updated_at = v_now
    RETURNING (xmax = 0) AS is_insert
  )
  SELECT COUNT(*) FILTER (WHERE is_insert) INTO v_inserted,
         COUNT(*) FILTER (WHERE NOT is_insert) INTO v_updated FROM upserted;
  RETURN QUERY SELECT v_inserted, v_updated;
END;
$$ LANGUAGE plpgsql;
```

### 6. Indexes

```sql
CREATE INDEX idx_kpi_actuals_lookup ON kpi_actuals(profession_id, branch_id, target_type, period_type, period_start)
  WHERE last_refresh_at > now() - interval '90 days';
CREATE INDEX idx_kpi_actuals_achievement ON kpi_actuals(profession_id, achievement_rate, target_type)
  WHERE target_amount > 0;
CREATE INDEX idx_kpi_targets_lookup ON kpi_targets(profession_id, branch_id, target_type, period_type, start_date, end_date);
CREATE INDEX idx_kpi_refresh_log_recent ON kpi_refresh_log(profession_id, refresh_type, started_at DESC)
  WHERE started_at > now() - interval '7 days';
CREATE INDEX idx_kpi_alert_thresholds ON kpi_alert_thresholds(profession_id, target_type);
CREATE INDEX idx_kpi_targets_branch ON kpi_targets(branch_id);
CREATE INDEX idx_kpi_targets_employee ON kpi_targets(employee_id);
CREATE INDEX idx_kpi_actuals_branch ON kpi_actuals(branch_id);
CREATE INDEX idx_kpi_actuals_employee ON kpi_actuals(employee_id);
```

### 7. Triggers

```sql
CREATE TRIGGER trg_kpi_targets_updated_at BEFORE UPDATE ON kpi_targets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_kpi_actuals_updated_at BEFORE UPDATE ON kpi_actuals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_kpi_alert_thresholds_updated_at BEFORE UPDATE ON kpi_alert_thresholds
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

---

## ER Diagram

```
professions                    orders (POS)
  | profession_id                | profession_id, branch_id
  ▼                              | final_amount, status ('paid')
┌─────────────┐                  | created_at, served_by
| kpi_targets |                  ▼
| - branch_id |◄───────────────── kpi_actuals (Read Model)
| - employee_id|                   | actual_amount, achievement_rate
| - target_amount|                 | last_refresh_at
└──────┬──────┘                  ▼
       |                      kpi_refresh_log
       |                      | records_processed, started_at
       ▼
┌──────────────────┐
|kpi_alert_thresholds|
| warning_threshold_pct |
| critical_threshold_pct|
└──────────────────┘

organization_branches
  | branch_id
  ▼
employees
  | employee_id, user_id
  |                |
  |                | orders.served_by = users.id
  |                ▼
  |             orders (POS)
  |             | final_amount, status ('paid')
  |             | served_by (users.id)
  |             | created_at
  |                |
  └───────────────▶ kpi_actuals (employee revenue)

chart_of_accounts (Accounting)
  | account_type = 4 (Revenue) / 5 (Expenses)
  ▼
journal_entry_lines
  | journal_entry_id, account_id
  | debit_amount, credit_amount
  ▼
journal_entries
  | status = 'posted'
  | entry_date
  ▼
  kpi_actuals (net_profit)
  | data_source = 'journal_entries'
```

---

## Business Logic

### 1. Actual Calculation (Revenue)
```
actual_amount = SUM(orders.final_amount)
  WHERE status IN ('paid','completed')
    AND profession_id = ? AND branch_id IS NOT DISTINCT FROM ?
    AND created_at BETWEEN period_start AND period_end

achievement_rate = (actual_amount / target_amount) * 100
```

### 2. Refresh Schedule
```
Cron Job (every 1 hour for daily, every 6 hours for weekly+)
  → refresh_kpi_actuals(profession_id, period_type, lookback)
  → INSERT/UPDATE kpi_actuals
  → INSERT kpi_refresh_log
  → IF achievement < critical: INSERT outbox (critical_alert)
  → ELSE IF achievement < warning: INSERT outbox (warning_alert)
```

### 3. Alert Workflow
```
Trigger: achievement_rate < threshold_pct
Action:
  1. INSERT outbox_events (aggregate_type='kpi', event_type='kpi.actual.{warning|citical}_alert')
  2. Notification Worker reads outbox → creates platform_notifications
  3. Dashboard shows alert badge
```

### 4. Actual Calculation (Net Profit — Phase 2)
```
actual_amount = SUM(credit_amount WHERE account_type = 4)
                - SUM(debit_amount WHERE account_type = 5)
  FROM journal_entries je
  JOIN journal_entry_lines jel ON jel.journal_entry_id = je.id
  JOIN chart_of_accounts coa ON coa.id = jel.account_id
  WHERE je.status = 'posted'
    AND coa.account_type IN (4, 5)
    AND je.profession_id = ? AND je.branch_id IS NOT DISTINCT FROM ?
    AND je.entry_date BETWEEN period_start AND period_end

achievement_rate = (actual_amount / target_amount) * 100
```

### 5. Actual Calculation (Individual Employee Revenue — Phase 2)
```
actual_amount = SUM(orders.final_amount)
  FROM orders o
  JOIN employees e ON e.user_id = o.served_by AND e.profession_id = o.profession_id
  WHERE o.status IN ('paid','completed')
    AND o.served_by IS NOT NULL
    AND o.profession_id = ? AND o.branch_id IS NOT DISTINCT FROM ?
    AND e.id = target.employee_id
    AND o.created_at BETWEEN period_start AND period_end

achievement_rate = (actual_amount / target_amount) * 100
```

### 6. Actual Calculation (Consultations — Phase 3)
```
actual_amount = COUNT(consultation_requests)
  WHERE status IN ('completed', 'assigned')
    AND created_at BETWEEN period_start AND period_end

achievement_rate = (actual_amount / target_amount) * 100
```

### 7. Refresh Schedule (Phase 2 + 3)
```
Cron Job (hourly for daily, every 6h for weekly+)
  → refresh_kpi_actuals(profession_id, period_type, lookback, 'revenue')
  → refresh_kpi_actuals(profession_id, period_type, lookback, 'net_profit')
  → refresh_kpi_actuals(profession_id, period_type, lookback, 'consultations')
  → refresh_kpi_appointments(profession_id, period_type, lookback)
  → refresh_kpi_employee_actuals(profession_id, period_type, lookback)
  → INSERT/UPDATE kpi_actuals
  → INSERT kpi_refresh_log
  → IF achievement < critical: INSERT outbox (critical_alert)
  → ELSE IF achievement < warning: INSERT outbox (warning_alert)
```

### 8. Permission Logic (App Layer)
```
owner     → all branches + org-level data + all employees
manager   → own branch(es) + employees in branch
staff     → own employee_id only (if module_permission.kpi_dashboard = 'view_own')
no perm   → 403 Forbidden
```

---

## Integrations

| System | Phase | Data Source | Table/Field | Status |
|--------|-------|-------------|-------------|--------|
| POS | 1 | Revenue Actual | `orders.final_amount` | ✓ Complete |
| Accounting | 2 | Net Profit | `journal_entries` + `chart_of_accounts` (account_type 4/5) | ✓ Complete |
| HR | 2 | Individual Quota | `orders.served_by` → `employees.user_id` | ✓ Complete |
| Consultation | 3 | Consultation Count | `consultation_requests` (status = 'completed') | ✓ Complete |
| Appointments | 3 | Appointment Count | `clinic_appointments` (status = 'completed') | ✓ Complete |
| Inventory | 3 | COGS / Turnover | `inventory_items` + `inventory_movements` | ⚠️ Tables not yet created |
| Procurement | 3 | Gross Profit | `order_items` + `products.cost_price` | ⚠️ cost_price not yet tracked |

---

## Outbox Payload Examples

### kpi.target.created
```json
{
  "event_type": "kpi.target.created",
  "aggregate_type": "kpi",
  "aggregate_id": "<target_id>",
  "profession_id": "<profession_id>",
  "payload": {
    "target_id": "<uuid>", "target_type": "revenue",
    "target_amount": 150000.00, "period_type": "monthly",
    "start_date": "2026-06-01", "end_date": "2026-06-30",
    "branch_id": null, "employee_id": null, "created_by": "<user_id>"
  }
}
```

### kpi.actual.warning_alert
```json
{
  "event_type": "kpi.actual.warning_alert",
  "aggregate_type": "kpi",
  "aggregate_id": "<actual_id>",
  "profession_id": "<profession_id>",
  "payload": {
    "target_type": "revenue", "period_type": "daily", "period_start": "2026-06-09",
    "actual_amount": 42000.00, "target_amount": 50000.00,
    "achievement_rate": 84.00, "warning_threshold_pct": 80.00,
    "branch_id": "<branch_id>", "alert_level": "warning"
  }
}
```

### kpi.actual.critical_alert
```json
{
  "event_type": "kpi.actual.critical_alert",
  "aggregate_type": "kpi",
  "aggregate_id": "<actual_id>",
  "profession_id": "<profession_id>",
  "payload": {
    "target_type": "revenue", "period_type": "daily", "period_start": "2026-06-09",
    "actual_amount": 28000.00, "target_amount": 50000.00,
    "achievement_rate": 56.00, "critical_threshold_pct": 60.00,
    "branch_id": "<branch_id>", "alert_level": "critical"
  }
}
```

---

## Flutter UI Architecture

```
lib/features/kpi/
├── data/
│   ├── models/ (KpiTarget, KpiActual, KpiAlertThreshold)
│   ├── repositories/ (KpiRepository)
│   └── services/ (KpiRefreshService)
├── domain/
│   ├── entities/ (KpiTargetEntity, KpiDashboardSummary)
│   └── usecases/ (GetKpiDashboard, CreateKpiTarget, RefreshKpiData)
└── presentation/
    ├── pages/ (KpiDashboardPage, KpiTargetFormPage, KpiRefreshHistoryPage)
    ├── widgets/ (KpiGauge, KpiBarChart, KpiTrendLine, KpiAlertCard, KpiPeriodSelector)
    └── providers/ (KpiProvider)
```

### Routes
```dart
class KpiRoutes {
  static const dashboard = '/kpi/dashboard';
  static const targetForm = '/kpi/target/form';
  static const refreshHistory = '/kpi/refresh/history';
}
```

---

## Implementation Phases

### Phase A: Foundation ✓ (Migrations Complete)
- [x] SQL Migration: `kpi_targets`, `kpi_actuals`, `kpi_alert_thresholds`, `kpi_refresh_log`
  - `20260609220000_create_kpi_schema.sql` — Phase 1 (revenue)
  - `20260609230000_kpi_phase2_net_profit_and_quota.sql` — Phase 2 (net_profit + employee quota)
  - `20260610000000_kpi_phase3_additional_metrics.sql` — Phase 3 (consultations + appointments + placeholders)
- [x] Function: `refresh_kpi_actuals()` — รองรับ `revenue`, `net_profit`, `consultations`
- [x] Function: `refresh_kpi_employee_actuals()` — quota รายบุคคล
- [x] Function: `refresh_kpi_appointments()` — appointments count
- [x] **Cron Job**: `pg_cron` สำหรับ scheduled refresh (`20260610020000_kpi_cron_jobs.sql`)
- [x] **Seed revenue thresholds**: เปิดใช้งานแล้วใน Phase 1 migration (warning=80%, critical=60%)
- [x] RPC endpoint: ใช้ `refresh_kpi_actuals()` ผ่าน Supabase RPC ได้ทันที

> **หมายเหตุ:** Foundation layer เสร็จสมบูรณ์ 100% — ทุก migration, function, cron job, และ seed พร้อมใช้งาน

### Phase B: UI Core ✓ (Implementation Complete)
- [x] `KpiDashboardPage` (`lib/features/kpi/presentation/pages/kpi_dashboard_page.dart`)
- [x] `KpiTargetFormPage` (`lib/features/kpi/presentation/pages/kpi_target_form_page.dart`)
- [x] Chart Widgets ด้วย `fl_chart`:
  - `KpiGauge` — Gauge chart แสดง achievement rate
  - `KpiBarChart` — Bar chart เปรียบเทียบ actual vs target
  - `KpiTrendLine` — Line chart แสดง trend  overtime
- [x] `KpiAlertCard` — Card แจ้งเตือนตามสถานะ
- [x] `KpiPeriodSelector` — Filter chip สำหรับ target type + period
- [x] `KpiProvider` (`StateNotifier`) + `KpiRepository`
- [x] Wire routes ใน `main.dart` (`/kpi/dashboard`, `/kpi/target/form`)

> **หมายเหตุ:** UI Core เสร็จแล้ว 100% — แต่ยังไม่มี tab/integration ใน `ErpDashboardPage` หรือ `MainAppLayout`

### Phase 2: Net Profit + Individual Employee Quota ✓
- [x] SQL Migration: `employees` table (foundational for individual quota)
- [x] Extend `refresh_kpi_actuals()` รองรับ `p_target_type = 'net_profit'`
- [x] Create `refresh_kpi_employee_actuals()` สำหรับ quota รายบุคคล
- [x] Net Profit Alert Threshold seed

### Phase 3: Additional Metrics ✓
- [x] Extend `refresh_kpi_actuals()` รองรับ `p_target_type = 'consultations'`
- [x] สร้าง `refresh_kpi_appointments()` จาก `clinic_appointments`
- [x] Consultation + Appointments alert threshold seed
- [x] Placeholder functions สำหรับ `gross_profit`, `inventory_turnover`
- [x] Update KPI plan with Phase 3 scope, business logic, integration status

### Phase C: Alert & Polish (UI) ✓ (Practical Minimum Complete)
- [x] `KpiAlertBanner` — In-app alert banner ดึงจาก `kpi_actuals` โดยตรง (no-cost, no push)
  - แสดง critical/warning ตาม `kpi_alert_thresholds`
  - ไม่ใช้ Firebase / push notification (ฟรี 100%)
- [x] `KpiRefreshHistoryPage` — แสดง log จาก `kpi_refresh_log` 50 รายการล่าสุด
- [x] Manual Refresh button + UX (loading indicator + snackbar) — อยู่ใน `KpiDashboardPage`
- [x] Supabase Realtime subscription บน `kpi_actuals` (ฟรี, auto-reload เมื่อ data change)
- [ ] Notification integration (outbox → in-app) — Level 3 (outbox pattern) รอทำในอนาคต
- [ ] Performance test 10,000+ orders — รอ mock data / benchmark environment

> **หมายเหตุ:** Phase C Practical Minimum เสร็จแล้ว — ทุกอย่างใช้ Supabase ฟรี (Realtime, RPC, DB) ไม่มีค่าใช้จ่ายเพิ่ม

---

## ข้อจำกัดเฉพาะ Phase 3 (Prerequisites Blocked)

สอง metric นี้ **ถูก block โดย prerequisite จากโมดูลอื่น** ต้องรอแผน/สคีมาอื่นสำเร็จก่อน:

### Gross Profit — BLOCKED (รอ Procurement + Products)
```
สูตร: gross_profit = SUM(orders.final_amount) - COGS
       COGS = SUM(order_items.quantity × products.cost_price)
```
- ❌ `products` table ไม่มี `cost_price` column
- ❌ ไม่มี Procurement/Purchasing module (ต้องรู้ต้นทุนตอนซื้อเข้า)
- ❌ `order_items` มีแค่ `unit_price` (ราคาขาย) ไม่มีต้นทุน
- **Action ต้องทำก่อน:** สร้าง `PROCUREMENT_SYSTEM_PLAN.md` + `products` table ที่มี `cost_price`

### Inventory Turnover — BLOCKED (รอ Inventory System)
```
สูตร: turnover = COGS / ((beginning_inventory + ending_inventory) / 2)
```
- ❌ `inventory_items` table ไม่มี
- ❌ `inventory_movements` table ไม่มี
- ❌ COGS calculation ขึ้นอยู่กับ Gross Profit ที่ยังทำไม่ได้
- **Action ต้องทำก่อน:** สร้าง Inventory/Warehouse module (`inventory_items` + `inventory_movements`)

### Dependency Chain
```
[Procurement System] → ซื้อสินค้า → รู้ต้นทุน → products.cost_price
      ↓
[Inventory System] → รับเข้าคลัง → เก็บ stock → inventory_items / inventory_movements
      ↓
[KPI Dashboard] → คำนวณ Gross Profit + Inventory Turnover ได้
```

### ทำไมไม่สร้าง Procurement/Inventory migration ตอนนี้

**แผนมีอยู่แล้ว แต่ migration ยังไม่มี:**
- `docs/ERP/PROCUREMENT_SYSTEM_PLAN.md` — ครบถ้วน (PR, PO, Goods Receipt, Back Order, Approval)
- `docs/ERP/INVENTORY_SYSTEM_PLAN.md` — ครบถ้วน (`inventory_items` มี `cost_price`, `stock_movements`, Lot/Expiry)
- SQL Migration ทั้งสองโมดูล — **ยังไม่มี**

**เหตุผลที่ควรรอ:**
1. **ขนาดงานใหญ่มาก** — Procurement (~10 ตาราง) + Inventory (~4 ตาราง) + Functions/Triggers/Indexes = งานเท่ากับ KPI Phase 1-3 รวมกัน
2. **5 metrics พร้อมใช้แล้ว** (Revenue, Net Profit, Employee Quota, Consultations, Appointments) ครอบคลุม ~80% use case Executive Dashboard
3. **UI เป็น natural next step** — Foundation layer เสร็จแล้ว ควรลงมือทำ Flutter UI (`KpiDashboardPage`, Chart widgets, Provider, Repository) ก่อน
4. **Procurement/Inventory เป็นโมดูลอิสระ** — ไม่ควรสร้างเพื่อ unblock KPI อย่างเดียว ควรสร้างเมื่อธุรกิจมี pharmacist/warehouse staff และต้องซื้อ/รับสินค้าจริงๆ

**ลำดับถัดไปที่แนะนำ:**
1. UI Implementation (`KpiDashboardPage`, `fl_chart` widgets, `KpiProvider`, `KpiRepository`, routes)
2. RPC + Cron Job (`refresh_kpi_actuals()` endpoint + scheduled refresh)
3. Alert Integration (`KpiAlertCard` + outbox → notification)
4. (อนาคต) Procurement/Inventory migration เมื่อธุรกิจต้องการ — ค่อย unblock Gross Profit + Inventory Turnover

---

## Backlog / สิ่งที่ยังไม่ครบ (Future Work)

### Phase 4: Advanced Charts + Real-time
- **Advanced Charts:** Heatmap, drill-down, comparison YoY/MoM
- **Real-time WebSocket push:** Real-time update เมื่อมี order ใหม่
- **Dashboard Widgets:** Home-screen widget สำหรับ Owner/Manager

### Phase 5: Export + Scheduled Reports
- **Export:** PDF/Excel report สำหรับ executive meeting
- **Scheduled Report:** Email report รายสัปดาห์/เดือน

### Phase 6: AI / Prediction
- **Predictive Target:** AI แนะนำ target จาก historical data
- **Anomaly Detection:** ตรวจจับยอดผิดปกติ (หลุดจาก trend)
- **What-if Analysis:** จำลอง scenario เปลี่ยน target/price

### Phase 7: Pending Prerequisites (Metrics waiting for other systems)
- **Gross Profit metric:** รอ `order_items.cost_price` หรือ `products` table with cost tracking
- **Inventory Turnover metric:** รอ `inventory_items` + `inventory_movements` tables

---

## ไฟล์ที่เกี่ยวข้อง (Related Files)

### Plans
- `docs/ERP/ERP_CORE_ARCHITECTURE.md` — สถาปัตยกรรมหลัก
- `docs/ERP/PROCUREMENT_SYSTEM_PLAN.md` — มาตรฐาน schema/business logic
- `docs/ERP/POS System_plan.md` — แหล่งข้อมูล revenue
- `docs/ERP/ACCOUNTING_SYSTEM_PLAN.md` — แหล่งข้อมูล net profit (Phase 2)
- `docs/ERP/HR_SYSTEM_PLAN.md` — แหล่งข้อมูล employee quota (Phase 2)
- `.agent/workflows/auth_data_guidelines.md` — หลักการควบคุมสิทธิ์

### Migrations (Execution Order)
1. `supabase/migrations/20260609180000_create_accounting_core_schema.sql` — Accounting (prerequisite for net profit)
2. `supabase/migrations/20260609215000_create_employees_table.sql` — Employees (prerequisite for individual quota)
3. `supabase/migrations/20260610010000_create_pos_core_schema.sql` — POS Core (orders, order_items, clinic_appointments, etc.)
4. `supabase/migrations/20260609220000_create_kpi_schema.sql` — KPI Phase 1 (revenue + thresholds seed)
5. `supabase/migrations/20260609230000_kpi_phase2_net_profit_and_quota.sql` — KPI Phase 2 (net profit + employee quota)
6. `supabase/migrations/20260610000000_kpi_phase3_additional_metrics.sql` — KPI Phase 3 (consultations + appointments + placeholders)
7. `supabase/migrations/20260610020000_kpi_cron_jobs.sql` — KPI Scheduled Refresh (pg_cron jobs)

> **หมายเหตุ:**
> - `consultation_requests` table อยู่ใน `database/schemas/supabase_consultation_schema.sql` (ยังไม่มีใน supabase/migrations)
> - `inventory_items`, `inventory_movements`, `products` tables ยังไม่มี
