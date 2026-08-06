# หาเพื่อนออกกำลังกาย (Find Fitness Buddies) — แผนพัฒนา

สรุปหนึ่งบรรทัด: สร้างฟีเจอร์ชุมชนสำหรับค้นหา/เข้าร่วมก๊วนกีฬาแบบเปิดดูได้โดยไม่ต้องล็อกอิน แต่บังคับล็อกอินเมื่อกดเข้าร่วม พร้อม redirect กลับหน้าที่ตั้งใจเข้าหลังสำเร็จ รวมตัวกรองสถานที่/ระยะทาง แผนที่ และห้องแชทของก๊วน

---

## เป้าหมายและขอบเขต (MVP + ส่วนขยายในรอบเดียว)
- MVP: รายการก๊วนตามหมวดกีฬา + หน้ารายละเอียดก๊วน + ปุ่ม “เข้าร่วมก๊วน” (ต้องล็อกอินก่อน) + redirect กลับหลังล็อกอิน
- เพิ่มตัวกรองสถานที่: จังหวัด/อำเภอ/รัศมี (กม.) โดยอาศัยตำแหน่งผู้ใช้แบบ opt‑in
- เพิ่มแผนที่: แสดงจุดนัดของก๊วนบนแผนที่ (ระหว่างพัฒนาใช้ OSM ผ่าน flutter_map เพื่อไม่มีค่าใช้จ่าย; เตรียม Adapter สำหรับสลับเป็น Google Maps เมื่อมี API key)
- เพิ่มแชทก๊วน: เปิดห้องแชทสำหรับสมาชิกก๊วน ใช้โครงสร้างแชทที่มีอยู่

## การนำทางและเมนู
- Drawer ซ้าย > กลุ่ม “ชุมชน” > เมนูใหม่: “หาเพื่อนออกกำลังกาย”
- เส้นทาง (proposed routes):
  - `/community/find-buddies` (รายการ/ตัวกรอง/สลับมุมมองแผนที่)
  - `/community/find-buddies/group/:id` (รายละเอียดก๊วน + CTA เข้าร่วม/เปิดแชท)
  - `/community/find-buddies/group/create` (สร้างก๊วน; รับ args ทางเลือก `{ sportId }` เพื่อกำหนดค่าเริ่มต้นของ dropdown กีฬา)

## หน้าจอและ UI (ใช้ `tlz_app_top_bar.dart`)
- Top bar ทั่วไป: 
  - ซ้าย: ปุ่มเปิด Drawer/ย้อนกลับ (ตาม context)
  - กลาง: ชื่อหน้า "หาเพื่อนออกกำลังกาย" หรือชื่อก๊วน
  - ขวา: ปุ่มค้นหา (รวมตัวกรองใน dialog เดียว), ปุ่มสลับ "รายการ/แผนที่"
- หน้า "รายการก๊วน"
  - แถบ "หมวดหมู่กีฬา" (แนวนอนแบบ Chip) + ปุ่ม "+" ทรงกลม (เฉพาะ admin `role == 'admin'`; ผู้ใช้ทั่วไปไม่เห็นปุ่มนี้) — ปุ่มอยู่นอก scroll area ติดขวาไม่เลื่อนตาม chip
  - รายการก๊วน (การ์ด): ชื่อก๊วน, กีฬา, วันเวลา/ความถี่, พื้นที่, ระยะทาง, สมาชิกปัจจุบัน, รูปสนาม (thumbnail), badge เพศที่เชิญชวน (ช./ญ./เสรี)
  - ค้นหาและตัวกรอง: รวมใน dialog เดียวเปิดจากปุ่ม search ใน top bar — มีช่องค้นหาก๊วน/สถานที่, จังหวัด, อำเภอ, และ checkbox "เฉพาะก๊วนเปิดรับ"
  - ปุ่ม toggle แผนที่ (เปิด/ปิด มุมมองแผนที่)
- หน้า “แผนที่”
  - แสดง Marker ของก๊วนตามตัวกรอง, คลิก Marker เปิดแผ่นสรุปและนำทางไปหน้ารายละเอียด
- หน้า “รายละเอียดก๊วน”
  - ปกก๊วน, คำอธิบาย, สถานที่/พิกัด/ลิงก์นำทาง, ตารางนัดหมายถัดไป, จำนวนสมาชิก
  - CTA: “เข้าร่วมก๊วน” (ถ้าเป็นสมาชิกแล้ว: “ไปที่แชทก๊วน”)

## หมวดหมู่กีฬา (เริ่มต้นในไทย)
- Seed 63 ประเภทกีฬาพร้อม emoji icon ครอบคลุมทุกหมวด (กีฬาทีม/บอล, แร็กเก็ต, ทางน้ำ, วิ่ง/จักรยาน/กลางแจ้ง, ฟิตเนส/โยคะ, ศิลปะการต่อสู้, ความเร็ว/ยิง, อื่นๆ) — ดู migration `20260805083000_seed_sports_with_icons.sql`
- ตัวอย่าง: ⚽ ฟุตบอล, 🏀 บาสเกตบอล, 🏸 แบดมินตัน, 🏊 ว่ายน้ำ, 🏃 วิ่ง, 🚴 ปั่นจักรยาน, 🧗 ปีนผา, 🥾 เดินป่า, 🧘 โยคะ, 🥊 มวยไทย, 🎾 เทนนิส, 🏓 ปิงปอง, 🏐 วอลเลย์บอล, 🏋️ เวทเทรนนิ่ง, 🎮 อีสปอร์ต
- `sports.icon` (TEXT) เก็บ emoji แสดงผลใน: sport chip แถวหมวดหมู่, การ์ดก๊วน, dropdown เลือกกีฬาในหน้าสร้างก๊วน, รายการรออนุมัติ
- กีฬาที่ผู้ใช้เสนอใหม่ (ไม่มีใน seed): admin ใส่ emoji icon ได้ตอนอนุมัติผ่าน dialog ในหน้า `ReviewProposedSportsPage`
- ปุ่ม "+" ทรงกลม: เฉพาะ admin (`role == 'admin'`) เท่านั้น ผู้ใช้ทั่วไปไม่เห็นปุ่มนี้ (`SizedBox.shrink()`); ปุ่มอยู่นอก scroll area ติดขวาของแถบ chip
- การเรียงลำดับ chip กีฬา: เรียงตามพยัญชนะหลักตัวแรกของชื่อไทยแบบ ascending (ก → ฮ) โดยข้ามสระนำหน้า (เ แ โ ใ ไ) ผ่าน `_thaiFirstConsonantIndex()` และ `_compareThaiAsc()` ใน `fitness_buddies_repository.dart`; chip "ทั้งหมด" เป็นตัวแรกเสมอ (hardcoded ใน UI)
- **เรียงตามความถี่ใช้งาน (สำหรับผู้ใช้ที่ล็อกอิน):** ประเภทกีฬาที่ผู้ใช้เคยสร้างก๊วนหรือเข้าร่วมก๊วน จะถูกจัดวางซ้ายสุดก่อน เรียงตามความถี่จากมากไปน้อย (ผ่าน `getUserSportFrequency()`) ส่วนประเภทที่ไม่เคยใช้เรียง ก → ฮ ตามหลัง; ผู้ใช้ที่ยังไม่ล็อกอินเรียง ก → ฮ ทั้งหมด
- Seed migration เป็น idempotent (`NOT EXISTS` + `UPDATE` icon สำหรับกีฬาที่มีอยู่แต่ยังไม่มี icon)

