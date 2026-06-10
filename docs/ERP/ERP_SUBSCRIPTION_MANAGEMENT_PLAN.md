# ERP Subscription Management Plan — Sheserved

## ภาพรวม (Overview)

ระบบจัดการ Subscription Tier สำหรับ **Sheserved Platform Admin** (ไม่ใช่ Admin องค์กร) เพื่อกำหนดแพ็กเกจบริการ ราคา และสิทธิ์การใช้งานของแต่ละองค์กรภายนอก (Partner Clinics/Centers)

> **สำคัญ:** หน้าจัดการ Subscription Tier นี้เป็น **หน้าภายใน Sheserved** เท่านั้น — ไม่ใช่หน้าที่องค์กรภายนอกเห็น

---

## ลักษณะการทำงาน

### ผู้ใช้งานหลัก
- **Sheserved Super Admin** — สร้าง/แก้ไข/ลบ Tier, กำหนดราคา, เปิด/ปิด Feature
- **Sheserved Sales/Account Manager** — ดูรายงาน, upgrade/downgrade Tier ให้องค์กร

### สิ่งที่ Sheserved Admin สามารถทำได้
1. **สร้าง Tier ใหม่** — ตั้งชื่อ, ราคา, คำอธิบาย, ระยะเวลาทดลอง
2. **แก้ไข Tier** — ปรับราคา, เพิ่ม/ลด Feature, เปลี่ยน Quota
3. **ลบ Tier** — เฉพาะ Tier ที่ยังไม่มีองค์กรใช้งาน
4. **กำหนด Feature ต่อ Tier** — เปิด/ปิดโมดูล ERP, เปิด/ปิด External Channel
5. **กำหนด Quota ต่อ Tier** — จำกัดจำนวน SMS, Push, Storage, Users
6. **มอบหมาย Tier ให้องค์กร** — Assign tier ให้ `profession_id` ใดๆ
7. **ดูรายงานการใช้งาน** — ยอดขาย, การใช้ Quota, องค์กรที่ใกล้หมดอายุ

---

## ฐานข้อมูล (Database Schema)

```sql
-- ============================================================
-- 1. ตาราง Subscription Tier (Sheserved กำหนด)
-- ============================================================
CREATE TABLE subscription_tiers (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tier_code               TEXT NOT NULL UNIQUE,                    -- 'basic','standard','premium','enterprise'
  display_name_th         TEXT NOT NULL,
  display_name_en         TEXT NOT NULL,
  description_th          TEXT,
  description_en          TEXT,
  
  monthly_fee_baht        DECIMAL(12,2) NOT NULL DEFAULT 0,
  yearly_fee_baht         DECIMAL(12,2),
  setup_fee_baht          DECIMAL(12,2) DEFAULT 0,
  
  trial_days              INTEGER DEFAULT 14,
  billing_cycle           TEXT DEFAULT 'monthly'
    CHECK (billing_cycle IN ('monthly','yearly','quarterly')),
  
  is_active               BOOLEAN DEFAULT true,
  is_public               BOOLEAN DEFAULT true,
  display_order           INTEGER DEFAULT 0,
  
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 2. ตาราง Feature ต่อ Tier
-- ============================================================
CREATE TABLE tier_features (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tier_id                 UUID NOT NULL REFERENCES subscription_tiers(id) ON DELETE CASCADE,
  feature_category        TEXT NOT NULL
    CHECK (feature_category IN ('erp_module','notification_channel','quota','limit','integration')),
  feature_key             TEXT NOT NULL,
  feature_name_th         TEXT NOT NULL,
  feature_name_en         TEXT NOT NULL,
  is_enabled              BOOLEAN DEFAULT true,
  numeric_value           INTEGER,
  text_value              TEXT,
  created_at              TIMESTAMPTZ DEFAULT now(),
  UNIQUE (tier_id, feature_key)
);

-- ============================================================
-- 3. ตารางการสมัครสมาชิกขององค์กร
-- ============================================================
CREATE TABLE organization_subscriptions (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  tier_id                 UUID NOT NULL REFERENCES subscription_tiers(id),
  started_at              TIMESTAMPTZ DEFAULT now(),
  expires_at              TIMESTAMPTZ,
  trial_ends_at           TIMESTAMPTZ,
  status                  TEXT DEFAULT 'trial'
    CHECK (status IN ('trial','active','suspended','cancelled','expired')),
  last_payment_at         TIMESTAMPTZ,
  next_billing_at         TIMESTAMPTZ,
  payment_method          TEXT,
  assigned_by_user_id     UUID REFERENCES users(id),
  notes                   TEXT,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_org_subs_profession ON organization_subscriptions(profession_id);
CREATE INDEX idx_org_subs_status ON organization_subscriptions(status);
CREATE INDEX idx_org_subs_expiry ON organization_subscriptions(expires_at) WHERE status = 'active';

-- ============================================================
-- 4. ตารางประวัติการเปลี่ยนแปลง Tier
-- ============================================================
CREATE TABLE subscription_change_logs (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id),
  old_tier_id             UUID REFERENCES subscription_tiers(id),
  new_tier_id             UUID NOT NULL REFERENCES subscription_tiers(id),
  changed_by_user_id      UUID NOT NULL REFERENCES users(id),
  change_reason           TEXT,
  created_at              TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 5. RLS (เฉพาะ Sheserved Admin)
-- ============================================================
ALTER TABLE subscription_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY subscription_tiers_admin ON subscription_tiers
  USING (EXISTS (
    SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'sheserved_admin'
  ));

CREATE POLICY org_subs_admin ON organization_subscriptions
  USING (EXISTS (
    SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'sheserved_admin'
  ));
```

