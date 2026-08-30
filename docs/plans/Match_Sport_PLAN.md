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
  - ซ้าย: ปุ่มเปิด Drawer (`TlzHamburgerMenu`)
  - กลาง: ชื่อหน้า "หาเพื่อนออกกำลังกาย" แบบ `FittedBox` บังคับหนึ่งบรรทัด หรือชื่อก๊วน
  - ขวา: ปุ่มรีเฟรช, ปุ่มค้นหา (เปิด `_showSearchDialog()`), ปุ่มเมนูเพิ่มเติม (ก๊วนของฉัน + สลับมุมมอง รายการ/แผนที่), ปุ่มแจ้งเตือน และปุ่มตะกร้าตามมาตรฐานของ `TlzAppTopBar`
- การจัดวางปุ่ม: ลดจำนวนปุ่มหลักเพื่อรักษาพื้นที่ชื่อหน้า โดยเก็บ action ที่ใช้รองลงมาไว้ใน `PopupMenuButton` (`more_vert`)
- หน้า "รายการก๊วน"
  - แถบ "หมวดหมู่กีฬา" (แนวนอนแบบ Chip) + ปุ่ม "+" ทรงกลม (เฉพาะ admin `role == 'admin'`; ผู้ใช้ทั่วไปไม่เห็นปุ่มนี้) — ปุ่มอยู่นอก scroll area ติดขวาไม่เลื่อนตาม chip
  - รายการก๊วน (การ์ด): รูปสนาม/ปก (thumbnail), ชื่อก๊วน, กีฬา (emoji + ชื่อ), badge เพศที่เชิญชวน (ช./ญ./เสรี), คำอธิบาย 2 บรรทัด, พื้นที่ (จังหวัด/อำเภอ), **สรุปจำนวนที่ว่างของรอบนัดถัดไป**, รอบนัดถัดไปสูงสุด 3 รอบ, ปุ่ม CTA (เข้าร่วมก๊วน / เข้าร่วมแล้ว / รอคิวสำหรับผู้ถูกบล็อก / เพิ่มรอบนัดสำหรับผู้จัดการก๊วน)
  - ค้นหาและตัวกรอง: รวมใน dialog เดียวเปิดจากปุ่ม search ใน top bar — มีช่องค้นหาก๊วน/สถานที่, จังหวัด, อำเภอ, และ checkbox "เฉพาะก๊วนที่เข้าร่วมได้ทันที" (กรองเอาก๊วนส่วนตัวที่ต้องรออนุมัติออก; ก๊วนส่วนตัวยังแสดงในรายการเปิดรับตามปกติ)
  - ปุ่ม toggle แผนที่ (เปิด/ปิด มุมมองแผนที่)
- หน้า “แผนที่”
  - แสดง Marker ของก๊วนตามตัวกรอง, คลิก Marker เปิดแผ่นสรุปและนำทางไปหน้ารายละเอียด
- หน้า “รายละเอียดก๊วน” (เปิดเป็น Bottom Sheet `sport_club_page.dart`)
  - Header: ชื่อก๊วนกึ่งกลาง และแสดง `สิทธิ์ของคุณ` ระดับก๊วน (เจ้าของก๊วน/ผู้ดูแลก๊วน/ผู้ดูแล Sheserved/สมาชิกก๊วน/ผู้ขอเข้าร่วม/ผู้เยี่ยมชม)
  - รายการรอบนัด: แต่ละรอบเป็นหัวข้อ expandable แสดงช่วงเวลา (`รอบที่ N · ...`), `ผู้เข้าร่วม N / capacity คน · รออนุมัติ N คน · เหลือ N ที่` และรายชื่อ **ผู้เข้าร่วมรอบนี้** แยกจากรอบอื่น
  - ผู้จัดการก๊วนเห็นคำขอรออนุมัติอยู่ใต้รอบที่ผู้ขอเลือก โดยแต่ละรายแสดงสถานะและ **เวลาที่ส่งคำขอ** จาก `fitness_group_bookings.created_at`; ปัดซ้ายเพื่อ **อนุมัติ/ปฏิเสธ booking รอบนั้น** หรือ **บล็อกผู้ใช้ระดับก๊วน**
  - สมาชิก/ผู้ขอเข้าร่วมเห็นเฉพาะ section `คำขอของฉัน` ของตนเองใต้รอบที่ขอ และไม่เห็นชื่อหรือเวลาของผู้ขอรายอื่น
  - สรุปสมาชิกก๊วน: `สมาชิกก๊วนรวม (ไม่ซ้ำ) N คน` เป็น section แยก/ย่อด้านล่าง ใช้บอกสิทธิ์ระดับก๊วน ไม่ใช้แทนรายชื่อผู้เข้าร่วมรายรอบ
  - รายชื่อสมาชิก: avatar, ชื่อ-นามสกุล, บทบาท (**เจ้าของก๊วน/ผู้ดูแล/สมาชิก**), สถานะ (เข้าร่วมแล้ว/หยุดพัก); ผู้จัดการก๊วนปัดซ้ายเพื่อเปิดเมนูจัดการ และผู้ที่ถูกบล็อกต้องไม่อยู่ใน section นี้
  - สมาชิกก๊วนหรือ owner ที่ปิด auto-join แล้วมีสิทธิ์เลือกเพิ่มรอบ: ปัดหัวข้อรอบนัดจากขวาไปซ้ายเพื่อเปิดปุ่ม **“เลือกเพิ่มรอบ”**; ไม่แสดงปุ่มหลักด้านล่าง
  - Section “ถูกบล็อก”: แสดงแยกจากสมาชิก เฉพาะผู้จัดการก๊วน (owner/active group admin) และ admin Sheserved เท่านั้น
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
- `fitness_groups` (id, sport_id, name VARCHAR(60), description VARCHAR(500), province, district, lat DOUBLE PRECISION CHECK(lat BETWEEN -90 AND 90), lng DOUBLE PRECISION CHECK(lng BETWEEN -180 AND 180), owner_auto_join BOOLEAN NOT NULL DEFAULT true, requires_owner_approval BOOLEAN DEFAULT false, cover_image_url VARCHAR(500), venue_photo_url VARCHAR(500), gender_preference VARCHAR(10) DEFAULT 'any' CHECK(gender_preference IN ('male','female','any')), created_by UUID REFERENCES users(id), created_at TIMESTAMPTZ DEFAULT now())
  - ระยะแรกไม่กำหนดจำนวนสมาชิกสูงสุดรวมทั้งก๊วน; `fitness_group_members` เก็บสมาชิกแบบไม่ซ้ำเพื่อใช้สิทธิ์และแสดงผลเท่านั้น
  - `owner_auto_join`: ค่าเริ่มต้น `true` — เมื่อเปิดจะสร้าง booking `confirmed` ของ owner ในทุก upcoming session และ owner กิน 1 ที่นั่งของแต่ละรอบ; ถ้า `false` owner ไม่ถูกจองรอบใหม่อัตโนมัติ แต่ยังควบคุมก๊วนผ่าน `created_by` และจองเฉพาะรอบที่ต้องการเองได้
  - **นิยาม “ก๊วนส่วนตัว”:** คือก๊วนที่ `requires_owner_approval = true` — ยังแสดงในรายการเปิดรับเหมือนก๊วนทั่วไป แต่ผู้เข้าร่วมต้องรอเจ้าของก๊วนอนุมัติก่อนเข้าร่วม (ไม่ใช้ฟิลด์ `visibility` แยกอีกต่อไป; `public`/`private` เป็นสิ่งเดียวกันกับ toggle อนุมัติ)
  - `venue_photo_url`: รูปถ่ายสนาม/สถานที่จริงที่ใช้นัดเล่น (แยกจาก `cover_image_url` ซึ่งเป็นภาพปกของก๊วน)
  - `gender_preference`: เพศที่กำลังชวนเข้าร่วมก๊วน — `'male'` (ชาย), `'female'` (หญิง), `'any'` (เสรี/ไม่จำกัด — ค่าเริ่มต้น)
- `fitness_group_sessions` (id, group_id UUID REFERENCES fitness_groups(id) ON DELETE CASCADE, starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ, capacity INTEGER NOT NULL DEFAULT 5 CHECK(capacity BETWEEN 1 AND 30), place_name VARCHAR(200), lat DOUBLE PRECISION, lng DOUBLE PRECISION, note VARCHAR(500), CHECK(ends_at > starts_at))
  - `capacity`: จำนวนผู้เข้าร่วมสูงสุดของรอบนัดนั้น ๆ; ไม่ใช่จำนวนสมาชิกสูงสุดของก๊วน
- `fitness_group_members` (group_id UUID, user_id UUID REFERENCES users(id), role VARCHAR(10) CHECK(role IN ('member','admin')), is_active BOOLEAN DEFAULT true, joined_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY(group_id, user_id))
  - หมายเหตุ: แถวสมาชิกของผู้จอง **สร้าง/อัปเดตอัตโนมัติโดยระบบ** เมื่อจองรอบนัดครั้งแรก — ไม่มีฟอร์ม "สมัครสมาชิก" แยก; owner ที่ `owner_auto_join=true` จะมี booking `confirmed` ในทุก upcoming session, ส่วน owner ที่ปิด auto-join จะ active เมื่อคงหรือสร้าง booking ของตนเองไว้; สิทธิ์ควบคุมก๊วนยังอ้างอิง `fitness_groups.created_by` ได้แม้ owner ไม่ active (ดูหัวข้อ "เข้าร่วมก๊วน = จองรอบนัด")
- `fitness_group_bookings` (id UUID DEFAULT gen_random_uuid(), session_id UUID REFERENCES fitness_group_sessions(id), user_id UUID REFERENCES users(id), status VARCHAR(10) CHECK(status IN ('pending','confirmed','cancelled','rejected')), created_at TIMESTAMPTZ DEFAULT now(), cancelled_at TIMESTAMPTZ, cancelled_by VARCHAR(10) CHECK(cancelled_by IN ('user','owner','system')), cancel_reason VARCHAR(200), UNIQUE(session_id, user_id))
  - ⚠️ `UNIQUE(session_id, user_id)` ป้องกันการจองซ้ำระดับ DB — ถ้ายกเลิกแล้วต้องการจองใหม่ ให้ UPDATE แถวเดิม (soft-reactivate) แทนการ INSERT ใหม่
- `fitness_group_blocklist` (group_id UUID, blocked_user_id UUID REFERENCES users(id), blocked_by UUID REFERENCES users(id), reason VARCHAR(200), is_active BOOLEAN DEFAULT true, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY(group_id, blocked_user_id))
- ความสัมพันธ์กับแชท: ผูก `chat_rooms` เดิม (ต้องมี migration เพิ่ม — ดูหัวข้อ "Chat Room Integration")

### Owner Participation + Session Capacity Policy (ตัดสินใจใหม่)
- ระยะแรก **ไม่กำหนดจำนวนสมาชิกสูงสุดรวมทั้งก๊วน**; `fitness_group_members` ใช้เก็บสิทธิ์สมาชิกแบบไม่ซ้ำ ไม่ใช่ตัวหาร capacity ของ session
- `fitness_group_sessions.capacity` คือจำนวนผู้เข้าร่วมสูงสุดของ **รอบนัดนั้นเท่านั้น** และอนุญาตค่า 1–30
- `owner_auto_join = true` เป็นค่าเริ่มต้น — owner จะมี booking `confirmed` และกิน 1 ที่นั่งในทุก upcoming session; session ใหม่จะสร้าง booking ของ owner อัตโนมัติ
- หาก owner เปลี่ยนเป็น `false` ระบบถามทุกครั้งว่าจะคงหรือยกเลิก booking ของ owner ในรอบอนาคต; เมื่อปิดแล้ว owner จองเฉพาะรอบที่ต้องการเองได้ และการจองเองไม่เปิด `owner_auto_join` กลับเป็น `true`
- การเปิด `owner_auto_join` กลับเป็น `true` ต้องสร้าง/เปิดใช้ booking ของ owner ให้ครบทุก upcoming session แบบ all-or-nothing; ถ้ารอบใดเต็ม หรือ upcoming sessions ของก๊วนมีเวลาทับซ้อนกัน ให้ปฏิเสธทั้งการเปิด
- `pending` ไม่กินที่นั่ง; capacity ของรอบคำนวณจากผู้จอง `confirmed` แบบ distinct เท่านั้น และตรวจซ้ำตอนอนุมัติ
- owner (`created_by`) ยังคงจัดการก๊วนได้แม้ membership inactive; active membership ของ owner เกิดจาก auto-join หรือมี explicit confirmed booking ที่คงอยู่
- `fitness_groups.capacity` เดิมยังคงอยู่ชั่วคราวเพื่อรองรับข้อมูลเก่าและใช้ backfill เท่านั้น ไม่ใช้กับ flow ใหม่ และไม่ควรเรียกว่า group capacity อีกต่อไป
- **Migration:** เพิ่ม `fitness_group_sessions.capacity`, backfill จากค่า legacy ใน `fitness_groups.capacity`, เพิ่ม owner booking สำหรับ upcoming sessions เดิม และปรับ RPC/trigger ให้ใช้กติกาใหม่ผ่าน migration `20260825130000_fitness_buddies_session_capacity.sql`
- **สิทธิ์:** owner (`created_by`) เป็นผู้เปลี่ยน owner participation; active group admin/admin Sheserved จัดการข้อมูลก๊วนและรอบนัดได้ตาม manager policy แต่ไม่เปลี่ยน participation ของ owner
- ผู้จัดการก๊วนสามารถ `ถอดจากรอบนี้` ได้เฉพาะ confirmed booking ของสมาชิกที่ไม่ใช่ owner; การถอดนี้ไม่กระทบ membership/booking ของรอบอื่น และไม่เปลี่ยน owner participation

