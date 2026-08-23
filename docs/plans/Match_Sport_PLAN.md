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
  - รายการก๊วน (การ์ด): รูปสนาม/ปก (thumbnail), ชื่อก๊วน, กีฬา (emoji + ชื่อ), badge เพศที่เชิญชวน (ช./ญ./เสรี), คำอธิบาย 2 บรรทัด, พื้นที่ (จังหวัด/อำเภอ), **จำนวนว่าง (capacity − member_count)**, รอบนัดถัดไปสูงสุด 3 รอบ, ปุ่ม CTA (เข้าร่วมก๊วน / เข้าร่วมแล้ว / เพิ่มรอบนัดสำหรับแอดมิน)
  - ค้นหาและตัวกรอง: รวมใน dialog เดียวเปิดจากปุ่ม search ใน top bar — มีช่องค้นหาก๊วน/สถานที่, จังหวัด, อำเภอ, และ checkbox "เฉพาะก๊วนที่เข้าร่วมได้ทันที" (กรองเอาก๊วนส่วนตัวที่ต้องรออนุมัติออก; ก๊วนส่วนตัวยังแสดงในรายการเปิดรับตามปกติ)
  - ปุ่ม toggle แผนที่ (เปิด/ปิด มุมมองแผนที่)
- หน้า “แผนที่”
  - แสดง Marker ของก๊วนตามตัวกรอง, คลิก Marker เปิดแผ่นสรุปและนำทางไปหน้ารายละเอียด
- หน้า “รายละเอียดก๊วน” (เปิดเป็น Bottom Sheet `sport_club_page.dart`)
  - Header: ชื่อก๊วนกึ่งกลาง
  - รายการรอบนัด: แต่ละรอบแสดงช่วงวันเวลา (`ห้วง: ...`); แอดมินปัดซ้ายเพื่อเปิดปุ่ม **“แก้ไข”** และ **“ยกเลิก”**
  - แถวจำนวนสมาชิก: `เข้าร่วมแล้ว N คน · ว่าง: N คน` (capacity − member_count) — ไม่มีปุ่ม “จัดการ” แยกแล้ว
  - รายชื่อสมาชิก: avatar, ชื่อ-นามสกุล, บทบาท (ผู้ดูแล/สมาชิก), สถานะ (เข้าร่วมแล้ว/หยุดพัก); แอดมินปัดซ้ายเพื่อเปิดเมนูจัดการ และผู้ที่ถูกบล็อกต้องไม่อยู่ใน section นี้
  - คำขอรออนุมัติ: แสดงเป็น section แยกเหนือรายชื่อสมาชิกสำหรับแอดมิน และปัดซ้ายเพื่ออนุมัติ/ปฏิเสธ/บล็อก
  - Section “ถูกบล็อก”: แสดงแยกจากสมาชิก เฉพาะเจ้าของก๊วนและ admin Sheserved เท่านั้น
  - CTA: “เข้าร่วมก๊วน” หรือ “เข้าร่วมก๊วนแล้ว”

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
- `fitness_groups` (id, sport_id, name VARCHAR(60), description VARCHAR(500), province, district, lat DOUBLE PRECISION CHECK(lat BETWEEN -90 AND 90), lng DOUBLE PRECISION CHECK(lng BETWEEN -180 AND 180), requires_owner_approval BOOLEAN DEFAULT false, cover_image_url VARCHAR(500), venue_photo_url VARCHAR(500), gender_preference VARCHAR(10) DEFAULT 'any' CHECK(gender_preference IN ('male','female','any')), created_by UUID REFERENCES users(id), created_at TIMESTAMPTZ DEFAULT now())
  - **นิยาม “ก๊วนส่วนตัว”:** คือก๊วนที่ `requires_owner_approval = true` — ยังแสดงในรายการเปิดรับเหมือนก๊วนทั่วไป แต่ผู้เข้าร่วมต้องรอเจ้าของก๊วนอนุมัติก่อนเข้าร่วม (ไม่ใช้ฟิลด์ `visibility` แยกอีกต่อไป; `public`/`private` เป็นสิ่งเดียวกันกับ toggle อนุมัติ)
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
- เมื่อ booking แรกถูกสร้าง RPC ปัจจุบันยัง **upsert** `fitness_group_members` (`role='member', is_active=true`) ทั้งกรณี `pending` และ `confirmed`; แต่ App Layer จะถือว่า “เข้าร่วมแล้ว” เฉพาะ admin ของก๊วนหรือผู้ที่มี booking `confirmed` อย่างน้อยหนึ่งรายการเท่านั้น
- booking `pending` ของก๊วนที่ต้องอนุมัติ: แสดง CTA “รออนุมัติ”, อยู่เฉพาะ section คำขอรออนุมัติ, ไม่แสดงในรายชื่อ/จำนวน “เข้าร่วมแล้ว” และไม่แสดงก๊วนเป็น joined ของผู้ขอ
- **ออกจากก๊วน:** ตั้ง `fitness_group_members.is_active = false` และยกเลิก booking ที่ `pending`/`confirmed` ทั้งหมดของผู้ใช้ในก๊วนนั้นแบบ cascade (`status='cancelled', cancelled_by='user'`) ภายใน transaction เดียว
- สิทธิ์เข้าแชทกลุ่มใน App Layer: `isGroupMember()` ต้องพบ membership active, ไม่ถูกบล็อก และเป็น admin หรือมี booking `confirmed`
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
- Sync `participant_ids`: trigger `sync_fitness_chat_participants()` ปัจจุบัน sync จาก `fitness_group_members.is_active=true`; App Layer จึงต้องตรวจ confirmed/admin ซ้ำก่อนเปิดแชท — งาน DB follow-up คือปรับ trigger ให้รวมเฉพาะ admin หรือผู้มี booking `confirmed` และให้ booking status update trigger sync ห้องอีกครั้ง
- ⚠️ Tech debt เดิมที่ต้องรับทราบ: `chat_messages.sender_id REFERENCES auth.users(id)` อ้าง Supabase Auth ที่ไม่ได้ใช้งานจริงในโปรเจกต์นี้ — ไม่แก้ในรอบนี้ แต่ FK นี้จะไม่ enforce ความสัมพันธ์กับ `public.users.id` จริง (ความเสี่ยงเดิมที่มีอยู่แล้วในระบบ)

### Data Integrity Guards (ป้องกัน Race Condition ระดับ DB)
- **ป้องกันจองซ้ำ:** `UNIQUE(session_id, user_id)` บน `fitness_group_bookings` (เพิ่มใน schema แล้ว)
- **ป้องกันเกิน capacity:** สร้าง Postgres function `book_fitness_session(p_session_id, p_user_id)` ทำงานใน transaction เดียว:
  1. `SELECT ... FOR UPDATE` ล็อกแถว `fitness_groups` ของ session นั้น
  2. นับสมาชิก `is_active=true` ปัจจุบันเทียบกับ capacity เป้าหมาย
  3. ถ้าเกิน → return error `GROUP_FULL`
  4. ถ้าไม่เกิน → insert/reactivate booking + upsert `fitness_group_members` ในธุรกรรมเดียว