## กฎการล็อกอินและ Redirect
- เปิดดูรายการ/รายละเอียดก๊วน: ไม่บังคับล็อกอิน
- กด “เข้าร่วมก๊วน”: ถ้าไม่ล็อกอิน → นำทางไปหน้า Login พร้อมส่งพารามิเตอร์ redirect (route + args)
- หลังล็อกอินสำเร็จ: กลับมาที่หน้ารายละเอียดก๊วนเดิม และถ้ามี `intent = join_group` ให้ดำเนินการจองรอบนัดถัดไปอัตโนมัติ/หรือยืนยันอีกครั้ง (หมายเหตุ: "เข้าร่วมก๊วน" และ "จองรอบนัด" คือ action เดียวกัน ดูหัวข้อ "เข้าร่วมก๊วน = จองรอบนัด")
- แนวทางเทคนิค: reuse กลไก redirect ที่แอปใช้กับ donation tab (ส่ง `{ route, args }` ไปยัง /login และ pop กลับพร้อม args)

## สถาปัตยกรรมข้อมูล (Proposed on Supabase)
- `sports` (id, name_th, name_en, icon TEXT, status VARCHAR(10) DEFAULT 'approved' CHECK(status IN ('pending','approved','rejected')), proposed_by UUID REFERENCES users(id), proposed_at TIMESTAMPTZ, reviewed_by UUID REFERENCES users(id), reviewed_at TIMESTAMPTZ, rejection_reason VARCHAR(200))
  - `icon`: emoji แสดงผลประจำกีฬา (เช่น ⚽ 🏀 🏸) — seed 63 ประเภทพร้อม icon ผ่าน migration `20260805083000_seed_sports_with_icons.sql`; กีฬาที่เสนอใหม่ได้รับ icon ตอน admin อนุมัติ
- `fitness_groups` (id, sport_id, name VARCHAR(60), description VARCHAR(500), province, district, lat DOUBLE PRECISION CHECK(lat BETWEEN -90 AND 90), lng DOUBLE PRECISION CHECK(lng BETWEEN -180 AND 180), visibility VARCHAR(10) DEFAULT 'public' CHECK(visibility IN ('public','private')), requires_owner_approval BOOLEAN DEFAULT false, cover_image_url VARCHAR(500), venue_photo_url VARCHAR(500), gender_preference VARCHAR(10) DEFAULT 'any' CHECK(gender_preference IN ('male','female','any')), created_by UUID REFERENCES users(id), created_at TIMESTAMPTZ DEFAULT now())
  - `venue_photo_url`: รูปถ่ายสนาม/สถานที่จริงที่ใช้นัดเล่น (แยกจาก `cover_image_url` ซึ่งเป็นภาพปกของก๊วน)
  - `gender_preference`: เพศที่กำลังชวนเข้าร่วมก๊วน — `'male'` (ชาย), `'female'` (หญิง), `'any'` (เสรี/ไม่จำกัด — ค่าเริ่มต้น)
- `fitness_group_sessions` (id, group_id UUID REFERENCES fitness_groups(id) ON DELETE CASCADE, starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ, place_name VARCHAR(200), lat DOUBLE PRECISION, lng DOUBLE PRECISION, note VARCHAR(500), CHECK(ends_at > starts_at))
- `fitness_group_members` (group_id UUID, user_id UUID REFERENCES users(id), role VARCHAR(10) CHECK(role IN ('member','admin')), is_active BOOLEAN DEFAULT true, joined_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY(group_id, user_id))
  - หมายเหตุ: แถวนี้ **สร้าง/อัปเดตอัตโนมัติโดยระบบ** เมื่อผู้ใช้จองรอบนัดครั้งแรก — ไม่มีฟอร์ม "สมัครสมาชิก" แยก (ดูหัวข้อ "เข้าร่วมก๊วน = จองรอบนัด")
- `fitness_group_bookings` (id UUID DEFAULT gen_random_uuid(), session_id UUID REFERENCES fitness_group_sessions(id), user_id UUID REFERENCES users(id), status VARCHAR(10) CHECK(status IN ('pending','confirmed','cancelled','rejected')), created_at TIMESTAMPTZ DEFAULT now(), cancelled_at TIMESTAMPTZ, cancelled_by VARCHAR(10) CHECK(cancelled_by IN ('user','owner','system')), cancel_reason VARCHAR(200), UNIQUE(session_id, user_id))
  - ⚠️ `UNIQUE(session_id, user_id)` ป้องกันการจองซ้ำระดับ DB — ถ้ายกเลิกแล้วต้องการจองใหม่ ให้ UPDATE แถวเดิม (soft-reactivate) แทนการ INSERT ใหม่
- `fitness_group_blocklist` (group_id UUID, blocked_user_id UUID REFERENCES users(id), blocked_by UUID REFERENCES users(id), reason VARCHAR(200), is_active BOOLEAN DEFAULT true, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY(group_id, blocked_user_id))
- ความสัมพันธ์กับแชท: ผูก `chat_rooms` เดิม (ต้องมี migration เพิ่ม — ดูหัวข้อ "Chat Room Integration")

### เข้าร่วมก๊วน = จองรอบนัด (Unified Action)
- sheserved ไม่มีขั้นตอน "สมัครสมาชิกก๊วน" แยกจาก "จองรอบนัด" — ทั้งสองคำมีความหมายเดียวกัน: กด **"เข้าร่วมก๊วน"** = สร้าง `fitness_group_bookings` สำหรับรอบนัดถัดไปโดยตรง (สมาชิก sheserved จองได้อิสระ ไม่ต้องผ่านขั้นตอนสมัครสมาชิกก่อน)
- เมื่อ booking แรกของผู้ใช้ในก๊วนนั้นถูกสร้าง (ไม่ว่า `pending` หรือ `confirmed`) ระบบ **upsert** แถวใน `fitness_group_members` (`role='member', is_active=true`) อัตโนมัติภายใน transaction เดียวกับการสร้าง booking (ผ่าน RPC function — ดูหัวข้อ Data Integrity Guards)
- **ออกจากก๊วน:** ตั้ง `fitness_group_members.is_active = false` และยกเลิก booking ที่ `pending`/`confirmed` ทั้งหมดของผู้ใช้ในก๊วนนั้นแบบ cascade (`status='cancelled', cancelled_by='user'`) ภายใน transaction เดียว
- สิทธิ์เข้าแชทกลุ่ม: ตรวจจาก `fitness_group_members.is_active = true` เท่านั้น
- แอดมินก๊วน (`role='admin'`): ผู้สร้างก๊วนเป็นแอดมินคนแรกอัตโนมัติ; เพิ่ม/ถอดแอดมินคนอื่นทำได้เฉพาะแอดมินปัจจุบัน

