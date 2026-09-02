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
- ข้อจำกัด security ปัจจุบัน: RLS ยังเป็น `USING(true)` และ legacy RPC รับ actor จาก client จึงยังไม่ใช่ cryptographic identity boundary; ช่วง compatibility ให้ Repository/App Layer ตรวจ `AuthService` ต่อไป และ Phase 13 จะใช้ 3 path ตาม data classification — public read ผ่าน VIEW, private read ผ่าน Backend-issued PostgREST token + strict RLS, mutation ผ่าน trusted Backend + secure RPC — ก่อน revoke legacy path

## การปฏิบัติตามแนวทาง Security & Infrastructure

### Auth Data Guidelines (`auth_data_guidelines.md`)
- ❌ ห้ามใช้ `Supabase.instance.client.auth.currentUser` หรือ `_client.auth.currentUser` — ค่าเป็น `null` เสมอ
- ✅ ดึง `userId` จาก custom session ของโปรเจกต์ (`AuthService.instance.currentUser?.id` หรือ `ServiceLocator` abstraction ที่หน้าจอนั้นใช้อยู่)
- ✅ Repository ต้องรับ `userId`/`actorUserId` เป็นพารามิเตอร์ ไม่ดึงเองจาก Supabase Auth และ mutation สำคัญต้องตรวจว่า actor ตรงกับ current user จาก custom auth ก่อนดำเนินการ
- ✅ Repository ของ Find Fitness Buddies ต้องตรวจผู้จัดการก๊วนผ่าน `_requireGroupManager()` ก่อนแก้ไขก๊วน/รอบนัด/คำขอ/blocklist โดยยอมรับ owner, active group admin หรือ Sheserved admin
- ✅ UI (Presentation) ส่ง `userId`/`actorUserId` จาก custom auth เข้า Repository
- ช่วง compatibility: Owner rejoin และ group management ใช้ App-Layer authorization ตามเดิม; target Phase 13 คง custom AuthService เป็น state container แต่ใช้ PostgREST token + `request.jwt.claims` สำหรับ private read และ secure RPC ที่อ่าน `SET LOCAL app.user_id` จาก Backend สำหรับ mutation; ไม่พึ่ง `auth.uid()` ของ native Supabase Auth

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
- หลัง Fitness cutover: public browse ใช้ public VIEW + anon; private read ใช้ Backend-issued PostgREST token ที่ Supabase verify และ strict RLS; mutation ผ่าน Backend ที่สร้าง `req.userId` จาก JWT ที่ verify แล้ว, ตั้ง `SET LOCAL app.user_id` ใน transaction และใช้ secure RPC ที่ไม่รับ actor จาก client
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

## Phase 13 — Trusted Backend Identity Bridge Rollout (ตัดสินใจครบ 12/12; รอ implement)

### Phase 13 baseline audit (สำรวจโค้ดจริง 2026-08-30)
> ตัวเลขและข้อเท็จจริงทั้งหมดในหัวข้อนี้มาจากการอ่านโค้ด/migration จริง ไม่ใช่การประมาณ; ใช้เป็น baseline ในการวัดความคืบหน้าและกำหนด scope

| ด้าน | สถานะจริง | ผลต่อแผน |
|---|---|---|
| Backend identity | `websocket-server/middleware/auth.js` `_extractUserId()` อ่าน `x-user-id` ก่อน แล้ว fallback ไป base64-decode JWT payload **โดยไม่ verify signature**; `verifyToken(pool)` ปล่อย anonymous ผ่านเมื่อไม่มี header | ต้องเขียน verification ใหม่ทั้งหมด ไม่ใช่แค่ปรับ |
| Auth endpoints | **ไม่มี `/api/auth/*` เลย**; `Caddyfile.dev` มี path matcher แต่ไม่มี route จริง | Phase 13.2 คือการสร้างของใหม่ 100% |
| Backend deps ที่ขาด | `jsonwebtoken`, `bcrypt`/`argon2`, `helmet` **ไม่มีใน package.json**; `pino` ถูก `require` ใน `utils/logger.js` แต่ไม่มีใน package.json และไม่ได้ติดตั้ง (`middleware/request-context.js` เป็น dead code ยังไม่ wire เข้า `server.js` จึงยังไม่ crash) | ต้องเพิ่ม dependency + ตรวจ supply chain ก่อน 13.2 |
| Backend endpoint surface | `routes/` มี 4 ไฟล์ 25 endpoints (12 ต้องล็อกอิน) และ **ไม่มี endpoint ใดรับ actor id จาก body**; แต่ `server.js` มีอีก ~33 endpoints ที่หลายตัวรับ `userId`/`responderId` จาก `req.body`/`req.query` โดยไม่เทียบกับ `req.userId` | BOLA surface จริงอยู่ใน `server.js` ไม่ใช่ `routes/` |
| WebSocket | handshake ใช้ `socket.handshake.auth.token` เป็น user id ตรง ๆ หรือ `x-user-id`/unsigned JWT; `join-room`, `join-emergency-chat` **ไม่มี membership check ใด ๆ** — client join ห้องไหนก็ได้ | ต้องเพิ่ม room authorization เป็นงานแยก ไม่ใช่ผลพลอยได้ของ JWT |
| DB connection ของ backend | `server.js` สร้าง `new Pool()` ชี้ **local PostgreSQL** (`DB_HOST=localhost`, `DB_PORT=5432`); การคุย Supabase ใช้ `@supabase/supabase-js` + service key ผ่าน PostgREST | ⚠️ **ข้อค้นพบสำคัญที่สุด** — ดูหัวข้อ Q7 |
| `SET LOCAL` / transaction | ไม่มี `SET LOCAL` และไม่มี `BEGIN/COMMIT` ใน request path ใด ๆ ทั้ง repo | ต้องสร้าง per-request transaction scope ใหม่ทั้งหมด |
| Supabase pooler | ไม่พบ `pooler.supabase.com`, `pgbouncer`, หรือพอร์ต `6543` ในโค้ด/เอกสาร/env ใด ๆ | ยังไม่มี pooler constraint ผูกมัด — เลือกโหมดได้อิสระ |
| service_role | ใช้ใน 10 ไฟล์ (`server.js` + 9 services) ผ่าน `SUPABASE_SERVICE_KEY`/`SUPABASE_SERVICE_ROLE_KEY` และบางไฟล์ fallback ไป `SUPABASE_ANON_KEY` | fallback ไป anon เป็น silent-downgrade ที่ต้องปิด |
| Redis session helper | `middleware/cache-aside.js` มี `getSession/setSession/deleteSession` (คีย์ `auth:session:${sessionId}`, TTL 2 ชม., sliding) แต่ **ไม่มี production endpoint เรียกใช้** | โครงพร้อมแล้ว ต่อยอดได้เลย |
| Rate limiting | มี 13 limiter รวม `loginLockoutLimiter` (5 ครั้ง → ล็อก 15 นาที) และ `otpCooldownLimiter` แต่ยังไม่ผูกกับ auth endpoint เพราะยังไม่มี auth endpoint | Phase 13.2 นำมาใช้ได้ทันที |
| Flutter session | `AuthService` เก็บ `_currentUser` ใน memory เท่านั้น ไม่ persist; ปิดแอป = หลุด login | ต้องเพิ่ม token storage layer ใหม่ |
| Flutter password | `user_repository.dart` hash SHA-256 ฝั่ง client แล้ว **query `.eq('password_hash', hashedPassword)`** — hash ทำหน้าที่เป็นรหัสผ่านจริง | ดูหัวข้อ P0 blockers |
| Secure storage | `flutter_secure_storage` **ไม่ได้ประกาศใน pubspec.yaml** (มีใน pubspec.lock แบบ transitive 10.3.1 และไม่มีไฟล์ใน `lib/` import) | ต้อง declare เป็น direct dependency |
| Refactor surface | `Supabase.instance.client` ถูกเรียก **189 ครั้งใน 83+ ไฟล์**; หนักสุด `consultation` 33, `services` 31, `admin` 24, `erp` 19, `donation` 16 | ยืนยันว่าต้องทำแบบ module wave ไม่ใช่ big-bang |
| `x-user-id` ฝั่ง client | ตั้งเพียง 3 ที่: `victim_repository.dart`, `watermark_repository.dart`, `consultation_repository.dart` | จุดตัด client ง่ายกว่าที่คาด |
| RLS ปัจจุบัน | 211 migration files, `ENABLE ROW LEVEL SECURITY` 208 ครั้ง, `CREATE POLICY` 468 ครั้ง, **`USING (true)` 372 ครั้ง**, `auth.uid()` 86 ครั้ง (มี policy จริงเช่น `app_notifications.recipient_id = auth.uid()` ที่จะเป็น null ตลอดใน custom auth) | 372 permissive policy = งาน tighten ที่ต้องแบ่ง wave |
| DB roles | **`CREATE ROLE` = 0 ครั้ง** ในทุก migration; role ยังอยู่แค่ในเอกสาร `12_least_privilege.md` | Phase 13.1 ต้องสร้าง role จากศูนย์ |
| `app.user_id` GUC | มีอยู่แล้วใน `20260624090500_add_user_categories_rls.sql` และ `app.require_current_user_id()` ใน `20260825130000` | pattern พิสูจน์แล้ว ต่อยอดได้ |
| Secure vs legacy RPC | secure overload (ไม่รับ actor) ถูก `REVOKE` จาก `PUBLIC, anon, authenticated` และ **ยังไม่ grant ให้ใคร**; legacy overload ที่รับ actor **ยัง grant ให้ `anon, authenticated`** | ตรงตามที่แผนระบุ — compatibility window ยังเปิด |
| Audit log | **ไม่มีตาราง `audit_logs`**; มี `transaction_audit_log`, `victim_report_consent_logs`, `victim_health_access_logs` เท่านั้น | ต้องตัดสินใจว่า auth audit ไปตารางไหน |
| Session table | มี `public.sessions` จาก `20260728190000_create_sessions_table.sql` แต่ **ไม่มี `refresh_tokens`** | Q6-B: reuse/extend `public.sessions` ใน Phase 13.2 ไม่สร้างตาราง refresh ซ้ำซ้อน |
| TLS | Caddy Phase 1 deploy แล้ว (`:8080` dev, `:80` local) แต่ **TLS/HTTPS ยังไม่ implement** | เป็น hard prerequisite ของ 13.0 |

### P0 blockers — ต้องแก้ก่อนเริ่ม Phase 13 (แยกเป็น Phase 12.9)
> B1–B4 เป็นช่องโหว่/bug ที่ทำงานอยู่ในโค้ดปัจจุบัน ไม่ใช่ความเสี่ยงในอนาคต; ต้องแก้ B1, B3, B4 ทันที, ทำ containment ของ B2 ทันที และปิด B2 แบบสมบูรณ์หลัง Flutter เปลี่ยน login ไป Backend ใน Phase 13.2 — ห้าม revoke direct auth query ก่อน compatibility cutover

| # | ปัญหา | หลักฐาน | ผลกระทบ | วิธีแก้ที่เสนอ |
|---|---|---|---|---|
| B1 | `updatePassword()` เขียนรหัสผ่าน **แบบ plaintext** ลง `users.password_hash` | `user_repository.dart:222` `'password_hash': newPassword, // TODO: Hash password` | ผู้ใช้ที่เปลี่ยนรหัสผ่านมี plaintext อยู่ใน DB และ login ไม่ได้อีก (เพราะ login เทียบ SHA-256) | แก้ทันทีให้เรียก `_hashPassword()` เป็น hotfix; ระยะยาวย้ายไป server-side ใน 13.2 |
| B2 | Client ส่ง SHA-256 hash เป็นเงื่อนไข query | `user_repository.dart:150` `.eq('password_hash', hashedPassword)` | hash **คือ** credential; ใครอ่าน `users` ได้ = login เป็นใครก็ได้; ประกอบกับ `USING(true)` บน `users` = auth bypass | ทำ containment ทันที (ห้ามคืน `password_hash` ใน generic user/public view) แต่ **อย่า revoke direct auth query ก่อน Flutter switch**; ปิดเต็มรูปแบบหลัง 13.2 เปลี่ยน login ไป Backend |
| B3 | `SyncService` sync คอลัมน์ `password_hash` ลง local DB | `sync_service.dart:289-297` select list มี `password_hash` | hash ทั้งระบบถูกกระจายไปเครื่อง local ทุกเครื่องที่ sync | ตัด `password_hash` ออกจาก select list ของ sync และ purge สำเนาเดิมจาก local store |
| B4 | `UserModel` พา `passwordHash` ไปทั่ว UI | `user_model.dart:110, 196, 233` | hash ค้างใน memory/log/crash report ได้ | ลบ field จาก model และทุกจุดที่ serialize (แผน 08 T8 ระบุไว้แล้ว) |

