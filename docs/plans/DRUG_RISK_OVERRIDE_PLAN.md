# แผนการพัฒนาระบบ Override หมวดหมู่ความเสี่ยงยา
## Drug Risk Classification Override Plan

> **สถานะ:** Draft v3.0
> **วันที่:** 2026-07-09
> **อ้างอิง:** [route_security_implementation_plan.md](../guides/route_security_implementation_plan.md), [CHAT_CONSULTATION_IMPROVEMENT_PLAN.md](CHAT_CONSULTATION_IMPROVEMENT_PLAN.md), [Delivery_PLAN.md](Delivery_PLAN.md), [ERP_CORE_ARCHITECTURE.md](../ERP/ERP_CORE_ARCHITECTURE.md)

---

## ระบบความเสี่ยงยา 3 ระดับ (3-Tier Risk Layer)

| ระดับ | Scope | ใครเปลี่ยนได้ | เก็บที่ใด |
|-------|-------|--------------|----------|
| **1. Thai FDA Standard** | Global | System Admin | `medications.fda_risk_status` |
| **2. Platform Custom Risk** | Global | System Admin | `custom_risk_levels` |
| **3. Override (ใหม่)** | Org หรือ Personal | ผู้ที่ได้รับสิทธิ์ `canManageDrugRisk` | `drug_risk_overrides` |

### Merge Priority (ลำดับความสำคัญเมื่อมีหลาย Tier)

```
Personal Override (user_id)             ← ชนะสูงสุด (ถ้ามี)
    ↓ ถ้าไม่มี
Organization Override (profession_id)   ← (ถ้า user สังกัดองค์กร)
    ↓ ถ้าไม่มี
Platform Custom Risk (Tier 2)
    ↓ ถ้าไม่มี
Thai FDA Standard (Tier 1)              ← ค่าเริ่มต้นของ Sheserved
```

> หากองค์กรหรืออาชีพอิสระไม่มีประวัติการ Override ใดๆ ระบบจะใช้ค่ากลางของ Sheserved (Tier 1+2) เป็น Default อัตโนมัติ

---

## Legal Compliance (กฎเหล็ก)

> [!CAUTION]
> **ยา `N` (ยาเสพติดให้โทษ) และ `P` (วัตถุออกฤทธิ์ต่อจิตและประสาท) ห้าม override เป็น telemedicine allowed ทุกกรณี**
> ไม่ว่าจะเป็น Personal หรือ Organization scope — บังคับตามกฎหมายไทย
>
> การบังคับใช้:
> - **Repository Layer:** `setOverride()` throw Exception ทันทีหากพยายาม override N/P เป็น `is_telemedicine_prohibited = false`
> - **UI Layer:** ปุ่ม toggle สำหรับ `is_telemedicine_prohibited` จะถูก disable + แสดงป้ายกำกับ "บังคับตามกฎหมาย" เมื่อยาเป็น N หรือ P

---

## สิทธิ์และโหมดของผู้ใช้ (Permission Matrix)

| ผู้ใช้ | เงื่อนไข | โหมด UI | สิทธิ์ |
|--------|----------|----------|--------|
| **System Admin** | `isAdmin == true` | 🌐 Global Admin | แก้ค่ากลาง Sheserved |
| **สมาชิกองค์กร + มีสิทธิ์แก้** | `professionId != null` + `canManageDrugRisk == true` + `!isAdmin` | 🏥 Organization Override | แก้ Override **ในนามองค์กร** (ทุกคนในองค์กรได้รับผล) |
| **สมาชิกองค์กร + ไม่มีสิทธิ์แก้** | `professionId != null` + `canManageDrugRisk == false` | *(ไม่เห็นเมนู)* | ใช้ค่า Override ขององค์กรอัตโนมัติ |
| **อาชีพอิสระ + มีสิทธิ์แก้** | `professionId == null` + `canManageDrugRisk == true` + `!isAdmin` | 👤 Personal Override | แก้ Override **ส่วนตัว** (ผลกระทบเฉพาะตนเอง) |

---

## การจัดการ Multi-Editor Conflict & การพ้นสภาพผู้มีสิทธิ์

### 1. ลำดับการหาผู้รับผิดชอบ (Owner Resolution Fallback)

```
ผู้แก้ไขล่าสุด (last_modified_by)
    ↓ (หากพ้นสภาพ หรือ ถูกเพิกถอนสิทธิ์ หรือ ถูกลบ)
ผู้แก้ไขก่อนหน้าในประวัติ (History) ที่ยังมีสถานะ Active และมีสิทธิ์ในองค์กร/อาชีพนั้น
    ↓ (หากไม่มีประวัติการ override เลย หรือทุกคนในประวัติพ้นสภาพหมดแล้ว)
ผู้ดูแลระบบกลาง (System Admin) ของ Sheserved และใช้ค่าเริ่มต้น (Global Default) ของ Sheserved
```

### 2. UI Banner Indicators

* **กรณีปกติ:**
  > ⚠️ แก้ไขล่าสุดโดย **นพ.สมชาย** เมื่อ 2 ชั่วโมงที่แล้ว
* **กรณีคนล่าสุดพ้นสภาพ แต่มีคนอื่นยัง Active:**
  > ⚠️ ตั้งค่าโดยอดีตเจ้าหน้าที่ (โอนย้ายสิทธิ์ดูแลให้ **พญ.วิภา [Active]** ล่าสุดเมื่อ 1 วันก่อน)
* **กรณีไม่มีประวัติ หรือ ทุกคนพ้นสภาพ:**
  > ℹ️ ใช้ค่าเริ่มต้นของ Sheserved — ดูแลโดย **System Admin**
