# คู่มือวิเคราะห์ระบบอาชีพ: Built-in vs Custom Professions

> เอกสารสรุปการวิเคราะห์ความเสี่ยงและแนวทางการเปลี่ยนจาก Built-in Professions (hardcode UUID) ไปใช้ Custom Professions ทั้งระบบ พร้อมคำแนะนำระยะยาว

---

## 1. ภาพรวมระบบปัจจุบัน

### Built-in Professions (กำหนดในโค้ด)

ระบบปัจจุบันใช้ UUID คงที่ (hardcode) สำหรับอาชีพหลัก กำหนดไว้ใน `lib/features/admin/models/profession.dart:238-258`:

| อาชีพ | UUID | `profession_code` | `category` | `can_manage_drug_risk` |
|---|---|---|---|---|
| ผู้ซื้อ/ผู้รับบริการ | `00000000-...-000001` | `consumer` | consumer | false |
| ผู้เชี่ยวชาญ/ผู้ขาย | `00000000-...-000002` | `expert` | provider | **true** |
| คลินิก/ศูนย์ | `00000000-...-000003` | `clinic` | provider | **true** |
| แพทย์ทั่วไป | `00000000-...-000101` | `doctor_gp` | provider | false |
| แพทย์เฉพาะทาง | `00000000-...-000103` | `doctor_specialist` | provider | false |
| เภสัชกร | `00000000-...-000105` | `pharmacist` | provider | false |
| อาจารย์แพทย์ | `00000000-...-000107` | `professor` | provider | false |
| ผู้นำชุมชน | `00000000-...-000004` | (ไม่กำหนด) | leader | - |
| ผู้ดูแลระบบ | `00000000-...-000999` | (ไม่กำหนด) | admin | - |

**คุณสมบัติของ Built-in:**
- มี UUID รูปแบบ `00000000-0000-0000-0000-000000000XXX` (คงที่)
- ถูก hardcode ใน `Profession` class เป็น `static const`
- มี trigger ใน SQL ป้องกันการลบ built-in `00000000-...-000001` ถึง `00000000-...-000004` (`20260609110000_fix_default_consumer_profession.sql:40-64`)
- มี field config ครบถ้วนในตอน seed ข้อมูล
- ใช้ในการตรวจสอบสิทธิ์ต่าง ๆ ในโค้ดทั้งระบบ

**ความหมายของ `can_manage_drug_risk` ในแผนนี้:**
- เป็น permission โดยตรงสำหรับการเข้าถึง UI จัดการหมวดหมู่ความเสี่ยงยา ไม่ใช่เพียง metadata ของอาชีพ
- เมื่อเป็น `true` ผู้ใช้ non-admin จะเข้า Organization Override mode และสามารถสร้าง/แก้ไข Drug Risk Override ผ่าน UI ตาม scope ที่ระบบรองรับ
- การบันทึกจริงต้องเกิดในตาราง `drug_risk_overrides` และ `drug_risk_override_history` ผ่าน repository/RPC ที่เกี่ยวข้อง
- ค่าใน `professions.can_manage_drug_risk` จาก DB เป็น source of truth สำหรับ runtime; ห้ามอนุมานสิทธิ์จากชื่ออาชีพ, `profession_code` หรือ hardcoded UUID เพียงอย่างเดียว
- การมี flag เป็น `true` ไม่ได้แปลว่าผู้ใช้เป็นเจ้าขององค์กรโดยอัตโนมัติ การแยก organization membership เป็นงานระยะกลางตามแผน

**ข้อเท็จจริงที่พบ:**
- `00000000-...-000004` (ผู้นำชุมชน) ถูก seed ใน DB และมี trigger ป้องกันการลบ แต่ **ไม่มี constant** ใน `lib/features/admin/models/profession.dart` นี่เป็น inconsistency ที่ควรแก้ไขระยะยาว

### Custom Professions (สร้างโดยผู้ใช้/ระบบ)

- มี UUID แบบสุ่ม เช่น `0a8e7857-f5ad-4eef-9eea-0abeef39901d`
- `profession_code = 'custom_profession'`
- `is_built_in = false`
- ไม่มีในค่าคงที่ของ `Profession` class
- **ไม่ถูกตรวจในเงื่อนไขใด ๆ ในโค้ด** → ระบบต่าง ๆ ไม่รู้จัก

---

## 2. จุดที่ใช้ Built-in Profession ID ในโค้ด (15 ไฟล์)

### กลุ่ม A: ตรวจสอบสิทธิ์/โหมดระบบ (Critical — กระทบ UX โดยตรง)

| ไฟล์ | การใช้งาน | ผลกระทบถ้าใช้ Custom |
|---|---|---|
| `drug_risk_classification_admin_page.dart:53-54` | เช็ค `clinicProfessionId`/`expertProfessionId` → Organization mode | Custom จะใช้ Personal mode เสมอ แม้เป็น owner ขององค์กร |
| `user_model.dart:274` | `_computeIsConsultationProvider` fallback เช็ค `!= '00000000-...-000001'` | Custom ที่ไม่ใช่ consumer จะถูกมองเป็น consultation provider (ถูกต้อง) |
| `home_page.dart:584` | เช็ค `== consumerProfessionId` → skip การโหลด consultation | Custom จะไม่ skip → โหลด consultation (ไม่มีปัญหาถ้าเป็น provider) |
| `chat_room_page.dart:60` | เช็ค `!= consumerProfessionId` → `_isProvider` | Custom ที่ไม่ใช่ consumer จะถูกมองเป็น provider (ถูกต้อง) |
| `chart_board_page.dart:173` | เช็ค `!= consumerProfessionId` → `_isProvider` | เช่นเดียวกัน (ถูกต้อง) |
| `health_program_request_dashboard.dart:140` | เช็ค `!= consumerProfessionId` → `_isProvider` | เช่นเดียวกัน (ถูกต้อง) |
| `profile_page.dart:337,608` | เช็ค `== consumerProfessionId` → `isConsumer` | Custom ที่ไม่ใช่ consumer จะถูกมองเป็น provider (ถูกต้อง) |
| `health_article_repository.dart:392-398` | เช็ค consumer/expert/clinic → แยกหมวดผู้แท็ก | Custom จะถูกมองเป็น 'other' (ไม่กระทบฟังก์ชันหลัก) |