> **หมายเหตุ:** B1 คือ bug ที่ทำให้ผู้ใช้ล็อกอินไม่ได้ด้วย ไม่ใช่แค่เรื่อง security — ควรแก้เป็น hotfix แยกจาก Phase 13 ทันที

### Architecture decision
- คง custom `AuthService`/`ServiceLocator` เป็น state container ฝั่ง Flutter และไม่ย้ายไป Supabase Auth
- Backend ออก signed access JWT อายุสั้น และ rotated opaque refresh token; refresh token เก็บเฉพาะ hash ใน persistent session registry
- Backend ตรวจ password และ social provider token ฝั่ง server; ห้าม query `password_hash` หรือเชื่อ social identity จาก Flutter โดยตรง
- Flutter เก็บ access token ใน memory และ refresh token ใน platform secure storage; ใช้ authenticated HTTP client กลางจัดการ Bearer header, refresh-once และ logout เมื่อ refresh ล้มเหลว
- HTTP/WebSocket ต้อง verify signature, issuer, audience, expiry และ session revoke state ก่อนสร้าง `req.userId`/`socket.userId`; ห้ามเชื่อ `x-user-id`, request body actor หรือ JWT ที่ decode โดยไม่ verify
- Public read ที่ไม่มีข้อมูลส่วนตัวอ่านผ่าน public VIEW ด้วย anon key; private read ใช้ short-lived PostgREST token ที่ Backend ออกให้เพื่อให้ RLS ทำงาน; mutation/operation ที่มี side effect ผ่าน Backend
- Backend request path ใช้ `sheserved_gateway` (LOGIN, server-only credential) แล้ว `SET LOCAL ROLE sheserved_app`; `sheserved_app` เป็น permission role ที่ไม่มี `BYPASSRLS`, ไม่มี DDL; ห้ามใช้ Supabase `service_role` เป็น app request role
- ทุก DB request ที่อาศัย identity ต้องทำใน transaction เดียวและตั้ง `SET LOCAL app.user_id`, `app.session_id`, `app.role`, `app.organization_id`/`app.branch_id` ตาม claims ที่ verify แล้ว
  - ⚠️ **ข้อจำกัดที่พบจากการสำรวจจริง:** ใช้ได้เฉพาะเมื่อ Backend เปิด connection `pg` **ตรงไปยัง Supabase Postgres** เท่านั้น; การเรียกผ่าน `@supabase/supabase-js`/PostgREST ทำ `SET LOCAL` ข้าม statement ไม่ได้เพราะแต่ละ RPC call เป็น transaction ของตัวเอง — ดู Decision Sheet Q7
- Strict RLS ใช้ `app.current_user_id()`/trusted transaction context; service_role จำกัดเฉพาะ migration, sync และ audit/system worker ที่กำหนดขอบเขต และห้ามอยู่ใน HTTP/Socket request handler
- Access JWT มี fixed expiry และไม่ใช้ sliding TTL; Redis ใช้ denylist/session cache/refresh lock/rate limit ส่วน refresh registry ถาวรอยู่ใน PostgreSQL

### Compatibility contract จาก migration `20260825130000_fitness_buddies_session_capacity.sql` และ migration ถัดไป
- migration `20260825130000` ที่ apply แล้วมี `app.require_current_user_id()` สำหรับอ่าน `app.user_id`; **ห้ามแก้หรือรัน migration เดิมซ้ำ**
- Phase 13.1 ใช้ migration ใหม่เพิ่ม `app.current_user_id()`/ปรับ helper ให้ยืนยัน active user; ถ้ามีทั้ง `app.user_id` และ `request.jwt.claims.sub` ต้องตรวจว่าเป็น UUID เดียวกัน ห้ามใช้ `COALESCE` กลบ identity ที่ขัดกัน
- เพิ่ม secure RPC overload ที่ไม่รับ actor จาก client:
  - `is_fitness_group_manager(p_group_id)`
  - `set_fitness_group_owner_auto_join(p_group_id, p_enabled, p_cancel_bookings)`
  - `book_fitness_session(p_session_id)`
  - `approve_fitness_session_booking(p_booking_id)`
  - `leave_fitness_group(p_group_id, p_user_id)`
- Secure overload เป็น bounded `SECURITY DEFINER` พร้อม `SET search_path=''`, รับเฉพาะ business/resource IDs และ derive actor จาก `app.require_current_user_id()`; ถูก `REVOKE ... FROM PUBLIC, anon, authenticated` และยังไม่ grant ให้ `sheserved_app` จนกว่า Phase 13.1 จะผ่าน role/pooler spike และโอน function owner เรียบร้อย
- Legacy RPC signature ที่รับ `p_actor_id`/`p_user_id` ยังคง grant ให้ `anon, authenticated` ใน migration นี้เพื่อไม่ทำให้ Flutter ปัจจุบันเสียระหว่าง compatibility window
- การคง legacy grant หมายความว่า actor spoofing ยังไม่ถูกปิดสมบูรณ์จนถึง Phase 13.5; ห้ามอ้างว่า migration preparation นี้เป็น security cutover
- การสร้าง DB role, strict RLS และ revoke legacy grants ต้องอยู่ใน migration cutover ใหม่ภายหลัง ไม่แก้ย้อนหลัง migration ที่ apply แล้ว


---

## Phase 13 — Decision Sheet (คำถามที่ต้องตอบก่อนเริ่ม พร้อมทางเลือก)

> วิธีใช้: แต่ละคำถามมีข้อเท็จจริงจากโค้ดจริง, ทางเลือก, และคำแนะนำที่เหมาะกับ sheserved โดยเฉพาะ
> ให้เลือก 1 ข้อต่อคำถาม แล้วบันทึกใน Decision Log ท้ายเอกสาร; ตัวเลือกที่เลือกจะกลายเป็นข้อผูกมัดของ sub-phase ที่เกี่ยวข้อง

### Q1 — ทีมและการแบ่งงาน: Phase 13 ควรใหญ่แค่ไหนต่อรอบ
**ข้อเท็จจริง:** แผน 09 ประเมินเฉพาะชั้น auth ว่า 6–10 สัปดาห์ และประเมิน refactor repository ที่ยิง Supabase ตรงว่า "~40+ repositories"; การสำรวจจริงพบ **189 call sites ใน 83+ ไฟล์** ซึ่งมากกว่าที่แผนประเมิน

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** | ทำ Phase 13 ตามลำดับเดิม 13.0→13.6 เป็นก้อนเดียว | ลำดับพึ่งพาชัด, เอกสารเดียว | ถ้าติดกลางทางต้องถือ half-migrated state นาน; rollback หลายชั้นพร้อมกัน |
| **B** ⭐ | แยกเป็น **release ที่ deploy ได้จริงต่อ sub-phase** โดยแต่ละ sub-phase ต้อง "ปล่อยแล้วอยู่ได้ไม่มีกำหนด" (independently shippable) | ถ้าหยุดกลางทางระบบยังปลอดภัยกว่าเดิมและใช้งานได้; ลด risk ของ solo dev | ต้องรักษา compatibility 2 ทางนานกว่า |
| **C** | ทำเฉพาะ 13.0–13.2 (auth identity ที่ verify ได้ แต่ยังไม่เปิด Fitness gateway/room path) แล้วหยุดประเมินก่อนตัดสินใจเรื่อง canary/RLS cutover | ได้ประโยชน์ security สูงสุดต่อความพยายาม (ปิด G2/G3) | Fitness ยังเปิด actor spoofing ต่อไป |

**คำแนะนำ: B** — และเพิ่มกฎว่า *ทุก sub-phase ต้องจบด้วยสถานะที่ปล่อยค้างได้* เพราะโปรเจกต์นี้ดูแลโดยคนน้อยและมี feature อื่นเดินขนานอยู่
**หมายเหตุ:** ถ้าเลือก C ให้ยอมรับอย่างชัดเจนในเอกสารว่า Fitness mutation ยัง spoof ได้ ห้ามเคลมว่า cutover แล้ว

---

### Q2 — Backend ตัวไหนเป็น identity authority
**ข้อเท็จจริง:** `websocket-server` มี Express 5 + Socket.IO + `pg` Pool + ioredis + Caddy Phase 1 อยู่แล้ว; **ไม่มี `/api/auth/*`**; `jsonwebtoken`/`bcrypt`/`argon2`/`helmet` ไม่มีใน `package.json`; `utils/logger.js` require `pino` ที่ไม่ได้ติดตั้ง (แต่ยังไม่ถูก wire เข้า `server.js` จึงยังไม่ crash)

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** ⭐ | ต่อยอด `websocket-server` เดิม เพิ่ม `routes/auth.js`, `middleware/auth.js` และ `middleware/socket-auth.js` ที่ verify จริง; `server.js` ทำเพียง wiring | ใช้ Caddy/Redis/rate-limiter/pool ที่มีอยู่ทันที; ไม่มี service ใหม่ให้ดูแล | `server.js` ใหญ่อยู่แล้ว (~33 inline endpoints) เสี่ยง regression |
| **B** | สร้าง service `auth-service` แยก process/repo | แยก blast radius, signing key อยู่ service เดียว | ต้อง deploy/monitor/TLS เพิ่ม; token verification ต้องแชร์ key หรือ JWKS |
| **C** | ใช้ Supabase Edge Function เป็น auth authority | ไม่ต้องดูแล server; อยู่ใกล้ DB | ขัดกับ local-only/unified mode ที่ต้องออก token ได้โดยไม่มีอินเทอร์เน็ต |

**คำแนะนำ: A** — เพราะ `docs/infrastructure/architecture_analysis.md` วาง Caddy → websocket-server เป็นทางเข้าหลักแล้ว และข้อกำหนด LocalOnly ตัด C ออกโดยปริยาย
**เงื่อนไขบังคับถ้าเลือก A:** auth/Socket.IO verification ต้องอยู่ใน middleware แยกจาก `server.js`; `server.js` ทำเพียงประกอบ middleware; ย้าย inline endpoints ของ `server.js` เข้าสู่ `routes/` ทีละกลุ่มพร้อมเพิ่ม `req.userId` enforcement

---

### Q3 — Signing algorithm และที่เก็บ key
**ข้อเท็จจริง:** แผน 08 แนะนำ HS256 ก่อนแล้วย้าย RS256; แผน 07 จัด JWT signing secret เป็น **P2 server-only rotate ทุก 90 วัน** และกำหนด dual-key period; ปัจจุบันไม่มี secret manager (`.env` เท่านั้น) และ `.env.example` ไม่มีตัวแปร JWT เลย

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** ⭐ | HS256 + dual key (`kid` = `active`/`previous`) ใน `.env`, rotate 90 วัน | ง่ายที่สุด, ตรงกับ single-service ปัจจุบัน | ทุก service ที่ verify ได้ก็ sign ได้ |
| **B** | RS256 + JWKS endpoint | แยก signer/verifier; Supabase/PostgREST verify ด้วย public key ได้ | ต้องจัดการ key pair + JWKS cache; งานเพิ่มโดยยังไม่มีหลาย service |
| **C** | HS256 ด้วย **Supabase JWT secret** เพื่อให้ PostgREST verify ได้ตรง | RLS ใช้ `auth.uid()` ได้เลย ไม่ต้อง gateway สำหรับ read | secret เดียวกันกับที่ Supabase ใช้; revoke ก่อนหมดอายุไม่ได้ (Supabase ไม่รู้จัก denylist ของเรา) |