### Chat Room Integration (ต้องมี Migration ใหม่)
- Schema ปัจจุบันของ `chat_rooms` (`database/schemas/supabase_chat_schema.sql:2-9`) มีแค่ `id, participant_ids UUID[], last_message, ...` — **ไม่มี** `room_type`/`room_ref_id`
- Migration ที่ต้องเพิ่ม:
  ```sql
  ALTER TABLE chat_rooms
    ADD COLUMN room_type VARCHAR(20) DEFAULT 'direct' CHECK (room_type IN ('direct','fitness_group')),
    ADD COLUMN room_ref_id UUID;
  CREATE INDEX idx_chat_rooms_ref ON chat_rooms(room_type, room_ref_id);
  ```
- สร้างห้องแชท (`room_type='fitness_group', room_ref_id=group_id`) อัตโนมัติตอนสร้างก๊วนสำเร็จ (1 ก๊วน = 1 ห้องแชท)
- Sync `participant_ids`: ทุกครั้งที่ `fitness_group_members` เปลี่ยนแปลง (join ผ่านการจอง / leave) ให้ Postgres trigger `sync_fitness_chat_participants()` อัปเดต `chat_rooms.participant_ids` ให้ตรงกับสมาชิก `is_active=true` ปัจจุบันของก๊วนนั้นแบบ atomic
- ⚠️ Tech debt เดิมที่ต้องรับทราบ: `chat_messages.sender_id REFERENCES auth.users(id)` อ้าง Supabase Auth ที่ไม่ได้ใช้งานจริงในโปรเจกต์นี้ — ไม่แก้ในรอบนี้ แต่ FK นี้จะไม่ enforce ความสัมพันธ์กับ `public.users.id` จริง (ความเสี่ยงเดิมที่มีอยู่แล้วในระบบ)

### Data Integrity Guards (ป้องกัน Race Condition ระดับ DB)
- **ป้องกันจองซ้ำ:** `UNIQUE(session_id, user_id)` บน `fitness_group_bookings` (เพิ่มใน schema แล้ว)
- **ป้องกันเกิน capacity:** สร้าง Postgres function `book_fitness_session(p_session_id, p_user_id)` ทำงานใน transaction เดียว:
  1. `SELECT ... FOR UPDATE` ล็อกแถว `fitness_groups` ของ session นั้น
  2. นับสมาชิก `is_active=true` ปัจจุบันเทียบกับ capacity เป้าหมาย
  3. ถ้าเกิน → return error `GROUP_FULL`
  4. ถ้าไม่เกิน → insert/reactivate booking + upsert `fitness_group_members` ในธุรกรรมเดียว
- **ป้องกันจองซ้อนเวลา (overlap):** สร้าง Postgres function `check_booking_overlap(p_user_id, p_starts_at, p_ends_at)` ตรวจ `fitness_group_bookings JOIN fitness_group_sessions` ที่ status ไม่ใช่ `cancelled`/`rejected` และช่วงเวลาทับซ้อน — เรียกจากภายใน `book_fitness_session()` ก่อน insert เพื่อความ atomic
- ทุก mutation (จอง/ยกเลิก/อนุมัติ) เรียกผ่าน Supabase RPC จาก Flutter แทนการทำ SELECT แล้ว INSERT แยกฝั่ง client เพื่อปิดช่องว่าง race condition

### Indexes ที่ต้องสร้าง
- `idx_fitness_sessions_group_starts` ON `fitness_group_sessions(group_id, starts_at)`
- `idx_fitness_bookings_user_status` ON `fitness_group_bookings(user_id, status)`
- `idx_fitness_bookings_session_active` ON `fitness_group_bookings(session_id) WHERE status IN ('pending','confirmed')`
- `idx_fitness_groups_sport_province` ON `fitness_groups(sport_id, province, district)`
- `idx_fitness_members_group_active` ON `fitness_group_members(group_id) WHERE is_active = true`

### RLS Policy (สอดคล้องกับ rls_audit_report.md Phase 1)
> ⚠️ โปรเจกต์นี้ **ไม่ได้ใช้ Supabase Auth** — `auth.uid()` เป็น `null` เสมอ (ดู `auth_data_guidelines.md` และ `20260526144500_fix_emergency_health_fk_to_public_users.sql`)
> ใช้รูปแบบ `USING(true)` + App Layer enforce (เหมือน `20260409010000_add_beneficiary_system.sql`)

| ตาราง | SELECT Policy | INSERT/UPDATE/DELETE Policy |
|-------|--------------|---------------------------|
| `sports` | `USING(true)` (public reference) | service_role เท่านั้น |
| `fitness_groups` | `USING(true)` (ตาม visibility filter ฝั่ง App) | App Layer ตรวจสิทธิ์: created_by หรือ admin ของก๊วน |
| `fitness_group_sessions` | `USING(true)` | App Layer: เฉพาะ admin ของก๊วน |
| `fitness_group_members` | `USING(true)` | App Layer: สมาชิกเข้าร่วมเอง / admin จัดการ |
| `fitness_group_bookings` | `USING(true)` | App Layer: ผู้จองสร้าง/ยกเลิกของตน; เจ้าของอนุมัติ/ยกเลิก |
| `fitness_group_blocklist` | `USING(true)` | App Layer: เฉพาะ admin ของก๊วน |

> **Phase 2/3 (อนาคต):** เมื่อ migrate ไป Supabase Auth ตามแผน 09 ให้แทนที่ `USING(true)` ด้วย `auth.uid()`-based policies ตาม `rls_audit_report.md` Section 7

## ฟังก์ชันหลัก
- สร้างก๊วน: ทุกคนที่ล็อกอิน
- แก้ไข/จัดการก๊วน: เฉพาะแอดมินของก๊วน
- เพิ่ม/แก้ไขหมวดหมู่กีฬา: เฉพาะแอดมินก๊วน/ผู้ดูแลระบบ (ผู้ใช้อื่นเสนอคำขอได้)
- เข้าร่วม/ออกก๊วน (= จองรอบนัด/ยกเลิกจอง ดู "เข้าร่วมก๊วน = จองรอบนัด"), เปิดแชทก๊วน
- ตัวกรองสถานที่/ค้นหา + cache ข้อมูลหน้าแรก
- แผนที่ + การคำนวณระยะทางจากตำแหน่งผู้ใช้ (opt-in; ถ้าไม่อนุญาตแสดงผลเชิงพื้นที่ตามจังหวัดแทน)

## UX/UI — หน้าสร้างก๊วนกีฬา (Create Group)
- เส้นทางที่ใช้: `/community/find-buddies/group/create` (เปิดดูได้โดยไม่ล็อกอิน แต่ส่งฟอร์มต้องล็อกอิน)

