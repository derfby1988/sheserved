# 🏥 แผนการปรับปรุงระบบปรึกษาแพทย์ด้วยการแชท
# Chat Consultation Improvement Plan

> **วันที่วิเคราะห์:** 13 พฤษภาคม 2569  
> **สถานะ:** Draft v1.0  
> **ขอบเขต:** UX/UI Flow + Database Schema + Technical Improvements

---

## 📋 สรุปสถานะปัจจุบัน (Current State)

### ระบบที่มีอยู่แล้ว

| Feature | File | สถานะ |
|---|---|---|
| รายการห้องแชท | `chat_list_page.dart` | ✅ มีแล้ว |
| ห้องแชท | `chat_room_page.dart` | ✅ มีแล้ว |
| รายชื่อผู้เชี่ยวชาญ | `contact_list_page.dart` | ✅ มีแล้ว |
| วิดีโอคอล | `live_vdo_page.dart` | ✅ มีแล้ว |
| เลือกแพ็คเกจ (Wheel UI) | `package_healthcare_page.dart` | ✅ มีแล้ว |
| วิเคราะห์อาการ (Body Map) | `analyze_body_area_page.dart` | ✅ มีแล้ว |
| Vega AI Pre-consultation | `vega_ai_chat_page.dart` | ✅ มีแล้ว |
| Dashboard แพทย์ | `health_program_request_dashboard.dart` | ✅ มีแล้ว |

### ปัญหาที่พบ

```
❌ ไม่มีระบบ Rating/Review หลังปรึกษา
❌ ไม่มี Session Timer (ไม่รู้เหลือเวลาอีกเท่าไร)
❌ Payment ยังไม่เชื่อมกับ Chat Room opening
❌ ไม่มี Quick Reply Templates สำหรับแพทย์
❌ ไม่มี Medical Note / Summary จากแพทย์
❌ ChatRoom ไม่รู้ว่า consultation_id คืออะไร (metadata ว่าง)
❌ ไม่มี Prescription (ใบสั่งยา) ในระบบแชท
❌ ไม่มี Follow-up Reminder
❌ chat_rooms.participant_ids เป็น array → ไม่ scalable
❌ ไม่มี unread_count → ต้อง load message ทุกครั้ง
❌ ค้นหาใน Chat List ค้นได้แค่ last_message ไม่ได้ค้นชื่อ
```

---

## 🗂️ Database Schema ที่เสนอ

### 1. แก้ไข `consultation_packages` — เพิ่มการตั้งค่าเวลา (ใหม่)

```sql
ALTER TABLE consultation_packages ADD COLUMN IF NOT EXISTS
  session_minutes INT DEFAULT 15,          -- ระยะเวลาให้คำปรึกษา (NULL = ไม่จำกัด)
  expire_minutes INT DEFAULT 120;          -- เวลาหมดอายุหากไม่มีแพทย์รับงาน (นาที)
```

### 2. แก้ไข `chat_rooms` — เพิ่ม columns

```sql
ALTER TABLE chat_rooms ADD COLUMN IF NOT EXISTS
  room_type          TEXT DEFAULT 'general',
  -- 'general' | 'consultation' | 'support'

  consultation_id    UUID REFERENCES consultation_requests(id),
  package_id         UUID REFERENCES consultation_packages(id),
  title              TEXT,
  is_active          BOOLEAN DEFAULT true,
  expires_at         TIMESTAMPTZ,
  session_minutes    INT DEFAULT 15,
  started_at         TIMESTAMPTZ,
  ended_at           TIMESTAMPTZ;
```

### 2. สร้าง `chat_room_members` (แทน participant_ids array)

```sql
CREATE TABLE IF NOT EXISTS chat_room_members (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id        UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role           TEXT DEFAULT 'member',
  -- 'patient' | 'doctor' | 'admin' | 'member'
  joined_at      TIMESTAMPTZ DEFAULT now(),
  last_read_at   TIMESTAMPTZ,
  unread_count   INT DEFAULT 0,
  is_muted       BOOLEAN DEFAULT false,
  UNIQUE(room_id, user_id)
);

CREATE INDEX idx_chat_room_members_user ON chat_room_members(user_id);
CREATE INDEX idx_chat_room_members_room ON chat_room_members(room_id);

-- Trigger: increment unread_count เมื่อมีข้อความใหม่
CREATE OR REPLACE FUNCTION increment_unread_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE chat_room_members
  SET unread_count = unread_count + 1
  WHERE room_id = NEW.room_id
    AND user_id != NEW.sender_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_new_message_increment_unread
  AFTER INSERT ON chat_messages
  FOR EACH ROW EXECUTE FUNCTION increment_unread_count();
```

### 3. แก้ไข `chat_messages` — เพิ่ม columns

```sql
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS
  message_type   TEXT DEFAULT 'text',
  -- 'text'|'image'|'voice'|'file'|'system'|'prescription'|'summary'
  reply_to_id    UUID REFERENCES chat_messages(id),
  is_deleted     BOOLEAN DEFAULT false,
  deleted_at     TIMESTAMPTZ,
  edited_at      TIMESTAMPTZ,
  reactions      JSONB DEFAULT '{}';
  -- {"❤️": ["userId1"], "👍": ["userId2"]}
```

### 4. สร้าง `consultation_sessions` (ใหม่)

```sql
CREATE TABLE IF NOT EXISTS consultation_sessions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id     UUID NOT NULL REFERENCES consultation_requests(id),
  room_id             UUID REFERENCES chat_rooms(id),
  provider_id         UUID NOT NULL REFERENCES users(id),
  patient_id          UUID NOT NULL REFERENCES users(id),
  status              TEXT DEFAULT 'waiting',
  -- 'waiting'|'active'|'paused'|'completed'|'cancelled'
  session_type        TEXT DEFAULT 'chat',
  -- 'chat'|'video'|'voice'
  duration_minutes    INT DEFAULT 15,
  started_at          TIMESTAMPTZ,
  ended_at            TIMESTAMPTZ,
  provider_joined_at  TIMESTAMPTZ,
  patient_joined_at   TIMESTAMPTZ,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);
```

### 5. สร้าง `consultation_notes` — Medical Summary (ใหม่)

```sql
CREATE TABLE IF NOT EXISTS consultation_notes (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id       UUID NOT NULL REFERENCES consultation_requests(id),
  session_id            UUID REFERENCES consultation_sessions(id),
  provider_id           UUID NOT NULL REFERENCES users(id),
  patient_id            UUID NOT NULL REFERENCES users(id),
  chief_complaint       TEXT,       -- อาการสำคัญ
  diagnosis             TEXT,       -- การวินิจฉัย
  treatment_plan        TEXT,       -- แผนการรักษา
  recommendations       TEXT,       -- คำแนะนำ
  follow_up_date        DATE,       -- วันนัดติดตาม
  is_visible_to_patient BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);
```

### 6. สร้าง `prescriptions` — ใบสั่งยา (ใหม่)