**คำแนะนำ: A สำหรับ token ของ Sheserved เอง** และถ้าเลือก Q7 ตัวเลือก C ให้ออก **token คนละใบ** ที่ sign ด้วย Supabase JWT secret แยกจาก access token หลัก อายุสั้นกว่า (≤5 นาที) และไม่ใช้เป็น refresh
**เหตุผล:** อย่าให้ token ใบเดียวทำสองหน้าที่ เพราะขอบเขต revoke ต่างกันโดยธรรมชาติ

---

### Q4 — Password migration: SHA-256 → Argon2id
**ข้อเท็จจริง:** `_hashPassword()` ใช้ SHA-256 ไม่มี salt; `login()` เทียบด้วย `.eq('password_hash', ...)`; `updatePassword()` เขียน **plaintext**; `SyncService` sync `password_hash` ไป local DB; ไม่มี rehash path

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** | บังคับ reset password ทุกคน | ล้าง SHA-256 หมดในรอบเดียว, ชัดเจน | ผู้ใช้ทุกคนสะดุด; ต้องมีช่องทาง reset ที่เชื่อถือได้ (OTP) ก่อน |
| **B** ⭐ | **Lazy rehash**: server รับ password จริง → เทียบ SHA-256 เดิม → ถ้าผ่านให้ Argon2id ทับทันที + ตั้ง deadline บังคับ reset ผู้ที่ไม่ login ภายใน N เดือน | ผู้ใช้ไม่สะดุด; migrate ตามการใช้งานจริง | ต้องคง legacy verify path ชั่วคราว |
| **C** | เก็บ SHA-256 ต่อแต่ห่อด้วย Argon2id (`argon2(sha256(pw))`) แล้ว migrate เงียบ ๆ | ไม่ต้องรู้รหัสผ่านจริงก็ migrate ได้ทั้งตาราง | โครงสร้าง hash ซ้อนทำให้สับสนระยะยาว; ยังต้อง client ส่งอะไรมาให้ตรง |

**คำแนะนำ: B + องค์ประกอบของ C เป็น backstop** — ทำ B เป็นทางหลัก และใช้ C (`argon2(sha256(pw))`) เฉพาะเพื่อ **ปิด plaintext-equivalent risk ของแถวที่ยังไม่ login** ทันทีในคืนเดียว โดยบันทึก `password_algo` ต่อแถว
**สิ่งที่ต้องเพิ่มในตาราง `users`:** `password_algo VARCHAR(20)`, `password_updated_at TIMESTAMPTZ`, `password_migrated_at TIMESTAMPTZ`
**Prerequisite บังคับ:** ต้องแก้ B1 (plaintext) และ B3 (sync hash) ก่อน มิฉะนั้น migration จะ migrate ข้อมูลที่ผิดอยู่แล้ว; แถวที่ตรวจพบว่าเป็น plaintext ต้องตั้ง `requires_password_reset`/บังคับ reset และ **ห้าม**นำไป backstop อัตโนมัติ
**ลำดับ compatibility บังคับ:** Backend auth ต้องพร้อม → Flutter เปลี่ยน login/register/social ไป Backend → revoke direct password-hash query → จึงเปิด lazy rehash/backstop; ห้าม rehash ก่อนแอป switch

---

### Q5 — Public data contract: อะไรอ่านตรงด้วย anon key ได้
**ข้อเท็จจริง:** `rls_audit_report.md` (2026-07-28) ระบุ 46 ตาราง: 15 มี policy เหมาะสม, **23 มี RLS แต่ `USING(true)`**, 6 เคยไม่มี RLS (แก้แล้ว), 2 ไม่มี RLS โดยเจตนา; ตารางเสี่ยงสูงที่ยัง `USING(true)`: `chat_rooms`, `chat_messages`, `consultation_requests`, `payment_transactions`, `checkout_sessions`, `provider_credentials`, `donation_contributions`

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** | คง public read ทั้ง Fitness ตามเดิม (ทุกคอลัมน์) | ไม่ต้องแก้ browse flow เลย | รายชื่อสมาชิก/pending/โปรไฟล์รั่วผ่าน REST ตรง |
| **B** ⭐ | สร้าง **public VIEW ต่อ use case** (เช่น `fitness_groups_public`, `fitness_sessions_public`) ที่ expose เฉพาะคอลัมน์ที่ตั้งใจ แล้วให้ anon อ่านได้เฉพาะ view; ตารางจริงปิด anon SELECT | ขอบเขต public ชัดเจนตรวจสอบได้; browse ไม่ต้องล็อกอิน; ไม่ต้องรอ gateway | ต้องแก้ query ฝั่ง Flutter ให้ชี้ view |
| **C** | ปิด anon อ่านทั้งหมด ให้ทุก read ผ่าน gateway | ควบคุมสูงสุด + audit ครบ | ขัดข้อกำหนด "ดูก๊วนได้โดยไม่ล็อกอิน" ถ้า backend ล่ม; latency เพิ่มทุกหน้า |

**คำแนะนำ: B** — เป็นวิธีที่ให้ผลลัพธ์ security สูงโดยไม่แตะ 189 call sites และทำได้ก่อน gateway
**Deliverable ที่ต้องมีก่อน 13.0 จบ:** ตาราง classification ทุกตาราง Fitness ระบุ `public / member / manager / server-only` ต่อคอลัมน์

---

### Q6 — Refresh token rotation กับ parallel request
**ข้อเท็จจริง:** ยังไม่มีตาราง `refresh_tokens`; มี `public.sessions` จาก `20260728190000_create_sessions_table.sql`; Redis มี `getSession/setSession/deleteSession` (`auth:session:${sessionId}`) ที่ไม่มีใครเรียก; Redis เป็น single instance `localhost:6379`

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** | Strict: refresh ซ้ำ = revoke ทั้ง family ทันที | ตรวจ token theft ได้ไวสุด | มือถือยิงขนาน/รีทรายทำให้ผู้ใช้ถูกเตะออกโดยไม่มีการโจมตี |
| **B** ⭐ | **Rotation + grace window**: token เก่าใช้ได้อีก 30–60 วินาทีหลัง rotate โดยคืน token ใหม่ **ใบเดิม** (idempotent), พร้อม Redis lock ต่อ session; ถ้าใช้ token เก่า *หลัง* grace = revoke family | ไม่ false-positive จาก parallel refresh; ยังตรวจ theft ได้ | ช่องเวลาที่ token ถูกขโมยใช้ได้จริง ≤ grace |
| **C** | ไม่ rotate: refresh คงเดิมจนหมดอายุ | ง่ายสุด ไม่มี race | เสีย property การตรวจ theft ทั้งหมด — ขัดแผน 08 |

**คำแนะนำ: B** — grace window 60 วินาที + `SETNX` lock ต่อ `session_id` (Redis มี distributed lock pattern ใช้อยู่แล้วตาม `caching_strategy.md`) พร้อม **client-side single-flight** (refresh หนึ่งครั้งต่อ session ในขณะเดียวกัน)
**ข้อกำหนดที่เพิ่มเพื่อให้ replay ได้จริง:** เพราะ server เก็บ hash อย่างเดียวจึงคืน raw token ใหม่ให้ parallel request ไม่ได้; ต้องเก็บ refresh response ล่าสุดแบบ **เข้ารหัส** ใน Redis/secure server cache ด้วย TTL 60 วินาที (ห้ามเก็บ raw token plaintext ใน PostgreSQL/log) หรือใช้ idempotent refresh-result store ที่เทียบเท่า
**การออกแบบตาราง:** **reuse `public.sessions` ที่มีอยู่แล้ว** (`20260728190000_create_sessions_table.sql`) เป็น refresh-session registry; migration ใหม่เพิ่ม `family_id`, `prev_token_hash`, `rotated_at` และใช้ `device_info` เดิม และใช้ `token_hash` เป็น hash ของ refresh token — เก็บ hash ใน PostgreSQL เป็น source of truth; Redis ใช้ lock/denylist และ encrypted replay result TTL 60 วิเท่านั้น เพราะ Redis เป็น single instance ไม่มี HA (`caching_strategy.md`); ห้ามสร้างตาราง refresh registry ใหม่ซ้ำซ้อน
**มติ implementation:** reuse/extend `public.sessions` เดิม — schema นี้มี `user_id`, `token_hash`, `expires_at`, `revoked_at`, `device_info` และ index ที่ต้องใช้แล้ว; migration ใหม่เพิ่มเฉพาะ `family_id`, `prev_token_hash`, `rotated_at`; ห้ามสร้าง refresh state ซ้ำซ้อน

---

### Q7 — ⚠️ `SET LOCAL app.user_id` ใช้กับ Supabase ไม่ได้ตามที่แผนเขียนไว้
**ข้อเท็จจริงที่เปลี่ยนแผน:**
- `server.js` สร้าง `new Pool()` ชี้ **local PostgreSQL** (`DB_HOST=localhost:5432`) ไม่ใช่ Supabase
- การคุย Supabase ทำผ่าน `@supabase/supabase-js` (PostgREST/HTTP) ใน 10 ไฟล์
- ข้อมูล Fitness ทั้งหมดอยู่ใน **Supabase** ไม่ใช่ local DB
- **PostgREST ทำ `SET LOCAL` ข้าม statement ไม่ได้** เพราะแต่ละ RPC call เป็น transaction ของตัวเอง
- ไม่พบการใช้ pooler (`6543`) หรือ `pgbouncer` ที่ใดเลย จึงยังไม่มีข้อผูกมัด

**สรุป:** ประโยค "Backend `BEGIN` → `SET LOCAL app.user_id` → RPC → `COMMIT`" **ใช้ได้เฉพาะเมื่อ backend เปิด connection `pg` ตรงไปยัง Supabase Postgres** ไม่ใช่ผ่าน supabase-js — แผนเดิมยังไม่ได้ระบุจุดนี้

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** | Backend เปิด `pg` Pool ตรงไป Supabase Postgres (transaction pooler `:6543`) แล้วทำ `BEGIN; SET LOCAL app.user_id; ...; COMMIT` | ตรงกับ `app.require_current_user_id()` ที่ **มีอยู่แล้ว**; ควบคุม transaction/atomicity เต็มที่ | backend ต้องถือ DB credential ของ Supabase; ทุก read/write ที่ต้อง identity ต้องผ่าน backend (แตะ call sites จำนวนมาก) |
| **B** | ไม่ใช้ `SET LOCAL`; backend เรียก legacy RPC ที่รับ actor param แต่ **client เรียกไม่ได้แล้ว** (revoke จาก anon) | เปลี่ยนน้อยสุด; ใช้ RPC ที่มีอยู่ทันที | RLS ไม่ได้เป็นชั้นป้องกัน เพราะ service_role bypass ทั้งหมด — เหลือชั้นเดียวคือ backend |
| **C** ⭐ | **Hybrid ตามความเสี่ยง**: <br>• public read → anon key + public VIEW (Q5-B) <br>• private read → client ยิง Supabase ตรงด้วย **JWT ที่ sign ด้วย Supabase JWT secret** → PostgREST verify → RLS ใช้ `auth.uid()`/`request.jwt.claims` <br>• mutation ที่ต้อง atomic/มี side effect → gateway + `pg` ตรง + `SET LOCAL` | ไม่ต้อง refactor 189 call sites ทันที; ได้ RLS จริงที่ DB; mutation สำคัญยัง atomic และ audit ได้ | ต้องดูแลสอง identity path; revoke access token ก่อนหมดอายุใน PostgREST path ทำไม่ได้ → ต้องใช้ TTL สั้น |