### กลุ่ม B: ฟอร์มสมัคร/Field Config (Medium — กระทบการสมัคร)

| ไฟล์ | การใช้งาน | ผลกระทบถ้าใช้ Custom |
|---|---|---|
| `register_wizard_page.dart:115,179,212,275` | ใช้ built-in UUID ใน switch case สำหรับ default fields | Custom จะไม่มี default fields → ฟอร์มว่าง |
| `registration_field_admin_page.dart:57,93,140` | เช่นเดียวกัน | เช่นเดียวกัน |
| `profile_page.dart:1602-1603` | เช็ค `== clinic/expert` → แสดงตัวเลือก owner request | Custom จะไม่เห็นตัวเลือก owner request |

### กลุ่ม C: Consultation/Package (Medium — กระทบการปรึกษา)

| ไฟล์ | การใช้งาน | ผลกระทบถ้าใช้ Custom |
|---|---|---|
| `consultation_package.dart:7` | แปลง role string → `doctorGpProfessionId` | Custom ที่ไม่ตรง role string จะไม่ถูก map |
| `chart_board_page.dart:633` | เช็ค `doctorGpProfessionId`/`doctorFamilyProfessionId` | Custom จะไม่ตรงเงื่อนไข |
| `package_admin_page.dart:115,160` | ใช้ `doctorGpProfessionId` เป็น role ใน expert group | Custom จะไม่ถูกเพิ่มเป็น expert group ได้ |

### กลุ่ม D: Backend/Database (Low — กระทบเฉพาะเมื่อ approve/reject)

| ไฟล์ | การใช้งาน | ผลกระทบถ้าใช้ Custom |
|---|---|---|
| `server.js:1958` | ใช้ consumer UUID hardcoded สำหรับ reject reset | ไม่มีปัญหา (เป็น fallback เดียวกัน) |
| `unified_repository.dart:429` | เช่นเดียวกัน | เช่นเดียวกัน |
| SQL migrations (11 ไฟล์) | Seed data, trigger ป้องกันการลบ built-in | ไม่กระทบ custom (trigger เช็คเฉพาะ built-in) |

---

## 3. ปัจจัยเสี่ยงของการใช้ Built-in Professions

### ความเสี่ยงที่มีอยู่ในปัจจุบัน

1. **Hardcode coupling:** ถ้า UUID ของ built-in profession เปลี่ยน ต้องแก้โค้ดทุกที่ → ไม่ยืดหยุ่น
2. **ไม่รองรับอาชีพใหม่:** ถ้าต้องการเพิ่มอาชีพใหม่ที่มีสิทธิ์จัด Drug Risk ต้องแก้โค้ดเพิ่มเติม
3. **ความขัดแย้งกับ Custom Profession:** ผู้ใช้ที่สร้าง custom profession จะไม่ได้รับสิทธิ์เดียวกับ built-in แม้มีคุณสมบัติเท่ากัน
4. **การขยายตัวถูกจำกัด:** แพลตฟอร์มไม่สามารถรองรับอาชีพแบบไดนามิกได้อย่างเต็มที่
5. **ความเสี่ยงด้านความปลอดภัย:** การอ้างอิง UUID แบบ hardcode หมายความว่าถ้ามีการแก้ไขข้อมูลใน DB โดยตรง (เช่น เปลี่ยน UUID ของ built-in profession) ระบบจะทำงานผิดพลาดโดยไม่มี error ชัดเจน

---

## 4. ข้อเท็จจริงสำคัญ: Backend รองรับ Custom Profession อยู่แล้ว

การวิเคราะห์ SQL migrations พบว่า backend ตรวจสอบสิทธิ์ Drug Risk ผ่าน flag `can_manage_drug_risk` แล้ว:

- ใน `supabase/migrations/20260614120000_add_drug_risk_classification.sql` มีการเพิ่ม column `can_manage_drug_risk` ให้ `professions`
- ใน `supabase/migrations/20260708160000_add_drug_risk_overrides.sql` function `resolve_drug_risk_effective_modifier` และ `get_drug_risk_override_modifier` ใช้เงื่อนไข `p.can_manage_drug_risk = true` เพื่อตรวจสอบว่า user มีสิทธิ์เป็น modifier หรือไม่

**ผลที่ได้:**
- Backend สามารถรองรับ Custom Profession ได้โดยอัตโนมัติ ถ้า profession นั้นมี `can_manage_drug_risk = true`
- ปัญหาที่แท้จริงไม่ใช่ "ระบบไม่รองรับ custom profession" แต่เป็น **frontend `_pageMode` ไม่สอดคล้องกับ backend**
- การใช้ `can_manage_drug_risk` ใน frontend จึงไม่ใช่ workaround แต่เป็นการ **ทำให้ logic สอดคล้องกันระหว่าง frontend กับ backend**

---

## 5. ผลเสียถ้าเปลี่ยนเป็น Custom Professions ทั้งระบบ

### ผลเสียต่อระบบ Drug Risk Management
- **Custom profession จะใช้ Personal Override mode เสมอ** แม้ผู้ใช้เป็นเจ้าขององค์กร → ไม่สามารถตั้งค่า Override ระดับองค์กรได้
- สิทธิ์การจัดการความเสี่ยงยาถูกจำกัดเฉพาะ built-in clinic/expert เท่านั้น
- การทดสอบ Maestro Scenario 2 (Organization Override) จะ fail เสมอ หากใช้ custom profession