* **กรณี Personal Override:**
  > 👤 ตั้งค่าส่วนตัวโดยคุณ เมื่อ 3 วันที่แล้ว

---

## 1. Database Schema

### [NEW] Table `drug_risk_overrides` — Active Override

```sql
CREATE TABLE IF NOT EXISTS drug_risk_overrides (
  id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Scope: ต้องมีอย่างน้อย 1 (แต่ไม่ต้องมีทั้งคู่)
  user_id                         UUID REFERENCES users(id) ON DELETE CASCADE,
  profession_id                   UUID REFERENCES professions(id) ON DELETE CASCADE,
  medication_id                   UUID NOT NULL REFERENCES medications(id) ON DELETE CASCADE,

  -- Override fields (null = ใช้ค่า tier ที่ต่ำกว่า)
  override_fda_risk_status        TEXT CHECK (override_fda_risk_status IN ('ND', 'D', 'S', 'N', 'P')),
  override_sub_category           TEXT,
  override_custom_risk_code       TEXT,
  override_is_telemedicine_prohibited BOOLEAN,
  override_notes                  TEXT,

  -- Traceability — ON DELETE SET NULL เพื่อไม่ให้ค่า Override หายเมื่อลบ User
  last_modified_by                UUID REFERENCES users(id) ON DELETE SET NULL,
  last_modified_at                TIMESTAMPTZ DEFAULT now(),
  created_by                      UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at                      TIMESTAMPTZ DEFAULT now(),

  CONSTRAINT chk_scope_required CHECK (user_id IS NOT NULL OR profession_id IS NOT NULL)
);

-- Partial Unique Indexes (รองรับ Postgres ทุกเวอร์ชัน)
CREATE UNIQUE INDEX idx_dro_user_medication
  ON drug_risk_overrides (user_id, medication_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX idx_dro_profession_medication
  ON drug_risk_overrides (profession_id, medication_id) WHERE profession_id IS NOT NULL;

-- Query Indexes
CREATE INDEX idx_dro_user       ON drug_risk_overrides(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_dro_profession ON drug_risk_overrides(profession_id) WHERE profession_id IS NOT NULL;
CREATE INDEX idx_dro_medication ON drug_risk_overrides(medication_id);
```

### [NEW] Table `drug_risk_override_history` — Version History (ทั้ง Org และ Personal)

```sql
CREATE TABLE IF NOT EXISTS drug_risk_override_history (
  id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  override_id                     UUID REFERENCES drug_risk_overrides(id) ON DELETE SET NULL,

  -- Scope: รองรับทั้ง Org และ Personal history
  profession_id                   UUID REFERENCES professions(id),  -- nullable สำหรับ Personal
  user_id                         UUID REFERENCES users(id),        -- nullable สำหรับ Org
  medication_id                   UUID NOT NULL REFERENCES medications(id),

  -- Snapshot ค่าก่อน/หลัง
  fda_risk_status_before          TEXT,
  fda_risk_status_after           TEXT,
  sub_category_before             TEXT,
  sub_category_after              TEXT,
  custom_risk_code_before         TEXT,
  custom_risk_code_after          TEXT,
  is_telemedicine_prohibited_before BOOLEAN,
  is_telemedicine_prohibited_after  BOOLEAN,
  notes_before                    TEXT,
  notes_after                     TEXT,

  -- Audit
  action                          TEXT NOT NULL CHECK (action IN ('create', 'update', 'delete')),
  changed_by                      UUID REFERENCES users(id) ON DELETE SET NULL,
  changed_by_name                 TEXT NOT NULL, -- Text Snapshot ชื่อจริงของผู้แก้ ณ เวลานั้น
  changed_at                      TIMESTAMPTZ DEFAULT now(),
  change_reason                   TEXT,

  CONSTRAINT chk_history_scope CHECK (profession_id IS NOT NULL OR user_id IS NOT NULL)
);

CREATE INDEX idx_droh_profession ON drug_risk_override_history(profession_id) WHERE profession_id IS NOT NULL;
CREATE INDEX idx_droh_user       ON drug_risk_override_history(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_droh_medication ON drug_risk_override_history(medication_id);
CREATE INDEX idx_droh_changed_at ON drug_risk_override_history(changed_at DESC);
```

### [NEW] SQL RPC Function — `resolve_effective_modifier` (แก้ N+1 Query)