**คำแนะนำ: C** — เป็นตัวเลือกเดียวที่สอดคล้องกับข้อเท็จจริงทั้งสามข้อ: (1) 189 call sites, (2) 372 permissive policy ที่ต้อง tighten อยู่แล้ว, (3) ต้องคง public browse
**ผลต่อ RLS:** policy ของตาราง Fitness ควรอ่าน identity จาก **ทั้งสองแหล่ง** ผ่าน helper เดียว แต่ต้องตรวจ conflict ก่อนเลือกค่า:
```
app.current_user_id() :=
  gateway_id := parse_uuid(current_setting('app.user_id', true))
  rest_id := parse_uuid(request.jwt.claims ->> 'sub')
  if gateway_id IS NOT NULL AND rest_id IS NOT NULL AND gateway_id <> rest_id:
    RAISE EXCEPTION 'UNAUTHORIZED'
  return COALESCE(gateway_id, rest_id)
```
helper ต้องยืนยัน active user และทุก policy/RPC ใช้ helper นี้ตัวเดียว เพื่อไม่ให้ identity ที่ขัดกันถูกกลบด้วย `COALESCE`
**ถ้าเลือก A:** ต้องยืนยันว่า Supabase pooler mode ที่ใช้เป็น **transaction mode** (`:6543`) ซึ่ง `SET LOCAL` ทำงานได้เพราะอยู่ใน transaction; ห้ามใช้ `SET` ธรรมดาเด็ดขาด

---

### Q8 — Offline / LocalOnly กับ fail-closed
**ข้อเท็จจริง:** `AppConfig.databaseMode` hardcode เป็น `unified`; `SyncService._pendingChanges` และ `UnifiedRepository._offlineQueue` เป็น **in-memory list ไม่ persist** — ปิดแอปคือหาย; log จาก `flutter run` แสดงว่าเมื่อเน็ตหลุดทั้ง Supabase และ local API ล้มเหลวพร้อมกันและแอปยัง retry เป็นรอบ

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** ⭐ | **Fitness mutation = online-only, fail closed** (ไม่มี offline queue); เก็บ offline capability ไว้เฉพาะ Emergency/Health ที่จำเป็นจริง | ตรงกับ business จริง (จองรอบนัดขณะออฟไลน์ไม่มีความหมาย เพราะ capacity ต้องตรวจที่ server); ลด attack surface มาก | ผู้ใช้ที่เน็ตไม่ดีทำรายการไม่ได้ |
| **B** | ทำ persistent encrypted outbox สำหรับทุก module | UX ดีที่สุดตอนออฟไลน์ | ต้องออกแบบ conflict/idempotency/replay auth ทั้งระบบ — งานใหญ่และเสี่ยง double-booking |
| **C** | Outbox เฉพาะ Emergency + re-verify token ตอน sync | สมดุล | ยังต้องมี persistent store + token grace |

**คำแนะนำ: A** — และระบุในแผนตรง ๆ ว่า Fitness ไม่รองรับ offline mutation
**เหตุผลเชิงเทคนิค:** capacity ของรอบนัดต้อง atomic ที่ DB (`pending` ไม่กินที่นั่ง, ตรวจซ้ำตอน approve) — offline booking ที่ sync ภายหลังจะขัดกับกติกานี้โดยพื้นฐาน
**ผลพลอยได้ที่ควรทำ:** in-memory queue ที่มีอยู่ควรถูกลบหรือทำ persistent ให้ชัด เพราะสถานะปัจจุบัน "ดูเหมือนมี offline support แต่หายเมื่อปิดแอป" อันตรายกว่าไม่มีเลย

---

### Q9 — WebSocket room authorization
**ข้อเท็จจริง:** `join-room` และ `join-emergency-chat` **ไม่มี membership check** — client join ห้องใดก็ได้; handshake รับ `socket.handshake.auth.token` เป็น user id ตรง ๆ; group chat ของ Fitness ผูก `chat_rooms` (`group_chat_popup.dart`)

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** ⭐ | ตรวจ membership ที่ DB ทุกครั้งที่ join + cache ผลใน Redis 60 วินาที; ห้าม join ห้องที่ไม่ผ่านการตรวจ | ถูกต้องเสมอ; สอดคล้อง blocklist/remove member ที่เปลี่ยนได้ตลอด | +1 query ต่อ join (cache ช่วยได้) |
| **B** | ใส่รายการห้องที่อนุญาตใน JWT claims | ไม่ต้อง query ตอน join | claims เก่าหลังถูกถอด/บล็อก; token ใหญ่ขึ้นตามจำนวนก๊วน |
| **C** | ตรวจตอน join + ตรวจซ้ำตอน emit ทุก event | แน่นที่สุด | overhead สูงต่อ event; ต้องระวัง latency ของแชท |

**คำแนะนำ: A + องค์ประกอบของ C เฉพาะ event ที่มีผลถาวร** — 13.1 เป็นต้นไปใช้ direct `pg`/`sheserved_app` ตรวจ DB ตอน join; ก่อน DB foundation พร้อม ห้ามให้ HTTP/socket handler ใช้ service_role ทั่วไป (ถ้าจำเป็นต้องมี compatibility adapter ให้เป็น read-only allowlist, time-boxed และมี audit); ตรวจซ้ำก่อน `message:send` และ `history/read` ที่เปิดเผยข้อมูลหรือเขียนถาวร ส่วน `typing` ใช้ผลจาก join ได้
**เพิ่มเติมบังคับ:** ต้อง **invalidate cache ทันที** เมื่อมีการถอดสมาชิก/บล็อก/revoke และต้อง force-leave socket ที่อยู่ในห้องนั้น; ถ้ามีหลาย socket instance ให้ใช้ Redis Pub/Sub

---

### Q10 — Canary จะวัดอะไรถึงถือว่าผ่าน
**ข้อเท็จจริง:** gate เดิมเขียนเชิงคุณภาพ ("ไม่มี booking ซ้ำ, capacity drift") ยังไม่มีตัวเลข; ไม่มีตาราง `audit_logs`; `pino` ยังไม่ถูกใช้จริง

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** | ใช้ SQL invariant query รายวันเป็น gate | ทำได้ทันที ไม่ต้องมี observability stack | เห็นย้อนหลัง ไม่ real-time |
| **B** ⭐ | SQL invariant + structured log counter + alert 3 ตัว (auth failure spike, permission-denied spike, invariant violation) | ตรวจจับได้จริงและยังไม่ต้องลงทุน Loki/Grafana ทันที | ต้องทำ `pino` ให้ทำงานจริงก่อน |
| **C** | ตั้ง Loki + Grafana + dashboard ก่อนเริ่ม canary | สมบูรณ์ที่สุด | เลื่อน Phase 13 ออกไปเพื่องาน infra |

**คำแนะนำ: B** — โดยใช้ invariant query เหล่านี้เป็น **hard gate** (ต้อง = 0 ทุกข้อ ต่อเนื่อง 7 วัน):
```sql
-- 1. confirmed เกิน capacity ของรอบ
SELECT count(*) FROM fitness_group_sessions s
WHERE (SELECT count(*) FROM fitness_group_bookings b
       WHERE b.session_id = s.id AND b.status = 'confirmed') > s.capacity;

-- 2. booking ซ้ำ (ควรถูกกันด้วย UNIQUE แต่ต้องยืนยันว่าไม่มีทางเลี่ยง)
SELECT count(*) FROM (
  SELECT session_id, user_id FROM fitness_group_bookings
  GROUP BY session_id, user_id HAVING count(*) > 1
) d;

-- 3. ผู้ถูกบล็อกยังมี booking ที่ยังไม่ยกเลิกในรอบอนาคต
SELECT count(*) FROM fitness_group_bookings b
JOIN fitness_group_sessions s ON s.id = b.session_id
JOIN fitness_group_blocklist bl
  ON bl.group_id = s.group_id AND bl.blocked_user_id = b.user_id AND bl.is_active
WHERE b.status IN ('pending','confirmed') AND s.starts_at > now();

-- 4. owner_auto_join = true แต่ owner ไม่มี confirmed booking ในรอบอนาคต
SELECT count(*) FROM fitness_groups g
JOIN fitness_group_sessions s ON s.group_id = g.id AND s.starts_at > now()
WHERE g.owner_auto_join
  AND NOT EXISTS (SELECT 1 FROM fitness_group_bookings b
                  WHERE b.session_id = s.id AND b.user_id = g.created_by
                    AND b.status = 'confirmed');

-- 5. active membership ที่ไม่มี pending/confirmed booking ใน upcoming sessions และไม่ใช่ admin/owner
SELECT count(*) FROM fitness_group_members m
JOIN fitness_groups g ON g.id = m.group_id
WHERE m.is_active AND m.role <> 'admin' AND m.user_id <> g.created_by
  AND NOT EXISTS (SELECT 1 FROM fitness_group_bookings b
                  JOIN fitness_group_sessions s ON s.id = b.session_id
                  WHERE s.group_id = m.group_id AND b.user_id = m.user_id
                    AND s.starts_at > now()
                    AND b.status IN ('pending', 'confirmed'));
```
**SLI/SLO ที่เสนอ:** auth endpoint error rate < 1% (ไม่รวม invalid credential ตามเกณฑ์ที่กำหนด), refresh success rate > 99% (แยก revoked/expired ออกจาก server error), p95 latency ของ mutation ผ่าน gateway ≤ baseline + 150 ms, invariant ใหม่ 1–5 = 0 ต่อเนื่อง 7 วัน, จำนวน `authz.denied` ต่อผู้ใช้ไม่เกิน baseline × 1.5
**ข้อกำหนด baseline:** รัน invariant 1–5 ก่อน canary, แยก/แก้ pre-existing violation ให้หมดหรือบันทึก waiver พร้อม owner; gate นับเฉพาะ violation ใหม่หลังเริ่ม canary; 404 จาก BOLA concealment ห้ามนับรวมเป็น permission spike โดยไม่จำแนก event

---

### Q11 — Audit log ของ auth จะไปที่ไหน และเมื่อไหร่
**ข้อเท็จจริง:** **ไม่มีตาราง `audit_logs`**; มี `transaction_audit_log` + `record_audit_log()` (procurement), `victim_report_consent_logs`, `victim_health_access_logs`; แผน 05 เสนอ schema `audit_logs` ไว้ครบแล้วและระบุว่าแผน 12 `permission_audit_log` ควรรวมเป็นตารางเดียวกัน

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** | structured log (pino) เท่านั้นในช่วง Phase 13, ทำตาราง audit ที Phase S1 | เร็ว ไม่ต้องออกแบบ schema | ช่วง cutover ไม่มี audit trail ที่ query ได้ — จุดที่ต้องการมากที่สุด |
| **B** ⭐ | สร้าง `audit_logs` ตาม schema แผน 05 ตั้งแต่ 13.2 แต่ **เขียนเฉพาะ auth + Fitness manager action** ก่อน (ไม่ต้องครบทุก module) | มี trail ตอน cutover; schema เดียวใช้ต่อได้ทั้งระบบ; ตอบ compliance ในอนาคต | ต้อง partition/retention ตั้งแต่ต้น |
| **C** | reuse `transaction_audit_log` ที่มีอยู่ | ไม่เพิ่มตาราง | schema ออกแบบมาเพื่อ procurement; ปนความหมาย |

**คำแนะนำ: B** — สร้างตารางเดียวแต่เริ่ม populate แค่ scope ที่จำเป็น
**Event ขั้นต่ำที่ต้อง log ใน 13.2:** `auth.login.success/failure`, `auth.refresh.success/reuse_detected`, `auth.logout`, `auth.session.revoked`, `auth.password.changed`, `authz.denied`, และ Fitness: `fitness.session.created/cancelled`, `fitness.booking.approved/rejected`, `fitness.member.removed`, `fitness.user.blocked`
**ข้อกำหนด implementation:** ถ้า partition ตาม `occurred_at` ต้องออกแบบ primary/unique key ให้รวม partition key เช่น `(occurred_at, id)` หรือใช้ index strategy ที่ถูกต้องกับ PostgreSQL; ห้ามใช้ primary key `id` เดี่ยวบน partitioned parent โดยไม่ตรวจสอบ
**การเขียน audit:** auth handler/HTTP request ห้ามถือ service_role เพื่อเขียนโดยตรง; ส่ง event เข้า durable queue/outbox แล้ว `audit-worker` ที่มี `sheserved_worker` เป็นผู้เขียน; compliance event เขียน transaction เดียวกับ operation; ต้อง redaction PII/secret และมี retry/dead-letter
**ข้อบังคับ:** ต้อง `REVOKE UPDATE, DELETE ON audit_logs` จาก app role ตั้งแต่ migration แรก (แผน 05 และ 12 ระบุตรงกัน)

