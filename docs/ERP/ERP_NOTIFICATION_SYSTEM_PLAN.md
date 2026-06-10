# ERP Notification System Plan — Sheserved

## ภาพรวม (Overview)

ระบบแจ้งเตือนกลาง (Centralized Notification System) สำหรับ Sheserved ERP ทุกโมดูล ออกแบบให้รองรับทั้ง **การแจ้งเตือนภายในองค์กร (Intra-Organization)** และ **การแจ้งเตือนถึงลูกค้าภายนอก (External)** โดยแยกการทำงานเป็น 2 ชั้น:

| ชั้น | รายละเอียด | ค่าใช้จ่าย |
|------|-----------|-----------|
| **ชั้น 1: In-App (Headsector)** | แจ้งเตือนภายในแอป บริเวณมุมขวาบน (Headsector) ของหน้า Home — ใช้ Supabase Realtime + In-app UI | **ฟรี 100%** |
| **ชั้น 2: External Channels** | Push Notification, SMS, Line, Email — ผ่าน Third-party Provider | **มีค่าใช้จ่าย** (ควบคุมผ่าน Subscription Plan) |

> **หลักการพัฒนา:** Phase เริ่มต้นพัฒนา **ชั้น 1 (In-App)** ให้สมบูรณ์ก่อน ชั้น 2 รอเปิดใช้งานตาม Subscription Tier ของแต่ละองค์กร

---

## สถาปัตยกรรม (Architecture)

```
ERP Modules (Sources)
  POS │ Inventory │ HR │ Accounting │ CRM │ Procurement │ HIS │ LIS
   │      │        │       │         │       │           │     │
   └──────┴────────┴───────┴─────────┴───────┴───────────┴─────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │  Notification Events  │
                    │  (Outbox / Event Bus) │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
    ┌─────────────────┐ ┌─────────────┐ ┌──────────────┐
    │  In-App (Free)  │ │  External   │ │  External    │
    │  Headsector     │ │  Push/SMS   │ │  Line/Email  │
    │  Realtime       │ │  (Paid)     │ │  (Paid)      │
    └─────────────────┘ └─────────────┘ └──────────────┘

    Subscription Control: Basic -> Standard -> Premium -> Enterprise
    (In-App only)    (Push)    (SMS+Push)   (All Channels)
```

---

## ชั้น 1: In-App Notification (ฟรี — Phase เริ่มต้น)

### ตำแหน่งแสดงผล: Headsector (มุมขวาบน)

ตามมาตรฐานที่กำหนดไว้ใน [ERP_CORE_ARCHITECTURE.md](ERP_CORE_ARCHITECTURE.md):

- **ตำแหน่ง:** บริเวณ **Headsector (มุมขวาบน)** ในหน้า Home ของแอปพลิเคชัน
- **การเรียงลำดับ:** ล่าสุดอยู่ด้านบนเสมอ (Newest first)
- **รูปแบบการแสดงผล:**
  - พื้นหลังสีม่วงอ่อน (Light Purple)
  - โลโก้ขององค์กรนำหน้าข้อความเสมอ (ดึงจาก `professions.logo_url`)
  - Badge แสดงจำนวนการแจ้งเตือนที่ยังไม่อ่าน

### ฐานข้อมูล (Database Schema)