### เข้าร่วมก๊วน = จองรอบนัด (Unified Action)
- sheserved ไม่มีขั้นตอน "สมัครสมาชิกก๊วน" แยกจาก "จองรอบนัด" — ทั้งสองคำมีความหมายเดียวกัน: กด **"เข้าร่วมก๊วน"** = สร้าง `fitness_group_bookings` สำหรับรอบนัดถัดไปโดยตรง (สมาชิก sheserved จองได้อิสระ ไม่ต้องผ่านขั้นตอนสมัครสมาชิกก่อน)
- เมื่อสร้างก๊วน ค่าเริ่มต้น `owner_auto_join=true` ให้ owner เป็น `role='admin', is_active=true`; การสร้าง session ใหม่จะสร้าง booking `confirmed` ของ owner และนับ owner 1 ที่นั่งใน session นั้น
- เมื่อ owner ปิด auto-join ระบบถามว่าจะคงหรือยกเลิก booking ของ owner ในรอบอนาคต; หากคงไว้ owner ยังเป็นผู้เข้าร่วมรอบนั้นได้ แต่จะไม่ถูกเพิ่มอัตโนมัติใน session ใหม่
- เมื่อ owner ที่ opt-out จองรอบเอง RPC ต้องยกเว้น approval สำหรับ owner, เปลี่ยน booking เป็น `confirmed`, ทำให้ owner active ในฐานะผู้เข้าร่วมรอบนั้น และ **ไม่** ตั้ง `owner_auto_join=true` กลับ
- เมื่อเปิด auto-join กลับ RPC ต้องตรวจทุก upcoming session แบบ atomic ทั้ง capacity และ overlap ก่อนสร้าง/เปิดใช้ booking owner ให้ครบทุก session
- เมื่อ booking ของผู้ขอถูกสร้าง RPC อาจ upsert `fitness_group_members` ตั้งแต่สถานะ `pending`; แต่ App Layer จะถือว่า “เข้าร่วมแล้ว” เฉพาะ admin ที่มีสิทธิ์ควบคุมก๊วนหรือผู้ที่มี booking `confirmed` อย่างน้อยหนึ่งรายการ
- booking `pending` ของก๊วนที่ต้องอนุมัติ: แสดง CTA “รออนุมัติ”, อยู่เฉพาะ section คำขอรออนุมัติ, ไม่แสดงในรายชื่อ/จำนวน “เข้าร่วมแล้ว” และไม่กิน capacity จนกว่าจะอนุมัติ
- `fitness_group_sessions.capacity` คือจำนวนผู้เข้าร่วมสูงสุดของรอบนั้น; `confirmed_count` และ `available_count` ต้องคำนวณจาก booking ของ session นั้น ไม่รวมยอดสมาชิกก๊วนหรือผลรวม capacity ของหลายรอบ
- **ออกจากก๊วน/ถอดทั้งก๊วน:** สมาชิกทั่วไปตั้ง `fitness_group_members.is_active = false` และยกเลิก booking ที่ `pending`/`confirmed` ทั้งหมดแบบ cascade; owner ใช้ toggle owner participation แทนการออก เพื่อรักษาสิทธิ์ควบคุมก๊วน
- **ถอดจากรอบนี้:** ผู้จัดการก๊วนยกเลิกเฉพาะ booking `confirmed` ของสมาชิกที่ไม่ใช่ owner; ถ้ายังมี booking confirmed รอบอื่นหรือเป็น active group admin ให้คง membership ไว้, ถ้าไม่มี confirmed อื่นให้ deactivate membership เพื่อไม่ให้สิทธิ์เข้าร่วมค้างอยู่
- สิทธิ์เข้าแชทกลุ่มใน App Layer: `isGroupMember()` ต้องพบ membership active, ไม่ถูกบล็อก และเป็น admin หรือมี booking `confirmed`; owner ที่ปิด auto-joinและไม่มี booking `confirmed` ที่คงอยู่จะไม่มีสิทธิ์แชท ส่วน owner ที่คงหรือสร้าง booking รายรอบจะ active ตามการเข้าร่วมนั้น
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
- Sync `participant_ids`: trigger `sync_fitness_chat_participants()` ต้อง sync owner ที่มี membership active (จาก auto-join หรือ explicit confirmed booking) และผู้มี booking `confirmed`; owner ที่ opt-out และไม่มี booking ที่คงอยู่ยังจัดการก๊วนได้แต่ไม่เป็น participant ในแชท — booking status update ต้อง trigger sync ห้องอีกครั้ง
- ⚠️ Tech debt เดิมที่ต้องรับทราบ: `chat_messages.sender_id REFERENCES auth.users(id)` อ้าง Supabase Auth ที่ไม่ได้ใช้งานจริงในโปรเจกต์นี้ — ไม่แก้ในรอบนี้ แต่ FK นี้จะไม่ enforce ความสัมพันธ์กับ `public.users.id` จริง (ความเสี่ยงเดิมที่มีอยู่แล้วในระบบ)

### Data Integrity Guards (ป้องกัน Race Condition ระดับ DB)
- **ป้องกันจองซ้ำ:** `UNIQUE(session_id, user_id)` บน `fitness_group_bookings` (เพิ่มใน schema แล้ว)
- **ป้องกันเกิน capacity รายรอบ:** ปรับ Postgres function `book_fitness_session(p_session_id, p_user_id)` ให้ทำงานใน transaction เดียว:
  1. `SELECT ... FOR UPDATE` ล็อกแถว `fitness_group_sessions` ของรอบนั้น
  2. ใช้ `fitness_group_sessions.capacity` และนับผู้จองแบบ distinct ที่มีสถานะ `confirmed` เฉพาะรอบนั้น; `pending` ไม่กินที่นั่ง
  3. ถ้าเป็น booking ที่จะเปลี่ยนเป็น `confirmed` แล้วเกิน capacity → return error `SESSION_FULL`
  4. ถ้าไม่เกิน → insert/reactivate booking + upsert membership ในธุรกรรมเดียว
- **Approval capacity:** `approve_fitness_session_booking()` ต้อง lock session และตรวจ `confirmed_count < session.capacity` ซ้ำก่อนเปลี่ยน pending เป็น confirmed
- **ข้อควรระวังจาก Approval Filtering Regression:** ห้ามใช้ `fitness_group_members.is_active=true` เพียงอย่างเดียวเพื่อแสดงผลว่าเข้าร่วมแล้ว เพราะ RPC สร้างแถวผู้ขอตั้งแต่สถานะ `pending`; UI/query ต้องตรวจ owner participation, `role='admin'` หรือ booking `status='confirmed'` ร่วมด้วย
- **Owner auto-booking:** trigger/RPC สร้าง booking `confirmed` ของ owner ในทุก upcoming session เมื่อเปิด auto-join; ต้อง reject การเปิดแบบทั้งชุดถ้ามี session เต็มหรือ session ของก๊วนทับเวลา
- **ป้องกันจองซ้อนเวลา (overlap):** สร้าง Postgres function `check_booking_overlap(p_user_id, p_starts_at, p_ends_at)` ตรวจ `fitness_group_bookings JOIN fitness_group_sessions` ที่ status ไม่ใช่ `cancelled`/`rejected` และช่วงเวลาทับซ้อน — เรียกจากภายใน `book_fitness_session()` ก่อน insert เพื่อความ atomic
- Booking mutation (จอง/ยกเลิก/อนุมัติ) เรียกผ่าน Supabase RPC จาก Flutter แทนการทำ SELECT แล้ว INSERT แยกฝั่ง client; session capacity/owner auto-booking ใช้ database trigger/guard และ Repository manager check เพื่อปิดช่องว่าง race condition

### Indexes ที่ต้องสร้าง
- `idx_fitness_sessions_group_starts` ON `fitness_group_sessions(group_id, starts_at)`
- `idx_fitness_bookings_user_status` ON `fitness_group_bookings(user_id, status)`
- `idx_fitness_bookings_session_active` ON `fitness_group_bookings(session_id) WHERE status IN ('pending','confirmed')`
- `idx_fitness_groups_sport_province` ON `fitness_groups(sport_id, province, district)`
- `idx_fitness_members_group_active` ON `fitness_group_members(group_id) WHERE is_active = true`

### RLS Policy (compatibility ก่อน Phase 13.5)
> โปรเจกต์ไม่ใช้ Supabase Auth และ `auth.uid()` เป็น `null`; ระหว่าง compatibility window ยังคง `USING(true)` + App Layer เพื่อไม่ทำให้ Flutter ปัจจุบันเสีย แต่ยังไม่ใช่ security boundary สำหรับ direct client

| ตาราง | SELECT Policy ปัจจุบัน | Write control ปัจจุบัน |
|-------|----------------------|------------------------|
| `sports` | `USING(true)` (public reference) | service-role/system path เดิมระหว่าง compatibility |
| `fitness_groups` | `USING(true)` (ก๊วนทั้งหมดแสดงในรายการเปิดรับ รวมก๊วนส่วนตัว) | App Layer ตรวจสิทธิ์: owner/active group admin หรือ admin Sheserved |
| `fitness_group_sessions` | `USING(true)` | App Layer: เฉพาะ owner/active group admin/admin Sheserved |
| `fitness_group_members` | `USING(true)` | App Layer: สมาชิกเข้าร่วมเอง / owner/active group admin/admin Sheserved จัดการ |
| `fitness_group_bookings` | `USING(true)` | App Layer: ผู้จองสร้าง/ยกเลิกของตน; owner/active group admin/admin Sheserved อนุมัติ/จัดการ |
| `fitness_group_blocklist` | `USING(true)` | App Layer: เฉพาะ owner/active group admin/admin Sheserved |

> **Target Phase 13.5:** ไม่ย้ายไป Supabase Auth; Backend verify JWT แล้วตั้ง `SET LOCAL app.user_id` ภายใน transaction, ใช้ `sheserved_app` ที่ไม่มี `BYPASSRLS`, เปลี่ยน private read/write เป็น strict RLS ผ่าน `app.get_current_user_id()` และคง direct anon access เฉพาะ public SELECT

## ฟังก์ชันหลัก
- สร้างก๊วน: ทุกคนที่ล็อกอิน
- แก้ไข/จัดการก๊วน: owner/controller (`created_by`), active group admin (`fitness_group_members.role='admin'`) หรือ admin Sheserved (`users.role='admin'`) — owner ยังคงจัดการได้แม้เลือกไม่เป็นสมาชิก active
- เพิ่ม/แก้ไขหมวดหมู่กีฬา: เฉพาะแอดมินก๊วน/ผู้ดูแลระบบ (ผู้ใช้อื่นเสนอคำขอได้)
- เข้าร่วม/ออกก๊วน (= จองรอบนัด/ยกเลิกจอง ดู "เข้าร่วมก๊วน = จองรอบนัด"), owner participation toggle, เปิดแชทก๊วน
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
  - จำนวนสมาชิกก๊วน: ไม่ต้องระบุในขั้นตอนสร้างก๊วน; จำนวนสมาชิกแสดงตามผู้ใช้แบบไม่ซ้ำที่มี membership/confirmed booking
  - การเข้าร่วมของเจ้าของ: Toggle “เข้าร่วมทุกรอบอัตโนมัติ” ค่าเริ่มต้น **เปิด** — เปิดแล้วสร้าง owner booking `confirmed` และนับ 1 ที่นั่งในทุก upcoming session; ปิดแล้ว owner ยังเป็นผู้ควบคุมก๊วนและจองเฉพาะรอบเองได้
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
      CapacityStepper(min: 1, max: 30, ...),
      OwnerAutoJoinToggle(value: true, ...),
      MultilineTextField(label: 'รายละเอียด')
    ])
  )
  bottomNavigationBar: PrimaryButton('สร้างก๊วน', enabled: isValid)