- **ข้อควรระวังจาก Approval Filtering Regression:** ห้ามใช้ `fitness_group_members.is_active=true` เพียงอย่างเดียวเพื่อแสดงผลว่าเข้าร่วมแล้ว เพราะ RPC สร้างแถวนี้ตั้งแต่สถานะ `pending`; UI/query ต้องตรวจ `role='admin'` หรือ booking `status='confirmed'` ร่วมด้วย
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
| `fitness_groups` | `USING(true)` (ก๊วนทั้งหมดแสดงในรายการเปิดรับ รวมก๊วนส่วนตัว) | App Layer ตรวจสิทธิ์: created_by หรือ admin ของก๊วน |
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
  - การจองและการอนุมัติ: Toggle “ก๊วนส่วนตัว (ต้องให้เจ้าของก๊วนอนุมัติก่อนจึงมีผลต่อการจอง)” — ค่าเริ่มต้น: ปิด = ก๊วนเปิด (ยอมรับอัตโนมัติ); เปิด = ก๊วนส่วนตัว (รออนุมัติ) — ฟิลด์เดียวนี้คือตัวกำหนดสถานะก๊วนส่วนตัว ไม่มีฟิลด์ visibility แยก

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
  2. ปุ่ม "เพิ่มรอบนัด" ในการ์ดก๊วน หรือเมื่อไม่มีรอบนัดในการ์ด (เฉพาะแอดมินของก๊วนนั้น) → เรียก `_showCreateSessionSheet(groupId)` ใน `sport_club_page.dart`
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
  - `lib/features/community/find_buddies/presentation/pages/sport_club_page.dart` — `_showCreateSessionSheet()`, ปุ่ม "เพิ่มรอบนัด"/"เข้าร่วมก๊วน"
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
  - `lib/features/home/presentation/widgets/home_header_section.dart`: เพิ่ม branch ใหม่ `item['type'] == 'fitness_booking'` ใน `combinedItems` (ตาม pattern ของ `donation_update`/`yield_way`) พร้อม callback `onFitnessBookingAlertTapped` นำไปหน้า `/community/sport-club/booking/:id` (มี alias เดิม `/community/find-buddies/booking/:id` ชั่วคราว)
  - แสดงเป็นฟีดใหม่→เก่า คลิกเข้าหน้า "รายละเอียดการจอง"
- **Timeout สำหรับ pending booking:** ถ้า booking สถานะ `pending` ไม่ได้รับอนุมัติภายใน 24 ชั่วโมง หรือถึงเวลาก่อนเริ่ม session 1 ชั่วโมง (แล้วแต่ถึงก่อน) ระบบ auto-reject (`status='rejected', cancelled_by='system'`) ผ่าน BullMQ delayed job ที่ enqueue ตอนสร้าง booking (สอดคล้องกับ `architecture_analysis.md` ที่ใช้ BullMQ queue อยู่แล้ว) และแจ้งเตือนทั้งผู้จองและเจ้าของก๊วนผ่าน event `fitness_booking_status` ด้านบน
- ป้องกันการจองซ้ำซ้อน: ก๊วนเปิด (`requires_owner_approval=false`) ตรวจผ่าน `check_booking_overlap()` RPC (ดู Data Integrity Guards) ในขั้นตอนขอร่วมก๊วน; ก๊วนส่วนตัว (`requires_owner_approval=true`) ให้สร้างคำขอ `pending` ก่อน แล้วตรวจ overlap ตอนแอดมินอนุมัติผ่าน `approve_fitness_session_booking()` RPC เพื่อไม่ให้คำขอค้างถูกตัดด้วย `OVERLAP_BOOKING` ตั้งแต่ต้น
- บล็อกผู้ใช้: แอดมินก๊วนสามารถบล็อกจาก swipe ของสมาชิกหรือผู้ขอ pending (ห้ามจองก๊วนนี้); เจ้าของก๊วน/admin Sheserved ดูรายชื่อใน section “ถูกบล็อก” และปัดซ้ายเพื่อปลด

## อนุมัติคำขอเข้าร่วม (Owner Approval UI — ปรับเป็น Swipe)
- ทริกเกอร์เดิมคือปุ่ม "จัดการ" ในรายละเอียดก๊วน แต่ปุ่มนี้ถูกยกเลิกแล้วตาม Phase 8
- ปัจจุบัน admin เห็น section **"คำขอรออนุมัติ"** แยกเหนือรายชื่อสมาชิกใน `_showGroupDetailSheet()`; ผู้ที่มีเฉพาะ booking `pending` ไม่ถือว่าเข้าร่วมแล้ว
- แต่ละรายการแสดง avatar, ชื่อ และจำนวนรอบที่ขอ จากนั้นปัดซ้ายเพื่อเปิด **อนุมัติ / ปฏิเสธ / บล็อก**
- อนุมัติหรือปฏิเสธ: เปิด dialog ให้เลือก booking pending เป็นรายรอบ แล้วเรียก `approveBooking()`/`rejectBooking()` เดิม; เมื่อเสร็จแล้ว refresh ด้วย `setSheetState()`
- Blocklist: `blockUser()` upsert blocklist แล้วเรียก `leaveGroup()` เพื่อตั้งสมาชิก inactive และยกเลิก booking `pending/confirmed`; ผู้ถูกบล็อกจึงถูกนำออกจากทั้ง section pending และ “เข้าร่วมแล้ว”
- Repository/เมธอดที่ใช้ (Flutter):
  - `listGroupPendingBookings(groupId)` → ดึง pending booking ของทุก session ในก๊วน พร้อมข้อมูล user/session แล้ว group ตามผู้ใช้ฝั่ง client
  - `approveBooking({ bookingId, ownerId })` → เรียก RPC `approve_fitness_session_booking()` เพื่ออัปเดตสถานะเป็น `confirmed` พร้อมตรวจ overlap และสิทธิ์แอดมิน
  - `rejectBooking({ bookingId, ownerId, reason? })` → อัปเดตสถานะเป็น `rejected` เฉพาะแถวที่ยัง `pending` และบันทึก `cancelled_by='owner'` พร้อม `cancel_reason` ถ้ามี
- รอบนัดที่มีอยู่: admin ปัดซ้ายแต่ละรอบเพื่อเปิด **แก้ไข / ยกเลิก**; ผู้ใช้ทั่วไปไม่มี action pane
- Realtime/WebSocket: เมื่อเชื่อมต่อให้ emit event `fitness_booking_status` ไปยังผู้จองเมื่ออนุมัติ/ปฏิเสธสำเร็จ

## UX Completeness เพิ่มเติม
- **Push Notification (นอกแอป):** รอบแรกไม่ทำ — Headsector ทำงานเฉพาะตอนแอปเปิดอยู่ (WebSocket only) ผู้ใช้ที่ปิดแอปจะไม่เห็นแจ้งเตือนจนกว่าจะเปิดแอปใหม่ (ออกแบบ `payload` ของ event ไว้ล่วงหน้าให้ขยายไปต่อ FCM/APNs ได้ในเฟสถัดไปโดยไม่แก้ schema)
- **Cover image ก๊วน:** ใช้คอลัมน์ `fitness_groups.cover_image_url` (เพิ่มใน schema แล้ว) กับ Supabase Storage bucket ใหม่ `fitness-group-covers` (public read, insert/update เฉพาะ owner/admin ของก๊วนผ่าน storage RLS policy)
- **ภาพถ่ายสนาม:** ใช้คอลัมน์ `fitness_groups.venue_photo_url` กับ Supabase Storage bucket ใหม่ `fitness-group-venues` (public read, insert/update เฉพาะ owner/admin ของก๊วนผ่าน storage RLS policy เช่นเดียวกับ cover image) — แสดงในหน้ารายละเอียดก๊วนเพื่อให้ผู้เข้าร่วมเห็นสภาพสนามจริงก่อนตัดสินใจเข้าร่วม
- **เพศที่เชิญชวนเข้าร่วม:** ใช้คอลัมน์ `fitness_groups.gender_preference` (`'male'|'female'|'any'`, ค่าเริ่มต้น `'any'`) แสดงเป็น badge ในการ์ดรายการก๊วนและหน้ารายละเอียด — เป็นข้อมูลประกอบการตัดสินใจเท่านั้น ไม่บังคับกรองสิทธิ์การจอง/เข้าร่วมระดับระบบในรอบแรก
- **Province/District:** ใช้ free-text VARCHAR ต่อไปในรอบแรก (ตรวจสอบแล้วไม่มี master table province/district กลางในระบบที่ reuse ได้) — มี index `(sport_id, province, district)` รองรับการกรองแล้ว
- **ก๊วนส่วนตัว = ต้องอนุมัติก่อนเข้าร่วม:** ไม่มีฟิลด์ `visibility` แยก — ก๊วนทุกก๊วน (รวมก๊วนส่วนตัว) แสดงในรายการค้นหาทั่วไป; ความต่างอยู่ที่ `requires_owner_approval` ซึ่งถ้าเปิด ก๊วนนั้นคือ “ก๊วนส่วนตัว” และผู้เข้าร่วมต้องรอเจ้าของอนุมัติก่อนเข้าร่วม
- **สิทธิ์แก้ไข `requires_owner_approval`:** เฉพาะ `fitness_group_members.role='admin'` ของก๊วนนั้นแก้ไขได้ การเปลี่ยนค่าไม่มีผลย้อนหลังกับ booking ที่มีสถานะอยู่แล้ว มีผลกับ booking ใหม่เท่านั้น