### Seed Data

```sql
INSERT INTO subscription_tiers (tier_code, display_name_th, display_name_en, monthly_fee_baht, trial_days) VALUES
('basic', 'เบสิก', 'Basic', 0, 30),
('standard', 'สแตนดาร์ด', 'Standard', 299, 14),
('premium', 'พรีเมี่ยม', 'Premium', 599, 14),
('enterprise', 'เอนเทอร์ไพรส์', 'Enterprise', 999, 30);
```

---

## หน้าจอจัดการ Subscription Tier (UI Design)

### 1. Tier List Page (`/admin/subscription/tiers`)

```
┌─────────────────────────────────────────────────────────────┐
|  Sheserved Admin  |  Subscription Tiers              [+]    |
├─────────────────────────────────────────────────────────────┤
|  [Search]  [Filter: All]  [Sort: Price]                    |
├─────────────────────────────────────────────────────────────┤
|  ┌───────────────────────────────────────────────────────┐  |
|  | เบสิก (Basic)          ฟรี   30 วันทดลอง   [แก้ไข]   |  |
|  | โมดูล: CRM, POS | แจ้งเตือน: In-App | องค์กร: 15   |  |
|  └───────────────────────────────────────────────────────┘  |
|  ┌───────────────────────────────────────────────────────┐  |
|  | สแตนดาร์ด (Standard) 299/ด 14 วัน  [🔥 ยอดนิยม] [แก้ไข]|  |
|  | โมดูล: CRM, POS, Inv | แจ้งเตือน: +Push | องค์กร: 42 |  |
|  └───────────────────────────────────────────────────────┘  |
|  ┌───────────────────────────────────────────────────────┐  |
|  | พรีเมี่ยม (Premium)   599/ด | แจ้งเตือน: +SMS | [แก้ไข]|  |
|  └───────────────────────────────────────────────────────┘  |
|  ┌───────────────────────────────────────────────────────┐  |
|  | เอนเทอร์ไพรส์ (Enterprise) 999/ด [🔒 ไม่แสดง] [แก้ไข] |  |
|  └───────────────────────────────────────────────────────┘  |
└─────────────────────────────────────────────────────────────┘
```

### 2. Create/Edit Tier Page (`/admin/subscription/tiers/form`)

```
┌─────────────────────────────────────────────────────────────┐
|  <- กลับ  |  สร้าง/แก้ไข Tier                                  |
├─────────────────────────────────────────────────────────────┤
|  ข้อมูลพื้นฐาน                                              |
|  รหัส: [standard____]  ชื่อ(ไทย): [สแตนดาร์ด____]          |
|  ราคา/เดือน: [ 299 ]  ราคา/ปี: [ 2,990 ]  ทดลอง: [ 14 ] วัน |
|                                                              |
|  ERP Modules                                                 |
|  [✓] CRM  [✓] POS  [✓] Inventory  [ ] HIS  [ ] LIS       |
|                                                              |
|  Notification Channels                                       |
|  [✓] In-App  [✓] Push [quota: 1000]  [ ] SMS  [ ] Line     |
|                                                              |
|  Quota & Limits                                              |
|  ผู้ใช้สูงสุด: [ 10 ]  สาขาสูงสุด: [ 3 ]  Storage: [ 5 ] GB |
|                                                              |
|  [✓] แสดงให้องค์กรเลือกได้  [✓] เปิดใช้งาน                  |
|                                                              |
|            [💾 บันทึก]    [❌ ยกเลิก]                        |
└─────────────────────────────────────────────────────────────┘
```

### 3. Assign Tier Page (`/admin/subscription/assign`)

```
┌─────────────────────────────────────────────────────────────┐
|  มอบหมาย Tier ให้องค์กร                                     |
├─────────────────────────────────────────────────────────────┤
|  องค์กร: [🔍 ค้นหา...]                                       |
|  ปัจจุบัน: เบสิก — หมดอายุ 2026-07-15                       |
|                                                              |
|  Tier ใหม่: [สแตนดาร์ด ▼]                                  |
|  [ ] ทดลองใช้  [✓] ชำระเงินทันที                            |
|  เริ่ม: [2026-06-10]  หมดอายุ: [2026-07-10]                 |
|  หมายเหตุ: [____________]                                   |
|                                                              |
|       [💾 มอบหมาย]    [❌ ยกเลิก]                            |
└─────────────────────────────────────────────────────────────┘
```