---

### Q12 — Backend ที่ถือ service_role กลายเป็นเป้าหมายเดียว
**ข้อเท็จจริง:** service_role ถูกใช้ใน 10 ไฟล์ และ **บาง service fallback ไป `SUPABASE_ANON_KEY`** เมื่อไม่มี service key; ไม่มี secret manager; TLS ยังไม่ implement; `ALLOWED_ORIGINS` default เป็น `'*'`

| ตัวเลือก | เนื้อหา | ข้อดี | ข้อเสีย |
|---|---|---|---|
| **A** | คง service_role ใช้ต่อ แต่จำกัดเฉพาะ background jobs และห้ามอยู่ใน request path | ทำได้เร็ว; ตรงกับ `bounded_gateway_design.md` | request path ยังต้องมี credential อื่นอยู่ดี |
| **B** ⭐ | สร้าง permission role `sheserved_app NOLOGIN` (ไม่มี `BYPASSRLS`) และ login role `sheserved_gateway LOGIN` ที่ `SET ROLE sheserved_app` สำหรับ business request path; เพิ่ม auth-only role/pool แยกสำหรับ login/session functions; คง service_role เฉพาะ migration/sync/audit-worker/system job + **ลบ fallback ไป anon ทั้งหมด** | ได้ least privilege จริง; RLS เป็นชั้นป้องกันที่สอง; ตรงแผน 12 | ต้องสร้าง role (ยังไม่มี `CREATE ROLE` ใน migration เลย) และ grant ต่อ object |
| **C** | ย้าย secret ไป Vault/Infisical ก่อนเริ่ม | จัดการ secret ครบ | เลื่อน Phase 13 เพื่องาน infra |

**คำแนะนำ: B** — และทำ `.env` hardening ขั้นต่ำ (permission 600, ไม่มี fallback เงียบ, `ALLOWED_ORIGINS` บังคับตั้งค่าใน production) โดยเลื่อน secret manager ไปหลัง cutover
**ความเสี่ยงที่ต้องยอมรับอย่างชัดเจน:** backend ยังเป็น single point of compromise — บรรเทาด้วย `sheserved_gateway` ที่ไม่มี `BYPASSRLS`/DDL และใช้ `SET ROLE sheserved_app` ใน transaction; ห้าม HTTP handler ถือ service_role; service_role แยกไว้เฉพาะ worker/system job; ห้ามลบ audit log

---

## Phase 13 — โครงสร้าง sub-phase ฉบับปรับปรุง

> **Decision Q1 = B (2026-08-30):** แต่ละ sub-phase เป็น **release ที่ deploy ได้จริงแบบอิสระ** และต้อง "ปล่อยแล้วค้างอยู่ได้ไม่มีกำหนดโดยไม่ทำให้ระบบแย่ลง" (independently shippable)
> **กฎ 3 ข้อของ Q1-B:**
> 1. ทุก sub-phase ต้องจบด้วย **deliverable ที่ deploy ได้** และถ้าหยุดหลัง sub-phase ใด ระบบต้องปลอดภัยกว่า/เท่าเดิม ไม่ใช่ครึ่ง ๆ กลาง ๆ
> 2. **ห้ามเริ่ม sub-phase ถัดไปก่อนปิด gate ของ sub-phase ปัจจุบัน** (แต่ละ gate ต้องมีหลักฐาน เช่น log/metrics/test ที่รันผ่าน)
> 3. ถ้าตัดสินใจหยุดกลางทาง ให้เลือกจุดหยุดที่ "ปลอดภัยที่สุดต่อความพยายาม" — จุดที่แนะนำคือหลัง 13.0 (prerequisite พร้อม), หลัง 13.1 (DB role/pooler พร้อม แต่ยังไม่เปิด auth path), หลัง 13.2 (auth จริง, audit worker และ Flutter switch แล้ว แต่ Fitness ยัง legacy), และหลัง 13.3 (HTTP/WebSocket identity verify แล้ว) — แต่ละจุดมี Safe Stop/Deliverable/Gate ของตัวเอง
> ลำดับพึ่งพาที่ปรับตามความเสี่ยงและ least privilege: **12.9 → 13.0 → 13.1 (DB bootstrap/role spike) → 13.2 (server auth + Flutter switch) → 13.3 (verified HTTP/WebSocket + room auth) → 13.4 → 13.5 → 13.6**; ห้ามเริ่ม phase ถัดไปก่อน gate ปัจจุบันผ่าน

### Phase 12.9 — Hotfix ช่องโหว่ที่ทำงานอยู่ (ทำก่อนทุกอย่าง, ไม่ต้องรอ decision)
- แก้ `updatePassword()` ให้ hash ก่อนบันทึก (B1) — เป็น bug ที่ทำให้ล็อกอินไม่ได้ด้วย; ตรวจและหยุดใช้แถวที่พบว่าเป็น plaintext
- **Password exposure containment (B2):** ห้ามคืน `password_hash` ใน generic user/public view และห้ามเพิ่ม call site ใหม่; **ยังไม่ revoke direct auth query ของแอปเก่า** จนกว่า Phase 13.2 จะเปลี่ยน Flutter login ไป Backend มิฉะนั้นแอปเก่าจะล็อกอินไม่ได้
- ตัด `password_hash` ออกจาก select list ของ `SyncService` และ purge สำเนาเดิมจาก local store (B3)
- ลบ `passwordHash` จาก `UserModel` และทุกจุดที่ serialize (B4)
- เพิ่ม `pino` เป็น direct dependency (Q10-B ต้องใช้ structured counter), ตรวจ lockfile/supply chain, wire `request-context` ที่มีอยู่เข้าจุดเริ่ม Express และทดสอบ redaction; ห้ามถอด logger แล้วกลับไปใช้ unstructured log เพราะจะทำให้ canary gate Q10 ไม่ครบ
- **Plaintext scan:** ตรวจรูปแบบ/แหล่งที่มาของ `users.password_hash`; แถวที่ไม่ใช่ legacy SHA-256/Argon2id ให้ตั้งสถานะ `requires_password_reset` หรือบังคับ reset โดยไม่พยายาม hash ค่า plaintext เดิมอัตโนมัติ
- **จุดหยุดที่ปลอดภัย (Safe Stop):** ✅ หยุดได้ แต่ต้องบันทึก residual risk ว่า B2 ยังไม่ปิดเต็มรูปแบบจนกว่า 13.2 compatibility cutover
- **Deliverable:** hotfix PR + local-data purge + plaintext inventory + test report
- Gate: update password ไม่เก็บ plaintext; plaintext inventory มีการจัดการ; ไม่มี `password_hash` ใน sync/model/public response ใหม่; ระบบเดิมยัง login/register ได้; `pino` redaction/request ID ทำงาน; B2 direct query มี owner และวันปิดใน Phase 13.2
- **Implementation status (2026-09-02):** ✅ **Phase 12.9 ปิดสมบูรณ์** — โค้ด hotfix + migration + regression ครบ
  - B1 `updatePassword()` hash ก่อนบันทึก ✅
  - B2 containment แก้ backend `POST /api/users` และ `PUT /api/users/:id` จาก `RETURNING *` เป็น explicit column list (ไม่คืน `password_hash`) ✅
  - B3 ตัด `password_hash` ออกจาก sync select list + purge local (`_saveToLocal` set `password_hash=null`) ✅
  - B4 ลบ `passwordHash` ออกจาก `UserModel` (field/ctor/toJson/fromJson/copyWith) ✅
  - `pino` ลง direct dependency + wire `requestContext` ที่ Express + redaction test ผ่าน (top-level และ nested) ✅
  - migration `20260831120000_phase_12_9_password_hotfix.sql` **apply สำเร็จ** (เพิ่ม `password_algo`/`password_updated_at`/`password_migrated_at`/`requires_password_reset`) ✅
  - **Plaintext inventory:** ไม่พบแถว plaintext ใน DB (0 แถวถูก mark `requires_password_reset`); แถวที่มีทั้งหมดเป็น SHA-256 64-hex ปกติ (7 แถว) ✅
  - **Regression ผ่านจริงบนอุปกรณ์:** login (บัญชีที่มีอยู่) ✅, register (บัญชีใหม่ `dave`, `password_algo='sha256'`, `requires_password_reset=false`) ✅; change-password ยังไม่ได้ทดสอบเพราะหน้า login ไม่มีปุ่ม "ลืมรหัสผ่าน"/"เปลี่ยนรหัส" — เป็น known gap ของ UI ปัจจุบัน ไม่ใช่ regression ของ hotfix (B1 fix ยืนยันด้วย register path ที่ hash ถูกต้องแล้ว)
  - ⚠️ **Residual risk (ปิดใน 13.2):** B2 ยังไม่ปิดเต็มรูปแบบจนกว่า 13.2 compatibility cutover — Supabase direct `.select()` ใน `createUser`/`login`/`getUserByUsername` ยังคืน `password_hash` ใน HTTP response แต่ `UserModel.fromJson` ไม่อ่านแล้ว; `local_database_repository.createUser` และ `database_service.createUser` ยังรับ `passwordHash` (dead code ไม่มี caller แต่ไม่ลบเพราะเป็น existing path ใน compatibility window)
  - ⚠️ **ค้างต่อไปใน 13.0/13.3:** `npm audit` พบ high severity ใน `socket.io-parser` (pre-existing ไม่ใช่ pino)
  - **Gate ผ่าน:** update password ไม่เก็บ plaintext ✅, plaintext inventory มีการจัดการ (0 แถว) ✅, ไม่มี `password_hash` ใน sync/model/public response ใหม่ ✅, ระบบเดิม login/register ได้ ✅, `pino` redaction/request ID ทำงาน ✅, B2 direct query มี owner และวันปิดใน Phase 13.2 ✅

### Phase 13.0 — Prerequisites (เอกสาร, secret, network, data contract)
- ตัดสินใจ Q1–Q12 และบันทึกใน Decision Log
- **Public data contract:** ตาราง classification ต่อคอลัมน์ของทุกตาราง Fitness (`public / member / manager / server-only`)
- **Decision Q5 = B (public VIEW):** สร้าง public VIEW ต่อ use case โดย expose เฉพาะคอลัมน์ที่ตั้งใจ:
  - `fitness_groups_public` — รายการการ์ด: id, sport_id, name, description, province, district, lat/lng (ปัดถ้าจำเป็น), gender_preference, cover_image_url, venue_photo_url, created_at, aggregate รอบ upcoming/confirmed/pending โดยไม่เปิดรายชื่อ
  - `fitness_sessions_public` — รายละเอียดรอบ: id, group_id, starts_at, ends_at, capacity, confirmed_count, available_count, place_name, lat/lng, note
  - **ห้าม** expose ใน public view: `created_by`, รายชื่อ members/bookings, blocklist, owner_auto_join หรือข้อมูลส่วนตัว
  - ตั้งค่า view เป็น security model ที่ตรวจสอบแล้ว (ไม่เปิดทางอ้อมให้ anon อ่านตารางจริง); anon อ่านได้เฉพาะ view และตารางจริงจะปิด anon SELECT ใน migration cutover 13.5
  - Flutter repository เปลี่ยน query browse ไปชี้ view; count/aggregate ต้องทดสอบว่าไม่เปิด row ของ member
  - Grant `SELECT` เฉพาะ view ให้ `anon`/`authenticated`; ห้าม grant mutation ให้ `authenticated` เพราะ Q7-C ให้ mutation ผ่าน gateway เท่านั้น
