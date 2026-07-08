# ERP Sidebar Nav Items — Device & Orientation Wireframes

ร่าง Nav Items ใน Collapsible Sidebar ตามอุปกรณ์ (Mobile/Tablet/Desktop) และแนวตั้ง/แนวนอน โดยรองรับทั้ง Light/Dark Theme + Badge + Active State

> **Light mode update:** ใช้ drawer โทน natural pastel + active pill แบบนุ่ม และสอดคล้องกับ dashboard mixed-size cards

---

## 1. Mobile Portrait (Collapsed — 56dp)

```
┌────┐
│ 🏢 │  ← Logo (28x28)
│  > │  ← Toggle Button (amber)
├────┤
│ 📊 │  ← Dashboard (icon only)
│ 🛒 │  ← POS
│ 📦 │  ← Inventory
│ 👥 │  ← HR
│ 💰 │  ← Accounting
│ 📊 │  ← CRM
│ 🔔 │  ← Notifications (badge ซ่อนใน collapsed)
│ 💬 │  ← Messages
│ ⚙️ │  ← Settings
│    │
│ 💡 │  ← Promo (icon อย่างเดียว)
│ 🔗 │  ← External Link
└────┘
 56dp
```

**ลักษณะ:**
- Icon อย่างเดียว (24dp)
- Active: pill shape ขาวนวล/ฟ้าอ่อน (bg `#FFFFFF` หรือ `#F8FBFF`, text `primaryColor`)
- Badge ซ่อน (แสดงแค่จุดสีแดงเล็กๆ มุมขวาบน)
- Long-press → Tooltip ชื่อ nav item

---

## 2. Mobile Portrait (Expanded — 240dp)

```
┌────────────────┐
│ 🏢 คลินิกหมอสมชาย  < │  ← Logo + Name + Toggle
├────────────────┤
│ 📊 Dashboard       │  ← Icon + Label + active pill
│ 🛒 POS            │
│ 📦 Inventory     │
│ 👥 HR             │
│ 💰 Accounting    │
│ 📊 CRM          🔴2│  ← Icon + Label + Badge (56)
│ 🔔 Notifications🔴5│
│ 💬 Messages     🔴45│
│ ⚙️ Settings        │
│                │
│ ┌────────────┐ │
│ │ 💡 Upgrade │ │  ← Promo Card (expanded)
│ │ สมัคร Premium│ │
│ │ [Upgrade →] │ │
│ └────────────┘ │
│ 🔗 External    │  ← Icon + Label
└────────────────┘
      240dp
```

---

## 3. Mobile Landscape (Mini Rail — 56dp)

```
┌────┬────────────────────────────────────┐
│ 🏢 │                                    │
│  > │                                    │
├────┤                                    │
│ 📊 │                                    │
│ 🛒 │                                    │
│ 📦 │         Main Content Area          │
│ 👥 │                                    │
│ 💰 │                                    │
│ 📊 │                                    │
│ 🔔 │                                    │
│ 💬 │                                    │
│ ⚙️ │                                    │
│    │                                    │
│ 💡 │                                    │
│ 🔗 │                                    │
└────┴────────────────────────────────────┘
 56dp
```

**ลักษณะ:**
- Persistent mini rail (ไม่ซ่อน)
- Icon อย่างเดียว
- Hover/long-press → Tooltip ชื่อ
- เนื้อหาอยู่ขวาเต็มจอ

---

## 4. Tablet Portrait (Expanded Overlay — 240dp)

```
┌────────────────┬─────────────────────────────┐
│ 🏢 คลินิกหมอสมชาย  < │  [Overlay ปกคลุม 70%]      │
├────────────────┤  [Main Content มืด]        │
│ 📊 Dashboard     │                            │
│ 🛒 POS          │                            │
│ 📦 Inventory    │                            │
│ 👥 HR           │                            │
│ 💰 Accounting   │                            │
│ 📊 CRM        🔴2│                            │
│ 🔔 Notif      🔴5│                            │
│ 💬 Messages   🔴45│                            │
│ ⚙️ Settings     │                            │
│                │                            │
│ [Promo Card]   │                            │
│ 🔗 External    │                            │
└────────────────┴─────────────────────────────┘
      240dp          กด overlay → ปิด sidebar
```