```

## สร้างรอบนัด (Bottom Sheet) — Implementation (2026-08-06)
- **โฟลว์:** หลังสร้างก๊วนสำเร็จ → ส่ง `groupId` กลับ `SportClubPage`, เริ่มรีเฟรชรายการการ์ดแบบเบื้องหลัง และเปิด Bottom Sheet สร้างรอบนัดได้ทันที (ไม่บล็อกการแสดงก๊วนใหม่)
- **ทริกเกอร์ 2 จุด:**
  1. หลัง `createGroup()` สำเร็จใน `create_group_page.dart` → `Navigator.pop(..., {groupId, sportId})`; `sport_club_page.dart` ตั้ง filter ที่เกี่ยวข้อง, เรียก `_reload()` โดยไม่ await ก่อนเปิด `_showCreateSessionSheet(groupId, refreshFuture: ...)`
  2. ปุ่ม "เพิ่มรอบนัด" ในการ์ดก๊วน หรือเมื่อไม่มีรอบนัดในการ์ด (เฉพาะผู้จัดการก๊วน: owner/แอดมินก๊วน หรือ admin Sheserved) → เรียก `_showCreateSessionSheet(groupId)` ใน `sport_club_page.dart`
- **ปุ่ม "เข้าร่วมก๊วน" สำหรับผู้ใช้ทั่วไป:** แสดงแทนปุ่ม "เพิ่มรอบนัด" เมื่อไม่ใช่ผู้จัดการก๊วน → ดึงรอบนัดที่ใกล้ที่สุด (limit=1) แล้วเรียก `_book(sessionId)` อัตโนมัติ
- **ฟิลด์ใน Bottom Sheet:**
  - วันที่: Material `showDatePicker` ค่าเริ่มต้น = วันที่ของเวลาเริ่มต้น
  - เวลาเริ่มต้น: Material `showTimePicker` ค่าเริ่มต้น = ปัดขึ้นครึ่งชั่วโมงถัดไป
  - เวลาสิ้นสุด: Material `showTimePicker` ค่าเริ่มต้น = เวลาเริ่ม + 1 ชั่วโมง
  - จำนวนผู้เข้าร่วมสูงสุดของรอบ (`capacity`): slider/field ช่วง 1–30 คน ค่าเริ่มต้น 5
  - หมายเหตุ (`note`): ไม่บังคับ, สูงสุด ~500 ตัวอักษรตาม schema
  - ปัจจุบัน Bottom Sheet ใช้ข้อมูลสถานที่ของก๊วนเดิม (`place_name/lat/lng` ไม่ได้กรอกจาก UI); หน้า fallback ยังรองรับฟิลด์สถานที่ตาม schema
- **Validation:**
  - เวลาเริ่มต้น ≥ ตอนนี้ + 15 นาที
  - `capacity` ของรอบอยู่ระหว่าง 1–30 และลดต่ำกว่า confirmed participants ไม่ได้
  - เวลาสิ้นสุด > เวลาเริ่มต้น
  - หากเวลาที่เลือกไม่ผ่านเงื่อนไข (`เริ่ม < ตอนนี้ + 15 นาที` หรือ `สิ้นสุด ≤ เริ่ม`) ระบบต้องขยับเวลาอัตโนมัติ และจะต้องอัปเดต `startTime`/`endTime` บนหน้าจอพร้อม `selectedDate` ไม่ใช่ปรับเฉพาะตัวแปรทีจะส่งเข้า repository เท่านั้น มิเช่นนั้นเวลาสิ้นสุดบนหน้าจอจะไม่เลื่อนตามทำให้ผู้ใช้สับสน
  - การเลื่อนเวลาให้รักษาระยะห่าง (duration) เดิมของรอบนัด หรือถ้าข้ามเที่ยงคืนหรือไม่ผ่านเงื่อนไขให้ตั้ง `สิ้นสุด = เริ่ม + 1 ชั่วโมง`
  - Repository ตรวจซ้ำก่อน insert ว่า actor เป็น owner/แอดมินก๊วนที่ active/admin Sheserved, `capacity` อยู่ในช่วง 1–30 และเวลาเริ่มต้องห่างจากปัจจุบันอย่างน้อย 15 นาที
  - เมื่อ `owner_auto_join=true` การสร้างรอบใหม่ต้องสร้าง owner booking `confirmed` อัตโนมัติ; ถ้ารอบใหม่ทับกับรอบ upcoming เดิมของ owner ให้ปฏิเสธ
- **ระหว่างรอ reload:** เมื่อ Bottom Sheet ถูกเปิดพร้อม `refreshFuture` ปุ่ม "บันทึกรอบนัด" แสดง `CircularProgressIndicator` และ disabled; เมื่อ reload สำเร็จ/ล้มเหลวจึงเปิดให้กดบันทึกได้ เพราะ `groupId` ถูกสร้างสำเร็จแล้ว
- **หลังบันทึกสำเร็จ:** ปิด Bottom Sheet, แสดง SnackBar "สร้างรอบนัดสำเร็จ" และให้ parent เรียก `_reload()` อีกครั้งเพื่ออัปเดตจำนวนรอบ/ข้อมูลการ์ด; การ์ดก๊วนถูกรีเฟรชและแสดงได้ตั้งแต่สร้างก๊วนสำเร็จก่อนเปิด sheet นี้แล้ว
- **Root cause เคสปัญหาเวลาสิ้นสุดไม่เลื่อนตาม:** `setModalState()` อัปเดตแค่ `startsAt/endsAt` ที่บันทึก แต่ไม่อัปเดต `startTime`/`endTime` บนหน้าจอ ทำให้ผู้ใช้เห็นเวลาเก่าขณะทีส่งค่าไป DB เป็นค่าใหม่อยู่; แก้ไขโดย `setModalState(() { startTime = TimeOfDay.fromDateTime(actualStart); endTime = TimeOfDay.fromDateTime(actualEnd); })` ทุกครั้งทีมีการขยับเวลา
- **ไฟล์ที่เกี่ยวข้อง:**
  - `lib/features/community/find_buddies/presentation/pages/sport_club_page.dart` — `_showCreateSessionSheet()`, ปุ่ม "เพิ่มรอบนัด"/"เข้าร่วมก๊วน"
  - `lib/features/community/find_buddies/presentation/pages/create_session_page.dart` — หน้าสร้างรอบนัด fallback (หลัง `createGroup()`)
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
  - ก๊วนเปิด (`requires_owner_approval=false`): ยอมรับอัตโนมัติ → สถานะ `confirmed` โดยไม่แจ้งเตือนผู้จองหรือเจ้าของก๊วน
  - ก๊วนส่วนตัว (`requires_owner_approval=true`): บันทึกเป็น `pending` รอเจ้าของอนุมัติ และส่ง event แจ้งเตือนเจ้าของก๊วนทันทีเมื่อมีผู้ขอเข้าร่วม; เมื่อ `confirm` หรือ `reject` สำเร็จ ให้แจ้งผู้จองเท่านั้น
- การยกเลิก:
  - ผู้จองยกเลิกเมื่อใดก็ได้ → เปลี่ยนเป็น `cancelled` และแจ้ง “เจ้าของก๊วน”
  - เจ้าของก๊วนยกเลิกรอบ/ก๊วนทั้งหมด → แจ้งผู้จองทุกคนที่มีสถานะไม่ใช่ `cancelled`
- **หัวข้อแจ้งเตือน (Headsector ด้านขวา Home) — ใช้ WebSocket แบบ Real-time** (ตาม pattern เดียวกับ donation/yield-way ที่มีอยู่ ไม่ใช่ polling table):
  - Backend (`websocket-server`): event `fitness_booking_status` emit ไปยัง `userId` ที่เกี่ยวข้องทันทีที่มีการสร้าง `pending` ของก๊วนส่วนตัว หรือมีการ confirm/reject/cancel booking; ก๊วนเปิดที่ auto-accept ไม่ emit event
  - `lib/services/websocket_service.dart`: ใช้ `final _fitnessBookingAlertController = StreamController<Map<String, dynamic>>.broadcast();` และ getter `Stream<Map<String, dynamic>> get fitnessBookingAlertStream => _fitnessBookingAlertController.stream;` (เหมือน `_donationStatusController`/`_yieldWayAlertController`)
  - `lib/features/home/presentation/pages/home_page.dart`: ใช้ state `_fitnessBookingAlerts` + subscription ที่ listen ใน method รูปแบบเดียวกับ `_listenForDonationStatus()` พร้อม auto-clear หลัง ~15 วินาที
  - `lib/features/home/presentation/widgets/home_header_section.dart`: แสดง branch `item['type'] == 'fitness_booking'` ใน `combinedItems`; callback `onFitnessBookingAlertTapped` รับข้อมูล alert `Map<String, dynamic>` ทั้งหมด
    - ถ้า `status == 'pending'` และมี `groupId` → นำทางไป `/community/sport-club` พร้อม `arguments: { 'groupId': groupId, 'intent': 'review_pending' }` เพื่อให้เจ้าของก๊วน review คำขอทันที
    - ถ้ามี `bookingId` → นำทางไป `/community/sport-club/booking` พร้อม `arguments: { 'id': bookingId }` สำหรับสถานะ confirm/reject/cancel (มี alias เดิม `/community/find-buddies/booking/:id` ชั่วคราว)
    - alert payload จาก WebSocket/Repository ต้องส่ง `groupId`/`group_id` และ `bookingId`/`booking_id` พร้อม `status` เสมอ เพื่อให้ `home_page.dart` แยกทางเลือกนำทางได้ถูกต้อง
  - แสดงเป็นฟีดใหม่→เก่า
- **Timeout สำหรับ pending booking:** ถ้า booking สถานะ `pending` ไม่ได้รับอนุมัติภายใน 24 ชั่วโมง หรือถึงเวลาก่อนเริ่ม session 1 ชั่วโมง (แล้วแต่ถึงก่อน) ระบบ auto-reject (`status='rejected', cancelled_by='system'`) ผ่าน BullMQ delayed job ที่ enqueue ตอนสร้าง booking (สอดคล้องกับ `architecture_analysis.md` ที่ใช้ BullMQ queue อยู่แล้ว) และแจ้งเตือนทั้งผู้จองและเจ้าของก๊วนผ่าน event `fitness_booking_status` ด้านบน
- ป้องกันการจองซ้ำซ้อน: ก๊วนเปิด (`requires_owner_approval=false`) ตรวจผ่าน `check_booking_overlap()` RPC (ดู Data Integrity Guards) ในขั้นตอนขอร่วมก๊วน; ก๊วนส่วนตัว (`requires_owner_approval=true`) ให้สร้างคำขอ `pending` ก่อน แล้วตรวจ overlap ตอนแอดมินอนุมัติผ่าน `approve_fitness_session_booking()` RPC เพื่อไม่ให้คำขอค้างถูกตัดด้วย `OVERLAP_BOOKING` ตั้งแต่ต้น
- บล็อกผู้ใช้: owner/active group admin/admin Sheserved สามารถบล็อกจาก swipe ของสมาชิกหรือผู้ขอ pending (ห้ามจองก๊วนนี้); ผู้จัดการก๊วนดูรายชื่อใน section “ถูกบล็อก” และปัดซ้ายเพื่อปลด

## อนุมัติคำขอเข้าร่วม (Owner Approval UI — ปรับเป็น Swipe)
- ทริกเกอร์เดิมคือปุ่ม "จัดการ" ในรายละเอียดก๊วน แต่ปุ่มนี้ถูกยกเลิกแล้วตาม Phase 8
- ปัจจุบัน admin เห็น section **"คำขอรออนุมัติ"** แยกเหนือรายชื่อสมาชิกใน `_showGroupDetailSheet()`; ผู้ที่มีเฉพาะ booking `pending` ไม่ถือว่าเข้าร่วมแล้ว
- เมื่อมีผู้ขอเข้าร่วมก๊วนส่วนตัวและสร้าง booking `pending` สำเร็จ ระบบส่ง event `fitness_booking_status` แจ้งเจ้าของก๊วนทันที; ก๊วนเปิดที่ auto-accept ไม่ส่ง event แจ้งเตือน
- เจ้าของก๊วนสามารถกดแจ้งเตือนจาก Headsector เพื่อเปิดหน้ารายละเอียดก๊วนและดูรายการใน section “คำขอรออนุมัติ”
- แต่ละรายการแสดง avatar, ชื่อ และจำนวนรอบที่ขอ จากนั้นปัดซ้ายเพื่อเปิด **อนุมัติ / ปฏิเสธ / บล็อก**
- อนุมัติหรือปฏิเสธ: เปิด dialog ให้เลือก booking pending เป็นรายรอบ แล้วเรียก `approveBooking()`/`rejectBooking()` เดิม; เมื่อเสร็จแล้ว refresh ด้วย `setSheetState()`
- Blocklist: `blockUser()` upsert blocklist แล้วเรียก `leaveGroup()` เพื่อตั้งสมาชิก inactive และยกเลิก booking `pending/confirmed`; ผู้ถูกบล็อกจึงถูกนำออกจากทั้ง section pending และ “เข้าร่วมแล้ว”
- Repository/เมธอดที่ใช้ (Flutter):
  - `listGroupPendingBookings(groupId, requesterUserId)` → ตรวจสิทธิ์ผู้จัดการก๊วนก่อนดึง pending booking ของทุก session ในก๊วน พร้อมข้อมูล user/session แล้ว group ตามผู้ใช้ฝั่ง client
  - `approveBooking({ bookingId, actorUserId })` → ตรวจ owner/active group admin/admin Sheserved แล้วเรียก RPC `approve_fitness_session_booking()` เพื่ออัปเดตสถานะเป็น `confirmed` พร้อมตรวจ overlap และสิทธิ์
  - `rejectBooking({ bookingId, actorUserId, reason? })` → ตรวจผู้จัดการก๊วนก่อนอัปเดตสถานะเป็น `rejected` เฉพาะแถวที่ยัง `pending` และบันทึก `cancelled_by='owner'` พร้อม `cancel_reason` ถ้ามี
- รอบนัดที่มีอยู่: ผู้จัดการก๊วนปัดซ้ายแต่ละรอบเพื่อเปิด **แก้ไข / ยกเลิก**; ผู้ใช้ทั่วไปไม่มี action pane
- Realtime/WebSocket: เมื่อสร้าง booking `pending` ของก๊วนส่วนตัวให้ emit event `fitness_booking_status` ไปยังเจ้าของก๊วน; เมื่ออนุมัติ/ปฏิเสธให้ emit ไปยังผู้จอง และเมื่อยกเลิกให้ emit ไปยังผู้รับที่เกี่ยวข้องตามกติกาการยกเลิก

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
- แก้ไข/จัดการก๊วน: เฉพาะ **ผู้จัดการก๊วน** ซึ่งหมายถึง owner/controller ที่ระบุด้วย `fitness_groups.created_by`, แอดมินก๊วนที่มี `fitness_group_members.role='admin' AND is_active=true`, หรือแอดมิน Sheserved ที่มี `users.role='admin'`
- เพิ่มรอบนัด/แก้ไขรอบนัด/ยกเลิกรอบนัด/อนุมัติ/ปฏิเสธ/บล็อก/ปลดบล็อก: ใช้กฎผู้จัดการก๊วนเดียวกัน ห้ามใช้เพียงการซ่อนปุ่มใน UI
- เพิ่ม/แก้ไขหมวดหมู่กีฬา: เฉพาะแอดมินก๊วน/ผู้ดูแลระบบ
- เข้าร่วม: ผู้ใช้ล็อกอินเท่านั้น
- แชท: เฉพาะสมาชิกก๊วน (ตรวจสิทธิ์ก่อนเข้าห้อง)
- แผนที่: ระหว่างพัฒนาใช้ผู้ให้บริการไม่มีค่าใช้จ่าย (OSM + flutter_map); เตรียม config สำหรับสลับ Google Maps ได้โดยไม่แก้โค้ด
- การบล็อก: ผู้ใช้ที่ถูกบล็อกจะถูกถอดจากสมาชิก active และยกเลิก booking `pending/confirmed` ผ่าน `leave_fitness_group`; ไม่สามารถจองใหม่ในก๊วนนั้นได้จนกว่าจะปลดบล็อก โดยผู้ดำเนินการต้องเป็นผู้จัดการก๊วน
- การมองเห็นรายชื่อผู้ถูกบล็อก: ผู้จัดการก๊วนทุกประเภท (owner/active group admin/Sheserved admin) มีสิทธิ์ดูและจัดการ blocklist; UI และ repository `listBlockedUsers(..., requesterUserId)` ตรวจสิทธิ์ก่อนคืนข้อมูลโปรไฟล์
- ข้อจำกัด security ปัจจุบัน: RLS ยังเป็น `USING(true)` และ legacy RPC รับ actor จาก client จึงยังไม่ใช่ cryptographic identity boundary; ช่วง compatibility ให้ Repository/App Layer ตรวจ `AuthService` ต่อไป และ Phase 13 จะย้าย private read/mutation ไป trusted Backend + secure RPC/strict RLS ก่อน revoke legacy path

## การปฏิบัติตามแนวทาง Security & Infrastructure

### Auth Data Guidelines (`auth_data_guidelines.md`)
- ❌ ห้ามใช้ `Supabase.instance.client.auth.currentUser` หรือ `_client.auth.currentUser` — ค่าเป็น `null` เสมอ
- ✅ ดึง `userId` จาก custom session ของโปรเจกต์ (`AuthService.instance.currentUser?.id` หรือ `ServiceLocator` abstraction ที่หน้าจอนั้นใช้อยู่)
- ✅ Repository ต้องรับ `userId`/`actorUserId` เป็นพารามิเตอร์ ไม่ดึงเองจาก Supabase Auth และ mutation สำคัญต้องตรวจว่า actor ตรงกับ current user จาก custom auth ก่อนดำเนินการ
- ✅ Repository ของ Find Fitness Buddies ต้องตรวจผู้จัดการก๊วนผ่าน `_requireGroupManager()` ก่อนแก้ไขก๊วน/รอบนัด/คำขอ/blocklist โดยยอมรับ owner, active group admin หรือ Sheserved admin
- ✅ UI (Presentation) ส่ง `userId`/`actorUserId` จาก custom auth เข้า Repository
- ช่วง compatibility: Owner rejoin และ group management ใช้ App-Layer authorization ตามเดิม; target Phase 13 ใช้ secure RPC ที่อ่าน `SET LOCAL app.user_id` จาก Backend และไม่เพิ่ม `auth.uid()` เพราะตัดสินใจคง custom AuthService

### BOLA/IDOR Prevention (`docs/secure/01_broken_object_level_authorization.md`)
- ⚠️ Backend endpoints ต้องใช้ `req.userId` จาก identity ที่ยืนยันแล้ว ไม่ใช่ `req.body.userId`
- ⚠️ ทุก endpoint ที่อ่าน/แก้ไข booking, member, blocklist และ owner participation ต้องตรวจสิทธิ์ผู้จัดการก๊วนก่อน (เช่น `member.role = 'admin' AND is_active=true`, `fitness_groups.created_by = req.userId` หรือ `users.role = 'admin'` ของ Sheserved)
- ⚠️ สำหรับ Flutter → Supabase RPC ใน custom-auth architecture ต้องรับ `userId` จาก `AuthService` ผ่าน Repository และตรวจ equality ก่อนเรียก; ห้ามถือ `p_user_id` จาก input อื่นเป็น identity ที่ยืนยันแล้ว
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
  - `capacity`: integer 1–30
  - `owner_auto_join`: boolean; แก้ไขได้เฉพาะ owner
  - `status`: enum allowlist `['pending','confirmed','cancelled','rejected']`
  - `role`: enum allowlist `['member','admin']`
  - `cancelled_by`: enum allowlist `['user','owner','system']`
  - `cancel_reason`: สูงสุด 200 ตัวอักษร
- DB constraints (CHECK, VARCHAR length, FK) เป็น defense layer สำรอง; constraint capacity 1–30 และ `owner_auto_join` ถูก apply แล้วผ่าน migration ของ Phase 9; ถ้า environment ใดยังไม่ apply migration ต้อง migrate ก่อนใช้งาน

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
- เลือก Trusted Backend Identity Bridge: signed access JWT + rotated opaque refresh session + server-side password/social verification โดยคง `AuthService` เป็น state container ของ Flutter
- ช่วง compatibility ก่อน cutover: App Layer และ legacy RPC ยังทำงานเพื่อไม่ให้ client ปัจจุบันเสีย แต่ยังไม่ถือเป็น cryptographic identity boundary
- หลัง Fitness cutover: private read/mutation ต้องผ่าน Backend ที่สร้าง `req.userId` จาก JWT ที่ verify แล้ว; Backend ตั้ง `SET LOCAL app.user_id` ภายใน transaction และใช้ secure RPC signature ที่ไม่รับ actor จาก client
- ห้ามใช้ `x-user-id`, unsigned JWT, service-role เป็น app request role หรือ direct-Supabase mutation fallback หลัง cutover

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
- ผู้ใช้ที่ล็อกอินสามารถ “สร้างก๊วน” ได้ตามสิทธิ์ และแก้ไข/จัดการก๊วนได้เฉพาะ owner/active group admin ของก๊วนนั้น หรือ admin Sheserved
- Dev build ใช้แผนที่จากผู้ให้บริการไม่มีค่าใช้จ่าย และสามารถสลับไป Google Maps ผ่าน config/env
- Toggle “ก๊วนส่วนตัว” แสดงในหน้าสร้างก๊วน (ค่าเริ่มต้น: ปิด = ก๊วนเปิด ยอมรับอัตโนมัติ; เปิด = ก๊วนส่วนตัว ต้องรออนุมัติ) — ฟิลด์เดียวนี้คือตัวกำหนดสถานะก๊วนส่วนตัว และก๊วนส่วนตัวยังแสดงในรายการเปิดรับตามปกติ
- ก๊วนเปิดที่ auto-accept เปลี่ยน booking เป็น `confirmed` โดยไม่แจ้งเตือนใคร; ก๊วนส่วนตัวเมื่อมี booking `pending` ใหม่จะแจ้งเตือนเจ้าของก๊วนผ่าน Headsector; เมื่ออนุมัติ/ปฏิเสธจะแจ้งผู้จอง, เมื่อผู้จองยกเลิกจะแจ้งเจ้าของก๊วน และเมื่อเจ้าของยกเลิกรอบ/ก๊วนจะแจ้งผู้จองทั้งหมด
- ป้องกันการจองซ้ำซ้อนตามช่วงเวลา หากทับซ้อนต้องอธิบายเหตุผลและไม่อนุญาต
- หน้ารายละเอียดการจองมีปุ่ม “ยกเลิกจอง”; เจ้าของก๊วนเปิด dialog จากโปรไฟล์ผู้จองเพื่อดูประวัติและ “บล็อกผู้ใช้” ได้
- Repository ดึง `userId` จาก `ServiceLocator.instance.currentUser?.id` เท่านั้น ไม่ใช้ `_client.auth.currentUser` (ตาม `auth_data_guidelines.md`)
- Backend endpoint ใช้ `req.userId` ไม่ใช่ `req.body.userId`; ตรวจ ownership ก่อนอ่าน/แก้ไข booking และ blocklist (ป้องกัน BOLA)
- DB schema มี CHECK constraints สำหรับ enum fields และ numeric range สำหรับ lat/lng
- Endpoint ใหม่มี rate limiter และ idempotency middleware
- Google Maps API key ไม่ถูก hardcode ใน source code (ใช้ dart-define/config)
- Security events (สร้างก๊วน, จอง, ยกเลิก, บล็อก) ถูก log แบบ structured logging
- กด "เข้าร่วมก๊วน" สร้าง booking โดยตรง (ไม่มีขั้นตอนสมัครสมาชิกแยก) และ `fitness_group_members` ถูก upsert อัตโนมัติในธุรกรรมเดียวกัน
- การสร้างรอบนัดรับ `capacity` ของรอบในขั้นตอนสร้าง/แก้ไข session; การ์ดและ Bottom Sheet แสดง confirmed/pending/available แยกต่อรอบ และไม่ใช้ผลรวม capacity หลายรอบแทนจำนวนสมาชิกก๊วน
- `book_fitness_session()` RPC ป้องกันทั้งการจองซ้ำ (`UNIQUE`), เกิน session capacity (`FOR UPDATE`), และจองซ้อนเวลา (`check_booking_overlap()`) แบบ atomic; pending ไม่กินที่นั่งและ approval ตรวจซ้ำก่อน confirm
- `owner_auto_join=true` สร้าง owner booking `confirmed` ในทุก upcoming session; การเปิด auto-join ตรวจ capacity และ overlap แบบ all-or-nothing
- Migration เพิ่ม `room_type`/`room_ref_id` ใน `chat_rooms` สำเร็จ และ `participant_ids` sync ถูกต้องเมื่อสมาชิก join/leave
- Headsector แจ้งเตือนคำขอ `pending` ของก๊วนส่วนตัว รวมถึงการอนุมัติ/ปฏิเสธ/ยกเลิก ผ่าน WebSocket real-time (ไม่ใช่ polling) และปรากฏใน `home_header_section.dart`; ก๊วนเปิดที่ auto-accept ไม่แจ้งเตือน
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
- การ์ดรายการก๊วน: แสดงสมาชิกก๊วนแบบข้อมูลประกอบ และสรุป **จำนวนว่างของแต่ละรอบนัด** (`confirmed / session.capacity`, `pending`, `available`); รูปสนาม/ปก, กีฬา, badge เพศ, คำอธิบาย, พื้นที่, รอบนัดถัดไปสูงสุด 3 รอบ
- CTA ในการ์ด:
  - ผู้ใช้ทั่วไป: ปุ่ม "เข้าร่วมก๊วน" (เปิดรายการรอบนัดให้เลือก) หรือ "เข้าร่วมก๊วนแล้ว"
  - ผู้ร้องขอที่ถูกบล็อก: แสดงสถานะ **"รอคิว"** แบบ disabled เพื่อใช้ถ้อยคำสุภาพและป้องกันการส่งคำขอซ้ำ (สถานะภายในยังเป็น `blocked`)
  - ผู้จัดการก๊วน: แถวปุ่ม "เข้าร่วมก๊วนแล้ว" + "เพิ่มรอบนัด" ชิดขวา
- แผ่นรายละเอียดก๊วน (Bottom Sheet):
  - รายการรอบนัดเป็น `ExpansionTile` แบบ session-first แสดง `ยืนยันแล้ว N / capacity คน · รออนุมัติ N คน · เหลือ N ที่` และรายชื่อผู้เข้าร่วม/คำขอของรอบนั้น
  - สมาชิกปัจจุบันหรือ owner ที่ปิด auto-join แล้วปัดหัวข้อรอบนัดจากขวาไปซ้ายเพื่อเปิด **เลือกเพิ่มรอบ**; ผู้จัดการก๊วนใช้หัวข้อเดียวกันเพื่อเปิด **แก้ไข/ยกเลิก**
  - แถวสมาชิกก๊วนรวมแสดง `สมาชิกก๊วนรวม N คน` แบบ distinct เป็นข้อมูลสิทธิ์ระดับก๊วน ไม่หักจาก session capacity
  - pending ใต้ session จัดการ **อนุมัติ/ปฏิเสธ booking รอบนั้น**; การบล็อกยังเป็น group-level และยกเลิก booking ของผู้ใช้ทั้งก๊วน
  - รายชื่อสมาชิก: avatar, บทบาท, สถานะ; ผู้จัดการก๊วนปัดซ้ายเพื่อ **แชท/บล็อก/ถอดออก**, สมาชิกทั่วไปปัดแถวตนเองเพื่อแชท; ผู้ถูกบล็อกถูกกรองออก
  - Section “ถูกบล็อก” แยกต่างหากและเห็นได้เฉพาะ owner/active group admin/admin Sheserved; ปัดรายชื่อไปทางซ้ายเพื่อเปิดปุ่ม “ปลด”
  - นำปุ่ม "จัดการบล็อกลิสต์" และ Blocklist Sheet แยกออกจาก UI
- ไฟล์หลักของหน้า: `lib/features/community/find_buddies/presentation/pages/sport_club_page.dart` (ไม่ใช่ `find_buddies_page.dart`)

## คำถามเปิด (เพื่อจัดลำดับรายละเอียด)
- กติกา moderation สำหรับก๊วนที่สร้างใหม่ (รายงาน/ปิดก๊วน/อัปเกรดเป็นแอดมิน)
- ต้องการผูกปฏิทิน/การแจ้งเตือนงานนัดหมายไหม (เฟสถัดไป)?

## Roadmap ปรับปรุงจากผลวิเคราะห์ Gap (2026-08-22) — เรียงตามความสำคัญ

> ผลตรวจสอบโค้ดจริง ณ 2026-08-25: หน้ารายการ/bottom sheet รายละเอียด/สร้างก๊วน/สร้างรอบนัด/จอง-อนุมัติผ่าน RPC/เสนอ-รีวิวกีฬา/booking detail/WebSocket headsector/migrations/ก๊วนของฉัน/แชท/บล็อก/แชท popup ฝั่ง ChatRoomPage, swipe actions ในรายละเอียดก๊วน และ owner participation/owner rejoin ตาม Phase 9 ทำครบแล้ว — ช่องว่างที่เหลือคือการทดสอบ E2E (Phase 6) และการทดสอบ regression บน environment จริง

### Phase 1 — ปักหมุดพิกัดตอนสร้างก๊วน + Pagination ✅ เสร็จแล้ว (ปรับ page size 10 และ filtered-page loading 2026-08-30)
- ปัญหา: ฟอร์ม `create_group_page.dart` ไม่มีการเก็บ `lat/lng` เลย → ก๊วนใหม่ไม่มีพิกัด, มุมมองแผนที่ใน `sport_club_page.dart` ไม่มี marker, ตัวกรองรัศมี (กม.) ไม่ทำงานจริง
- งาน:
  - เพิ่ม MapCard ใน create group: `flutter_map` (OSM) พร้อมพินลากได้ + ปุ่ม "ใช้ตำแหน่งฉัน" (geolocator, opt-in) + แสดงพิกัดสรุป
  - บันทึก `lat/lng` ผ่าน `createGroup()` (คอลัมน์ `fitness_groups.lat/lng` มีอยู่แล้วพร้อม CHECK constraint)
  - Validation: ถ้าเปิดใช้ตัวกรองรัศมี ก๊วนที่ไม่มีพิกัดให้ fallback แสดงตามจังหวัด
  - **Pagination / infinite scroll:** เพิ่ม `limit/offset` ใน `listGroups()` + `ScrollController`; แสดงครั้งละ **10 การ์ด** และดึงชุดถัดไปเมื่อเลื่อนเข้าใกล้ท้ายรายการ
  - หากการกรองฝั่ง client ตัดก๊วนออก ระบบอ่าน raw page ถัดไปต่อจนได้การ์ดที่แสดงครบ 10 ใบหรือข้อมูลหมด เพื่อไม่ให้หน้าจอว่างและไม่ข้าม offset
- สถานะ: ✅ ทำครบ — `MapCard` + ปุ่ม "ใช้ตำแหน่งฉัน" + สรุปพิกัดใน `create_group_page.dart`, ส่ง `lat/lng` ผ่าน `createGroup()`, `listGroups()` รองรับ `limit/offset`, `sport_club_page.dart` มี `ScrollController` + `_loadMore()` แบบ page size 10 + `_hasMore` flag

### Phase 2 — Join flow สมบูรณ์ ✅ เสร็จแล้ว (2026-08-22)
- **เลือกรอบนัดเอง (ตัดสินใจแล้ว 2026-08-22):** เปลี่ยนปุ่ม "เข้าร่วมก๊วน" จากจองรอบใกล้สุดอัตโนมัติ → เปิด bottom sheet รายการรอบนัดให้ผู้ใช้เลือกรอบก่อน แล้วค่อยเรียก `bookSession()`
- **สถานะ "รออนุมัติ" บน CTA:** ผู้จองก๊วนส่วนตัวที่ booking ยัง `pending` ให้การ์ด/bottom sheet แสดง "รออนุมัติ" (disabled) แทน "เข้าร่วมก๊วนแล้ว"
- **Redirect + intent:** หลัง login สำเร็จ ให้กลับมาที่ก๊วนเดิมพร้อม `intent=join_group` เพื่อเปิด sheet เลือกรอบต่อทันที (ปัจจุบัน redirect กลับแค่ `/community/sport-club` ระดับ list)
- **Draft ฟอร์มสร้างก๊วน:** ถ้าโดนพาไป login ระหว่างกด "บันทึก" ให้ serialize text/scalar fields (ชื่อ, คำอธิบาย, sportId, เพศ, toggle, จังหวัด/อำเภอ, lat/lng, coverImageUrl, venuePhotoUrl) ลง `SharedPreferences` key `create_group_draft` เป็น JSON — ไม่เก็บ session capacity ใน draft ก๊วน — บันทึกเฉพาะตอน redirect ไป login (ไม่ auto-save ทุก keystroke) — restore ใน `initState`/`didChangeDependencies` เมื่อกลับจาก login — ลบ draft ทันทีหลังสร้างสำเร็จหรือ restore แล้ว — ใส่ TTL 1 ชั่วโมงกัน draft ค้าง
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
- **แก้ไขก๊วน:** หน้า/sheet แก้ไข (ชื่อ, คำอธิบาย, ภาพ, เพศ, toggle `requires_owner_approval`, พิกัด) เฉพาะผู้จัดการก๊วน — owner/controller ผ่าน `created_by`, active group admin ผ่าน membership หรือ admin Sheserved (`users.role='admin'`); ไม่แก้ session capacity จากหน้าแก้ไขก๊วน
- **Owner participation:** เพิ่ม toggle “เข้าร่วมทุกรอบอัตโนมัติ” ใน create/edit ค่าเริ่มต้นเปิด; เมื่อเปิดจะสร้าง owner booking `confirmed` ให้ทุก upcoming session; เมื่อปิดระบบถามว่าจะคงหรือยกเลิก booking อนาคต
- **Owner auto-join guard:** เปิดกลับได้แบบ all-or-nothing เมื่อทุก upcoming session มีที่ว่างและรอบ upcoming ของก๊วนไม่ทับเวลา; ถ้าไม่ผ่านจะไม่เปลี่ยน flag และไม่สร้าง booking บางส่วน
- **ปุ่มถอนเจ้าของ:** ในแถวสมาชิกของ owner ให้แสดงปุ่ม “ถอน” ผ่านเมนู swipe เดียวกับ “แชท”/เมนูจัดการอื่น; การถอนยกเลิก booking owner ในรอบอนาคตและคงสิทธิ์ผู้ดูแลผ่าน `created_by`; owner ที่ opt-out แล้วจองเฉพาะรอบได้เองโดยไม่เปิด auto-join กลับ
- **เพิ่ม/แก้ไข/ยกเลิกรอบนัด:** ผู้จัดการก๊วน (owner/active group admin/admin Sheserved) เท่านั้น; `createSession()`, `updateSession()` และ `cancelSession()` ตรวจ `actorUserId` กับ custom `AuthService` และตรวจสิทธิ์ก๊วนก่อน direct mutation; `createSession()`/`updateSession()` รับและตรวจ session capacity
- **อนุมัติ/ปฏิเสธคำขอ:** ผู้จัดการก๊วนเท่านั้น; repository ตรวจ actor ก่อนเรียก RPC และ RPC `approve_fitness_session_booking()` ตรวจ owner, active group admin หรือ admin Sheserved ซ้ำ
- **ออกจากก๊วน:** เพิ่ม `leaveGroup()` — ตั้ง `fitness_group_members.is_active=false` + ยกเลิก booking `pending/confirmed` ทั้งหมดแบบ cascade ใน transaction เดียว ผ่าน RPC `leave_fitness_group(p_group_id, p_user_id, p_actor_id)`; self-leave ใช้ current user, admin remove ส่ง actor จาก `AuthService`, และ admin Sheserved สามารถถอดสมาชิกที่ไม่ใช่ owner ได้
- **Blocklist UI:** รายชื่อสมาชิก/pending มี swipe ปุ่มบล็อก; ผู้ถูกบล็อกถูกถอดจากสมาชิก active และย้ายไป section “ถูกบล็อก” ซึ่งมองเห็นและจัดการได้โดย owner/active group admin/admin Sheserved; ปัดแถวผู้ถูกบล็อกเพื่อเปิดปุ่ม “ปลด”; ไม่มีปุ่ม/Blocklist Sheet แยกแล้ว; repository guard อยู่ใน `listBlockedUsers(..., requesterUserId)` และ `book_fitness_session()` RPC ตรวจ blocklist
- **หน้า "ก๊วนของฉัน":** หน้ารวมก๊วนที่ผู้ใช้สร้าง/เข้าร่วม + ประวัติการจองทั้งหมด (ปัจจุบันไม่มีที่ดูรวม — ดูได้เฉพาะ booking detail ทีละรายการ) — เพิ่ม route `/community/sport-club/my-groups`
- **สถานะ:** ✅ ทำครบแล้วตามโค้ดจริง (รวม Phase 9 owner participation/rejoin) — `updateGroup()`/`updateSession()`/`leaveGroup()`/`blockUser()`/`unblockUser()`/`listBlockedUsers()` พร้อมใช้งาน, มี sheet แก้ไขก๊วนและรอบนัด, owner ถอน/กลับเข้าร่วมผ่าน flow ที่กำหนด, section ผู้ถูกบล็อกแบบ swipe, และหน้า `MyGroupsPage` + route `/community/sport-club/my-groups`
- **บันทึกการย้าย capacity:** เดิม DB กำหนด `fitness_groups.capacity` เป็นจำนวนสมาชิกก๊วน; แนวทางใหม่ย้ายการจำกัดจำนวนคนไป `fitness_group_sessions.capacity` และคงคอลัมน์เดิมไว้ชั่วคราวเพื่อ backfill ข้อมูลเก่าเท่านั้น
- **บันทึกสาเหตุ owner rejoin ใช้ไม่ได้:** ห้ามใช้ `auth.uid()` ใน RPC เพราะโปรเจกต์ใช้ custom `AuthService` และ Supabase Auth session เป็น `null`; Repository ต้องตรวจ `userId` กับ `AuthService.instance.currentUser?.id` ก่อนเรียก RPC และ RPC ต้องใช้ `created_by` เพื่อแยก owner พร้อมคง invoker scope ตาม custom-auth policy
- **บันทึกสาเหตุออก/ถอดสมาชิกไม่สำเร็จ:** Repository เรียก `leave_fitness_group` แต่ไม่มี function นี้ใน migrations จึงเกิด PostgREST `schema cache ... no matches`; แก้ด้วย migration `20260825110000_fitness_buddies_leave_group.sql` ซึ่งสร้าง RPC แบบ atomic รับ `p_group_id`, `p_user_id`, `p_actor_id`, ตรวจ actor จาก custom-auth App Layer, ป้องกัน owner ถูกถอดผ่าน leave flow และยกเลิก booking `pending/confirmed` พร้อม deactivate membership

### Phase 5 — Auto-reject pending timeout (Supabase scheduled cleanup) ✅ เสร็จแล้ว (2026-08-23)
- **เหตุผลที่เลือกแนวนี้ (Option A):** booking ถูกสร้างจาก Flutter → Supabase RPC โดยตรง ไม่ผ่าน backend request lifecycle การใช้ BullMQ delayed job enqueue ตอนสร้าง booking จะเกิด dual-write risk และเพิ่ม coupling กับ websocket-server โดยไม่จำเป็น DB เป็น source of truth อยู่แล้ว เงื่อนไข timeout ทั้งหมด (`status`, `starts_at`, `created_at`, `requires_owner_approval`) อยู่ในฐานข้อมูล — ให้ DB/RPC จัดการ atomic ปลอดภัยกว่า
- **งาน:**
  - สร้าง RPC `auto_reject_expired_fitness_bookings()` ใน Supabase migration
  - เงื่อนไข reject: `status = 'pending'` และเลย deadline (`created_at + interval '24 hours'` หรือ `starts_at - interval '1 hour'` แล้วแต่เงื่อนไขใดถึงก่อน)
  - update เป็น `status = 'rejected'`, `cancelled_by = 'system'`, `cancel_reason = 'AUTO_TIMEOUT'`
  - ใช้ Supabase scheduled job (`pg_cron` หรือ `pg_net`) เรียก RPC ทุก 5-15 นาที
  - Notification: ✅ ใช้ `pg_notify('fitness_booking_status_updates', ...)` จาก RPC แล้ว `websocket-server` ฟัง `LISTEN` แล้ว broadcast ผ่าน `fitness_booking_status` ไปยังผู้ใช้ที่เกี่ยวข้อง
- หมายเหตุ: ไม่เพิ่ม backend proxy/rate limiting/idempotency ในรอบนี้ — ใช้ Repository/App-Layer guard ร่วมกับ RPC ที่ตรวจ manager role; RLS ของ fitness tables ยัง permissive ตาม custom-auth architecture (ดูหัวข้อความปลอดภัยและสิทธิ์)

### Phase 6 — Maestro UI Tests ⏳ รอทำ
- สร้าง test flows ตาม Milestone 5 เดิม:
  - `view_groups.yaml` — เปิดดูรายการก๊วน, สลับหมวดกีฬา, เปิด filter dialog, สลับมุมมองแผนที่
  - `join_group.yaml` — กดเข้าร่วมก๊วน (ต้องล็อกอิน), เลือกรอบนัด, ยืนยันการจอง
  - `create_group.yaml` — สร้างก๊วนใหม่ + สร้างรอบนัดแรก
  - `owner_approval.yaml` — เจ้าของก๊วนปัดคำขอเข้าร่วมเพื่ออนุมัติ/ปฏิเสธ/บล็อก และเลือก booking เป็นรายรอบ
  - `session_swipe_actions.yaml` — owner/active group admin/admin Sheserved ปัดรอบนัดเพื่อแก้ไข/ยกเลิก และตรวจ action responsive บนหน้าจอแคบ

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
แทนที่ Bottom Sheet "จัดการ" ผู้เข้าร่วมรอบนัด (`_showManageSessionSheet`) ด้วย **swipe actions บนรอบนัดและรายชื่อสมาชิกโดยตรง** ใน Bottom Sheet รายละเอียดก๊วน (`_showGroupDetailSheet`) — ผู้จัดการก๊วน (owner/active group admin/admin Sheserved) ปัดรายการเพื่อเปิดเมนูจัดการ ไม่ต้องเปิด sheet จัดการผู้เข้าร่วมซ้อนอีกชั้น

### ข้อตกลงที่ยืนยันแล้ว (2026-08-23)
| หัวข้อ | การตัดสินใจ |
|---|---|
| ทิศทางสไลด์ | **ปัดซ้าย ปุ่มโผล่ด้านขวา** (`flutter_slidable` `endActionPane` — pattern มาตรฐาน iOS/Android) |
| ปุ่มใน swipe ของรอบนัด (admin) | **แก้ไข** (สีหลัก) + **ยกเลิก** (แดง); action pane responsive และย่อไอคอน/ข้อความอัตโนมัติเมื่อพื้นที่แคบ |
| คำขอรออนุมัติ (pending) | แสดง **ใต้รอบนัดที่ผู้ขอเลือก** ใน session-first view; ผู้จัดการก๊วนจัดการ booking เป็นรายรอบ |
| ผู้ถูกบล็อก | ไม่แสดงใน pending/“เข้าร่วมแล้ว”; แสดงใน section **“ถูกบล็อก”** เฉพาะ owner/active group admin และ admin Sheserved |
| ปุ่มใน swipe ของสมาชิก (ผู้จัดการก๊วน) | **แชทก๊วน** (ฟ้า) + **บล็อก** (เทา) + **ถอดออกจากก๊วน** (แดง) |
| ปุ่มใน swipe ของสมาชิก (ไม่ใช่ผู้จัดการก๊วน) | **แชทก๊วน** (ฟ้า) — แถวอื่นปัดไม่ได้, แถวตัวเองปัดได้แค่แชท |
| ปุ่มใน swipe ของหัวข้อรอบนัด | สมาชิกปัจจุบันหรือ owner ที่เลือกเข้าร่วมเองเห็น **“เลือกเพิ่มรอบ”**; ผู้จัดการก๊วนเห็น **“แก้ไข”** + **“ยกเลิก”** |
| ปุ่มใน swipe ของผู้เข้าร่วม confirmed | ผู้จัดการก๊วนเห็น **“ถอดจากรอบนี้”** เฉพาะสมาชิกที่ไม่ใช่ owner; ไม่กระทบ membership/booking รอบอื่น |
| ปุ่มใน swipe ของคน pending | **อนุมัติ** (เขียว) + **ปฏิเสธ booking รอบนี้** (แดง) + **บล็อกผู้ใช้ระดับก๊วน** (เทา) สำหรับผู้จัดการก๊วน |
| ขอบเขตการอนุมัติ | session-first view แสดง pending ใต้รอบที่เลือกและจัดการ booking นั้นโดยตรง; ถ้าบล็อกให้ยืนยันว่าการบล็อกจะยกเลิก booking ของผู้ใช้ทั้งก๊วน |
| Bottom Sheet "จัดการ" เดิม | **ยกเลิก** — ลบ `_showManageSessionSheet()` และปุ่ม "จัดการ" ออก |

### สภาพปัจจุบันหลังปรับ UI
- `_showManageSessionSheet(sessionId, groupId)` — **ถูกลบ**; การอนุมัติ/ปฏิเสธผู้เข้าร่วมย้ายมาอยู่ใน section pending ของ Bottom Sheet รายละเอียดก๊วน
- ปุ่ม "จัดการ" ในแถวจำนวนสมาชิก (`_showGroupDetailSheet`) — **ถูกลบ**
- รายชื่อสมาชิก (`listGroupMembers`) แสดงเฉพาะ `is_active=true` และเป็นสมาชิกแบบไม่ซ้ำ; confirmed booking ถูกจัดเข้ารอบใน session-first view ส่วน pending ถูกจัดเข้ารอบจาก `listGroupPendingBookings(groupId, requesterUserId)`
- แต่ละรอบนัดใช้ `ExpansionTile` แสดงผู้เข้าร่วม/คำขอของรอบนั้น; `Slidable` ของหัวข้อรอบนัดแสดง `เลือกเพิ่มรอบ` สำหรับสมาชิกปัจจุบัน และ `แก้ไข`/`ยกเลิก` สำหรับผู้จัดการก๊วน
- `flutter_slidable: ^4.0.3` มีใน `pubspec.yaml` แล้ว (ตัวอย่างการใช้: `triage_victim_card.dart`, `health_article_comment_item.dart`)

### รายการที่ implement แล้ว

**8.1 ✅ เพิ่ม repository method `listGroupPendingBookings(groupId, requesterUserId)`** (`fitness_buddies_repository.dart`)
- ตรวจสิทธิ์ requester เป็น owner/active group admin/admin Sheserved ก่อนดึงข้อมูล
- ดึง `fitness_group_bookings` ที่ `status='pending'` ของทุกรอบนัดในก๊วน (join `fitness_group_sessions` และ filter ตาม `group_id`) พร้อม `created_at`, user profile (id, first_name, last_name, profile_image_url) และข้อมูลรอบนัด (id, group_id, starts_at, ends_at)
- จัดกลุ่มตาม session ฝั่ง client เพื่อแสดงแต่ละคำขอใต้รอบที่เกี่ยวข้อง; `created_at` ของ booking แต่ละรายการใช้แสดงเวลาที่ผู้ใช้ส่งคำขอ

**8.1.1 ✅ เพิ่ม `listMyPendingBookingsForGroup(groupId, userId)` สำหรับผู้ขอ**
- ดึงเฉพาะ booking ของ `userId` ที่ `status='pending'` ใน session ของก๊วนนี้ พร้อม `created_at`, session และ profile ของตนเอง
- เรียก `_assertCurrentUser(userId)` ก่อน query เพื่อไม่ให้ client ขอ pending ของ user อื่น
- ใช้เมื่อผู้ดูรายละเอียดไม่ใช่ manager; ห้ามใช้ query รายการ pending ทั้งก๊วนในกรณีนี้

**8.2 ✅ Session-first participant sections ใน `_showGroupDetailSheet`**
- แต่ละ `ExpansionTile` เป็นรอบนัดหนึ่งรอบ แสดง capacity summary และรายชื่อ **ผู้เข้าร่วมรอบนี้** จาก confirmed bookings แบบ distinct
- ผู้จัดการก๊วนปัดรายชื่อ confirmed ใต้รอบเพื่อเปิด **ถอดจากรอบนี้**; ห้ามแสดง action นี้กับ owner และต้องคง membership/booking ของรอบอื่น
- คำขอ `pending` แสดงใต้ session ที่ผู้ขอเลือกโดยตรง ไม่รวมเป็นรายการกลางที่ต้องไล่จับคู่กับเวลา
- ผู้จัดการก๊วนเห็น pending ของทุกคน; สมาชิก/ผู้ขอเห็นเฉพาะ pending ของตนเอง และไม่เห็นข้อมูลผู้ขอรายอื่น
- pending แต่ละรายการแสดง `รออนุมัติ` และเวลาที่ส่งคำขอจาก `fitness_group_bookings.created_at` ในรูปแบบวันที่/เวลาไทย
- pending แต่ละรายการใช้ `Slidable` (`endActionPane`): **อนุมัติ booking รอบนี้** / **ปฏิเสธ booking รอบนี้** / **บล็อกผู้ใช้ระดับก๊วน**
- การบล็อกต้องถือเป็น group-level action และยกเลิก booking ของผู้ใช้ทั้งก๊วนตาม policy; การอนุมัติ/ปฏิเสธกระทบเฉพาะ booking ของ session นั้น
- section `สมาชิกก๊วนรวม (ไม่ซ้ำ)` คงไว้เป็นข้อมูล membership/role และ action จัดการสมาชิก ไม่ใช้แทนรายชื่อผู้เข้าร่วมแต่ละ session
- Header แสดง `สิทธิ์ของคุณ` แยกจาก global user role; รายชื่อสมาชิกระบุ `เจ้าของก๊วน` แยกจาก `ผู้ดูแล` และ `สมาชิก` เพื่ออธิบายเหตุผลของสิทธิ์อนุมัติ
- ไม่มีผู้เข้าร่วมหรือคำขอในรอบนั้น → แสดงข้อความว่างภายใน ExpansionTile

**8.3 ✅ Swipe actions บนหัวข้อรอบนัด**
- ห่อหัวข้อรอบนัดด้วย `Slidable` (`endActionPane`, `motion: ScrollMotion`)
- สมาชิกปัจจุบันหรือ owner ที่ปิด auto-join แล้วปัดซ้ายเพื่อเปิด **เลือกเพิ่มรอบ** และเปิด session picker เดิม; ไม่มีปุ่มเลือกเพิ่มรอบหลักด้านล่าง
- ผู้จัดการก๊วนปัดซ้ายเพื่อเปิด **แก้ไข** และ **ยกเลิก** ทางขวา
- กด "แก้ไข" เปิด `_showEditSessionSheet()`; กด "ยกเลิก" แสดง dialog ยืนยันก่อนเรียก `cancelSession()`
- `ExpansionTile` รอบแรกและรอบที่มี pending เปิดให้เห็นรายละเอียดโดยอัตโนมัติ; รอบอื่นย่อได้เพื่อลดความยาว Bottom Sheet
- ใช้ custom responsive action (`CustomSlidableAction` + `FittedBox`) เพื่อให้ไอคอน/ข้อความปรับขนาดพอดีกับพื้นที่บนหน้าจอแต่ละขนาด

**8.4 ✅ Swipe actions บนรายชื่อสมาชิก** (ทุกคนปัดแถวตัวเองได้, ผู้จัดการก๊วนปัดแถวคนอื่นได้)
- ห่อ `ListTile` สมาชิกด้วย `Slidable` (`endActionPane`, `motion: ScrollMotion`)
- **แถวตัวเอง** (ทุกคน ไม่ว่าจะเป็น admin หรือสมาชิกทั่วไป):
  - ปุ่ม: **แชทก๊วน** (ฟ้า, `Icons.chat_bubble_outline` → `showGroupChatPopup(...)`)
- **แถวสมาชิกคนอื่น** (เฉพาะผู้จัดการก๊วน, `memberUserId != currentUserId` และ member ไม่ใช่ admin):
  - ปุ่ม: **แชทก๊วน** (ฟ้า) + **บล็อก** (เทา, `Icons.block` → `_blockUserDialog`) / **ถอดออกจากก๊วน** (แดง, `Icons.person_remove` → confirm dialog → `leaveGroup(groupId, memberUserId)`); actor ของ action มาจาก `AuthService`
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
- กด “ปลด” เรียก `unblockUser()` ได้โดยไม่ตรวจจำนวนสมาชิกก๊วน เพราะไม่มี group capacity แล้ว; การปลดบล็อกไม่สร้าง booking และไม่จองที่นั่งของ session ใด
- หลังปลดบล็อก ผู้ใช้จะต้องเลือก session และจองตาม `fitness_group_sessions.capacity` ของรอบนั้นเอง; ถ้ารอบเต็ม ระบบปฏิเสธการจองด้วย `SESSION_FULL`
- เมื่อปลดสำเร็จให้ refresh Bottom Sheet/รายการก๊วนทันที
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
- กด “ปลด” → ปลดบล็อกได้โดยไม่ตรวจ capacity ระดับก๊วน เพราะการปลดไม่สร้าง booking; ผู้ใช้ต้องเลือก session และจองตาม capacity ของรอบนั้นภายหลัง
- ผู้ถูกบล็อกไม่ปรากฏใน pending/“เข้าร่วมแล้ว” และไม่ถูกนับในจำนวนสมาชิก/จำนวนว่างของ session
- เจ้าของก๊วนและ admin Sheserved เห็น section “ถูกบล็อก”; group admin คนอื่นและสมาชิกทั่วไปไม่เห็นข้อมูลรายชื่อผู้ถูกบล็อก
- บล็อกสมาชิกแล้ว membership เป็น inactive และ booking `pending/confirmed` ถูกยกเลิก
- ผู้ใช้ที่ส่งคำขอเข้าก๊วนส่วนตัวเห็น CTA “รออนุมัติ” และยังไม่ปรากฏใน “เข้าร่วมแล้ว”/member count/ก๊วนของฉัน/สิทธิ์แชท
- ผู้ร้องขอที่ถูกบล็อกเห็น CTA “รอคิว” แบบ disabled และไม่สามารถส่งคำขอซ้ำ
- หลัง admin อนุมัติ booking ผู้ใช้จึงปรากฏใน “เข้าร่วมแล้ว” และได้รับสิทธิ์สมาชิกตามปกติ
- `flutter analyze` ผ่านไม่มี error ใหม่

---

## Phase 9 — Owner Participation + Session Capacity ✅ implement แล้ว (2026-08-25)

### ข้อตกลงที่ยืนยันแล้ว
- ระยะแรกไม่จำกัดจำนวนสมาชิกแบบไม่ซ้ำรวมทั้งก๊วน; `fitness_group_members` ใช้บอก membership/role และแสดงจำนวนสมาชิกเท่านั้น
- `fitness_group_sessions.capacity` คือจำนวนผู้เข้าร่วมสูงสุดของรอบนัดแต่ละรอบ ช่วง 1–30 คน; ไม่รวม capacity ของหลายรอบเข้าด้วยกัน
- `owner_auto_join=true` เป็นค่าเริ่มต้น และสร้าง booking `confirmed` ของ owner ให้ทุก upcoming session โดย owner กิน 1 ที่นั่งต่อรอบ
- เมื่อปิด auto-join ระบบถามทุกครั้งว่าจะคงหรือยกเลิก booking ของ owner ในรอบอนาคต; ถ้าคงไว้ owner ยังเป็นผู้เข้าร่วมรอบนั้นได้ แต่ไม่ถูกเพิ่มอัตโนมัติในรอบใหม่
- เมื่อ owner ปิด auto-joinแล้วจองรอบเอง booking เป็น `confirmed` โดยไม่เปิด auto-join กลับ; owner active ตาม explicit confirmed booking
- เมื่อเปิด auto-join กลับ ระบบสร้าง/เปิดใช้ booking ของ owner ให้ครบทุก upcoming sessionแบบ atomic; ถ้ารอบใดไม่มีที่ว่างหรือ upcoming sessions ทับเวลา ให้ปฏิเสธทั้งชุด
- `pending` ไม่กินที่นั่ง; นับเฉพาะ `confirmed` ต่อ session เพื่อหา `available_count` และตรวจ capacity ซ้ำตอน approval
- owner ยังคงจัดการก๊วนผ่าน `fitness_groups.created_by` แม้ไม่มี membership active

### งานที่ implement แล้ว
- Migration `20260825130000_fitness_buddies_session_capacity.sql`: เพิ่ม `fitness_group_sessions.capacity`, backfill จาก legacy `fitness_groups.capacity`, เพิ่ม owner booking ของ upcoming sessions เดิม และคง group capacity เดิมไว้ชั่วคราวเพื่อ compatibility
- Migration ปรับ `book_fitness_session()` ให้ lock session, ใช้ `s.capacity`, นับ confirmed เฉพาะ session นั้น, ตรวจ blocklist และไม่เปลี่ยน owner auto-join เมื่อ owner จองเอง
- Migration ปรับ `approve_fitness_session_booking()` ให้ lock session และตรวจ confirmed capacity ก่อนอนุมัติ
- Migration เพิ่ม trigger/RPC สำหรับ owner booking อัตโนมัติ, ตรวจ overlap/capacity แบบ all-or-nothing และรองรับการคง/ยกเลิก owner booking เมื่อปิด auto-join
- Create Group UI/Repository: นำช่องจำนวนสมาชิกสูงสุดออก; ค่า legacy ไม่ถูกส่งจาก flow สร้างก๊วนใหม่
- Create/Edit Session UI/Repository: เพิ่ม field จำนวนผู้เข้าร่วมสูงสุดของรอบ และป้องกันลดต่ำกว่าจำนวน confirmed
- Query/UI: เพิ่ม `confirmed_count`, `pending_count`, `available_count` ต่อ session; เปลี่ยน Bottom Sheet เป็น session-first แสดงผู้เข้าร่วม/คำขอใต้แต่ละรอบ และคงสมาชิกก๊วนรวมแบบ distinct เป็น section แยก; สมาชิกปัจจุบันเลือกเพิ่มรอบผ่าน swipe ที่หัวข้อ session
- UI เพิ่ม action `ถอดจากรอบนี้` สำหรับผู้จัดการก๊วนบน confirmed participant ที่ไม่ใช่ owner; action นี้ไม่กระทบ booking รอบอื่น
- Apply สำเร็จแล้ว: migration `20260830170000_fitness_buddies_session_participant_management.sql` สำหรับ RPC ถอด confirmed booking รายรอบแบบ atomic; ห้ามรัน migration นี้ซ้ำ
- Unblock: ไม่ตรวจ group capacity อีกต่อไป; การปลดบล็อกไม่สร้าง booking ผู้ใช้ต้องเลือกและจอง session เอง

### Regression checklist
- สร้างก๊วนโดยไม่ระบุจำนวนสมาชิกสูงสุดได้ และยังสร้าง session พร้อม capacity ได้
- มีหลาย session ที่ capacity ต่างกันได้ และแต่ละรอบแสดง confirmed/pending/available แยกกัน
- Bottom Sheet เป็น session-first; ผู้เข้าร่วมและ pending แสดงใต้รอบที่เกี่ยวข้อง และสมาชิกก๊วนรวมไม่ซ้ำอยู่ใน section แยก
- สมาชิกปัจจุบันปัดหัวข้อ session เพื่อเลือกเพิ่มรอบ; ผู้จัดการก๊วนยังเข้าถึงแก้ไข/ยกเลิกจากหัวข้อเดียวกัน
- ผู้ใช้คนเดียวจองหลาย sessionได้ แต่ถูกนับสมาชิกก๊วนเพียง 1 คน และถูกนับที่นั่งแยกในแต่ละ session
- ผู้จัดการก๊วนถอดสมาชิกจาก session หนึ่งได้โดย booking รอบอื่นและ role/membership ยังอยู่; ถ้าไม่มี confirmed booking อื่นให้ deactivate membership ของสมาชิกทั่วไป
- ปุ่ม `ถอดออกจากก๊วนทั้งหมด` ยกเลิก membership และ booking ทุก session; owner ยังคงถูกป้องกันและต้องใช้ owner participation toggle
- pending หลายคนไม่ลด available จนกว่าจะอนุมัติ; เมื่ออนุมัติพร้อมกัน session ต้องไม่เกิน capacity
- ผู้ขอทั่วไปเห็นเฉพาะ `คำขอของฉัน` ใต้ session ที่ตนเองเลือก พร้อม `created_at` ในรูปแบบเวลาไทย; ไม่เห็นชื่อ/เวลาของผู้ขอรายอื่น
- owner/active group admin/Sheserved admin เห็น pending ทั้งก๊วนและ action อนุมัติ/ปฏิเสธ/บล็อก; สมาชิกทั่วไปไม่มี action จัดการ
- Bottom Sheet แสดง `สิทธิ์ของคุณ` และ label `เจ้าของก๊วน` แยกจาก `ผู้ดูแล`/`สมาชิก`
- ลด session capacity ต่ำกว่า confirmed ไม่ได้
- owner auto-join สร้าง booking confirmed ในทุก upcoming session; session ใหม่ก็สร้าง owner booking อัตโนมัติ
- ปิด owner auto-join แล้วถามว่าจะคงหรือยกเลิก booking อนาคต; owner จองเฉพาะรอบเองได้โดยไม่เปิด auto-join กลับ
- เปิด owner auto-join กลับเมื่อมี session เต็มหรือ session ทับเวลา ต้องไม่เปลี่ยนสถานะและไม่สร้าง booking บางส่วน
- ตรวจ CTA, member count, จำนวนว่างรายรอบ, pending/confirmed, หน้า “ก๊วนของฉัน”, สิทธิ์แชท และสิทธิ์ admin ให้ตรงกัน

---

## Phase 10 — ปรับปรุง Loading/Refresh UX ของหน้า “หาเพื่อนออกกำลังกาย” ✅ implement แล้ว (2026-08-25)

### ปัญหาที่พบ
- ผู้ใช้ยังเห็น `CircularProgressIndicator` กลางจอเมื่อเข้าหน้า “หาเพื่อนออกกำลังกาย” แม้ลบตัวโหลดของปุ่มรีเฟรชใน header ไปแล้ว
- สาเหตุ: ใน `sport_club_page.dart` มีตัวโหลดอีกจุดคือ
  ```dart
  child: _loading
      ? const Center(child: CircularProgressIndicator())
      : _showMapView ? _buildMapView() : RefreshIndicator(...)
  ```
  โดย `_loading` เริ่มต้นเป็น `true` และเปลี่ยนเป็น `false` หลัง `_init()` โหลดข้อมูลเสร็จ จึงทำให้ผู้ใช้เห็นวงกลมหมุนกลางจอทุกครั้งที่เปิดหน้า

### วิธีแก้ไข
- ลบเงื่อนไข `_loading ? Center(CircularProgressIndicator)` ออกจาก body ของหน้า
- ใช้ **Skeleton Card** (`_buildSkeletonCard()` ที่มีอยู่แล้ว ใช้ `Shimmer`) แสดง 3 รายการแทนระหว่างโหลดครั้งแรกและระหว่างรีเฟรช:
  ```dart
  if (_loading || _reloadingGroups)
    for (var i = 0; i < 3; i++) _buildSkeletonCard(),
  ```
- ระหว่าง `_loading`/`_reloadingGroups` ให้ซ่อน `_groups` เดิมทั้งหมด ไม่ render skeleton ปนกับการ์ดข้อมูล; การ์ดเดิมค่อยแสดงเมื่อ request เสร็จ ส่วน `_isLoadingMore` คงการ์ดเดิมและแสดง spinner ต่อท้าย
- ปรับเงื่อนไขการเลือก Map view ให้รอจนโหลดเสร็จก่อน:
  ```dart
  child: _showMapView && !_loading
      ? _buildMapView()
      : RefreshIndicator(...)
  ```
- ปุ่มรีเฟรชใน header แสดงไอคอน `Icons.refresh` คงที่ ไม่สลับเป็น `CircularProgressIndicator` ระหว่างโหลด; ป้องกันกดซ้ำด้วย `_reloadingGroups`
- คง `CircularProgressIndicator` จุดอื่นที่จำเป็นไว้ เช่น โหลดเพิ่ม (`_isLoadingMore`), บันทึกฟอร์ม, และ `FutureBuilder` ใน dialog

### ไฟล์ที่เกี่ยวข้อง
- `lib/features/community/find_buddies/presentation/pages/sport_club_page.dart`

### สาเหตุ/วิธีป้องกัน (บันทึกเพื่อไม่ให้เกิดซ้ำ)
- การลบตัวโหลดในจุดเดียวไม่เพียงพอ ต้องตรวจทุกจุดที่ใช้ `_loading`/`_reloadingGroups` ร่วมกับ `CircularProgressIndicator`
- ควรใช้ skeleton/shimmer สำหรับ loading state หลักของหน้า list เพื่อให้ผู้ใช้เห็นโครงสร้างคร่าวๆ แทนวงกลมหมุนกลางจอ
- แยก loading state ของ header action (เช่น ปุ่มรีเฟรช) จาก loading state ของ body อย่างชัดเจน

---

## Phase 11 — ใช้ TlzAppTopBar ในหน้า “หาเพื่อนออกกำลังกาย” ✅ implement แล้ว (2026-08-25)

### ข้อตกลงที่ยืนยันแล้ว
- หน้า `sport_club_page.dart` ใช้ `TlzAppTopBar.onPrimary` เป็น header หลัก โดยคง gradient และมุมโค้งด้านล่างของ header เดิม
- ส่วนกลางของ Top Bar แสดงชื่อ “หาเพื่อนออกกำลังกาย” แบบ `FittedBox` และบังคับให้แสดงหนึ่งบรรทัด
- การค้นหายังคงใช้ปุ่มค้นหาและ `_showSearchDialog()` เดิม เพื่อไม่เปลี่ยนพฤติกรรมตัวกรองกีฬา/จังหวัด/อำเภอ/รัศมี
- แสดงปุ่มมาตรฐาน Notification และ Cart ของ `TlzAppTopBar`
- ปุ่มรีเฟรชและค้นหาเป็นปุ่มหลักที่แสดงโดยตรง ส่วน “ก๊วนของฉัน” และ Map/List อยู่ในเมนูเพิ่มเติมเพื่อให้ชื่อหน้าไม่ถูกย่อจนอ่านยากบนจอแคบ
- ใช้ `SafeArea` และปรับ padding ให้ header รองรับพื้นที่ status bar ตามมาตรฐานของ Top Bar

### สาเหตุ/วิธีป้องกัน
- การวางปุ่มเฉพาะหน้า 4 ปุ่มรวมกับ Notification และ Cart ในแถวเดียวทำให้พื้นที่ชื่อหน้าเหลือน้อยและข้อความถูกย่อมากเกินไป
- เมื่อนำ shared Top Bar มาใช้ ต้องตรวจสอบความกว้างรวมของ leading, middle และ actions ก่อนเพิ่มปุ่มใหม่
- ควรเก็บ action ที่ใช้บ่อยไว้ในแถวหลัก และรวม action ที่ใช้รองลงมาไว้ใน overflow menu โดยต้องไม่สูญเสียฟังก์ชันเดิม

### Search Dialog UX
- แตะพื้นที่นอก `TextField` ภายใน dialog แล้วต้องซ่อนแป้นพิมพ์ด้วย `TextField.onTapOutside` และ `FocusManager.instance.primaryFocus?.unfocus()`
- ช่อง “ค้นหา” ต้องแสดงปุ่มล้างค่าเมื่อมีข้อความ; กดแล้วล้าง `qController` และอัปเดต dialog ทันทีด้วย `setDialogState()`
- ชื่อ dialog “ค้นหาก๊วน” ต้องจัดกึ่งกลางตามแนวนอนด้วย `Center`
- ป้องกัน regression: การแตะช่องอื่นหรือ control อื่นใน dialog ต้องไม่ทำให้ dialog ปิด และการกดล้างค่าต้องไม่ล้างตัวกรองจังหวัด/อำเภอโดยไม่ตั้งใจ

---

## การทดสอบ Widget
- เพิ่ม `test/features/home/presentation/widgets/home_header_section_test.dart`
- ครอบคลุม:
  - แสดง fitness booking alert ขณะ `HomeHeaderSection` กำลังโหลด (`isLoading: true`)
  - ส่งค่า `bookingId`, `groupId`, `status` ของ alert ไปยัง `onFitnessBookingAlertTapped` เมื่อผู้ใช้แตะข้อความ เพื่อให้ `home_page.dart` แยกนำทาง pending review กับรายละเอียด booking ได้ถูกต้อง
- รัน: `flutter test test/features/home/presentation/widgets/home_header_section_test.dart`

---

## Phase 12 — Group Management Authorization ✅ implement แล้ว (2026-08-25)

### Policy ที่ยืนยันแล้ว
- การแก้ไข/จัดการก๊วนทุกประเภทอนุญาตเฉพาะ **ผู้จัดการก๊วน** เท่านั้น:
  - owner/controller ที่ตรงกับ `fitness_groups.created_by` แม้ `owner_auto_join=false` หรือ membership inactive
  - active group admin ที่ตรงกับ `fitness_group_members.user_id` และมี `role='admin'`
  - admin ของ Sheserved ที่ตรงกับ `users.role='admin'` ผ่าน current custom-auth user
- ผู้ใช้ที่เป็นสมาชิกทั่วไป, ผู้ขอ pending, ผู้ถูกบล็อก หรือผู้ใช้ที่ไม่เกี่ยวข้องกับก๊วน ห้ามแก้ไข/จัดการก๊วน
- การสร้างก๊วนยังอนุญาตผู้ใช้ที่ล็อกอินแล้ว เพราะเป็นการสร้าง resource ใหม่ ไม่ใช่การแก้ไข/จัดการก๊วนเดิม
- owner ยังไม่สามารถใช้ ordinary leave เพื่อถอนสิทธิ์ควบคุมก๊วน; ต้องใช้ owner participation toggle ตาม Phase 9

### ขอบเขตของ action ที่ใช้ policy นี้
- แก้ไขข้อมูลก๊วนและ owner participation
- เพิ่ม/แก้ไข/ยกเลิกรอบนัด
- อ่านและจัดการ pending bookings: อนุมัติ/ปฏิเสธ
- block/unblock สมาชิกและดู blocklist
- ถอดสมาชิกคนอื่นออกจากก๊วนผ่าน `leave_fitness_group`

### Implementation ที่ทำแล้ว
- เพิ่ม `_assertCurrentUser()` และ `_requireGroupManager()` ใน `fitness_buddies_repository.dart`
- `updateGroup()` ตรวจ owner/active group admin/Sheserved admin ก่อน update และไม่จำกัด update ด้วย `created_by` อย่างเดียวอีกต่อไป
- `createSession()` รับ `actorUserId` และ session `capacity` พร้อมตรวจสิทธิ์/validation ก่อน insert; `updateSession()`/`cancelSession()` หา group จาก session แล้วตรวจสิทธิ์ก่อน mutation
- `approveBooking()`/`rejectBooking()` ตรวจสิทธิ์จาก group ที่ผูกกับ booking ก่อนจัดการ และ approval ตรวจ session capacity ซ้ำที่ RPC
- `blockUser()`/`unblockUser()`/`listBlockedUsers()` และ `listGroupPendingBookings()` ใช้กฎ manager เดียวกัน; ยกเลิกการตรวจ capacity ระดับก๊วนตอน unblock
- UI ของ `sport_club_page.dart` แสดง action สำหรับ Sheserved admin ในทุกก๊วน และอนุญาต active group admin จัดการ blocklist ได้
- migration `20260825120000_fitness_buddies_management_authorization.sql` เพิ่ม `is_fitness_group_manager()` และปรับ RPC อนุมัติ/ถอดสมาชิกให้รองรับ Sheserved admin นอกเหนือจาก owner และ active group admin; ต้อง apply migration นี้ใน Supabase และ reload schema ก่อนทดสอบ

### Custom-auth security boundary
- เนื่องจากโปรเจกต์ยังใช้ `AuthService` และ Supabase Auth session เป็น `null`, Repository ต้องตรวจ `actorUserId == AuthService.instance.currentUser?.id` ก่อน mutation
- RLS ปัจจุบันของ fitness tables ยังเป็น permissive `USING(true)` เพื่อรองรับ custom-auth architecture ดังนั้นการตรวจใน Repository และ RPC ที่รับ actor ID เป็น enforcement ตามสถาปัตยกรรมปัจจุบัน ไม่ใช่ cryptographic identity boundary สำหรับ direct client ที่จงใจ spoof parameter
- เลือก trusted backend identity bridge แทน native Supabase Auth: Backend ต้อง verify JWT, สร้าง `req.userId`, ตั้ง `SET LOCAL app.user_id` ภายใน transaction และเรียก secure RPC overload ที่ไม่รับ `p_actor_id`; จากนั้นจึง tighten RLS และ revoke legacy RPC จาก client

### Regression checklist
- owner และ active group admin เพิ่ม/แก้ไข/ยกเลิกรอบนัดของก๊วนตนเองได้
- Sheserved admin เพิ่ม/แก้ไข/ยกเลิกรอบนัด, อนุมัติ/ปฏิเสธคำขอ และจัดการ blocklist ได้ทุกก๊วน
- สมาชิกทั่วไปเรียก repository mutation โดยตรงแล้วได้ `NOT_GROUP_ADMIN`
- ผู้ใช้ที่ไม่ใช่ current custom-auth user ได้ `UNAUTHORIZED` ก่อนเรียก Supabase
- กลุ่มที่ไม่มีรอบนัดยังปรากฏต่อ owner/group admin/Sheserved admin เพื่อให้เพิ่มรอบได้
- owner ที่ `owner_auto_join=false` ยังคงแก้ไข/จัดการก๊วนได้ผ่าน `created_by`

---

## Phase 13 — Trusted Backend Identity Bridge Rollout (อนุมัติแนวทางแล้ว; รอ implement)

### Architecture decision
- คง custom `AuthService`/`ServiceLocator` เป็น state container ฝั่ง Flutter และไม่ย้ายไป Supabase Auth
- Backend ออก signed access JWT อายุสั้น และ rotated opaque refresh token; refresh token เก็บเฉพาะ hash ใน persistent session registry
- Backend ตรวจ password และ social provider token ฝั่ง server; ห้าม query `password_hash` หรือเชื่อ social identity จาก Flutter โดยตรง
- Flutter เก็บ access token ใน memory และ refresh token ใน platform secure storage; ใช้ authenticated HTTP client กลางจัดการ Bearer header, refresh-once และ logout เมื่อ refresh ล้มเหลว
- HTTP/WebSocket ต้อง verify signature, issuer, audience, expiry และ session revoke state ก่อนสร้าง `req.userId`/`socket.userId`; ห้ามเชื่อ `x-user-id`, request body actor หรือ JWT ที่ decode โดยไม่ verify
- Public read ที่ไม่มีข้อมูลส่วนตัวอาจอ่าน Supabase ด้วย anon keyต่อได้ภายใต้ public SELECT policy; private read และ mutation ต้องผ่าน Backend
- Backend request path ใช้ DB role `sheserved_app` ที่ไม่มี `BYPASSRLS`; ห้ามใช้ Supabase `service_role` เป็น app request role
- ทุก DB request ที่อาศัย identity ต้องทำใน transaction เดียวและตั้ง `SET LOCAL app.user_id`, `app.session_id`, `app.role`, `app.organization_id`/`app.branch_id` ตาม claims ที่ verify แล้ว
- Strict RLS ใช้ `app.get_current_user_id()`/trusted transaction context; service-role จำกัดเฉพาะ migration, sync และ system job ที่กำหนดขอบเขต
- Access JWT มี fixed expiry และไม่ใช้ sliding TTL; Redis ใช้ denylist/session cache/refresh lock/rate limit ส่วน refresh registry ถาวรอยู่ใน PostgreSQL

### Compatibility contract ใน migration `20260825130000_fitness_buddies_session_capacity.sql`
- เพิ่ม `app.require_current_user_id()` เพื่ออ่าน `app.user_id` และยืนยันว่าเป็น active user
- เพิ่ม secure RPC overload ที่ไม่รับ actor จาก client:
  - `is_fitness_group_manager(p_group_id)`
  - `set_fitness_group_owner_auto_join(p_group_id, p_enabled, p_cancel_bookings)`
  - `book_fitness_session(p_session_id)`
  - `approve_fitness_session_booking(p_booking_id)`
  - `leave_fitness_group(p_group_id, p_user_id)`
- Secure overload เป็น bounded `SECURITY DEFINER` พร้อม `SET search_path=''`, รับเฉพาะ business/resource IDs และ derive actor จาก `app.require_current_user_id()`; ถูก `REVOKE ... FROM PUBLIC, anon, authenticated` และยังไม่ grant ให้ app role จนกว่า Phase 13.3 จะสร้าง/จำกัด role และโอน function owner เรียบร้อย
- Legacy RPC signature ที่รับ `p_actor_id`/`p_user_id` ยังคง grant ให้ `anon, authenticated` ใน migration นี้เพื่อไม่ทำให้ Flutter ปัจจุบันเสียระหว่าง compatibility window
- การคง legacy grant หมายความว่า actor spoofing ยังไม่ถูกปิดสมบูรณ์จนถึง Phase 13.5; ห้ามอ้างว่า migration preparation นี้เป็น security cutover
- การสร้าง DB role, strict RLS และ revoke legacy grants ต้องอยู่ใน migration cutover ใหม่ภายหลัง ไม่แก้ย้อนหลัง migration ที่ apply แล้ว

### Phase 13.0 — Documentation, secrets และ network prerequisites
- อัปเดต security decision ให้เลือก JWT + Backend Gateway และกำหนด owner ของ signing keys/session registry
- เพิ่ม backend env template สำหรับ JWT active/previous key, issuer, audience, access TTL, refresh TTL และ secure cookie/web settings โดยไม่ใส่ค่าจริงใน git
- ใช้ dual-key rotation พร้อม `kid`; signing key/DB credential/Redis credential เป็น P2 server-only และต้อง rotate ตาม `docs/secure/07_secret_management.md`
- Staging/production ต้องพร้อม HTTPS/WSS ผ่าน Caddy ก่อนเปิด token; auth endpoints ใช้ `Cache-Control: no-store`, CORS allowlist และ WebSocket origin allowlist
- กำหนด role-specific TTL ตาม `docs/secure/08_session_token_security.md`; admin/clinical สั้นกว่า consumer และ sensitive action ต้อง re-auth
- กำหนด LocalOnly/Unified behavior: Local Backend ออก/verify token ได้โดยไม่ใช้อินเทอร์เน็ต; เมื่อ identity authority ใช้งานไม่ได้ protected mutation ต้อง fail closed
- Gate: environment validation ผ่าน, ไม่มี secret ใน client/log, HTTPS/WSS test ผ่าน และ legacy behavior ยังทำงานเหมือนเดิม

### Phase 13.1 — Auth foundation แบบไม่เปลี่ยน Fitness path
- เพิ่ม `/api/auth/login`, `/api/auth/social/:provider`, `/api/auth/refresh`, `/api/auth/logout`, `/api/auth/logout-all`, `/api/auth/me` และ session-management endpoints
- ใช้ Argon2id ฝั่ง server (bcrypt cost 12 เป็น fallback) พร้อม legacy SHA-256 lazy rehash; ห้ามส่ง `password_hash` กลับ Flutter
- Social login ต้องส่ง provider credential ให้ Backend verify กับ provider ก่อน map `public.users` และออก Sheserved session
- Refresh token ต้อง random อย่างน้อย 256-bit, เก็บ hash, rotate ทุกครั้ง, ตรวจ reuse และ revoke session family เมื่อพบ reuse
- เพิ่ม account lockout/rate limit ต่อ identifier และ audit event: login success/failure, refresh, reuse, logout, revoke, role change
- ขยาย `AuthService` ให้ถือ user + access token metadata โดยคง API `currentUser` เดิมเพื่อลดผลกระทบหน้าอื่น
- เพิ่ม authenticated HTTP client กลาง; mobile เก็บ refresh ใน Keychain/EncryptedSharedPreferences, web ใช้ HttpOnly+Secure+SameSite=Strict และป้องกัน CSRF เฉพาะ refresh endpoint
- Gate: login/register/social/refresh/logout/session restore ผ่าน test; legacy Fitness repository ยังไม่เปลี่ยน path

### Phase 13.2 — HTTP/WebSocket verified identity
- แทนที่ middleware ที่รับ `x-user-id`/unsigned JWT ด้วย signature verification แบบ fail closed
- Protected route ใช้ `req.userId`, `req.sessionId`, role/permission จาก verified claims และตรวจ active/revoked session ซ้ำตาม policy
- Socket.IO รับเฉพาะ signed access token, verify เหมือน HTTP และ re-auth/reconnect เมื่อ token refresh; event-level actor ต้องตรง `socket.userId`
- Public endpoint/anonymous socket แยก route และ event allowlist ชัดเจน ห้าม fallback จาก protected path ไป anonymous
- Cache key ของ private response ต้องรวม user/org/permission context; ห้าม cache `/api/auth/*` response และห้าม log token/password/OTP
- Gate: token ปลอม, หมดอายุ, issuer/audience ผิด, revoked session และ socket actor mismatch ถูกปฏิเสธ; client รุ่น compatibility ยังใช้งานส่วนที่ยังไม่ cutover ได้

### Phase 13.3 — DB identity context, roles และ RLS foundation
- สร้าง role แยกใน migration ใหม่: `sheserved_app`, `sheserved_worker`, `sheserved_readonly`, `sheserved_migrate` และ `sheserved_fitness_owner NOLOGIN`; ยกเลิก `GRANT ALL` สำหรับ app request role
- `sheserved_app` มีเฉพาะสิทธิ์ตาราง/RPC ของ Fitness ที่จำเป็น, ไม่มี DDL, ไม่มี `BYPASSRLS`, แก้/ลบ audit log ไม่ได้
- ก่อน cutover ให้โอน ownership ของ bounded secure RPC จาก migration role ไป `sheserved_fitness_owner` ที่มีสิทธิ์เฉพาะตาราง Fitness; `sheserved_app` ได้เพียง `EXECUTE` และเรียก legacy actor signature โดยตรงไม่ได้
- Backend checkout connection แล้วต้อง `BEGIN` → `SET LOCAL app.user_id/session_id/role/...` → query/RPC → `COMMIT`/`ROLLBACK` ก่อนคืน connection ทุกครั้ง เพื่อป้องกัน identity รั่วข้าม pooled connection
- Grant secure RPC overload จาก migration preparation ให้ `sheserved_app`; Backend ห้ามเรียก legacy signature ที่รับ actor
- เพิ่ม strict Fitness RLS ใน shadow/validation mode หรือ migration staging โดยใช้ trusted context; public SELECT policy แยกจาก private/member/admin policy
- Service-role ใช้เฉพาะ migration/sync/system jobs และต้องมี credential/connection pool แยกจาก HTTP request handler
- Gate: deny/allow matrix ผ่านสำหรับ owner, active group admin, Sheserved admin, member, unrelated user, blocked user, missing context และ invalid context

### Phase 13.4 — Fitness Backend Gateway canary
- เพิ่ม Backend endpoints สำหรับ create/update group, create/update/cancel session, book/cancel/approve/reject booking, owner auto-join, leave/remove member, block/unblock และ sensitive reads
- Flutter ส่งเฉพาะ resource/business fields; ห้ามส่ง actor ID เพื่อใช้ authorization โดย Backend derive actor จาก `req.userId`
- Backend ใช้ policy/data-access boundary กลางและ ownership-scoped query/RPC; session capacity/approval ยังเป็น atomic ที่ DB
- Public group/session list สามารถอ่าน Supabase โดยตรงต่อได้; pending/member profile/blocklist และ mutation ผ่าน Gateway
- ใช้ environment/user cohort feature flag เลือก **หนึ่ง write path ต่อ request**; ห้าม dual-write เพราะเสี่ยงจองซ้ำและ state divergence
- Shadow mode ทำได้เฉพาะเปรียบเทียบ authorization decision/read result โดยไม่ทำ mutation ซ้ำ
- Offline/emergency mode เก็บ encrypted outbox ได้ แต่ห้ามถือว่า server-authorized จนกว่าจะออนไลน์และ Backend ตรวจ token/ownership ใหม่
- Gate: canary ไม่มี booking ซ้ำ, capacity drift, notification drift หรือ permission regression; audit log ผูก actor/session/request ID ครบ

### Phase 13.5 — Fitness security cutover
- เปลี่ยน Fitness Repository ทุก mutation/private read ให้ใช้ authenticated Backend path และยืนยันว่าไม่มี direct Supabase write เหลือ
- Apply migration cutover ใหม่เพื่อ:
  - `REVOKE EXECUTE` legacy Fitness RPC จาก `PUBLIC, anon, authenticated`
  - revoke permissive INSERT/UPDATE/DELETE policies ของ Fitness tables
  - enable/force strict RLS และ grant เฉพาะ scoped DB roles/secure RPCs
  - คง public SELECT เท่าที่จำเป็น
- ปิด `x-user-id`, request actor และ direct-Supabase mutation fallback ใน production โดยเด็ดขาด
- Rollback ต้องเป็นการ rollback Backend/App version พร้อม matching DB migration ที่ผ่านการอนุมัติ; ห้ามมี runtime switch กลับไปเปิด anon mutation
- Gate: direct REST/RPC ด้วย anon keyถูกปฏิเสธ, spoof UUID ไม่เปลี่ยนข้อมูล, Backend verified owner/admin ยังทำงานครบ และ public browse ไม่เสีย

### Phase 13.6 — Module waves และ legacy cleanup
- ย้าย protected module อื่นตาม risk: health/consultation/chat → donation/escrow → users/roles → ERP → module ที่เหลือ
- แต่ละ module tighten RLS/DB grants หลัง Backend cutover ของ module นั้นเท่านั้น ไม่เปิด strict RLS ทั้งแอปแบบ big-bang
- เมื่อ client compatibility window สิ้นสุด ให้ลบ legacy Fitness function overload ที่รับ actor หรือคงไว้แบบ revoked สำหรับ forensic compatibility
- ลบ client-side password verification, `passwordHash` ใน `UserModel`, unsigned token decode และ `x-user-id`
- อัปเดต `.agent/workflows/auth_data_guidelines.md`, `docs/secure/*` และ `docs/infrastructure/*` ให้สะท้อน verified Backend identity, DB roles, RLS context, token/cache/TLS/rollback policy
- ทำ quarterly access review, key rotation drill, refresh-token reuse drill และ incident rollback drill

### Fitness secure endpoint/RPC mapping
| Action | Backend input จาก client | Verified actor | Secure DB path |
|---|---|---|---|
| Book session | `sessionId` | `req.userId` | `book_fitness_session(p_session_id)` |
| Approve booking | `bookingId` | `req.userId` | `approve_fitness_session_booking(p_booking_id)` |
| Owner auto-join | `groupId, enabled, cancelBookings` | `req.userId` | `set_fitness_group_owner_auto_join(p_group_id, p_enabled, p_cancel_bookings)` |
| Leave/remove member | `groupId, targetUserId` | `req.userId` | `leave_fitness_group(p_group_id, p_user_id)` — ยกเลิกทั้งก๊วน |
| Remove session participant | `bookingId` | `req.userId` | `remove_fitness_session_participant(p_booking_id)` — ยกเลิกเฉพาะรอบ |
| Manager check | `groupId` | transaction context | `is_fitness_group_manager(p_group_id)` |
| Create/update/cancel group/session | allowlisted business fields | `req.userId` | scoped transaction + strict RLS/manager policy |
| Cancel/reject booking | `bookingId, reason?` | `req.userId` | ownership/manager-scoped transaction |
| Block/unblock user | `groupId, targetUserId, reason?` | `req.userId` | manager-scoped transaction + strict RLS |

### Required regression/security tests ก่อน Phase 13.5
- forged/unsigned/expired/wrong-audience JWT → 401
- revoked session/refresh reuse/inactive user → 401 และ audit event
- member ส่ง owner/admin UUID ใน body/header → ไม่มีผล; Backend ใช้ verified actor เท่านั้น
- missing `SET LOCAL app.user_id` หรือ invalid/inactive ID → secure RPC คืน `UNAUTHORIZED`
- pooled connection request A/B สลับกันแล้ว identity ไม่รั่ว
- owner/active group admin/Sheserved admin ผ่านเฉพาะ scope ที่กำหนด; member/unrelated/blocked ถูกปฏิเสธ
- pending ไม่กิน session capacity; concurrent approval/book ไม่เกิน capacity
- owner auto-join capacity/overlap ยัง all-or-nothing
- anon direct mutation/RPC หลัง cutover → permission denied
- public group/session browse ยังทำงานโดยไม่ login
- WebSocket token refresh/reconnect และ actor mismatch ทำงานถูกต้อง
- logs/audit ไม่เก็บ password, access token, refresh token, OTP หรือ signing key