### ผลเสียต่อระบบสมัครอาชีพ (Registration)
- **Custom profession จะไม่มี default field config** → ฟอร์มสมัครจะว่างเปล่า ไม่มีฟิลด์ให้กรอก
- ผู้ใช้ custom profession จะไม่เห็นตัวเลือก "ขอเป็นเจ้าขององค์กร" (owner request) ในหน้าโปรไฟล์
- แอดมินต้องสร้าง field config เองสำหรับทุก custom profession ที่เพิ่มเข้ามา

### ผลเสียต่อระบบปรึกษาแพทย์ (Consultation)
- **Custom profession จะไม่ถูก map ใน expert groups** → ไม่สามารถเป็นผู้ให้บริการในแพ็คเกจปรึกษาได้
- การตรวจจับ role (แพทย์ทั่วไป, แพทย์เฉพาะทาง, เภสัชกร) จะไม่ทำงานสำหรับ custom profession
- สิทธิ์การเข้าถึง Chart Board อาจไม่ถูกต้อง

### ผลเสียต่อระบบ ERP/HR
- การคำนวณ KPI ที่อ้างอิง `employees.profession_id` อาจไม่ทำงานถ้า profession ไม่ตรงกับที่คาดไว้
- การจัดการพนักงานในหน้า Admin อาจไม่แสดง custom profession อย่างถูกต้อง

### ผลเสียต่อระบบ Accounting
- Chart of Accounts template ที่ผูกกับ `clinicProfessionId` (`...000003`) จะไม่ทำงานสำหรับ custom profession
- การสร้าง COA อัตโนมัติสำหรับอาชีพใหม่จะไม่มี template ให้ใช้

### ผลเสียต่อความปลอดภัย
- ถ้าใช้ `profession_code` แทน UUID และไม่มี validation ผู้ใช้สามารถสร้าง custom profession ที่มี code ตรงกับ built-in ได้ → **สิทธิ์รั่ว**
- ไม่มี trigger ป้องกันการลบ custom profession (เฉพาะ built-in มี trigger)
- การตรวจสอบสิทธิ์ใน RLS policy อาจไม่ครอบคลุม custom profession

---

## 6. แนวทางแก้ไข 4 ทาง เรียงตามข้อดี (มาก → น้อย)

### แนวทาง 1: ใช้ flag `can_manage_drug_risk` (แนะนำอันดับ 1)

**หลักการ:** แทนที่จะเช็ค UUID ในโค้ด ให้ใช้ flag `can_manage_drug_risk` ในตาราง `professions` (มีอยู่แล้วใน DB ตั้งแต่ migration `20260614120000`)

**วิธีการ:**
- ใน `drug_risk_classification_admin_page.dart` โหลด `Profession` ของผู้ใช้ปัจจุบันจาก `ProfessionRepository.getProfessionById()` ก่อนโหลดข้อมูล Drug Risk
- กำหนด Organization mode เมื่อ `_currentUserProfession?.canManageDrugRisk == true`
- Admin ตั้งค่า `can_manage_drug_risk` ได้จาก toggle ที่มีอยู่แล้วใน `ProfessionEditorDialog` ของ `profession_admin_page.dart`

**ข้อดี:**
- ✅ รองรับ Custom Professions ทุกแบบ — admin ตั้งค่า flag ได้จาก UI
- ✅ **Backend รองรับอยู่แล้ว**: SQL functions ตรวจ `can_manage_drug_risk` เพื่อยอมรับ modifier
- ✅ ใช้ flag ที่มีอยู่แล้วใน DB (ไม่ต้องเพิ่ม column)
- ✅ ไม่ต้องแก้ SQL migrations
- ✅ ยืดหยุ่นสูงสุด — ไม่ต้องแก้โค้ดเมื่อเพิ่มอาชีพใหม่
- ✅ Admin ควบคุมสิทธิ์ได้จาก UI โดยตรง
- ✅ แก้ไขน้อยที่สุด (1 ไฟล์หลัก)

**ข้อเสียและข้อควรระวัง:**
- การโหลด profession เป็น async ถ้าเรียก `_loadAllData()` ก่อนโหลดเสร็จ หน้าอาจเลือก mode ผิดและใช้ query ผิด scope
- ถ้าโหลดไม่สำเร็จ ต้อง fallback เป็น Personal mode เพื่อป้องกันการเปิดสิทธิ์เกินจริง แต่ผู้ใช้อาจเข้าใจว่าไม่มีสิทธิ์
- `can_manage_drug_risk` เป็น capability ไม่ใช่หลักฐานว่าเป็นองค์กร — อาชีพ freelance ที่เปิด flag จะถูกเข้า Organization mode
- ต้อง invalidate/refresh session state หลัง Admin เปลี่ยน flag ไม่เช่นนั้นผู้ใช้ที่เปิดแอปค้างจะเห็นสิทธิ์เดิม

**ไฟล์ที่แก้แล้ว:** `drug_risk_classification_admin_page.dart`

**ไฟล์ที่มีความสามารถอยู่แล้ว:** `profession.dart`, `profession_repository.dart`, `profession_admin_page.dart`, `tlz_drawer.dart`

---

### แนวทาง 2: ใช้ `employees` table + `professions.category` (แนะนำอันดับ 2)

**หลักการ:** ตรวจสอบว่า user เป็นสมาชิกขององค์กร (มี record ใน `employees` table ที่ `is_active = true`) และ profession ขององค์กรนั้นมี `category = 'provider'`

**วิธีการ:**
- โหลดข้อมูล `employees` ของ user ใน `initState`
- ถ้ามี active employee record → Organization mode
- ใช้ `employees.profession_id` เป็น context ขององค์กร