```sql
-- แทนที่การวนลูป Dart ด้วย Single DB call
CREATE OR REPLACE FUNCTION resolve_effective_modifier(
  p_medication_id UUID,
  p_profession_id UUID DEFAULT NULL,
  p_user_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_override RECORD;
  v_result JSON;
  v_modifier RECORD;
BEGIN
  -- 1. ดึง Override ที่ active
  SELECT dro.last_modified_by, dro.last_modified_at
  INTO v_override
  FROM drug_risk_overrides dro
  WHERE dro.medication_id = p_medication_id
    AND (
      (p_profession_id IS NOT NULL AND dro.profession_id = p_profession_id)
      OR (p_user_id IS NOT NULL AND dro.user_id = p_user_id)
    )
  LIMIT 1;

  -- ไม่มี Override → ใช้ค่าเริ่มต้น
  IF v_override IS NULL THEN
    RETURN json_build_object(
      'name', 'Sheserved Default',
      'status', 'no_override'
    );
  END IF;

  -- 2. ตรวจสอบ User ล่าสุด
  IF v_override.last_modified_by IS NOT NULL THEN
    SELECT u.id, u.name, u.is_active, p.can_manage_drug_risk
    INTO v_modifier
    FROM users u
    LEFT JOIN professions p ON u.profession_id = p.id
    WHERE u.id = v_override.last_modified_by;

    IF v_modifier IS NOT NULL AND v_modifier.is_active = true
       AND v_modifier.can_manage_drug_risk = true THEN
      RETURN json_build_object(
        'id', v_modifier.id,
        'name', v_modifier.name,
        'status', 'active',
        'modified_at', v_override.last_modified_at
      );
    END IF;
  END IF;

  -- 3. ค้นประวัติย้อนหลัง — Single JOIN query แทนวนลูป
  SELECT h.changed_by, h.changed_by_name, u.id AS uid, u.name AS uname,
         u.is_active, p.can_manage_drug_risk
  INTO v_modifier
  FROM drug_risk_override_history h
  JOIN users u ON u.id = h.changed_by
  LEFT JOIN professions p ON u.profession_id = p.id
  WHERE h.medication_id = p_medication_id
    AND (
      (p_profession_id IS NOT NULL AND h.profession_id = p_profession_id)
      OR (p_user_id IS NOT NULL AND h.user_id = p_user_id)
    )
    AND u.is_active = true
    AND p.can_manage_drug_risk = true
  ORDER BY h.changed_at DESC
  LIMIT 1;

  IF v_modifier IS NOT NULL THEN
    RETURN json_build_object(
      'id', v_modifier.uid,
      'name', v_modifier.uname,
      'status', 'fallback_history',
      'snapshot_name', v_modifier.changed_by_name
    );
  END IF;

  -- 4. Fallback → System Admin
  RETURN json_build_object(
    'name', 'System Admin',
    'status', 'fallback_system'
  );
END;
$$;
```

### [MODIFY] Table `drug_risk_admin_logs`

```sql
ALTER TABLE drug_risk_admin_logs
  ADD COLUMN IF NOT EXISTS override_user_id       UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS override_profession_id UUID REFERENCES professions(id),
  ADD COLUMN IF NOT EXISTS override_context       TEXT DEFAULT 'global'
    CHECK (override_context IN ('global', 'organization', 'personal'));
```

---

## 2. Repository Logic

### Owner Resolution (ใช้ RPC แทน N+1)

```dart
/// เรียก RPC รอบเดียว — ไม่มี N+1 query
Future<Map<String, dynamic>> resolveEffectiveModifier({
  required String medicationId,
  String? professionId,
  String? userId,
}) async {
  final result = await _client.rpc('resolve_effective_modifier', params: {
    'p_medication_id': medicationId,
    'p_profession_id': professionId,
    'p_user_id': userId,
  });
  return Map<String, dynamic>.from(result as Map);
}
```

### Merge Logic (getMedicationRiskEffective)

```dart
Future<Map<String, dynamic>> getMedicationRiskEffective({
  required String medicationId,
  String? currentUserId,    // สำหรับ Personal scope
  String? professionId,     // สำหรับ Organization scope
}) async {
  // Tier 1+2: ค่ากลาง
  final base = await _fetchBaseRisk(medicationId);
  Map<String, dynamic> result = {...base, 'has_override': false};

  // Tier 3a: Organization Override
  if (professionId != null) {
    final orgOverride = await _fetchOverride(
      professionId: professionId, medicationId: medicationId);
    if (orgOverride != null && orgOverride.hasAnyOverride) {
      result = _mergeOverride(result, orgOverride, scope: 'organization');
    }
  }

  // Tier 3b: Personal Override (ชนะ Org)
  if (currentUserId != null) {
    final personalOverride = await _fetchOverride(
      userId: currentUserId, medicationId: medicationId);
    if (personalOverride != null && personalOverride.hasAnyOverride) {
      result = _mergeOverride(result, personalOverride, scope: 'personal');
    }
  }

  return result;
}
```

---

## 3. UI — 3 โหมด

### โหมดที่ 1: 🌐 Global Admin
- **เงื่อนไข:** `isSystemAdmin == true`
- **Scope:** แก้ไข `medications`, `dangerous_drug_subcategories`, `custom_risk_levels` (ส่วนกลาง)
- **Banner:** `[🌐 โหมดจัดการส่วนกลาง — เปลี่ยนแปลงส่งผลต่อทุกผู้ใช้]`

### โหมดที่ 2: 🏥 Organization Override
- **เงื่อนไข:** `canManageDrugRisk && professionId != null && !isSystemAdmin`
- **Scope:** แก้ไข `drug_risk_overrides` (profession-scope)
- **Banner:** `[🏥 ตั้งค่าสำหรับ [ชื่อคลินิก] — ไม่กระทบข้อมูลกลาง]`
- **Last-Modified Banner:** แสดงเมื่อมี Override อยู่แล้ว
- **Badge:** 🔵 บนยาที่มี org override
- **Tab "ประวัติ":** ดึงจาก `drug_risk_override_history` กรอง `profession_id`
- **ปุ่ม "คืนค่า Default":** ลบ Override → History action='delete'

### โหมดที่ 3: 👤 Personal Override
- **เงื่อนไข:** `canManageDrugRisk && professionId == null && !isSystemAdmin`
- **Scope:** แก้ไข `drug_risk_overrides` (user-scope)
- **Banner:** `[👤 ตั้งค่าส่วนตัว — ใช้เฉพาะกับการออกใบสั่งยาของคุณ]`
- **Badge:** 🟣 บนยาที่มี personal override
- **Tab "ประวัติ":** ดึงจาก `drug_risk_override_history` กรอง `user_id`

### Mode Selection Logic (Dart)

```dart
enum DrugRiskPageMode { globalAdmin, organizationOverride, personalOverride }

DrugRiskPageMode _resolveMode(User user) {
  if (user.isAdmin) return DrugRiskPageMode.globalAdmin;
  if (user.canManageDrugRisk && user.professionId != null) {
    return DrugRiskPageMode.organizationOverride;
  }
  if (user.canManageDrugRisk && user.professionId == null) {
    return DrugRiskPageMode.personalOverride;
  }
  throw StateError('User should not reach this page without permission');
}
```