## ไม่ใช่ขอบเขต (รอบแรก)
- ระบบนัดหมายซับซ้อน (เช่น วนรายสัปดาห์พร้อมกติกา), ระบบเช็คอิน, คะแนนความน่าเชื่อถือ
- ระบบชำระเงิน/จองสนาม

## ความปลอดภัยและสิทธิ์
- อ่านข้อมูล: public (ทุกก๊วนแสดงในรายการเปิดรับ รวมก๊วนส่วนตัว)
- สร้างก๊วน: ผู้ใช้ที่ล็อกอินทุกคน
- แก้ไข/จัดการก๊วน: เฉพาะแอดมินของก๊วน
- เพิ่ม/แก้ไขหมวดหมู่กีฬา: เฉพาะแอดมินก๊วน/ผู้ดูแลระบบ
- เข้าร่วม: ผู้ใช้ล็อกอินเท่านั้น
- แชท: เฉพาะสมาชิกก๊วน (ตรวจสิทธิ์ก่อนเข้าห้อง)
- แผนที่: ระหว่างพัฒนาใช้ผู้ให้บริการไม่มีค่าใช้จ่าย (OSM + flutter_map); เตรียม config สำหรับสลับ Google Maps ได้โดยไม่แก้โค้ด
- การบล็อก: ผู้ใช้ที่ถูกบล็อกจะถูกถอดจากสมาชิก active และยกเลิก booking `pending/confirmed` ผ่าน `leave_fitness_group`; ไม่สามารถจองใหม่ในก๊วนนั้นได้จนกว่าจะปลดบล็อก
- การมองเห็นรายชื่อผู้ถูกบล็อก: เฉพาะ `fitness_groups.created_by` (เจ้าของก๊วน) หรือผู้ใช้ `users.role='admin'` ของ Sheserved; UI และ repository `listBlockedUsers(..., requesterUserId)` ตรวจสิทธิ์ก่อนคืนข้อมูลโปรไฟล์
- ข้อจำกัด security ปัจจุบัน: เนื่องจากระบบยังไม่ใช้ Supabase Auth และ RLS เป็น `USING(true)` การจำกัดนี้เป็น App-Layer guard; เมื่อ migrate auth ตาม Phase 2/3 ต้องย้าย enforcement ไป RLS/RPC ฝั่ง server

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
- Toggle “ก๊วนส่วนตัว” แสดงในหน้าสร้างก๊วน (ค่าเริ่มต้น: ปิด = ก๊วนเปิด ยอมรับอัตโนมัติ; เปิด = ก๊วนส่วนตัว ต้องรออนุมัติ) — ฟิลด์เดียวนี้คือตัวกำหนดสถานะก๊วนส่วนตัว และก๊วนส่วนตัวยังแสดงในรายการเปิดรับตามปกติ
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

## การเปลี่ยนแปลง UI/Flow ล่าสุด (2026-08-23)
- การ์ดรายการก๊วน: แสดงเฉพาะ **จำนวนว่าง** (`capacity − member_count`) ไม่แสดงจำนวนสมาชิกทั้งหมด; รูปสนาม/ปก, กีฬา, badge เพศ, คำอธิบาย, พื้นที่, รอบนัดถัดไปสูงสุด 3 รอบ
- CTA ในการ์ด:
  - ผู้ใช้ทั่วไป: ปุ่ม "เข้าร่วมก๊วน" (เปิดรายการรอบนัดให้เลือก) หรือ "เข้าร่วมก๊วนแล้ว"
  - ผู้ร้องขอที่ถูกบล็อก: แสดงสถานะ **"รอคิว"** แบบ disabled เพื่อใช้ถ้อยคำสุภาพและป้องกันการส่งคำขอซ้ำ (สถานะภายในยังเป็น `blocked`)
  - แอดมิน: แถวปุ่ม "เข้าร่วมก๊วนแล้ว" + "เพิ่มรอบนัด" ชิดขวา
- แผ่นรายละเอียดก๊วน (Bottom Sheet):
  - รายการรอบนัด: admin ปัดซ้ายเพื่อเปิด **แก้ไข/ยกเลิก**; action ปรับขนาดไอคอนและข้อความด้วย responsive `FittedBox`
  - แถวจำนวนสมาชิก: `เข้าร่วมแล้ว N คน · ว่าง: N คน` ไม่มีปุ่ม "จัดการ" แยกแล้ว
  - Section "คำขอรออนุมัติ" แยกเหนือรายชื่อสมาชิก: admin ปัดซ้ายเพื่อ **อนุมัติ/ปฏิเสธ/บล็อก** และเลือก booking เป็นรายรอบ
  - รายชื่อสมาชิก: avatar, บทบาท, สถานะ; admin ปัดซ้ายเพื่อ **แชท/บล็อก/ถอดออก**, สมาชิกทั่วไปปัดแถวตนเองเพื่อแชท; ผู้ถูกบล็อกถูกกรองออก
  - Section “ถูกบล็อก” แยกต่างหากและเห็นได้เฉพาะเจ้าของก๊วน/admin Sheserved; ปัดรายชื่อไปทางซ้ายเพื่อเปิดปุ่ม “ปลด”
  - นำปุ่ม "จัดการบล็อกลิสต์" และ Blocklist Sheet แยกออกจาก UI
- ไฟล์หลักของหน้า: `lib/features/community/find_buddies/presentation/pages/sport_club_page.dart` (ไม่ใช่ `find_buddies_page.dart`)

## คำถามเปิด (เพื่อจัดลำดับรายละเอียด)
- กติกา moderation สำหรับก๊วนที่สร้างใหม่ (รายงาน/ปิดก๊วน/อัปเกรดเป็นแอดมิน)
- ต้องการผูกปฏิทิน/การแจ้งเตือนงานนัดหมายไหม (เฟสถัดไป)?

## Roadmap ปรับปรุงจากผลวิเคราะห์ Gap (2026-08-22) — เรียงตามความสำคัญ

> ผลตรวจสอบโค้ดจริง ณ 2026-08-23: หน้ารายการ/bottom sheet รายละเอียด/สร้างก๊วน/สร้างรอบนัด/จอง-อนุมัติผ่าน RPC/เสนอ-รีวิวกีฬา/booking detail/WebSocket headsector/migrations/ก๊วนของฉัน/แชท/บล็อก/แชท popup ฝั่ง ChatRoomPage และ swipe actions ในรายละเอียดก๊วนทำครบแล้ว — ช่องว่างที่เหลือคือการทดสอบ E2E (Phase 6) และการทดสอบ regression ตาม Definition of Done

### Phase 1 — ปักหมุดพิกัดตอนสร้างก๊วน + Pagination ✅ เสร็จแล้ว (2026-08-22)
- ปัญหา: ฟอร์ม `create_group_page.dart` ไม่มีการเก็บ `lat/lng` เลย → ก๊วนใหม่ไม่มีพิกัด, มุมมองแผนที่ใน `sport_club_page.dart` ไม่มี marker, ตัวกรองรัศมี (กม.) ไม่ทำงานจริง
- งาน:
  - เพิ่ม MapCard ใน create group: `flutter_map` (OSM) พร้อมพินลากได้ + ปุ่ม "ใช้ตำแหน่งฉัน" (geolocator, opt-in) + แสดงพิกัดสรุป
  - บันทึก `lat/lng` ผ่าน `createGroup()` (คอลัมน์ `fitness_groups.lat/lng` มีอยู่แล้วพร้อม CHECK constraint)
  - Validation: ถ้าเปิดใช้ตัวกรองรัศมี ก๊วนที่ไม่มีพิกัดให้ fallback แสดงตามจังหวัด
  - **Pagination / infinite scroll:** เพิ่ม limit+offset ใน `listGroups()` + `ScrollController` ดึงเพิ่มเมื่อ scroll ใกล้สุด (ปัจจุบันโหลดทั้งหมดในครั้งเดียว)
- สถานะ: ✅ ทำครบ — `MapCard` + ปุ่ม "ใช้ตำแหน่งฉัน" + สรุปพิกัดใน `create_group_page.dart`, ส่ง `lat/lng` ผ่าน `createGroup()`, `listGroups()` รองรับ `limit/offset` (default 50), `sport_club_page.dart` มี `ScrollController` + `_loadMore()` infinite scroll + `_hasMore` flag