**ข้อดี:**
- ✅ รองรับกรณี user เป็น employee ของหลายองค์กร (เลือก context ได้)
- ✅ แยก "เป็นสมาชิกองค์กร" กับ "มีสิทธิ์จัด Drug Risk" ออกจากกัน
- ✅ สอดคล้องกับ ERP/HR system ที่มีอยู่ (`employees` table)
- ✅ ใช้ `UserCategory.providerId` / `isConsultationProvider` ที่มีอยู่แล้ว
- ✅ กรณี `apisek` จากข้อมูลก่อนหน้า มี record ใน `employees` table (`is_active: true`) → ควรใช้ได้ทันทีหากข้อมูลเป็นจริง

**ข้อเสีย:**
- ต้อง query `employees` table เพิ่ม (async)
- อาจกระทบ performance ถ้า user เป็นสมาชิกหลายองค์กร
- ซับซ้อนกว่าแนวทาง 1
- ต้องเชื่อมกับ `can_manage_drug_risk` เพื่อตรวจสอบสิทธิ์จัดการ Drug Risk ด้วย
- ต้องตรวจสอบข้อมูลจริงก่อน implement เพราะ local DB ไม่มี `employees` table ใน environment ที่ตรวจสอบ

**ไฟล์ที่ต้องแก้:** `drug_risk_classification_admin_page.dart` + อาจต้องเพิ่ม query helper

---

### แนวทาง 3: ใช้ `profession_code` แทน UUID (แนะนำอันดับ 3)

**หลักการ:** แทนที่จะเช็ค UUID ให้เช็ค `profession_code` เช่น `clinic` / `expert` / `doctor_gp`

**วิธีการ:**
- เปลี่ยน `user.professionId == Profession.clinicProfessionId` → `profession.professionCode == 'clinic'`
- ต้องโหลด `Profession` object จาก DB เพื่อเข้าถึง `professionCode`

**ข้อดี:**
- ✅ รองรับ custom profession ที่มี code ตรงกับ built-in
- ✅ อ่านง่ายกว่า UUID (`'clinic'` vs `'00000000-...-000003'`)
- ✅ สามารถเพิ่ม code ใหม่ได้โดยไม่ต้องแก้โค้ด (ถ้าเช็คแบบ list)

**ข้อเสีย:**
- ⚠️ **ความเสี่ยงด้านความปลอดภัย:** ถ้า admin สร้าง custom profession ด้วย code ซ้ำกับ built-in → สิทธิ์รั่ว (ต้องเพิ่ม validation ในหน้า Admin)
- ต้องโหลด `Profession` data จาก DB (async)
- ไม่ยืดหยุ่นเท่า flag-based (แนวทาง 1) — ถ้าต้องการเพิ่ม code ใหม่ต้องแก้โค้ด
- DB มี partial unique index บน `profession_code` แล้ว (`idx_professions_profession_code_unique`) แต่ต้องเพิ่ม validation ใน UI ด้วย

**ไฟล์ที่ต้องแก้:** `drug_risk_classification_admin_page.dart` + validation ใน `profession_admin_page.dart` + SQL constraint

---

### แนวทาง 4: เพิ่ม flag `is_organization` ในตาราง `professions` (แนะนำอันดับ 4)

**หลักการ:** เพิ่ม column `is_organization BOOLEAN DEFAULT false` ในตาราง `professions` และใช้ flag นี้ในการตรวจสอบ

**วิธีการ:**
- SQL migration: `ALTER TABLE professions ADD COLUMN is_organization BOOLEAN DEFAULT false;`
- Update built-in: `UPDATE professions SET is_organization = true WHERE id IN (...002, ...003);`
- ใน `_pageMode`: เช็ค `profession.isOrganization == true`

**ข้อดี:**
- ✅ ชัดเจน แยก "เป็นองค์กร" กับ "จัด Drug Risk ได้" ออกจากกัน
- ✅ Admin ตั้งค่าได้จาก UI
- ✅ ไม่มีปัญหาความปลอดภัยเรื่อง code ซ้ำ

**ข้อเสีย:**
- ต้องเพิ่ม column ใหม่ใน DB (migration)
- ต้องแก้ `Profession` model + `fromJson` + `toJson`
- ต้องแก้หน้า Admin UI เพื่อตั้งค่า flag
- มี flag ซ้อนกับ `can_manage_drug_risk` อาจสับสน

**ไฟล์ที่ต้องแก้:** SQL migration + `profession.dart` model + `profession_admin_page.dart` + `drug_risk_classification_admin_page.dart`

---

## 7. ตารางเปรียบเทียบ 4 แนวทาง

| เกณฑ์ | แนวทาง 1 (flag) | แนวทาง 2 (employees) | แนวทาง 3 (code) | แนวทาง 4 (is_org) |
|---|---|---|---|---|
| **รองรับ Custom Profession** | ✅ ทุกแบบ | ✅ ทุกแบบ | ⚠️ ต้องมี code ตรง | ✅ ทุกแบบ |
| **ไฟล์ที่ต้องแก้** | 1 ไฟล์ | 1-2 ไฟล์ | 2-3 ไฟล์ | 4 ไฟล์ |
| **ต้องแก้ DB schema** | ไม่ | ไม่ | เพิ่ม constraint | เพิ่ม column |
| **ยืดหยุ่น** | สูงสุด | สูง | ปานกลาง | สูง |
| **ความปลอดภัย** | ปลอดภัย | ปลอดภัย | ⚠️ รั่วถ้า code ซ้ำ | ปลอดภัย |
| **Performance** | ดี (1 query) | ปานกลาง (2 queries) | ดี (1 query) | ดี (1 query) |
| **Backend สนับสนุนอยู่แล้ว** | ✅ ใช้ `can_manage_drug_risk` | ⚠️ ต้องเพิ่ม query เอง | ❌ ไม่ | ❌ ไม่ |
| **ความซับซ้อน** | ต่ำ | ปานกลาง | ปานกลาง | สูง |

---

## 8. คำแนะนำสำหรับจุดอื่น ๆ ที่ใช้ Built-in UUID

