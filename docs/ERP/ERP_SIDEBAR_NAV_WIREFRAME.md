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