### 4. Subscription Report (`/admin/subscription/reports`)

```
┌─────────────────────────────────────────────────────────────┐
|  รายงาน Subscription                                        |
├─────────────────────────────────────────────────────────────┤
|  องค์กร: 78  |  รายได้เดือนนี้: ฿24,501  |  Active: 65    |
|                                                              |
|  กราฟรายได้รายเดือน                                        |
|  ▁▃▅▇███▇▅▃▁  Jan Feb Mar Apr May Jun                      |
|                                                              |
|  ใกล้หมดอายุ (< 7 วัน)                                     |
|  🏥 คลินิกหมอสมชาย   เบสิก   2026-06-15  [ต่ออายุ]          |
|  🏥 ศูนย์สุขภาพสุขใจ พรีเมี่ยม 2026-06-17  [ต่ออายุ]        |
|                                                              |
|  ใช้ Quota (เดือนนี้)                                       |
|  Tier       | องค์กร | Push ใช้/เหลือ | SMS ใช้/เหลือ       |
|  สแตนดาร์ด | 42     | 8,234/2,766   | -/-               |
|  พรีเมี่ยม  | 18     | 3,401/1,599   | 234/266           |
└─────────────────────────────────────────────────────────────┘
```

---

## Flutter Architecture

```
lib/features/subscription_admin/          -- Sheserved Admin only
├── data/
│   ├── models/
│   │   ├── subscription_tier_model.dart
│   │   ├── tier_feature_model.dart
│   │   └── organization_subscription_model.dart
│   └── repositories/
│       ├── subscription_tier_repository.dart
│       └── organization_subscription_repository.dart
├── domain/
│   └── services/
│       └── subscription_validator_service.dart
└── presentation/
    ├── providers/
    │   ├── subscription_tier_provider.dart
    │   └── subscription_report_provider.dart
    └── pages/
        ├── subscription_tier_list_page.dart
        ├── subscription_tier_form_page.dart
        ├── assign_tier_page.dart
        └── subscription_report_page.dart
```

### Admin Guard

```dart
class SubscriptionAdminGuard extends StatelessWidget {
  final Widget child;
  const SubscriptionAdminGuard({required this.child});

  @override
  Widget build(BuildContext context) {
    final user = ServiceLocator.instance.currentUser;
    if (user?.role != 'sheserved_admin') return const AccessDeniedPage();
    return child;
  }
}
```

---

## API / RPC Functions

```sql
-- Sheserved Admin: สร้าง Tier
CREATE OR REPLACE FUNCTION admin_create_tier(
  p_tier_code TEXT, p_display_name_th TEXT, p_display_name_en TEXT,
  p_monthly_fee DECIMAL(12,2), p_features JSONB
) RETURNS UUID;

-- Sheserved Admin: มอบหมาย Tier
CREATE OR REPLACE FUNCTION admin_assign_tier(
  p_profession_id UUID, p_tier_id UUID,
  p_started_at TIMESTAMPTZ, p_expires_at TIMESTAMPTZ, p_assigned_by UUID
) RETURNS UUID;

-- องค์กร: ดึง Tier ของตนเอง
CREATE OR REPLACE FUNCTION get_my_tier(p_profession_id UUID) RETURNS JSONB;

-- องค์กร: ตรวจสอบ Feature เปิดใช้งานหรือไม่
CREATE OR REPLACE FUNCTION check_tier_feature(
  p_profession_id UUID, p_feature_key TEXT
) RETURNS BOOLEAN;
```

---

## แผนการพัฒนา (Roadmap)

| Phase | งาน | สถานะ |
|-------|-----|-------|
| **Phase 1** | DB Schema: `subscription_tiers`, `tier_features`, `organization_subscriptions` | ☐ TODO |
| **Phase 2** | Seed Data + RPC Functions | ☐ TODO |
| **Phase 3** | Flutter: `SubscriptionTierListPage` + `SubscriptionTierFormPage` | ☐ TODO |
| **Phase 4** | Flutter: `AssignTierPage` + `SubscriptionReportPage` | ☐ TODO |
| **Phase 5** | Integration: `check_tier_feature()` กับทุก ERP module | ☐ TODO |
| **Phase 6** | Billing Integration — บันทึกการชำระเงิน | ☐ TODO |

---

*เอกสารนี้ครอบคลุมหน้าจัดการ Subscription Tier สำหรับ Sheserved Platform Admin รวมถึงการมอบหมาย Tier ให้องค์กร และรายงานการใช้งาน*