| กลุ่ม | แนะนำ | วิธี |
|---|---|---|
| **A (isProvider/isConsumer)** | ใช้ `profession.category` | มีอยู่แล้วใน `UserCategory` model (`consumerId`/`providerId`) |
| **B (field config)** | สร้าง default field config สำหรับ custom profession | เพิ่มในหน้า Admin ให้สร้าง field config ได้ |
| **C (consultation)** | ใช้ `profession.category.isConsultationProvider` | มีอยู่แล้วใน `UserCategory` model |
| **D (backend)** | ไม่ต้องแก้ | consumer UUID เป็น fallback ที่ถูกต้องสำหรับ reject |

---

## 9. แผนการ Implement และตรวจรับ

### ขั้นตอนที่ 1: Frontend mode resolution — เสร็จแล้ว
- `drug_risk_classification_admin_page.dart` โหลด `Profession` ของผู้ใช้ก่อนเรียก `_loadAllData()`
- Admin ยังคงเข้า `globalAdmin` ก่อนตรวจ profession
- ผู้ใช้ non-admin ที่ `can_manage_drug_risk = true` เข้า `organizationOverride`
- ถ้า profession หายหรือ query ล้มเหลว ใช้ `personalOverride` เป็น secure fallback

### ขั้นตอนที่ 2: ตั้งค่า capability สำหรับ custom profession — เสร็จแล้ว
- ตรวจสอบ DB จริงเมื่อ 2026-07-12 แล้ว พบว่า:
  - `apisek` ใช้ profession `0a8e7857-...` (แพทย์ทั่วไป) ซึ่งมี `can_manage_drug_risk = true` อยู่แล้ว
  - `เภสัชกร` (custom, `191e414a-...`) มี flag `true` อยู่แล้ว
  - `อาจารย์แพทย์` (`5d81c5ac-...`, is_built_in=true) มี flag `true` อยู่แล้ว
- **พบ bug:** Consumer (`...-000001`) มี `can_manage_drug_risk = true` ใน DB ทั้งที่ไม่ควร — แก้ใน migration `20260712190000`
- Migration `20260712190000_set_can_manage_drug_risk_for_custom_professions.sql` แก้ consumer เป็น `false` และยืนยัน expert/clinic เป็น `true`
- ห้ามใช้ `employees` เพียงอย่างเดียวในการเปิด flag เพราะ employee ไม่ได้แปลว่ามีสิทธิ์จัดการ Drug Risk

### ขั้นตอนที่ 3: ตรวจสอบ Admin UI — มีอยู่แล้ว
- `profession_admin_page.dart` มี toggle `จัดการหมวดหมู่ความเสี่ยงยา`
- `ProfessionRepository.createProfession()` และ `updateProfession()` ส่งค่า `can_manage_drug_risk` แล้ว
- ไม่ต้องสร้าง toggle ใหม่ แต่ควรจำกัดการแก้ flag ให้เฉพาะ admin ตาม RLS/authorization

### ขั้นตอนที่ 4: ทดสอบ functional และ security
- ผู้ใช้ admin ต้องเห็น global mode และ 4 tabs
- custom profession ที่ flag เป็น `true` ต้องเห็น Organization mode และ 2 tabs
- custom profession ที่ flag เป็น `false` ต้องเห็น Personal mode
- query/load profession ล้มเหลวต้องไม่เปิด Organization mode
- ตรวจสอบว่า override ใช้ `profession_id` ของผู้ใช้ใน Organization mode
- ตรวจสอบว่า backend ปฏิเสธ modifier ที่ profession flag เป็น `false`
- ทดสอบเปลี่ยน flag จาก true เป็น false แล้วเปิดหน้าใหม่/refresh session
- รัน Maestro test `scenario_02_organization_override.yaml`

### ขั้นตอนที่ 5: แผนระยะกลางสำหรับ scope องค์กร
- ถ้าธุรกิจต้องการแยก freelance กับ organization ให้เพิ่มการตรวจ active organization membership/owner ร่วมกับ flag
- ห้ามใช้ `can_manage_drug_risk` เพียงตัวเดียวเป็นหลักฐานว่าเป็นองค์กร
- รองรับหลายองค์กรด้วยการเลือก active organization context ก่อนส่ง `profession_id`
- ต้องย้าย authorization หลักไป backend/RPC ไม่พึ่ง frontend mode เพียงอย่างเดียว

---

### ขั้นตอนที่ 6: ปรับปรุงระยะกลาง (แนวทาง 2 ร่วมกับแนวทาง 1)
- ใน `drug_risk_classification_admin_page.dart` เพิ่มการโหลด `employees` ของ user
- กำหนด Organization mode เมื่อ **ทั้ง** `can_manage_drug_risk = true` **และ** user มี active employee record
- ใช้ `employees.profession_id` เป็น context องค์กร
- สร้าง default field config สำหรับ custom profession ในหน้า Admin (`registration_field_admin_page.dart`)

### ขั้นตอนที่ 7: Data cleanup — เสร็จแล้ว (บางส่วน)
- ตรวจสอบ DB จริงเมื่อ 2026-07-12 แล้ว พบ professions ที่มี `can_manage_drug_risk = true` ได้แก่:
  - `...-000001` (Consumer) — **BUG: แก้เป็น false ใน migration 20260712190000**
  - `...-000002` (Expert/ร้านค้า) — correct
  - `...-000003` (Clinic/คลินิก) — correct
  - `0a8e7857-...` (แพทย์ทั่วไป, custom) — correct (apisek)
  - `191e414a-...` (เภสัชกร, custom) — correct
  - `5d81c5ac-...` (อาจารย์แพทย์, is_built_in=true) — correct