### Phase 2 — Join flow สมบูรณ์ ✅ เสร็จแล้ว (2026-08-22)
- **เลือกรอบนัดเอง (ตัดสินใจแล้ว 2026-08-22):** เปลี่ยนปุ่ม "เข้าร่วมก๊วน" จากจองรอบใกล้สุดอัตโนมัติ → เปิด bottom sheet รายการรอบนัดให้ผู้ใช้เลือกรอบก่อน แล้วค่อยเรียก `bookSession()`
- **สถานะ "รออนุมัติ" บน CTA:** ผู้จองก๊วนส่วนตัวที่ booking ยัง `pending` ให้การ์ด/bottom sheet แสดง "รออนุมัติ" (disabled) แทน "เข้าร่วมก๊วนแล้ว"
- **Redirect + intent:** หลัง login สำเร็จ ให้กลับมาที่ก๊วนเดิมพร้อม `intent=join_group` เพื่อเปิด sheet เลือกรอบต่อทันที (ปัจจุบัน redirect กลับแค่ `/community/sport-club` ระดับ list)
- **Draft ฟอร์มสร้างก๊วน:** ถ้าโดนพาไป login ระหว่างกด "บันทึก" ให้ serialize text/scalar fields (ชื่อ, คำอธิบาย, sportId, เพศ, toggle, จังหวัด/อำเภอ, capacity, lat/lng, coverImageUrl, venuePhotoUrl) ลง `SharedPreferences` key `create_group_draft` เป็น JSON — บันทึกเฉพาะตอน redirect ไป login (ไม่ auto-save ทุก keystroke) — restore ใน `initState`/`didChangeDependencies` เมื่อกลับจาก login — ลบ draft ทันทีหลังสร้างสำเร็จหรือ restore แล้ว — ใส่ TTL 1 ชั่วโมงกัน draft ค้าง
- สถานะ: ✅ ทำครบ — `_showSessionPickerSheet()` เปิดรายการรอบนัดก่อนจอง, CTA แสดง "รออนุมัติ" disabled (ไอคอน hourglass) จาก `_myPendingGroupIds`, `_handleIntent()` อ่าน `intent=join_group` เปิด sheet ต่อหลัง login, `_saveDraft()`/`_restoreDraft()`/`_clearDraft()` ใน `create_group_page.dart` (TTL 1 ชม.)

### Phase 3 — แชทก๊วน (Milestone 4 เดิม) ✅ เสร็จแล้ว
- DB side พร้อมแล้ว (trigger สร้าง `chat_rooms` id=`group_<uuid>` ตอนสร้างก๊วน)
- งาน:
  - ปุ่ม "แชทก๊วน" ใน bottom sheet รายละเอียด แสดงเฉพาะสมาชิก `is_active=true`
  - ตรวจสิทธิ์ก่อนเข้าห้อง (ไม่ใช่สมาชิก → ซ่อนปุ่ม/แจ้งเตือน)
  - ตรวจสอบ trigger `sync_fitness_chat_participants()` ว่า sync `participant_ids` ตอน join/leave ครบ
  - Badge จำนวนข้อความใหม่ (ถ้าโครงแชทเดิมรองรับ)
- สถานะ: ✅ แชทก๊วนเปิดผ่าน `showGroupChatPopup()` จาก swipe action ของรายชื่อสมาชิกใน `sport_club_page.dart` และจากปุ่มแชทใน `my_groups_page.dart`; ปุ่มแชทใน `_buildGroupActionButtons()` ถูกย้ายออกตาม Phase 8

### Phase 4 — จัดการก๊วน + หน้าก๊วนของฉัน ✅ เสร็จแล้ว (2026-08-23)
- **แก้ไขก๊วน:** หน้า/sheet แก้ไข (ชื่อ, คำอธิบาย, ภาพ, เพศ, toggle `requires_owner_approval`, พิกัด, capacity) เฉพาะแอดมินก๊วน — เพิ่ม `updateGroup()` ใน repository
- **แก้ไขรอบนัด:** แอดมินแก้ไขเวลาเริ่ม/สิ้นสุด และหมายเหตุของรอบนัดที่มีอยู่แล้ว — เพิ่ม `updateSession()` ใน repository
- **ออกจากก๊วน:** เพิ่ม `leaveGroup()` — ตั้ง `fitness_group_members.is_active=false` + ยกเลิก booking `pending/confirmed` ทั้งหมดแบบ cascade ใน transaction เดียว (RPC) ตามหัวข้อ "เข้าร่วมก๊วน = จองรอบนัด"
- **Blocklist UI:** รายชื่อสมาชิก/pending มี swipe ปุ่มบล็อก; ผู้ถูกบล็อกถูกถอดจากสมาชิก active และย้ายไป section “ถูกบล็อก” ซึ่งมองเห็นเฉพาะเจ้าของก๊วน/admin Sheserved; ปัดแถวผู้ถูกบล็อกเพื่อเปิดปุ่ม “ปลด”; ไม่มีปุ่ม/Blocklist Sheet แยกแล้ว; repository guard อยู่ใน `listBlockedUsers(..., requesterUserId)` และ `book_fitness_session()` RPC ตรวจ blocklist
- **หน้า "ก๊วนของฉัน":** หน้ารวมก๊วนที่ผู้ใช้สร้าง/เข้าร่วม + ประวัติการจองทั้งหมด (ปัจจุบันไม่มีที่ดูรวม — ดูได้เฉพาะ booking detail ทีละรายการ) — เพิ่ม route `/community/sport-club/my-groups`
- **สถานะ:** ✅ ทำครบแล้วตามโค้ดจริง — `updateGroup()`/`updateSession()`/`leaveGroup()`/`blockUser()`/`unblockUser()`/`listBlockedUsers()` พร้อมใช้งาน, มี sheet แก้ไขก๊วนและรอบนัด, section ผู้ถูกบล็อกแบบ swipe, และหน้า `MyGroupsPage` + route `/community/sport-club/my-groups`

### Phase 5 — Auto-reject pending timeout (Supabase scheduled cleanup) ✅ เสร็จแล้ว (2026-08-23)
- **เหตุผลที่เลือกแนวนี้ (Option A):** booking ถูกสร้างจาก Flutter → Supabase RPC โดยตรง ไม่ผ่าน backend request lifecycle การใช้ BullMQ delayed job enqueue ตอนสร้าง booking จะเกิด dual-write risk และเพิ่ม coupling กับ websocket-server โดยไม่จำเป็น DB เป็น source of truth อยู่แล้ว เงื่อนไข timeout ทั้งหมด (`status`, `starts_at`, `created_at`, `requires_owner_approval`) อยู่ในฐานข้อมูล — ให้ DB/RPC จัดการ atomic ปลอดภัยกว่า
- **งาน:**
  - สร้าง RPC `auto_reject_expired_fitness_bookings()` ใน Supabase migration
  - เงื่อนไข reject: `status = 'pending'` และเลย deadline (`created_at + interval '24 hours'` หรือ `starts_at - interval '1 hour'` แล้วแต่เงื่อนไขใดถึงก่อน)
  - update เป็น `status = 'rejected'`, `cancelled_by = 'system'`, `cancel_reason = 'AUTO_TIMEOUT'`
  - ใช้ Supabase scheduled job (`pg_cron` หรือ `pg_net`) เรียก RPC ทุก 5-15 นาที
  - Notification: ✅ ใช้ `pg_notify('fitness_booking_status_updates', ...)` จาก RPC แล้ว `websocket-server` ฟัง `LISTEN` แล้ว broadcast ผ่าน `fitness_booking_status` ไปยังผู้ใช้ที่เกี่ยวข้อง
- หมายเหตุ: ไม่เพิ่ม backend proxy/rate limiting/idempotency ในรอบนี้ — ใช้ RPC + RLS ป้องกันระดับ DB ตาม pattern เดิมของโปรเจกต์ (ดูหัวข้อ Data Integrity Guards)