**ลักษณะ:**
- Overlay ปกคลุม 70% จอ (backdrop soft dim)
- กดพื้นที่ว่าง → ปิด sidebar
- แสดง label + badge ครบ

---

## 5. Tablet Landscape (Persistent Expandable)

```
State A: Collapsed (56dp)          State B: Expanded (240dp)
┌────┬───────────────┐            ┌────────────────┬───────────┐
│ 🏢 │               │            │ 🏢 คลินิก  <   │           │
│  > │               │            ├────────────────┤           │
├────┤               │            │ 📊 Dashboard   │           │
│ 📊 │               │            │ 🛒 POS         │           │
│ 🛒 │               │            │ 📦 Inventory   │           │
│ 📦 │   Main        │            │ 👥 HR          │           │
│ 👥 │   Content     │     ──►    │ 💰 Accounting  │  Content  │
│ 💰 │   (Full)      │            │ 📊 CRM      🔴2│           │
│ 📊 │               │            │ 🔔 Notif    🔴5│           │
│ 🔔 │               │            │ 💬 Messages 🔴45│           │
│ 💬 │               │            │ ⚙️ Settings    │           │
│ ⚙️ │               │            │                │           │
│    │               │            │ [Promo Card]   │           │
│ 💡 │               │            │ 🔗 External    │           │
│ 🔗 │               │            └────────────────┴───────────┘
└────┴───────────────┘
```

---

## 6. Desktop (Persistent Expanded — 240dp)

```
┌────────────────┬──────────────────────────────────────────────────┐
│ 🏢 คลินิกหมอสมชาย  < │  🏢 คลินิกหมอสมชาย  [Branch ▼]  🔔 2  💬 5  ⚙️  │
├────────────────┤                                                    │
│ 📊 Dashboard     │  ┌────────────────────────────────────────────┐   │
│   └─ Overview   │  │                                            │   │
│   └─ Analytics  │  │         Main Content Area                    │   │
│ 🛒 POS           │  │         (Navigation Hub)                     │   │
│   └─ Products   │  │                                            │   │
│   └─ Sales      │  │                                            │   │
│ 📦 Inventory    │  │                                            │   │
│   └─ Stock      │  └────────────────────────────────────────────┘   │
│   └─ Orders     │                                                    │
│ 👥 HR           │                                                    │
│   └─ Staff      │                                                    │
│   └─ Payroll    │                                                    │
│ 💰 Accounting   │                                                    │
│   └─ Ledger     │                                                    │
│   └─ Reports    │                                                    │
│ 📊 CRM       🔴2│                                                    │
│   └─ Customers  │                                                    │
│   └─ Appointments│                                                   │
│ 🔔 Notif     🔴5│                                                    │
│ 💬 Messages  🔴45│                                                    │
│ ⚙️ Settings      │                                                    │
│   └─ Theme      │                                                    │
│   └─ Permissions│                                                    │
│                │                                                    │
│ [Promo Card]   │                                                    │
│ 🔗 External    │                                                    │
└────────────────┴──────────────────────────────────────────────────┘
      240dp
```

**ลักษณะ:**
- Expanded ตลอดเวลา
- **Sub-menu** (dropdown/expandable) บาง nav items
- Badge แสดงเต็ม
- Promo card แสดงเต็ม
- ไม่มี overlay — เนื้อหาอยู่ขวาเสมอ

---

## 7. Nav Item States (Light Theme)