- Built-in UUIDs `...-000101` ถึง `...-000107` (แพทย์ทั่วไป/เฉพาะทาง/เภสัชกร/ทันตแพทย์ ฯลฯ) **ไม่มีใน DB** — แพทย์เหล่านี้สร้างเป็น custom professions แทน
- Dart `defaultProfessions` ยังมี UUID เหล่านี้เป็น fallback แต่ไม่มีผล runtime เพราะ frontend โหลดจาก DB
- **หมายเหตุ:** ไม่ควรกำหนดสิทธิ์ตาม `employees.profession_id` เพราะการเป็นพนักงานขององค์กรไม่ได้หมายความว่าอาชีพนั้นมีสิทธิ์จัดการ Drug Risk
- ตรวจสอบ RLS policies ที่อาจอ้างอิง built-in UUID (ยังไม่ได้ทำ — ระยะถัดไป)

---

## 10. Flow ทดสอบหลัง Implement แนวทาง 1

### 10.1 เตรียมข้อมูลทดสอบ

สร้างหรือเลือกข้อมูลทดสอบแยกกันอย่างน้อย 5 บัญชี/สถานะ:

| กลุ่ม | `profession_id` | `can_manage_drug_risk` | membership | ผลที่คาดหวัง |
|---|---|---:|---|---|
| Admin | ใดก็ได้ | ใดก็ได้ | ไม่เกี่ยวข้อง | Global Admin |
| Custom provider มีสิทธิ์ | custom A | true | ยังไม่ใช้เป็นเกณฑ์ในระยะสั้น | Organization mode ชั่วคราว |
| Custom provider ไม่มีสิทธิ์ | custom B | false | มี/ไม่มี | Personal mode และแก้ Org ไม่ได้ |
| สมาชิกองค์กรไม่มีสิทธิ์ | custom B | false | active | ใช้ค่า Org ได้ แต่แก้ไม่ได้ |
| ผู้ใช้ส่วนตัว | custom C/null | false | ไม่มี | Personal mode |

ก่อนทดสอบต้องบันทึกค่า baseline ของ `users.profession_id`, `professions.is_active` และ `professions.can_manage_drug_risk` ไว้ เพื่อ rollback ได้

### 10.2 ทดสอบการเลือก mode ของหน้า

1. **Admin**
   - เปิดหน้า Drug Risk
   - ต้องเห็น `globalAdmin` และ 4 tabs
   - ต้องเข้าถึง global configuration ได้

2. **Custom profession + flag true**
   - เปิดหน้าใหม่หลัง refresh session
   - ต้องเห็น Organization Override และ 2 tabs
   - ค้นหายา X
   - ต้องส่ง `profession_id` ของผู้ใช้เป็น organization scope

3. **Custom profession + flag false**
   - ต้องเห็น Personal Override
   - ต้องไม่แสดงหรือไม่อนุญาตการแก้ Organization Override
   - ต้องไม่ส่ง `profession_id` เป็น organization scope จาก UI

4. **Profession ไม่พบ / inactive / network error**
   - ต้อง fallback เป็น Personal mode
   - ต้องไม่เปิดสิทธิ์ Organization โดยอัตโนมัติ
   - UI ควรแสดง retry/error state ไม่ใช่รายงานว่างอย่างเงียบ ๆ

### 10.3 ทดสอบ CRUD และ scope isolation

ใช้ยา X เดียวกันและค่าความเสี่ยงที่เห็นชัดเจน:

1. User A สร้าง Personal Override
   - User A เห็นค่า Personal
   - User B ไม่เห็นค่า Personal ของ A
   - ค่า Organization เดิมต้องไม่ถูกเปลี่ยน

2. User A สร้าง Organization Override ของ profession A
   - สมาชิกที่อ่าน scope profession A เห็นค่า Organization
   - profession B ไม่เห็นค่า Organization ของ A
   - Personal Override ต้อง override ค่า Organization ตามลำดับที่ออกแบบไว้

3. User B ซึ่งมี flag false พยายามแก้ Organization Override
   - UI ต้องไม่แสดง action หรือแสดง error
   - Backend/RPC ต้องปฏิเสธด้วย authorization error
   - ต้องไม่มี row ใหม่และไม่มี history ใหม่

4. ทดสอบ update และ delete
   - update ต้องสร้าง history action `update`
   - delete ต้องสร้าง history action `delete`
   - หลัง delete ต้องกลับไปใช้ tier ก่อนหน้า
   - ตรวจ `changed_by`, `changed_by_name`, `profession_id`, `user_id` ให้ตรง scope

### 10.4 ทดสอบ business/legal rules

- Override ยา FDA `N` หรือ `P` ให้ `is_telemedicine_prohibited = false` ต้องถูกปฏิเสธ
- ยาที่ไม่มี override ต้องใช้ค่า platform default
- ผลลัพธ์ต้องแสดง badge และ `override_scope` ถูกต้อง
- Personal Override ต้องชนะ Organization Override
- การทำ prescription ต้องส่ง effective risk และ scope ถูกต้อง
- ทดสอบ delivery flags ว่า organization/personal scope ถูก serialize ถูกต้อง

### 10.5 ทดสอบ stale state และการเปลี่ยนสิทธิ์

1. เปิดหน้าใน User A ขณะที่ flag เป็น `true`
2. เปลี่ยน flag เป็น `false` จาก Admin
3. เปิดหน้าใหม่/refresh
4. ต้องเปลี่ยนเป็น Personal mode และแก้ Org ไม่ได้
5. ทดสอบ revoke `is_active` ของ profession/user เช่นเดียวกัน
6. ตรวจว่า override เดิมยังอ่านได้ตาม policy แต่ modifier banner เปลี่ยนเป็น fallback ที่ถูกต้อง

### 10.6 ตรวจสอบ backend และ RLS — ต้องทำก่อน Production

ข้อเท็จจริงจาก `20260708160000_add_drug_risk_overrides.sql`:

- `drug_risk_overrides` และ `drug_risk_override_history` เปิด RLS แต่ policy ปัจจุบันใช้ `USING (true)` สำหรับ SELECT และ `FOR ALL`
- migration ระบุว่าระบบใช้ custom `AuthService` และมอบ authorization ให้ Dart Repository
- `DrugRiskClassificationRepository.setOverride()` ทำ insert/update โดยตรง และไม่มี server-side capability check ใน method นี้