```sql
CREATE TABLE IF NOT EXISTS prescriptions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id UUID NOT NULL REFERENCES consultation_requests(id),
  provider_id     UUID NOT NULL REFERENCES users(id),
  patient_id      UUID NOT NULL REFERENCES users(id),
  room_id         UUID REFERENCES chat_rooms(id),
  medications     JSONB NOT NULL DEFAULT '[]',
  -- [{"name":"Paracetamol","dose":"500mg","frequency":"ทุก 6 ชั่วโมง","duration":"3 วัน","notes":""}]
  notes           TEXT,
  issued_at       TIMESTAMPTZ DEFAULT now(),
  expires_at      TIMESTAMPTZ,
  status          TEXT DEFAULT 'active'
  -- 'active'|'dispensed'|'cancelled'
);
```

### 7. สร้าง `consultation_reviews` — Rating (ใหม่)

```sql
CREATE TABLE IF NOT EXISTS consultation_reviews (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id       UUID NOT NULL REFERENCES consultation_requests(id),
  session_id            UUID REFERENCES consultation_sessions(id),
  reviewer_id           UUID NOT NULL REFERENCES users(id),
  provider_id           UUID NOT NULL REFERENCES users(id),
  rating                SMALLINT CHECK (rating BETWEEN 1 AND 5),
  rating_communication  SMALLINT CHECK (rating_communication BETWEEN 1 AND 5),
  rating_expertise      SMALLINT CHECK (rating_expertise BETWEEN 1 AND 5),
  review_text           TEXT,
  is_anonymous          BOOLEAN DEFAULT false,
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(consultation_id, reviewer_id)
);
```

### 8. สร้าง `doctor_quick_replies` — Template Messages (ใหม่)

```sql
CREATE TABLE IF NOT EXISTS doctor_quick_replies (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES users(id),
  title       TEXT NOT NULL,
  content     TEXT NOT NULL,
  category    TEXT DEFAULT 'general',
  -- 'greeting'|'follow_up'|'prescription'|'general'
  sort_order  INT DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT now()
);
```

---

## 🇹🇭 นโยบายการใช้ภาษา (Language Policy)

เพื่อประสบการณ์ที่ดีที่สุดของผู้ป่วย **ระบบจะต้องใช้ "ภาษาไทย" ในทุกสถานะ (Status) และข้อความที่แสดงผล (System Messages)** หลีกเลี่ยงการใช้ภาษาอังกฤษสื่อสารกับผู้ป่วยโดยเด็ดขาด

| สถานะใน DB (Backend) | การแสดงผลใน UI (Frontend) |
|---|---|
| `awaiting_payment` | 🟡 รอชำระเงิน |
| `pending` | ⏳ รอผู้เชี่ยวชาญเข้าร่วม |
| `in_progress` | 🟢 กำลังให้คำปรึกษา |
| `completed` | ✅ เสร็จสิ้น |
| `cancelled` | ❌ ยกเลิก (คืนเงิน) |
| `expired` | ⏰ หมดเวลา (คืนเงิน) |

---

## 🔒 มาตรการความเป็นส่วนตัวของภาพถ่าย (PDPA & Image Privacy)

เนื่องจากการปรึกษาทางการแพทย์มีการส่งภาพถ่ายที่ละเอียดอ่อน (เช่น รอยโรค, อวัยวะ) ระบบแชทต้องมีมาตรการดังนี้:

1. **Private Storage:** รูปภาพในแชทต้องเก็บใน Supabase Storage แบบ Private (เข้าถึงได้เฉพาะ `chat_room_members`)
2. **Camera Only:** ปิดการเลือกรูปจากอัลบั้ม (Gallery) บังคับให้ถ่ายจากกล้อง (Camera) ณ เวลานั้นเท่านั้น เพื่อป้องกันการนำรูปของบุคคลอื่นหรือรูปเก่ามาใช้
3. **AI Face Blur (Free Tier):** ใช้ AI ฝั่ง Client หรือ Server (แบบฟรี) เพื่อตรวจจับและเบลอใบหน้าอัตโนมัติก่อนอัปโหลด
4. **Watermark:** ประทับลายน้ำ (Watermark) ชื่อย่อของผู้ป่วย/เจ้าของรูป ไว้บนรูปภาพทุกใบที่ถ่ายผ่านระบบแชท

---

## 🎨 UX/UI Flow ที่เสนอ

### Flow 1: Patient Journey (ปรับปรุง)

```
[Home Page]
  → [Banner "ปรึกษาแพทย์"]
  → [เลือกแพ็คเกจ — Wheel UI]        ✅ มีแล้ว
  → [วิเคราะห์อาการ Body Map]         ✅ มีแล้ว
  → [Vega AI Pre-screening]           ✅ มีแล้ว
  → [หน้าสรุปอาการ + ยืนยัน]         ← NEW
  → [ชำระเงิน]                        ← NEW
  → [Waiting Room — ⏳ รอผู้เชี่ยวชาญเข้าร่วม] ← NEW
      (หากหมดเวลา expire_minutes → ❌ ยกเลิกและคืนเงินอัตโนมัติ)
  → [ห้องแชท + Session Timer]         ← IMPROVE
      (ผู้ป่วยสามารถคลิกรูปโปรไฟล์แพทย์เพื่อดูประวัติและรีวิวได้)
  → [สรุปผลการปรึกษา (Medical Note)]  ← NEW
  → [ให้คะแนน & รีวิว]               ← NEW
  → [Follow-up Reminder]              ← NEW
```

### Flow 2: Doctor/Provider Journey (ปรับปรุง)

```
[Dashboard — คิวรอรับงาน]   ✅ มีแล้ว
  → [กด "รับงาน" (RPC)]
  → [ดูข้อมูลผู้ป่วย + Body Map Summary]
  → [เข้าห้องแชทอัตโนมัติ]
  → [หากฉุกเฉิน → กด "สละสิทธิ์" เพื่อคืนโควต้าให้แพทย์อื่น] ← NEW
  → [แชท + Quick Reply Templates]     ← NEW
  → [เขียน Medical Note]              ← NEW
  → [ออก Prescription (ใบสั่งยา)]     ← NEW
  → [หมดเวลา / กด "จบ Session" → ล็อกห้องแชท]
  → [ส่ง Summary ให้ผู้ป่วยอัตโนมัติ]  ← NEW
```

### Flow 3: Chat Room — UI Layout ใหม่

```
┌─────────────────────────────────────┐
│ ← [Avatar] นพ.สมชาย  ⏱️12:45 📞 ⋮ │  ← AppBar + Timer (คลิกโปรไฟล์ได้)
├─────────────────────────────────────┤
│ 📋 ปรึกษาแพทย์ทั่วไป | แพ็คเกจ 299฿│  ← Medical Context Banner
│ อาการ: ปวดหัว, มีไข้                │
├─────────────────────────────────────┤
│                                     │
│         [Messages Area]             │
│  ┌──────────────────┐               │
│  │ Text bubble      │               │
│  │ Image bubble     │               │
│  │ Voice bubble     │               │
│  │ Prescription Card│  ← NEW       │
│  │ Medical Summary  │  ← NEW       │
│  │ System message   │  ← NEW       │
│  └──────────────────┘               │
│                   ─────────────── ─ │
│                         ┌─────────┐ │
│                         │ My msg  │ │
│                         └─────────┘ │
├─────────────────────────────────────┤
│ [📎][  พิมพ์ข้อความ...  ][⚡][🎤][➤]│  ← Bottom Input
└─────────────────────────────────────┘
```