```sql
-- ============================================================
-- 1. ตารางแจ้งเตือนกลาง
-- ============================================================
CREATE TABLE notifications (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  recipient_user_id     UUID NOT NULL REFERENCES users(id),
  sender_user_id        UUID REFERENCES users(id),               -- NULL = ระบบ
  
  source_module         TEXT NOT NULL
    CHECK (source_module IN ('pos','inventory','hr','accounting','crm','procurement','his','lis','reliability','system')),
  source_entity_type    TEXT NOT NULL,                            -- 'appointment', 'order', 'shift'
  source_entity_id      UUID,
  
  notification_type     TEXT NOT NULL
    CHECK (notification_type IN ('info','warning','success','error','urgent')),
  title                 TEXT NOT NULL,
  body                  TEXT NOT NULL,
  action_url            TEXT,                                     -- Deep link
  action_label          TEXT DEFAULT 'ดูรายละเอียด',
  
  is_read               BOOLEAN DEFAULT false,
  read_at               TIMESTAMPTZ,
  dismissed_at          TIMESTAMPTZ,
  
  external_channels_sent TEXT[] DEFAULT '{}',
  external_sent_at      TIMESTAMPTZ,
  
  created_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_notifications_recipient ON notifications(recipient_user_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(recipient_user_id, is_read) WHERE is_read = false;
CREATE INDEX idx_notifications_profession ON notifications(profession_id, source_module);

-- ============================================================
-- 2. ตารางการตั้งค่าการแจ้งเตือนต่อผู้ใช้
-- ============================================================
CREATE TABLE notification_preferences (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  profession_id         UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  module_name           TEXT NOT NULL
    CHECK (module_name IN ('pos','inventory','hr','accounting','crm','procurement','his','lis','reliability','system')),
  
  enable_in_app         BOOLEAN DEFAULT true,                     -- ฟรีเสมอ
  enable_push           BOOLEAN DEFAULT false,                    -- ต้องมี Subscription
  enable_sms            BOOLEAN DEFAULT false,
  enable_line           BOOLEAN DEFAULT false,
  enable_email          BOOLEAN DEFAULT false,
  
  min_notification_level TEXT DEFAULT 'info'
    CHECK (min_notification_level IN ('urgent','warning','info','success')),
  
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, profession_id, module_name)
);

-- ============================================================
-- 3. ช่องทางแจ้งเตือน ตาม Subscription Tier
-- ============================================================
-- อ้างอิงจาก subscription_tiers + tier_features ใน ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md
-- ไม่สร้างตารางใหม่ — ใช้ tier_features ที่มีอยู่แล้ว

-- ตัวอย่าง Feature Key สำหรับ Notification:
--   feature_category = 'notification_channel'
--   feature_key      = 'in_app' | 'push' | 'sms' | 'line' | 'email'
--   is_enabled       = true/false
--   numeric_value    = quota/เดือน (0 = ไม่จำกัด)

-- Seed (ในระบบจริงจะอยู่ใน ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md):
-- INSERT INTO tier_features (tier_id, feature_category, feature_key, feature_name_th, feature_name_en, is_enabled, numeric_value) VALUES
-- (basic_tier_id,  'notification_channel', 'in_app', 'In-App', 'In-App', true, 0),
-- (basic_tier_id,  'notification_channel', 'push',   'Push',   'Push',   false, 0),
-- (standard_tier_id,'notification_channel','push',   'Push',   'Push',   true, 1000),
-- (premium_tier_id,'notification_channel', 'sms',    'SMS',    'SMS',    true, 500),
-- (enterprise_tier_id,'notification_channel','line', 'Line',   'Line',   true, 0),
-- (enterprise_tier_id,'notification_channel','email','Email',  'Email',  true, 0);

-- ============================================================
-- 4. ตารางใช้งาน External Channel รายเดือน
-- ============================================================
CREATE TABLE notification_usage_monthly (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id UUID NOT NULL REFERENCES professions(id),
  year_month    TEXT NOT NULL,                                     -- '2026-06'
  channel       TEXT NOT NULL CHECK (channel IN ('in_app','push','sms','line','email')),
  count_used    INTEGER NOT NULL DEFAULT 0,
  count_success INTEGER NOT NULL DEFAULT 0,
  count_failed  INTEGER NOT NULL DEFAULT 0,
  UNIQUE (profession_id, year_month, channel)
);

-- ============================================================
-- 5. Row Level Security
-- ============================================================
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY notifications_recipient_isolation ON notifications
  USING (recipient_user_id = auth.uid());

CREATE POLICY notification_preferences_user_isolation ON notification_preferences
  USING (user_id = auth.uid());
```