### Phase 6 — Maestro UI Tests ⏳ รอทำ
- สร้าง test flows ตาม Milestone 5 เดิม:
  - `view_groups.yaml` — เปิดดูรายการก๊วน, สลับหมวดกีฬา, เปิด filter dialog, สลับมุมมองแผนที่
  - `join_group.yaml` — กดเข้าร่วมก๊วน (ต้องล็อกอิน), เลือกรอบนัด, ยืนยันการจอง
  - `create_group.yaml` — สร้างก๊วนใหม่ + สร้างรอบนัดแรก
  - `owner_approval.yaml` — เจ้าของก๊วนปัดคำขอเข้าร่วมเพื่ออนุมัติ/ปฏิเสธ/บล็อก และเลือก booking เป็นรายรอบ
  - `session_swipe_actions.yaml` — admin ปัดรอบนัดเพื่อแก้ไข/ยกเลิก และตรวจ action responsive บนหน้าจอแคบ

---

## Phase 7 — เปลี่ยน UI แชทก๊วนเป็น Popup ลอยเหนือหน้าเดิม ✅ เสร็จแล้ว (2026-08-23)

### เป้าหมาย
แทนที่การ `Navigator.push` เปิด `ChatRoomPage` เต็มหน้า → เปิดเป็น **popup ลอยกลางหน้าจอ** เหนือหน้าปัจจุบัน ผู้ใช้ยังเห็น context ของหน้าก๊วนด้านหลัง ปิดแล้วกลับมาที่เดิมทันทีโดยไม่เสีย scroll position

### ข้อตกลงที่ยืนยันแล้ว (2026-08-23)
| หัวข้อ | การตัดสินใจ |
|---|---|
| ขนาด | **สูง 50% แบบ responsive** — มือถือ: กว้าง 92% สูง 55-60% / แท็บเล็ต-เดสก์ท็อป: `maxWidth` ~480-560px สูง 50-60% |
| ขอบเขต | `sport_club_page.dart` + `my_groups_page.dart` (จุดอื่นในแอปคงเปิดเต็มหน้าเหมือนเดิม) |
| คีย์บอร์ด | **เลื่อน popup ขึ้นด้านบน** — ใช้ `viewInsets.bottom` จัด popup ให้อยู่ในพื้นที่เหนือ keyboard และแตะพื้นที่ว่างของข้อความ/นอกช่องกรอกเพื่อซ่อน keyboard |
| ปุ่มวิดีโอคอล | **ซ่อน** ในโหมด popup (แชทก๊วนเป็นกลุ่มหลายคน วิดีโอคอล 1:1 ไม่เหมาะ) |
| ปิดด้วยแตะนอกพื้นที่ | **เปิดใช้** (`barrierDismissible: true`) |
| header | แสดง **ชื่อก๊วน + จำนวนสมาชิก active** แทนชื่อคู่สนทนาแบบ 1:1 |
| ปุ่มขยายเต็มหน้า | **ไม่ทำ** — popup อย่างเดียว |

### สภาพก่อนปรับปรุง
- เดิม `sport_club_page.dart` `_buildGroupActionButtons()` ใช้ `Navigator.push` เปิด `ChatRoomPage` เต็มหน้า
- เดิม `ChatRoomPage` มี header และ action ที่ออกแบบมาสำหรับ consultation 1:1
- เดิม `my_groups_page.dart` ยังไม่มีปุ่มแชทใน card

### งานที่ต้องทำ

**7.1 ✅ เพิ่ม popup mode ให้ `ChatRoomPage`** (`lib/features/chat/presentation/pages/chat_room_page.dart`)
- เพิ่ม optional params (default = พฤติกรรมเดิมทั้งหมด ไม่กระทบจุดเรียกอื่น):
  - `bool isPopup = false` — ซ่อนปุ่มวิดีโอคอล, เปลี่ยนไอคอน back เป็น `Icons.close`, ลด `toolbarHeight`
  - `String? titleOverride` — ชื่อก๊วน
  - `String? subtitleOverride` — เช่น `"สมาชิก 12 คน"`
  - `String? mentionTargetName` — ชื่อสมาชิกที่เลือกจาก swipe action เพื่อกล่าวถึงในข้อความใหม่; ถ้าเปิดจากรายชื่อตนเองให้เป็น `null`
- `Scaffold(resizeToAvoidBottomInset: !widget.isPopup)` — popup ไม่ย่อซ้ำกับการจัดตำแหน่งเหนือ keyboard ส่วนหน้าเต็มยัง resize ตามปกติ

**7.2 ✅ สร้าง helper `showGroupChatPopup()`** (ไฟล์ `lib/features/community/find_buddies/presentation/widgets/group_chat_popup.dart`)
- signature: `Future<void> showGroupChatPopup(BuildContext context, {required String groupId, required String groupName, int? memberCount, String? mentionTargetName})`
- ใช้ `showDialog(barrierDismissible: true, barrierColor: Colors.black54)`
- คำนวณขนาด responsive จาก `MediaQuery.sizeOf(context)`:
  - `width  = min(size.width * 0.92, 560)`
  - `height = size.height * (size.width < 600 ? 0.58 : 0.55)`
- เลื่อนหนีคีย์บอร์ด: อ่าน `MediaQuery.viewInsetsOf(context).bottom` แล้วใช้ `AnimatedPadding(padding: EdgeInsets.only(bottom: bottomInset))` จัด popup ในพื้นที่เหนือ keyboard
- `ChatRoomPage` ห่อด้วย `ClipRRect(borderRadius: 20)` + `Material(elevation)` และรับ `mentionTargetName` เพื่อแสดงสมาชิกเป้าหมายในข้อความใหม่
- ชื่อ header แสดงรูปแบบ `ก๊วน <ชื่อก๊วน>`

**7.3 ✅ แก้จุดเรียกใน `sport_club_page.dart`**
- แชทก๊วนเปิดผ่าน `showGroupChatPopup(...)` จาก swipe action ของรายชื่อสมาชิก (และปุ่มแชทใน `my_groups_page.dart`)
- **ไม่เรียก `Navigator.pop(ctx)` ก่อนเปิด popup** — popup ลอยเหนือ Bottom Sheet รายละเอียดก๊วน ปิดแล้วกลับมาที่ sheet เดิมทันที
- เมื่อเปิดจากสมาชิกคนอื่น ส่ง `mentionTargetName` เข้า popup; เมื่อเปิดจากแถวตนเองไม่ส่งชื่อเป้าหมาย
- `memberCount` ดึงจาก field ที่ `listGroups()` ใส่มาให้ในแต่ละ group map อยู่แล้ว

**7.4 ✅ เพิ่มปุ่มแชทใน `my_groups_page.dart`** (2026-08-23)
- `_buildGroupCard()` เปลี่ยน `trailing` จาก `Icon(Icons.chevron_right)` เดี่ยว → `Row(mainAxisSize: min)` ที่มี `IconButton(Icons.chat_bubble_outline)` + `chevron_right`
- ทุกก๊วนในหน้านี้ผู้ใช้เป็นสมาชิกอยู่แล้ว จึงแสดงปุ่มแชทได้ทุกใบ
- `listMyGroups()` ไม่มี member count → ส่ง `memberCount: null` → header แสดงแค่ชื่อก๊วน (เพิ่ม count ใน query ภายหลังถ้าต้องการ)

### รายละเอียด UI ข้อความแชทก๊วน (Implementation)
- Header ของ popup แสดง `ก๊วน <ชื่อก๊วน>` และจำนวนสมาชิก active
- แสดงชื่อผู้ส่งในรูปแบบ `ชื่อ + อักษรแรกของนามสกุล` เหนือข้อความและอยู่นอก bubble
- เมื่อเปิดแชทจากสมาชิกเป้าหมาย ข้อความใหม่จะบันทึก mention ในรูปแบบ `@ชื่อ น.\nข้อความ` และแสดง `@ชื่อ น.` อยู่นอก bubble ในแถวเดียวกับ bubble; ฝั่งข้อความของเราอยู่ด้านซ้าย/ขวาตาม layout ที่กำหนด
- เปิดแชทจากแถวของตนเองหรือจากหน้า `my_groups_page.dart` โดยไม่มีเป้าหมาย จะไม่เพิ่ม mention
- เวลาและสถานะอ่าน (`✓`/`✓✓`) แสดงอยู่นอก bubble ใต้ข้อความ
- ข้อความ `อ่านโดย` เปลี่ยนเป็น `<รายชื่อผู้อ่าน> อ่าน` สีเทา
- มีระยะห่างระหว่างชุดข้อความแต่ละชุด 12 px
- Composer ใช้ปุ่มส่งข้อความตลอดเวลาแทนปุ่มอัดเสียง