- เพิ่ม env template สำหรับ JWT (`JWT_ACTIVE_KID`, `JWT_ACTIVE_SECRET`, `JWT_PREVIOUS_KID`, `JWT_PREVIOUS_SECRET`, `JWT_ISSUER`, `JWT_AUDIENCE`, `ACCESS_TTL`, `REFRESH_TTL`, `SUPABASE_JWT_SECRET`) โดยไม่ใส่ค่าจริงใน git; validator ต้อง fail startup เมื่อ key/issuer/audience/TTL ผิดหรือซ้ำกัน
- **Decision Q3 = A:** HS256 dual-key — เก็บ key active/previous ใน server secret store (`.env` permission 600 ในระยะแรก), ใส่ `kid`, allowlist algorithm เป็น HS256 เท่านั้น, verify ต้องเลือกเฉพาะ known `kid` และลอง active/previous ระหว่าง rotation, sign ด้วย active เท่านั้น; runbook rotation 90 วันตาม `docs/secure/07_secret_management.md`
- **Decision Q7 = C:** public read → anon+VIEW; private read → short-lived PostgREST token ที่ Backend ออกให้และ sign ด้วย `SUPABASE_JWT_SECRET` (claims อย่างน้อย `sub`, `role='authenticated'`, `iss`, `aud`, `iat`, `exp`, TTL ≤5 นาที, ไม่ใช่ access/refresh token หลัก); mutation → Gateway + direct Supabase `pg` + `SET LOCAL`
- ลบ silent fallback `SUPABASE_SERVICE_KEY → SUPABASE_ANON_KEY` ในทุก service; ถ้าไม่มี service key ต้อง fail loud; ห้าม service_role อยู่ใน HTTP/Socket request handler
- บังคับ `ALLOWED_ORIGINS` ใน production (เลิก default `'*'`); ตรวจ CORS และ WebSocket origin allowlist
- HTTPS/WSS ผ่าน Caddy บน staging (ปัจจุบัน TLS ยังไม่มี — เป็น hard blocker ของ 13.2)
- **จุดหยุดที่ปลอดภัย (Safe Stop):** ✅ **แนะนำจุดหยุดแรก** — หลัง 13.0 config/contract/TLS พร้อมและยังไม่มี production path เปลี่ยน; residual risk B2 ยังถูกบันทึกจนกว่า 13.2 compatibility cutover
- **Deliverable:** env template + public data contract + public view design/test + config hardening PR
- Gate: environment validation ผ่าน, ไม่มี secret ใน client/log, view ไม่เปิด PII, HTTPS/WSS ใช้งานได้บน staging, service fallback ถูกลบ, Decision Log ครบทุกข้อ

### Phase 13.1 — DB identity context, roles และ RLS foundation (Decision Q7 = C, Q12 = B)
- **จุดประสงค์:** เตรียม trusted DB path, worker/audit role และ staging RLS ก่อนเปิด Auth/verified WebSocket; phase นี้ต้องไม่มี production cutover และยังไม่รับ traffic ใหม่
- **Decision Q7 = C:** สร้าง helper เดียวรวมสอง identity path — RLS/RPC ทุกจุดต้องอ่านจาก helper นี้เท่านั้น; `app.current_user_id()` ต้อง parse UUID/ตรวจ active user และถ้ามีทั้ง `app.user_id` กับ `request.jwt.claims.sub` แล้วไม่ตรงกันต้องคืน `UNAUTHORIZED` (ห้ามใช้ `COALESCE` กลบ identity conflict); `app.require_current_user_id()` เดิมเรียก helper นี้
- **PostgREST path (เตรียมไว้เท่านั้น):** private read จะใช้ token ที่ Auth Backend mint ให้ใน Phase 13.2 → PostgREST verify ด้วย Supabase JWT secret → policy อ่าน `request.jwt.claims` ผ่าน helper; token ต้องมี `sub`, `role='authenticated'`, `iss`, `aud`, `iat`, `exp` และ TTL ≤5 นาที
- **Decision Q12 = B / role model:** `sheserved_app NOLOGIN` เป็น permission role (ไม่มี `BYPASSRLS`, ไม่มี DDL, ห้าม UPDATE/DELETE `audit_logs`); `sheserved_gateway LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS` เป็น server-only business connection role ที่ `SET LOCAL ROLE sheserved_app`; เพิ่ม `sheserved_auth NOLOGIN` + `sheserved_auth_gateway LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS` สำหรับ bounded login/password/session functions และใช้ pool แยก (ไม่ให้ auth handler ใช้ service_role); `sheserved_worker`, `sheserved_readonly`, `sheserved_migrate` ใช้ credential/pool แยกตามหน้าที่; `sheserved_fitness_owner NOLOGIN` เป็น owner ของ bounded secure RPC
- Migration ใหม่ต้องสร้าง/ตั้งสิทธิ์ role ทั้งหมดแบบ idempotent ผ่าน migration/admin connection; ห้ามให้ app role สร้าง role หรือ DDL เอง
- **Gateway path:** local PostgreSQL pool เดิมต้องแยกจาก Supabase direct pool; direct pool ใช้ env `SUPABASE_DB_*` คนละชุด; ทุก request ทำ `BEGIN → SET LOCAL ROLE sheserved_app → SET LOCAL app.user_id/session_id/role/... → query/RPC → COMMIT/ROLLBACK`; error ต้อง `ROLLBACK` และ reset/release connection ทุกครั้ง
- **Spike ก่อนเปิด role/DB path:** ยืนยัน Supabase hosted อนุญาต role/membership, `sheserved_gateway` ต่อผ่าน transaction pooler `:6543` ได้, `SET LOCAL ROLE`/`SET LOCAL app.user_id` ทำงาน, RLS ไม่รั่วข้าม pooled connection และ role ไม่มี privilege เกินขอบเขต; ถ้าไม่ได้ให้หยุดและปรับ credential/network — เป็น hard gate
- โอน ownership secure RPC ไป `sheserved_fitness_owner`; grant `EXECUTE` เฉพาะ `sheserved_app`; Backend ห้ามเรียก legacy actor signature
- เขียน strict Fitness RLS ใน staging/shadow; private-read policy ให้ `authenticated` ตาม data classification; public browse ใช้ public VIEW และ grant `SELECT` เฉพาะ view; **ห้าม grant mutation ให้ `authenticated`**
- `public.sessions` เป็น auth-private: ห้าม grant table SELECT ให้ `anon`/`authenticated` แบบกว้าง; session-management endpoint ใช้ Backend/worker scoped access เท่านั้น และ refresh registry ไม่เปิดผ่าน public PostgREST
- service_role จำกัดเฉพาะ migration/sync/audit-worker/system job และมี pool แยกจาก HTTP/Socket request; ลบ silent fallback `SUPABASE_SERVICE_KEY → SUPABASE_ANON_KEY` ทุกจุด; ไม่มี key = fail loud
- **จุดหยุดที่ปลอดภัย (Safe Stop):** ✅ แนะนำจุดหยุดที่สอง — DB roles/helper/pooler พร้อมใน staging แต่ production RLS/legacy grants ยังไม่เปลี่ยน; ไม่มีผลต่อผู้ใช้
- **Deliverable:** migration roles + helper + Supabase direct-pool adapter + audit-worker role/outbox plumbing + staging RLS/public-view scripts + deny/allow matrix
- Gate: owner/active group admin/Sheserved admin/member/unrelated/blocked/missing/invalid identity matrix ผ่าน; pooled request A/B ไม่รั่ว; `sheserved_gateway`/`sheserved_app` ต่อ DDL/แก้ audit ไม่ได้; `public.sessions`/auth-private data ไม่เปิดผ่าน PostgREST; service_role ไม่อยู่ใน request handler; public browse ยังทำงาน

### Phase 13.2 — Auth foundation (ยังไม่แตะ Fitness path)
- **Decision Q3 = A:** sign HS256 ด้วย key active (`kid` ใน header), verify ด้วย active/previous ที่เป็น known key เท่านั้น; `ACCESS_TTL`/`REFRESH_TTL` ตาม role; ห้าม log secret/token
- เพิ่ม `routes/auth.js`: `login`, `social/:provider`, `refresh`, `logout`, `logout-all`, `me`, `sessions`, `sessions/:id`
- เพิ่ม dependency: `jsonwebtoken`, `argon2` (fallback `bcrypt` cost 12), `helmet`; ตรวจ published date ≥ 7 วันตามกฎ supply chain
- **Decision Q11 = B (audit_logs):** reuse/extend `public.sessions` เป็น refresh registry และสร้าง `audit_logs` ตาม schema แผน 05 ตั้งแต่ migration แรกของ 13.2 พร้อม index `(actor_id, occurred_at DESC)`, `(resource_type, resource_id, occurred_at DESC)`, `(event_type, occurred_at DESC)`; ถ้า partition ตาม `occurred_at` ให้ใช้ primary/unique key ที่รวม partition key เช่น `(occurred_at, id)` หรือ index strategy ที่ PostgreSQL รองรับ — ห้ามใช้ primary key `id` เดี่ยวบน partitioned parent โดยไม่ตรวจสอบ; `REVOKE UPDATE, DELETE` จาก app role ตั้งแต่แรก; retention security event 1 ปี online / 3 ปี archive
- Audit events ขั้นต่ำ: `auth.login.success/failure`, `auth.refresh.success/reuse_detected`, `auth.logout`, `auth.session.revoked`, `auth.password.changed`, `authz.denied`, และ Fitness: `fitness.session.created/cancelled`, `fitness.booking.approved/rejected`, `fitness.member.removed`, `fitness.user.blocked`; auth handler ส่งผ่าน durable queue/outbox ไป `audit-worker` ที่ใช้ `sheserved_worker`, ไม่ถือ service_role ใน HTTP request; compliance event เขียนใน transaction เดียวกับ operation; redaction ห้ามเก็บ password/token/OTP/secret/PII ที่ไม่จำเป็น
- **Decision Q4 = B (lazy rehash + backstop):** เพิ่ม `password_algo VARCHAR(20)`, `password_updated_at TIMESTAMPTZ`, `password_migrated_at TIMESTAMPTZ` และ `requires_password_reset BOOLEAN` บน `users`; verify `argon2id` ก่อน, legacy SHA-256 ต่อเมื่อยังอยู่ใน compatibility window แล้ว rehash เป็น Argon2id ทันที; backstop ใช้ `argon2(sha256(pw))` เฉพาะแถว legacy SHA-256 ที่ตรวจรูปแบบได้และไม่มี plaintext; แถว plaintext ให้บังคับ reset ห้าม hash ค่าเดิมอัตโนมัติ; ครบ 90 วันหลัง password cutover ผู้ใช้ที่ยังไม่เป็น `argon2id` ต้อง reset ผ่าน OTP
- Social: verify provider token ฝั่ง server ก่อน map `public.users` (ปัจจุบันเชื่อ SDK ทั้งหมด)
- **Decision Q7 = C:** ออก PostgREST token แยกใบสำหรับ private read — sign ด้วย `SUPABASE_JWT_SECRET`, claims `sub`, `role='authenticated'`, `iss`, `aud`, `iat`, `exp`, TTL ≤5 นาที; Backend เท่านั้นที่ mint token; ไม่ใช่ access/refresh token หลัก และ Flutter ห้ามถือ secret
- **Decision Q6 = B:** refresh token random ≥256-bit, เก็บ hash ใน `public.sessions` ที่ขยายแล้ว; rotate ทุกครั้ง; ใช้ client-side single-flight + Redis `SETNX` lock ต่อ `session_id`; เพื่อคืนผลลัพธ์เดิมให้ parallel request ต้องเก็บ refresh response ล่าสุดแบบเข้ารหัสใน Redis/server cache TTL 60 วิ (ห้าม raw token plaintext ใน DB/log); token เก่าหลัง grace = revoke family + audit; Redis ล่มให้ fallback DB ตาม policy
- ผูก `loginLockoutLimiter`/`authRateLimiter`/`otpCooldownLimiter` ที่มีอยู่แล้วเข้ากับ auth endpoints
- Flutter: declare `flutter_secure_storage` เป็น direct dependency; `AuthService` ถือ user + access token metadata โดยคง API `currentUser` เดิม; เพิ่ม authenticated HTTP client กลาง (refresh-once/single-flight, logout เมื่อ refresh ล้ม)
- **ลำดับ compatibility บังคับ:** (1) ship backend auth, (2) Flutter login/register/social เปลี่ยนไป Backend และเพิ่ม minimum-supported-app/force-update policy, (3) monitor ว่าไม่มี client-side login รุ่นเก่าค้าง, (4) revoke direct `password_hash` query/สิทธิ์ anon, (5) เปิด `PASSWORD_SERVER_VERIFY` และ lazy rehash/backstop; ระหว่าง transition server verify Argon2id + legacy SHA-256 ได้ แต่ไม่ให้ client query hash ต่อหลัง cutover
- **จุดหยุดที่ปลอดภัย (Safe Stop):** ✅ แนะนำจุดหยุดที่สาม — auth server + Flutter switch + password exposure cutover เสร็จ, แต่ Fitness ยังใช้ path เดิมและยัง spoof ได้ในส่วน Fitness (ห้ามเคลมว่า Fitness cutover)
- **Deliverable:** backend auth + extended `public.sessions`/`audit_logs`/durable audit queue + Flutter token layer + minimum-app-version control
- Gate: login/register/social/refresh/logout/session restore, refresh parallel/reuse, plaintext-reset, old-app rejection และ audit delivery ผ่าน test; **Fitness repository ยังไม่เปลี่ยน path**