### การทำงานของ In-App Notification (ฟรี)

1. **Trigger:** ERP module ใดก็ตามสร้าง event -> Insert ลง `notifications`
2. **Realtime:** Supabase Realtime บน `notifications` (filter: `recipient_user_id = currentUser.id`)
3. **Display:** Headsector Bell อัปเดต Badge count + แสดง Panel ล่าสุด
4. **Action:** ผู้ใช้กดอ่าน -> Update `is_read = true` + นำทางไป `action_url`

> **ค่าใช้จ่าย:** 0 บาท — ใช้ Supabase Realtime (ฟรี) + DB Insert (ฟรี)

### HomeErpCard Badge Integration

Badge แจ้งเตือนบน `HomeErpCard` (หน้า Home) ใช้ In-App Notification เดียวกันกับ Headsector:

```dart
// ใน HomeErpCard — ดึง unread count จาก notificationProvider
Consumer(builder: (context, ref, _) {
  final unreadCount = ref.watch(unreadNotificationCountProvider);
  
  if (unreadCount == 0) {
    return Text('ไม่มีการแจ้งเตือนใหม่', 
      style: AppTextStyles.caption.copyWith(color: AppColors.textHint));
  }
  
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text('$unreadCount ใหม่',
        style: AppTextStyles.caption.copyWith(
          color: Colors.red.shade700, fontWeight: FontWeight.w600)),
    ],
  );
});
```

- Badge บน `HomeErpCard` ไม่ใช่ Push Notification — เป็น **In-App Realtime** (ฟรี)
- แสดงเฉพาะการแจ้งเตือนที่ยังไม่อ่าน (`is_read = false`) ใน `notifications` table
- อัปเดตอัตโนมัติเมื่อมี notification ใหม่ผ่าน Supabase Realtime
- ใช้ `Consumer` (Riverpod) เพื่อ re-build เฉพาะส่วน Badge ไม่กระทบ performance หน้า Home

---

## ชั้น 2: External Channels (มีค่าใช้จ่าย — Phase 2)

### ช่องทางการแจ้งเตือน

| ช่องทาง | Provider | ค่าใช้จ่าย/ครั้ง | ความเหมาะสม |
|---------|----------|------------------|-------------|
| **In-App** | Supabase Realtime | **ฟรี** | ทุกกรณี |
| **Push** | Firebase FCM | ~0.0001 บาท | ด่วน, real-time |
| **SMS** | ThaiBulkSMS / Twilio | ~0.20-0.80 บาท | ยืนยันการจอง, OTP |
| **Line** | Line Messaging API | ~0.02 บาท | ลูกค้าที่มี Line OA |
| **Email** | SendGrid / AWS SES | ~0.01 บาท | รายงาน, เอกสาร |

### Subscription Tier ควบคุมช่องทาง

| Tier | ราคา/เดือน | In-App | Push | SMS | Line | Email |
|------|-----------|--------|------|-----|------|-------|
| **Basic** | ฟรี | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Standard** | 299 บาท | ✅ | ✅ (1,000) | ❌ | ❌ | ❌ |
| **Premium** | 599 บาท | ✅ | ✅ (5,000) | ✅ (500) | ❌ | ❌ |
| **Enterprise** | 999 บาท | ✅ | ✅ (ไม่จำกัด) | ✅ (ไม่จำกัด) | ✅ | ✅ |

### การจัดเรียงตามค่าใช้บริการ (Cost-Optimized Routing)

ระบบจะพยายามส่งผ่านช่องทางที่ **ถูกที่สุดที่ผู้ใช้เปิดรับ** ก่อน:

1. **Priority 1:** In-App (ฟรี) -> ส่งทุกครั้ง
2. **Priority 2:** Push (ถูก) -> ถ้า user เปิดรับ และ tier อนุญาต
3. **Priority 3:** Line (ถูกกว่า SMS) -> ถ้า user เชื่อม Line OA
4. **Priority 4:** SMS (แพง) -> ใช้เฉพาะ urgent/ยืนยัน
5. **Priority 5:** Email (ถูก แต่ช้า) -> ใช้สำหรับรายงาน/เอกสาร

---

## Cross-Module Event Registry

### Event Types ตามโมดูล

| โมดูล | Event Key | ระดับ | Default Channels | ผู้รับ |
|-------|-----------|-------|-----------------|--------|
| **CRM** | `crm.appointment.confirmed` | success | In-App + Push* | ผู้ป่วย |
| **CRM** | `crm.appointment.reminder_24h` | warning | In-App + Push* + SMS* | ผู้ป่วย |
| **CRM** | `crm.appointment.reminder_2h` | warning | In-App + Push* + SMS* | ผู้ป่วย |
| **CRM** | `crm.appointment.cancelled` | warning | In-App + Push* | ผู้ป่วย, Staff |
| **CRM** | `crm.appointment.no_show` | error | In-App | Staff |
| **CRM** | `crm.waitlist.available` | success | In-App + Push* | ผู้ป่วย |
| **CRM** | `crm.loyalty.points_earned` | success | In-App | ลูกค้า |
| **CRM** | `crm.coupon.expiring` | warning | In-App | ลูกค้า |
| **POS** | `pos.order.completed` | success | In-App | แคชเชียร์ |
| **POS** | `pos.payment.failed` | error | In-App + Push* | แคชเชียร์ |
| **Inventory** | `inventory.stock.low` | warning | In-App | ผู้จัดการ |
| **Inventory** | `inventory.stock.out` | urgent | In-App + Push* | ผู้จัดการ |
| **HR** | `hr.shift.assigned` | info | In-App | พนักงาน |
| **HR** | `hr.payroll.approved` | success | In-App | พนักงาน |
| **HR** | `hr.leave.approved` | success | In-App | พนักงาน |
| **HR** | `hr.leave.rejected` | error | In-App | พนักงาน |
| **Accounting** | `accounting.invoice.overdue` | warning | In-App | บัญชี |
| **Procurement** | `procurement.po.approved` | success | In-App | จัดซื้อ |
| **System** | `system.role.assigned` | info | In-App | พนักงาน |
| **System** | `system.ownership.transferred` | urgent | In-App | Owner ใหม่ |

> `*` = ต้องมี Subscription Tier ที่รองรับ

### DB: Notification Event Registry

```sql
CREATE TABLE notification_event_registry (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key             TEXT NOT NULL UNIQUE,                     -- 'crm.appointment.confirmed'
  source_module         TEXT NOT NULL,
  event_description     TEXT NOT NULL,
  default_level         TEXT NOT NULL DEFAULT 'info',
  default_channels      TEXT[] DEFAULT '{in_app}',
  requires_subscription BOOLEAN DEFAULT false,
  created_at            TIMESTAMPTZ DEFAULT now()
);
```

---

## Outbox Integration (Reliability Core)

การส่ง External Notification ทุกครั้งต้องผ่าน **Outbox Pattern**:

```sql
-- ใช้ outbox_events ที่มีอยู่แล้ว
INSERT INTO outbox_events (
  aggregate_type, aggregate_id, event_type, payload, status
) VALUES (
  'notification', gen_random_uuid(),
  'notification.external.send',
  jsonb_build_object(
    'notification_id', '...', 'channels', '{push,sms}',
    'recipient_user_id', '...', 'title', '...', 'body', '...'
  ),
  'pending'
);
```

**Worker Process:**
1. Poll `outbox_events` ที่ `event_type = 'notification.external.send'` + `status = 'pending'`
2. เช็ค Subscription Tier
3. ส่งผ่าน Provider ที่เหมาะสม
4. อัปเดต `status = 'processed'` + บันทึก `notification_usage_monthly`
5. ถ้า failed -> `status = 'failed'` + Retry ตาม policy