### ความเสี่ยง / จุดที่ต้องระวัง
- **`Navigator.push` ภายใน `ChatRoomPage`** — โค้ดมี push ไป `ConsultationNoteEditorPage`, `PrescriptionEditorPage`, `pushNamed('/live-vdo')` ซึ่งจะเปิดทับ popup เต็มหน้าจอ แต่ path เหล่านี้เป็นของ consultation ไม่เกิดใน group chat จึงไม่กระทบจริง
- **`_loadInitialData()` ใช้ `rooms.firstWhere((r) => r.id == widget.roomId)`** — ถ้าห้อง `group_<uuid>` ยังไม่ถูก sync เข้า `chat_rooms` จะ throw ทำให้ popup ค้างที่ loading ควรเพิ่ม `orElse` guard
- **`barrierDismissible: true` ขณะพิมพ์** — ผู้ใช้อาจแตะพลาดแล้วข้อความที่พิมพ์ค้างหาย; พฤติกรรมปัจจุบันยังปิด popup เมื่อแตะนอก dialog ตามข้อตกลง
- **การซ่อนคีย์บอร์ด** — แตะพื้นที่ว่างของรายการข้อความหรือแตะนอกช่องกรอกใน dialog จะ `unfocus()` โดยไม่ปิด dialog (กรณีแตะนอก popup จะปิด popup ตาม `barrierDismissible`)
- **ปุ่ม `more_vert` ใน AppBar** — ซ่อนในโหมด popup แล้ว (`actions: null`) เพื่อไม่ให้เปลืองพื้นที่ header
- **แนบรูป/อัดเสียง** — ปุ่มอัดเสียงถูกแทนที่ด้วยปุ่มส่งข้อความใน composer แล้ว; โค้ดอัดเสียงเดิมยังคงอยู่แต่ไม่มีปุ่มเรียกใช้จาก UI ปัจจุบัน ส่วน image picker/bottom sheet ต้องทดสอบว่ากลับมาแล้ว popup ยังอยู่
- **ห้องแชทลอยทับหน้ารายการก๊วน (regression สำคัญ)** — ภาพหน้าจอ `test13` แสดงห้องแชทลอยเหนือนหน้า “หาเพื่อนออกกำลังกาย” แทนที่จะลอยเหนือน bottom sheet รายละเอียดก๊วน ทำให้ผู้ใช้งงและพื้นหลังไม่ถูก dim
  - สาเหตุ: เรียก `ChatRoomPage` ด้วย `Navigator.push` หรือเปิด widget บน `Overlay`/ root navigator โดยไม่มี `Dialog` / modal barrier ทำให้หน้าเดิมยังแสดงอยู่ด้านหลัง หรือใช้ `BuildContext` ผิด (context ของหน้ารายการแทน context ใน sheet) จึงเปิด popup ทับหน้ารายการแทน sheet
  - วิธีแก้: เปิดแชทกลุ่มด้วย `showDialog`/`showGeneralDialog` ผ่าน `showGroupChatPopup()` เท่านั้น ใช้ `barrierColor: Colors.black54` + `barrierDismissible: true` เพื่อให้พื้นหลังถูก dim และย้อนกลับมาที่ bottom sheet ก๊วนเดิมได้ถูกต้อง
  - ข้อห้ามป้องกัน: ห้ามเรียก `ChatRoomPage` โดยตรงด้วย `Navigator.push(MaterialPageRoute(...))` หรือ `Overlay.of(context).insert(...)` จาก `_buildGroupActionButtons()` หรือ `my_groups_page.dart` นอกเหนือจาก helper popup

### Definition of Done
- กด "แชทก๊วน" จาก `sport_club_page` → popup ลอยกลางจอสูง ~50-58% เห็นหน้าก๊วนจางๆ ด้านหลัง
- พิมพ์ข้อความ → popup เลื่อนขึ้นพ้นคีย์บอร์ด ส่งได้ ข้อความขึ้นทันที
- ปิด popup ด้วยปุ่ม X หรือแตะพื้นหลัง → กลับมาที่ bottom sheet ก๊วนเดิม
- กดไอคอนแชทใน `my_groups_page` → popup เดียวกันเปิดได้
- จุดเปิดแชทอื่น (`chat_list_page`, `contact_list_page`, `/chat-room`) ยังเปิดเต็มหน้าเหมือนเดิม ไม่ regression
- `flutter analyze` ผ่านไม่มี error ใหม่

---

## Phase 8 — Redesign Bottom Sheet รายละเอียดก๊วนเป็น Swipe Actions ✅ UI implement แล้ว (2026-08-23)

### เป้าหมาย
แทนที่ Bottom Sheet "จัดการ" ผู้เข้าร่วมรอบนัด (`_showManageSessionSheet`) ด้วย **swipe actions บนรอบนัดและรายชื่อสมาชิกโดยตรง** ใน Bottom Sheet รายละเอียดก๊วน (`_showGroupDetailSheet`) — แอดมินปัดรายการเพื่อเปิดเมนูจัดการ ไม่ต้องเปิด sheet จัดการผู้เข้าร่วมซ้อนอีกชั้น

### ข้อตกลงที่ยืนยันแล้ว (2026-08-23)
| หัวข้อ | การตัดสินใจ |
|---|---|
| ทิศทางสไลด์ | **ปัดซ้าย ปุ่มโผล่ด้านขวา** (`flutter_slidable` `endActionPane` — pattern มาตรฐาน iOS/Android) |
| ปุ่มใน swipe ของรอบนัด (admin) | **แก้ไข** (สีหลัก) + **ยกเลิก** (แดง); action pane responsive และย่อไอคอน/ข้อความอัตโนมัติเมื่อพื้นที่แคบ |
| คำขอรออนุมัติ (pending) | **แยก section "คำขอรออนุมัติ"** เหนือรายชื่อสมาชิก ใน sheet รายละเอียดก๊วนเดียวกัน |
| ผู้ถูกบล็อก | ไม่แสดงใน pending/“เข้าร่วมแล้ว”; แสดงใน section **“ถูกบล็อก”** เฉพาะเจ้าของก๊วนและ admin Sheserved |
| ปุ่มใน swipe ของสมาชิก (admin) | **แชทก๊วน** (ฟ้า) + **บล็อก** (เทา) + **ถอดออกจากก๊วน** (แดง) |
| ปุ่มใน swipe ของสมาชิก (ไม่ใช่ admin) | **แชทก๊วน** (ฟ้า) — แถวอื่นปัดไม่ได้, แถวตัวเองปัดได้แค่แชท |
| ปุ่มใน swipe ของคน pending | **อนุมัติ** (เขียว) + **ปฏิเสธ** (แดง) + **บล็อก** (เทา) |
| ขอบเขตการอนุมัติ | **เลือกรอบนัดก่อนอนุมัติ** — กดอนุมัติแล้วแสดง dialog รายการ booking pending ของผู้ใช้คนนั้น (รายรอบนัด) ให้เลือกอนุมัติ/ปฏิเสธเป็นรายรอบ |
| Bottom Sheet "จัดการ" เดิม | **ยกเลิก** — ลบ `_showManageSessionSheet()` และปุ่ม "จัดการ" ออก |

### สภาพปัจจุบันหลังปรับ UI
- `_showManageSessionSheet(sessionId, groupId)` — **ถูกลบ**; การอนุมัติ/ปฏิเสธผู้เข้าร่วมย้ายมาอยู่ใน section pending ของ Bottom Sheet รายละเอียดก๊วน
- ปุ่ม "จัดการ" ในแถวจำนวนสมาชิก (`_showGroupDetailSheet`) — **ถูกลบ**
- รายชื่อสมาชิก (`listGroupMembers`) แสดงเฉพาะ `is_active=true` — คน pending ถูกดึงแยกด้วย `listGroupPendingBookings(groupId)` แล้ว group ตามผู้ใช้ฝั่ง client
- รายการรอบนัดของ admin ใช้ `Slidable` พร้อม `แก้ไข`/`ยกเลิก`; รายชื่อสมาชิกและ pending ใช้ swipe actions เช่นกัน
- `flutter_slidable: ^4.0.3` มีใน `pubspec.yaml` แล้ว (ตัวอย่างการใช้: `triage_victim_card.dart`, `health_article_comment_item.dart`)