---

## 🖼️ UI Design Improvements

### Chat List Page

| ปัญหา | การปรับปรุง |
|---|---|
| ListTile ธรรมดา | Card + gradient + shadow |
| ไม่แสดงประเภท | Chip "ปรึกษาแพทย์" / "กลุ่ม" |
| ไม่มี unread count | Badge จำนวนที่ยังไม่อ่าน |
| ค้นหาได้แค่ last_message | ค้นชื่อผู้เชี่ยวชาญได้ด้วย |
| ไม่มี filter | Tab: ทั้งหมด / ปรึกษา / ทั่วไป |

### Chat Room Page

| ปัญหา | การปรับปรุง |
|---|---|
| ไม่มี Session Timer | Countdown pill ใน AppBar |
| ไม่มีบริบท consultation | Medical Context Banner |
| Long press ไม่มี menu | Reply / Copy / Delete menu |
| ไม่มี quick actions | ⚡ ปุ่ม Quick Reply |
| ไม่มีใบสั่งยา | Prescription Card message type |
| ไม่มีสรุปผล | Medical Summary Card |

### Session Timer Widget (กฎการนับเวลาและการล็อก)

**กฎการทำงาน:**
1. **เริ่มนับเวลา:** เมื่อแพทย์/ผู้เชี่ยวชาญกดรับงาน "ครบ" ตามที่แพ็คเกจระบุ (Required Experts == Joined)
2. **การล็อกห้อง:** เมื่อเวลาหมด (`session_minutes` เป็น 0) ระบบจะ **"ล็อกห้องแชทอัตโนมัติ"** ทันที ไม่ให้พิมพ์ต่อทั้งสองฝ่าย (บังคับจบ session) หรือล็อกเมื่อแพทย์กด "จบ Session" เอง

```
╔═══════════════════════════════╗
║  ⏱️  เหลือเวลา  12:45         ║
║  ████████████░░░░░  85%       ║
╚═══════════════════════════════╝
```

### Medical Summary Card

```
╔═══════════════════════════════╗
║  📋 สรุปผลการปรึกษา           ║
║  ─────────────────────────── ║
║  🩺 การวินิจฉัย: ไข้หวัดใหญ่ ║
║  💊 ยาที่สั่ง: Paracetamol    ║
║  📅 นัดติดตาม: 20 พ.ค. 2569  ║
║  [ดูรายละเอียด] [บันทึก PDF] ║
╚═══════════════════════════════╝
```

### Prescription Card

```
╔═══════════════════════════════╗
║  💊 ใบสั่งยา                  ║
║  ─────────────────────────── ║
║  1. Paracetamol 500mg         ║
║     ทุก 6 ชั่วโมง 3 วัน       ║
║  2. Loratadine 10mg           ║
║     วันละ 1 เม็ด ก่อนนอน     ║
║  [📄 ดูใบสั่งยาเต็ม]         ║
╚═══════════════════════════════╝
```

### Post-Consultation Review

```
╔═══════════════════════════════╗
║  ⭐ ให้คะแนนการปรึกษา         ║
║  นพ.สมชาย ใจดี               ║
║  ─────────────────────────── ║
║  ความเชี่ยวชาญ: ⭐⭐⭐⭐⭐      ║
║  การสื่อสาร:    ⭐⭐⭐⭐☆       ║
║  [เขียนรีวิว...]             ║
║        [ข้าม]    [ส่ง]       ║
╚═══════════════════════════════╝
```

---

## ⚙️ Flutter Model Updates

### `ChatRoom` — เพิ่ม fields

```dart
class ChatRoom {
  // fields เดิม...
  
  // เพิ่มใหม่:
  final String roomType;          // 'general' | 'consultation'
  final String? consultationId;
  final String? packageId;
  final String? title;
  final DateTime? expiresAt;
  final DateTime? startedAt;
  final int sessionMinutes;
  final int unreadCount;          // จาก chat_room_members
}
```

### `ChatMessage` — เพิ่ม fields

```dart
class ChatMessage {
  // fields เดิม...
  
  // เพิ่มใหม่:
  final String messageType;       // 'text'|'image'|'voice'|'prescription'|'summary'|'system'
  final String? replyToId;
  final bool isDeleted;
  final Map<String, List<String>> reactions;
}
```

### Models ใหม่ที่ต้องสร้าง

```dart
// lib/features/consultation/data/models/
class ConsultationSession { ... }
class ConsultationNote { ... }
class Prescription { ... }
class ConsultationReview { ... }

// lib/features/chat/data/models/
class DoctorQuickReply { ... }
class ChatRoomMember { ... }
```

---

## 🔒 Supabase RLS Policies ที่ต้องเพิ่ม

```sql
-- chat_room_members: เห็นเฉพาะห้องที่ตัวเองอยู่
CREATE POLICY "Members see their rooms"
  ON chat_room_members FOR SELECT
  USING (user_id = auth.uid());

-- consultation_notes: ผู้ป่วยเห็นเฉพาะของตัวเอง
CREATE POLICY "Patients see own notes"
  ON consultation_notes FOR SELECT
  USING (patient_id = auth.uid() AND is_visible_to_patient = true);

-- prescriptions: เห็นเฉพาะที่เกี่ยวข้อง
CREATE POLICY "Users see own prescriptions"
  ON prescriptions FOR SELECT
  USING (patient_id = auth.uid() OR provider_id = auth.uid());

-- consultation_reviews: เขียนได้ครั้งเดียว
CREATE POLICY "Patients write own review"
  ON consultation_reviews FOR INSERT
  WITH CHECK (reviewer_id = auth.uid());
```

---

## 📡 Supabase Realtime Channels

```dart
// 1. Messages ในห้อง
supabase.channel('room:$roomId')
  .onPostgresChanges(
    event: PostgresChangeEvent.insert,
    table: 'chat_messages',
    filter: 'room_id=eq.$roomId')

// 2. Session status
supabase.channel('session:$sessionId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    table: 'consultation_sessions')

// 3. Unread count badge
supabase.channel('member:$userId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    table: 'chat_room_members',
    filter: 'user_id=eq.$userId')
```

---

## 🗓️ Migration Plan (ลำดับ Implement)

### Sprint 1 — Foundation (สัปดาห์ 1-2)
- [ ] สร้าง `chat_room_members` + migrate participant_ids เดิม
- [ ] เพิ่ม columns ใน `chat_rooms`, `chat_messages`
- [ ] อัปเดต `ChatRoom` / `ChatMessage` models
- [ ] unread badge ใน Chat List