### Retry Policy

| ช่องทาง | Retry | Backoff | Max Retry |
|---------|-------|---------|-----------|
| Push | 3 ครั้ง | Exponential (1s, 2s, 4s) | 3 |
| SMS | 2 ครั้ง | Linear (5s, 10s) | 2 |
| Line | 3 ครั้ง | Exponential (1s, 2s, 4s) | 3 |
| Email | 3 ครั้ง | Exponential (5s, 10s, 20s) | 3 |

---

## In-App Notification Center (UI)

### Notification Panel (Dropdown)

```
┌─────────────────────────────┐
| 🔔 การแจ้งเตือน        [⚙️] |
├─────────────────────────────┤
| ┌─────────────────────────┐ |
| | 🏥 [Logo] มีนัดหมายใหม่ | |
| |    "คุณมีนัดวันนี้ 14:00" | |
| |    2 นาทีที่แล้ว    [→]  | |
| └─────────────────────────┘ |
| ┌─────────────────────────┐ |
| | 🏥 [Logo] สินค้าใกล้หมด  | |
| |    "Paracetamol เหลือ 5" | |
| |    10 นาทีที่แล้ว  [→]   | |
| └─────────────────────────┘ |
|                             |
| [ดูทั้งหมด]          [ล้าง] |
└─────────────────────────────┘
```

**Features:**
- **Filter:** แยกตามโมดูล
- **Mark All Read:** อ่านทั้งหมด
- **Dismiss:** ซ่อน (ไม่ลบ)
- **Settings:** ไปหน้า `notification_preferences`
- **Infinite Scroll:** 50 รายการ/ครั้ง

---

## Rate Limiting & Quota

### Per-Organization Quota Check

```sql
CREATE OR REPLACE FUNCTION check_notification_quota(
  p_profession_id UUID, p_channel TEXT, p_requested_count INT DEFAULT 1
) RETURNS BOOLEAN AS $$
DECLARE
  v_limit INT; v_used INT; v_year_month TEXT;
BEGIN
  v_year_month := to_char(now(), 'YYYY-MM');

  -- ดึง quota จาก tier_features (ผ่าน organization_subscriptions)
  SELECT f.numeric_value INTO v_limit
  FROM tier_features f
  JOIN organization_subscriptions s ON s.tier_id = f.tier_id
  WHERE s.profession_id = p_profession_id
    AND s.status IN ('trial','active')
    AND f.feature_category = 'notification_channel'
    AND f.feature_key = p_channel
    AND f.is_enabled = true;

  SELECT count_used INTO v_used
  FROM notification_usage_monthly
  WHERE profession_id = p_profession_id AND year_month = v_year_month AND channel = p_channel;
  v_used := COALESCE(v_used, 0);

  -- 0 = unlimited, NULL = ไม่เปิดใช้งาน (return false)
  IF v_limit IS NULL THEN RETURN false; END IF;
  IF v_limit = 0 THEN RETURN true; END IF;
  RETURN (v_used + p_requested_count) <= v_limit;
END;
$$ LANGUAGE plpgsql;
```

### Global Rate Limiting

| Channel | Rate Limit | Window |
|---------|-----------|--------|
| In-App | 10/sec per user | 1 วินาที |
| Push | 500/sec per app | 1 วินาที |
| SMS | 10/min per user | 1 นาที |
| Line | 1000/min per bot | 1 นาที |
| Email | 100/min per domain | 1 นาที |

---

## Flutter Architecture

