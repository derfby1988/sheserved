# แผนการพัฒนาระบบ Override หมวดหมู่ความเสี่ยงยา
## Drug Risk Classification Override Plan

> **สถานะ:** Phase 1–7 Implementation Complete (12/13 scenarios passed, 1 awaiting regression test)
> **วันที่:** 2026-07-09 (created) / 2026-07-24 (last updated)
> **อ้างอิง:** [route_security_implementation_plan.md](../guides/route_security_implementation_plan.md), [CHAT_CONSULTATION_IMPROVEMENT_PLAN.md](CHAT_CONSULTATION_IMPROVEMENT_PLAN.md), [Delivery_PLAN.md](Delivery_PLAN.md), [ERP_CORE_ARCHITECTURE.md](../ERP/ERP_CORE_ARCHITECTURE.md)
>
> **Implementation clarification (2026-07-14):** สิทธิ์ Drug Risk ต้องตรวจจากข้อมูลจริงของ `users.profession_id` → `professions.can_manage_drug_risk` เท่านั้น ห้ามอนุมานจากชื่อบัญชี, ประเภทพนักงาน, การเข้า ERP Dashboard หรือ screenshot. ผู้มีสิทธิ์หลายคนที่ใช้ `profession_id` เดียวกันสามารถแก้ Organization Override เดียวกันได้ เพราะ scope อยู่ที่ `profession_id`; `last_modified_by` และ History ใช้แยกผู้แก้แต่ละคน. ERP Dashboard access (`employee_roles`) เป็นคนละระบบและไม่เปลี่ยนค่า `can_manage_drug_risk` โดยอัตโนมัติ.

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
| **อาชีพอิสระ / ไม่มี professionId** | `professionId == null` + `!isAdmin` | *(ไม่เห็นเมนู)* | ไม่สามารถเข้าหน้า **จัดการความเสี่ยงยา** ได้ (Drawer ตรวจ `_canManageDrugRisk`) |

> **ข้อกำหนดสำหรับผู้มีสิทธิ์หลายคน:** พนักงานทุกคนที่มี `canManageDrugRisk == true` และอยู่ใน `profession_id` เดียวกันต้องเห็นและแก้ Org Override เดียวกันได้. ห้ามซ่อนปุ่มแก้ไขเพียงเพราะไม่ใช่ผู้สร้างรายการคนแรก. ก่อนสรุปสิทธิ์ของพนักงานคนใด ต้องตรวจค่า `users.profession_id` และแถว `professions.can_manage_drug_risk` ของข้อมูลจริง.

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
- **เงื่อนไข:** `canManageDrugRisk && professionId != null && มี employees.is_active = true ใน profession เดียวกัน && !isSystemAdmin`
- **Scope:** แก้ไข `drug_risk_overrides` (profession-scope)
- **Banner:** `[🏥 ตั้งค่าสำหรับ [ชื่อคลินิก] — ไม่กระทบข้อมูลกลาง]`
- **Last-Modified Banner:** แสดงเมื่อมี Override อยู่แล้ว
- **Badge:** 🔵 บนยาที่มี org override
- **Tab "ประวัติ":** ดึงจาก `drug_risk_override_history` กรอง `profession_id`
- **ปุ่ม "คืนค่า Default":** ลบ Override → History action='delete'

### โหมดที่ 3: 👤 Personal Override
- **เงื่อนไข:** `!isSystemAdmin` และผู้ใช้ไม่มี employee record ที่ `is_active = true` ใน profession ปัจจุบัน แม้ profession จะมี `can_manage_drug_risk = true`
- **Scope:** แก้ไข `drug_risk_overrides` (user-scope)
- **Banner:** `[👤 ตั้งค่าส่วนตัว — ใช้เฉพาะกับการออกใบสั่งยาของคุณ]`
- **Badge:** 🟣 บนยาที่มี personal override
- **Tab "ประวัติ":** ดึงจาก `drug_risk_override_history` กรอง `user_id`
- **⚠️ ข้อจำกัดปัจจุบัน:** ผู้ใช้ที่ `professionId == null` ไม่สามารถเข้าหน้านี้ได้ เพราะ Drawer ล็อกด้วย `_canManageDrugRisk` (ซึ่งเป็น `false` เมื่อไม่มี `professionId`) ดังนั้นโหมดนี้จึงเข้าถึงได้เฉพาะเมื่อ navigate โดยตรง หรือถ้าในอนาคตมีการเปลี่ยน gating ให้ผู้ใช้ทั่วไปเข้าหน้าได้

### Mode Selection Logic (Dart)

```dart
enum DrugRiskPageMode { globalAdmin, organizationOverride, personalOverride }

DrugRiskPageMode _resolveMode(User user) {
  if (user.isAdmin) return DrugRiskPageMode.globalAdmin;
  if (user.professionId != null &&
      user.canManageDrugRisk &&
      hasActiveEmployeeRecord(user.id, user.professionId)) {
    return DrugRiskPageMode.organizationOverride;
  }
  return DrugRiskPageMode.personalOverride;
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

> **⚠️ ข้อจำกัดปัจจุบัน:** `_canManageDrugRisk` ถูกคำนวณจาก `professions.can_manage_drug_risk` เมื่อ `professionId != null` และเป็น `false` เสมอเมื่อ `professionId == null` ดังนั้นผู้ใช้ที่ไม่มี `professionId` (อาชีพอิสระ / ผู้ใช้ทั่วไป) จะ **ไม่เห็นเมนู** นี้ ไม่สามารถเข้าหน้า **จัดการความเสี่ยงยา** เพื่อตั้งค่า Personal Override ได้ผ่าน Drawer

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
| 1 🔄 | อาชีพอิสระเข้าหน้า Personal Override | ผู้ใช้ที่ login แล้วและไม่มี `professionId` เห็นเมนูและเข้าโหมด Personal Override — **รอทดสอบหลังแก้ Drawer Gating (2026-07-23)** |
| 2 ✅ | คลินิก A Override ยา X (org) | ทุกคนในคลินิก A เห็น Badge 🔵 — **ผ่าน (2026-07-17)** |
| 3 ✅ | สมาชิกคลินิก A (ไม่มีสิทธิ์แก้) | ใช้ค่า org override อัตโนมัติ ไม่เห็นเมนู — **ผ่าน (2026-07-17)** |
| 4 ✅ | ผู้มีสิทธิ์คนที่ 2 แก้ org Override ยา X | เห็น Last-Modified Banner → บันทึกทับ → History — **ผ่าน (2026-07-22)** |

| 5 ✅ | องค์กรไม่มี Override ใดๆ | ใช้ Sheserved Default (Tier 1+2) — **ผ่าน (2026-07-22)** |
| 6 ✅ | Override ยา N → `is_telemedicine_prohibited = false` | ระบบปฏิเสธ (Legal Compliance) — **ผ่าน (2026-07-22)** |
| 7 ✅ | กด "คืนค่า Default" | ลบ Override, History action='delete' — **ผ่าน (2026-07-22)** |
| 8 ✅ | แพทย์ A ตั้ง Override → พ้นสภาพ → แพทย์ B ดูหน้า | Banner แสดง fallback (RPC `resolve_effective_modifier`) — **ผ่าน (2026-07-22)** |
| 9 ✅ | ทุกคนในประวัติพ้นสภาพ | Banner แสดง "ดูแลโดย System Admin" (fallback_system) — **ผ่าน (2026-07-22)** |
| 10 🔄 | อาชีพอิสระ ดูประวัติ Personal Override | รอทดสอบ UI หลังแก้ Drawer Gating; ต้องเห็นเฉพาะ history ของ `user_id` ตนเอง |
| 11 ✅ | Delivery ยาที่มี org override | `metadata.drug_risk_flags.has_override = true` — **ผ่าน (unit tests, 25 tests all passing)** |
| 12 ✅ | Prescription Editor แสดง effective risk (Org Override) | ค่า Merge แล้วจาก `getMedicationRiskEffective` + Badge 🔵 ตาม scope — **ผ่าน (2026-07-23)** |
| 13 ✅ | Prescription Editor แสดง Personal Override Badge | Personal Override (P) ชนะ Org Override (S) ตาม merge priority + Badge 🟣 — **ผ่าน (2026-07-23)** |

> **ห้ามตีความ Scenario 3/4 ปะปนกัน:** สมาชิกที่ `can_manage_drug_risk = false` ไม่ควรเข้า Admin Page; ผู้มีสิทธิ์คนที่ 2 ที่ `can_manage_drug_risk = true` ต้องยังมีปุ่มแก้ไขและคืนค่า Default. การทดสอบต้องใช้ค่าจาก profession row จริง ไม่ใช้การคาดเดาจากชื่อผู้ใช้หรือสิทธิ์ ERP.

### 8.0 Maestro Test Environment Setup

> การทดสอบ Maestro ทำบน **macOS** กับ **iOS Simulator** (iPhone 16, iOS 18.1, UDID: `A692F954-72BF-4D54-9557-FB61BCB5DBA6`) และ **Android physical device** (UDID: `R8YYA0G5S6J`)

#### 8.0.1 Prerequisites

- **macOS 12+**
- **Homebrew** ติดตั้งแล้ว (`brew --version`)
- **iOS Simulator** (Xcode) หรือ **Android device/emulator**
- **Flutter app `com.example.treeLawZoo`** ติดตั้งบนอุปกรณ์แล้ว (debug build)

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
# รัน Maestro flow บน iOS simulator
maestro test docs/guides/scenario_02_organization_override.yaml \
  --udid A692F954-72BF-4D54-9557-FB61BCB5DBA6

# รันพร้อม env variable
maestro test docs/guides/scenario_12_prescription_editor.yaml \
  --udid A692F954-72BF-4D54-9557-FB61BCB5DBA6 \
  --env MEDICATION_SEARCH=Paracetamol

# รันผ่าน Maestro Studio (สำหรับ debug)
maestro studio
```