---

## 4. Drawer Navigation

```dart
// lib/shared/widgets/tlz_drawer.dart
if (_canManageDrugRisk) ...[
  _buildGroupHeader(context, title: 'การจัดการยา', icon: Icons.medication_outlined),
  if (_expandedGroups['drug_management']!) ...[
    _buildMenuItem(
      context,
      title: 'จัดการหมวดหมู่ความเสี่ยงยา',
      subtitle: _professionId != null
          ? 'ตั้งค่าสำหรับคลินิก'
          : 'ตั้งค่าส่วนตัว',
      icon: Icons.warning_amber_outlined,
      onTap: () { /* navigate to DrugRiskClassificationAdminPage */ },
      isSubItem: true,
    ),
  ],
],
```

---

## 5. Integration Points

### 5.1 Prescription (`CHAT_CONSULTATION_IMPROVEMENT_PLAN.md`)

- `PrescriptionEditorPage` ส่ง `currentUserId` + `professionId` (nullable) ไปยัง `DrugRiskScreeningService`
- `screenMedication(medicationId, currentUserId: ..., professionId: ...)` → merge ผ่าน `getMedicationRiskEffective`
- Badge 🔵 (org) หรือ 🟣 (personal) แสดงใน MedicationCard

### 5.2 Delivery (`Delivery_PLAN.md`)

- เมื่อสร้าง `delivery_orders` ให้ embed `drug_risk_flags` ใน `metadata`:
```jsonb
{
  "drug_risk_flags": {
    "has_override": true,
    "override_scope": "organization",
    "requires_id_verification": true,
    "no_safe_box_allowed": true
  }
}
```

**Implementation (P6):**
- Migration `20260709120000_add_delivery_orders_metadata.sql` — เพิ่ม `metadata JSONB` column + GIN index
- `DeliveryOrder` model เพิ่ม `metadata`, `drugRiskFlags`, `hasDrugRiskFlags`, `requiresIdVerification`, `noSafeBoxAllowed` getters
- `DrugRiskScreeningService.buildDeliveryRiskFlags(results)` — static helper แปลง `List<DrugRiskScreeningResult>` → `drug_risk_flags` map (aggregate has_override, override_scope ตามลำดับ personal > organization, requires_id_verification/no_safe_box_allowed = true ถ้ามียา S/N/P หรือ custom risk prohibited/very_high)
- `PhaseTwoRepository.createDeliveryOrder(data, {drugRiskFlags})` + `PhaseTwoProvider.createDeliveryOrder` — merge `drugRiskFlags` เข้า `data['metadata']` อัตโนมัติก่อน insert
- **หมายเหตุ:** ยังไม่มีหน้า UI สร้าง delivery order จากใบสั่งยาโดยตรง (มีแค่หน้า list `delivery_orders_page.dart`) เมื่อสร้าง flow ดังกล่าวในอนาคต ให้เรียก `DrugRiskScreeningService.buildDeliveryRiskFlags(screenResults)` แล้วส่งผ่าน `drugRiskFlags` parameter

### 5.3 Donation (`DONATION_SYSTEM_PLAN.md`)
*(Future Scope — ดำเนินการหลัง Phase นี้เสร็จ)*

---

## 6. Security Rules

| กฎ | ระดับการบังคับ |
|---|---|
| ยา N/P ห้าม override เป็น telemedicine allowed | Repository (throw Exception) + UI (disable toggle) |
| เฉพาะผู้ที่ `canManageDrugRisk` เท่านั้น | Page Guard + Drawer conditional |
| Org scope: ผู้ใช้ต้องมี `professionId` เดียวกัน | Repository (ตรวจ user.professionId == professionId) |
| Personal scope: ผู้ใช้ override ของ `userId` ตัวเอง | Repository (ตรวจ userId == performedBy) |
| ทุก Override ต้องบันทึก History + Name Snapshot | Repository (auto-insert `drug_risk_override_history`) |

---

## 7. Execution Order

| Phase | งาน | ขึ้นกับ |
|-------|-----|---------|
| **P0** | DB Migration (2 ตาราง + 1 RPC function + alter log table) | — |
| **P1** | Dart Models (`DrugRiskOverride`, `DrugRiskOverrideHistory`) + Repository methods | P0 |
| **P2** | ปรับ `DrugRiskScreeningService` รับ `currentUserId` + `professionId` | P1 |
| **P3** | ปรับ `DrugRiskClassificationAdminPage` — 3 โหมด + History Tab + Last-Modified Banner | P2 |
| **P4** | ปรับ Drawer เพิ่มกลุ่มเมนู "การจัดการยา" + subtitle ตาม scope | P2 |
| **P5** | Integration กับ `PrescriptionEditorPage` | P2, P3 |
| **P6** | Integration กับ `delivery_orders.metadata` | P2 |
| **P7** | Verification & Testing | P6 |

---

## 8. Verification Scenarios