- โครงร่างหน้า
  - AppBar: ใช้ `tlz_app_top_bar.dart` ชื่อหน้า “สร้างก๊วนกีฬา” ปุ่มซ้าย Back
  - ปุ่มหลัก: “สร้างก๊วน” ตรึงล่าง (enabled เมื่อกรอกครบขั้นต่ำ)

- องค์ประกอบฟอร์ม (บนลงล่าง)
  - กีฬา: DropdownMenu อยู่ก่อน "ชื่อก๊วน" จัดกึ่งกลาง หน้ากว้าง 50% ของจอ เมนูสูงไม่เกิน 50% ของจอ; ระหว่างโหลดรายการกีฬา แสดง CircularProgressIndicator ภายในช่อง; เรียงลำดับกีฬาตามความถี่การใช้งานของผู้ใช้ (desc) แล้วตามพยัญชนะไทย (ก → ฮ); ถ้าเข้าหน้านี้จากหน้า "หาเพื่อนฯ" พร้อมเลือกหมวดไว้ ให้ default เป็นกีฬานั้น (อ่านจาก args `{ sportId }`)
  - ชื่อก๊วน: TextField บังคับกรอก สูงสุด 60 ตัวอักษร
  - **ภาพถ่ายสนาม:** ปุ่ม “เพิ่มรูปสนาม” เปิด image picker (กล้อง/คลังภาพ) อัปโหลดไป Supabase Storage bucket `fitness-group-venues` (public read, insert/update เฉพาะ owner/admin ของก๊วน) แล้วบันทึก URL ลง `fitness_groups.venue_photo_url` (ไม่บังคับ, แสดง preview thumbnail หลังอัปโหลดสำเร็จ) — แยกจากภาพปกก๊วน (`cover_image_url`)
  - **เพศที่ต้องการชวนเข้าร่วม:** แถวปุ่มเลือกแบบ segmented/Chip 3 ตัวเลือก “ช.” (ชาย), “ญ.” (หญิง), “เสรี” (ไม่จำกัด — ค่าเริ่มต้นที่เลือกไว้) บันทึกลง `fitness_groups.gender_preference` (`'male'|'female'|'any'`) — ใช้เป็นข้อมูลแสดงผลในรายการ/รายละเอียดก๊วนเพื่อให้ผู้เข้าชมทราบกลุ่มเป้าหมาย ไม่ใช่การบังคับกรองสิทธิ์เข้าร่วมระดับ DB/RLS ในรอบแรก
  - สถานที่ + แผนที่: การ์ดแผนที่พร้อมพิน (draggable) ปุ่ม “ค้นหาสถานที่”, “ใช้ตำแหน่งฉัน”, “ปักหมุด” แสดงชื่อสถานที่/ที่อยู่สรุป และลิงก์ “เปิดใน Google Maps”
    - Dev ใช้ OSM ผ่าน flutter_map (ไม่มีค่าใช้จ่าย) ด้วย MapAdapter ที่สลับไป Google Maps ได้ภายหลังเมื่อมี key
  - ~~วันที่และเวลา: DatePicker + TimePicker ต้องเป็นอนาคต ≥ ปัจจุบัน + 30 นาที~~ → **ย้ายไป Bottom Sheet "สร้างรอบนัด" แยกต่างหาก** (ดูหัวข้อ "สร้างรอบนัด (Bottom Sheet)" ด้านล่าง)
  - จำนวนสมาชิกเป้าหมาย: Stepper/Slider ช่วง 2–30 (เริ่มต้น 5)
  - รายละเอียด: TextArea 2–5 บรรทัด (ไม่บังคับ, สูงสุด ~500 ตัวอักษร)
  - การจองและการอนุมัติ: Toggle “ต้องให้เจ้าของก๊วนอนุมัติก่อนจึงมีผลต่อการจอง” (ค่าเริ่มต้น: ปิด = ยอมรับอัตโนมัติ)

- สถานะ/การโต้ตอบ
  - Validation ระหว่างพิมพ์และก่อนส่ง: ต้องเลือกกีฬา, ชื่อก๊วนยาวพอ, มีพิกัด lat/lng (วันเวลาย้ายไป Bottom Sheet แยก)
  - สิทธิ์ตำแหน่ง: ถ้าไม่อนุญาต ปุ่ม “ใช้ตำแหน่งฉัน” disabled พร้อมคำอธิบายสั้น ๆ
  - สิทธิ์กล้อง/คลังภาพ: ถ้าไม่อนุญาต ปุ่ม “เพิ่มรูปสนาม” แสดง SnackBar อธิบายวิธีเปิดสิทธิ์ในตั้งค่าเครื่อง
  - บังคับล็อกอินเมื่อส่ง: ถ้าไม่ล็อกอิน เมื่อกด “สร้างก๊วน” → ไปหน้า Login พร้อม redirect `{ route: '/community/find-buddies/create', args: draft }` และกลับมาดำเนินการต่อ
  - ระหว่างบันทึก: ปุ่มแสดงสถานะ loading + disabled และมี SnackBar เมื่อสำเร็จ/ล้มเหลว

- โครงร่าง Widget Tree (สรุป)
```
Scaffold
  appBar: TLZAppTopBar(title: 'สร้างก๊วนกีฬา')
  body: SafeArea(
    child: ListView(children: [
      Center(
        child: SizedBox(width: 0.5 * screenWidth,
          child: DropdownMenu(label: 'กีฬา')
        )
      ),
      TextField(label: 'ชื่อก๊วน (สูงสุด 60 ตัวอักษร)'),
      VenuePhotoPicker(...),
      GenderPreferenceChips(...),
      MapCard(...),
      // DateTimeRow ย้ายไป Bottom Sheet "สร้างรอบนัด"
      CapacityStepper(...),
      MultilineTextField(label: 'รายละเอียด')
    ])
  )
  bottomNavigationBar: PrimaryButton('สร้างก๊วน', enabled: isValid)
```

## สร้างรอบนัด (Bottom Sheet) — Implementation (2026-08-06)
- **โฟลว์:** หลังสร้างก๊วนสำเร็จ → เปิด Bottom Sheet สร้างรอบนัดทันที (ไม่นำทางไปหน้าแยก)
- **ทริกเกอร์ 2 จุด:**
  1. หลัง `createGroup()` สำเร็จใน `create_group_page.dart` → `Navigator.pushNamed('/community/find-buddies/session/create')` (คงไว้ชั่วคราว ก่อนเปลี่ยนเป็น Bottom Sheet ในอนาคต)
  2. ปุ่ม "เพิ่มรอบนัด" ในการ์ดก๊วน (เฉพาะแอดมินของก๊วนนั้น) → เรียก `_showCreateSessionSheet(groupId)` ใน `find_buddies_page.dart`