### Sprint 2 — Session (สัปดาห์ 3-4)
- [ ] สร้าง `consultation_sessions`
- [ ] Session Timer Widget
- [ ] System Messages (เริ่ม/จบ session)
- [ ] เชื่อม consultation flow → chat room โดยอัตโนมัติ

### Sprint 3 — Medical Features (สัปดาห์ 5-6)
- [ ] `consultation_notes` + Medical Note UI
- [ ] Quick Reply Templates
- [ ] Reply to Message
- [ ] Medical Context Banner ใน Chat Room

### Sprint 4 — Completion (สัปดาห์ 7-8)
- [ ] `prescriptions` + Prescription Card
- [ ] `consultation_reviews` + Rating UI
- [ ] Follow-up Reminder (Push Notification)
- [ ] PDF Export

---

---

## 👨‍⚕️ ระบบจำกัดสิทธิ์และแสดงสถานะกลุ่มผู้เชี่ยวชาญในห้องแชท

### สภาพปัจจุบันจากโค้ด

`ExpertGroup` ใน `consultation_packages` มีโครงสร้างดังนี้ (จาก `package_admin_page.dart` และ `consultation_package.dart`):

```dart
class ExpertGroup {
  final String id;
  final String name;      // ชื่อกลุ่ม เช่น "หมอ", "เภสัช", "อาจารย์แพทย์"
  final String role;      // 'professor' | 'specialist' | 'pharmacist' | 'doctor'
  final int maxExperts;   // จำนวนสูงสุด เช่น ×1, ×2
  final bool isRequired;  // ⭐ บังคับหรือไม่
}
```

**ตัวอย่างแพ็คเกจจากภาพ (495 บาท):**
- `หมอ ×1` (isRequired: true)
- `เภสัช ×1` (isRequired: false)

**ปัญหาปัจจุบัน:** Dashboard แพทย์ (`_isProvider`) กรองเฉพาะ `_myPackageIds` แต่ไม่ได้กรองโดย `ExpertGroup.role` → แพทย์ทุกประเภทสามารถรับงานที่ไม่ตรงกับ role ของตัวเองได้

---

### 🔒 Access Control: จำกัดสิทธิ์เข้าห้องแชทตาม ExpertGroup

#### กฎหลัก

```
แพทย์/ผู้เชี่ยวชาญเข้าห้องแชทได้ก็ต่อเมื่อ:
  1. professionId ของแพทย์ตรงกับ ExpertGroup.role ของแพ็คเกจ
  2. จำนวนที่เข้าร่วมแล้วใน group นั้น < ExpertGroup.maxExperts
  3. consultation_request.status == 'pending' (ยังไม่มีใครรับครบ)
```

#### ตาราง `consultation_room_experts` (ใหม่)

```sql
-- ติดตามการตอบรับเข้าร่วมของแต่ละ ExpertGroup
CREATE TABLE IF NOT EXISTS consultation_room_experts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id   UUID NOT NULL REFERENCES consultation_requests(id) ON DELETE CASCADE,
  room_id           UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  expert_group_id   TEXT NOT NULL,      -- ExpertGroup.id จาก package
  expert_group_name TEXT NOT NULL,      -- ชื่อกลุ่ม เช่น "หมอ", "เภสัช"
  expert_group_role TEXT NOT NULL,      -- 'doctor' | 'pharmacist' | 'specialist' | 'professor'
  max_experts       INT DEFAULT 1,      -- จำนวนสูงสุดของกลุ่มนี้
  is_required       BOOLEAN DEFAULT false,
  provider_id       UUID REFERENCES users(id),  -- NULL = ยังไม่มีใครรับ
  status            TEXT DEFAULT 'waiting',      -- 'waiting' | 'joined' | 'declined'
  joined_at         TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE(consultation_id, expert_group_id, provider_id)
);

CREATE INDEX idx_room_experts_consultation ON consultation_room_experts(consultation_id);
CREATE INDEX idx_room_experts_provider ON consultation_room_experts(provider_id);
```

#### Logic เมื่อ Provider กด "รับงาน" (แก้ `_joinRequest` ใน Dashboard)

```dart
Future<void> _joinRequest(ConsultationEntry entry) async {
  final user = _currentUser;
  if (user == null) return;

  // 1. ตรวจสิทธิ์: role ของ provider ตรงกับ ExpertGroup ในแพ็คเกจหรือไม่?
  final eligibleGroup = entry.expertGroups.firstWhereOrNull(
    (g) => g.role == user.professionRole &&
           g.currentCount < g.maxExperts,
  );
  if (eligibleGroup == null) {
    // แสดง error: "คุณไม่อยู่ในกลุ่มผู้เชี่ยวชาญของแพ็คเกจนี้"
    return;
  }

  // 2. Assign provider ผ่าน Supabase RPC เพื่อป้องกัน Race Condition (แย่งรับงาน)
  final response = await Supabase.instance.client.rpc(
    'assign_provider_to_group',
    params: {
      'p_consultation_id': entry.id,
      'p_provider_id': user.id,
      'p_expert_group_id': eligibleGroup.id,
    },
  );

  if (response == false || response['success'] == false) {
    // แสดง error: "โควต้าเต็มแล้ว มีแพทย์ท่านอื่นรับงานไปแล้ว"
    return;
  }

  // 3. อัปเดต consultation status ถ้า required groups ครบแล้ว
  final allRequiredFilled = await _repo.checkRequiredGroupsFilled(entry.id);
  if (allRequiredFilled) {
    await _repo.updateStatus(entry.id, 'in_progress');
  }
}
```

#### SQL Query: ตรวจ required groups ครบหรือยัง

```sql
-- คืน true ถ้ากลุ่มที่ isRequired ทั้งหมดมี provider เข้าร่วมแล้ว
SELECT NOT EXISTS (
  SELECT 1 FROM consultation_room_experts
  WHERE consultation_id = :id
    AND is_required = true
    AND status != 'joined'
) AS all_required_filled;
```

---

### 🎨 UI: Expert Group Status Panel ในห้องแชท

แสดงเป็น Banner ด้านบนห้องแชท ให้ผู้ป่วยเห็นว่ากลุ่มใดเข้าร่วมแล้วบ้าง:

```
┌────────────────────────────────────────────┐
│  👥 กลุ่มผู้เชี่ยวชาญที่เข้าร่วม           │
│  ┌─────────────────────────────────────┐   │
│  │ ⭐ หมอ        ✅ นพ.สมชาย ใจดี     │   │  ← required + joined
│  │    เภสัช      ⏳ รอเภสัชกร...       │   │  ← optional + waiting
│  └─────────────────────────────────────┘   │
│  ✅ สามารถแชทได้เลย ไม่ต้องรอให้ครบ     │
└────────────────────────────────────────────┘
```

#### Widget: `ExpertGroupStatusBanner`