| # | Scenario | Expected |
|---|----------|----------|
| 1 | อาชีพอิสระ Override ยา X (personal) | เฉพาะตนเองเห็นผล, Badge 🟣 |
| 2 | คลินิก A Override ยา X (org) | ทุกคนในคลินิก A เห็น Badge 🔵 |
| 3 | สมาชิกคลินิก A (ไม่มีสิทธิ์แก้) | ใช้ค่า org override อัตโนมัติ ไม่เห็นเมนู |
| 4 | ผู้มีสิทธิ์คนที่ 2 แก้ org Override ยา X | เห็น Last-Modified Banner → บันทึกทับ → History |
| 5 | องค์กรไม่มี Override ใดๆ | ใช้ Sheserved Default (Tier 1+2) |
| 6 | Override ยา N → `is_telemedicine_prohibited = false` | ระบบปฏิเสธ (Legal Compliance) |
| 7 | กด "คืนค่า Default" | ลบ Override, History action='delete' |
| 8 | แพทย์ A ตั้ง Override → พ้นสภาพ → แพทย์ B ดูหน้า | Banner แสดง fallback (RPC `resolve_effective_modifier`) |
| 9 | ทุกคนในประวัติพ้นสภาพ | Banner แสดง "ใช้ค่า Sheserved Default — ดูแลโดย System Admin" |
| 10 | อาชีพอิสระ ดูประวัติ Personal Override | Tab "ประวัติ" แสดง history กรอง `user_id` + ชื่อจาก snapshot |
| 11 | Delivery ยาที่มี org override | `metadata.drug_risk_flags.has_override = true` |
| 12 | Prescription Editor แสดง effective risk | ค่า Merge แล้วจาก `getMedicationRiskEffective` + Badge ตาม scope |

### 8.0 Maestro Test Environment Setup

> เครื่องหลักสำหรับรัน Maestro คือ **macOS** ตามแนวคิดใน `VIDEO_SYSTEM_PLAN.md` (เครื่องเดียวกับที่รัน PostgreSQL, FFmpeg, WebSocket Server) คำแนะนำด้านล่างจึงเขียนสำหรับ macOS เป็นหลัก

#### 8.0.1 Prerequisites

- **macOS 12+** (เครื่องหลัก)
- **Homebrew** ติดตั้งแล้ว (`brew --version`)
- **Android device หรือ Emulator** ที่ enable USB Debugging
- **Flutter app `com.sheserved.app`** ติดตั้งบนอุปกรณ์แล้ว (debug build หรือ release build)

#### 8.0.2 Install Maestro

```bash
# 1. เพิ่ม tap ของ mobile-dev-inc
brew tap mobile-dev-inc/tap

# 2. ติดตั้ง Maestro
brew install mobile-dev-inc/tap/maestro

# 3. ตรวจสอบเวอร์ชัน
maestro --version
```

หาก Homebrew ไม่พร้อมใช้งาน ใช้ curl แทน:

```bash
curl -Ls "https://get.maestro.mobile.dev" | bash
```

จากนั้นเพิ่ม path ลงใน `~/.zshrc` (หรือ `~/.bash_profile`):

```bash
export PATH="$PATH:$HOME/.maestro/bin"
```

#### 8.0.3 Install Android SDK Platform Tools (adb)

Maestro ต้องการ `adb` เพื่อเชื่อมต่อกับ Android device

```bash
# ติดตั้งผ่าน Homebrew
brew install --cask android-platform-tools

# ตรวจสอบ adb
adb --version
```

หากติดตั้ง Android Studio แล้ว `adb` จะอยู่ที่:

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
```

เพิ่มลง `~/.zshrc` เพื่อใช้งานถาวร

#### 8.0.4 Environment Variables

เพิ่มใน `~/.zshrc`:

```bash
# Maestro
export PATH="$PATH:$HOME/.maestro/bin"

# Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$PATH:$ANDROID_HOME/emulator"
export PATH="$PATH:$ANDROID_HOME/platform-tools"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"
```

จากนั้น reload:

```bash
source ~/.zshrc
```

#### 8.0.5 Verify Device Connection

```bash
# แสดงอุปกรณ์ที่เชื่อมต่อ
adb devices

# ตัวอย่างผลลัพธ์:
# List of devices attached
# R8YYA0G5S6J    device
```

หากใช้ emulator ให้ start emulator ก่อน:

```bash
emulator -avd <avd_name>
```

#### 8.0.6 Run Sheserved Maestro Flow

จาก root ของ project:

```bash
# ตรวจสอบ syntax ของ YAML
maestro test maestro/scenario_01_personal_override.yaml

# รันพร้อม env variable
maestro test maestro/scenario_01_personal_override.yaml \
  --env MEDICATION_NAME=Paracetamol

# รันผ่าน Maestro Studio (สำหรับ debug)
maestro studio
```

#### 8.0.7 Useful Commands

```bash
# ดู device ID ที่ Maestro ใช้
maestro hierarchy

# ตรวจสอบ flow ที่กำลังรัน
maestro test --continuous maestro/scenario_01_personal_override.yaml