```
┌──────────────────────────┐
│  INACTIVE (Collapsed)    │
│  ┌────┐                  │
│  │ 📊 │  ← Icon: white 70% opacity│
│  └────┘                  │
│                          │
│  ACTIVE (Collapsed)      │
│  ┌────┐                  │
│  │ 📊 │  ← Icon: primaryColor│
│  └────┘                  │
│   bg: white pill         │
│                          │
│  INACTIVE (Expanded)     │
│  ┌────────────────┐      │
│  │ 📊 Dashboard     │  ← Icon: white 70% + Label: white│
│  └────────────────┘      │
│                          │
│  ACTIVE (Expanded)       │
│  ┌────────────────┐      │
│  │ 📊 Dashboard     │  ← Icon: primaryColor + Label: primaryColor│
│  └────────────────┘      │
│   bg: white pill         │
│                          │
│  WITH BADGE (Expanded)   │
│  ┌────────────────────┐  │
│  │ 🔔 Notifications  🔴56│  ← Label + Badge (red bg, white text)│
│  └────────────────────┘  │
│                          │
│  WITH BADGE (Collapsed)  │
│  ┌────┐                  │
│  │ 🔔 │  ← Icon + จุดแดงเล็กๆ มุมขวาบน│
│  └────┘                  │
└──────────────────────────┘
```

---

## 8. Nav Item States (Dark Theme)

```
┌──────────────────────────┐
│  INACTIVE (Collapsed)    │
│  ┌────┐                  │
│  │ 📊 │  ← Icon: white 50% opacity│
│  └────┘                  │
│                          │
│  ACTIVE (Collapsed)      │
│  ┌────┐                  │
│  │ 📊 │  ← Icon: #CCFF00 (lime)│
│  └────┘                  │
│   bg: #1A1A1A pill       │
│                          │
│  INACTIVE (Expanded)     │
│  ┌────────────────┐      │
│  │ 📊 Dashboard     │  ← Icon: white 50% + Label: white 50%│
│  └────────────────┘      │
│                          │
│  ACTIVE (Expanded)       │
│  ┌────────────────┐      │
│  │ 📊 Dashboard     │  ← Icon: #CCFF00 + Label: #CCFF00│
│  └────────────────┘      │
│   bg: #1A1A1A pill       │
│   border: #CCFF00 0.5px  │
└──────────────────────────┘
```

---

## 9. Nav Items List (ERP Modules)

```
| Icon | Label          | Route            | Badge Source       | Sub-items |
|------|----------------|------------------|--------------------|-----------|
| 📊   | Dashboard      | /erp/dashboard   | -                  | -         |
| 🛒   | POS            | /erp/pos         | -                  | Products, Sales |
| 📦   | Inventory      | /erp/inventory   | สต๊อกใกล้หมด      | Stock, Orders |
| 👥   | HR             | /erp/hr          | -                  | Staff, Payroll |
| 💰   | Accounting     | /erp/accounting  | ใบเสร็จรออนุมัติ  | Ledger, Reports |
| 📊   | CRM            | /erp/crm         | นัดหมายใหม่       | Customers, Appointments |
| 🔔   | Notifications  | /erp/notifications| ยังไม่อ่าน (ทุกโมดูล) | -         |
| 💬   | Messages       | /erp/messages    | ข้อความใหม่      | -         |
| ⚙️   | Settings       | /erp/settings    | -                  | Theme, Permissions, Branch |
| 🏥   | HIS            | /erp/his         | 🔒 (ถ้าไม่มีสิทธิ์)| -         |
| 🔬   | LIS            | /erp/lis         | 🔒                 | -         |
| 📞   | Telemedicine   | /erp/telemedicine| 🔒                 | -         |
| 🚚   | Logistics      | /erp/logistics   | 🔒                 | -         |
| 🛍️   | Commerce       | /erp/commerce    | 🔒                 | -         |
```

---

## 10. Responsive Behavior Summary

| Device | Orientation | Sidebar Width | Mode | Label | Badge | Sub-menu |
|--------|-------------|---------------|------|-------|-------|----------|
| **Mobile** | Portrait | 56dp → 240dp | Overlay + Expandable | Hidden → Visible | Dot → Number | No |
| **Mobile** | Landscape | 56dp | Persistent Mini Rail | Tooltip | Dot | No |
| **Tablet** | Portrait | 56dp → 240dp | Overlay + Expandable | Hidden → Visible | Dot → Number | No |
| **Tablet** | Landscape | 56dp → 240dp | Persistent Expandable | Hidden → Visible | Dot → Number | No |
| **Desktop** | Any | 240dp | Persistent Expanded | Visible | Number | Yes |

