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
| Unified Consultation Room | `chart_board_page.dart` | 🔄 รวมหน้า (Merging) |

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
❌ ~~Dismissible notifications ใช้ in-memory Set (`_dismissedConsultationIds`) → หายเมื่อรีเฟรช~~ ✅ **FIXED** — ดู Section 8: Best Practice
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
  title       TEXT,     -- อนุญาตให้เป็น null ได้ เนื่องจากหน้า UI ใช้แค่ content
  content     TEXT NOT NULL,
  category    TEXT DEFAULT 'general',
  -- 'greeting'|'follow_up'|'prescription'|'general'
  sort_order  INT DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Note: ปิดการใช้งาน RLS สำหรับตารางนี้ เนื่องจากโปรเจกต์ใช้ Custom Auth
-- ALTER TABLE doctor_quick_replies DISABLE ROW LEVEL SECURITY;
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
  → [ChartBoard (Unified Room)]      ← MERGED
      - [สรุปอาการ Body Map + เลือก Pain Level]
      - [ชำระเงิน / ยืนยันคำขอ]
      - [Waiting Room — ⏳ รอผู้เชี่ยวชาญเข้าร่วม]
      - [ห้องแชท + Session Timer]
  → [สรุปผลการปรึกษา (Medical Note)]  ← NEW
  → [ให้คะแนน & รีวิว]               ← NEW
  → [Follow-up Reminder]              ← NEW
```

### Flow 2: Doctor/Provider Journey (ปรับปรุง)

```
[Dashboard — คิวรอรับงาน]   ✅ มีแล้ว
  → [กด "รับงาน" (RPC)]
  → [เข้าสู่ ChartBoard (Unified Room)] ← NEW
      - [ดูข้อมูลผู้ป่วย + Body Map Summary]
      - [แชท + Session Timer]
      - [Quick Reply Templates]
      - [ออก Prescription / เขียน Medical Note]
  → [หากฉุกเฉิน → กด "สละสิทธิ์" เพื่อคืนโควต้าให้แพทย์อื่น]
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
1. **เริ่มนับเวลา:** เมื่อแพทย์/ผู้เชี่ยวชาญกดรับงาน **"ครบ"** ตามที่แพ็คเกจระบุ (Required Experts == Joined)
   - ❌ **ไม่ใช่** แพทย์เข้ามาแค่คนเดียวก็เริ่มนับ
   - ✅ **ต้อง** ผู้เชี่ยวชาญที่ `isRequired=true` **ทุกคน** ต้องมี `status='joined'`
2. **การล็อกห้อง:** เมื่อเวลาหมด (`session_minutes` เป็น 0) ระบบจะ **"ล็อกห้องแชทอัตโนมัติ"** ทันที ไม่ให้พิมพ์ต่อทั้งสองฝ่าย (บังคับจบ session) หรือล็อกเมื่อแพทย์กด "จบ Session" เอง

**การตรวจสอบก่อนเริ่มนับเวลา (ยึดเป็นหลัก):**

```dart
bool shouldStartTimer(List<Map<String, dynamic>> expertStatuses) {
  final requiredExperts = expertStatuses.where((e) => e['isRequired'] == true).toList();
  final allRequiredJoined = requiredExperts.isNotEmpty &&
      requiredExperts.every((e) => e['status'] == 'joined' || e['joinedAt'] != null);
  final anyJoined = expertStatuses.any((e) => e['status'] == 'joined' || e['joinedAt'] != null);

  // ✅ ถูกต้อง: รอ expert ครบก่อน ไม่ใช้ _roomStartedAt เป็นเงื่อนไข
  final shouldStart = allRequiredJoined || (requiredExperts.isEmpty && anyJoined);
  return shouldStart;
}
```

> **⚠️ สำคัญ: ห้ามใช้ `_roomStartedAt != null` เป็นเงื่อนไขเริ่มนับเวลา**
> 
> ❌ **ผิด:** `shouldStart = allRequiredJoined || _roomStartedAt != null`
> 
> ✅ **ถูก:** `shouldStart = allRequiredJoined || (requiredExperts.isEmpty && anyJoined)`
> 
> `_roomStartedAt` เป็น timestamp ที่บันทึกว่าห้องเคยเริ่มไปแล้ว แต่ไม่ใช่เงื่อนไขที่จะให้ timer เริ่มทั้งทีโดยไม่สน expert ครบหรือไม่ หากใช้ `_roomStartedAt` เป็นเงื่อนไข จะทำให้ timer เริ่มนับทันทีที่เปิดห้อง แม้ยังไม่มี expert เข้าร่วมครบ
>
> **Bug ที่พบและแก้ไขเพิ่มเติม:**
>
> | # | ที่ตั้ง | ปัญหา | การแก้ไข |
> |---|---|---|---|
> | 1 | Initial room data loading | เริ่ม timer เมื่อ `started_at != null` | ลบ `_startTimer()` ออก ให้เหลือแค่ set `_remainingSeconds` |
> | 2 | Room subscription stream | เริ่ม timer เมื่อ `started_at` เปลี่ยน | ลบ `_startTimer()` ออก ให้เหลือแค่ set `_remainingSeconds` |
> | 3 | Expert status stream | ใช้ `data` (raw DB) แทน `_expertStatuses` (merged) | เปลี่ยนไปใช้ `_expertStatuses` หลัง merge |
> | 4 | `_fetchExpertStatuses()` | ใช้ `mapped` (raw) แทน `_expertStatuses` (merged) | เปลี่ยนไปใช้ `_expertStatuses` หลัง merge |
> | 5 | `_mergeWithPackageGroups` | จับคู่ role ผิดพลาด (UUID vs Legacy string) ทำให้โชว์ชิปซ้ำซ้อน | ใช้ `findProfessionByNameOrRole` และดัก Keyword ภาษาไทยเพื่อเปรียบเทียบ Role ทั้งแบบ UUID และ Text ให้ตรงกัน |
> | 6 | `consultation_requests` Stream | ฝั่งผู้ป่วยไม่ยอมรีเฟรชหน้าจอเมื่อหมอกดรับงาน | เพิ่มเงื่อนไข `newStatus != oldStatus` เพื่อสั่ง `_fetchExpertStatuses` ทุกครั้งที่สถานะแชทเปลี่ยนเป็น `in_progress` |
> | 7 | `findProfessionByNameOrRole` | ไม่สามารถจับคู่อาชีพจากตารางใหม่ได้หากเป็นแพ็คเกจเก่า (Legacy) | เพิ่มตารางแมปคำ (Legacy Map) เช่น `'doctor'` -> `'แพทย์ทั่วไป'` เพื่อให้ดึง ID จาก DB ได้ถูกต้อง |
> | 8 | `ExpertStatusBanner` | แสดงชื่อชิปตามชื่อหน้ากลุ่ม (เช่น "หมอ") แทนที่จะเป็นชื่ออาชีพจริง | ปรับให้ดึง `prof.name` (เช่น "แพทย์ทั่วไป") มาแสดงเสมอ ทั้งตอนรอคนรับงานและตอนที่มีคนเข้าร่วมแล้ว |
>
> **เหตุผล:** `data` / `mapped` จาก `consultation_room_experts` มีเฉพาะ expert ที่เข้าร่วมแล้ว ไม่มี waiting groups จากแพ็คเกจ → ตรวจสอบ `isRequired` ไม่ครบ → timer เริ่มก่อน expert ครบ
>
> **Flow ที่ถูกต้อง (ยึดเป็นหลัก):**
>
> ```
> consultation_room_experts (DB) → map → _mergeWithPackageGroups → _expertStatuses
>                                               ↓
>                                         ตรวจ isRequired จาก _expertStatuses
>                                               ↓
>                                       ครบ → _startTimer()
>                                     ไม่ครบ → รอต่อ
> ```
>
> `consultation_room_experts` มีเฉพาะ expert ที่เข้าร่วมแล้ว (`joined`)
> `_mergeWithPackageGroups` รวม joined experts + waiting groups จากแพ็คเกจ → `_expertStatuses`
> ตรวจ `isRequired` จาก `_expertStatuses` จึงครบถ้วน (มีทั้ง joined + waiting)

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

> **⚠️ ข้อควรระวังสำคัญ (Custom Auth):** 
> โปรเจกต์นี้ไม่ได้ใช้ Supabase Auth แต่อย่างใด (`auth.uid()` จะมีค่าเป็น `null` เสมอ) และ Query จากแอปจะอยู่ในฐานะ `anon` role 
> **ห้ามสร้าง Policy ที่อ้างอิง `auth.uid()` หรือระบุ `TO authenticated`** เพราะจะทำให้เกิด Error 42501 Unauthorized 
> 
> **แนวทางปฏิบัติสำหรับตารางที่เกี่ยวข้องกับการแชทและประวัติแพทย์:**
> ให้ทำการปิดใช้งาน RLS สำหรับตารางเหล่านี้ และควบคุม Access Control + Data Filtering ที่ฝั่ง Application Layer (Flutter/Node.js) โดยใช้ข้อมูลจาก `ServiceLocator.instance.currentUser` แทน 