# ล้าง state ของ app บน device ก่อนรัน
adb shell pm clear com.sheserved.app
```

#### 8.0.8 Troubleshooting

| ปัญหา | สาเหตุ | วิธีแก้ |
|---|---|---|
| `adb: command not found` | `adb` ไม่ได้อยู่ใน PATH | ติดตั้ง `android-platform-tools` และเพิ่ม PATH |
| `maestro: command not found` | Maestro ยังไม่ได้ติดตั้งหรือ PATH ไม่ถูกต้อง | รัน `brew install mobile-dev-inc/tap/maestro` หรือ reload `~/.zshrc` |
| `no devices found` | อุปกรณ์ไม่ได้เชื่อมต่อหรือ USB Debugging ปิด | เปิด USB Debugging, เสียบสายใหม่, รัน `adb devices` |
| `appId not found` | app ยังไม่ได้ติดตั้งบน device | ติดตั้ง debug build ก่อน (`flutter run` หรือ `flutter install`) |
| `Read-only file system` ที่ `takeScreenshot` | Maestro MCP context ไม่มีสิทธิ์ write | ใช้ `assertVisible` แทน screenshot หรือรันผ่าน terminal โดยตรง |

### 8.1 Step-by-step Manual Test Instructions

#### Scenario 1: อาชีพอิสระ Override ยา X (Personal)

**บัตรผู้ทดสอบ:** ผู้ใช้ที่เป็นอาชีพอิสระ (ไม่มี `can_manage_drug_risk` ในระดับ org)

**Maestro Automation:** ไฟล์ `maestro/scenario_01_personal_override.yaml` (66 คำสั่ง ผ่านครบทุกขั้นตอน)

**Bug fixes ระหว่างทดสอบ Maestro (Scenario 1):**
  3. **Maestro YAML — `inputText` ไม่รองรับ Unicode บน Android** → ใช้ `setClipboard` + `pasteText` แทน `inputText` สำหรับกรอกข้อความใน dialog (ใช้ข้อความภาษาอังกฤษ "Test Personal Override" และ "For testing")
  4. **Maestro YAML — `pressKey: Back` ปิด dialog ก่อนกด Save** → เปลี่ยนเป็น `hideKeyboard` เพื่อปิด keyboard โดยไม่ปิด dialog
  5. **Maestro YAML — `assertVisible` ไม่ match ข้อความที่อยู่ใน accessibility text ที่ยาวกว่า** → ใช้ regex `.*Override ส่วนตัว.*` แทน exact match `"Override ส่วนตัว"`
  6. **Maestro YAML — regex escaping ใน YAML** → `\(` ใน YAML single quotes กลายเป็น literal `\(` ซึ่ง regex engine ตีความเป็น literal backslash + group open → ใช้ `\(` ตัวเดียว
  7. **Maestro YAML — `tapOn` ด้วย `hint` property ไม่รองรับ** → ใช้ `tapOn` ด้วย `point` coordinates แทนสำหรับ text fields ใน dialog
  8. **Maestro YAML — `takeScreenshot` ล้มเหลวใน MCP context** (Read-only file system) → ลบ step ออก เนื่องจาก `assertVisible` ยืนยันผลลัพธ์ได้เพียงพอ

1. Login ด้วยบัญชีอาชีพอิสระ
2. เปิด Drawer → กลุ่ม "การจัดการยา" → เมนู "จัดการความเสี่ยงยา"
3. ตรวจสอบว่า Mode Banner แสดง "Personal Override" (สีม่วง)
4. ไป Tab "ค้นหายา" → พิมพ์ชื่อยาที่ต้องการ Override
5. กดปุ่ม "ตั้งค่า Override" บนการ์ดยานั้น
6. เลือก FDA Risk Status = `D` (หรือค่าอื่นที่ต่างจาก default)
7. ใส่หมายเหตุ "ทดสอบ Personal Override"
8. ใส่เหตุผล "สำหรับทดสอบ"
9. กด "บันทึก Override"
10. **คาดหวัง:** กลับสู่หน้าค้นหา การ์ดยาแสดง Badge 🟣 (Personal)
11. Login ด้วยบัญชีอื่นที่เป็นอาชีพอิสระคนละคน
12. ค้นหายาตัวเดียวกัน
13. **คาดหวัง:** ไม่เห็น Badge 🟣, ใช้ค่า Default (ไม่ได้รับผลจาก Personal Override ของคนแรก)

#### Scenario 2: คลินิก A Override ยา X (Organization)

**บัตรผู้ทดสอบ:** ผู้ใช้ในคลินิก A ที่มี `can_manage_drug_risk = true`

1. Login ด้วยบัญชีของคลินิก A (มี `profession_id` ของคลินิก)
2. เปิด Drawer → "การจัดการยา" → "จัดการความเสี่ยงยา"
3. ตรวจสอบว่า Mode Banner แสดง "Organization Override" (สีน้ำเงิน)
4. ไป Tab "ค้นหายา" → ค้นหายา X
5. กด "ตั้งค่า Override" → เลือก FDA Risk Status = `S`
6. ใส่เหตุผล → กด "บันทึก Override"
7. **คาดหวัง:** การ์ดยาแสดง Badge 🔵 (Organization)
8. Login ด้วยบัญชีอื่นในคลินิก A (เป็นสมาชิกคลินิกเดียวกัน)
9. ค้นหายา X
10. **คาดหวัง:** เห็น Badge 🔵 เหมือนกัน (Organization Override มีผลกับทุกคนในคลินิก)

#### Scenario 3: สมาชิกคลินิก A (ไม่มีสิทธิ์แก้)

**บัตรผู้ทดสอบ:** ผู้ใช้ในคลินิก A ที่ `can_manage_drug_risk = false`

1. Login ด้วยบัญชีสมาชิกคลินิก A (ไม่มีสิทธิ์จัดการยา)
2. เปิด Drawer
3. **คาดหวัง:** ไม่เห็นกลุ่มเมนู "การจัดการยา" (ซ่อนเพราะ `_canManageDrugRisk = false`)
4. ไปหน้า Prescription Editor และเพิ่มยา X (ที่คลินิกตั้ง Override ไว้ใน Scenario 2)
5. **คาดหวัง:** ยา X แสดงค่า risk ตาม Organization Override อัตโนมัติ (Badge 🔵) แม้ผู้ใช้ไม่มีสิทธิ์แก้

#### Scenario 4: ผู้มีสิทธิ์คนที่ 2 แก้ Org Override ยา X

**บัตรผู้ทดสอบ:** ผู้ใช้ B ในคลินิก A ที่มี `can_manage_drug_risk = true`

1. Login ด้วยบัญชีผู้ใช้ B (คลินิก A, มีสิทธิ์)
2. เปิด "จัดการความเสี่ยงยา" → ค้นหายา X
3. **คาดหวัง:** การ์ดยา X แสดง Last-Modified Banner ชื่อผู้ใช้ A ที่ตั้ง Override ไว้
4. กด "ตั้งค่า Override" → เปลี่ยน FDA Risk Status เป็นค่าใหม่
5. ใส่เหตุผล → กด "บันทึก Override"
6. **คาดหวัง:** Banner เปลี่ยนเป็นชื่อผู้ใช้ B
7. ไป Tab "ประวัติการตั้งค่า"
8. **คาดหวัง:** เห็น history 2 รายการ — `create` โดยผู้ใช้ A และ `update` โดยผู้ใช้ B

#### Scenario 5: องค์กรไม่มี Override ใดๆ

**บัตรผู้ทดสอบ:** ผู้ใช้ในคลินิก B (ไม่เคยตั้ง Override)

1. Login ด้วยบัญชีคลินิก B (มีสิทธิ์จัดการยา)
2. เปิด "จัดการความเสี่ยงยา"
3. ค้นหายา X (ที่คลินิก A ตั้ง Override ไว้)
4. **คาดหวัง:** การ์ดยา X แสดงค่า Sheserved Default (Tier 1+2) ไม่มี Badge 🔵 หรือ 🟣
5. ตรวจสอบว่าไม่มี Last-Modified Banner

#### Scenario 6: Override ยา N → ปิด Telemedicine (Legal Compliance)

**บัตรผู้ทดสอบ:** ผู้ใช้ที่มีสิทธิ์จัดการยา

1. Login → เปิด "จัดการความเสี่ยงยา"
2. ค้นหายาที่มี FDA Risk Status = `N` (ยาเสพติดให้โทษ)
3. กด "ตั้งค่า Override"
4. เลือก FDA Risk Status = `N`
5. สังเกต Switch "ห้ามจ่ายผ่าน Telemedicine"
6. **คาดหวัง:** Switch ถูก disabled (สีเทา) มีป้าย Chip สีแดง "บังคับตามกฎหมาย" และ subtitle สีแดง
7. พยายามเปลี่ยนค่า Switch → **คาดหวัง:** ไม่สามารถ toggle ได้
8. กด "บันทึก Override" (ค่า `is_telemedicine_prohibited` คว้มเป็น `true` โดยบังคับ)
9. **คาดหวัง:** บันทึกสำเร็จ, ค่า `is_telemedicine_prohibited = true` ถูกบันทึก

#### Scenario 7: กด "คืนค่า Default" (ลบ Override)

**บัตรผู้ทดสอบ:** ผู้ใช้ที่มี Override อยู่ (จาก Scenario 1 หรือ 2)

1. Login → เปิด "จัดการความเสี่ยงยา"
2. ค้นหายาที่เคยตั้ง Override ไว้
3. กด "ตั้งค่า Override" บนการ์ดยา
4. กดปุ่ม "คืนค่า Default" หรือ "ลบ Override"
5. ยืนยันการลบ
6. **คาดหวัง:** การ์ดยากลับเป็นค่า Default (ไม่มี Badge)
7. ไป Tab "ประวัติการตั้งค่า"
8. **คาดหวัง:** เห็น history รายการใหม่ action = `delete`

#### Scenario 8: แพทย์ A ตั้ง Override → พ้นสภาพ → แพทย์ B ดูหน้า

**เตรียมการ:** ต้องมีสิทธิ์แก้ `is_active` ของผู้ใช้ใน Supabase

1. Login ด้วยบัญชีแพทย์ A (คลินิก A, `can_manage_drug_risk = true`)
2. ตั้ง Override ยา X ในคลินิก A
3. Logout
4. ใน Supabase Dashboard ตั้ง `is_active = false` สำหรับแพทย์ A (จำลองพ้นสภาพ)
5. Login ด้วยบัญชีแพทย์ B (คลินิก A, `can_manage_drug_risk = true`)
6. เปิด "จัดการความเสี่ยงยา" → ค้นหายา X
7. **คาดหวัง:** Banner แสดง "ตั้งค่าโดยอดีตเจ้าหน้าที่ (โอนย้ายสิทธิ์ดูแลให้ ... [Active])" (status = `fallback_history`)
8. ตรวจสอบว่า Override ยังมีผลอยู่ (ค่าที่แพทย์ A ตั้งไว้ยังใช้งานได้)

#### Scenario 9: ทุกคนในประวัติพ้นสภาพ

**เตรียมการ:** ต้องมี Override ที่ผู้ตั้งทั้งหมดพ้นสภาพแล้ว

1. สร้าง Override ยา Y โดยผู้ใช้ C
2. ตั้ง `is_active = false` สำหรับผู้ใช้ C
3. ตั้ง `can_manage_drug_risk = false` สำหรับผู้ใช้ C (ถ้ายัง active แต่ไม่มีสิทธิ์)
4. Login ด้วยบัญชีผู้ใช้ D (คลินิกเดียวกัน, มีสิทธิ์)
5. เปิด "จัดการความเสี่ยงยา" → ค้นหายา Y
6. **คาดหวัง:** Banner แสดง "ดูแลโดย System Admin (เนื่องจากผู้ตั้งค่าพ้นสภาพการเป็นผู้ดูแลระบบ)" (status = `fallback_system`)

#### Scenario 10: อาชีพอิสระ ดูประวัติ Personal Override

**บัตรผู้ทดสอบ:** อาชีพอิสระที่เคยตั้ง/แก้/ลบ Override

1. Login ด้วยบัญชีอาชีพอิสระ
2. เปิด "จัดการความเสี่ยงยา" (Mode = Personal Override)
3. ไป Tab "ประวัติการตั้งค่า"
4. **คาดหวัง:** เห็นรายการ History กรองเฉพาะ `user_id` ของผู้ใช้ปัจจุบัน
5. ตรวจสอบว่าแต่ละรายการแสดง:
   - action (`create` / `update` / `delete`)
   - ชื่อผู้เปลี่ยน (จาก `changed_by_name` snapshot)
   - ค่าก่อน/หลัง (FDA status, sub_category, custom_risk_code, telemedicine)
   - เวลาที่เปลี่ยน (`changed_at`)
6. **คาดหวัง:** ไม่เห็น history ของคนอื่น (เฉพาะของตนเอง)

#### Scenario 12: Prescription Editor แสดง Effective Risk

**บัตรผู้ทดสอบ:** ผู้ใช้ที่มีสิทธิ์สั่งยา

1. Login → เปิด Prescription Editor (จาก consultation หรือ flow ที่เกี่ยวข้อง)
2. ค้นหาและเพิ่มยา X (ที่มี Organization Override จาก Scenario 2)
3. **คาดหวัง:** ยา X แสดงค่า risk ที่ merge แล้วจาก `getMedicationRiskEffective` (FDA status ตาม org override)
4. ตรวจสอบ Badge บนยา X
5. **คาดหวัง:** แสดง Badge 🔵 (Organization scope)
6. เพิ่มยา Z (ที่มี Personal Override จาก Scenario 1)
7. **คาดหวัง:** ยา Z แสดง Badge 🟣 (Personal scope)
8. เพิ่มยา W (ที่ไม่มี Override ใดๆ)
9. **คาดหวัง:** ยา W แสดงค่า Sheserved Default (ไม่มี Badge)
10. กดปุ่ม "ตรวจสอบความเสี่ยง" หรือ trigger screening
11. **คาดหวัง:** ผล screening ใช้ค่าที่ merge แล้ว (override > default) สำหรับทุกยา

---

## 9. P7: Verification & Testing

**Implementation (P7):**
- สร้าง test files:
  - `test/features/pharmacy/data/services/drug_risk_screening_service_test.dart`
  - `test/features/erp/presentation/providers/phase_two_notifier_test.dart`
- **Unit tests (25 tests, all passing):**
  - `DrugRiskScreeningResult` helpers: `hasOverride`, `summary` (blocked/warning/approved)
  - `buildDeliveryRiskFlags` — Scenario 11 (a–i): org override, personal > org priority, no override, FDA S/N/P restricted handling, custom risk prohibited/very_high, mixed results, empty results
  - `DeliveryOrder` model serialization: fromJson with `drug_risk_flags`, empty metadata, null metadata, toJson preservation, round-trip, Supabase-style `Map<dynamic, dynamic>` input
  - `DeliveryOrder.drugRiskFlags` getter with nested `Map<dynamic, dynamic>`
  - `PhaseTwoNotifier.createDeliveryOrder` pass-through: with/without `drugRiskFlags`, repository returns null
- **Manual test scripts (11 scenarios, skipped):**
  - Scenarios 1–10, 12 require live Supabase + UI (override CRUD, RPC `resolve_effective_modifier`, Drawer guard, Prescription Editor)
  - Each scenario documented with step-by-step instructions and expected results
- **Bug fixes during testing:**
  1. `DeliveryOrder.fromJson` — `metadata` และ `proofOfDelivery` cast จาก `Map<dynamic, dynamic>` ไม่ได้โดยตรง → แก้ด้วย `Map<String, dynamic>.from(json[...] as Map)` ป้องกัน runtime type error เมื่อรับ JSON จาก Supabase
  2. `DeliveryOrder.drugRiskFlags` getter — nested `drug_risk_flags` ยังเป็น `Map<dynamic, dynamic>` ได้ → แก้ด้วย `Map<String, dynamic>.from(value as Map)`
  3. `PhaseTwoRepository.createDeliveryOrder` merge logic — `data['metadata']` อาจเป็น `Map<dynamic, dynamic>` → แก้ด้วย `Map<String, dynamic>.from(rawMetadata as Map)`
  4. **`setOverride` upsert ล้มเหลวเพราะ partial unique index** — ตาราง `drug_risk_overrides` ใช้ **partial unique indexes** (มี `WHERE` clause เช่น `WHERE user_id IS NOT NULL`) ซึ่ง parameter `onConflict` ของ PostgREST ไม่รองรับ → แก้โดยเปลี่ยนจาก `upsert(data, onConflict: 'user_id,medication_id')` เป็นการตรวจสอบด้วย `getOverride` ก่อน แล้วค่อย `insert` หรือ `update` ตามกรณี (ไฟล์ `drug_risk_classification_repository.dart` บรรทัด 626–661) — *ป้องกัน: หากตารางใช้ partial unique index ห้ามใช้ `upsert` กับ `onConflict` ต้องใช้ manual check-then-insert-or-update เสมอ*
  5. **`fda_risk_status` column ไม่มีในตาราง `medications`** — query ใน `updateMedicationClassification` (บรรทัด 499–503) และ `getMedicationRiskEffective` (บรรทัด 850–854) เลือกคอลัมน์ `fda_risk_status` และ `dangerous_sub_category` จากตาราง `medications` แต่คอลัมน์เหล่านี้ไม่มีอยู่จริง (ข้อมูล risk ถูกเก็บในตาราง `drug_risk_overrides` และ `medication_risk_classifications`) → แก้โดยเปลี่ยนเป็น `select()` (เลือกทุกคอลัมน์) — *ป้องกัน: อย่าระบุชื่อคอลัมน์ที่ไม่แน่ใจว่ามีอยู่ในตาราง ใช้ `select()` หรือตรวจสอบ schema ก่อน*
- **Analyze status:** No errors in P6/P7 files. Remaining warnings are pre-existing (unused stack trace variables, deprecated APIs, style infos) outside this scope.
- **Pending:** Run manual scenarios 1–10, 12 against live Supabase after migrations applied.