```dart
class ExpertGroupStatusBanner extends StatelessWidget {
  final List<RoomExpertStatus> expertStatuses;
  final bool isCollapsible;

  // แสดงสถานะแต่ละ group:
  // - waiting  → ⏳ icon + "รอ[ชื่อกลุ่ม]..."  (สีเทา)
  // - joined   → ✅ icon + ชื่อแพทย์           (สีเขียว)
  // - declined → ❌ icon + "ปฏิเสธ"            (สีแดง)
}

class RoomExpertStatus {
  final String groupId;
  final String groupName;
  final String groupRole;
  final bool isRequired;
  final int maxExperts;
  final String status;          // 'waiting' | 'joined' | 'declined'
  final String? providerName;
  final String? providerAvatar;
  final DateTime? joinedAt;
}
```

#### ตัวอย่าง UI States

**State 1: รอทุกกลุ่ม (เพิ่งสร้าง consultation)**
```
┌────────────────────────────────────────┐
│ ⏳ รอผู้เชี่ยวชาญเข้าร่วม...           │
│  ⭐ หมอ      ⏳ รอ...                   │
│     เภสัช   ⏳ รอ...                   │
│ 💬 คุณสามารถส่งข้อความได้เลย          │
└────────────────────────────────────────┘
```

**State 2: required group เข้าแล้ว (พร้อมใช้งาน)**
```
┌────────────────────────────────────────┐
│ ✅ พร้อมให้คำปรึกษา                   │
│  ⭐ หมอ      ✅ นพ.สมชาย ใจดี  (14:32)│
│     เภสัช   ⏳ รอเภสัชกร...           │
└────────────────────────────────────────┘
```

**State 3: ครบทุกกลุ่ม**
```
┌────────────────────────────────────────┐
│ ✅ ผู้เชี่ยวชาญพร้อมให้บริการครบแล้ว  │
│  ⭐ หมอ      ✅ นพ.สมชาย ใจดี  (14:32)│
│     เภสัช   ✅ ภก.สมหญิง    (14:35)  │
└────────────────────────────────────────┘
```

---

### 📡 Realtime: ติดตาม Expert Join Status

```dart
// Subscribe เพื่ออัปเดต Banner แบบ real-time
supabase.channel('room_experts:$consultationId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    table: 'consultation_room_experts',
    filter: 'consultation_id=eq.$consultationId',
    callback: (payload) {
      // อัปเดต ExpertGroupStatusBanner
      _refreshExpertStatuses();
    },
  )
  .subscribe();
```

---

### 🔄 Flow การเข้าร่วมของผู้เชี่ยวชาญ

```
[Dashboard แพทย์]
    ↓ กด "รับงาน"
    ↓ ตรวจ: role ตรงกับ ExpertGroup? → ไม่ตรง → แสดง error
    ↓ ตรง → บันทึกใน consultation_room_experts (status: 'joined')
    ↓ ส่ง Realtime event
    ↓ ห้องแชทผู้ป่วยอัปเดต Banner อัตโนมัติ
    ↓ consultation status → 'in_progress' ถ้า required groups ครบ
```

---

### ไฟล์ที่ต้องแก้ไข/สร้าง

| ไฟล์ | การเปลี่ยนแปลง |
|---|---|
| `consultation_request_model.dart` | เพิ่ม `expertGroups` field (ดึงจาก package) |
| `consultation_repository.dart` | เพิ่ม `assignProviderToGroup()`, `getRoomExpertStatuses()` |
| `health_program_request_dashboard.dart` | แก้ `_joinRequest()` ให้ตรวจ role ก่อนรับงาน |
| `ExpertGroupStatusBanner` (ใหม่) | Widget แสดงสถานะการเข้าร่วม |
| `chat_room_page.dart` / `ExpertChatRoomPage` | เพิ่ม Banner ด้านบน + Realtime subscription |
| DB: `consultation_room_experts` | สร้างตารางใหม่ |

---

## 🚨 ปัญหาวิกฤต: roomId ไม่แยกตาม Consultation (Critical Bug)

### สภาพปัจจุบัน — Bug ที่ต้องแก้ทันที

จากการวิเคราะห์โค้ดใน `health_program_request_dashboard.dart` บรรทัด 56-57:

```dart

// ❌ โค้ดปัจจุบัน — ผิดมาก!
final userId = map['user_id'] as String? ?? 'unknown';
final shortId = userId.length >= 8 ? userId.substring(0, 8) : userId;
final roomId = 'consult_$shortId';  // ← ใช้แค่ userId ตัวแรก 8 ตัว!
```

**ผลเสียที่เกิดขึ้นตอนนี้:**

| ปัญหา | ตัวอย่าง |
|---|---|
| ผู้ป่วย A สั่งปรึกษา 3 ครั้ง → **ใช้ room เดียวกันทั้ง 3 ครั้ง** | roomId = `consult_a1b2c3d4` ทุกครั้ง |
| ประวัติแชทปะปนกันหมด | ครั้งที่ 1 (ไข้) + ครั้งที่ 2 (ปวดหลัง) อยู่ในห้องเดียวกัน |
| แพทย์คนละคนเห็นแชทของกันและกัน | provider_id ต่างกัน แต่ room เดิม |
| ไม่รู้ว่าข้อความไหนของ consultation ไหน | ไม่มี context เลย |

### วิธีแก้ที่ถูกต้อง

`roomId` ต้องผูกกับ `consultation_request.id` **1:1** เสมอ:

```dart
// ✅ โค้ดที่ถูกต้อง
final consultationId = map['id'] as String;        // ID ของ consultation_request
final roomId = 'consult_$consultationId';           // unique ต่อการปรึกษา 1 ครั้ง
```

หรือดีกว่านั้น — เก็บ `room_id` ใน `consultation_requests` table โดยตรง:

```sql
-- เพิ่ม column room_id ใน consultation_requests
ALTER TABLE consultation_requests
  ADD COLUMN IF NOT EXISTS room_id UUID REFERENCES chat_rooms(id);
```

```dart
// เมื่อ assign provider → สร้าง room → เก็บ room_id กลับไปใน consultation
final roomId = 'consult_${entry.id}'; // consultation_request.id → unique
```

---

## 🏗️ สถาปัตยกรรม: 1 Consultation = 1 Chat Room

### ความสัมพันธ์ที่ถูกต้อง

```
consultation_requests (1)
    │
    ├── room_id ──────────────────→ chat_rooms (1)
    │                                    │
    │                               chat_room_members (many)
    │                                    ├── patient_id (role: 'patient')
    │                                    └── provider_id (role: 'doctor')
    │
    ├── consultation_sessions (many)    ← session แต่ละครั้ง
    ├── consultation_notes (1)          ← สรุปผลจากแพทย์
    ├── prescriptions (many)            ← ใบสั่งยา
    └── consultation_reviews (1)        ← คะแนนรีวิว
```

### SQL: สร้าง room ที่ผูกกับ consultation