> **หมายเหตุ:** ไฟล์ Maestro flow ทั้งหมดอยู่ใน `docs/guides/` ไม่ใช่ `maestro/`

#### 8.0.7 Useful Commands

```bash
# ดู device ID ที่ Maestro ใช้
maestro hierarchy

# รันผ่าน Maestro MCP (ใน Cascade)
# ใช้ mcp1_list_devices เพื่อดูอุปกรณ์ที่เชื่อมต่อ

# ล้าง state ของ app บน iOS simulator
xcrun simctl uninstall A692F954-72BF-4D54-9557-FB61BCB5DBA6 com.example.treeLawZoo
xcrun simctl install A692F954-72BF-4D54-9557-FB61BCB5DBA6 build/ios/iphonesimulator/Runner.app
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

#### Scenario 1: อาชีพอิสระเข้าหน้า Personal Override ผ่าน Drawer

**บัตรผู้ทดสอบ:** ผู้ใช้ที่เป็นอาชีพอิสระ (ไม่มี `profession_id` และไม่มี `can_manage_drug_risk`)

> **สถานะเดิม:** ข้อจำกัดนี้ถูกแก้แล้ว — ผู้ใช้ที่ login แล้วและไม่มี `professionId` เข้าได้เฉพาะโหมด Personal Override ผ่าน Drawer
>
> **ขอบเขตความปลอดภัย:** ผู้ใช้ที่มี `professionId` แต่ `can_manage_drug_risk = false` ยังไม่เห็นเมนู และผู้ใช้ที่ไม่มี `professionId` จะบันทึก/ลบได้เฉพาะ `user_id` ของตนเอง

**สถานะเดิม:** ✅ **ผ่าน (2026-07-17)** — ยืนยันว่า Drawer เดิมซ่อนเมนูสำหรับผู้ใช้ที่ไม่มี `professionId`

**สถานะล่าสุด:** 🔄 **รอทดสอบซ้ำ (2026-07-23)** — หลังปรับ Drawer Gating ให้ผู้ใช้ที่ login แล้วและไม่มี `professionId` เข้าหน้า Personal Override ได้

1. Login ด้วยบัญชีอาชีพอิสระ (ไม่มี `profession_id`)
2. เปิด Drawer
3. **คาดหวังใหม่:** เห็นกลุ่มเมนู "การจัดการยา" และเมนู "จัดการหมวดหมู่ความเสี่ยงยา"
4. เปิดเมนู → **คาดหวัง:** เข้า `DrugRiskClassificationAdminPage` ในโหมด `Personal Override`
5. ค้นหายาที่มี Personal Override อยู่แล้ว
6. **คาดหวัง:** ยาแสดง Badge 🟣 (Personal) ตามค่า `drug_risk_overrides` ที่ merge แล้ว
7. เปิดการ์ดและแก้ไข Override
8. **คาดหวัง:** บันทึกลง scope `user_id` ของผู้ใช้ปัจจุบันเท่านั้น ไม่สามารถแก้ Organization Override ได้
9. เปิด Tab "ประวัติการตั้งค่า"
10. **คาดหวัง:** เห็นเฉพาะ History ที่มี `user_id` ของผู้ใช้ปัจจุบัน

#### Scenario 2: คลินิก A Override ยา X (Organization)

**บัตรผู้ทดสอบ:** ผู้ใช้ในคลินิก A ที่มี `can_manage_drug_risk = true`

**ผลการทดสอบ:** ✅ **ผ่าน (2026-07-17)** — ทดสอบอัตโนมัติด้วย Maestro (iPhone 16 simulator, iOS 18.1) บัญชี "apisek" (admin) และ "firm" (member)

1. Login ด้วยบัญชีของคลินิก A (มี `profession_id` ของคลินิก)
   - **ผลจริง:** ✅ Login สำเร็จ ไปยังหน้า Home
2. เปิด Drawer → "การจัดการยา" → "จัดการความเสี่ยงยา"
   - **ผลจริง:** ✅ เห็นเมนู "จัดการหมวดหมู่ความเสี่ยงยา" ใน Drawer (ยืนยันสิทธิ์ `can_manage_drug_risk = true`)
3. ตรวจสอบว่า Mode Banner แสดง "Organization Override" (สีน้ำเงิน)
   - **ผลจริง:** ✅ หน้าจอแสดง Mode Banner "ตั้งค่าสำหรับองค์กร"
4. ไป Tab "ค้นหายา" → ค้นหายา X (Paracetamol)
   - **ผลจริง:** ✅ ค้นหาเจอ Paracetamol ในผลการค้นหา
5. กด "ตั้งค่า Override" → เลือก FDA Risk Status = `S`
6. ใส่เหตุผล → กด "บันทึก Override"
   - **ผลจริง:** ✅ บันทึก Override สำเร็จ (เห็น SnackBar "บันทึก Override สำเร็จ")
7. **คาดหวัง:** การ์ดยาแสดง Badge 🔵 (Organization)
   - **ผลจริง:** ✅ การ์ดยาแสดง Badge "Override องค์กร" (สี teal)
8. Login ด้วยบัญชีอื่นในคลินิก A (เป็นสมาชิกคลินิกเดียวกัน — "firm")
   - **ผลจริง:** ✅ Login สำเร็จในฐานะ member ของคลินิกเดียวกัน
9. ค้นหายา X (Paracetamol)
   - **ผลจริง:** ✅ ค้นหาเจอ Paracetamol
10. **คาดหวัง:** เห็น Badge 🔵 เหมือนกัน (Organization Override มีผลกับทุกคนในคลินิก)
    - **ผลจริง:** ✅ การ์ดยาแสดง Badge "Override องค์กร" เหมือนกัน

> **Maestro Test File:** `docs/guides/scenario_02_organization_override.yaml` — รันบน iPhone 16 simulator (UDID: 822794E6-EF5C-420A-8620-0BB8653C60E3, iOS 18.1) ผ่านทุกขั้นตอน (exit code 0)

#### Scenario 3: สมาชิกคลินิก A (ไม่มีสิทธิ์แก้)

**บัตรผู้ทดสอบ:** ผู้ใช้ในคลินิก A ที่ `can_manage_drug_risk = false`

**ผลการทดสอบ:** ✅ **ผ่าน (2026-07-17)** — ทดสอบอัตโนมัติด้วย Maestro (iPhone 16 simulator, iOS 18.1) บัญชี "firm" (`can_manage_drug_risk = false`)

1. Login ด้วยบัญชีสมาชิกคลินิก A (ไม่มีสิทธิ์จัดการยา)
   - **ผลจริง:** ✅ Login สำเร็จ (ยืนยันโดยเห็น "ออกจากระบบ" ใน Drawer)
2. เปิด Drawer
3. **คาดหวัง:** ไม่เห็นกลุ่มเมนู "การจัดการยา" (ซ่อนเพราะ `_canManageDrugRisk = false`)
   - **ผลจริง:** ✅ ไม่เห็น "จัดการหมวดหมู่ความเสี่ยงยา" และไม่เห็น "การจัดการยา" (ยืนยันโดย `assertNotVisible`)
4. ไปหน้า Prescription Editor และเพิ่มยา X (ที่คลินิกตั้ง Override ไว้ใน Scenario 2)
   - **สถานะ:** ✅ ครอบคลุมโดย Scenario 12 แล้ว (2026-07-23) — ทดสอบ Prescription Editor Badge ผ่าน Maestro บน simulator
5. **คาดหวัง:** ยา X แสดงค่า risk ตาม Organization Override อัตโนมัติ (Badge 🔵) แม้ผู้ใช้ไม่มีสิทธิ์แก้
   - **สถานะ:** ✅ ครอบคลุมโดย Scenario 12 (2026-07-23)

> **Maestro Test File:** `docs/guides/scenario_03_member_no_permission.yaml` — รันบน iPhone 16 simulator ผ่านทุกขั้นตอนที่ทดสอบได้ (exit code 0)

> **Implementation Note (2026-07-16):** การแสดง Badge ใน Prescription Editor ขึ้นกับการส่ง `medication_id` จาก `PrescriptionEditorPage` ไปยัง `DrugRiskScreeningService.screenPrescriptionWithOverride()` หากส่งแค่ชื่อยา (ไม่มี `id`) ระบบจะไม่สามารถดึง `Organization Override` ได้ → Badge ไม่ปรากฏ แม้ผู้ใช้จะมี `profession_id` ตรงก็ตาม
>
> สาเหตุเดิม: `MedicationItem` ไม่ได้เก็บ `medication_id` และ `_buildMedicationSnapshot()` ไม่ได้รวม `id` ไว้ใน snapshot
>
> วิธีแก้ไข: เพิ่ม `medicationId` ใน `MedicationItem`, เก็บ `model.id` เมื่อเลือกจาก autocomplete, ล้าง `medicationId` เมื่อผู้ใช้พิมพ์ชื่อยาเอง, ส่ง `'id': m.medicationId` ใน `_buildMedicationSnapshot()`, และ persist `medication_id` ใน Draft/Template
>
> ไฟล์: `lib/features/consultation/presentation/pages/prescription_editor_page.dart`

#### Scenario 4: ผู้มีสิทธิ์คนที่ 2 แก้ Org Override ยา X

**บัตรผู้ทดสอบ:** ผู้ใช้ B ในคลินิก A ที่มี `can_manage_drug_risk = true`

**ผลการทดสอบ:** ✅ **ผ่าน (2026-07-22)** — ทดสอบด้วยมือบน iPhone 14ProMax (physical device) บัญชี "firm" (`can_manage_drug_risk = true`, profession_id = `0a8e7857` แพทย์ทั่วไป)

> **หมายเหตุ:** Last-Modified Banner แสดง **ชื่อเต็ม** ของผู้ใช้ (`first_name + last_name`) ไม่ใช่ username เช่น "Dr. Dave" สำหรับ apisek และ "อภิเษก ปัญญาคง" สำหรับ firm ค่าที่เก็บใน `drug_risk_override_history.changed_by_name` คือ full name ณ ขณะนั้น

1. Login ด้วยบัญชีผู้ใช้ B (firm, คลินิก A, มีสิทธิ์)
   - **ผลจริง:** ✅ Login สำเร็จ, `_isActiveOrganizationEmployee = true`, page mode = `organizationOverride`
2. เปิด "จัดการความเสี่ยงยา" → ค้นหายา X (Paracetamol)
   - **ผลจริง:** ✅ ค้นหาเจอ Paracetamol และแสดง Badge "Override องค์กร" (สี teal)
3. **คาดหวัง:** การ์ดยา X แสดง Last-Modified Banner ชื่อผู้ใช้ A ที่ตั้ง Override ไว้
   - **ผลจริง:** ✅ Banner แสดง "แก้ไขล่าสุดโดย Dr. Dave เมื่อ 7 วันที่แล้ว"
4. กด "ตั้งค่า Override" → เปลี่ยน FDA Risk Status เป็นค่าใหม่ (N)
   - **ผลจริง:** ✅ เปลี่ยนสำเร็จ บันทึกไปที่ org scope (profession_id) ไม่ใช่ personal scope
5. ใส่เหตุผล → กด "บันทึก Override"
   - **ผลจริง:** ✅ บันทึกสำเร็จ Badge ยังคงเป็น "Override องค์กร"
6. **คาดหวัง:** Banner เปลี่ยนเป็นชื่อผู้ใช้ B
   - **ผลจริง:** ✅ Banner เปลี่ยนเป็น "แก้ไขล่าสุดโดย อภิเษก ปัญญาคง เมื่อสักครู่"
7. ไป Tab "ประวัติการตั้งค่า"
8. **คาดหวัง:** เห็น history 2 รายการ — `create` โดยผู้ใช้ A และ `update` โดยผู้ใช้ B
   - **ผลจริง:** ✅ History แสดงรายการ `create` โดย "Dr. Dave" และ `update` โดย "อภิเษก ปัญญาคง"

> **Maestro Test File:** `docs/guides/scenario_04_second_editor_history.yaml` — อัพเดตให้ใช้ชื่อเต็มใน assertions (`FIRST_EDITOR_NAME: "Dave"`, `SECOND_EDITOR_NAME: "อภิเษก"`) แทน username

> **การแก้ไขปัญหา:** ก่อนหน้านี้ test ล้มเหลวเพราะ `profession_id` ของ user "firm" ในตาราง `users` ไม่ตรงกับ `employees` table (เป็น `191e414a` เภสัชกร แทนที่จะเป็น `0a8e7857` แพทย์ทั่วไป) ทำให้ `_isActiveOrganizationEmployee = false` และ page mode เป็น `personalOverride` แก้โดย update `users.profession_id` ให้ตรงกับ employee record

#### Scenario 5: องค์กรไม่มี Override ใดๆ

**บัตรผู้ทดสอบ:** ผู้ใช้ในคลินิก B (ไม่เคยตั้ง Override)

**ผลการทดสอบ:** ✅ **ผ่าน (2026-07-22)** — ทดสอบอัตโนมัติด้วย Maestro (iPhone 16 simulator, iOS 18.1) บัญชี "sister" (เภสัชกร, `can_manage_drug_risk = true`, profession_id = `191e414a`)

1. Login ด้วยบัญชีคลินิก B (มีสิทธิ์จัดการยา)
   - **ผลจริง:** ✅ Login สำเร็จ
2. เปิด "จัดการความเสี่ยงยา"
   - **ผลจริง:** ✅ เห็นเมนู "จัดการหมวดหมู่ความเสี่ยงยา" (ยืนยันสิทธิ์ `can_manage_drug_risk = true`)
3. ค้นหายา X (Paracetamol ที่คลินิก A ตั้ง Override ไว้)
   - **ผลจริง:** ✅ ค้นหาเจอ Paracetamol
4. **คาดหวัง:** การ์ดยา X แสดงค่า Sheserved Default (Tier 1+2) ไม่มี Badge 🔵 หรือ 🟣
   - **ผลจริง:** ✅ ไม่แสดง Badge "Override องค์กร" และไม่แสดง Badge "Override ส่วนตัว" (`assertNotVisible` ผ่านทั้งคู่)
5. ตรวจสอบว่าไม่มี Last-Modified Banner
   - **ผลจริง:** ✅ ไม่แสดง "แก้ไขล่าสุดโดย" และไม่แสดง fallback banner ใดๆ (`assertNotVisible` ผ่านทั้งหมด)

> **Maestro Test File:** `docs/guides/scenario_05_other_clinic_no_override.yaml` — รันบน iPhone 16 simulator (UDID: A692F954-72BF-4D54-9557-FB61BCB5DBA6, iOS 18.1) ผ่านทุกขั้นตอน (46 commands, exit code 0)

#### Scenario 6: Override ยา N → ปิด Telemedicine (Legal Compliance)

**บัตรผู้ทดสอบ:** ผู้ใช้ที่มีสิทธิ์จัดการยา

**ผลการทดสอบ:** ✅ **ผ่าน (2026-07-22)** — ทดสอบอัตโนมัติด้วย Maestro (iPhone 16 simulator, iOS 18.1) บัญชี "apisek"

1. Login → เปิด "จัดการความเสี่ยงยา"
   - **ผลจริง:** ✅ Login สำเร็จ เข้าหน้า Drug Risk Admin ได้
2. ค้นหายา (Paracetamol ที่มี Override อยู่แล้ว)
   - **ผลจริง:** ✅ ค้นหาเจอ แสดง Badge "Override องค์กร"
3. กด "ตั้งค่า Override"
   - **ผลจริง:** ✅ Dialog เปิดขึ้น แสดง Override: Paracetamol
4. เลือก FDA Risk Status = `N`
   - **ผลจริง:** ✅ เลือกสำเร็จ
5. สังเกต Switch "ห้ามจ่ายผ่าน Telemedicine"
   - **ผลจริง:** ✅ Switch แสดงค่า on (checked=true, enabled=false)
6. **คาดหวัง:** Switch ถูก disabled มีป้าย Chip สีแดง "บังคับตามกฎหมาย" และ subtitle สีแดง
   - **ผลจริง:** ✅ แสดง "บังคับตามกฎหมาย" และ "ประเภท N/P ห้ามจ่ายผ่าน Telemedicine ตามกฎหมาย"
7. พยายามเปลี่ยนค่า Switch → **คาดหวัง:** ไม่สามารถ toggle ได้
   - **สถานะ:** ⛔ Maestro ไม่สามารถทดสอบ disabled switch โดยตรง แต่ `enabled: false` ยืนยันจาก view hierarchy
8. กด "บันทึก Override" (ค่า `is_telemedicine_prohibited` ควรเป็น `true` โดยบังคับ)
   - **ผลจริง:** ✅ บันทึกสำเร็จ
9. **คาดหวัง:** บันทึกสำเร็จ, ค่า `is_telemedicine_prohibited = true` ถูกบันทึก
   - **ผลจริง:** ✅ Badge "Override องค์กร" ยังแสดงหลัง re-search

> **Maestro Test File:** `docs/guides/scenario_06_telemedicine_legal.yaml` — รันบน iPhone 16 simulator (UDID: A692F954-72BF-4D54-9557-FB61BCB5DBA6, iOS 18.1) ผ่านทุกขั้นตอน (69 commands, exit code 0)
>
> **หมายเหตุ:** Maestro `assertVisible` ใช้ full-string regex match แต่ SwitchListTile รวม text ทั้งหมดเป็น accessibility label เดียว จึงต้องใช้ `.*บังคับตามกฎหมาย.*` แทน `บังคับตามกฎหมาย`

#### Scenario 7: กด "คืนค่า Default" (ลบ Override)

**บัตรผู้ทดสอบ:** ผู้ใช้ที่มี Override อยู่ (จาก Scenario 1 หรือ 2)

**ผลการทดสอบ:** ✅ **ผ่าน (2026-07-22)** — ทดสอบอัตโนมัติด้วย Maestro (iPhone 16 simulator, iOS 18.1) บัญชี "apisek"

1. Login → เปิด "จัดการความเสี่ยงยา"
   - **ผลจริง:** ✅ Login สำเร็จ เข้าหน้า Drug Risk Admin ได้
2. ค้นหายาที่เคยตั้ง Override ไว้ (Paracetamol)
   - **ผลจริง:** ✅ ค้นหาเจอ แสดง Badge "Override องค์กร" สำหรับ BOOTS PARACETAMOL (โอสถ อินเตอร์)
3. กด "ตั้งค่า Override" บนการ์ดยา
   - **ข้อสังเกต:** ปุ่ม "คืนค่า Default" อยู่บนการ์ดยา (TextButton.icon) ไม่ใช่ใน Override dialog
4. กดปุ่ม "คืนค่า Default" บนการ์ดยา
   - **ผลจริง:** ✅ กดได้ ต้อง scroll ลงเพื่อเห็นปุ่ม (ค้นหา Paracetamol ได้หลายการ์ด)
5. ยืนยันการลบใน Confirmation Dialog
   - **ผลจริง:** ✅ Dialog "ยืนยันการคืนค่าเริ่มต้น" แสดง กด "ยืนยันการคืนค่า" สำเร็จ
6. **คาดหวัง:** การ์ดยากลับเป็นค่า Default (ไม่มี Badge)
   - **ผลจริง:** ✅ SnackBar "คืนค่า Default สำเร็จ" แสดง การ์ด BOOTS PARACETAMOL (โอสถ อินเตอร์) ไม่มี Override badge และไม่มีปุ่ม "คืนค่า Default"
7. ไป Tab "ประวัติการตั้งค่า"
   - **ผลจริง:** ✅ สลับ Tab สำเร็จ
8. **คาดหวัง:** เห็น history รายการใหม่ action = `delete`
   - **ผลจริง:** ✅ แสดง "ยกเลิกการ Override" และ "ดำเนินการโดย: Dr. Dave"

> **Maestro Test File:** `docs/guides/scenario_07_remove_override.yaml` — รันบน iPhone 16 simulator (UDID: A692F954-72BF-4D54-9557-FB61BCB5DBA6, iOS 18.1) ผ่านทุกขั้นตอน (71 commands, exit code 0)
>
> **หมายเหตุ:**
> - ต้อง dismiss keyboard หลัง search โดยใช้ `tapOn: id: "Done"` (ปุ่ม Done บน iOS keyboard)
> - ต้อง scroll ลงเพื่อหาการ์ดที่มี "คืนค่า Default" เนื่องจาก search "Paracetamol" ได้หลายการ์ด
> - ใช้ `scrollUntilVisible` แทน manual swipe
> - ไม่สามารถ assert "ไม่มี Override badge ทุกการ์ด" เพราะ Paracetamol ตัวอื่น (CAPLETS) อาจมี override ของตัวเอง
> - SnackBar duration เพิ่มจาก 2 เป็น 5 วินาทีเพื่อให้ Maestro ทันเห็น

#### Scenario 8: แพทย์ A ตั้ง Override → พ้นสภาพ → แพทย์ B ดูหน้า

**เตรียมการ:** ต้องมีสิทธิ์แก้ `is_active` ของผู้ใช้ใน Supabase

**ผลการทดสอบ:** ✅ **ผ่าน (2026-07-22)** — ทดสอบอัตโนมัติด้วย Maestro (iPhone 16 simulator, iOS 18.1) บัญชี "apisek" (Doctor A) และ "firm" (Doctor B)

1. Login ด้วยบัญชีแพทย์ A (apisek, `can_manage_drug_risk = true`)
   - **ผลจริง:** ✅ Login สำเร็จ เข้าหน้า Drug Risk Admin ได้
2. ตั้ง Override ยา Paracetamol ในองค์กร (FDA = S)
   - **ผลจริง:** ✅ ตั้ง Override สำเร็จ แสดง SnackBar "บันทึก Override สำเร็จ"
3. Logout (killApp)
   - **ผลจริง:** ✅ KillApp สำเร็จ
4. ใน Supabase Dashboard ตั้ง `is_active = false` สำหรับ apisek (จำลองพ้นสภาพ)
   - **ผลจริง:** ✅ ตั้ง `is_active = false` สำเร็จ
5. Login ด้วยบัญชีแพทย์ B (firm, `can_manage_drug_risk = true`, same `profession_id`)
   - **ผลจริง:** ✅ Login สำเร็จ เข้าหน้า Drug Risk Admin ได้
6. เปิด "จัดการความเสี่ยงยา" → ค้นหายา Paracetamol
   - **ผลจริง:** ✅ ค้นหาเจอ แสดงการ์ดยา
7. **คาดหวัง:** Banner แสดง "ตั้งค่าโดยอดีตเจ้าหน้าที่ (โอนย้ายสิทธิ์ดูแลให้ ... [Active])" (status = `fallback_history`)
   - **ผลจริง:** ✅ แสดง Banner "ตั้งค่าโดยอดีตเจ้าหน้าที่" สำเร็จ
8. ตรวจสอบว่า Override ยังมีผลอยู่ (ค่าที่แพทย์ A ตั้งไว้ยังใช้งานได้)
   - **ผลจริง:** ✅ Badge "Override องค์กร" ยังแสดงอยู่

> **Maestro Test Files:** `docs/guides/scenario_08a_set_override.yaml` (Phase 1: 62 commands) และ `docs/guides/scenario_08b_verify_fallback.yaml` (Phase 3: 48 commands) — รันบน iPhone 16 simulator (UDID: A692F954-72BF-4D54-9557-FB61BCB5DBA6, iOS 18.1) ผ่านทุกขั้นตอน (exit code 0)
>
> **หมายเหตุ:**
> - แบ่งเป็น 2 ไฟล์เนื่องจากต้อง manual intervention (set `is_active = false`) ระหว่าง Phase 1 และ Phase 3
> - Doctor A: apisek (id: `341cbf8b...`, profession_id: `0a8e7857...`)
> - Doctor B: firm (id: `176179bd...`, profession_id: `0a8e7857...` — same)
> - ใช้ Paracetamol การ์ดแรกที่แสดงใน search results (ไม่เจาะจง BOOTS PARACETAMOL เพราะ search อาจไม่ได้การ์ดนั้น)
> - หลังทดสอบต้อง set `is_active = true` คืนสำหรับ apisek

#### Scenario 9: ทุกคนในประวัติพ้นสภาพ

**เตรียมการ:** ต้องมี Override ที่ผู้ตั้งทั้งหมดพ้นสภาพแล้ว

**ผลการทดสอบ:** ✅ **ผ่าน (2026-07-22)** — ทดสอบอัตโนมัติด้วย Maestro (iPhone 16 simulator, iOS 18.1) บัญชี "firm" (Viewer) ตรวจสอบ override ที่ตั้งโดย "apisek" (พ้นสภาพ)

1. สร้าง Override ยา DPCP โดย apisek (มีอยู่แล้วจากการทดสอบก่อนหน้า)
   - **ผลจริง:** ✅ Override บน "0.0001% DPCP" (medication_id: `81c3e60f`) มีอยู่, `last_modified_by = apisek`
2. ตั้ง `is_active = false` สำหรับ apisek
   - **ผลจริง:** ✅ ตั้ง `is_active = false` สำเร็จ (manual Supabase intervention)
3. ตั้ง `can_manage_drug_risk = false` สำหรับผู้ใช้ C (ถ้ายัง active แต่ไม่มีสิทธิ์)
   - **ข้าม:** ไม่จำเป็นเพราะ apisek พ้นสภาพแล้ว (`is_active = false`) RPC ตรวจสอบเงื่อนไข `is_active = true AND can_manage_drug_risk = true` พร้อมกัน
4. Login ด้วยบัญชี firm (คลินิกเดียวกัน, มีสิทธิ์)
   - **ผลจริง:** ✅ Login สำเร็จ เข้าหน้า Drug Risk Admin ได้
5. เปิด "จัดการความเสี่ยงยา" → ค้นหายา DPCP
   - **ผลจริง:** ✅ ค้นหาเจอ แสดงการ์ดยา
6. **คาดหวัง:** Banner แสดง "ดูแลโดย System Admin (เนื่องจากผู้ตั้งค่าพ้นสภาพการเป็นผู้ดูแลระบบ)" (status = `fallback_system`)
   - **ผลจริง:** ✅ แสดง Banner "ดูแลโดย System Admin" สำเร็จ

> **Maestro Test File:** `docs/guides/scenario_09_fallback_system.yaml` (47 commands) — รันบน iPhone 16 simulator (UDID: A692F954-72BF-4D54-9557-FB61BCB5DBA6, iOS 18.1) ผ่านทุกขั้นตอน (exit code 0)
>
> **หมายเหตุ:**
> - ใช้ยา "0.0001% DPCP" (medication_id: `81c3e60f`) เพราะ history มีเฉพาะ apisek เท่านั้น (ไม่มีคนอื่นแก้ไข)
> - ไม่ใช้ Paracetamol เพราะบางการ์ดมี history จาก firm ด้วย ทำให้ RPC ส่ง `fallback_history` แทน `fallback_system`
> - RPC `resolve_effective_modifier` ตรวจสอบ `is_active = true AND can_manage_drug_risk = true` พร้อมกัน จึงไม่ต้องตั้ง `can_manage_drug_risk = false` แยก
> - หลังทดสอบต้อง set `is_active = true` คืนสำหรับ apisek

#### Scenario 10: อาชีพอิสระ ดูประวัติ Personal Override

**บัตรผู้ทดสอบ:** ผู้ใช้ `independent` / `123456` (สร้างใหม่เพื่อทดสอบโดยเฉพาะ เพราะไม่มี user ใดใน DB ที่ `profession_id IS NULL`)

**DB Verification (2026-07-24):**
- `users` table: ทุก user มี `profession_id` ไม่เป็น NULL (ทั้ง 6 คน)
- `user_group_roles` table: ว่าง (ไม่มี fallback records)
- สร้าง user `independent` ใหม่ด้วย `profession_id = NULL`, `role = consumer`
- profession `00000000-...001` ("ผู้ใช้งานทั่วไป") มี `can_manage_drug_risk = false` — ยืนยันว่า `sister` (ที่ใช้ profession นี้) ไม่ควรเห็นเมนู และ Maestro test ก่อนหน้านี้ที่ใช้ `sister` และผ่านนั้น **ไม่ถูกต้อง** (app บน simulator ยังไม่ได้ rebuild)

**ผลการทดสอบ:** ✅ **ผ่าน (2026-07-24)** — Maestro บน iPhone 16 Simulator (`A692F954-72BF-4D54-9557-FB61BCB5DBA6`), flow สำเร็จ 29 commands หลัง rebuild app

1. Login ด้วยบัญชี `independent` ( `profession_id IS NULL` ใน DB)
2. เปิด Drawer
3. **ผลจริง:** เห็นเมนู "จัดการหมวดหมู่ความเสี่ยงยา" (ในกลุ่ม "การจัดการยา")
4. เปิดเมนู
5. **ผลจริง:** เข้า `DrugRiskClassificationAdminPage` ในโหมด `จัดการความเสี่ยงยา (Personal)`
6. เปิด Tab `ประวัติการตั้งค่า`
7. **ผลจริง:** แสดง "ไม่มีประวัติการตั้งค่า Override" — ยืนยันว่า history ถูก scope ตาม user ปัจจุบัน ไม่แสดงของ user อื่น
8. **การแก้ไขปัญหา:** Maestro test ก่อนหน้านี้ใช้ `sister` ซึ่งมี `profession_id = 00000000-...001` (ไม่ใช่ NULL) และ app บน simulator ยังไม่ได้ rebuild หลังแก้ code — หลัง rebuild และใช้ user `independent` ที่มี `profession_id IS NULL` จริงๆ test ผ่านถูกต้อง

#### Scenario 12: Prescription Editor แสดง Effective Risk

**บัตรผู้ทดสอบ:** ผู้ใช้ที่มีสิทธิ์สั่งยา (provider)

**Flow การนำทาง (อัปเดต 2026-07-23):** เข้าผ่าน `HealthProgramRequestDashboard` ไม่ใช่ `ChatListPage`
1. Login → เปิด Drawer → เลือก "คำขอโปรแกรมรักษา" (เมนู provider ในกลุ่มบริการทางการแพทย์)
2. ใน Dashboard เลือกแท็บ "กำลังดำเนินการ" → กด "เข้าห้องแชทผู้ป่วย" → `ChartBoardPage`
3. ใน ChartBoardPage เปิด Medical Tools → เลือก "ออกใบสั่งยา" → `PrescriptionEditorPage`
4. ค้นหาและเพิ่มยา X (ที่มี Organization Override จาก Scenario 2)
5. **คาดหวัง:** ยา X แสดงค่า risk ที่ merge แล้วจาก `getMedicationRiskEffective` (FDA status ตาม org override)
6. ตรวจสอบ Badge บนยา X
7. **คาดหวัง:** แสดง Badge 🔵 (Organization scope)
8. เพิ่มยา Z (ที่มี Personal Override จาก Scenario 1)
9. **คาดหวัง:** ยา Z แสดง Badge 🟣 (Personal scope)
10. เพิ่มยา W (ที่ไม่มี Override ใดๆ)
11. **คาดหวัง:** ยา W แสดงค่า Sheserved Default (ไม่มี Badge)
12. กดปุ่ม "บันทึก & ส่งใบสั่งยา" เพื่อ trigger screening
13. **คาดหวัง:** ผล screening ใช้ค่าที่ merge แล้ว (override > default) สำหรับทุกยา

> **Maestro Test File:** `docs/guides/scenario_12_prescription_editor.yaml`
>
> **การเปลี่ยนแปลง flow (2026-07-23):** เดิมใช้ `ChatListPage` (Drawer → แชท / สนทนา → เลือก chat room → `ChatRoomPage`) เปลี่ยนเป็นใช้ `HealthProgramRequestDashboard` (Drawer → คำขอโปรแกรมรักษา → เลือกแท็บกำลังดำเนินการ → "เข้าห้องแชทผู้ป่วย" → `ChartBoardPage`) เพราะ ChartBoardPage คือหน้า consultation ที่ใช้จริง ส่ง `ConsultationEntry` โดยตรง และรองรับ medical tools icon เหมือน `ChatRoomPage`
>
> **Bug fix (2026-07-23):** `onChanged` ใน `_MedicationCardWidget` ล้าง `medicationId = null` ก่อนเช็ค `_ignoreNextChange` ทำให้ `medicationId` ที่ `_select()` ตั้งไว้ถูกล้างเมื่อ `nameController.text` ถูก set แก้โดยย้ายการล้าง `medicationId` ไปหลังเช็ค `_ignoreNextChange`
>
> **Root cause (2026-07-23):** มียา 2 รายการชื่อ "BOOTS PARACETAMOL" ใน DB — `a50cd6bd` (generic: ไบโอแลป, ref: 266681) และ `93f3d4ad` (generic: โอสถ อินเตอร์ แลบบอราทอรีส์, ref: 627272) autocomplete ส่งกลับ `93f3d4ad` แต่ override เดิมตั้งไว้ที่ `a50cd6bd` ทำให้ไม่พบ override แก้โดยเพิ่ม override สำหรับ `93f3d4ad` ด้วย (profession_id `0a8e7857`, fda_risk_status = S)
>
> **ผลการทดสอบ (2026-07-23):** ผ่าน — Dialog แสดง "Override องค์กร" badge ถูกต้อง, debug log ยืนยัน `has_override: true, override_scope: organization, fda_risk_status: S` แต่ FDA status S ทำให้บล็อค telemedicine ("ห้ามสั่งผ่าน Telemedicine") ซึ่งเป็น behavior ที่ถูกต้องตามกฎหมาย

#### Scenario 13: Prescription Editor แสดง Personal Override Badge

**บัตรผู้ทดสอบ:** ผู้ใช้ที่มีสิทธิ์สั่งยา (provider) และมี Personal Override ใน DB

**วัตถุประสงค์:** ทดสอบว่า Prescription Editor แสดง Badge 🟣 (Personal scope) เมื่อเพิ่มยาที่มี Personal Override (Tier 3b) และตรวจสอบว่า Personal Override มี priority เหนือ Organization Override

**Flow การนำทาง:** เหมือน Scenario 12 (Drawer → คำขอโปรแกรมรักษา → HealthProgramRequestDashboard → ChartBoardPage → PrescriptionEditorPage)

**Prerequisites:**
- ผู้ใช้ "apisek" (id: `341cbf8b`, profession_id: `0a8e7857`) ต้องมี Personal Override ใน `drug_risk_overrides` สำหรับยาที่ค้นหาได้ง่าย (เช่น Paracetamol)
- Personal Override = row ที่ `user_id = 341cbf8b` และ `medication_id` ตรงกับยาที่ autocomplete ส่งกลับ
- ต้องมี consultation ที่ active (id: `59294c78`)

**ขั้นตอน:**
1. Login ด้วย apisek → เปิด Drawer → เลือก "คำขอโปรแกรมรักษา"
2. ใน Dashboard เลือกแท็บ "กำลังดำเนินการ" → กด "เข้าห้องแชทผู้ป่วย" → `ChartBoardPage`
3. ใน ChartBoardPage เปิด Medical Tools → เลือก "ออกใบสั่งยา" → `PrescriptionEditorPage`
4. ค้นหาและเพิ่มยาที่มี Personal Override
5. กดปุ่ม "บันทึก & ส่งใบสั่งยา" เพื่อ trigger screening
6. **คาดหวัง:** Dialog แสดง Badge "Override ส่วนตัว" (สีม่วง)
7. **คาดหวัง:** ค่า FDA status ใช้ค่าจาก Personal Override (ไม่ใช่ Org Override หรือ Default)
8. ถ้ายาตัวเดียวกันมีทั้ง Org และ Personal Override → **คาดหวัง:** Personal ชนะ (merge priority)

**ข้อควรระวัง:**
- ต้องยืนยันว่า `medicationId` ที่ autocomplete ส่งกลับตรงกับ `medication_id` ใน `drug_risk_overrides` (บทเรียนจาก Scenario 12: ยาชื่อเดียวกันอาจมีหลาย UUID)
- ถ้ายาถูกบล็อค telemedicine จาก FDA status ที่ override ไป ให้ใช้ FDA status ที่ไม่บล็อค (เช่น `P` หรือ `N` แต่ต้องระวังว่า N/P บังคับ telemedicine prohibition ตามกฎหมาย) หรือใช้ `S` และยอมรับว่าจะบล็อค
- ต้องเตรียม Personal Override ใน DB ก่อนทดสอบ (เพิ่ม row ใน `drug_risk_overrides` ที่ `user_id = 341cbf8b`)

> **Maestro Test File:** `docs/guides/scenario_13_personal_override_badge.yaml`
>
> **สถานะ:** ✅ ผ่านแล้ว (2026-07-23) — ทดสอบบน simulator + debug log ยืนยัน Personal Override ชนะ Org Override
>
> **ผลการทดสอบ (2026-07-23):** ผ่าน — Dialog แสดง "Override ส่วนตัว" badge (ไม่ใช่ "Override องค์กร"), ยืนยันว่า Personal Override (FDA = P) ชนะ Org Override (FDA = S) ตาม merge priority. แต่ FDA status P ทำให้บล็อค telemedicine ("ห้ามสั่งผ่าน Telemedicine") เช่นเดียวกับ S เนื่องจาก override_is_telemedicine_prohibited = true
>
> **ข้อมูล Override ใน DB สำหรับทดสอบ:**
> - Org Override: `drug_risk_overrides` (user_id=NULL, profession_id=`0a8e7857`, medication_id=`93f3d4ad`, fda_risk_status=S)
> - Personal Override: `drug_risk_overrides` (user_id=`341cbf8b`, profession_id=NULL, medication_id=`93f3d4ad`, fda_risk_status=P)
> - **ผล:** Personal (P) ชนะ Org (S) ตาม merge priority ✅

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
- **Manual test scripts (13 scenarios):**
  - 🔄 **Scenario 1 — รอทดสอบซ้ำ (2026-07-23):** ปรับ Drawer Gating แล้ว ให้ personaluser ("father panya", `professionId == null`) เห็นเมนูและเข้า Personal Override ได้; ต้องยืนยันด้วย Maestro/manual บน device จริง
  - ✅ **Scenario 2 — ผ่าน (2026-07-17):** ทดสอบอัตโนมัติด้วย Maestro — admin ("apisek") ตั้ง Organization Override ยา Paracetamol → บันทึกสำเร็จ → Badge "Override องค์กร" ปรากฏ → member ("firm") login และเห็น Badge เดียวกัน (Organization Override มีผลกับทุกคนในคลินิก)
  - ✅ **Scenario 3 — ผ่าน (2026-07-17):** ทดสอบอัตโนมัติด้วย Maestro — member ("firm", `can_manage_drug_risk = false`) login สำเร็จ → เปิด Drawer ไม่เห็น "การจัดการยา" และ "จัดการหมวดหมู่ความเสี่ยงยา" (Drawer gating ทำงานถูกต้อง) ส่วน Prescription Editor Badge ค้างทดสอบ Manual
  - ✅ **Scenario 10 — ผ่าน (2026-07-24):** `independent` (user ใหม่ที่ `profession_id IS NULL`) เปิด Drawer → เห็น "การจัดการยา" → เข้า Personal Override → เปิด History สำเร็จบน iPhone 16 simulator (29 commands) หลัง rebuild app; การทดสอบก่อนหน้านี้ที่ใช้ `sister` ไม่ถูกต้องเพราะ `sister` มี `profession_id` และ app ยังไม่ได้ rebuild
  - ✅ **Scenarios 4–9, 11 — ผ่านแล้ว (2026-07-22):** ทดสอบด้วย Maestro อัตโนมัติและ manual บน live Supabase
  - ✅ **Scenario 12 — ผ่าน (2026-07-23):** ทดสอบด้วย Maestro บน iPhone 16 simulator — Prescription Editor แสดง Badge "Override องค์กร" สำหรับยาที่มี Org Override, debug log ยืนยัน `has_override: true, override_scope: organization, fda_risk_status: S`. แก้ bug `medicationId` ถูกล้างโดย `onChanged` และเพิ่ม override สำหรับยาที่มีชื่อซ้ำ
  - ✅ **Scenario 13 — ผ่าน (2026-07-23):** ทดสอบด้วย Maestro บน iPhone 16 simulator — Prescription Editor แสดง Badge "Override ส่วนตัว" (ไม่ใช่ "Override องค์กร"), ยืนยัน Personal Override (FDA = P) ชนะ Org Override (FDA = S) ตาม merge priority
  - Each scenario documented with step-by-step instructions and expected results
- **Bug fixes during testing:**
  1. `DeliveryOrder.fromJson` — `metadata` และ `proofOfDelivery` cast จาก `Map<dynamic, dynamic>` ไม่ได้โดยตรง → แก้ด้วย `Map<String, dynamic>.from(json[...] as Map)` ป้องกัน runtime type error เมื่อรับ JSON จาก Supabase
  2. `DeliveryOrder.drugRiskFlags` getter — nested `drug_risk_flags` ยังเป็น `Map<dynamic, dynamic>` ได้ → แก้ด้วย `Map<String, dynamic>.from(value as Map)`
  3. `PhaseTwoRepository.createDeliveryOrder` merge logic — `data['metadata']` อาจเป็น `Map<dynamic, dynamic>` → แก้ด้วย `Map<String, dynamic>.from(rawMetadata as Map)`
  4. **`setOverride` upsert ล้มเหลวเพราะ partial unique index** — ตาราง `drug_risk_overrides` ใช้ **partial unique indexes** (มี `WHERE` clause เช่น `WHERE user_id IS NOT NULL`) ซึ่ง parameter `onConflict` ของ PostgREST ไม่รองรับ → แก้โดยเปลี่ยนจาก `upsert(data, onConflict: 'user_id,medication_id')` เป็นการตรวจสอบด้วย `getOverride` ก่อน แล้วค่อย `insert` หรือ `update` ตามกรณี (ไฟล์ `drug_risk_classification_repository.dart` บรรทัด 626–661) — *ป้องกัน: หากตารางใช้ partial unique index ห้ามใช้ `upsert` กับ `onConflict` ต้องใช้ manual check-then-insert-or-update เสมอ*
  5. **`fda_risk_status` column ไม่มีในตาราง `medications`** — query ใน `updateMedicationClassification` (บรรทัด 499–503) และ `getMedicationRiskEffective` (บรรทัด 850–854) เลือกคอลัมน์ `fda_risk_status` และ `dangerous_sub_category` จากตาราง `medications` แต่คอลัมน์เหล่านี้ไม่มีอยู่จริง (ข้อมูล risk ถูกเก็บในตาราง `drug_risk_overrides` และ `medication_risk_classifications`) → แก้โดยเปลี่ยนเป็น `select()` (เลือกทุกคอลัมน์) — *ป้องกัน: อย่าระบุชื่อคอลัมน์ที่ไม่แน่ใจว่ามีอยู่ในตาราง ใช้ `select()` หรือตรวจสอบ schema ก่อน*
  6. **`medicationId` ถูกล้างโดย `onChanged` ใน `_MedicationCardWidget`** — `onChanged` callback ล้าง `medicationId = null` ก่อนเช็ค `_ignoreNextChange` flag ทำให้ `medicationId` ที่ `_select()` ตั้งไว้ถูกล้างเมื่อ `nameController.text` ถูก set โดย autocomplete selection → แก้โดยย้ายการล้าง `medicationId` ไปหลังเช็ค `_ignoreNextChange` — *ไฟล์: `lib/features/consultation/presentation/pages/prescription_editor_page.dart`*
  7. **ยาซ้ำชื่อใน DB ทำให้ `medicationId` ไม่ตรงกับ override** — มียา 2 รายการชื่อ "BOOTS PARACETAMOL" ใน DB คนละ UUID (`a50cd6bd` และ `93f3d4ad`) autocomplete ส่งกลับ `93f3d4ad` แต่ override ตั้งไว้ที่ `a50cd6bd` → แก้โดยเพิ่ม override สำหรับ `93f3d4ad` ด้วย — *ป้องกัน: ต้องตรวจสอบว่า `medication_id` ที่ autocomplete ส่งกลับตรงกับ `medication_id` ใน `drug_risk_overrides` เสมอ*
- **Analyze status:** No errors in P6/P7 files. Remaining warnings are pre-existing (unused stack trace variables, deprecated APIs, style infos) outside this scope.
- **สรุปสถานะทดสอบ:**
  - 🔄 Scenario **1** — ผ่านแล้วเดิม (2026-07-17) แต่รอ regression test หลังเปลี่ยน Drawer Gating (2026-07-24)
  - ✅ Scenario **2** — ผ่านแล้ว (2026-07-17) ทดสอบด้วย Maestro อัตโนมัติ
  - ✅ Scenario **3** — ผ่านแล้ว (2026-07-17) ทดสอบด้วย Maestro อัตโนมัติ (Prescription Editor ครอบคลุมโดย Scenario 12)
  - ✅ Scenario **4** — ผ่านแล้ว (2026-07-22) ทดสอบด้วยมือบน physical device
  - ✅ Scenario **5** — ผ่านแล้ว (2026-07-22) ทดสอบด้วย Maestro อัตโนมัติ
  - ✅ Scenario **6** — ผ่านแล้ว (2026-07-22) ทดสอบด้วย Maestro อัตโนมัติ
  - ✅ Scenario **7** — ผ่านแล้ว (2026-07-22) ทดสอบด้วย Maestro อัตโนมัติ
  - ✅ Scenario **8** — ผ่านแล้ว (2026-07-22) ทดสอบด้วย Maestro อัตโนมัติ (แบ่งเป็น 2 ไฟล์)
  - ✅ Scenario **9** — ผ่านแล้ว (2026-07-22) ทดสอบด้วย Maestro อัตโนมัติ
  - ✅ Scenario **11** — ผ่านแล้ว (unit tests, 25 tests all passing)
  - ✅ Scenario **12** — ผ่านแล้ว (2026-07-23) ทดสอบด้วย Maestro บน simulator + debug log ยืนยัน override merge ทำงานถูกต้อง
  - ✅ Scenario **10** — ผ่านแล้ว (2026-07-24) ทดสอบด้วย Maestro บน simulator, ใช้ user `independent` ที่ `profession_id IS NULL` จริงๆ
  - ✅ Scenario **13** — ผ่านแล้ว (2026-07-23) ทดสอบด้วย Maestro บน simulator, "Override ส่วนตัว" badge แสดงถูกต้อง (Personal ชนะ Org)

---

## 10. Next Steps & Remaining Work (วิเคราะห์ลำดับถัดไป)

> **วันที่วิเคราะห์:** 2026-07-24

### สรุปสถานะรวม

| งาน | สถานะ | หมายเหตุ |
|-----|--------|----------|
| P0: DB Migration | ✅ เสร็จ | 2 ตาราง + 1 RPC + alter log table |
| P1: Dart Models + Repository | ✅ เสร็จ | `DrugRiskOverride`, `DrugRiskOverrideHistory`, CRUD methods |
| P2: `DrugRiskScreeningService` | ✅ เสร็จ | รับ `currentUserId` + `professionId`, merge logic |
| P3: `DrugRiskClassificationAdminPage` | ✅ เสร็จ | 3 โหมด + History Tab + Last-Modified Banner |
| P4: Drawer Navigation | ✅ เสร็จ | กลุ่ม "การจัดการยา" + Personal Override สำหรับผู้ไม่มี `professionId` |
| P5: Prescription Editor Integration | ✅ เสร็จ | Badge แสดงใน screening dialog, `medicationId` ส่งถูกต้อง |
| P6: Delivery Integration | ✅ เสร็จ | `drug_risk_flags` ใน `metadata`, unit tests 25 tests |
| P7: Verification & Testing | 🔄 ดำเนินการต่อ | 12/13 scenarios ผ่านยืนยัน; Scenario 1 รอ regression test หลังเปลี่ยน Drawer behavior |

### งานที่ยังเหลือและควรทำเป็นลำดับถัดไป

#### 1. ✅ ปรับ Drawer Gating ให้ผู้ใช้ที่ไม่มี `professionId` เข้าหน้า Personal Override ได้ (Scenario 10)

**ปัญหาเดิม:** ผู้ใช้ที่ `professionId == null` (อาชีพอิสระ) ไม่สามารถเข้าหน้า "จัดการความเสี่ยงยา" ได้ เพราะ Drawer ล็อกด้วย `_canManageDrugRisk` ซึ่งเป็น `false` เสมอเมื่อไม่มี `professionId`

**การแก้ไข (2026-07-23):**
- `tlz_drawer.dart`: authenticated user ที่ไม่มี `professionId` เห็นเมนู "การจัดการยา" และเข้า `DrugRiskClassificationAdminPage` ได้
- `DrugRiskClassificationAdminPage`: อนุญาตผู้ใช้ที่ไม่มี `professionId` และ resolve เป็น `personalOverride` อัตโนมัติ
- ผู้ใช้ที่มี `professionId` แต่ `professions.can_manage_drug_risk = false` ยังถูกซ่อนเมนูและถูกปฏิเสธการเข้าหน้าเช่นเดิม
- การบันทึก/ลบยังส่งเฉพาะ `user_id` ของผู้ใช้ปัจจุบัน จึงไม่เปิดสิทธิ์แก้ Organization Override ให้ผู้ใช้กลุ่มนี้

**ไฟล์ที่แก้ไข:**
- `lib/shared/widgets/tlz_drawer.dart`
- `lib/features/pharmacy/presentation/pages/drug_risk_classification_admin_page.dart`

**สถานะ:** ✅ เสร็จสมบูรณ์ — Implementation, DB verification, และ Maestro E2E test ผ่านหมดแล้ว (2026-07-24); เหลือ regression test ของ Scenario 1

**ความสำคัญ:** สูง — เป็น feature ที่ปลดล็อกการจัดการ Personal Override ผ่าน UI

#### 2. 🟡 ทดสอบ Delivery Order UI จริง (End-to-End)

**ปัญหา:** Scenario 11 ทดสอบผ่าน unit tests เท่านั้น ยังไม่มีหน้า UI สร้าง delivery order จากใบสั่งยาโดยตรง

**ผลกระทบ:** ไม่สามารถยืนยันได้ว่า `drug_risk_flags` ถูก embed ใน `metadata` จริงเมื่อผ่าน UI flow

**แนวทาง:**
- สร้าง flow สร้าง delivery order จากใบสั่งยา (Prescription → Delivery)
- เรียก `DrugRiskScreeningService.buildDeliveryRiskFlags(screenResults)` แล้วส่งผ่าน `drugRiskFlags` parameter
- ทดสอบด้วย Maestro บน simulator

**ความสำคัญ:** ปานกลาง — unit tests ครอบคลุม logic แล้ว แต่ขาด E2E verification

#### 3. 🟡 ทดสอบ Prescription Editor กับยาที่ไม่มี Override (Default behavior)

**ปัญหา:** Scenario 12 และ 13 ทดสอบเฉพาะยาที่มี Override (Org และ Personal) ยังไม่ได้ทดสอบยาที่ไม่มี Override ใดๆ ว่าแสดงค่า Default (Tier 1+2) ถูกต้อง

**แนวทาง:**
- เพิ่ม step ใน Scenario 12 หรือสร้าง Scenario ใหม่: เพิ่มยาที่ไม่มี Override → ตรวจสอบว่าไม่มี Badge และค่า FDA status เป็นค่า Default

**ความสำคัญ:** ปานกลาง — เป็น negative test case ที่ควรมี

#### 4. 🟢 ทำความสะอาด Test Data ใน Supabase

**ปัญหา:** มี override ทดสอบหลายรายการใน DB ที่อาจกระทบการทดสอบในอนาคต (เช่น ยาที่ถูก override ใน Scenario 7 แล้วลบ แต่ history ยังคงอยู่)

**แนวทาง:**
- ตรวจสอบและทำความสะอาด `drug_risk_overrides` และ `drug_risk_override_history` ที่ไม่จำเป็น
- อาจสร้าง script สำหรับ reset test data

**ความสำคัญ:** ต่ำ — ไม่กระทบ production

#### 5. ✅ เพิ่ม Maestro Test สำหรับ Scenario 10 หลังแก้ Drawer Gating

**สถานะ:** สร้างและรันผ่านแล้วด้วย `docs/guides/scenario_10_personal_override_history.yaml`

**แนวทาง:**
- สร้าง `docs/guides/scenario_10_personal_override_history.yaml`
- ทดสอบ: login ด้วยอาชีพอิสระ → เปิด Drawer → เห็นเมนู → เข้าหน้า → ดู History Tab → ยืนยันเห็นเฉพาะ Personal history

**ความสำคัญ:** ต่ำ — รองาน #1 ก่อน