### รายการที่ implement แล้ว

**8.1 ✅ เพิ่ม repository method `listGroupPendingBookings(groupId)`** (`fitness_buddies_repository.dart`)
- ดึง `fitness_group_bookings` ที่ `status='pending'` ของทุกรอบนัดในก๊วน (join `fitness_group_sessions` และ filter ตาม `group_id`) พร้อม user profile (id, first_name, last_name, profile_image_url) และข้อมูลรอบนัด (id, group_id, starts_at, ends_at)
- group by ผู้ใช้ฝั่ง client: 1 คนอาจมีหลาย booking pending หลายรอบ

**8.2 ✅ Section "คำขอรออนุมัติ" ใน `_showGroupDetailSheet`** (เฉพาะ admin เห็น)
- แสดงเหนือ section รายชื่อสมาชิก มีหัวข้อ "คำขอรออนุมัติ" + จำนวน
- แต่ละแถว: avatar + ชื่อ + จำนวนรอบที่ขอ (badge "รออนุมัติ")
- swipe (`endActionPane`): **อนุมัติ** (เขียว) / **ปฏิเสธ** (แดง) / **บล็อก** (เทา)
- กดอนุมัติ/ปฏิเสธ → เปิด dialog รายการรอบนัด pending ของคนนั้นให้เลือกจัดการเป็นรายรอบ (เรียก `approveBooking()`/`rejectBooking()` เดิม) → `setSheetState()` รีเฟรช
- ไม่มีคำขอ → ซ่อน section ทั้งหมด (ไม่แสดงหัวข้อเปล่า)

**8.3 ✅ Swipe actions บนรายการรอบนัด** (admin เท่านั้น)
- ห่อแถวรอบนัดด้วย `Slidable` (`endActionPane`, `motion: ScrollMotion`)
- ปัดซ้ายเพื่อเปิด **แก้ไข** และ **ยกเลิก** ทางขวา
- กด "แก้ไข" เปิด `_showEditSessionSheet()`; กด "ยกเลิก" แสดง dialog ยืนยันก่อนเรียก `cancelSession()`
- ผู้ใช้ทั่วไปเห็นรอบนัดแบบปกติและไม่มี action pane
- ใช้ custom responsive action (`CustomSlidableAction` + `FittedBox`) เพื่อให้ไอคอน/ข้อความปรับขนาดพอดีกับพื้นที่บนหน้าจอแต่ละขนาด

**8.4 ✅ Swipe actions บนรายชื่อสมาชิก** (ทุกคนปัดแถวตัวเองได้, admin ปัดแถวคนอื่นได้)
- ห่อ `ListTile` สมาชิกด้วย `Slidable` (`endActionPane`, `motion: ScrollMotion`)
- **แถวตัวเอง** (ทุกคน ไม่ว่าจะเป็น admin หรือสมาชิกทั่วไป):
  - ปุ่ม: **แชทก๊วน** (ฟ้า, `Icons.chat_bubble_outline` → `showGroupChatPopup(...)`)
- **แถวสมาชิกคนอื่น** (เฉพาะ admin, `memberUserId != currentUserId` และ member ไม่ใช่ admin):
  - ปุ่ม: **แชทก๊วน** (ฟ้า) + **บล็อก** (เทา, `Icons.block` → `_blockUserDialog`) / **ถอดออกจากก๊วน** (แดง, `Icons.person_remove` → confirm dialog → `leaveGroup(groupId, memberUserId)`)
  - ห้ามถอดแอดมินคนอื่น (`role != 'admin'`)
- **สมาชิกทั่วไปปัดแถวคนอื่น**: ไม่มี action (`Slidable` ไม่แสดง action pane หรือ `enabled: false`)
- ลบ `IconButton` block ใน `trailing` ที่เพิ่มไว้ชั่วคราว (แทนด้วย swipe)
- **ลบปุ่ม "แชทก๊วน" ออกจาก `_buildGroupActionButtons`** — แทนด้วย swipe (ดู 8.6)

**8.5 ✅ ลบ Bottom Sheet "จัดการ" เดิม**
- ลบ `_showManageSessionSheet()` ทั้งฟังก์ชัน
- ลบปุ่ม "จัดการ" ในแถวจำนวนสมาชิกของ `_showGroupDetailSheet`

**8.6 ✅ ลบปุ่ม "แชทก๊วน" ออกจาก `_buildGroupActionButtons`**
- ปุ่ม `ElevatedButton.icon` (แชทก๊วน) ถูกลบ — แทนด้วย swipe action ใน 8.4
- `_buildGroupActionButtons` เหลือแค่: **แก้ไขก๊วน** (admin) และ **ออกจากก๊วน** (สมาชิกทั่วไป)

**8.7 ✅ ปลดบล็อกแบบ Swipe ในรายละเอียดก๊วน**
- นำปุ่ม "จัดการบล็อกลิสต์" ออกจาก `_buildGroupActionButtons`
- รายชื่อใน section “ถูกบล็อก” ห่อด้วย `Slidable` และปัดซ้ายเพื่อเปิดปุ่ม **“ปลด”** สีเขียว
- กด “ปลด” ต้องเรียก `getUnblockCapacityStatus()` เพื่อตรวจข้อมูลสดจาก DB ก่อน: อนุญาตเมื่อ `member_count + 1 <= capacity` เท่านั้น
- ถ้า `member_count + 1 > capacity` ให้คง blocklist ไว้ ไม่เรียก `unblockUser()` และแสดง dialog “ไม่สามารถปลดบล็อกได้” พร้อมจำนวนปัจจุบัน/จำนวนที่เปิดรับ
- ข้อความ dialog ต้องแนะนำให้เจ้าของก๊วนเข้าไป “แก้ไขก๊วน” และเพิ่มจำนวนที่เปิดรับให้เสร็จก่อนลองปลดอีกครั้ง
- เมื่อผ่านเงื่อนไขจึงเรียก `unblockUser()` แล้ว refresh Bottom Sheet/รายการก๊วนทันที
- ไม่มี Blocklist Sheet แยกใน flow ปัจจุบัน

**8.8 ✅ แยกผู้ถูกบล็อกออกจากสมาชิก active**
- `listGroupMembers()`, `listGroupPendingBookings()`, `listMyJoinedGroupIds()` และ member count กรอง `fitness_group_blocklist.is_active=true` ออก
- เมื่อบล็อกสำเร็จ `blockUser()` เรียก `leaveGroup()` ต่อเพื่อ deactivate membership และยกเลิก booking `pending/confirmed`
- Bottom Sheet รายละเอียดก๊วนคำนวณ `เข้าร่วมแล้ว/ว่าง` จากสมาชิกที่ผ่านการกรอง
- Section “ถูกบล็อก” แสดง avatar, ชื่อ, เหตุผล และสถานะบล็อก แยกจาก “เข้าร่วมแล้ว”; แต่ละแถวปัดซ้ายเพื่อปลดบล็อก
- เฉพาะเจ้าของก๊วน (`fitness_groups.created_by`) หรือ admin Sheserved (`users.role='admin'`) เท่านั้นที่เห็น section “ถูกบล็อก”; `listBlockedUsers()` ตรวจสิทธิ์จาก DB ก่อนคืนข้อมูลโปรไฟล์