---

## 11. Animation Specs

| Action | Duration | Curve |
|--------|----------|-------|
| Expand/Collapse sidebar | 300ms | `Curves.easeInOut` |
| Active item bg (pill) | 200ms | `Curves.easeOut` |
| Badge appear | 150ms | `Curves.elasticOut` |
| Sub-menu expand | 250ms | `Curves.easeInOut` |
| Toggle button rotate | 300ms | `Curves.easeInOut` |

---

## 12. Accessibility

- **Minimum touch target:** 48dp (icon 24dp + padding 12dp)
- **Screen reader:** "POS, 2 notifications, button" (announce badge count)
- **High contrast:** Active item border 2px + text shadow
- **Reduced motion:** ปิด animation ถ้า user ตั้งค่า accessibility

---

## 13. Overflow Issue — Root Cause & Fix (Mini Sidebar)

### Problem
เมื่อ Mini Sidebar อยู่ในสถานะ **Collapsed (ย่อสุด)** ปรากฏข้อผิดพลาด `Right Overflowed by 1.00 pixels` ตามแนวแกนด้านขวา

### Root Cause
การคำนวณพื้นที่ใช้งานภายใน sidebar ขณะย่อสุดมีการใช้พื้นที่เกินกว่าที่กำหนดไว้ โดยมีปัจจัยดังนี้:

1. **ความกว้าง sidebar ย่อสุด:** `56dp`
2. **เส้นขอบด้านขวา (Border):** หนา `1dp` → พื้นที่เนื้อหาจริงเหลือ `55dp`
3. **Padding แนวนอนของ `_MiniNavItem`:** ซ้าย `8dp` + ขวา `8dp` = `16dp`
4. **พื้นที่เนื้อหาภายในที่เหลือ:** `55 - 16 = 39dp`
5. **กล่องไอคอน (`SizedBox`):** กว้าง `40dp`

**ผลลัพธ์:** กล่องไอคอน `40dp` ถูกวางในพื้นที่ที่เหลือเพียง `39dp` ทำให้เกิด **Overflow 1.00 pixel พอดีเป๊ะ** บนหน้าจอบางเครื่องที่มีการปัดเศษพิกเซล (Fractional Rounding Errors)

### Solution
แก้ไขโดยปรับขนาดและระยะห่างให้ปลอดภัยจากเศษทศนิยมพิกเซล:

1. **เพิ่มความกว้าง Mini Sidebar:** จาก `56dp` → `60dp`
   ```dart
   static const double _collapsedWidth = 60; // จาก 56
   ```
   ทำให้พื้นที่เนื้อหาภายในหลังหัก border มี `59dp` (ปลอดภัยกว่า)

2. **ปรับ Padding แนวนอนแบบไดนามิก:**
   - ตอนย่อ (`collapsed`): `6dp` ซ้าย/ขวา (รวม `12dp`)
   - ตอนขยาย (`expanded`): `8dp` ซ้าย/ขวา (รวม `16dp`)
   ```dart
   padding: EdgeInsets.symmetric(
     horizontal: isExpanded ? 8 : 6,
     vertical: 3,
   ),
   ```

3. **ผลลัพธ์หลังแก้ไข:**
   - พื้นที่เนื้อหาตอนย่อ: `60 - 1 (border) - 12 (padding) = 47dp`
   - กล่องไอคอน `40dp` อยู่ในพื้นที่ `47dp` → **ปลอดภัย มีระยะหายใจ `7dp`**
   - ไม่เกิด Overflow อีกต่อไป

### Prevention Checklist
- [ ] ตรวจสอบว่าผลรวมของ `padding + content width + border` ไม่เกินความกว้าง container
- [ ] ใช้ `LayoutBuilder` เพื่อวัดพื้นที่จริงก่อนแสดง expanded content
- [ ] ใช้ `ClipRect` + `OverflowBox` ครอบส่วนที่มีขนาดคงที่เพื่อป้องกัน reflow ตอน animation
- [ ] ทดสอบบนหน้าจอที่มีความละเอียดต่าง ๆ (DPI ต่างกัน) เพราะการปัดเศษพิกเซลอาจทำให้ overflow