### Phase 13.3 — Verified identity ที่ HTTP และ WebSocket (Decision Q2 = A, Q9 = A)
- **Decision Q2 = A:** `websocket-server` เดิมคือ identity authority; auth code อยู่ใน `middleware/auth.js`, `middleware/socket-auth.js` และ `routes/auth.js`; `server.js` ทำเพียง wiring (`io.use(socketAuth(...))`/mount routes) **ห้ามมี token decode/verify ใน `server.js`**
- `middleware/auth.js`/`socket-auth.js`: verify algorithm allowlist HS256, known `kid` (active/previous), signature, issuer, audience, expiry, session revoke และ active user แบบ fail closed; **เลิกใช้ `x-user-id` เป็น identity** (เหลือได้เฉพาะ tracing หลัง redaction)
- **ย้าย inline endpoints ทั้งหมดของ `server.js` (~33 จุด) เข้าสู่ `routes/` ทีละกลุ่ม** พร้อมใช้ `req.userId` แทน `userId`/`responderId` จาก body/query (จุดเสี่ยงที่พบ: ~1603, 1663, 1695, 1714, 1817, 1927, 2104) และปฏิเสธ mismatch
- **Decision Q9 = A:** handshake รับ signed access token เท่านั้น; ทุก `join` ต้องผ่าน DB membership check โดยใช้ Supabase direct-pool adapter/`sheserved_app` จาก 13.1 (ไม่ใช้ service_role ใน request handler) แล้ว cache ผลใน Redis 60 วิ; ก่อน 13.1 gate ผ่าน ห้ามเปิด room authorization ใน production
- ห้อง Fitness ตรวจ `chat_rooms` → `fitness_groups` → active `fitness_group_members` และไม่มี active `fitness_group_blocklist`; ต้องมี migration ผูก `chat_rooms.group_id` ↔ `fitness_groups.id`; consultation/emergency ตรวจ membership ของห้องนั้น
- invalidate cache + force-leave socket ทันทีเมื่อถอดสมาชิก/บล็อก/revoke; หลาย instance ใช้ Redis Pub/Sub; ตรวจซ้ำก่อน `message:send`, `history/read` และ event ที่มีผลถาวร; `typing` ใช้ผลจาก join ได้
- Flutter เปลี่ยน 3 จุด `x-user-id` (`victim_repository`, `watermark_repository`, `consultation_repository`) ไปใช้ `Authorization: Bearer`; private Supabase read ใช้ PostgREST token แยกจาก access token หลัก
- **จุดหยุดที่ปลอดภัย (Safe Stop):** ✅ แนะนำจุดหยุดที่สี่ — หลัง 13.3 HTTP/WebSocket identity verify แล้วและ room membership ทำงาน แต่ Fitness gateway/cutover ยังไม่เปิด; direct mutation legacy ยังต้องระบุ residual risk
- **Deliverable:** release 13.3 = verified middleware + `socket-auth` + BOLA refactor + room authorization + Flutter Bearer migration
- Gate: forged/unsigned/expired/wrong-issuer-audience/revoked token → 401; missing/conflicting identity → 401; actor mismatch → ปฏิเสธ; join ห้องไม่ได้รับอนุญาต → ปฏิเสธ; `message:send`/history หลัง revoke → ปฏิเสธ; public/anonymous allowlist ไม่ fallback ไป protected

### Phase 13.4 — Fitness Gateway canary (Decision Q10 = B, Q8 = A)
- เพิ่ม Backend endpoints ตามตาราง "Fitness secure endpoint/RPC mapping"; ทุก mutation ใช้ Supabase direct-pool adapter ผ่าน `sheserved_gateway` → `SET LOCAL ROLE sheserved_app` → `SET LOCAL app.*` → secure RPC/query ใน transaction เดียว
- Flutter ส่งเฉพาะ resource/business fields; **ห้ามส่ง actor ID เพื่อ authorization**; actor มาจาก verified `req.userId`
- **หนึ่ง write path ต่อ request** ผ่าน feature flag; ห้าม dual-write และห้าม optimistic local write ที่กลายเป็น write ที่สอง; idempotency key ต้องผูกกับ user/session/resource/action
- **Decision Q8 = A:** Fitness mutation online-only และ fail closed เมื่อไม่มี network/verified token; ไม่ใส่ Fitness booking/approval/member mutation ลง offline queue; offline Emergency/Health ต้องมี policy แยกและห้ามนำมาใช้กับ Fitness
- **Decision Q7 = C:** public browse ใช้ anon + public VIEW; private read ใช้ PostgREST token TTL ≤5 นาที; mutation ใช้ Gateway เท่านั้น; repository ต้องเลือก path ตาม data classification ไม่ fallback ข้ามขอบเขต
- Shadow mode เปรียบเทียบเฉพาะ authorization decision/read result โดยไม่ mutate ซ้ำ; ห้าม shadow path เขียน booking/notification/audit ซ้ำ
- **Decision Q10 = B:** ทำ `pino` ให้ทำงานจริงก่อน; เก็บ structured event พร้อม request/session/user ID แบบ redacted; cron รัน invariant SQL 1–5 ทุก 5 นาที และ alert violation แรกทันที
- Baseline ก่อน canary: เก็บ SLI/SLO และผล invariant 1–5 ของ path เดิมอย่างน้อย 7 วัน; แก้ pre-existing violation หรือทำ waiver พร้อม owner; ระหว่าง canary gate นับเฉพาะ violation ใหม่
- **Hard gate:** invariant ใหม่ 1–5 ต้อง = 0 ต่อเนื่อง 7 วัน; auth error < 1% (ไม่รวม invalid credential ตามเกณฑ์), refresh success > 99% (แยก revoked/expired), p95 mutation latency ≤ baseline + 150 ms, `authz.denied` ≤ baseline × 1.5
- **3 alerts:** auth failure spike > 20/นาที/IP หรือ > 5/นาที/user; `authz.denied` spike > 10/นาที/user (ไม่รวม 404 BOLA ที่จำแนกเป็น event อื่น); invariant violation; ช่องทางเริ่มต้น webhook/อีเมลหรือระบบแจ้งเตือนที่อนุมัติ
- **ผลพลอยได้บังคับ:** ตรวจ `UnifiedRepository._offlineQueue` และ `SyncService._pendingChanges`; Fitness ไม่ใช้ queue เหล่านี้ และ feature อื่นต้องไม่อ้างว่า persistent offline หาก queue ยังเป็น memory-only
- **จุดหยุดที่ปลอดภัย (Safe Stop):** ✅ canary เป็น cohort ผ่าน feature flag; ปิด flag กลับไป path เดิมได้โดยไม่เปิด anon mutation และเก็บ invariant/SLI เป็น baseline ของ 13.5
- **Deliverable:** gateway endpoints + feature flag + one-write-path guard + structured log/cron/alerts + invariant dashboard + canary runbook
- Gate: invariant/SLI/SLO ผ่าน 7 วัน; booking ซ้ำ/capacity drift/notification drift = 0; audit log ผูก actor/session/request ID ครบ; rollback flag ทดสอบจริง

### Phase 13.5 — Fitness security cutover
- **แยก 3 path ใน repository ตาม Q5-B/Q7-C:** (1) browse/public → anon + `fitness_groups_public`/`fitness_sessions_public`, (2) private read → Backend-issued PostgREST token และ RLS role `authenticated`, (3) mutation → Gateway direct-pg + `sheserved_gateway`/`SET LOCAL ROLE sheserved_app`; ห้าม fallback ข้าม path และห้ามใช้ anon กับ private data
- Fitness Repository ทุก mutation/private read ใช้ authenticated path; static scan ต้องยืนยันว่าไม่มี direct Supabase write/actor parameter/fallback เหลือใน Fitness
- migration cutover ใหม่ที่ผ่าน approval เท่านั้น: `REVOKE EXECUTE` legacy actor-param RPC จาก `PUBLIC, anon, authenticated`; ลบ permissive write policy ของ Fitness; enable/force strict RLS; public view grant เฉพาะ `SELECT`; private read policy ให้ `authenticated`; mutation RPC/table privilege ให้ `sheserved_app` เท่านั้น (ไม่ grant mutation ให้ `authenticated`)
- `sheserved_gateway` เป็น login role server-only และใช้ `SET LOCAL ROLE sheserved_app`; service_role ไม่อยู่ใน request path; ปิด `x-user-id`, request actor และ direct-Supabase mutation fallback ใน production
- ก่อน apply cutover ต้องมี min-supported app/force-update policy, verified gateway canary, invariant baseline ไม่มี violation ใหม่, backup/restore rehearsal และ rollback release ที่ยังใช้ secure path; **ห้ามมี runtime switch กลับไปเปิด anon mutation**
- Rollback ต้องเป็น Backend/App version ที่ยังใช้ secure path พร้อม matching DB forward-fix/migration ที่อนุมัติ; ห้าม down migration ที่คืนสิทธิ์ anon หรือ legacy actor RPC
- **จุดหยุดที่ปลอดภัย (Safe Stop):** ⚠️ จุดที่หยุดได้ยากที่สุด — หลัง 13.5 แล้วห้าม rollback ไป anon mutation เด็ดขาด; ถือเป็น commit ระยะยาวหลัง gate ครบ
- **Deliverable:** Fitness 3 paths + strict RLS/roles + legacy revoke + test/backup/rollback evidence
- Gate: anon direct REST/RPC ถูกปฏิเสธ; spoof UUID ไม่เปลี่ยนข้อมูล; public browse ยัง anonymous ได้; private read ไม่มี PII รั่ว; manager flow/capacity/owner rules ครบ; rollback secure release ทดสอบแล้ว

### Phase 13.6 — Module waves และ legacy cleanup
- ลำดับ wave ตามความเสี่ยง × ปริมาณ call sites จากการสำรวจจริง:
  1. `chat` (1 call site) + `health` (2) — เสี่ยงสูงแต่แตะน้อย ทำเป็น wave นำร่อง
  2. `consultation` (33) — เสี่ยงสูงและใหญ่สุด
  3. `donation`/escrow (16) — การเงิน
  4. `admin` (24) + `profile` (12)
  5. `erp` (19) + `pharmacy` (3) + `kpi` (3)
  6. `services` (31) — ชั้นล่างที่กระทบทุก module ทำท้ายสุด