```
lib/features/notifications/
├── data/
│   ├── models/
│   │   ├── notification_model.dart
│   │   ├── notification_preference_model.dart
│   │   └── notification_usage_model.dart
│   └── repositories/
│       ├── notification_repository.dart
│       ├── notification_preference_repository.dart
│       └── notification_usage_repository.dart
├── domain/
│   └── services/
│       ├── notification_router.dart           -- กำหนด channel ตาม event + tier
│       └── notification_sender_service.dart   -- ส่งผ่าน provider
└── presentation/
    ├── providers/
    │   ├── notification_provider.dart
    │   └── notification_preference_provider.dart
    └── widgets/
        ├── headsector_notification_bell.dart   -- 🔔 มุมขวาบน
        ├── notification_panel.dart
        ├── notification_card.dart
        └── notification_preference_sheet.dart
```

### Headsector Integration

```dart
AppBar(
  actions: [
    const HeadsectorNotificationBell(),  // มุมขวาบน
    const UserAvatarMenu(),
  ],
)
```

---

## แผนการพัฒนา (Roadmap)

| Phase | งาน | ค่าใช้จ่าย | สถานะ |
|-------|-----|-----------|-------|
| **Phase 1** | In-App: `notifications` table + Headsector UI + Realtime | ฟรี | ☐ TODO |
| **Phase 2** | Event Registry + Cross-module integration | ฟรี | ☐ TODO |
| **Phase 3** | Notification Preferences + Filter/Mark Read/Dismiss | ฟรี | ☐ TODO |
| **Phase 4** | Outbox Integration — ทุก event ผ่าน `outbox_events` | ฟรี | ☐ TODO |
| **Phase 5** | Push Notification (Firebase) — Standard Tier | ~299/เดือน | ☐ TODO |
| **Phase 6** | SMS (ThaiBulkSMS) — Premium Tier | ~599/เดือน | ☐ TODO |
| **Phase 7** | Line Messaging API — Enterprise Tier | ~999/เดือน | ☐ TODO |
| **Phase 8** | Email (SendGrid) — Enterprise Tier | ~999/เดือน | ☐ TODO |
| **Phase 9** | Usage Tracking Dashboard + Billing Integration | ฟรี | ☐ TODO |
| **Phase 10** | Notification Analytics (Open rate, Delivery rate) | ฟรี | ☐ TODO |

> **หมายเหตุ:** Phase 1-4 เป็น Foundation (ฟรี 100%) ที่ต้องเสร็จก่อน  Phase 5-8 เป็น External Channels ที่ต้องมี Subscription + Provider API Key ก่อนเปิดใช้งาน

---

## สรุปสิ่งที่ต้องทำต่อ (Next Steps)

### Phase 1 (In-App — ฟรี)
- [ ] Migration: `notifications`, `notification_preferences`, `notification_event_registry`
- [ ] Supabase Realtime subscription: `notifications` filter by `recipient_user_id`
- [ ] Flutter: `HeadsectorNotificationBell` + `NotificationPanel` + `NotificationCard`
- [ ] Flutter Provider: `notificationProvider` (unread count + list + mark read)
- [ ] Integration: CRM module ส่ง event -> Insert `notifications`
- [ ] Integration: POS module ส่ง event -> Insert `notifications`
- [ ] Integration: HR module ส่ง event -> Insert `notifications`

### Phase 2-4 (Foundation — ฟรี)
- [ ] `notification_event_registry` seed data
- [ ] `notification_preferences` UI + save
- [ ] Outbox integration for all external events
- [ ] Rate limiting implementation

### Phase 5+ (External — มีค่าใช้จ่าย)
- [ ] Firebase FCM setup + Push implementation
- [ ] ThaiBulkSMS/Twilio setup + SMS implementation
- [ ] Line Messaging API setup
- [ ] SendGrid/AWS SES setup + Email implementation
- [ ] Subscription tier enforcement
- [ ] Usage tracking + billing integration

---

*เอกสารนี้ครอบคลุมการแจ้งเตือนทุกโมดูลใน ERP โดยใช้ Headsector (มุมขวาบน) ของหน้า Home เป็นพื้นที่ In-App Notification (ฟรี) และควบคุม External Channels ผ่าน Subscription Tier ตามค่าใช้บริการ*