- **ปุ่ม "เข้าร่วมก๊วน" สำหรับผู้ใช้ทั่วไป:** แสดงแทนปุ่ม "เพิ่มรอบนัด" เมื่อไม่ใช่แอดมิน → ดึงรอบนัดที่ใกล้ที่สุด (limit=1) แล้วเรียก `_book(sessionId)` อัตโนมัติ
- **ฟิลด์ใน Bottom Sheet:**
  - วันที่: ใช้ `ThaiBuddhistDatePickerField` ค่าเริ่มต้น = วันปัจจุบัน
  - เวลาเริ่มต้น: Material `showTimePicker` ค่าเริ่มต้น = ปัดขึ้นครึ่งชั่วโมงถัดไป
  - เวลาสิ้นสุด: Material `showTimePicker` ค่าเริ่มต้น = เวลาเริ่ม + 1 ชั่วโมง
  - หมายเหตุ (`note`): ไม่บังคับ, สูงสุด ~500 ตัวอักษร
  - ไม่มีฟิลด์สถานที่ (`place_name`) หรือพิกัด lat/lng (พิกัดของก๊วนใช้ข้อมูลเดิมใน `fitness_groups`) เพื่อไม่ให้ซ้ำซ้อน
- **Validation:**
  - เวลาเริ่มต้น ≥ ตอนนี้ + 15 นาที
  - เวลาสิ้นสุด > เวลาเริ่มต้น
- **หลังบันทึกสำเร็จ:** ปิด Bottom Sheet, แสดง SnackBar "สร้างรอบนัดสำเร็จ", `setState()` เพื่อรีโหลด FutureBuilder รายการรอบนัด
- **ไฟล์ที่เกี่ยวข้อง:**
  - `lib/features/community/find_buddies/presentation/pages/find_buddies_page.dart` — `_showCreateSessionSheet()`, ปุ่ม "เพิ่มรอบนัด"/"เข้าร่วมก๊วน"
  - `lib/features/community/find_buddies/presentation/pages/create_group_page.dart` — redirect หลังสร้างก๊วน
  - `lib/features/community/find_buddies/data/fitness_buddies_repository.dart` — `createSession()`
  - `lib/shared/widgets/thai_buddhist_date_picker.dart` — `ThaiBuddhistDatePickerField`
- **อนาคต:** หากต้องการแผนที่โต้ตอบ ให้เพิ่ม dependency `flutter_map`/`latlong2` และอ้างอิงพิกัด `fitness_groups.lat/lng` โดยตรง ไม่ต้องกรอกพิกัดซ้ำในรอบนัด

## ปรับตำแหน่ง TLZBottomNavigationBar บน Android (2026-08-06)
- **สาเหตุ:** Android ที่มี gesture bar (`bottomSafeArea > 0`) ตกเงื่อนไขเดียวกับ iOS ทำให้ใช้ค่า `14.0` แทนค่า Android ที่ตั้งไว้
- **วิธีแก้:** เปลี่ยนจากเงื่อนไข `bottomSafeArea > 0` เป็น `Platform.isAndroid` แยกจาก iOS โดยตรง
  - Android: `bottomMargin = 26 * s` (ปรับจาก 16 → 26 → 35 → 26 ตาม feedback)
  - iOS: `bottomMargin = 14.0` คงที่
- **ไฟล์:** `lib/shared/widgets/tlz_bottom_navigation_bar.dart:88` และ import `dart:io` บรรทัด 1
- **บทเรียน:** อย่าใช้ `bottomSafeArea > 0` แยกแพลตฟอร์ม เพราะ Android รุ่นใหม่มี gesture bar ที่ทำให้ค่าไม่เป็น 0; ใช้ `Platform.isAndroid`/`Platform.isIOS` แทน

## กติกาธุรกิจ — การจอง อนุมัติ และการแจ้งเตือน
- ประเภทการจอง: ผู้ใช้จอง “เข้าร่วมรอบนัด (session)” ที่ `fitness_group_sessions`
- การอนุมัติ:
  - ค่าเริ่มต้น: ยอมรับอัตโนมัติ → สถานะ `confirmed` และแจ้งเตือนเฉพาะผู้จอง
  - ถ้าเปิด Toggle “ต้องอนุมัติก่อน” → บันทึกเป็น `pending` รอเจ้าของอนุมัติ (เมื่ออนุมัติสำเร็จ แจ้งผู้จองเท่านั้น)
- การยกเลิก:
  - ผู้จองยกเลิกเมื่อใดก็ได้ → เปลี่ยนเป็น `cancelled` และแจ้ง “เจ้าของก๊วน”
  - เจ้าของก๊วนยกเลิกรอบ/ก๊วนทั้งหมด → แจ้งผู้จองทุกคนที่มีสถานะไม่ใช่ `cancelled`
- **หัวข้อแจ้งเตือน (Headsector ด้านขวา Home) — ใช้ WebSocket แบบ Real-time** (ตาม pattern เดียวกับ donation/yield-way ที่มีอยู่ ไม่ใช่ polling table):
  - Backend (`websocket-server`): เพิ่ม event `fitness_booking_status` ที่ emit ไปยัง `userId` ที่เกี่ยวข้อง (ผู้จอง และ/หรือ เจ้าของก๊วน) ทันทีที่มีการ confirm/reject/cancel booking
  - `lib/services/websocket_service.dart`: เพิ่ม `final _fitnessBookingAlertController = StreamController<Map<String, dynamic>>.broadcast();` และ getter `Stream<Map<String, dynamic>> get fitnessBookingAlertStream => _fitnessBookingAlertController.stream;` (เหมือน `_donationStatusController`/`_yieldWayAlertController`)
  - `lib/features/home/presentation/pages/home_page.dart`: เพิ่ม state `_fitnessBookingAlerts` + subscription ที่ listen ใน method รูปแบบเดียวกับ `_listenForDonationStatus()` พร้อม auto-clear หลัง ~15 วินาที
  - `lib/features/home/presentation/widgets/home_header_section.dart`: เพิ่ม branch ใหม่ `item['type'] == 'fitness_booking'` ใน `combinedItems` (ตาม pattern ของ `donation_update`/`yield_way`) พร้อม callback `onFitnessBookingAlertTapped` นำไปหน้า `/community/find-buddies/booking/:id`
  - แสดงเป็นฟีดใหม่→เก่า คลิกเข้าหน้า "รายละเอียดการจอง"
- **Timeout สำหรับ pending booking:** ถ้า booking สถานะ `pending` ไม่ได้รับอนุมัติภายใน 24 ชั่วโมง หรือถึงเวลาก่อนเริ่ม session 1 ชั่วโมง (แล้วแต่ถึงก่อน) ระบบ auto-reject (`status='rejected', cancelled_by='system'`) ผ่าน BullMQ delayed job ที่ enqueue ตอนสร้าง booking (สอดคล้องกับ `architecture_analysis.md` ที่ใช้ BullMQ queue อยู่แล้ว) และแจ้งเตือนทั้งผู้จองและเจ้าของก๊วนผ่าน event `fitness_booking_status` ด้านบน
- ป้องกันการจองซ้ำซ้อน: ตรวจผ่าน `check_booking_overlap()` RPC (ดู Data Integrity Guards) — ปฏิเสธพร้อมแสดงเหตุผลให้ทราบในขั้นตอนขอร่วมก๊วน
- บล็อกผู้ใช้: เจ้าของก๊วนสามารถบล็อกผู้ใช้ (ห้ามจองก๊วนนี้) และดูประวัติการถูกบล็อก/การจองย้อนหลังจาก dialog ที่เปิดจากโปรไฟล์ผู้จอง