ดังนั้น **RLS ปัจจุบันยังไม่ใช่ authorization ที่ปลอดภัย** ผู้ที่เรียก Supabase ได้อาจอ่าน/แก้ข้อมูลโดยตรงได้ การทดสอบ UI ผ่านอย่างเดียวจึงยังไม่ถือว่าปลอดภัย

ตรวจสอบ policy/function ด้วย SQL read-only:

```sql
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename IN ('drug_risk_overrides', 'drug_risk_override_history');

SELECT n.nspname AS schema_name,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer,
       has_function_privilege(p.oid, 'EXECUTE') AS executable
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname IN ('resolve_effective_modifier', 'get_drug_risk_override_modifier');
```

ตรวจรับ backend/RLS ต้องครอบคลุม:

- anonymous/unauthorized client อ่าน override ไม่ได้
- user แก้ personal scope ของคนอื่นไม่ได้
- user ที่ไม่มี capability แก้ organization scope ไม่ได้
- user แก้ organization scope ของ profession อื่นไม่ได้
- user ปลอม `performedBy`, `performedByName` หรือ `profession_id` แล้วไม่ได้สิทธิ์เพิ่ม
- audit history ไม่สามารถแก้ย้อนหลังหรือลบโดยผู้ใช้ทั่วไปได้

### 10.7 แผนแก้ backend/RLS ที่แนะนำ

1. ย้ายการเขียน override ไป RPC หรือ backend endpoint ที่ตรวจสอบ `auth/user identity` ฝั่ง server
2. ห้ามรับ `performedBy` จาก client เป็นแหล่งความจริงหลัก ให้ derive จาก authenticated identity
3. ตรวจ `profession.can_manage_drug_risk = true` ใน server/RPC
4. ตรวจ `profession.is_active = true` และ user `is_active = true`
5. ตรวจ scope ว่า:
   - personal: identity ตรงกับ `user_id`
   - organization: user มี membership/owner role ของ organization context
6. จำกัด RLS จาก `USING (true)` เป็น policy ตาม authenticated identity หรือให้เฉพาะ RPC `SECURITY DEFINER` เขียนได้
7. เพิ่ม audit log สำหรับการเปลี่ยน capability และปฏิเสธ authorization

### 10.8 แผนแยก Organization Scope ออกจาก Capability

`can_manage_drug_risk` ควรตอบเฉพาะว่า **ทำอะไรได้** ส่วน organization membership ควรตอบว่า **ทำในนามใคร/องค์กรใด**

โมเดลระยะถัดไป:

```text
Capability:
  professions.can_manage_drug_risk = true

Scope:
  active organization context
  + organization membership/owner relation
  + membership status = active

Authorization:
  capability = true
  AND scope relation = valid
  AND target organization/profession = selected context
```

ขั้นตอน implement ระยะถัดไป:

1. ระบุ organization identity แยกจาก `profession_id` หากหนึ่ง profession ใช้หลายองค์กรได้
2. เพิ่มหรือใช้ตาราง membership ที่มี `organization_id`, `user_id`, `role`, `is_active`
3. ให้ owner/member เลือก active organization context
4. เปลี่ยน override record จากการผูก organization ด้วย profession อย่างเดียว เป็นผูกกับ organization context ที่ชัดเจน หรือกำหนด mapping ที่ enforce ได้
5. ให้ backend ตรวจ capability และ membership ทุกครั้ง
6. เก็บ `organization_id`, `profession_id`, `changed_by` ใน history เพื่อ audit ได้ครบ
7. ทดสอบ user หนึ่งคนที่อยู่หลายองค์กรและองค์กรเดียวกันมีหลาย profession

---

## 11. บทสรุป

**สำหรับปัญหา apisek และ Maestro Scenario 2 (ระยะสั้น):**

แนะนำ **แนวทาง 1 (flag `can_manage_drug_risk`)** เพราะ:
- Backend ใช้ flag นี้อยู่แล้วเพื่อตรวจสอบสิทธิ์ modifier
- Frontend `_pageMode` ไม่สอดคล้องกับ backend จึงเป็นต้นตอของปัญหา
- ใช้โครงสร้างที่มีอยู่แล้วใน DB ไม่ต้องเพิ่ม column ใหม่
- แก้ไขน้อยที่สุด (1 ไฟล์หลัก)
- ยืดหยุ่น — Admin ควบคุมสิทธิ์จาก UI โดยตรง

**สำหรับโครงสร้างระยะยาว:**

แนะนำ **แนวทาง 1 + แนวทาง 2 ร่วมกัน**:
- ใช้ `can_manage_drug_risk` ตรวจสอบ **สิทธิ์จัดการ Drug Risk**
- ใช้ organization membership ตรวจสอบ **ขอบเขตองค์กร**
- สองเงื่อนไขนี้ร่วมกันจึงจะเข้า Organization mode
- ย้าย authorization หลักไป backend/RPC ไม่พึ่ง frontend mode เพียงอย่างเดียว
- แก้ RLS จาก `USING (true)` ก่อน Production
- แยกความกังวล (separation of concerns) อย่างชัดเจน

**สำหรับจุดอื่น ๆ ที่ใช้ built-in UUID:**
- กลุ่ม A (isProvider/isConsumer): ใช้ `profession.category` แทน (มีอยู่แล้ว)
- กลุ่ม B (field config): สร้าง default field config สำหรับ custom profession ในหน้า Admin
- กลุ่ม C (consultation): ใช้ `profession.category.isConsultationProvider` แทน (มีอยู่แล้ว)
- กลุ่ม D (backend): ไม่ต้องแก้ (consumer UUID เป็น fallback ที่ถูกต้อง)

---