```sql
-- ปิด RLS เพื่อให้ client แบบ anon สามารถเข้าถึงข้อมูลของแชทได้ (จัดการกรองข้อมูลด้วย provider_id / patient_id ในแอป)
ALTER TABLE chat_room_members DISABLE ROW LEVEL SECURITY;
ALTER TABLE consultation_notes DISABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions DISABLE ROW LEVEL SECURITY;
ALTER TABLE consultation_reviews DISABLE ROW LEVEL SECURITY;
ALTER TABLE doctor_quick_replies DISABLE ROW LEVEL SECURITY;
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
- [ ] เพิ่ม `room_id` canonical mapping ใน `consultation_requests`
- [ ] ทำ `room upsert + participant merge` ทุกครั้งก่อนเปิดห้อง
- [ ] เพิ่ม `repair/backfill migration` สำหรับห้องเก่าที่สมาชิกไม่ครบ

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

### 🎨 UI: การ์ดคำปรึกษาบน Dashboard (Updated)

**การ์ดคำปรึกษาแบบใหม่สำหรับ Provider:**

```
┌─────────────────────────────────────────┐
│ 👤 อภิเศก ปัญญาคง          [ตรงกับคุณ]│
│    23 พ.ค. 2026 21:37                  │
│ ┌─────────────────────────────────────┐ │
│ │ 🌿 แพ็คเกจ: แพ็คเกจทั่วไป          │ │
│ │ 📍 บริเวณ: กรุงเทพ...               │ │
│ │ 💳 ราคา: 495 บาท                   │ │
│ └─────────────────────────────────────┘ │
│ [🩺 แพทย์]  ← chip จาก professions      │
│ [ดูรายละเอียด] [รับงานนี้]            │
└─────────────────────────────────────────┘
```

**องค์ประกอบของการ์ด:**

| ส่วน | รายละเอียด | แหล่งที่มา |
|---|---|---|
| **Badge มุมขวาบน** | `ตรงกับคุณ` (เขียว) / `ไม่ตรงอาชีพ` (เทา) / `งานของคุณ` (น้ำเงิน) | ตรวจ `_myPackageIds.contains(packageId)` |
| **Chip อาชีพ** | ไอคอน + ชื่อ + สี จาก `professions` table | `_professions` ที่โหลดจาก `ProfessionRepository` |
| **ปุ่มการกระทำ** | งานตรง → `[ดูรายละเอียด] [รับงานนี้]` / งานตัวเอง → `[เข้าห้องแชท]` | เงื่อนไข `_isMatching` |

**การโหลดข้อมูล professions:**

```dart
// ใน _init() โหลด professions พร้อมกับข้อมูลอื่น
await Future.wait([
  _userRepo.getAvailabilityStatus(user.id),
  if (_isProvider && user.professionId != null)
    _repo.getPackageIdsForProfession(user.professionId!),
  // โหลด professions สำหรับแสดง chip บนการ์ด
  ServiceLocator.instance.professionRepository
      .getAllProfessions()
      .then((profs) => _professions = profs),
]);
```

**การแสดง chip อาชีพ:**

```dart
Widget _buildProfessionChipRow(ConsultationEntry e) {
  final prof = _findProfessionForPackage(e.packageId);
  final isMatching = e.packageId != null && _myPackageIds.contains(e.packageId);

  if (isMatching && prof != null) {
    return Chip(
      avatar: Icon(_parseIconName(prof.iconName), 
                  color: _hexToColor(prof.colorHex)),
      label: Text(prof.name),
      backgroundColor: _hexToColor(prof.colorHex).withOpacity(0.1),
    );
  } else if (!isMatching) {
    return Chip(
      avatar: Icon(Icons.block, color: Colors.grey),
      label: Text('ไม่ตรงอาชีพคุณ'),
      backgroundColor: Colors.grey.shade100,
    );
  }
}
```

**การ์ดสถิติ (กดได้เพื่อกรอง):**

```dart
_statChip(
  'รอดำเนินการ', _pending, Icons.pending_outlined, AppColors.warning,
  onTap: () {
    setState(() => _filterStatus = 'pending');
    _applyFilter();
  },
  isActive: _filterStatus == 'pending',
);
```

**ปุ่มการกระทำแบบคู่ (สำหรับงานที่ตรง + pending):**

```dart
if (isMatching) {
  return Row(
    children: [
      Expanded(
        flex: 2,
        child: OutlinedButton(  // ดูรายละเอียด
          onPressed: () => _openChat(e),
          child: Text('ดูรายละเอียด'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 3,
        child: ElevatedButton(  // รับงาน
          onPressed: canJoin ? () => _joinRequest(e) : null,
          child: Text('รับงานนี้'),
        ),
      ),
    ],
  );
}
```

**⚠️ Edge Case: งานตรงแต่ถูกบล็อก (สำคัญ!)**

Badge `ตรงกับคุณ` อาจแสดงแม้ปุ่มถูกบล็อก เพราะ badge ดูจาก `packageId` แต่ปุ่มดูจาก `status`:

| เงื่อนไข | Badge | ปุ่ม | ข้อความ |
|---|---|---|---|
| `pending` + ตรง + ไม่มีคนรับ | `ตรงกับคุณ` | ✅ `[ดูรายละเอียด] [รับงานนี้]` | — |
| `in_progress` + ตรง + ไม่ใช่งานตัวเอง | `ตรงกับคุณ` | ❌ บล็อก | `ดำเนินการโดยผู้เชี่ยวชาญท่านอื่น` |
| `pending` + ตรง + มีคนรับแล้ว (`isBusy`) | `ตรงกับคุณ` | ❌ บล็อก | `มีผู้เชี่ยวชาญท่านอื่นรับแล้ว` |
| `pending` + ไม่ตรงอาชีพ | `ไม่ตรงอาชีพ` | ❌ บล็อก | `ไม่ตรงกับอาชีพของคุณ` |

**การจัดการข้อความบล็อก (else branch):**

```dart
String lockMessage;
IconData lockIcon = Icons.lock_outline_rounded;

if (e.status == 'in_progress') {
  lockMessage = 'ดำเนินการโดยผู้เชี่ยวชาญท่านอื่น';
  lockIcon = Icons.person_off_outlined;
} else if (isBusy) {
  lockMessage = 'มีผู้เชี่ยวชาญท่านอื่นรับแล้ว';
} else if (e.packageId != null && !_myPackageIds.contains(e.packageId)) {
  lockMessage = 'ไม่ตรงกับอาชีพของคุณ';
} else {
  lockMessage = 'ไม่สามารถดำเนินการได้';
}
```

**หลักการ:** Badge แสดง "โอกาส" (แพ็คเกจตรงอาชีพ) แต่ปุ่มแสดง "สิทธิ์" (status + availability) — ทั้งสองอย่างอิสระจากกัน ต้องไม่สรุปว่า badge เขียว = กดรับได้เสมอ

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

#### รูปโปรไฟล์และไอคอนผู้เชี่ยวชาญ

**แหล่งที่มาของไอคอนและสี:**

ไอคอนและสีของแต่ละกลุ่มผู้เชี่ยวชาญ **ไม่ใช่ hardcode** อีกต่อไป แต่ดึงมาจาก **`professions` table** (หน้าจัดการอาชีพ) โดยตรง:

| แหล่งที่มา | ตัวอย่าง |
|---|---|
| `professions.icon_name` | `medical_services`, `medication`, `psychology` |
| `professions.color_hex` | `#2196F3`, `#FF9800`, `#4CAF50` |
| Fallback (ไม่พบ profession) | `_iconNameFromRole()` + `_getDefaultIconForRole()` |

**กลไกการโหลด (Auto-Refresh):**

```dart
// 1. โหลด professions ทั้งหมดตอนเปิดหน้า
Future<void> _loadProfessions() async {
  final professions = await ServiceLocator.instance.professionRepository
      .getAllProfessions();
  setState(() => _professions = professions);
}

// 2. รีเฟรชทุก 30 วินาที
_professionsRefreshTimer = Timer.periodic(
  const Duration(seconds: 30), (_) => _loadProfessions());

// 3. รีโหลดเมื่อกลับมาหน้าแอป (background → foreground)
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) _loadProfessions();
}
```

**การค้นหา Profession ที่ตรงกับ Expert:**

```dart
Profession? _findProfessionByNameOrRole(String? name, String? role) {
  final searchTerms = {name?.toLowerCase(), role?.toLowerCase()};
  for (final prof in _professions) {
    if (searchTerms.any((term) =>
      prof.name.toLowerCase().contains(term) ||
      (prof.nameEn?.toLowerCase().contains(term) ?? false))) {
      return prof;
    }
  }
  return null;
}
```

**การแสดงรูปโปรไฟล์:**

| สถานะ | แสดงผล |
|---|---|
| `joined` + มี `providerAvatarUrl` | `CircleAvatar(radius: 12, backgroundImage: NetworkImage(...))` |
| `joined` + ไม่มี avatar | ไอคอนจาก `profession.iconName` + สีจาก `profession.colorHex` |
| `waiting` | ไอคอนจาก `profession.iconName` + สีเทา (แต่พื้นหลังต่างกันตาม `isRequired`) |

**Priority การเลือกแสดง Avatar vs Icon (Updated):**

```dart
// หา profession จาก admin settings
final prof = _findProfessionByNameOrRole(expert['name'], expert['role']);
final categoryIcon = _parseExpertGroupIcon(prof?.iconName ?? expert['expertGroupIcon'])
    ?? _getDefaultIconForRole(expert['role']);
final profColor = _hexToColor(prof?.colorHex); // null ถ้าไม่มีสี

if (isJoined && avatarUrl != null && avatarUrl.isNotEmpty)
  // แสดงรูปโปรไฟล์จริง
  CircleAvatar(radius: 12, backgroundImage: NetworkImage(avatarUrl))
else if (categoryIcon != null)
  // แสดงไอคอนจาก profession.iconName + สีจาก profession.colorHex
  Icon(categoryIcon, size: 20,
    color: isJoined ? (profColor ?? AppColors.primary) : (isRequired ? Colors.grey.shade600 : Colors.grey.shade400))
else
  // fallback icon
  Icon(isJoined ? Icons.check_circle : (isRequired ? Icons.priority_high : Icons.hourglass_empty))
```

**การดึงข้อมูลผู้เชี่ยวชาญ (3 ระดับ Fallback):**

```dart
// Level 1: ดึงจาก consultation_room_experts (ตารางที่ถูกต้องตามแผน)
await supabase.from('consultation_room_experts')
  .select().eq('consultation_id', consultationId);

// Level 2: fallback ไป chat_room_members + users (backward compatibility)
await supabase.from('chat_room_members')
  .select('user_id, role, joined_at, users!inner(first_name, last_name, profile_image_url)')
  .eq('room_id', roomId).eq('role', 'doctor');

// Level 3: fallback สุดท้าย — query users โดยใช้ provider_id จาก consultation_requests
// ⚠️ สำคัญ: ตาราง users มี columns: first_name, last_name, profile_image_url, profession_id
// ❌ ไม่มี: profession_role, user_type, payment_status
if (_consultationData?['provider_id'] != null) {
  final providerId = _consultationData!['provider_id'] as String;
  final user = await supabase.from('users')
    .select('first_name, last_name, profile_image_url, profession_id')
    .eq('id', providerId)
    .maybeSingle();

  if (user != null) {
    final firstName = user['first_name'] as String? ?? '';
    final lastName = user['last_name'] as String? ?? '';
    final name = '$firstName $lastName'.trim().isEmpty ? 'ผู้ให้คำปรึกษา' : '$firstName $lastName'.trim();
    mapped = [{
      'role': 'expert',  // hardcode — DB ไม่มี role column
      'name': name,
      'status': 'joined',
      'providerId': providerId,
      'isRequired': true,
      'joinedAt': _consultationData!['updated_at'],
      'providerAvatarUrl': user['profile_image_url'],
      'expertGroupIcon': null,
    }];
  }
}
```

> **⚠️ Warning: คอลัมน์ที่ไม่มีอยู่จริงใน `users` table**
> - `profession_role` → ไม่มี ❌
> - `user_type` → ไม่มี ❌  
> - `payment_status` (ใน `consultation_requests`) → ไม่มี ❌
> 
> ใช้ `profession_id` แทน `profession_role` และ hardcode `role: 'expert'`

**ไฟล์ที่เกี่ยวข้อง:**

| ไฟล์ | การเปลี่ยนแปลง |
|---|---|
| `chart_board_page.dart` | `_buildExpertStatusBanner()` widget `_fetchExpertStatuses()` 3-level fallback |
| | `_loadProfessions()` — โหลด professions จาก `professions` table |
| | `_findProfessionByNameOrRole()` — หา profession ตรงกับ expert name/role |
| | `_hexToColor()` — แปลง hex color → Flutter Color |
| | `WidgetsBindingObserver` + `Timer.periodic` — auto-refresh ทุก 30s |
| `health_program_request_dashboard.dart` | `_buildProfessionChipRow()` — แสดง chip อาชีพจาก professions |
| | `_findProfessionForPackage()` — หา profession ตรงกับ package |
| | `_parseIconName()` + `_hexToColor()` — แปลง icon/s.color จาก professions |
| | `_statChip()` — รองรับ `onTap` + `isActive` (กดกรองได้) |
| | `_buildActionRow()` — แสดง 2 ปุ่ม `[ดูรายละเอียด] [รับงานนี้]` |
| | Badge `ตรงกับคุณ` / `ไม่ตรงอาชีพ` บนการ์ด |
| `profession.dart` | Model `Profession` มี `iconName` + `colorHex` |
| `profession_repository.dart` | `getAllProfessions()` — ดึง professions ทั้งหมด |

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

**🎨 สีของสถานะ Waiting (Updated):**

ทั้ง `waiting + required` และ `waiting (ไม่ required)` ใช้ **สีเทาทั้งคู่** แต่แตกต่างเฉดกัน:

| สถานะ | พื้นหลัง | ขอบ | ไอคอน | ตัวอักษร | ตัวหนา |
|---|---|---|---|---|---|
| `waiting + required` | `grey.shade100` | `grey.shade300` | `grey.shade600` | `grey.shade700` | **bold** |
| `waiting (ไม่ required)` | `grey.shade50` | `grey.shade200` | `grey.shade400` | `grey.shade600` | normal |

- `required=true` → เฉดเทาเข้มขึ้น + ตัวหนา → บ่งบอกว่าเป็นกลุ่มจำเป็น
- `required=false` → เทาอ่อน + ตัวปกติ → กลุ่มเสริม มีหรือไม่มีก็ได้

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

### SQL: สร้าง/อัปเดต room ที่ผูกกับ consultation

**กฎสำคัญ:**

- ห้ามใช้ `insert-only` กับ consultation room
- `chat_rooms` ต้องถูก `upsert` ด้วย `consultation_id` เดียวกันเสมอ
- ต้อง merge `participant_ids` / `chat_room_members` ทุกครั้งที่ patient หรือ provider กลับเข้าห้อง
- ถ้าพบ room เก่าแต่สมาชิกไม่ครบ ให้ซ่อมด้วย migration/repair script แทนการสร้าง room ใหม่ทับ

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
  -- 1. สร้าง chat room ใหม่ถ้ายังไม่มี หรือเตรียมข้อมูลเพื่อ upsert
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

  -- 2. เพิ่มผู้ป่วยและแพทย์เป็น members (merge / idempotent)
  INSERT INTO chat_room_members (room_id, user_id, role)
  VALUES
    (v_room_id, p_patient_id,  'patient'),
    (v_room_id, p_provider_id, 'doctor');

  -- 3. อัปเดต consultation_requests ด้วย room_id
  UPDATE consultation_requests
  SET room_id = v_room_id,
      updated_at = now()
  WHERE id = p_consultation_id;

  -- 4. ทุกเส้นทางที่กลับเข้าห้องต้องเรียก ensure/upsert เดิมซ้ำได้
  --    เพื่อป้องกัน history หายเพราะ participant_ids ไม่ครบหรือ room ถูกสร้างแบบ partial

  RETURN v_room_id;
END;
$$ LANGUAGE plpgsql;
```

---

## ✅ บันทึกการแก้ไข: Pain Level UI + ช่องกรอกข้อความถูกล็อก

### ปัญหา
- ผู้ป่วยเข้าห้องแชทแล้วไม่มี UI เลือกระดับความเจ็บปวด (`_buildPainLevelSelector`)
- หลังเลือกระดับความเจ็บปวดและกด "ยืนยัน" ช่องกรอกข้อความยังคงถูกล็อกอยู่
- ปุ่ม "ยืนยันและส่งคำรักษา" ไม่แสดง

### Root Cause

**ปัญหาหลัก:** ใช้ `_isConsultationActive` flag เป็นตัวควบคุมการแสดง/ซ่อน UI แต่ flag นี้ถูกอัปเดตจากหลายจุด (`initState`, `_initChat`, `_submitConsultationRequest`) → เกิด race condition → UI ไม่สอดคล้องกับ state จริง

**ปัญหารอง:** พยายามใช้คอลัมน์ `payment_status` ใน `consultation_requests` แต่ **คอลัมน์นี้ไม่มีอยู่จริงใน DB schema** → เกิด `PostgrestException: Could not find the 'payment_status' column`

### วิธีแก้ไขที่ถูกต้อง

**หลักการ:** ใช้คอลัมน์ `status` ที่มีอยู่แล้วใน `consultation_requests` เป็นตัวควบคุม UI state ทั้งหมด:

| `status` | ความหมาย | Pain Selector | Payment Card | Chat Input |
|---|---|---|---|---|
| `pending` | ยังไม่ยืนยัน | ✅ แสดง | ✅ แสดง | 🔒 ล็อก |
| `in_progress` | ยืนยันแล้ว/กำลังดำเนินการ | ❌ ซ่อน | ❌ ซ่อน | 🔓 ปลดล็อก |
| `completed` | เสร็จสิ้น | ❌ ซ่อน | ❌ ซ่อน | 🔒 ล็อก |

**การ implement ที่ถูกต้องใน `chart_board_page.dart`:**

```dart
// ✅ ถูกต้อง: อ่าน status จาก _consultationData โดยตรง
// อย่าใช้ _isConsultationActive เป็น condition หลัก

// 1. Pain selector — แสดงเมื่อยังไม่ยืนยัน
if (!_isProvider && (_consultationData?['status'] ?? 'pending') == 'pending')
  _buildPainLevelSelector(),

// 2. Payment card — แสดงเมื่อยังไม่ยืนยัน
if (!_isProvider && (_consultationData?['status'] ?? 'pending') == 'pending')
  _buildPaymentCard(),

// 3. Chat input lock — ใช้ status แทน _isConsultationActive
Widget _buildChatInput() {
  final status = _consultationData?['status'] as String? ?? 'pending';
  final isChatActive = _isProvider || status == 'in_progress';
  return Stack(
    children: [
      Opacity(
        opacity: isChatActive ? 1.0 : 0.3,
        child: AbsorbPointer(
          absorbing: !isChatActive,
          child: Row(...),
        ),
      ),
      // Lock overlay
      if (!_isProvider && status == 'pending')
        Positioned.fill(child: ...),
    ],
  );
}
```

**การ submit ที่ถูกต้อง:**

```dart
// ✅ ถูกต้อง: อัปเดต status เป็น 'in_progress' พร้อมกับบันทึก pain_level
if (widget.entry != null) {
  // Update existing consultation
  await repo.updateRequest(consultationId, {
    'symptoms_chart': finalSymptomsChart,
    'status': 'in_progress',
  });
} else if (widget.request != null) {
  // Create new consultation (mark as active immediately)
  final newRequest = await repo.createRequest(
    userId: currentUserId,
    packageId: widget.request!.packageId ?? '',
    packageName: widget.request!.packageName ?? '',
    price: widget.request!.price ?? 0,
    bodyArea: widget.request!.bodyArea ?? {},
    symptomsChart: finalSymptomsChart,
    symptoms: widget.request!.symptoms ?? [],
    status: 'in_progress',  // ← สำคัญ!
  );
}

// อัปเดต local state ทันที ก่อน _initChat จะ re-fetch
setState(() {
  _isConsultationActive = true;
  if (_consultationData != null) {
    _consultationData!['status'] = 'in_progress';
  } else {
    _consultationData = <String, dynamic>{
      'id': consultationId,
      'status': 'in_progress',
    };
  }
});
```

**Repository update (`consultation_repository.dart`):**

```dart
Future<ConsultationRequestModel> createRequest({
  required String userId,
  // ...other params
  String? status,  // ← เพิ่ม parameter
}) async {
  final data = {
    // ...other fields
    'status': status ?? 'pending',
  };
  // ...insert logic
}
```

### สิ่งที่ห้ามทำ

```dart
// ❌ ห้ามใช้ _isConsultationActive เป็น condition หลัก
if (!_isProvider && !_isConsultationActive)  // ผิด!

// ❌ ห้ามอ้างอิง payment_status (ไม่มีใน DB)
_consultationData?['payment_status']  // ผิด!

// ❌ ห้าม set _isConsultationActive = true ใน initState
// ให้ _initChat อ่านจาก DB แล้วคำนวณเอง
```

### ไฟล์ที่เกี่ยวข้อง

| ไฟล์ | การเปลี่ยนแปลง |
|---|---|
| `chart_board_page.dart` | เปลี่ยน condition ทั้งหมดจาก `_isConsultationActive` / `payment_status` เป็น `status` |
| `consultation_repository.dart` | เพิ่ม `status` parameter ใน `createRequest()` |

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
- [x] สร้าง `ExpertGroupStatusBanner` Widget (`_buildExpertStatusBanner`) และใช้ Realtime Subscription คอยอัปเดต
- [x] เพิ่ม Chip อาชีพจาก `professions` table บนการ์ด Dashboard
- [x] เพิ่ม Badge `ตรงกับคุณ` / `ไม่ตรงอาชีพ` บนการ์ด Dashboard
- [x] ทำให้การ์ดสถิติกดได้เพื่อกรองรายการ
- [x] แสดงปุ่มคู่ `[ดูรายละเอียด] [รับงานนี้]` บนการ์ด
- [ ] สร้าง Session Timer Widget แสดงเวลาใน AppBar 
- [ ] อัปเดต Logic การล็อกห้องแชทเมื่อเวลาหมด (`session_minutes` = 0)
- [ ] เพิ่มปุ่ม "สละสิทธิ์" ให้แพทย์และจัดการคืนโควต้า

**จุดที่ต้องเทสต์ผ่าน (Test Checkpoints):**
- [ ] 🧪 ผู้ป่วยรอในห้องแชท → แพทย์กดรับงานปุ๊บ Banner เปลี่ยนเป็น ✅ ทันทีไม่ต้องรีเฟรช
- [ ] 🧪 แพทย์กด "สละสิทธิ์" → Banner เปลี่ยนกลับเป็น ⏳ และแพทย์คนอื่นสามารถกดรับแทนได้
- [ ] 🧪 เมื่อเวลาหมดหรือกดจบ Session → ช่องพิมพ์ข้อความต้องถูกล็อกทั้งสองฝ่าย

### Phase 3: PDPA & Medical Features (สัปดาห์ 3-4)
**งานที่ต้องทำ:**
- [x] สร้างระบบอัปโหลดรูป: บังคับใช้กล้อง (Camera Only) + Private Storage
- [x] ประทับลายน้ำด้วยวันที่ (รูปแบบไทย เช่น อ.07.มิย.69)
- [x] เชื่อมต่อ AI Face Blur ฝั่ง Client/Server เพื่อป้องกันรูปหลุด
- [x] สร้าง `consultation_notes`, `prescriptions` และ UI ที่เกี่ยวข้องในแชท (Card)
- [x] เพิ่ม Quick Reply Templates ให้แพทย์

**จุดที่ต้องเทสต์ผ่าน (Test Checkpoints):**
- [x] 🧪 กดไอคอนรูปภาพ → ไม่สามารถเลือกรูปจาก Gallery ได้ (บังคับถ่ายรูปใหม่เท่านั้น)
- [x] 🧪 ถ่ายรูปที่มีใบหน้า → AI เบลอหน้าให้อัตโนมัติและมีลายน้ำแปะทับรูปเมื่อส่ง
- [x] 🧪 แพทย์ส่งใบสั่งยา → ผู้ป่วยเห็นการ์ดใบสั่งยาแสดงขึ้นมาในแชท

### Phase 4: History & Auto-Refund (สัปดาห์ 5-6)
**งานที่ต้องทำ:**
- [x] สร้าง Tab ประวัติและหน้า `my_consultations_page.dart` ใน Profile ผู้ป่วย
- [x] สร้าง Tab ประวัติและหน้า `provider_history_page.dart` ใน Profile แพทย์
- [x] สร้างหน้า `consultation_chat_history_page.dart` สำหรับดูแชทย้อนหลัง (Read-Only)
- [x] สร้างระบบ Cron / Edge Function เพื่อยกเลิกและคืนเงินอัตโนมัติหากหมด `expire_minutes`

**จุดที่ต้องเทสต์ผ่าน (Test Checkpoints):**
- [x] 🧪 สร้าง Request แล้วไม่มีแพทย์รับงานจนหมดเวลา `expire_minutes` → สถานะเปลี่ยนเป็น "ยกเลิก" และระบบคืนเงิน
- [x] 🧪 กดดูประวัติแชทที่จบไปแล้วจากหน้า Profile → ต้องเป็น Read-Only ไม่มีช่องให้พิมพ์ส่งข้อความ

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

| ไฟล์ | การเปลี่ยนแปลง | สถานะ |
|---|---|---|
| `profile_page.dart` | เพิ่ม Tab + getter `_isConsumer` / `_isProvider` และระบบ Scrollbar | ✅ เสร็จสิ้น |
| `my_consultations_page.dart` | สร้างใหม่ — รองรับ `isEmbedded: true` (ไม่มี AppBar เมื่อ embed) | ✅ เสร็จสิ้น |
| `provider_history_page.dart` | สร้างใหม่ — รองรับ `isEmbedded: true` | ✅ เสร็จสิ้น |
| `consultation_chat_history_page.dart` | สร้างใหม่ — Read-Only chat viewer | ✅ เสร็จสิ้น |
| `main.dart` | เพิ่ม route สำหรับ History และ Read-Only Chat | ✅ เสร็จสิ้น |

---

✅ **โครงการ (CHAT CONSULTATION IMPROVEMENT) เสร็จสมบูรณ์ทุก Phase 1-4 แล้ว**

---

## 🔔 Phase 5: Head Sector Notification Integration (✅ เสร็จสมบูรณ์)

**หลักการ:** นำการแจ้งเตือนคำร้องขอคำปรึกษาใหม่ (New Consultation Requests) ไปแสดงผลใน `HomeHeaderSection` (มุมขวาบนของหน้า Home) เพื่อใช้พื้นที่ร่วมกับการแจ้งเตือนระบบอื่นๆ เช่น แจ้งเหตุฉุกเฉิน (Alerts), ระบบให้ทาง (Yield Way), และแจ้งเตือนทานยา

### 1. พฤติกรรมการแสดงผลและการโต้ตอบ (UX/UI Behaviors) - ✅ Implement แล้ว
- **การแจ้งเตือนแบบ Real-time:** แสดงรายการคำขอปรึกษาที่มีสถานะ `pending` ที่ตรงกับสายอาชีพ (Profession/Expert Group) ของผู้ให้บริการใน `HomeHeaderSection` ทันทีเมื่อมีคำร้องเข้ามาใหม่ (ผ่าน Supabase Stream)
- **การปัดเพื่อปฏิเสธ (Swipe to Dismiss):** ผู้ให้บริการปัดขวา/ซ้ายที่รายการแจ้งเตือน จะเป็นการนำรายการนั้นออกจาก UI ทันที (บันทึกลง Local State เพื่อไม่ให้แสดงผลซ้ำ)
- **แตะเพื่อนำทาง (Tap to Navigate):** กดที่การแจ้งเตือน นำทางผู้ใช้ไปยังหน้า `HealthProgramRequestDashboard` และระบบทำการ **Auto-focus** ไปยังการ์ดคำขออันนั้น พร้อม Animation Border สีเขียว
- **การหดกลับอัตโนมัติ (Auto-Resolve):** กรณีที่มีผู้เชี่ยวชาญคนอื่นกดรับงานในคำขอนั้นจนครบโควต้า (Status เปลี่ยนจาก `pending` เป็น `in_progress`) หรือระบบยกเลิก/หมดอายุ แจ้งเตือนใน Head Sector จะถูกลบออกอัตโนมัติ

### 2. ไฟล์ที่ได้รับการแก้ไขใน Phase 5

| ไฟล์ | การเปลี่ยนแปลง | สถานะ |
|---|---|---|
| `health_program_request_dashboard.dart` | เพิ่ม `initialFocusId`, `ScrollController`, ฟังก์ชัน Auto-scroll `_scrollToFocus()`, และ Highlight Animation ให้กับการ์ดเป้าหมาย | ✅ เสร็จสิ้น |
| `home_header_section.dart` | เพิ่ม Notification item ใหม่สำหรับ consultation (`consultationAlerts`), รองรับ Swipe to dismiss, และจัดเรียงแจ้งเตือนล่าสุดขึ้นบน | ✅ เสร็จสิ้น |
| `home_page.dart` | เพิ่ม State `_consultationAlerts`, ฟังก์ชัน Subscribe Supabase `_subscribeConsultationAlerts()` สำหรับ Provider, Handle การ Dismiss/Tap และส่งข้อมูลให้ Header | ✅ เสร็จสิ้น |

---

## 🏗️ Phase 6: Unified Consultation Room (ChartBoard) Integration (✅ เสร็จสมบูรณ์)

**หลักการ:** รวม (Merge) ฟีเจอร์ทั้งหมดของการปรึกษามาไว้ใน `ChartBoardPage` เพียงหน้าเดียว เพื่อความเป็นมืออาชีพและลดความซับซ้อนของ Navigation โดยครอบคลุมตั้งแต่ Pre-consultation จนถึงการจบงาน

### 1. เป้าหมายการรวมหน้า (Merging Goals)
- **Single Source of Truth:** ใช้ `ChartBoardPage` เป็นหน้าหลักแทน `ExpertChatRoomPage` สำหรับเคสปรึกษาแพทย์
- **Seamless Context:** แสดง Body Map, รายการอาการ, และระดับความเจ็บปวด (Pain Level) ร่วมกับหน้าแชท
- **Professional Tools:** ผสานเครื่องมือออกใบสั่งยา (Prescription) และสรุปผล (Summary) ไว้ใน Input Bar ของแพทย์

### 2. สถานะความสมบูรณ์ (Completion Status)

| ฟีเจอร์ | สถานะ | รายละเอียดการดำเนินงาน |
|---|---|---|
| **Session Timer** | ✅ สมบูรณ์ | เชื่อมต่อ `started_at` จาก DB และคำนวณเวลาที่เหลือจริงอัตโนมัติ |
| **Expert Status Banner** | ✅ สมบูรณ์ | ดึงสถานะจาก `consultation_room_experts` แบบ Real-time |
| **Body Map Summary** | ✅ สมบูรณ์ | แสดงผลจากข้อมูลใน `consultation_requests.body_area` |
| **Medical Tools** | ✅ สมบูรณ์ | เชื่อมต่อกับ `PrescriptionEditor` และ `ConsultationNoteEditor` แล้ว |
| **PDPA Privacy** | ✅ สมบูรณ์ | ระบบ Camera Only + Face Blur + Watermark อัตโนมัติ |
| **Video Call** | ✅ สมบูรณ์ | เชื่อมต่อกับระบบ `live_vdo_page.dart` โดยใช้ Room ID ของเซสชั่น |
| **Rating & Review** | ✅ สมบูรณ์ | ระบบให้คะแนนและบันทึกลงตาราง `consultation_reviews` หลังจบงานเรียบร้อย |
| **Auto-Close Logic** | ✅ สมบูรณ์ | ล็อกห้องแชทใน DB (is_active: false) ทันทีเมื่อหมดเวลา |
| **Provider Room Join** | ✅ สมบูรณ์ | `_ensureConsultationRoom()` อัปเดตและ append providerId เข้า `participant_ids` เมื่อแพทย์เข้าร่วมแชทเรียบร้อย |
| **Provider Availability Reset** | ✅ สมบูรณ์ | `_showFinishDialog()` คืน status เป็น `online` หลังแพทย์จบงานเรียบร้อย |

### 3. สิ่งที่ดำเนินการสำเร็จในเซสชั่นนี้
1. **Dynamic Expert Status:** ใช้ Stream สังเกตการณ์สถานะการเข้าร่วมของผู้เชี่ยวชาญทุกคนในห้อง
2. **Session Persistence:** ตรวจสอบสิทธิ์และสถานะการเริ่มเซสชั่นใน `initState` เพื่อกู้คืนสถานะที่ถูกต้อง
3. **Timer Start Mechanism:** อัปเดต RPC `assign_provider_to_group` ให้เริ่มนับเวลาเมื่อแพทย์คนแรกรับงาน
4. **End-to-End Closure:** ระบบปิดห้องอัตโนมัติพร้อมหน้าจอสรุปผลและให้คะแนนสำหรับผู้ป่วย

---

## 🛠️ Phase 6.1: ChartBoardPage Bug Fixes & Completion (🔄 กำลังดำเนินการ)

> **ที่มา:** ตรวจสอบเปรียบเทียบโค้ดระหว่าง `expert_chat_room_page.dart` (ต้นแบบ) กับ `chart_board_page.dart` (ปลายทาง) พบ 3 Bug หลัก และ 4 จุดปรับปรุง เรียงตามลำดับความสำคัญ

### ลำดับการแก้ไข (Priority Order)

---

#### 🔴 Fix #1 — Provider Availability Reset หลังจบงาน (Critical)
**ไฟล์:** `chart_board_page.dart` → `_showFinishDialog()`  
**ปัญหา:** เมื่อแพทย์กดปุ่ม "จบงาน" ระบบอัปเดตสถานะ consultation เป็น `completed` เท่านั้น **แต่ไม่ได้คืนสถานะ availability ของแพทย์** กลับเป็น `online` ทำให้แพทย์ค้างอยู่ใน `busy` state และรับงานใหม่ไม่ได้

**ผลกระทบ:** แพทย์ต้องออกจากระบบแล้วเข้าใหม่ หรือเปลี่ยนสถานะเองทุกครั้ง

**แนวทางแก้ไข:**
```dart
// _showFinishDialog() → onPressed ของปุ่ม "ยืนยัน"
final authUser = AuthService.instance.currentUser;
final consultationId = widget.entry?.id;
if (consultationId != null && authUser != null) {
  final repo = ServiceLocator.instance.consultationRepository;
  final userRepo = UserRepository(Supabase.instance.client);
  
  await repo.updateStatus(consultationId, 'completed');
  await userRepo.setAvailabilityStatus(authUser.id, 'online'); // ← เพิ่ม
  
  if (mounted) Navigator.pop(context);
}
```
**สถานะ:** - [x] เสร็จสิ้น (Fix #1 Completed)

---

#### 🔴 Fix #2 — ปุ่มส่งคะแนนใน ReviewCard ไม่ทำงาน (Critical)
**ไฟล์:** `chart_board_page.dart` → `_buildReviewCard()`  
**ปัญหา:** ปุ่ม "ส่งคะแนน" มี `onPressed: () {}` ว่างเปล่า ผู้ป่วยกดแล้วไม่มีผลใดๆ ทำให้ Review flow ที่วางแผนไว้ไม่ทำงานจริง

**แนวทางแก้ไข:** ผูก `onPressed` ให้เรียก `_showRatingDialog()` ซึ่งมีอยู่แล้วในไฟล์

```dart
// _buildReviewCard() → ElevatedButton
onPressed: _hasReviewed ? null : _showRatingDialog, // ← แก้จาก () {}
child: Text(_hasReviewed ? 'ให้คะแนนแล้ว ✓' : 'ส่งคะแนน'),
```
**สถานะ:** - [x] เสร็จสิ้น (Fix #2 Completed)

---

#### 🟡 Fix #3 — Provider ไม่ถูก append เข้า participant_ids เมื่อ Room มีอยู่แล้ว (High)
**ไฟล์:** `chart_board_page.dart` → `_ensureConsultationRoom()`  
**ปัญหา:** ใน `expert_chat_room_page.dart` เดิม มี logic ตรวจสอบว่า providerId อยู่ใน `participant_ids` หรือยัง ถ้าไม่มีจะ append เพิ่ม แต่ใน `ChartBoardPage` ทำเฉพาะกรณี room ยังไม่มี ทำให้แพทย์ที่เข้าห้องอาจไม่ได้อยู่ใน participant list และ Realtime subscription ที่กรองด้วย participant_ids อาจไม่ทำงาน

**แนวทางแก้ไข:** เพิ่ม logic ใน `_ensureConsultationRoom()` หลังจาก check ว่า room มีแล้ว:
```dart
// กรณี room มีอยู่แล้ว — ตรวจสอบและ append providerId
} else if (_isProvider) {
  final existing = await supabase
      .from('chat_rooms')
      .select('participant_ids')
      .eq('id', roomId)
      .maybeSingle();
  
  final participants = List<String>.from(existing?['participant_ids'] ?? []);
  if (!participants.contains(currentUserId)) {
    participants.add(currentUserId);
    await supabase.from('chat_rooms').update({
      'participant_ids': participants,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', roomId);
  }
}
```
**สถานะ:** - [x] เสร็จสิ้น (Fix #3 Completed)

---

#### 🟡 Fix #4 — Memory Leak: `_expertStatusSub` ไม่ถูก cancel ใน dispose() (Medium)
**ไฟล์:** `chart_board_page.dart` → `dispose()`  
**ปัญหา:** `_expertStatusSub` เปิด Stream subscription ไว้ใน `_initChat()` แต่ใน `dispose()` (บรรทัด 812-820) ไม่มีการ cancel ทำให้เกิด memory leak และ error `setState() called after dispose()`

**แนวทางแก้ไข:**
```dart
@override
void dispose() {
  _fadeController.dispose();
  _slideController.dispose();
  _msgController.dispose();
  _scrollController.dispose();
  _audioRecorder.dispose();
  _messagesSub?.cancel();
  _expertStatusSub?.cancel(); // ← เพิ่ม
  super.dispose();
}
```
**สถานะ:** - [ ] ยังไม่แก้ไข

---

#### 🟢 Fix #5 — `_initChat()` ถูกเรียก 2 ครั้งใน `initState()` (Low)
**ไฟล์:** `chart_board_page.dart` → `initState()` (บรรทัด 138-142)  
**ปัญหา:** `_initChat()` และ `_loadPackages()` ถูกเรียกซ้ำ 2 รอบ ทำให้มีการ query DB ซ้ำโดยไม่จำเป็น และอาจเกิด race condition ใน setState

**แนวทางแก้ไข:** ลบบรรทัดที่ซ้ำออก:
```dart
// initState() — คงไว้เพียงรอบเดียว
_initChat();      // ← คงไว้บรรทัด 138
_loadPackages();  // ← คงไว้บรรทัด 139
// ลบบรรทัด 141-142 ออก (ซ้ำกัน)
```
**สถานะ:** - [ ] ยังไม่แก้ไข

---

#### 🟢 Fix #6 — AppBar subtitle ข้อความ Role สลับกัน (Low)
**ไฟล์:** `chart_board_page.dart` → `build()` (บรรทัด 863)  
**ปัญหา:** `_isProvider ? "Patient Consultation" : "Expert Group"` — เมื่อเป็นแพทย์แสดง "Patient Consultation" แต่เมื่อเป็นผู้ป่วยกลับแสดง "Expert Group" ซึ่งสลับกัน

**แนวทางแก้ไข:**
```dart
// บรรทัด 863 — แก้ข้อความให้ถูก role
_isProvider ? "ห้องปรึกษา (มุมมองแพทย์)" : "กลุ่มผู้เชี่ยวชาญที่เข้าร่วม",
```
**สถานะ:** - [ ] ยังไม่แก้ไข

---

#### 🔵 Fix #7 — Quick Replies เป็น Hardcode ไม่ดึงจาก DB (Enhancement)
**ไฟล์:** `chart_board_page.dart` → `_showQuickReplies()`  
**ปัญหา:** รายการ Quick Reply ถูก hardcode ไว้ใน code แทนที่จะดึงจากตาราง `doctor_quick_replies` ตามที่ Schema กำหนดไว้ใน Phase 3 ทำให้แพทย์แต่ละคนใช้ template เดียวกันไม่สามารถปรับแต่งได้

**แนวทางแก้ไข:**
```dart
// _showQuickReplies() — ดึงจาก DB แทน
Future<void> _showQuickReplies() async {
  final providerId = _currentUser?.id;
  if (providerId == null) return;
  
  final data = await Supabase.instance.client
      .from('doctor_quick_replies')
      .select()
      .eq('provider_id', providerId)
      .order('sort_order');
  
  final templates = (data as List).map((e) => e['content'] as String).toList();
  // ถ้าไม่มี custom templates ให้ใช้ default
  if (templates.isEmpty) {
    templates.addAll([
      'สวัสดีครับ หมอรับเคสแล้วครับ',
      'กรุณาส่งรูปภาพบริเวณที่มีอาการครับ',
      'พบอาการมานานเท่าไรแล้วครับ?',
      'มีประวัติแพ้ยาอะไรไหมครับ?',
    ]);
  }
  // แสดง BottomSheet เหมือนเดิม...
}
```
**สถานะ:** - [x] เสร็จสิ้น (Fix #7 Completed)  
**หมายเหตุ:** ต้องสร้างตาราง `doctor_quick_replies` ใน DB ก่อน (Schema อยู่ใน Phase 3 ของแผนนี้)

---

### สรุปลำดับงาน Phase 6.1

| ลำดับ | Fix | ความสำคัญ | เวลาโดยประมาณ | สถานะ |
|---|---|---|---|---|
| 1 | Provider Availability Reset | 🔴 Critical | 10 นาที | ✅ เสร็จสิ้น |
| 2 | Review Card onPressed | 🔴 Critical | 5 นาที | ✅ เสร็จสิ้น |
| 3 | Provider Room Participant Append | 🟡 High | 15 นาที | ✅ เสร็จสิ้น |
| 4 | Memory Leak expertStatusSub | 🟡 Medium | 5 นาที | ✅ เสร็จสิ้น |
| 5 | initChat() Double Call | 🟢 Low | 2 นาที | ✅ เสร็จสิ้น |
| 6 | AppBar Subtitle Text | 🟢 Low | 2 นาที | ✅ เสร็จสิ้น |
| 7 | Quick Replies from DB | 🔵 Enhancement | 30 นาที | ✅ เสร็จสิ้น |

---

⚠️ **โครงการ CHAT CONSULTATION IMPROVEMENT (Phase 1-5) เสร็จสมบูรณ์ — Phase 6 มี 7 รายการที่ต้องแก้ไขเพิ่มเติม (Phase 6.1)**

---

## 🎨 Phase 6.2: UX/UI Improvement — Collapsible Chat Tools (ปรับปรุงช่องพิมพ์แชท)

### 📌 ปัญหาที่พบ (Problem)
ในหน้าห้องแชทของแพทย์ (`chart_board_page.dart`) แถบพิมพ์ข้อความด้านล่าง (Bottom Input Bar) มีปุ่มเครื่องมือสำหรับแพทย์มากถึง 4 ปุ่มวางเรียงกันในแนวนอน (รูปภาพ, ใบสั่งยา, สรุปผล, Quick Replies) 
สิ่งนี้ส่งผลให้ **ช่องสำหรับพิมพ์ข้อความ (Text Field) ถูกเบียดจนมีขนาดแคบมาก** ผู้เชี่ยวชาญพิมพ์และอ่านข้อความที่ตัวเองกำลังพิมพ์ได้ลำบาก (ดังภาพตัวอย่างที่พบว่าช่องกรอกเหลือพื้นที่เพียงแค่ "ถา...")

### 💡 แนวทางการออกแบบและแก้ไข (Proposed Solution)

เพื่อคืนพื้นที่ช่องกรอกข้อความให้กว้างที่สุด (Expandable Text Field) เสนอให้ปรับปรุง UI ดังนี้:

#### 1. เปลี่ยนโครงสร้าง Bottom Bar ใหม่
ยุบรวมปุ่มเครื่องมือพิเศษทั้งหมดซ่อนไว้ภายใต้ปุ่มเดียว (เช่น ปุ่มเครื่องหมายบวก `+` หรือไอคอนคลิปหนีบกระดาษ `📎`)
* **โครงสร้างใหม่ (ขณะพิมพ์):** `[ ➕ ] [ 💬 ช่องพิมพ์ข้อความที่กว้างขึ้น... ] [ 🎤 / ➤ ]`

#### 2. เลือกรูปแบบการแสดงผลเครื่องมือ (Tool Menu Options)

**ตัวเลือก A: Bottom Action Sheet (แนะนำ 🌟)**
* **พฤติกรรม:** เมื่อกดปุ่ม `+` จะมีเมนูเลื่อนขึ้นมาจากด้านล่างจอ (Modal Bottom Sheet)
* **ข้อดี:** ไม่เบียดบังความกว้างของช่องพิมพ์เลย, มีพื้นที่เหลือเฟือสำหรับใส่ข้อความกำกับไอคอน (Label) ทำให้แพทย์ใช้งานง่าย ไม่สับสนไอคอน
* **เมนูที่จะอยู่ใน Sheet:**
  * 🖼️ ส่งรูปภาพ (Gallery / Camera)
  * 💊 ออกใบสั่งยา (Prescription)
  * 📋 สรุปผลการรักษา (Medical Summary)
  * ⚡ ข้อความตอบด่วน (Quick Replies)

**ตัวเลือก B: Inline Expandable Toolbar (แถบสไลด์แนวนอน)**
* **พฤติกรรม:** เมื่อกดปุ่ม `+` ช่องพิมพ์ข้อความจะหดสั้นลง แล้วแถบไอคอน 4 ปุ่มจะสไลด์โชว์ออกมาทางซ้าย เมื่อกดหน้าจอหรือเริ่มพิมพ์ แถบเครื่องมือจะซ่อนกลับไปโดยอัตโนมัติ
* **ข้อดี:** ทำงานในพื้นที่เดิม (Inline) ไม่ต้องเด้ง Pop-up
* **ข้อเสีย:** แพทย์อาจเผลอกดผิดได้ง่ายถ้าไอคอนเล็ก และช่องพิมพ์จะสั้นลงชั่วคราวตอนที่เปิดแถบเครื่องมือ

### 🛠️ สิ่งที่ต้องแก้ไขในโค้ด (`chart_board_page.dart`)
1. แก้ไขฟังก์ชัน `_buildChatInput()`
2. สร้าง State ตัวแปรเพื่อจัดการการแสดงผลของ Toolbar (เช่น `bool _isToolMenuExpanded = false;`) หรือใช้ `showModalBottomSheet` สำหรับตัวเลือก A
3. ใช้ `Expanded` หุ้ม `TextField` เพื่อให้ช่องกรอกข้อความกินพื้นที่ที่เหลือทั้งหมดอย่างเต็มประสิทธิภาพ

---

## 📋 Phase 6.3: Health Data Permission Workflow

### 🎯 Goal
Enable doctors/expert users to request access to a patient’s health data and allow patients to grant or deny each data category individually, with **default allow** for a smooth experience.

### 🖼️ UI Mockup
![Health Data Permission Dialog](file:///Users/dave_macmini/.gemini/antigravity/brain/db70442c-bd2b-4838-b2c6-c99fc4c4409f/health_data_permission_dialog_1779343614147.png)

**Doctor side (ChartBoardPage)**
- A new icon button `Icons.lock_open` labeled **"ขอสิทธิ์ดูข้อมูลสุขภาพ"** appears next to the attachment menu button.
- Tapping it sends a permission request to the patient via a real‑time Supabase subscription.

**Patient side (ChartBoardPage)**
- A notification banner appears at the top of the chat: *"แพทย์ {doctorName} ขอสิทธิ์ดูข้อมูลสุขภาพ"* with a **"ดูรายละเอียด"** button.
- When the patient taps the button, a modal bottom‑sheet dialog (as shown in the mockup) opens, listing the following data categories with toggle switches (all **ON** by default):
  - ข้อมูลสุขภาพทั่วไป
  - ประวัติการรักษา
  - ผลการตรวจ
  - การใช้ยา
- The patient can turn any switch **OFF** to deny that specific category, then press **"ยอมให้"** (primary) or **"ปฏิเสธ"** (secondary).
- The dialog respects dark‑mode styling with teal accents and glass‑morphism effects.

### 📡 Data Flow
1. **Doctor** presses the request button → calls `HealthDataPermissionRepository.requestPermission(consultationId, doctorId)` which creates a row in `health_data_permission_requests` (status `pending`).
2. **Patient** receives a Supabase real‑time subscription on that table → shows the banner.
3. Patient’s response updates the row (`granted`, `denied`, and a JSON column `granted_fields`).
4. The chat screen reads the permission row:
   - If `granted`, the doctor can request the actual health data via RPC `fetch_patient_health_data(consultationId, fields)`. The RPC checks the `granted_fields` column before returning any data.
   - If `denied` or no row, the data request returns empty.

### 🗄️ Database Schema (Supabase)
```sql
CREATE TABLE health_data_permission_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id UUID REFERENCES consultation_requests(id) ON DELETE CASCADE,
  doctor_id UUID REFERENCES users(id) ON DELETE CASCADE,
  patient_id UUID REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending',   -- pending / granted / denied
  granted_fields JSONB DEFAULT '{"general":true,"history":true,"labs":true,"medications":true}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Row‑Level Security
CREATE POLICY "Doctor can request" ON health_data_permission_requests
  FOR INSERT USING (auth.uid() = doctor_id);
CREATE POLICY "Patient can respond" ON health_data_permission_requests
  FOR UPDATE USING (auth.uid() = patient_id);
```

### ⚙️ Implementation Steps
1. **Add button** in `chart_board_page.dart` for doctors.
2. **Create repository** `HealthDataPermissionRepository` with methods `requestPermission`, `respondPermission`, `streamPermission`.
3. **Subscribe** in patient’s `ChartBoardPage` to `health_data_permission_requests` filtered by `consultationId` and `patientId`.
4. **Build dialog** UI (reuse the mockup design) with `SwitchListTile` for each category.
5. **Handle defaults** – when the dialog opens all switches are `true`. If the patient never interacts, the request auto‑grants after a configurable timeout (e.g., 30 seconds).
6. **Secure RPC** that fetches health data, checking `granted_fields` before returning.
7. **Update documentation** in this plan and add unit‑tests for the repository.

### 🎨 Visual Guidelines
- Use the app’s primary teal (`#009688`) for active switches and primary buttons.
- Dark theme background: `Color(0xFF212121)` with glass‑morphism overlay (`rgba(255,255,255,0.12)`).
- Rounded corners (12 dp) and subtle elevation (4 dp) for the dialog.
- Typography: Google Font **'Kanit'** (Thai‑friendly) at 14 sp for titles, 12 sp for switches, 16 sp for the primary action.

### ✅ Acceptance Criteria
- Doctor sees request button and can send permission request.
- Patient receives real‑time banner, can open dialog, toggle categories, and confirm/deny.
- Permission row updates correctly and is persisted.
- Doctor can retrieve only the data categories the patient approved.
- All UI follows the visual guidelines above and works on both Android and iOS.

*Last Updated: 2026-05-21*

---

## ⚠️ Phase 6.4: Dashboard Pagination, Lazy Loading & UX Refinements (✅ เสร็จสิ้น — Last Updated: 2026-05-24 20:03)

### 🚨 ปัญหาที่พบ

ปัจจุบัน Dashboard (`health_program_request_dashboard.dart`) **ไม่มี pagination** — โหลดข้อมูลทั้งหมดจาก DB ในครั้งเดียว:

| Method | มี `.limit()`? | ผลกระทบ |
|---|---|---|
| `ConsultationRepository.getAllRequestsWithUserInfo()` | ❌ ไม่มี | โหลดทุกแถวในตาราง |
| `ConsultationRepository.getRequestsForProfession()` | ❌ ไม่มี | โหลดทุกแถวที่ตรง package |
| `_HealthProgramRequestDashboardState._loadData()` | ❌ ไม่มี | เก็บทั้งหมดใน `_all` |

**ผลกระทบ:**
- ถ้ามี 1,000+ คำปรึกษา → โหลดช้า + Memory บวม
- `_applyFilter()` กรองใน memory → ไม่ช่วยลดข้อมูลจาก DB
- `ListView.builder` ช่วยเรื่อง render ได้ แต่ **ไม่ช่วยเรื่องโหลดข้อมูล**

### 🎯 แนวทางแก้ไข: Per-Tab Pagination (โหลดทีละ 15 การ์ดต่อแถบ)

**หลักการสำคัญ:** แต่ละ tab (`all`/`pending`/`in_progress`/`completed`) โหลดข้อมูลอิสระจากกัน โดยกรอง status ที่ฝั่ง DB:

```dart
// Repository: กรอง status + pagination ที่ DB
Future<List<Map<String, dynamic>>> getRequestsByStatus({
  String? status,  // null = 'all'
  int page = 0,
  int pageSize = 15,
}) async {
  var query = _client.from('consultation_requests').select('...');

  if (status != null && status != 'all') {
    query = query.eq('status', status);  // ← กรองที่ DB
  }

  return await query
      .order('created_at', ascending: false)
      .range(page * pageSize, (page + 1) * pageSize - 1)
      .timeout(Duration(seconds: 10));
}
```

```dart
// Dashboard: State แยกตามแต่ละ tab
final Map<String, int> _pageByTab = {
  'all': 0, 'pending': 0, 'in_progress': 0, 'completed': 0
};
final Map<String, bool> _hasMoreByTab = {
  'all': true, 'pending': true, 'in_progress': true, 'completed': true
};
final Map<String, List<ConsultationEntry>> _entriesByTab = {};

// โหลดเฉพาะ tab ที่เลือก
Future<void> _loadTab(String tab, {bool refresh = false}) async {
  if (refresh) {
    _pageByTab[tab] = 0;
    _hasMoreByTab[tab] = true;
    _entriesByTab[tab] = [];
  }

  final page = _pageByTab[tab]!;
  final raw = await _repo.getRequestsByStatus(
    status: tab == 'all' ? null : tab,
    page: page,
    pageSize: 15,
  );

  if (raw.length < 15) _hasMoreByTab[tab] = false;

  final entries = raw.map(ConsultationEntry.fromMap).toList();
  _entriesByTab[tab] = [...?_entriesByTab[tab], ...entries];
  _pageByTab[tab] = page + 1;
}

// Scroll listener → load more เฉพาะ tab ปัจจุบัน
void _onScroll() {
  if (_scrollController.position.pixels >=
      _scrollController.position.maxScrollExtent - 200) {
    final tab = _filterStatus;
    if (!_isLoading && _hasMoreByTab[tab]!) {
      _loadTab(tab);
    }
  }
}
```

### 📊 เปรียบเทียบก่อน-หลัง

| สถานการณ์ | ก่อน (โหลดทั้งหมด) | หลัง (Per-Tab) |
|---|---|---|
| กด tab "เสร็จสิ้น" | โหลดทุก status มาก่อน แล้ว filter ใน memory | โหลดเฉพาะ `status='completed'` 15 รายการ |
| มี 1,000 รายการ | โหลด 1,000 แถว → ช้า + หน่วยความจำสูง | โหลด 15 แถว → เร็ว + หน่วยความจำต่ำ |
| Scroll ลงไป | ไม่มีอะไรโหลดเพิ่ม (มีหมดแล้ว) | Load more 15 รายการถัดไป |

### 📝 ตารางการเปลี่ยนแปลงที่ต้องทำ

| ไฟล์ | การเปลี่ยนแปลง |
|---|---|
| `consultation_repository.dart` | ✅ **เพิ่ม** `getRequestsByStatus()` — รองรับ `status` + `page` + `pageSize=15` |
| | ✅ ใช้ `.eq('status', ...)` กรองที่ DB + `.range()` แบ่งหน้า |
| | ✅ **เพิ่ม** `getStatusCounts()` — นับจำนวนต่อ status สำหรับ stat chips |
| `health_program_request_dashboard.dart` | ✅ แก้ `_all` / `_filtered` → `_entriesByTab` (Map แยกตาม tab) |
| | ✅ แก้ `_filterStatus` → `_activeTab` (string key) |
| | ✅ เพิ่ม `_pageByTab` / `_hasMoreByTab` (Map แยกตาม tab) |
| | ✅ เพิ่ม `_scrollController` + `_onScroll()` listener |
| | ✅ แก้ `_loadData()` → `_loadTab(tab)` โหลดเฉพาะ tab |
| | ✅ แก้ `_applyFilter()` → `_getFilteredEntries()` กรอง search ใน tab |
| | ✅ แก้ `_statChip()` onTap → `_switchTab()` |
| | ✅ แก้ `_buildBody()` → แสดง `_entriesByTab[_activeTab]` + loading indicator |
| | ✅ แก้ `RefreshIndicator` → `_loadTab(tab, refresh: true)` + `_loadCounts()` |
| | ✅ **Default tab = `pending`** — เปิด Dashboard มาที่แถบ "รอดำเนินการ" |
| | ✅ **Pin My Jobs** — แถบ `in_progress` เรียงงานของตัวเอง (`provider_id == myId`) ขึ้นด้านบน |
| `chart_board_page.dart` | ✅ **เพิ่ม** `readOnly` parameter — โหมดดูอย่างเดียว ป้องกันการดำเนินการ |
| | ✅ **เพิ่ม** `_hasSubmitted` flag + `PopScope` — หลังส่งคำรักษา back ไปหน้า profile/ประวัติปรึกษา |
| `main.dart` | ✅ **แก้** route `/chart-board` รองรับ `Map<String, dynamic>` arguments (`entry`, `readOnly`) |
| | ✅ **เพิ่ม** `navigatorObservers: [dashboardRouteObserver]` สำหรับ `RouteAware` |
| `presence_service.dart` | ✅ **`await` → `unawaited()`** ใน `start()` — `setAvailabilityStatus()` + `_sendHeartbeat()` ไม่ block |
| `auth_service.dart` | ✅ **`await` → `unawaited()`** ใน `login()` — ไม่รอ `PresenceService.start()` ก่อน navigate |
| `user_repository.dart` | ✅ **`login()`** รัน username + phone queries ขนานกัน (`Future.wait`) พร้อม `.timeout(8s)` |
| `package_healthcare_page.dart` | ✅ **แยก** `_isPackagesLoading` จาก `_isLoading` — provider redirect ทันที ไม่รอ packages |
| `health_program_request_dashboard.dart` | ✅ **เพิ่ม** `TlzBottomNavigationBar` — นำ navigation bar ส่วนกลางมาใช้ในหน้า Dashboard |
| | ✅ **`extendBody: true`** + `NotificationListener<ScrollNotification>` — auto-hide nav bar ตอน scroll |
| | ✅ **เพิ่ม** `bottomNavigationBar: TlzBottomNavigationBar(...)` พร้อม `currentIndex: 0` (Home) |
| | ✅ **แก้** `ListView.builder` padding bottom `24 → 120` — กัน content ถูก bottom nav ทับ |
| `consultation_repository.dart` | ✅ **เพิ่ม** `dismissed_by_provider_ids` filter ใน `getAllRequestsWithUserInfo()` และ `getRequestsForProfession()` |
| | ✅ **เพิ่ม** `dismissRequestForProvider()` — append provider ID เข้า array ใน Supabase |
| `home_page.dart` | ✅ **แก้** `_onConsultationAlertDismissed` → เรียก `repo.dismissRequestForProvider()` บันทึกลง DB |
| | ✅ **ลบ** `_dismissedConsultationIds` Set — ไม่ต้องเก็บ local อีกต่อไป |
| | ✅ **แก้** `_subscribeConsultationAlerts` → ส่ง `excludeProviderId: user.id` ไปกรองที่ฝั่ง DB |
| `supabase_consultation_schema.sql` | ✅ **เพิ่ม** `dismissed_by_provider_ids UUID[] DEFAULT '{}'` ใน `consultation_requests` |

### 🎨 UX Refinements ที่เพิ่มเติม

#### 1️⃣ Default Tab: "รอดำเนินการ"
- เปลี่ยน `_activeTab` เริ่มต้นจาก `'all'` → `'pending'`
- Provider เข้ามาจะเห็นงานที่รอดำเนินการทันที ไม่ต้องสลับ tab

#### 2️⃣ Pin My Jobs ในแถบ "กำลังดำเนินการ"
- `_getFilteredEntries()` ตรวจสอบ `_activeTab == 'in_progress'`
- งานที่ `provider_id == _currentUser.id` (`isMyJob`) → ขึ้นด้านบนสุด
- ภายในกลุ่มเดียวกัน → เรียงตาม `requestedAt` (ใหม่ → เก่า)

#### 3️⃣ Read-Only Preview Mode (ปุ่ม "ดูรายละเอียด")
- กด "ดูรายละเอียด" → เปิด `ChartBoardPage(readOnly: true)`
- Overlay สีเทาบังช่อง input พร้อมข้อความ "โหมดดูอย่างเดียว — กดรับงานเพื่อเข้าร่วม"
- ซ่อนปุ่ม "จบงาน" และ "วิดีโอคอล" ใน action bar
- แสดง subtitle "ห้องปรึกษา (โหมดดูอย่างเดียว)" ใน AppBar
- ซ่อน Health Data Permission Banner (provider ไม่ควรขอข้อมูลขณะ preview)
- ผู้ใช้ยังดูข้อความแชท, ดูสถานะผู้เชี่ยวชาญ, และดูรายละเอียดผู้ป่วยได้ตามปกติ

#### 4️⃣ Auto-Refresh: App Lifecycle + Route Observer
เดิม Dashboard มีเฉพาะ Real-time Stream (`_subscribeToChanges`) ที่รีเฟรชอัตโนมัติ เพิ่มอีก 2 กลไก:

**App Lifecycle Observer (`WidgetsBindingObserver`)**
- จับ `AppLifecycleState.resumed` (แอปกลับมาจาก background)
- ทำงาน: `_loadCounts()` + `_loadTab(_activeTab, refresh: true)`
- ตัวอย่างสถานการณ์: User กด Home → เปิด Facebook → กลับมาแอปเรา → ข้อมูลรีเฟรชทันที

**Route Observer (`RouteAware`)**
- จับ `didPopNext()` (navigate กลับมาหน้า dashboard จากหน้าอื่น)
- ทำงาน: `_loadCounts()` + `_loadTab(_activeTab, refresh: true)`
- ตัวอย่างสถานการณ์: กด "รับงาน" → เข้าห้องแชท → กด Back → Dashboard รีเฟรชทันที

| กลไกรีเฟรช | ทำงานตอนไหน | ประเภท |
|---|---|---|
| Real-time Stream | DB เปลี่ยน | Auto (always on) |
| App Lifecycle Observer | กลับจาก background | Auto |
| Route Observer | กลับจากหน้าอื่น | Auto |
| Pull-to-Refresh | User swipe ลง | Manual |
| ปุ่ม Refresh | User กด icon | Manual |

#### 5️⃣ Back Button Navigation After Submit (Chart Board)
**ปัญหา:** หลังผู้ป่วยกด "ยืนยันและส่งคำรักษา" ใน `ChartBoardPage` หากกดปุ่มย้อนกลับ (ระบบหรือ AppBar) จะกลับไปหน้า `analyze-body` ซึ่งไม่สมเหตุสมผล — ควรไปหน้า **ประวัติปรึกษา** ในโปรไฟล์แทน

**แก้ไข:**
- เพิ่ม `_hasSubmitted` flag (bool) ใน `_ChartBoardPageState`
- ตอน `_submitConsultationRequest()` สำเร็จ → `_hasSubmitted = true`
- Wrap `build()` ด้วย `PopScope(canPop: !_hasSubmitted)` + `onPopInvokedWithResult`
- แก้ AppBar leading back button → ถ้า `_hasSubmitted` ให้ `pushNamedAndRemoveUntil('/profile', ...)` พร้อม `arguments: {'tabIndex': 2}`

**ผลลัพธ์:**
| สถานะ | กด Back → |
|---|---|
| ยังไม่กด "ยืนยัน" (chat ล็อกอยู่) | กลับไปหน้า `analyze-body` ปกติ |
| กด "ยืนยัน" แล้ว | ไปหน้า `/profile` แถบ "ประวัติปรึกษา" |

#### 6️⃣ Fix Login Flow Hang (Spinner ค้างหลังกดเข้าสู่ระบบ)
**ปัญหา:** หลัง user กดปุ่มเข้าสู่ระบบจากหน้า Login → ปุ่ม/หน้า "ค้าง" ที่ `CircularProgressIndicator` เนื่องจาก async operation บล็อก thread

**จุดที่ 1: `PresenceService.start()` บล็อก `AuthService.login()`**
- `AuthService.login()` → `await PresenceService.instance.start(user.id)`
- `PresenceService.start()` → `await repo.setAvailabilityStatus(...)` + `await _sendHeartbeat()`
- 2 DB writes ติดกัน ไม่มี timeout → ถ้าเน็ตช้า/สัญญาณหลุด → Future ไม่ complete → `_isLoading` ค้าง → ปุ่ม Login หมุนตลอด

**แก้ไข (Round 1):**
- เปลี่ยน `await` → `unawaited()` ใน `PresenceService.start()` สำหรับ `setAvailabilityStatus()` และ `_sendHeartbeat()`
- แต่ยังไม่พอ! `AuthService.login()` ยัง `await PresenceService.instance.start()` อยู่

**จุดที่ 2: `AuthService.login()` ยัง `await` อยู่แม้ข้างในเป็น fire-and-forget**
- แก้ข้างใน `PresenceService.start()` แต่ caller ยัง `await` → ยังรอ Future complete

**แก้ไข (Round 2):**
- `AuthService.login()` → `unawaited(PresenceService.instance.start(user.id))`
- ทำให้ login flow ไม่รอ heartbeat อัปเดต last_seen_at ก่อน navigate

**จุดที่ 3: `UserRepository.login()` มี sequential DB queries ไม่มี timeout**
- Query 1: find by username (ไม่มี timeout)
- Query 2: find by phone (รอ query 1 ล้มเหลวก่อน)
- Query 3: user_group_roles (มี timeout แค่ตัวนี้)
- ถ้า DB ช้า/เน็ตหลุด → query 1 ค้าง → `_isLoading` ค้าง → spinner หมุนตลอด

**แก้ไข:**
- Query 1 + Query 2 → รันขนานกันด้วย `Future.wait()` พร้อม `.timeout(Duration(seconds: 8))`
- Query 3 → คง timeout 5 วินาที
- เพิ่ม `on TimeoutException catch` → return null ไม่ให้ค้าง

**จุดที่ 4: `PackageHealthCarePage` บล็อก UI ด้วย `_isLoading`**
- `_isLoading = true` ตั้งแต่ initState → build แสดง full-page `CircularProgressIndicator`
- Provider check (เร็ว) + `_loadLivePackages()` (ช้า) อยู่ใน post-frame callback เดียวกัน → provider ที่ควร redirect ทันที อาจช้าไปด้วย
- Consumer ต้องรอ packages โหลดก่อนถึงเห็น UI

**แก้ไข:**
- แยก `_isLoading` (auth/profession check เร็ว) ออกจาก `_isPackagesLoading` (package load)
- หลัง provider check → `setState(() => _isLoading = false)` ทันที → provider redirect ไม่เห็น spinner
- `_loadLivePackages()` ทำงานใน background พร้อม `_isPackagesLoading` flag
- build: empty packages + loading → แสดง spinner แต่เฉพาะช่วงโหลด packages (สั้นกว่าเดิมมาก)

**ผลลัพธ์:**
| กลุ่มผู้ใช้ | ก่อนแก้ | หลังแก้ |
|---|---|---|
| Provider | อาจค้างที่ spinner ถ้า DB ช้า | Redirect ไป Dashboard ทันที ไม่เห็น spinner |
| Consumer ไม่มี health info | อาจค้างที่ spinner | Redirect ไป `/health-data-entry` เร็วขึ้น |
| Consumer มี health info | ค้างรอ packages + auth + presence | รอเฉพาะ packages (สั้นลง) |
| ทุกกลุ่ม (เน็ตช้า/DB timeout) | Spinner หมุนตลอดไม่มี timeout | Timeout 8 วิ → แสดง error → ไม่ค้าง |

**ไฟล์ที่แก้:**
| ไฟล์ | การเปลี่ยนแปลง |
|---|---|
| `presence_service.dart` | `await` → `unawaited()` ใน `start()` — `setAvailabilityStatus()` และ `_sendHeartbeat()` ไม่ block |
| `auth_service.dart` | `await PresenceService.start()` → `unawaited(PresenceService.start())` — login flow ไม่รอ heartbeat |
| `user_repository.dart` | `login()` รัน username + phone queries ขนานกัน (`Future.wait`) พร้อม `.timeout(8s)` — ป้องกัน DB hang |
| `login_page.dart` | **ลบ** `await Future.delayed(500ms)` หลัง login สำเร็จ — ลด latency นำทาง |
| | **เพิ่ม** `debugPrint` + `try-catch` ใน `addPostFrameCallback` navigation — trace + ป้องกัน navigation fail เงียบ |
| `package_healthcare_page.dart` | แยก `_isPackagesLoading` จาก `_isLoading`, provider check จบก่อน load packages |

**แก้ไข (Round 3) — ปัญหาค้างหลังสลับ user (logout → login):**

**ปัญหา:** หลัง logout แล้ว login ใหม่ → login ผ่านแต่ spinner ยังค้าง → ไม่ navigate

**จุดที่ 5: `_onAuthChanged` ใน `HomePage` ยังเรียก `setState()` หลัง logout**
- `HomePage` ฟัง `AuthService.instance.addListener(_onAuthChanged)`
- หลัง logout → `_onAuthChanged` ตรวจ `userId == null` → เรียก `setState(() => _consultationAlerts.clear())`
- ถ้า `HomePage` ถูก dispose (เพราะ navigate ไป LoginPage) → `setState()` บน widget ที่ถูก dispose → Exception → `_onAuthChanged` อาจค้าง หรือ state ไม่สะอาด

**แก้ไข:**
- `home_page.dart` → `_onAuthChanged` logout branch: เพิ่ม `if (mounted)` ก่อน `setState()`
- `home_page.dart` → `dispose()`: ลบ `_scrollController.dispose()` ซ้ำ (เรียก 2 ครั้ง → error)

**จุดที่ 6: `_showSnackBar` เรียกบน widget ที่ถูก dispose ได้**
- หลัง `AuthService.login()` → `_showSnackBar('เข้าสู่ระบบสำเร็จ')`
- ถ้า `addPostFrameCallback` ทำงานช้า / หน้า navigate ไปแล้ว → `setState()` ใน `_showSnackBar` อาจ crash

**แก้ไข:**
- `login_page.dart` → ห่อ `_showSnackBar` ด้วย `if (mounted)` ทั้งใน `_handleLogin()` และ `_handleSocialLogin()`

**จุดที่ 7: `PresenceService.stop()` อาจค้างถ้า DB ช้าตอน logout**
- `logout()` → `await PresenceService.instance.stop()` → `await repo.setAvailabilityStatus(userId, 'offline')`
- ไม่มี timeout → logout ค้าง → user ไม่กลับไป LoginPage

**แก้ไข:**
- `presence_service.dart` → `stop()`: `.timeout(Duration(seconds: 5))` บน `setAvailabilityStatus()` พร้อม `on TimeoutException catch`

**ไฟล์ที่แก้ (Round 3):**
| ไฟล์ | การเปลี่ยนแปลง |
|---|---|
| `home_page.dart` | `_onAuthChanged` logout branch: `if (mounted)` ก่อน `setState()`; `dispose()`: ลบ `_scrollController.dispose()` ซ้ำ |
| `login_page.dart` | `_showSnackBar` ห่อด้วย `if (mounted)` ทั้ง `_handleLogin` และ `_handleSocialLogin` |
| `presence_service.dart` | `stop()`: `setAvailabilityStatus().timeout(5s)` + `on TimeoutException catch` — ป้องกัน logout ค้าง |

**แก้ไข (Round 4) — เพิ่ม timeout + debug trace ใน login flow:**

**แก้ไข:**
- `login_page.dart` → `_handleLogin()` และ `_handleSocialLogin()`:
  - ห่อ `AuthService.instance.login(user)` ด้วย `.timeout(Duration(seconds: 3))` พร้อม `onTimeout`
  - เพิ่ม `debugPrint` ทุกขั้นตอน (ก่อน/หลัง `_userRepository.login()`, `AuthService.login()`, `_isLoading = false`, navigation)
  - `addPostFrameCallback` ห่อ `try-catch` + `debugPrint` ถ้า navigation throw exception

**ผลลัพธ์รวม (Round 1-4):**
| สถานการณ์ | ก่อนแก้ | หลังแก้ |
|---|---|---|
| เน็ตช้า/DB timeout ตอน login | Spinner หมุนตลอด | Timeout 8 วิ → return null → แสดง error → ไม่ค้าง |
| เน็ตช้า/DB timeout ตอน logout | Logout ค้างไม่กลับไป Login | Timeout 5 วิ → skip → navigate ปกติ |
| สลับ user (logout → login) | Spinner ค้าง ไม่ navigate | ไม่ค้าง; navigation ทำงาน; ไม่มี setState บน disposed widget |
| `AuthService.login()` ช้า/timeout | Login ค้าง | Timeout 3 วิ → proceed anyway + debugPrint |
| Navigation throw exception | เงียบ fail → ไม่ไปหน้าอื่น | catch + debugPrint → trace ได้ |

**สรุปรายการ debugPrint ที่ควรเห็นใน console ตอน login สำเร็จ:**
```
LoginPage: calling _userRepository.login()
LoginPage: _userRepository.login() returned user=true
LoginPage: calling AuthService.instance.login()
LoginPage: AuthService.instance.login() completed
LoginPage: _isLoading set to false
LoginPage: scheduling navigation
LoginPage: navigating to /
```

#### 7️⃣ Fix Consultation Alert Dismiss Persist (ปัดทิ้งแล้วกลับมาอีก)
**ปัญหา:** Provider ปัดการ์ดคำขอปรึกษาทิ้งใน Home header → รีเฟรชหน้า Home → การ์ดกลับมาแสดงอีก

**ต้นเหตุ:** `_dismissedConsultationIds` เป็น `Set<String>` ธรรมดาใน widget state → ไม่ persist → รีเฟรชหน้า = state ใหม่ = Set ว่าง → การ์ดกลับมา

**แก้ไข:**
1. **Supabase Schema** — เพิ่ม `dismissed_by_provider_ids UUID[] DEFAULT '{}'` ใน `consultation_requests`
2. **Repository** — เพิ่ม `dismissRequestForProvider()` ที่ fetch current array → append provider ID → update row
3. **Repository queries** — `getAllRequestsWithUserInfo()` และ `getRequestsForProfession()` รับ `excludeProviderId` → ใช้ `.not('dismissed_by_provider_ids', 'cs', '{providerId}')` กรองที่ฝั่ง DB
4. **HomePage** — ลบ `_dismissedConsultationIds` Set → `_onConsultationAlertDismissed` เรียก `repo.dismissRequestForProvider()` → DB persist → real-time stream รีเฟรช → การ์ดหายไปถาวร

**ผลลัพธ์:**
| สถานการณ์ | ก่อนแก้ | หลังแก้ |
|---|---|---|
| Provider ปัดทิ้ง + รีเฟรช | การ์ดกลับมา | การ์ดหายไปถาวร |
| Provider ปัดทิ้ง + logout → login ใหม่ | การ์ดกลับมา | การ์ดหายไป (persist ใน DB) |
| Provider A ปัด / Provider B ไม่ปัด | — | Provider B ยังเห็นการ์ด (independent dismiss) |

#### 8️⃣ Best Practice: Dismissible Notifications Persist (ป้องกัน in-memory state)
**หลักการ:** หากฟีเจอร์มีการ "ปัดทิ้ง / dismiss / ซ่อน" ที่ต้องคงอยู่ข้าม session → **ต้อง persist ลง DB** ไม่ใช่เก็บใน widget state

**❌ ห้ามทำ:**
```dart
// ผิด — state หายเมื่อรีเฟรชหน้า
final Set<String> _dismissedIds = {};  // In-memory only
void dismiss(String id) {
  _dismissedIds.add(id);  // หายเมื่อ widget rebuild
}
```

**✅ ต้องทำ:**
```dart
// ถูก — persist ลง Supabase
Future<void> dismiss(String id) async {
  await repo.dismissForUser(requestId: id, userId: user.id);
}
// Query ฝั่ง DB กรอง dismissed ออก → ไม่กลับมาอีก
```

**Checklist ก่อน implement dismiss:**
| คำถาม | ต้องตอบ "ใช่" |
|---|---|
| Dismiss แล้วหายไปถาวรหรือไม่? | ✅ ต้อง persist ลง DB |
| ต้องกรองใน query ฝั่ง server หรือ client? | ✅ Server-side (`.not('col', 'cs', ...)`) |
| มีกรณี user A dismiss แต่ user B ยังเห็น? | ✅ ใช้ per-user dismiss array |
| ใช้ `Set<String>` หรือ `List<String>` ใน `_State`? | ❌ ห้าม — ถ้าต้องการ persist |

**ตัวอย่าง pattern ที่ใช้ในระบบนี้:**
```sql
-- Schema: dismissed_by_user_ids UUID[] DEFAULT '{}'
-- Query: .not('dismissed_by_user_ids', 'cs', '{userId}')
-- Update: fetch → append → update (ป้องกัน race condition)
```

### ⏰ ควรทำเมื่อไหร่

| จำนวนคำปรึกษา | ควรทำ? |
|---|---|
| < 100 | ยังไม่จำเป็น (แต่ทำได้ถ้าต้องการ) |
| 100-500 | **แนะนำ** (ประสิทธิภาพดีขึ้นมาก) |
| > 500 | **จำเป็น** (ป้องกัน crash / OOM) |

---

## 🚨 Critical Backlog — Provider Status Mismatch in `consultation_room_experts`

**ปัญหา:** Provider ที่รับงานแล้ว (`consultation_requests.provider_id` ถูกตั้ง) แต่ `consultation_room_experts.status` ยังเป็น `'waiting'` → `ExpertStatusBanner` แสดงเป็น 🔒 (waiting) แทนที่จะเป็น joined

**สาเหตุ:** `_joinRequest()` ใน `health_program_request_dashboard.dart` fallback ไปใช้ `assignProvider()` (ระบบเก่า) แต่ไม่ได้อัปเดต `consultation_room_experts` ให้เป็น `joined`

**แผนแก้ไข (วิธีที่ 2 — structural):**
1. **แก้ `_joinRequest`** — หลัง `assignProvider()` fallback success → เพิ่มการอัปเดต `consultation_room_experts` ให้สถานะเป็น `joined` (หรือยิ่งดี: ลบ fallback ระบบเก่า ให้แจ้ง user แทนถ้า expert group ไม่ตรง)
2. **Backfill ข้อมูลเก่า** — รัน SQL อัปเดต `consultation_room_experts` สำหรับคำปรึกษาที่ `provider_id` ถูกตั้งแล้วแต่ `status` ยังเป็น `waiting`
3. **(Optional safety net)** เพิ่ม client-side check ใน `_fetchExpertStatuses` ชั่วคราว จนกว่า backfill จะเสร็จ

**ไฟล์ที่เกี่ยวข้อง:**
- `lib/features/consultation/presentation/pages/health_program_request_dashboard.dart`
- `lib/features/consultation/presentation/pages/chart_board_page.dart`
- `lib/features/consultation/data/repositories/consultation_repository.dart`
- `supabase/migrations/20260516111500_strict_timer_start.sql` (RPC `assign_provider_to_group`)

**ความเร่งด่วน:** 🔴 **สูง** — กระทบ UX หลัก (provider เห็นตัวเองเป็น waiting แม้เข้าร่วมแล้ว) และ timer ไม่เริ่มถูกต้อง

---

**หลักการ:** Badge แสดง "โอกาส" (แพ็คเกจตรงอาชีพ) แต่ปุ่มแสดง "สิทธิ์" (status + availability) — ทั้งสองอย่างอิสระจากกัน