```sql
-- Function: สร้าง dedicated room เมื่อ provider รับงาน
CREATE OR REPLACE FUNCTION create_consultation_room(
  p_consultation_id UUID,
  p_patient_id      UUID,
  p_provider_id     UUID,
  p_package_name    TEXT,
  p_package_id      UUID
)
RETURNS UUID AS $$
DECLARE
  v_room_id UUID;
BEGIN
  -- 1. สร้าง chat room ใหม่
  INSERT INTO chat_rooms (
    id, room_type, consultation_id, package_id,
    title, is_active, session_minutes, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    'consultation',
    p_consultation_id,
    p_package_id,
    'ปรึกษา: ' || p_package_name,
    true,
    15,
    now(), now()
  )
  RETURNING id INTO v_room_id;

  -- 2. เพิ่มผู้ป่วยและแพทย์เป็น members
  INSERT INTO chat_room_members (room_id, user_id, role)
  VALUES
    (v_room_id, p_patient_id,  'patient'),
    (v_room_id, p_provider_id, 'doctor');

  -- 3. อัปเดต consultation_requests ด้วย room_id
  UPDATE consultation_requests
  SET room_id = v_room_id,
      updated_at = now()
  WHERE id = p_consultation_id;

  RETURN v_room_id;
END;
$$ LANGUAGE plpgsql;
```

---

## 📚 หน้าประวัติการปรึกษา (Consultation History)

### หน้า 1: ผู้ป่วย — ประวัติการปรึกษาของฉัน

**Route:** `/my-consultations`  
**File ที่ต้องสร้าง:** `lib/features/consultation/presentation/pages/my_consultations_page.dart`

```
┌──────────────────────────────────────┐
│  ← ประวัติการปรึกษาของฉัน           │
│     [ทั้งหมด] [กำลังดำเนินการ] [จบแล้ว]│
├──────────────────────────────────────┤
│                                      │
│  ┌────────────────────────────────┐  │
│  │  📅 10 พ.ค. 2569 | 14:30      │  │
│  │  💊 แพ็คเกจแพทย์ทั่วไป 299฿   │  │
│  │  👨‍⚕️ นพ.สมชาย ใจดี           │  │
│  │  🩺 อาการ: ปวดหัว, มีไข้       │  │
│  │  ✅ เสร็จสิ้น                  │  │
│  │  [ดูบทสนทนา]  [ดูสรุปผล]      │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  📅 2 พ.ค. 2569 | 09:15       │  │
│  │  💊 แพ็คเกจแพทย์เฉพาะทาง 799฿│  │
│  │  👨‍⚕️ รอแพทย์รับงาน           │  │
│  │  🩺 อาการ: ปวดหลัง            │  │
│  │  🕐 รอดำเนินการ               │  │
│  │  [ดูสถานะ]                    │  │
│  └────────────────────────────────┘  │
│                                      │
└──────────────────────────────────────┘
```

**Query สำหรับดึงข้อมูล:**

```sql
-- ดึงประวัติการปรึกษาของผู้ป่วย (พร้อมข้อมูลแพทย์และสรุปผล)
SELECT
  cr.id,
  cr.package_name,
  cr.price,
  cr.status,
  cr.created_at,
  cr.room_id,
  -- ข้อมูลแพทย์
  u.first_name || ' ' || u.last_name AS provider_name,
  u.profile_image_url AS provider_avatar,
  -- สรุปผล
  cn.diagnosis,
  cn.follow_up_date,
  -- อาการ
  cr.body_area
FROM consultation_requests cr
LEFT JOIN users u ON u.id = cr.provider_id
LEFT JOIN consultation_notes cn ON cn.consultation_id = cr.id
WHERE cr.user_id = auth.uid()
ORDER BY cr.created_at DESC;
```

**Dart Model:**

```dart
class MyConsultationHistoryItem {
  final String consultationId;
  final String packageName;
  final double price;
  final String status;
  final DateTime createdAt;
  final String? roomId;          // เข้าห้องแชทได้จาก history
  final String? providerName;
  final String? providerAvatar;
  final String? diagnosis;       // สรุปการวินิจฉัย
  final DateTime? followUpDate;
  final Map<String, dynamic> bodyArea;
}
```

---

### หน้า 2: ผู้ให้คำปรึกษา — ประวัติการให้บริการของฉัน

**Route:** `/my-consultation-history`  
**File ที่ต้องสร้าง:** `lib/features/consultation/presentation/pages/provider_history_page.dart`

```
┌──────────────────────────────────────┐
│  ← ประวัติการให้คำปรึกษา            │
│                                      │
│  📊 สถิติของฉัน                      │
│  ┌──────┐ ┌──────┐ ┌──────┐         │
│  │  42  │ │ 4.8⭐│ │ 38  │         │
│  │ ครั้ง │ │คะแนน │ │จบแล้ว│        │
│  └──────┘ └──────┘ └──────┘         │
│                                      │
│  [ทั้งหมด] [เดือนนี้] [ปีนี้]        │
├──────────────────────────────────────┤
│                                      │
│  ┌────────────────────────────────┐  │
│  │  📅 10 พ.ค. 2569 | 14:30–15:00 │  │
│  │  👤 คุณมานี มีดี               │  │
│  │  💊 แพ็คเกจแพทย์ทั่วไป 299฿   │  │
│  │  🩺 ไข้หวัดใหญ่                │  │
│  │  ⭐ 5.0 | 30 นาที              │  │
│  │  [ดูบทสนทนา]  [ดูNote]        │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  📅 8 พ.ค. 2569 | 10:00–10:15 │  │
│  │  👤 คุณสมศรี ดีใจ              │  │
│  │  💊 แพ็คเกจแพทย์เฉพาะทาง      │  │
│  │  🩺 ปวดเข่าเรื้อรัง            │  │
│  │  ⭐ 4.5 | 15 นาที              │  │
│  │  [ดูบทสนทนา]  [ดูNote]        │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

**Query สำหรับดึงข้อมูล:**

```sql
-- ดึงประวัติการให้บริการของ provider
SELECT
  cr.id,
  cr.package_name,
  cr.price,
  cr.status,
  cr.created_at,
  cr.room_id,
  -- ข้อมูลผู้ป่วย
  u.first_name || ' ' || u.last_name AS patient_name,
  u.profile_image_url AS patient_avatar,
  -- Session duration
  cs.started_at,
  cs.ended_at,
  EXTRACT(EPOCH FROM (cs.ended_at - cs.started_at))/60 AS duration_minutes,
  -- คะแนน
  crv.rating,
  -- สรุปผล
  cn.diagnosis
FROM consultation_requests cr
LEFT JOIN users u ON u.id = cr.user_id
LEFT JOIN consultation_sessions cs ON cs.consultation_id = cr.id
LEFT JOIN consultation_reviews crv ON crv.consultation_id = cr.id
LEFT JOIN consultation_notes cn ON cn.consultation_id = cr.id
WHERE cr.provider_id = auth.uid()
ORDER BY cr.created_at DESC;
```

**สถิติ Provider (สำหรับ Portfolio/Degree):**

```sql
-- คำนวณสถิติรวมของ provider
SELECT
  COUNT(*) AS total_consultations,
  COUNT(*) FILTER (WHERE status = 'completed') AS completed_count,
  AVG(crv.rating) AS avg_rating,
  SUM(EXTRACT(EPOCH FROM (cs.ended_at - cs.started_at))/3600) AS total_hours,
  COUNT(DISTINCT cr.package_id) AS package_types_served