## UX Completeness เพิ่มเติม
- **Push Notification (นอกแอป):** รอบแรกไม่ทำ — Headsector ทำงานเฉพาะตอนแอปเปิดอยู่ (WebSocket only) ผู้ใช้ที่ปิดแอปจะไม่เห็นแจ้งเตือนจนกว่าจะเปิดแอปใหม่ (ออกแบบ `payload` ของ event ไว้ล่วงหน้าให้ขยายไปต่อ FCM/APNs ได้ในเฟสถัดไปโดยไม่แก้ schema)
- **Cover image ก๊วน:** ใช้คอลัมน์ `fitness_groups.cover_image_url` (เพิ่มใน schema แล้ว) กับ Supabase Storage bucket ใหม่ `fitness-group-covers` (public read, insert/update เฉพาะ owner/admin ของก๊วนผ่าน storage RLS policy)
- **ภาพถ่ายสนาม:** ใช้คอลัมน์ `fitness_groups.venue_photo_url` กับ Supabase Storage bucket ใหม่ `fitness-group-venues` (public read, insert/update เฉพาะ owner/admin ของก๊วนผ่าน storage RLS policy เช่นเดียวกับ cover image) — แสดงในหน้ารายละเอียดก๊วนเพื่อให้ผู้เข้าร่วมเห็นสภาพสนามจริงก่อนตัดสินใจเข้าร่วม
- **เพศที่เชิญชวนเข้าร่วม:** ใช้คอลัมน์ `fitness_groups.gender_preference` (`'male'|'female'|'any'`, ค่าเริ่มต้น `'any'`) แสดงเป็น badge ในการ์ดรายการก๊วนและหน้ารายละเอียด — เป็นข้อมูลประกอบการตัดสินใจเท่านั้น ไม่บังคับกรองสิทธิ์การจอง/เข้าร่วมระดับระบบในรอบแรก
- **Province/District:** ใช้ free-text VARCHAR ต่อไปในรอบแรก (ตรวจสอบแล้วไม่มี master table province/district กลางในระบบที่ reuse ได้) — มี index `(sport_id, province, district)` รองรับการกรองแล้ว
- **`visibility` enum:** กำหนดค่าไว้แล้วใน schema — `'public'` (ค่าเริ่มต้น, แสดงในรายการค้นหาทั่วไป) / `'private'` (แสดงเฉพาะสมาชิกที่ `is_active=true` เท่านั้น ไม่ปรากฏใน public list)
- **สิทธิ์แก้ไข `requires_owner_approval`:** เฉพาะ `fitness_group_members.role='admin'` ของก๊วนนั้นแก้ไขได้ การเปลี่ยนค่าไม่มีผลย้อนหลังกับ booking ที่มีสถานะอยู่แล้ว มีผลกับ booking ใหม่เท่านั้น

## ไม่ใช่ขอบเขต (รอบแรก)
- ระบบนัดหมายซับซ้อน (เช่น วนรายสัปดาห์พร้อมกติกา), ระบบเช็คอิน, คะแนนความน่าเชื่อถือ
- ระบบชำระเงิน/จองสนาม

## ความปลอดภัยและสิทธิ์
- อ่านข้อมูล: public (ตาม visibility)
- สร้างก๊วน: ผู้ใช้ที่ล็อกอินทุกคน
- แก้ไข/จัดการก๊วน: เฉพาะแอดมินของก๊วน
- เพิ่ม/แก้ไขหมวดหมู่กีฬา: เฉพาะแอดมินก๊วน/ผู้ดูแลระบบ
- เข้าร่วม: ผู้ใช้ล็อกอินเท่านั้น
- แชท: เฉพาะสมาชิกก๊วน (ตรวจสิทธิ์ก่อนเข้าห้อง)
- แผนที่: ระหว่างพัฒนาใช้ผู้ให้บริการไม่มีค่าใช้จ่าย (OSM + flutter_map); เตรียม config สำหรับสลับ Google Maps ได้โดยไม่แก้โค้ด
- การบล็อก: ผู้ใช้ที่ถูกบล็อกในก๊วนจะไม่สามารถทำการจองใหม่ในก๊วนนั้นได้ จนกว่าจะถูกยกเลิกบล็อก

## การปฏิบัติตามแนวทาง Security & Infrastructure

### Auth Data Guidelines (`auth_data_guidelines.md`)
- ❌ ห้ามใช้ `Supabase.instance.client.auth.currentUser` หรือ `_client.auth.currentUser` — ค่าเป็น `null` เสมอ
- ✅ ดึง `userId` จาก `ServiceLocator.instance.currentUser?.id` เท่านั้น
- ✅ Repository ต้องรับ `userId` เป็นพารามิเตอร์ ไม่ดึงเองจาก Supabase Auth
- ✅ UI (Presentation) ส่ง `userId` จาก `ServiceLocator` เข้า Repository

### BOLA/IDOR Prevention (`docs/secure/01_broken_object_level_authorization.md`)
- ⚠️ Backend endpoints ต้องใช้ `req.userId` จาก identity ที่ยืนยันแล้ว ไม่ใช่ `req.body.userId`
- ⚠️ ทุก endpoint ที่อ่าน/แก้ไข booking, member, blocklist ต้องตรวจ ownership ก่อน (เช่น `booking.user_id = req.userId` หรือ `member.role = 'admin'`)
- ⚠️ อย่าใช้ `SELECT *` — ระบุ column ที่ต้องการเท่านั้น
- ⚠️ ตอบ 404 (ไม่ใช่ 403) เมื่อ object ไม่มีหรือไม่ใช่เจ้าของ เพื่อไม่ leak การมีอยู่ของ object
- ⚠️ ป้องกัน mass assignment: ระบุ field ที่รับจาก body เป็น allowlist อย่างชัดเจน

### Input Validation (`docs/secure/11_input_validation.md`)
- ฝั่ง Backend ต้อง validate schema ก่อนเข้า DB (อย่าใช้แค่ Flutter validator):
  - `sport_id`: UUID format + FK exists in `sports`
  - `name`: ความยาว 3–60 ตัวอักษร
  - `description`: สูงสุด 500 ตัวอักษร
  - `lat`: numeric range -90 ถึง 90
  - `lng`: numeric range -180 ถึง 180
  - `capacity`: integer 2–30
  - `status`: enum allowlist `['pending','confirmed','cancelled','rejected']`
  - `role`: enum allowlist `['member','admin']`
  - `cancelled_by`: enum allowlist `['user','owner','system']`
  - `cancel_reason`: สูงสุด 200 ตัวอักษร
- DB constraints (CHECK, VARCHAR length, FK) เป็น defense layer สำรอง (เพิ่มใน schema แล้ว)