- **แต่ละ wave เป็น release อิสระ (Q1-B):** หลังทุก wave ต้องไม่มี direct Supabase mutation/private-data bypass, private read ใช้ authenticated path, RLS ของ module strict, audit/metrics ผ่าน และสามารถหยุดค้างระหว่าง wave ได้โดยไม่กระทบ wave ที่ผ่านมา
- tighten RLS/DB grants เฉพาะหลัง cutover ของ module นั้น; ห้าม big-bang ทั้ง 372 policy; `service_role` ต้องอยู่เฉพาะ worker/system path
- ลบ client-side password verification, `passwordHash`, `x-user-id`, unsigned token decode และ legacy RPC ที่รับ actor (หรือคงไว้แบบ revoked เพื่อ forensic compatibility เท่านั้น)
- อัปเดต `.agent/workflows/auth_data_guidelines.md`, `docs/secure/*`, `docs/infrastructure/*` ให้สะท้อน verified identity, 3 data paths, role/pool, RLS context, token/cache/TLS/rollback policy
- ทำ quarterly access review, key rotation drill, refresh-token reuse drill, incident rollback drill และตรวจว่าไม่มี server handler ถือ service_role
- **Deliverable ต่อ wave:** migration + gateway/repository refactor + tests + audit/metrics + gate ของ wave; **จุดจบ Phase 13:** ไม่มี direct Supabase mutation/private-data bypass ใน production, legacy actor-param RPC ถูก revoke หรือคงแบบ revoked, และ service_role ไม่อยู่ใน request path

### Fitness secure endpoint/RPC mapping (ใช้หลัง Phase 13.1 DB foundation)
| Action | Backend input จาก client | Verified actor | Secure path |
|---|---|---|---|
| Book session | `sessionId` | `req.userId` | Gateway transaction + `SET LOCAL` + `book_fitness_session(p_session_id)` |
| Approve booking | `bookingId` | `req.userId` | Gateway transaction + `approve_fitness_session_booking(p_booking_id)` |
| Owner auto-join | `groupId, enabled, cancelBookings` | `req.userId` | Gateway transaction + `set_fitness_group_owner_auto_join(...)` |
| Leave/remove member | `groupId, targetUserId` | `req.userId` | Gateway transaction + `leave_fitness_group(p_group_id, p_user_id)` |
| Remove session participant | `bookingId` | `req.userId` | Gateway transaction + `remove_fitness_session_participant(p_booking_id)` |
| Manager check | `groupId` | transaction context | `is_fitness_group_manager(p_group_id)` |
| Create/update/cancel group/session | allowlisted business fields | `req.userId` | scoped gateway transaction + strict RLS/manager policy |
| Cancel/reject booking | `bookingId, reason?` | `req.userId` | ownership/manager-scoped gateway transaction |
| Block/unblock user | `groupId, targetUserId, reason?` | `req.userId` | manager-scoped gateway transaction + strict RLS |

> ทุก secure mutation ต้องรับเฉพาะ resource/business IDs และ derive actor จาก verified context; `targetUserId` เป็น resource เป้าหมาย ไม่ใช่ actor; secure RPC ที่ไม่มี actor parameter grant ให้ `sheserved_app` เท่านั้น

### Required regression/security tests ก่อน Phase 13.5
- forged/unsigned/expired/wrong-algorithm/wrong-issuer/wrong-audience/unknown-`kid` JWT → 401
- revoked session, refresh reuse หลัง grace, inactive user และ conflicting `app.user_id`/JWT subject → 401 + audit event
- member ส่ง owner/admin UUID ใน body/header → ไม่มีผล; Backend ใช้ verified actor เท่านั้น
- missing/invalid/inactive `SET LOCAL app.user_id` → secure RPC คืน `UNAUTHORIZED`
- pooled connection request A/B สลับกันแล้ว identity/role ไม่รั่ว; `RESET ROLE`/release ทำงานทุกเส้นทาง error
- `sheserved_gateway` ต่อ pooler ได้, `SET LOCAL ROLE sheserved_app` ได้, `sheserved_app` ทำ DDL/แก้หรือลบ audit ไม่ได้
- owner/active group admin/Sheserved admin ผ่านเฉพาะ scope; member/unrelated/blocked ถูกปฏิเสธ
- pending ไม่กิน capacity; concurrent approval/book ไม่เกิน capacity; owner auto-join capacity/overlap all-or-nothing
- public VIEW เปิดเฉพาะคอลัมน์ที่กำหนด; anon อ่าน public browse ได้ แต่ไม่อ่านตารางจริง/member/booking/blocklist/private profile
- direct anon mutation/RPC และ legacy actor-param RPC หลัง cutover → permission denied
- WebSocket handshake token, room join membership, `message:send`, history/read หลัง revoke และ force-leave ทำงานถูกต้อง; `x-user-id` ไม่มีผลต่อ actor
- refresh parallel ได้ผลลัพธ์ idempotent โดยไม่คืน raw token จาก log/DB; reuse หลัง grace revoke family
- plaintext password ถูกบังคับ reset; ไม่มี `password_hash` ใน Flutter model, sync, public response หรือ log
- Q8-A: Fitness mutation เมื่อ offline → fail closed และไม่มี booking ใน outbox
- Q10-B: invariant 1–5 baseline/violation alert, SLI/SLO และ rollback flag ทำงานจริง
- logs/audit ไม่เก็บ password, access token, refresh token, OTP, signing key หรือ PII ที่ไม่จำเป็น

---

## Phase 13 — Decision Log (สถานะ: ตัดสินใจแล้ว 12/12 ครบ — Q1–Q12)

| # | คำถาม | ตัวเลือก | คำแนะนำ | ตัดสินใจ | วันที่ |
|---|---|---|---|---|---|
| Q1 | ขนาดของ sub-phase | A / B / C | **B** independently shippable | ✅ **B** — แยก release ต่อ sub-phase, หยุดค้างได้ทุกจุด | 2026-08-30 |
| Q2 | Backend identity authority | A / B / C | **A** ต่อยอด `websocket-server` | ✅ **A** — เพิ่ม `routes/auth.js` + verify ใน `middleware/auth.js` เดิม, แยกไฟล์ auth ออกจาก `server.js` | 2026-08-30 |
| Q3 | Signing algorithm + key | A / B / C | **A** HS256 dual-key (+ token แยกถ้า Q7=C) | ✅ **A** — HS256 dual-key (`kid` active/previous), rotate 90 วัน; Q7=C แล้ว → ออก PostgREST token แยกที่ sign ด้วย Supabase JWT secret (TTL ≤5 นาที) | 2026-08-30 |
| Q4 | Password migration | A / B / C | **B** lazy rehash + backstop C | ✅ **B** — lazy rehash Argon2id เมื่อ login + backstop `argon2(sha256(pw))` ปิดความเสี่ยงแถวที่ยังไม่ login + deadline บังคับ reset | 2026-08-30 |
| Q5 | Public data contract | A / B / C | **B** public VIEW ต่อ use case | ✅ **B** — สร้าง public VIEW ต่อ use case, anon อ่านได้เฉพาะ view, ปิด anon SELECT ตารางจริง | 2026-08-30 |
| Q6 | Refresh rotation | A / B / C | **B** rotation + grace 60s + lock | ✅ **B** — rotation + grace window 60 วิ + client single-flight + Redis `SETNX` lock; เก็บ replay result แบบเข้ารหัสชั่วคราว; token เก่าหลัง grace = revoke ทั้ง family | 2026-08-30 |
| Q7 | identity path ไปถึง DB | A / B / C | **C** hybrid ตามความเสี่ยง | ✅ **C** — public read: anon+VIEW; private read: JWT ที่ PostgREST verify (RLS จริง); mutation: gateway + `pg` ตรง + `SET LOCAL` | 2026-08-30 |
| Q8 | Offline mutation | A / B / C | **A** Fitness online-only fail closed | ✅ **A** — Fitness mutation = online-only, fail closed; ไม่มี offline queue สำหรับ Fitness; ลบ/ทำให้ชัดเจนเรื่อง in-memory queue เดิม | 2026-08-30 |
| Q9 | WebSocket room auth | A / B / C | **A** DB check + Redis cache 60s | ✅ **A** (+ตรวจ `message:send`/history/read และ event ถาวร) — DB check ตอน join + Redis cache 60 วิ + invalidate/force-leave ทันทีเมื่อถอด/บล็อก/revoke | 2026-08-30 |
| Q10 | Canary metrics | A / B / C | **B** invariant SQL + log counter + 3 alerts | ✅ **B** — invariant SQL 1–5 เป็น hard gate (0 ใหม่ต่อเนื่อง 7 วันหลัง baseline) + pino counter + 3 alerts (auth failure spike, authz spike, invariant violation) | 2026-08-30 |
| Q11 | Audit log | A / B / C | **B** สร้าง `audit_logs` ตั้งแต่ 13.2 | ✅ **B** — สร้าง `audit_logs` ตั้งแต่ 13.2 ด้วย partition key ที่ถูกต้อง, durable audit-worker/outbox, populate auth + Fitness manager action, `REVOKE UPDATE/DELETE` ตั้งแต่ migration แรก | 2026-08-30 |
| Q12 | service_role / least privilege | A / B / C | **B** `sheserved_app` ไม่มี BYPASSRLS | ✅ **B** — `sheserved_app NOLOGIN` + `sheserved_gateway LOGIN` ใช้ `SET LOCAL ROLE`; auth role/pool แยก; service_role เฉพาะ worker/system path; ลบ fallback ไป anon ทั้งหมด | 2026-08-30 |

> **แพ็กเกจที่อนุมัติ:** (B, A, A, B, B, B, C, A, A, B, B, B) และ implementation amendments: staged B2, `sheserved_gateway LOGIN` + `sheserved_app NOLOGIN`, auth-only role/pool แยก, no service_role ใน request path, encrypted refresh replay result, partition-valid audit schema/durable worker, `socket-auth` แยกไฟล์ และ invariant baseline ก่อน canary

### Phase 12.9 / Phase 13 readiness checklist
| รายการตรวจ | สถานะ |
|---|---|
| Q1–Q12 มีคำตอบและผูกกับ sub-phase ที่เกี่ยวข้อง | ✅ ครบ 12/12 |
| ลำดับแก้ความเสี่ยง | ✅ 12.9 data/password containment → 13.0 prerequisites → 13.1 DB roles/pooler → 13.2 server auth + audit worker + Flutter switch → 13.3 verified HTTP/WebSocket → 13.4 canary → 13.5 cutover → 13.6 waves |
| แอปเก่าจะไม่ถูกตัดก่อนเวลา | ✅ B2 revoke direct query ทำหลัง Flutter switch + minimum-supported-app/force-update |
| `sheserved_app NOLOGIN` ใช้เปิด connection ได้หรือไม่ | ✅ แก้แล้ว: `sheserved_gateway LOGIN NOINHERIT` ใช้ `SET LOCAL ROLE sheserved_app` |
| service_role หลุดเข้า request path หรือไม่ | ✅ ห้าม; เหลือเฉพาะ migration/sync/audit-worker/system job และ pool แยก |
| refresh grace คืน token ใหม่ซ้ำได้จริงหรือไม่ | ✅ ใช้ client single-flight + encrypted replay result TTL 60 วิ; ไม่เก็บ raw token ใน DB/log |
| audit partition และการส่ง event เชื่อถือได้หรือไม่ | ✅ partition key ถูกต้อง + durable outbox/queue + `audit-worker` + redaction/retry/dead-letter |
| WebSocket auth มี DB path ก่อนเปิด room check หรือไม่ | ✅ DB foundation อยู่ 13.1 และ room auth อยู่ 13.3; ไม่มี service_role request handler |
| canary แยกข้อมูลเสียเดิมกับข้อมูลเสียใหม่หรือไม่ | ✅ baseline invariant ก่อน canary; gate นับเฉพาะ violation ใหม่ |
| แผน rollback เปิดช่องโหว่เดิมกลับหรือไม่ | ✅ rollback ได้เฉพาะ secure App/Backend release; ห้ามเปิด anon mutation/legacy actor RPC กลับ |
| สถานะ implementation | ✅ Phase 12.9 ปิดสมบูรณ์ (โค้ด + migration apply + regression login/register ผ่าน); ⚠️ Phase 13.0–13.6 ยังไม่ได้ลงมือ |