FROM consultation_requests cr
LEFT JOIN consultation_reviews crv ON crv.consultation_id = cr.id
LEFT JOIN consultation_sessions cs ON cs.consultation_id = cr.id
WHERE cr.provider_id = :providerId;
```

---

### หน้า 3: ดูบทสนทนาย้อนหลัง (Read-Only Chat History)

**Route:** `/consultation-chat-history/:consultationId`

```
┌──────────────────────────────────────┐
│  ← บทสนทนา | 10 พ.ค. 2569           │
│  📋 แพ็คเกจแพทย์ทั่วไป | เสร็จสิ้น  │
│  [Read Only — ดูย้อนหลัง]           │
├──────────────────────────────────────┤
│                                      │
│  [System] เริ่มการปรึกษา 14:30       │
│                                      │
│  ┌──────────────────┐                │
│  │ สวัสดีครับ ผมมีไข้│                │
│  │ มา 2 วันแล้ว      │  14:31        │
│  └──────────────────┘                │
│                   ┌────────────────┐ │
│                   │สวัสดีครับ      │ │
│                   │ขอถามอาการ...   │ │
│                   │           14:32│ │
│                   └────────────────┘ │
│                                      │
│  [System] จบการปรึกษา 15:00          │
│                                      │
├──────────────────────────────────────┤
│  📋 สรุปผล: ไข้หวัดใหญ่             │
│  💊 ยา: Paracetamol 500mg            │
│  📅 นัดติดตาม: 17 พ.ค. 2569         │
│  [ดาวน์โหลด PDF]                    │
└──────────────────────────────────────┘
```

**ข้อกำหนด Read-Only:**
- ผู้ป่วยและแพทย์เจ้าของ consultation ดูได้เท่านั้น
- ไม่สามารถส่งข้อความเพิ่ม (input bar ถูกซ่อน)
- แสดง Medical Summary ด้านล่างเสมอ

---

## 📊 ตาราง Entity Relationship สรุป

```
users
  ├── (patient) → consultation_requests → chat_rooms → chat_messages
  │                    │                      │
  │                    ├── consultation_sessions
  │                    ├── consultation_notes
  │                    ├── prescriptions
  │                    └── consultation_reviews
  │
  └── (provider) → consultation_requests (provider_id)
                       └── doctor_quick_replies (ส่วนตัว)
```

---

## 🔒 RLS สำหรับ History

```sql
-- ผู้ป่วยดูได้เฉพาะ consultation ของตัวเอง
CREATE POLICY "Patients see own consultations"
  ON consultation_requests FOR SELECT
  USING (user_id = auth.uid() OR provider_id = auth.uid());

-- ดูบทสนทนาย้อนหลังได้ถ้าเป็น member ของ room นั้น
CREATE POLICY "Room members see messages"
  ON chat_messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM chat_room_members
      WHERE room_id = chat_messages.room_id
        AND user_id = auth.uid()
    )
  );

-- Provider ดูประวัติของตัวเอง
CREATE POLICY "Provider sees own history"
  ON consultation_notes FOR SELECT
  USING (provider_id = auth.uid() OR patient_id = auth.uid());
```

---

## 🧪 แผนการแบ่ง Phase เพื่อการทดสอบ (Testable Phases)

การทำงานจะแบ่งออกเป็น 4 Phase โดยแต่ละ Phase **ต้องสามารถทดสอบ End-to-End ได้จริง** ก่อนเริ่ม Phase ถัดไป

### Phase 1: Core Isolation & Access Control (สัปดาห์นี้)
**งานที่ต้องทำ:**
- [x] อัปเดต `consultation_packages` เพิ่มตั้งค่าเวลา + สร้างตาราง `consultation_room_experts`
- [x] สร้าง SQL Function `create_consultation_room()` และ `assign_provider_to_group` (RPC)
- [x] แก้ `roomId` generation ใน Dart ให้ใช้ ID ของ Consultation เสมอ
- [x] สร้างตาราง `chat_room_members` และเพิ่ม columns `room_id` ใน `consultation_requests`
- [x] สร้าง Trigger SQL `init_consultation_room_experts` ให้เตรียมโควต้าแพทย์ตอนคนไข้สร้างคำปรึกษา
- [x] อัปเดตการกดรับงานใน Dashboard ให้ยิงผ่าน RPC (เชื่อมต่อ UI Dart)

**จุดที่ต้องเทสต์ผ่าน (Test Checkpoints):**
- [ ] 🧪 สร้างคำปรึกษา 2 ครั้ง → ได้ห้องแชทแยกกัน 2 ห้อง (1:1 Isolation)
- [ ] 🧪 แพทย์แย่งกันกดรับงานพร้อมกัน 2 คนในแพ็คเกจ 1 โควต้า → คนที่สองต้องถูกปฏิเสธ (Race Condition Protected)
- [ ] 🧪 แพทย์ที่ Role ไม่ตรงกับแพ็คเกจ → กดรับงานไม่ได้

### Phase 2: Live UI & Session Management (สัปดาห์ 1-2)
**งานที่ต้องทำ:**
- [ ] สร้าง `ExpertGroupStatusBanner` Widget และใช้ Realtime Subscription คอยอัปเดต
- [ ] สร้าง Session Timer Widget แสดงเวลาใน AppBar 
- [ ] อัปเดต Logic การล็อกห้องแชทเมื่อเวลาหมด (`session_minutes` = 0)
- [ ] เพิ่มปุ่ม "สละสิทธิ์" ให้แพทย์และจัดการคืนโควต้า

**จุดที่ต้องเทสต์ผ่าน (Test Checkpoints):**
- [ ] 🧪 ผู้ป่วยรอในห้องแชท → แพทย์กดรับงานปุ๊บ Banner เปลี่ยนเป็น ✅ ทันทีไม่ต้องรีเฟรช
- [ ] 🧪 แพทย์กด "สละสิทธิ์" → Banner เปลี่ยนกลับเป็น ⏳ และแพทย์คนอื่นสามารถกดรับแทนได้
- [ ] 🧪 เมื่อเวลาหมดหรือกดจบ Session → ช่องพิมพ์ข้อความต้องถูกล็อกทั้งสองฝ่าย

### Phase 3: PDPA & Medical Features (สัปดาห์ 3-4)
**งานที่ต้องทำ:**
- [ ] สร้างระบบอัปโหลดรูป: บังคับใช้กล้อง (Camera Only) + Private Storage
- [ ] เชื่อมต่อ AI Face Blur ฝั่ง Client/Server และประทับลายน้ำชื่อย่อ
- [ ] สร้าง `consultation_notes`, `prescriptions` และ UI ที่เกี่ยวข้องในแชท (Card)
- [ ] เพิ่ม Quick Reply Templates ให้แพทย์

**จุดที่ต้องเทสต์ผ่าน (Test Checkpoints):**
- [ ] 🧪 กดไอคอนรูปภาพ → ไม่สามารถเลือกรูปจาก Gallery ได้ (บังคับถ่ายรูปใหม่เท่านั้น)
- [ ] 🧪 ถ่ายรูปที่มีใบหน้า → AI เบลอหน้าให้อัตโนมัติและมีลายน้ำแปะทับรูปเมื่อส่ง
- [ ] 🧪 แพทย์ส่งใบสั่งยา → ผู้ป่วยเห็นการ์ดใบสั่งยาแสดงขึ้นมาในแชท

### Phase 4: History & Auto-Refund (สัปดาห์ 5-6)
**งานที่ต้องทำ:**
- [ ] สร้าง Tab ประวัติและหน้า `my_consultations_page.dart` ใน Profile ผู้ป่วย
- [ ] สร้าง Tab ประวัติและหน้า `provider_history_page.dart` ใน Profile แพทย์
- [ ] สร้างหน้า `consultation_chat_history_page.dart` สำหรับดูแชทย้อนหลัง (Read-Only)
- [ ] สร้างระบบ Cron / Edge Function เพื่อยกเลิกและคืนเงินอัตโนมัติหากหมด `expire_minutes`

**จุดที่ต้องเทสต์ผ่าน (Test Checkpoints):**
- [ ] 🧪 สร้าง Request แล้วไม่มีแพทย์รับงานจนหมดเวลา `expire_minutes` → สถานะเปลี่ยนเป็น "ยกเลิก" และระบบคืนเงิน
- [ ] 🧪 กดดูประวัติแชทที่จบไปแล้วจากหน้า Profile → ต้องเป็น Read-Only ไม่มีช่องให้พิมพ์ส่งข้อความ

---

## 🗂️ การวางหน้าประวัติใน Profile Page (Tab Integration)

### โครงสร้าง Tab ปัจจุบันใน `profile_page.dart`

ปัจจุบัน `_selectedTabIndex` มี 3 tabs:

| Index | Tab | แสดงเมื่อ |
|---|---|---|
| 0 | โปรไฟล์ (ชื่ออาชีพ) | ทุกคน |
| 1 | จิตอาสา | ทุกคน |
| 2 | อนุมัติบริจาค | `_canApproveDonation == true` เท่านั้น |

### Tab ใหม่ที่ต้องเพิ่ม

#### สำหรับ **ผู้ป่วย (consumer_profile)**

เพิ่ม Tab index ใหม่ (ต่อจาก index ปัจจุบัน):

```
Tab: "ประวัติการปรึกษา" (Icons.medical_services_outlined)
  → แสดงหน้า my_consultations_page.dart
  → แสดงเมื่อ: user มี role = consumer (ไม่ใช่ provider)
  → ตำแหน่ง: แถบ Tab ใน profile ถัดจาก "จิตอาสา"