### Rate Limiting (`docs/secure/03_rate_limiting_resource_exhaustion.md`)
- ใช้ Redis rate limiter ที่มีอยู่ (`middleware/rate-limiter.js`) สำหรับ endpoint ใหม่:
  - สร้างก๊วน: `userLimiter` (เช่น 10/hour ต่อ user)
  - จอง session: `userLimiter` (เช่น 20/hour ต่อ user)
  - ยกเลิกการจอง: `defaultRateLimiter`
  - บล็อกผู้ใช้: `strictRateLimiter` (เช่น 10/hour ต่อ admin)
  - ค้นหา/กรองรายการ: `ipLimiter` (300/min public read)
- ใช้ `idempotencyMiddleware` สำหรับการสร้างก๊วนและการจอง เพื่อป้องกัน duplicate submit
- ใช้ `clampPagination(limit, page)` สำหรับ list endpoints (limit ≤ 100)

### Session/Token Security (`docs/secure/08_session_token_security.md`)
- ⚠️ ปัจจุบัน backend ใช้ `x-user-id` header ที่ปลอมได้ (T1, T2) — ฟีเจอร์นี้ต้องออกแบบให้ทำงานได้กับระบบปัจจุบัน แต่ต้องระบุว่าเมื่อ migrate ไป JWT ตามแผน 08/09 แล้วต้องใช้ signed identity
- ในระหว่างนี้: App Layer บังคับสิทธิ์ทั้งหมด (ตามรูปแบบที่ใช้ในระบบอื่น)
- เมื่อแผน 08/09 implement แล้ว: เปลี่ยนไปใช้ signed token + server-side ownership check

### Google Maps API Key (`docs/secure/google_maps_key_restriction_guide.md`)
- ❌ ห้าม hardcode API key ใน source code (พบใน git history แล้ว — `AIzaSyB_cex2WRkdTKElFJ-Cjgsfhm0kk1AZkcQ`)
- ✅ ใช้ dart-define / `config/*.json` สำหรับ API key
- ✅ จำกัด key ใน Google Cloud Console: iOS apps, bundle ID `com.example.treeLawZoo`, APIs: Maps SDK for iOS เท่านั้น
- ✅ แยก key ตาม environment (dev/staging/prod)
- ✅ ตั้ง billing alerts ใน Google Cloud Console
- Dev: ใช้ OSM + flutter_map (ไม่ต้องใช้ key)

### SSRF Prevention (`docs/secure/16_ssrf.md`)
- หากมี server-side outbound request (เช่น geocoding, place search):
  - ใช้ safe-http client ที่มี timeout, redirect policy, DNS/IP validation
  - บล็อก private IP / metadata endpoint (`169.254.169.254`, `127.0.0.1`, `10.x`, `192.168.x`)
  - URL allowlist สำหรับ outbound domain
- หากทำ client-side (Flutter → Google Maps SDK โดยตรง): ความเสี่ยงต่ำกว่า แต่ต้อง validate input ฝั่ง client

### Logging & Audit (`docs/secure/05_logging_audit_monitoring.md`)
- Security events ที่ต้อง log:
  - สร้างก๊วน (who, group_id, sport_id)
  - จอง session (who, session_id, status)
  - อนุมัติ/ปฏิเสธการจอง (admin_id, booking_id, action)
  - ยกเลิกการจอง (who, booking_id, cancelled_by, reason)
  - บล็อกผู้ใช้ (admin_id, blocked_user_id, group_id, reason)
  - ปลดบล็อกผู้ใช้ (admin_id, blocked_user_id, group_id)
- ใช้ structured logging พร้อม timestamp, request ID, user ID, severity level
- ห้าม log ข้อมูลอ่อนไหว (PII, token, พิกัดผู้ใช้แบบละเอียด)

### Least Privilege (`docs/secure/12_least_privilege.md`)
- ⚠️ ปัจจุบัน role `admin` กว้างเกินไป (L1) — ผู้ดูแลระบบที่เพิ่มหมวดกีฬาไม่ควรจำเป็นต้องเข้าถึง ERP/HR/Finance
- ในรอบแรก: ตรวจสิทธิ์ `user.role == 'admin'` ฝั่ง App + Backend `requireRole('admin')` สำหรับเพิ่มหมวดกีฬา
- อนาคต: แยก permission `fitness.sports.manage` ออกจาก `admin` เมื่อระบบ permission แบบ fine-grained พร้อมใช้งาน
- แอดมินของก๊วน (`fitness_group_members.role = 'admin'`): จัดการก๊วนของตนเท่านั้น ไม่เกี่ยวกับ role ระบบ

### Infrastructure Integration (`docs/infrastructure/architecture_analysis.md`)
- ใช้ Redis middleware ที่มีอยู่: rate limiting, idempotency, cache-aside
- Cache รายการก๊วน: ใช้ `cacheAside()` pattern เหมือนระบบ video (key: `fitness:groups:${sport_id}:${page}`, TTL ตาม `TTL.DEFAULT`)
- ใช้ BullMQ queue สำหรับ notification delivery (booking confirmed/cancelled) เพื่อไม่ block request
- Pagination: `clampPagination(limit, page)` ทุก list endpoint

## Milestones (ส่งมอบเป็นขั้น ๆ)
1) นำทาง + Drawer + หน้ารายการ/รายละเอียด + หมวดกีฬาเริ่มต้น + CTA เข้าร่วมพร้อม redirect (MVP)
2) ตัวกรองสถานที่ + ค้นหา + คำนวณระยะทางเบื้องต้น (Geolocator)
3) มุมมองแผนที่ (Map SDK) + Marker + สรุปก๊วนจาก Marker
4) แชทก๊วน: สร้าง/เชื่อมห้องแชท, จำกัดสิทธิ์เฉพาะสมาชิก, badge แจ้งเตือน
5) QA/Telemetry: event สำหรับ view/join/filter; test flows (Maestro)