---

## 14. Expanded Sidebar Items Hidden — Root Cause & Fix (2026-07-06)

### Problem
เมื่อขยาย Sidebar (Expanded) แล้วไม่พบ:
- Sub-menu ใต้ **HR Management** (เงินเดือน, พนักงาน, ตั้งค่า HR)
- ปุ่ม **ตั้งค่า** ลัดด้านบน
- ส่วน **Settings** ด้านล่าง (ธีมสี Dashboard, ความโปร่งใส, ตั้งค่าองค์กร, กลับหน้า Home)

### Root Cause
`showExpandedContent` ถูกกำหนดด้วยเงื่อนไข 2 ตัว:

```dart
final sidebarWidth = constraints.maxWidth;
final showExpandedContent = widget.isExpanded && sidebarWidth >= _expandedWidth;
```

- `_expandedWidth = 240.0`
- บนอุปกรณ์จริง ค่าความกว้างที่ `LayoutBuilder` รายงานอาจเป็น `239.999...` หรือไม่ถึง `240` เนื่องจาก **pixel rounding / device pixel ratio / SafeArea padding** ทำให้ `sidebarWidth >= _expandedWidth` เป็น `false` ตลอด
- ผล: ทุกเนื้อหาที่ render ภายใต้ `if (showExpandedContent)` หายไปทั้งหมด

### Solution
ยกเลิกการเช็คความกว้าง ใช้เฉพาะสถานะ toggle เพราะ container มี width คงที่อยู่แล้ว:

```dart
// lib/ERP Dashboard/erp_mini_sidebar.dart
final showExpandedContent = widget.isExpanded;
```

### Prevention Checklist
- [ ] ไม่ใช้ `LayoutBuilder` วัด width แล้วเทียบกับค่าคงที่แบบ `>=` เพื่อตัดสินใจแสดงเนื้อหา
- [ ] ถ้าต้องใช้ width threshold ให้ใช้ช่วง tolerance เช่น `sidebarWidth > _expandedWidth - 10` หรือใช้สัดส่วน
- [ ] ทดสอบ sidebar บน device จริง ไม่ใช่แค่ emulator
- [ ] ถ้า container มี width คงที่ (AnimatedContainer กำหนด `width` เอง) ให้ rely บน state ของ toggle

---

## 15. Dashboard Modules Falling Into "ไม่มีกลุ่ม" — Root Cause & Fix

### Problem
Module ใหม่ที่เพิ่มใน `DashboardModuleLayoutConfig.defaultLayout()` (เช่น `payroll`, `hr_settings`) แสดงอยู่ในกลุ่ม **"ไม่มีกลุ่ม"** แทนที่จะอยู่ในกลุ่ม **บุคคล** ตามที่ default layout กำหนด

### Root Cause
1. ผู้ใช้มี layout ที่บันทึกไว้ใน `dashboard_theme.module_layout_json` ก่อน module ใหม่ถูกเพิ่ม
2. หน้า Dashboard เรียก `DashboardModuleLayoutConfig.fromJson(...)` โดยตรง โดยไม่ผ่าน `normalize()`:

```dart
// lib/ERP Dashboard/erp_dashboard_page.dart
final layout = theme?.moduleLayoutJson != null
    ? DashboardModuleLayoutConfig.fromJson(theme!.moduleLayoutJson)
    : DashboardModuleLayoutConfig.defaultLayout();
```

3. `_groupModules()` จับ module ที่ไม่ได้อยู่ใน group ใด ๆ โยนเข้า fallback group `ไม่มีกลุ่ม`

### Solution
1. เพิ่ม `normalize()` ใน `DashboardModuleLayoutConfig` เพื่อ auto-assign module ที่ขาดกลับเข้า default group:

```dart
// lib/features/erp/data/models/dashboard_module_layout.dart
DashboardModuleLayoutConfig normalize() {
  final defaultGroups = defaultLayout().groups;
  final defaultGroupByModuleId = <String, String>{};
  for (final def in dashboardModuleDefinitions) {
    defaultGroupByModuleId[def.id] = def.defaultGroupId;
  }

  final nextGroups = defaultGroups.map((defaultGroup) {
    final existingGroup = groupById(defaultGroup.id);
    final existingModules = existingGroup?.moduleIds.toSet() ?? <String>{};
    final normalizedModules = defaultGroup.moduleIds.toList();

    // ย้าย module ที่ default อยู่กลุ่มนี้ แต่ถูกบันทึกไว้ที่อื่น กลับมาที่นี่
    for (final moduleId in defaultGroup.moduleIds) {
      if (defaultGroupByModuleId[moduleId] == defaultGroup.id) {
        if (!normalizedModules.contains(moduleId)) {
          normalizedModules.add(moduleId);
        }
      }
    }

    // เก็บ module ที่ user จัดวางไว้ในกลุ่มนี้ (แต่ไม่ใช่ default) ไว้ก่อน
    for (final moduleId in existingModules) {
      if (!normalizedModules.contains(moduleId) &&
          groupForModule(moduleId)?.id == defaultGroup.id) {
        normalizedModules.add(moduleId);
      }
    }

    return defaultGroup.copyWith(moduleIds: normalizedModules);
  }).toList();

  return DashboardModuleLayoutConfig(groups: nextGroups);
}
```

2. เรียก `.normalize()` ทุกจุดที่โหลด layout จาก database:

```dart
// lib/ERP Dashboard/erp_dashboard_page.dart
final layout = theme?.moduleLayoutJson != null
    ? DashboardModuleLayoutConfig.fromJson(theme!.moduleLayoutJson).normalize()
    : DashboardModuleLayoutConfig.defaultLayout();
```

```dart
// lib/features/erp/presentation/providers/dashboard_theme_provider.dart
DashboardModuleLayoutConfig get moduleLayout {
  final theme = state.theme;
  if (theme?.moduleLayoutJson == null) {
    return DashboardModuleLayoutConfig.defaultLayout();
  }
  return DashboardModuleLayoutConfig.fromJson(theme!.moduleLayoutJson).normalize();
}
```

### Prevention Checklist
- [ ] ทุกการเรียก `fromJson` ของ module layout ต้องผ่าน `normalize()` ก่อนใช้
- [ ] เมื่อเพิ่ม module ใหม่ใน `dashboardModuleDefinitions` ต้องระบุ `defaultGroupId` ให้ถูกต้อง
- [ ] ทดสอบกับ user ที่มี layout เก่าบันทึกไว้ใน database ไม่ใช่แค่ default layout
- [ ] ถ้าเปลี่ยน default layout ที่มีผลกับ user เก่า ให้เพิ่ม migration/normalization หรือ reset flow

---

## 16. Current ERP Mini Sidebar Structure (2026-07-06)

### Main Items (always visible)
- หน้าหลัก (`/erp/dashboard`)
- POS Management (disabled)
- Inventory Management (disabled)
- Procurement Management (disabled)
- Accounting Management (disabled)
- HR Management → นำไป `/erp/payroll`
- CRM Management (disabled)
- KPI / Analytics (`/kpi/dashboard`)

### HR Management Sub-menu (when expanded)
- เงินเดือน (Payroll) → `/erp/payroll`
- พนักงาน → `/erp/employees`
- ตั้งค่า HR → `/erp/hr-settings`

### Settings (when expanded)
- ปุ่ม **ตั้งค่า** ด้านบน → เปิด Bottom Sheet
  - จัดการกลุ่มการ์ด (`/erp/settings/modules`)
  - ธีมสี Dashboard (`/erp/settings/theme`)
  - ความโปร่งใส (Glass) (`/erp/settings/glass`)
  - ตั้งค่าองค์กร (`/erp/settings`)
- ธีมสี Dashboard (`/erp/settings/theme`)
- ความโปร่งใส (Glass) (`/erp/settings/glass`)
- ตั้งค่าองค์กร (`/erp/settings`)
- กลับหน้า Home (`/home`)

### Bottom Promo
- Upgrade to AI card (expanded) / icon (collapsed)