```

**ตัวอย่างโค้ด Tab ที่ต้องเพิ่มใน `_buildContent()`:**

```dart
// เพิ่มเงื่อนไขตรวจว่าเป็น consumer หรือเปล่า
bool get _isConsumer =>
    _user?.professionId == null ||
    _user?.professionId == '00000000-0000-0000-0000-000000000001';

bool get _isProvider => !_isConsumer;

// ใน Tab Row:
if (_isConsumer)
  SizedBox(
    width: MediaQuery.of(context).size.width / tabCount,
    child: _buildTabItem(
      icon: Icons.medical_services_outlined,
      text: 'ประวัติปรึกษา',
      isActive: _selectedTabIndex == _consultationTabIndex,
      activeColor: AppColors.primary,
      onTap: () => setState(() => _selectedTabIndex = _consultationTabIndex),
    ),
  ),

// ใน SliverList content:
if (_isConsumer && _selectedTabIndex == _consultationTabIndex)
  const MyConsultationsPage(isEmbedded: true),
```

---

#### สำหรับ **แพทย์/ผู้เชี่ยวชาญ (expert_profile)**

เพิ่ม Tab index ใหม่:

```
Tab: "ประวัติให้บริการ" (Icons.history_edu_outlined)
  → แสดงหน้า provider_history_page.dart
  → แสดงเมื่อ: user มี professionId ≠ null และไม่ใช่ consumer
  → ตำแหน่ง: แถบ Tab ใน profile ถัดจาก "จิตอาสา"
```

**ตัวอย่างโค้ด:**

```dart
if (_isProvider)
  SizedBox(
    width: MediaQuery.of(context).size.width / tabCount,
    child: _buildTabItem(
      icon: Icons.history_edu_outlined,
      text: 'ประวัติให้บริการ',
      isActive: _selectedTabIndex == _providerHistoryTabIndex,
      activeColor: Colors.indigo,
      onTap: () => setState(() => _selectedTabIndex = _providerHistoryTabIndex),
    ),
  ),

// ใน SliverList content:
if (_isProvider && _selectedTabIndex == _providerHistoryTabIndex)
  const ProviderHistoryPage(isEmbedded: true),
```

---

#### หน้า **บทสนทนาย้อนหลัง** (Read-Only)

```
ไม่ใช่ Tab แยก — เปิดผ่านปุ่ม [ดูบทสนทนา] ในแต่ละ card
  → Navigate ไปหน้า ConsultationChatHistoryPage
  → Route: /consultation-chat-history/:consultationId
  → ทั้งผู้ป่วยและแพทย์เจ้าของ consultation เปิดได้
  → Input bar ถูกซ่อน (Read-Only mode)
```

---

### สรุป Tab Layout ใหม่ทั้งหมด

#### ผู้ป่วย (Consumer)

```
[โปรไฟล์] [จิตอาสา] [ประวัติปรึกษา]
    0           1            2
```

#### แพทย์/ผู้เชี่ยวชาญ (Provider)

```
[โปรไฟล์] [จิตอาสา] [ประวัติให้บริการ]
    0           1             2
```

#### แพทย์ + อนุมัติบริจาค (Provider + Approver)

```
[โปรไฟล์] [จิตอาสา] [อนุมัติบริจาค] [ประวัติให้บริการ]
    0           1            2                  3
```

#### ผู้ป่วย + อนุมัติบริจาค (Consumer + Approver)

```
[โปรไฟล์] [จิตอาสา] [อนุมัติบริจาค] [ประวัติปรึกษา]
    0           1            2                3
```

---

### ไฟล์ที่ต้องแก้ไข

| ไฟล์ | การเปลี่ยนแปลง |
|---|---|
| `profile_page.dart` | เพิ่ม Tab + getter `_isConsumer` / `_isProvider` |
| `my_consultations_page.dart` | สร้างใหม่ — รองรับ `isEmbedded: true` (ไม่มี AppBar เมื่อ embed) |
| `provider_history_page.dart` | สร้างใหม่ — รองรับ `isEmbedded: true` |
| `consultation_chat_history_page.dart` | สร้างใหม่ — Read-Only chat viewer |
| `main.dart` | เพิ่ม route `/consultation-chat-history` |

---

> วิเคราะห์จากโค้ดจริงใน `/lib/features/chat/`, `/lib/features/consultation/`, และ `/lib/features/profile/`  
> ควร review กับทีมก่อน implement เพื่อ prioritize ตาม business needs