## 12. ปัญหาที่ต้องระวังเพิ่มเติม

1. **`UserCategory` ในโค้ด vs ฐานข้อมูล:**
   - ปัจจุบัน `UserCategory.consumer` / `UserCategory.provider` / `UserCategory.localLeader` เป็น hardcode ใน Dart
   - ถ้า admin เพิ่ม category ใหม่ใน DB โค้ดจะไม่รู้จัก → ต้องโหลด categories จาก DB เหมือน professions
   - **ตัวอย่าง inconsistency:** `00000000-...-000004` (ผู้นำชุมชน) มี category `leader` ใน DB แต่ `UserCategory.localLeader` ใช้ค่า `local_leader` ไม่ตรงกัน (`leader` vs `local_leader`)

2. **`profession_code` ซ้ำซ้อน:**
   - DB มี partial unique index `idx_professions_profession_code_unique` แล้ว
   - ต้องเพิ่ม validation ใน UI และป้องกัน custom profession ใช้ code สงวน เช่น `clinic` / `expert` / `consumer`

3. **RLS Policies:**
   - ตาราง Drug Risk Override ปัจจุบันมี policy `USING (true)` และยังไม่ใช่ authorization ที่ปลอดภัย
   - ต้องเปลี่ยนเป็น identity/scope-based policy หรือบังคับเขียนผ่าน RPC/Backend ที่ตรวจ capability และ membership
   - ตรวจสอบด้วย `pg_policies`, function privileges และ negative tests ก่อน Production

4. **Seed Data และ Migrations ในอนาคต:**
   - ถ้าเปลี่ยนไปใช้ custom ทั้งระบบ ควรหยุด hardcode UUID ใน migrations ใหม่
   - ใช้ `profession_code` หรือ lookup function แทนใน seed data

5. **Test Data:**
   - Test fixtures หลายที่อาจสร้าง user ด้วย built-in UUID → ต้องตรวจสอบและอัปเดต test suite

6. **ความสับสนระหว่าง "สิทธิ์" กับ "องค์กร":**
   - แนวทาง 1 ทำให้ custom profession มีสิทธิ์จัด Drug Risk ได้
   - แต่ถ้าอาชีพนั้นไม่ใช่องค์กร (เช่น หมอเดี่ยว) อาจไม่ควรเข้า Organization mode
   - ระยะยาวควรใช้แนวทาง 1 + แนวทาง 2 ควบคู่กัน

---

## 12. งานที่ค้าง: แก้ Maestro Test Scenario 02 (Organization Override)

> อัปเดตล่าสุด: 2026-07-13

### สถานะปัจจุบัน

แก้ไขสำเร็จแล้ว:
- ปัญหา `hideKeyboard` ส่ง back button ทำให้หน้า drug risk ถูก pop ออกจาก stack → เปลี่ยนเป็น tap บน app bar area (`point: "400,75"`) แทน
- ปัญหา "ตั้งค่า Override" ไม่ปรากฏ → แก้ไขแล้ว ปุ่มโผล่และกดได้สำเร็จ (ใช้ `extendedWaitUntil` กับ regex `.*Override.*`)
- ปัญหา dialog ถูกปิดจากการ tap unfocus → เอาออกแล้ว กด "บันทึก Override" ได้สำเร็จ

ค้างอยู่:
- หลังกด "บันทึก Override" สำเร็จแล้ว keyboard ยังไม่ยอมปิด → ทำให้ badge "Override องค์กร" ไม่ visible ในสายตา Maestro
- ลอง tap ที่ app bar เพื่อ dismiss keyboard แล้วแต่ยังไม่สำเร็จ (keyboard ยังคงอยู่ใน view hierarchy)
- ต้องหาวิธี dismiss keyboard ที่ไม่ใช่ `hideKeyboard` (เพราะส่ง back button ทำให้ pop หน้า)

### แนวทางแก้ไขที่ยังไม่ได้ลอง

1. **แก้ที่ Flutter code:** เพิ่ม `FocusScope.of(context).unfocus()` หลัง `Navigator.pop` ใน `_showOverrideDialog` (บรรทัด ~1540-1541 ของ `drug_risk_classification_admin_page.dart`) เพื่อ dismiss keyboard ทันทีที่ dialog ปิด
2. **ใช้ Maestro `back` command:** อาจใช้ได้ถ้า dialog ยังเปิดอยู่ แต่ต้องระวังว่าอาจ pop หน้าหลักด้วย
3. **ใช้ `pressKey: Back` ใน Maestro:** ลองสั้น ๆ เพื่อ dismiss keyboard เฉพาะ
4. **เพิ่ม `FocusManager.instance.primaryFocus?.unfocus()` ใน Flutter:** หลัง `await _searchMedications(_searchController.text)` ในบรรทัด 1558

### ไฟล์ที่เกี่ยวข้อง

- `maestro/scenario_02_organization_override.yaml` — ไฟล์ Maestro test (แก้ไขแล้วหลายจุด)
- `lib/features/pharmacy/presentation/pages/drug_risk_classification_admin_page.dart` — Flutter source (ยังไม่ได้แก้)
  - `_showOverrideDialog` (บรรทัด 1324) — ฟังก์ชันเปิด dialog
  - บรรทัด 1540-1541 — `Navigator.pop` หลังบันทึก override สำเร็จ
  - บรรทัด 1557-1558 — `_searchMedications` หลัง dialog ปิด

### ขั้นตอนถัดไป

1. เลือกแนวทางแก้ (แนะนำข้อ 1 — แก้ที่ Flutter code เพราะเป็น root cause)
2. แก้ `drug_risk_classification_admin_page.dart` เพิ่ม `FocusScope.of(context).unfocus()` หลัง `Navigator.pop`
3. รัน Maestro test อีกครั้ง
4. ถ้าผ่าน ตรวจสอบว่า second login flow (MEMBER_USERNAME) ผ่านด้วย