## เกณฑ์ยอมรับงาน (Acceptance Criteria)
- เมนู “หาเพื่อนออกกำลังกาย” อยู่ใน Drawer > ชุมชน และเปิดเข้าได้
- ผู้ใช้ไม่ล็อกอินสามารถเปิดดูรายการ/รายละเอียดได้ แต่เมื่อกด “เข้าร่วม” จะถูกพาไป Login และถูกพากลับมาหน้าเดิมหลังสำเร็จ
- รายการมีหมวดกีฬาเริ่มต้น (63 ประเภทพร้อม emoji icon) + ปุ่ม "+ เพิ่มหมวดหมู่" แสดงเฉพาะแอดมินก๊วน/ผู้ดูแลระบบ; ผู้ใช้ทั่วไปเห็น "เสนอหมวดหมู่”
- ตัวกรองสถานที่/รัศมีใช้งานได้ (เมื่ออนุญาตตำแหน่ง)
- มุมมองแผนที่ทำงานได้ แสดง Marker และกดไปหน้ารายละเอียดได้
- สมาชิกก๊วนเปิดแชทก๊วนได้ ผู้ที่ไม่เป็นสมาชิกเข้าแชทไม่ได้
- ผู้ใช้ที่ล็อกอินสามารถ “สร้างก๊วน” ได้ตามสิทธิ์ และแก้ไขได้เฉพาะแอดมินของก๊วน
- Dev build ใช้แผนที่จากผู้ให้บริการไม่มีค่าใช้จ่าย และสามารถสลับไป Google Maps ผ่าน config/env
- Toggle การอนุมัติการจองแสดงในหน้าสร้างก๊วน (ค่าเริ่มต้น: ปิด = ยอมรับอัตโนมัติ)
- เมื่อจองสำเร็จ ระบบแจ้งเตือนผู้จอง (headsector), ถ้ายกเลิกให้แจ้งเจ้าของก๊วน; ถ้าเจ้าของยกเลิกรอบ/ก๊วน ให้แจ้งผู้จองทั้งหมด
- ป้องกันการจองซ้ำซ้อนตามช่วงเวลา หากทับซ้อนต้องอธิบายเหตุผลและไม่อนุญาต
- หน้ารายละเอียดการจองมีปุ่ม “ยกเลิกจอง”; เจ้าของก๊วนเปิด dialog จากโปรไฟล์ผู้จองเพื่อดูประวัติและ “บล็อกผู้ใช้” ได้
- Repository ดึง `userId` จาก `ServiceLocator.instance.currentUser?.id` เท่านั้น ไม่ใช้ `_client.auth.currentUser` (ตาม `auth_data_guidelines.md`)
- Backend endpoint ใช้ `req.userId` ไม่ใช่ `req.body.userId`; ตรวจ ownership ก่อนอ่าน/แก้ไข booking และ blocklist (ป้องกัน BOLA)
- DB schema มี CHECK constraints สำหรับ enum fields และ numeric range สำหรับ lat/lng
- Endpoint ใหม่มี rate limiter และ idempotency middleware
- Google Maps API key ไม่ถูก hardcode ใน source code (ใช้ dart-define/config)
- Security events (สร้างก๊วน, จอง, ยกเลิก, บล็อก) ถูก log แบบ structured logging
- กด "เข้าร่วมก๊วน" สร้าง booking โดยตรง (ไม่มีขั้นตอนสมัครสมาชิกแยก) และ `fitness_group_members` ถูก upsert อัตโนมัติในธุรกรรมเดียวกัน
- `book_fitness_session()` RPC ป้องกันทั้งการจองซ้ำ (`UNIQUE`), เกิน capacity (`FOR UPDATE`), และจองซ้อนเวลา (`check_booking_overlap()`) แบบ atomic
- Migration เพิ่ม `room_type`/`room_ref_id` ใน `chat_rooms` สำเร็จ และ `participant_ids` sync ถูกต้องเมื่อสมาชิก join/leave
- Headsector แจ้งเตือนการจอง/อนุมัติ/ยกเลิกทำงานผ่าน WebSocket real-time (ไม่ใช่ polling) และปรากฏใน `home_header_section.dart`
- Booking `pending` ที่ค้างเกิน 24 ชั่วโมงหรือใกล้เวลาเริ่ม session 1 ชั่วโมง ถูก auto-reject โดยระบบ
- ข้อเสนอหมวดกีฬาใหม่ (`sports.status='pending'`) ปรากฏในรายการรออนุมัติของผู้ดูแลระบบ และ admin สามารถกำหนด emoji icon ได้ตอนอนุมัติ
- `sports.icon` แสดงผลใน sport chip, การ์ดก๊วน, dropdown สร้างก๊วน, และรายการรออนุมัติ

## บันทึกปัญหาและวิธีแก้ไขระหว่าทดสอบ (Troubleshooting Notes)

### 1. 42501 `new row violates row-level security policy for table "fitness_groups"`
- สาเหตุ: Migration `20260803111500_fitness_buddies_schema.sql` เปิด RLS และสร้างแค่ SELECT policy (`..._select_all`) แต่ไม่มี INSERT/UPDATE/DELETE policy; ทำให้ `INSERT` ล้มเหลว
- วิธีแก้: สร้าง `supabase/migrations/20260806120000_fitness_buddies_rls_writes.sql` เพิ่ม `FOR ALL USING (true) WITH CHECK (true)` ให้ `sports`, `fitness_groups`, `fitness_group_sessions`, `fitness_group_members`, `fitness_group_bookings`, `fitness_group_blocklist`, `chat_rooms` พร้อม `NOTIFY pgrst, 'reload schema'`
- หลักการ: โปรเจกต์ไม่ใช้ Supabase Auth จึงใช้ App-Layer enforcement แบบ Phase 1

### 2. 42703 `column "room_ref_id" of relation "chat_rooms" does not exist`
- สาเหตุ: Migration `20260803111500_fitness_buddies_schema.sql` เพิ่ม `room_type`/`room_ref_id` ภายใน `DO $$ IF NOT EXISTS (room_type ...)` ซึ่งตรวจเฉพาะ `room_type`; แต่ `room_type` มีอยู่แล้วจาก migration แชทเก่า (`20260513133000_chat_consultation_phase_1.sql`) ทำให้ `room_ref_id` ไม่ถูกสร้าง
- นอกจากนี้ `chat_rooms.id` เป็น `TEXT` ส่วน `fitness_groups.id` เป็น `UUID`; trigger เดิมสร้าง id ไม่สอดคล้องกับชนิดข้อมูล
- วิธีแก้:
  - `supabase/migrations/20260806121500_fix_chat_rooms_room_ref_id.sql` เพิ่ม `room_ref_id UUID` และ index
  - `supabase/migrations/20260806122500_update_create_fitness_group_side_effects.sql` ปรับ trigger ให้ `v_room_id := 'group_' || NEW.id::text` แล้ว INSERT `chat_rooms(id, room_type='fitness_group', room_ref_id=NEW.id)`

### ข้อควรระวังเพื่อป้องกันการเกิดซ้ำ
- หลีกเลี่ยงการเพิ่มหลายคอลัมน์ภายใต้เงื่อนไข `IF NOT EXISTS` เดียว; ให้ใช้ `ADD COLUMN IF NOT EXISTS` แยกคอลัมน์หรือตรวจเงื่อนไขเฉพาะคอลัมน์นั้น
- ตรวจชนิดข้อมูลของ `chat_rooms.id` ทุกครั้งที่สร้าง/อ้างอิง (TEXT) เนื่องจากไม่ใช่ UUID
- หลัง apply migration ให้ `NOTIFY pgrst, 'reload schema'` เพื่อ PostgREST โหลด schema cache ใหม่

## คำถามเปิด (เพื่อจัดลำดับรายละเอียด)
- กติกา moderation สำหรับก๊วนที่สร้างใหม่ (รายงาน/ปิดก๊วน/อัปเกรดเป็นแอดมิน)
- ต้องการผูกปฏิทิน/การแจ้งเตือนงานนัดหมายไหม (เฟสถัดไป)?