**8.9 ✅ กรองผู้รออนุมัติออกจากสมาชิกที่เข้าร่วมแล้ว**
- `listMyJoinedGroupIds()` คืนก๊วนเฉพาะ membership role admin หรือผู้มี booking `confirmed`; pending-only จึงไม่ทำให้ CTA เป็น “เข้าร่วมก๊วนแล้ว”
- เพิ่ม `listMyBlockedGroupIds()` เพื่อระบุก๊วนที่ผู้ใช้ถูกบล็อกก่อนประเมิน `joined/pending`
- ผู้ร้องขอที่ถูกบล็อกเห็น CTA **“รอคิว”** แบบ disabled เป็นถ้อยคำสุภาพ; ไม่เปิดเผยคำว่า “ถูกบล็อก” และไม่สามารถส่งคำขอซ้ำ
- `listGroupMembers()` และ member count แสดงเฉพาะ admin หรือ user ที่มี booking `confirmed`
- `listMyGroups()` ไม่แสดงก๊วน pending-only ในรายการก๊วนที่เข้าร่วม แต่ประวัติ booking ยังคงแสดง “รออนุมัติ”
- `isGroupMember()` ใช้เงื่อนไข confirmed/admin + active + ไม่ถูกบล็อกก่อนอนุญาตเข้าแชท
- Section pending ไม่ตัดผู้ใช้ออกเพียงเพราะมี confirmed booking อื่นอยู่แล้ว เพื่อให้ admin ยังเห็นคำขอรายรอบครบถ้วน

### บันทึกบทเรียน: Approval Filtering Regression
- **อาการ:** ผู้ใช้ส่งคำขอเข้าก๊วนส่วนตัวแล้ว แต่หน้า card/Bottom Sheet แสดง “เข้าร่วมก๊วนแล้ว” และแสดงชื่อในรายชื่อสมาชิก ทั้งที่ booking ยังเป็น `pending` ตามภาพทดสอบบน iOS/Android
- **สาเหตุหลัก:** `book_fitness_session()` ตั้ง booking เป็น `pending` แต่ยัง upsert แถว `fitness_group_members` เป็น `is_active=true`; การใช้ `fitness_group_members.is_active` เพียงอย่างเดียวจึงทำให้ pending ถูกนับเป็นสมาชิกแล้ว
- **วิธีป้องกันที่ implement แล้ว:** ให้สถานะ effective member ใน App Layer อ้างอิง `role='admin'` หรือมี booking `status='confirmed'`; ใช้ filter เดียวกันใน `listGroupMembers()`, `listMyJoinedGroupIds()`, `listMyGroups()`, `isGroupMember()` และ member count
- **กฎ UI:** pending-only ต้องอยู่ใน section “คำขอรออนุมัติ” และ CTA เป็น “รออนุมัติ”; หลัง `approve_fitness_session_booking()` เปลี่ยนเป็น `confirmed` จึงย้ายไป “เข้าร่วมแล้ว” และเปิดสิทธิ์แชท
- **Regression checklist:** ทดสอบอย่างน้อย 3 สถานะ — (1) ก่อนจอง, (2) หลังส่งคำขอ pending, (3) หลัง admin approve — ตรวจ CTA, รายชื่อสมาชิก, member count, หน้า “ก๊วนของฉัน” และสิทธิ์แชทให้ตรงกัน
- **DB follow-up:** trigger `sync_fitness_chat_participants()` ยังใช้ `is_active=true`; ต้องปรับให้รวมเฉพาะ admin/confirmed และเพิ่มการ sync เมื่อ booking status เปลี่ยน เพื่อให้ DB participant list สอดคล้องกับ App Layer

### ความเสี่ยง / จุดที่ต้องระวัง
- **Discoverability:** มี hint text เล็กๆ ใต้หัวข้อรอบนัด/สมาชิก เช่น "ปัด...ไปทางซ้ายเพื่อจัดการ" (แสดงเฉพาะ admin) แต่ยังต้องทดสอบว่าผู้ใช้ค้นพบ gesture ได้จริง
- **Slidable ใน ListView ที่อยู่ใน SingleChildScrollView:** gesture แนวนอนของ Slidable ไม่ชนกับ scroll แนวตั้ง แต่ต้องทดสอบใน bottom sheet ที่ drag ปิดได้
- **Responsive action labels:** ใช้ `CustomSlidableAction` + `FittedBox` และกำหนด `extentRatio` ตามจำนวน action เพื่อป้องกันไอคอน/ข้อความล้นบนหน้าจอแคบ
- **การบล็อกสมาชิก/pending:** `blockUser()` เรียก `leaveGroup()` ต่อทันทีเพื่อถอดสมาชิกและยกเลิก booking; repository ยังกรอง blocklist ออกจาก `listGroupMembers()`, `listGroupPendingBookings()`, `listMyJoinedGroupIds()` และ member count เพื่อรองรับข้อมูลเก่าก่อนการแก้ไข
- **`leaveGroup` โดย admin แทนผู้ใช้:** RPC `leave_fitness_group` รับ `p_user_id` ตรงๆ (RLS เป็น `USING(true)` + App Layer enforce ตาม pattern โปรเจกต์) — UI gate ให้เฉพาะ admin และไม่แสดง action สำหรับแถวตัวเอง/แอดมินคนอื่น
- **Unblock swipe:** ตรวจ capacity แบบ fresh ทุกครั้งก่อนปลดและห้ามใช้ค่าจาก snapshot UI ที่อาจ stale; ต้องทดสอบกรณี `member_count + 1 == capacity` (ผ่าน) และ `> capacity` (ไม่ผ่าน) รวมถึงยืนยันว่าผู้ที่ปลดบล็อกยังไม่กลับเป็นสมาชิก active จนกว่าจะจองเข้าร่วมใหม่
- **Maestro test เดิม (`owner_approval.yaml`):** flow อนุมัติผ่านปุ่ม "จัดการ" ยังต้องอัปเดตเป็น swipe (`swipe` command ใน Maestro)

### Definition of Done
- Admin เปิด sheet รายละเอียดก๊วน → เห็น section "คำขอรออนุมัติ" (ถ้ามี) + รายชื่อสมาชิก
- ปัดรอบนัดไปทางซ้าย → เห็นปุ่ม **แก้ไข/ยกเลิก** ที่ไอคอนและข้อความพอดีใน action pane และใช้งานได้จริง
- ปัดรายชื่อคน pending ไปทางซ้าย → เห็นปุ่ม อนุมัติ/ปฏิเสธ/บล็อก ใช้งานได้จริง (เลือกรอบนัดก่อนอนุมัติ)
- Admin ปัดรายชื่อสมาชิกคนอื่น → เห็นปุ่ม แชทก๊วน/บล็อก/ถอดออกจากก๊วน ใช้งานได้จริง
- สมาชิกทั่วไปปัดแถวตัวเอง → เห็นปุ่ม แชทก๊วน ใช้งานได้จริง
- สมาชิกทั่วไปปัดแถวคนอื่น → ไม่มี action
- ปุ่ม "แชทก๊วน" ใน `_buildGroupActionButtons` ถูกลบแล้ว
- ปุ่ม "จัดการ" และ `_showManageSessionSheet` ถูกลบแล้ว ไม่มีโค้ดตาย
- ปุ่ม "จัดการบล็อกลิสต์" ถูกนำออก; ปัดแถวใน section “ถูกบล็อก” → เห็นปุ่ม “ปลด”
- กด “ปลด” เมื่อ `member_count + 1 > capacity` → ไม่ปลดบล็อกและเห็น dialog แนะนำให้เจ้าของแก้ไขจำนวนที่เปิดรับก่อน; เมื่อไม่เกินจึงปลดได้จริง
- ผู้ถูกบล็อกไม่ปรากฏใน pending/“เข้าร่วมแล้ว” และไม่ถูกนับในจำนวนสมาชิก/จำนวนว่าง
- เจ้าของก๊วนและ admin Sheserved เห็น section “ถูกบล็อก”; group admin คนอื่นและสมาชิกทั่วไปไม่เห็นข้อมูลรายชื่อผู้ถูกบล็อก
- บล็อกสมาชิกแล้ว membership เป็น inactive และ booking `pending/confirmed` ถูกยกเลิก
- ผู้ใช้ที่ส่งคำขอเข้าก๊วนส่วนตัวเห็น CTA “รออนุมัติ” และยังไม่ปรากฏใน “เข้าร่วมแล้ว”/member count/ก๊วนของฉัน/สิทธิ์แชท
- ผู้ร้องขอที่ถูกบล็อกเห็น CTA “รอคิว” แบบ disabled และไม่สามารถส่งคำขอซ้ำ
- หลัง admin อนุมัติ booking ผู้ใช้จึงปรากฏใน “เข้าร่วมแล้ว” และได้รับสิทธิ์สมาชิกตามปกติ
- `flutter analyze` ผ่านไม่มี error ใหม่
