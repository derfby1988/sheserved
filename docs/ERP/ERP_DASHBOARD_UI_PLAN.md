# ERP Dashboard UI/UX Plan — Unified

แผนรวมเดียวสำหรับ UX/UI ของ ERP Dashboard รวม Glassmorphism + Light/Dark Theme + Collapsible Sidebar Navigation

> **⚑ Single Source of Truth (SSOT):** เอกสารฉบับนี้เป็น **แหล่งอ้างอิง UI เดียว** สำหรับทุกหน้าจอในระบบ ERP เอกสาร `ERP_GLASSMORPHISM_PLAN.md`, `ERP_LIGHT_DARK_THEME_PLAN.md`, `ERP_SIDEBAR_NAV_WIREFRAME.md` ถูก **รวม (merged)** เข้ามาในฉบับนี้แล้ว — เก็บไว้เป็น archive สำหรับ wireframe/implementation notes เท่านั้น **ห้ามนิยามสี, opacity, blur, radius, spacing หรือ sidebar width ซ้ำ** ในแผนโมดูลอื่น — ให้อ้างอิง Design Tokens ในเอกสารนี้เสมอ

> **Design direction update:** Light mode ใช้โทน **iOS natural pastel** ตาม reference image และเปลี่ยน dashboard overview ให้เป็น **mixed-size responsive module board** ที่มีทั้ง square, capsule และ rounded cards

---

## 1. โครงสร้างธีม (Light / Dark)

| โหมด | Presets | ปรับแต่งได้ | รายละเอียด |
|------|---------|-----------|-----------|
| **Light** | 8 + custom | ✅ | `sheserved_default`, `ocean_blue`, `sunset_orange`, `forest_green`, `royal_purple`, `midnight_black`, `coral_pink`, `custom` |
| **Dark** | 1 preset | ❌ (fixed) | `sheserved_dark` — Lime Green accent (`#CCFF00`) |

### สี Dark Theme (คงที่)

| Token | ค่า |
|-------|-----|
| `primary` | `#0F0F0F` |
| `accent` | `#CCFF00` |
| `surface` | `#1A1A1A` |
| `text_primary` | `#FFFFFF` |
| `text_secondary` | `rgba(255,255,255,0.5)` |
| `error` | `#EF4444` |
| `card_bg` | `#1A1A1A` |

---

## 2. Glassmorphism (แก้วโปร่งใส)

| ส่วน | Default Opacity | Blur | Border |
|------|-----------------|------|--------|
| **Sidebar** | 12% | 12px | 1.5px ขาว |
| **Module Cards** | 12% | 12px | 1.5px ขาว |
| **Dialogs** | 12% | 12px | 1.5px ขาว |
| **Notification Panel** | 12% | 12px | 1.5px ขาว |

**ช่วงปรับ:** 0-50% (slider ละเอียด 1%) + Blur 2-20px

### Natural Pastel Light Mode

- **พื้นหลัง:** ฟ้าอ่อน + เขียวอ่อน + ม่วงอ่อน แบบ gradient หลวม ๆ พร้อม blob เบลอด้านหลัง (`#DFF8FF` → `#DFF7E8` → `#F4E4FB`)
- **AppBar:** transparent (`backgroundColor: Colors.transparent`, `elevation: 0`, `extendBodyBehindAppBar: true`) — ไม่มีสีทึบ เห็น gradient พื้นหลังผ่านมา
- **AppBar title:** `ERP Dashboard` แบบ compact; ถ้ามีหลายสาขาให้แสดงชื่อสาขาที่เลือกเป็น subtitle 1 บรรทัดใต้ title
- **AppBar icons/text (Light):** icon สีน้ำเงิน `#4F7DF3`, text สีเทาเข้ม `#1D2733`
- **AppBar icons/text (Dark):** icon + text สี lime `#CCFF00`
- **Branch selector:** อยู่ใน AppBar actions แบบ pill สีอ่อน `#F5FBFF` + border ฟ้าอ่อน `#D7E8F6`, radius 999px
- **Dashboard body:** แสดง module board โดยตรง; ไม่ render organization header card ซ้ำใต้ AppBar
- **Cards:** ใช้ `GlassCard` แบบมี inner shine, shadow นุ่ม และ tint เฉพาะการ์ด
- **Typography:** ข้อความอยู่กึ่งกลางภายในการ์ด แต่ยังคงลำดับสายตาชัดเจน
- **Shape language:** เน้นวงกลม, capsule, rounded square มากกว่ากรอบเหลี่ยมแข็ง

---

## 3. Collapsible Sidebar (Nav Items)

### Responsive Behavior

| Device | Orientation | Width | Mode |
|--------|-------------|-------|------|
| **Mobile** | Portrait | 60dp → 240dp | Overlay + Expandable |
| **Mobile** | Landscape | 60dp | Persistent Mini Rail |
| **Tablet** | Portrait | 60dp → 240dp | Overlay + Expandable |
| **Tablet** | Landscape | 60dp → 240dp | Persistent Expandable |
| **Desktop** | Any | 240dp | Persistent Expanded |

> **หมายเหตุ:** Collapsed width ใช้ **60dp** (แก้จาก 56dp เดิม) เพื่อแก้ Right Overflow 1px จาก `border 1dp + padding 12dp + icon 40dp` — ดู root cause ใน `ERP_SIDEBAR_NAV_WIREFRAME.md` section 13 (archive)

### Dashboard Overview Layout

- **Mobile portrait:** 2-column responsive board, mixed-size cards (บางการ์ด span 2 columns)
- **Tablet:** 3-column board, มี wide capsule cards แทรกเพื่อสร้างจังหวะสายตา
- **Desktop:** 4-column board, mix ระหว่าง square / capsule / hero tile
- **Tile spacing:** 10px สำหรับ 2 columns, 11px สำหรับ 3+ columns
- **Proportions:** square tile ~0.96, capsule tile ~0.68, hero/tall tile ~1.42
- **Radius:** square 30px, capsule 999px, tall/hero 36px
- **Tile behavior:** icon bubble ถูกวางกึ่งกลางด้านบน, label อยู่กึ่งกลาง, card content ใช้ glass glow ตามสีพาสเทลของแต่ละโมดูล

### Nav Items

> รายการ nav items กำหนดจาก **Module Catalog เดียว** (`dashboardModuleDefinitions` — ดู section 12) เท่านั้น ไม่มีรายการ hardcode ในเอกสาร
> สถานะปัจจุบัน (2026-07-06): implement แล้ว ~8 items (หน้าหลัก, POS, Inventory, Procurement, Accounting, HR + sub-menu Payroll/พนักงาน/ตั้งค่า HR, CRM, KPI/Analytics) — ที่เหลือเป็น disabled/locked ตาม section 13 — อ้างอิง `ERP_SIDEBAR_NAV_WIREFRAME.md` section 16 (archive)

### Active State

- **Light:** ขาว pill bg + primaryColor text
- **Dark:** `#1A1A1A` pill bg + `#CCFF00` lime text

---

## 4. ฐานข้อมูล

### ตาราง `theme_presets`

```sql
CREATE TABLE theme_presets (
  preset_key TEXT PRIMARY KEY,
  preset_name_th TEXT NOT NULL,
  preset_name_en TEXT NOT NULL,
  primary_color TEXT NOT NULL,
  accent_color TEXT NOT NULL,
  surface_color TEXT NOT NULL,
  text_primary TEXT NOT NULL,
  text_secondary TEXT NOT NULL,
  error_color TEXT NOT NULL,
  card_bg TEXT,
  card_text TEXT,
  is_active BOOLEAN DEFAULT true
);
```

### ตาราง `user_dashboard_themes`

```sql
CREATE TABLE user_dashboard_themes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  profession_id UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  theme_preset TEXT DEFAULT 'sheserved_default',
  is_dark_mode BOOLEAN DEFAULT false,
  -- Custom colors (ใช้เมื่อ theme_preset = 'custom')
  custom_primary TEXT,
  custom_accent TEXT,
  custom_surface TEXT,
  custom_text_primary TEXT,
  custom_text_secondary TEXT,
  custom_error TEXT,
  -- Glassmorphism settings
  glass_opacity_sidebar DECIMAL(5,4) DEFAULT 0.12,
  glass_opacity_cards DECIMAL(5,4) DEFAULT 0.12,
  glass_opacity_dialog DECIMAL(5,4) DEFAULT 0.12,
  glass_blur_level INTEGER DEFAULT 12,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, profession_id)
);
```

---

## 5. Flutter Architecture

```
lib/features/erp/
├── data/
│   ├── models/
│   │   ├── dashboard_theme.dart      # Theme model
│   │   ├── dashboard_module_layout.dart # Dashboard module grouping/layout model
│   │   └── theme_preset.dart         # Preset model
│   └── repositories/
│       └── dashboard_theme_repository.dart  # DB operations
├── presentation/
│   ├── providers/
│   │   └── dashboard_theme_provider.dart    # Riverpod StateNotifier
│   ├── widgets/
│   │   ├── glass_card.dart           # GlassCard widget
│   │   ├── glass_sidebar.dart        # GlassSidebar widget
│   │   ├── glass_dialog.dart         # showGlassDialog helper
│   │   ├── glass_opacity_slider.dart # Opacity slider widget
│   │   └── glass_preview_box.dart   # Preview box widget
│   └── pages/
│       ├── theme_settings_page.dart       # Theme settings
│       ├── module_layout_settings_page.dart # Module grouping/color management
│       └── glassmorphism_settings_page.dart # Glass settings
```

---

## 6. หน้า Settings

### Theme Settings (`/erp/settings/theme`)

- Toggle Light/Dark
- Light: 8 preset color circles + Custom color picker
- Dark: Fixed preset display (ไม่ให้ปรับ)
- ปุ่ม 💾 บันทึก / ❌ คืนค่าเริ่มต้น
- มี shortcut ไปยังหน้า **Module Layout Settings** สำหรับจัดการการ์ดและกลุ่ม

### Module Layout Settings (`/erp/settings/modules`)

- เปลี่ยนชื่อกลุ่มได้
- รีเซตชื่อกลุ่มกลับค่าเริ่มต้นได้
- รีเซตเฉพาะกลุ่มกลับค่าเริ่มต้นได้ โดยคงการ์ดในกลุ่มไว้
- รีเซตสีของทุกกลุ่มกลับ default ได้
- รีเซต layout ทั้งหมดกลับ default ได้
- drag-and-drop ย้ายการ์ดข้ามกลุ่ม
- **สีพื้นหลังการ์ดกลุ่ม:** เลือกสีพาสเทลหรือเลือก "ไม่มีสีพื้นหลังการ์ด" → กลุ่มจะไม่ห่อด้วย `GlassCard` (ไม่มีพื้นหลังแก้วและเงา)
- **สีชื่อกลุ่ม:** เลือกสีอิสระสำหรับจุดวงกลม + badge จำนวน หรือเลือก "ไม่มีสีชื่อกลุ่ม" → title row ไม่มี `GlassCard` wrapper (ไม่มีพื้นหลัง/เงา) แต่ยังแสดงจุด+badge สีเทา default

**ตารางเปรียบเทียบการเลือกสี:**

| ตัวเลือก | พื้นหลังกลุ่ม (`tintColor`) | ชื่อกลุ่ม (`titleAccentColor`) | ผลลัพธ์ |
|---|---|---|---|
| มีสีพื้นหลัง + มีสีชื่อ | มีค่า (GlassCard) | มีค่า | GlassCard มีสี + จุด/badge ตามสี |
| มีสีพื้นหลัง + ไม่มีสีชื่อ | มีค่า (GlassCard) | `null` | ไม่มี GlassCard แต่การ์ดย่อยยังอยู่ |
| ไม่มีสีพื้นหลัง + มีสีชื่อ | `null` | มีค่า | GlassCard ไม่มี tint (ใส) + จุด/badge ตามสี |
| ไม่มีสีพื้นหลัง + ไม่มีสีชื่อ | `null` | `null` | ไม่มี GlassCard + จุด/badge เทา |

### Glassmorphism Settings (`/erp/settings/glass`)

- **Page style:** transparent AppBar + pastel gradient background (`#DFF8FF` → `#DFF7E8` → `#F4E4FB`) พร้อม backdrop blobs
- **Section cards:** แต่ละกลุ่ม slider ห่อใน `GlassCard` แยก tint สี (title ฟ้า, sliders เหลืองครีม, blur เขียวมิ้นต์)
- 3 Opacity Sliders (Sidebar, Cards, Dialog)
- 1 Blur Intensity Slider
- Real-time Preview Box — แสดง sidebar mini + square card + capsule card อัปเดต real-time
- **Action buttons:** glass capsule buttons (radius 999px) มี gradient tint + border + shadow โปร่งใส
  - บันทึก: tint น้ำเงิน `#4F7DF3`
  - คืนค่าเริ่มต้น: tint ส้ม `#FF8A65`

---

## 7. การทำงาน (Flow)

```
1. User login → ตรวจสอบ user_dashboard_themes
   ├── ไม่มี → INSERT default (sheserved_default, Light, 12% opacity, 12px blur)
   └── มี → ดึงมาใช้

2. เปิด ERP Dashboard → userDashboardThemeProvider โหลด theme
   → AppBar แสดง title แบบ compact และชื่อสาขาเฉพาะกรณีมีหลายสาขา
   → แสดง branch selector ใน AppBar actions
   → แก้ไข sidebar bg, accent, card style ตาม theme
   → dashboard body แสดงเฉพาะ module board ไม่ render organization header ซ้ำ

3. กด Settings → Theme Tab → เลือก preset / custom color
   → กดบันทึก → UPDATE DB → Provider rebuild → UI เปลี่ยนทันที
   → เข้า Module Layout Settings เพื่อจัดการกลุ่มสี/ลำดับการ์ด

4. กด Settings → Glass Tab → ปรับ opacity/blur slider
   → กดบันทึก → UPDATE DB → Provider rebuild → UI เปลี่ยนทันที

5. สลับ Light/Dark → is_dark_mode flip
   → Dark: ใช้ sheserved_dark คงที่
   → Light: กลับไปใช้ preset เดิมที่เลือกไว้
```

---

## 8. Performance & Accessibility

- **GPU:** จำกัด blur ≤ 12px, ใช้ RepaintBoundary
- **Device เก่า:** Fallback เป็น solid color ถ้า blur > 12px
- **Touch target:** 48dp ขั้นต่ำ
- **Reduced motion:** ปิด animation ถ้า user ตั้งค่า

---

## 9. Design Tokens (มาตรฐานกลาง — ใช้ทุกหน้า ERP)

> **กฎ:** ทุกหน้าในระบบ ERP ต้องใช้ token ชุดนี้เท่านั้น ห้าม hardcode สี/radius/spacing ในแต่ละหน้า ถ้าต้องการสีเฉพาะหมวด (เช่น account type, stock status) ให้ลงทะเบียนใน `erpSemanticColors` กลาง

| Token | Light | Dark | ใช้กับ |
|-------|-------|------|--------|
| `bgGradient` | `#DFF8FF → #DFF7E8 → #F4E4FB` | `#0F0F0F → #1A1A1A` | พื้นหลังทุกหน้า ERP |
| `appBar` | transparent, `elevation 0` | เดียวกัน | AppBar ทุกหน้า |
| `appBarIcon` | `#4F7DF3` | `#CCFF00` | icon ใน AppBar |
| `appBarText` | `#1D2733` | `#CCFF00` | title/subtitle |
| `card` | `GlassCard` (opacity 12%, blur 12px, border 1.5px ขาว) | เดียวกัน | การ์ดทุกใบ |
| `glass.dialog` | opacity 12%, blur 12px | เดียวกัน | dialog (ผ่าน `showGlassDialog`) |
| `glass.notificationPanel` | opacity 12%, blur 12px | เดียวกัน | notification panel (section 14) |
| `radius.square` | `30` | `30` | การ์ด module board |
| `radius.listItem` | `20` | `20` | รายการใน list page (GlassCard) |
| `radius.capsule` | `999` | `999` | capsule card, pill button, branch selector |
| `radius.hero` | `36` | `36` | hero/tall tile |
| `radius.dialog` | `20` | `20` | dialog ทุกใบ |
| `spacing.board` | `10` (2col) / `11` (3+col) | เดียวกัน | module board |
| `spacing.scale` | `4 / 8 / 12 / 16 / 24` | เดียวกัน | padding/gap ทุกหน้า (ใช้เท่านี้เท่านั้น) |
| `sidebar.collapsed` | `60dp` | `60dp` | mini rail |
| `sidebar.expanded` | `240dp` | `240dp` | expanded sidebar |
| `accent` | ตาม preset | `#CCFF00` (fixed) | highlight |
| `error` | `#EF4444` | `#EF4444` | error state |
| `badgeUnread` | `#EF4444` (bg ขาว, text ขาว) | เดียวกัน | badge ตัวเลข/จุด unread (sidebar, bell, card) |
| `branchSelector` | bg `#F5FBFF`, border `#D7E8F6`, radius 999 | bg `#1A1A1A`, border lime | pill เลือกสาขาใน AppBar |

> **ที่ตั้งโค้ด (Single Token File):** tokens + `erpSemanticColors` + `erpStatusMaps` + `erpCategoryColors` ทั้งหมดอยู่ใน **ไฟล์เดียว**: `lib/features/erp/presentation/theme/erp_tokens.dart` (สร้างใน phase UI-1)
>
> **กฎการ import (บังคับ):**
> - `StatusChip`, `ErpPageScaffold`, `GlassCard` และ widget กลางทุกตัว **import จาก `erp_tokens.dart` เท่านั้น** — ห้ามสร้างไฟล์ token แยก (`page_colors.dart`, `module_colors.dart` ฯลฯ) และห้าม const สีใน widget/หน้าเอง
> - สีเฉพาะหมวด/โมดูล (account type 5 หมวด, stock status, lab status ฯลฯ) ลงทะเบียนใน `erpStatusMaps`/`erpCategoryColors` ในไฟล์นี้ ไม่ใช่ใน page
> - **ตรวจสอบได้ด้วย grep:** `Color(0x` หรือ `Colors.` ต้อง**ไม่ปรากฏ**ใน `lib/features/erp/presentation/pages/` และ `lib/features/erp/presentation/widgets/` (ยกเว้นเฉพาะใน `erp_tokens.dart` และ `GlassCard`) — ใช้เป็น CI/analyzer rule ได้ (ดู section 17)

### Typography (ขนาดมาตรฐาน)

| Style | Size / Weight | ใช้กับ |
|-------|--------------|--------|
| `erpTitle` | 20 / w600 | title หน้า (AppBar) |
| `erpSection` | 16 / w600 | หัวข้อ section ในหน้า |
| `erpBody` | 14 / w400 | เนื้อหาหลัก, label item |
| `erpCaption` | 12 / w400 | secondary text, timestamp |
| `erpNumber` | 16–20 / w700 (tabular) | ตัวเลขเงิน/สถิติ (ใช้ `FontFeature.tabularFigures()`) |

### Semantic Colors (สีสถานะกลาง)

| สถานะ | สี | ตัวอย่างการใช้ |
|-------|-----|----------------|
| `success` | `#34C759` | paid, completed, verified, in_stock |
| `warning` | `#FF9500` | pending_approval, low_stock, expiring |
| `error` | `#EF4444` | rejected, failed, out_of_stock, overdue |
| `info` | `#4F7DF3` | sent, in_transit, processing |
| `neutral` | `#94A3B8` | draft, cancelled, disabled, no group color |

> สีเฉพาะหมวด (เช่น account type: asset=เขียว, liability=แดง, equity=น้ำเงิน, revenue=ฟ้า, expense=ส้ม) ให้ลงทะเบียนเป็น **named map ใน `erpSemanticColors`** ไม่ hardcode ใน page แต่ละหน้า

---

## 10. Shared Page Pattern — `ErpPageScaffold`

ทุกหน้าจอของโมดูล ERP (list, form, detail, report) ต้องสร้างบน scaffold กลางเดียวกัน:

```dart
ErpPageScaffold(
  title: 'คลังสินค้า',
  subtitle: branchName,          // แสดงเฉพาะเมื่อมีหลายสาขา
  actions: [BranchSelectorPill(), HeadsectorNotificationBell()],
  floatingActionButton: ...,      // ถ้ามี
  body: ...,                      // list/form content
)
```

**Spec ภายใน `ErpPageScaffold`:**

- อ่าน token ทั้งหมดจาก `erp_tokens.dart` เท่านั้น — ห้าม hardcode สี/radius/spacing ใน scaffold เอง (ไฟล์นี้เป็นตัวกันหน้า modules ไม่ให้กำหนดค่าต่างกัน)
- `extendBodyBehindAppBar: true` + AppBar transparent ตาม token `appBar`
- พื้นหลัง `bgGradient` + backdrop blobs (light) / dark gradient (dark)
- Section/list item ห่อด้วย `GlassCard` (`section: GlassSection.card`)
- Dialog ทุกใบเปิดผ่าน `showGlassDialog` เท่านั้น (ไม่ใช้ `showDialog` ตรง)
- ปุ่ม action หลักใช้ glass capsule button (radius 999)
- Branch selector แสดงใน AppBar actions ของหน้าที่รองรับ multi-branch เสมอ
- props: `title`, `subtitle?`, `actions[]`, `floatingActionButton?`, `body`, `onRefresh?` (pull-to-refresh)

**Widget กลางที่ต้องมี (อยู่ใน `lib/features/erp/presentation/widgets/`):**

| Widget | หน้าที่ |
|--------|--------|
| `GlassCard` / `showGlassDialog` | มีแล้ว — ใช้เป็นฐานทุกการ์ด/dialog |
| `ErpPageScaffold` | scaffold กลางตาม spec ข้างบน |
| `StatusChip` | chip สถานะที่ map จาก `erpSemanticColors` เท่านั้น |
| `ErpEmptyState` | หน้าว่างมาตรฐาน (icon + ข้อความ + action button) |
| `ErpSearchBar` | search field กลาง (glass, capsule) สำหรับ list page |
| `ErpFilterChips` | แถว ChoiceChip/FilterChip กลาง (section 10.2) |
| `ErpListItem` | list item กลางตาม anatomy ด้านล่าง |
| `ErpLoadingSkeleton` | skeleton loading (glass card ปลอม 3-5 แถว) |
| `LockedModuleBadge` | badge "ต้องสมัคร" / lock สำหรับ tier gating (ดู section 13) |

### 10.1 List Item Anatomy (หน้า list ทุกโมดูล)

ทุกรายการในหน้า list ใช้ `ErpListItem` (ห่อด้วย `GlassCard`, radius `listItem` 20):

```
┌────────────────────────────────────────────┐
│  (icon bubble)  ชื่อรายการ          [StatusChip] │
│  สี pastel 40dp  subtitle 2 บรรทัดสูงสุด    (trailing icon/btn) │
│                 metadata แถวล่าง (เลขที่/วันที่) │
└────────────────────────────────────────────┘
```

- **Icon bubble:** วงกลม gradient pastel ขนาด 40dp ซ้ายสุด — สีจาก `erpSemanticColors`/หมวดของรายการ
- **ชื่อ:** `erpBody` w600 / **subtitle:** `erpBody` w400 text secondary / **metadata:** `erpCaption`
- **สถานะ:** `StatusChip` ขวาบนเสมอ — ไม่ใช้ text สีเดียว
- **Trailing:** icon กดได้ (chevron/edit/delete) ขนาด 20dp — delete เป็น `error` สีเสมอ
- สูงสุด 2 บรรทัดต่อ subtitle — เกินให้ `ellipsis`
- Tap target ขั้นต่ำ 48dp

### 10.2 Search & Filter Bar Pattern (หน้า list ที่มีข้อมูลเยอะ)

```
[ 🔍 ErpSearchBar (capsule, ฟิลด์เดียว) ]  [ErpFilterChips: ทั้งหมด|A|B|C]
```

- `ErpSearchBar`: แบบ capsule (radius 999), glass, icon ค้นหาซ้าย, ปุ่ม clear เมื่อมีข้อความ — ค้นหาแบบ real-time กับชื่อ/รหัส/เบอร์
- `ErpFilterChips`: ใช้ `ChoiceChip` (กรองทีละหมวด เช่น account type, status) + `FilterChip` (toggle boolean เช่น "เฉพาะที่สร้างเอง") — style เดียวกันทุกหน้า (label 12-14, selected = pill สี accent)
- ลำดับมาตรฐาน: SearchBar บน → FilterChips ล่าง → list ด้านล่าง (ทุกหน้าเหมือนกัน)

### 10.3 Loading / Empty / Error States

| State | แสดง |
|-------|------|
| Loading | `ErpLoadingSkeleton` (GlassCard ปลอม 3-5 แถว, shimmer เบาๆ) |
| Empty | `ErpEmptyState` — icon กลาง + ข้อความ 1 บรรทัด + action button (ถ้ามี) |
| Error | `ErpEmptyState` variant error + ปุ่ม "ลองใหม่" (reload) |

- ห้ามใช้ spinner กลางจอแบบ Material default ในหน้า ERP

---

## 11. `StatusChip` — สถานะสีกลาง

```dart
StatusChip(status: 'pending')   // → เทา neutral
StatusChip(status: 'paid')      // → เขียว success
StatusChip(status: 'rejected')  // → แดง error
StatusChip(status: 'urgent', icon: Icons.priority_high) // + icon เล็ก
```

- รับ `status` (String) → map เข้า `erpSemanticColors` เท่านั้น
- ใช้แทนการเขียน `Container` + สีเองในทุกหน้า list (AR/AP, PO, transfer, appointment, stock alert, payroll)
- ถ้า status ไม่อยู่ใน map → fallback `neutral` + log ไว้ตรวจ
- **ลงทะเบียน status ของโมดูล:** แต่ละโมดูลเพิ่ม status→color mapping ของตัวเองใน `erpStatusMaps` (เช่น `procurementStatusMap`, `inventoryStatusMap`) ที่ `erp_tokens.dart` — ห้ามส่ง `Color` ตรงเข้าจาก page
- `icon` เป็น optional — ใช้กับสถานะที่ต้องการเน้น (urgent, error, warning)
- พื้นหลัง chip ใช้สีของสถานะที่ opacity ~0.12 + text/icon สีเต็ม (เข้ากับ glass style)

---

## 12. Module Catalog (แหล่งข้อมูลโมดูลเดียว)

เพื่อแก้ปัญหารายชื่อโมดูลในเอกสาร/sidebar/dashboard board ไม่ตรงกัน ให้ใช้ **`dashboardModuleDefinitions` เป็นแหล่งเดียว (single catalog)** ที่ทุกส่วนอ้างอิง:

```dart
DashboardModuleDefinition(
  id: 'inventory',                    // key เดียวกับ feature flag + route
  labelTh: 'คลังสินค้า',
  icon: Icons.inventory_2_outlined,
  route: '/erp/inventory',
  defaultGroupId: 'operations',
  requiredFeature: 'erp_module.inventory', // key ใน tier_features
  badgeSource: 'inventory.stock.low',      // event key จาก notification_event_registry
  subRoutes: [...],                       // sub-menu สำหรับ desktop sidebar
  implemented: true,                      // false → แสดงเป็น disabled/lock (section 13)
)
```

**กฎ:**

- Sidebar nav, dashboard board, feature-flag check, tier gating และเอกสารทุกฉบับ **ต้องอ้างอิง catalog นี้เท่านั้น** — ห้ามแยกนิยามรายการโมดูลในเอกสารอื่น
- เมื่อเพิ่มโมดูลใหม่ → เพิ่มใน catalog + ระบุ `defaultGroupId` (ป้องกัน module ตกไป "ไม่มีกลุ่ม" — ดู fix ใน archive wireframe section 15)
- โมดูลที่ยังไม่ implement → ตั้ง `implemented: false` → แสดงเป็น disabled/lock ตาม section 13

---

## 13. Locked / Tier Gating Pattern (แบบเดียวทั้งระบบ)

โมดูลที่ถูกปิดหรือไม่ได้อยู่ใน Subscription Tier ต้องแสดงผลแบบเดียวกันทุกที่:

| สถานะ | Dashboard Board | Sidebar |
|-------|----------------|---------|
| เปิดใช้งาน | การ์ดปกติ | item ปกติ |
| ปิดผ่าน feature flag | **ซ่อน** | **ซ่อน** |
| ไม่อยู่ใน tier | การ์ด opacity 50% + `LockedModuleBadge("ต้องสมัคร")` | item opacity 50% + icon 🔒 เล็กขวาสุด |
| ยังไม่ implement | การ์ด opacity 50% + badge "เร็วๆ นี้" | item disabled (สี neutral) |

- กดที่ locked card/item → เปิด `showGlassDialog` อธิบาย tier ที่ต้องใช้ + ปุ่ม "ติดต่อ Sheserved" (ไม่ navigate เข้าหน้าโมดูล)
- **ห้าม** ใช้วิธี disabled แบบอื่น (เช่น badge สีแดง, icon ต่างกัน) ในแต่ละหน้า

---

## 14. Notification UI (Headsector + Glass Panel)

อ้างอิงรายละเอียดระบบใน `ERP_NOTIFICATION_SYSTEM_PLAN.md` — **UI ต้องใช้ spec นี้เท่านั้น:**

- **ตำแหน่ง:** `HeadsectorNotificationBell` ใน AppBar actions มุมขวาบนของ `ErpPageScaffold` (ทุกหน้า ERP) และหน้า Home
- **Bell:** icon `notifications_outlined` + badge จำนวน unread (dot เมื่อ collapsed/เล็ก, ตัวเลขเมื่อมีพื้นที่)
- **Panel:** เปิดเป็น `GlassCard` (`section: GlassSection.dialog` — opacity/blur ตาม theme ผู้ใช้) **ไม่ใช้พื้นหลังสีทึบแยก** (ยกเลิก spec "พื้นหลังสีม่วงอ่อน" เดิม)
- **Notification card:** แต่ละ item ใช้ `GlassCard` + logo องค์กรนำหน้า + `StatusChip` ตาม `notification_type` (info→info, warning→warning, error/urgent→error, success→success)
- **ฐานข้อมูล:** ใช้ตาราง `notifications` ตารางเดียวเป็น canonical — `platform_notifications` ใน POS plan ถือเป็น deprecated ให้ยุบเข้า `notifications`

---

## 15. Phased Rollout — ปรับ UI ให้สอดคล้อง (Module UI Unification)

| Phase | งาน | สถานะ |
|-------|-----|-------|
| **UI-0** | ประกาศ SSOT ฉบับนี้ + mark เอกสารซ้ำ (Glassmorphism/Light-Dark/Sidebar) เป็น merged archive | ✅ Done |
| **UI-1** | สร้าง/รวม `erp_tokens.dart` (Single Token File) + `erpSemanticColors`/`erpStatusMaps` + `StatusChip` + `ErpEmptyState` + `ErpSearchBar` + custom lint/grep check (section 17.1) ใน `lib/features/erp/presentation/` | ☐ TODO |
| **UI-2** | สร้าง `ErpPageScaffold` + `LockedModuleBadge` + `HeadsectorNotificationBell` (ตาม section 10, 13, 14) | ☐ TODO |
| **UI-2b** | ตั้งค่า Orientation Policy ระดับ 2 (section 18): แก้ `Info.plist` + `main.dart` ให้ portrait+landscape (ห้ามกลับหัว) ตาม device | ☐ TODO |
| **UI-3** | Refactor หน้าที่มีอยู่ให้ใช้ pattern กลาง: `ChartOfAccountsPage`, `InventoryPage`, `EmployeeListPage`, `GlEntriesPage`, `AccountsReceivablePage`, `AccountsPayablePage`, `ShiftManagementPage` (ย้ายสี hardcode → `erpSemanticColors`, dialog → `showGlassDialog`, AppBar → `ErpPageScaffold`, list item → `ErpListItem`) | ☐ TODO |
| **UI-3b** | Refactor หน้า Settings ให้เป็น `ErpPageScaffold`: `/erp/settings/theme`, `/erp/settings/modules`, `/erp/settings/glass`, `/erp/settings` (องค์กร) | ☐ TODO |
| **UI-4** | สร้าง `dashboardModuleDefinitions` catalog เดียว + refactor sidebar/dashboard board/feature flag ให้อ้างอิง catalog | ☐ TODO |
| **UI-5** | ยุบ `platform_notifications` → `notifications` + เชื่อม Headsector bell กับ `notifications` table + Realtime | ☐ TODO |
| **UI-6** | บังคับใช้ pattern กับทุกหน้าใหม่: แผนโมดูลทุกฉบับ (HR/Inventory/Procurement/Accounting/CRM/HIS/LAB/POS/KPI/Subscription) ต้องอ้างอิง SSOT ฉบับนี้ | ☐ TODO (กฎถาวร) |

### Definition of Done (หน้า ERP ใหม่ทุกหน้า)

- [ ] ใช้ `ErpPageScaffold` (AppBar transparent + `bgGradient` + branch selector)
- [ ] สี/radius/spacing มาจาก `erp_tokens.dart` เท่านั้น (ไม่มี hex hardcode ใน page)
- [ ] สถานะทุกจุดใช้ `StatusChip` + `erpStatusMaps` (ไม่มี text สีเอง)
- [ ] Dialog เปิดผ่าน `showGlassDialog` เท่านั้น
- [ ] List item ใช้ `ErpListItem` ตาม anatomy (section 10.1)
- [ ] มี Search/Filter (ถ้ามีข้อมูลเยอะ) ตาม section 10.2
- [ ] Loading/Empty/Error ใช้ widget กลาง (section 10.3)
- [ ] โมดูลใน sidebar/board อ้างอิง `dashboardModuleDefinitions` + ใช้ Tier Gating ตาม section 13
- [ ] ผ่าน Acceptance Test แนวตั้งของหน้านั้น (section 17) — manual smoke + grep/lint check
- [ ] แสดงผลถูกต้องทั้ง portrait และ landscape (section 18.6) — ไม่มี overflow ตอนหมุน

---

## 16. Docs Index (สถานะเอกสาร UI ใน docs/ERP)

| เอกสาร | สถานะ | บทบาท |
|--------|-------|-------|
| `ERP_DASHBOARD_UI_PLAN.md` | **SSOT** | เอกสารนี้ — spec UI กลางทั้งหมด (token, page pattern, module catalog, tier gating, notification UI) |
| `ERP_CORE_ARCHITECTURE.md` | Master architecture | สถาปัตยกรรมระบบ + รายชื่อโมดูล (อ้างอิง catalog ใน SSOT section 12) |
| `ERP_GLASSMORPHISM_PLAN.md` | 🔒 Merged (archive) | ตัวอย่างโค้ด `GlassCard`/`GlassSidebar`/slider — อย่าแก้ spec ที่นี่ |
| `ERP_LIGHT_DARK_THEME_PLAN.md` | 🔒 Merged (archive) | preset/RPC theme — อย่าแก้ spec ที่นี่ |
| `ERP_SIDEBAR_NAV_WIREFRAME.md` | 🔒 Merged (archive) | wireframe รายอุปกรณ์ + Root Cause & Fix notes (13–15) + โครงสร้าง sidebar ปัจจุบัน (16) |
| `ERP_NOTIFICATION_SYSTEM_PLAN.md` | Module plan | ระบบ notification — canonical table `notifications` + UI ตาม SSOT section 14 |
| `ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | Module plan | subscription tier + Tier Gating (อ้างอิง SSOT section 13) |
| `ACCOUNTING_SYSTEM_PLAN.md` และโมดูลอื่น (CRM/HIS/HR/Inventory/KPI/LAB/POS/Procurement) | Module plan | ธุรกิจ/DB ของแต่ละโมดูล — UI ต้องอ้างอิง SSOT นี้เท่านั้น (มี note อยู่ต้นไฟล์แล้ว) |

> **กฎ:** ถ้าจะเพิ่ม spec ใหม่ที่เกี่ยวกับสี/การ์ด/หน้า/แถบนำทาง ให้เพิ่มใน SSOT ฉบับนี้เท่านั้น แล้วแผนโมดูลอ้างอิงกลับมา — ห้าม duplicate

---

## 17. Acceptance Tests (Vertical Smoke — ตรวจความสอดคล้อง)

เป้าหมาย: พิสูจน์ว่าหน้า ERP ใช้ pattern กลางจริง ไม่ใช่แค่ "ดูคล้ายกัน" แบ่งเป็น 3 ชั้น:

### 17.1 Static Check (อัตโนมัติ — ใช้ได้ทันทีหลัง phase UI-1)

```bash
# 1) ไม่มี hex color ในหน้า/widget (ยกเว้น erp_tokens.dart + GlassCard)
grep -rn "Color(0x" lib/features/erp/presentation/pages lib/features/erp/presentation/widgets \
  --include="*.dart" | grep -v "erp_tokens.dart"

# 2) ไม่มี Colors.* ตรงๆ ในหน้า (ควร import จาก tokens)
grep -rn "Colors\." lib/features/erp/presentation/pages --include="*.dart" | grep -v "erp_tokens.dart"

# 3) ทุก dialog ใช้ showGlassDialog (ไม่เรียก showDialog ตรงในหน้า)
grep -rn "showDialog(" lib/features/erp/presentation/pages --include="*.dart"

# 4) StatusChip ถูกใช้แทน Container สีสถานะ
grep -rn "StatusChip(" lib/features/erp/presentation/pages --include="*.dart" | wc -l
```

> ทำเป็น CI step หรือ custom analyzer lint (`avoid_hardcoded_color_in_erp_pages`) ใน phase UI-1

### 17.2 Manual Smoke Checklist (ทุกหน้า list/ดึงข้อมูล)

เปิดหน้า (เช่น `/erp/chart-of-accounts`, `/erp/inventory`, `/erp/employees`) แล้วตรวจ:

- [ ] พื้นหลังเป็น pastel gradient (light) / dark gradient (dark) — ไม่ใช่สีขาว/เทาเรียบ
- [ ] AppBar โปร่งใสเห็น gradient ลอดผ่าน + icon สี `#4F7DF3` (light) / lime (dark)
- [ ] รายการทุกแถวเป็น `GlassCard` (blur + border ขาวบาง) — ไม่มีการ์ดทึบ
- [ ] สถานะทุกจุดเป็น `StatusChip` (สีจาก `erpSemanticColors`/`erpStatusMaps`)
- [ ] dialog (เปิด/แก้ไข/ยืนยัน) เป็น glass — ไม่ใช่ dialog ขาวทึบ
- [ ] loading = skeleton / empty = `ErpEmptyState` / error = ปุ่มลองใหม่
- [ ] เปลี่ยน theme (light ↔ dark) แล้วหน้า re-render ถูกต้อง ไม่มีสีเพี้ยน

### 17.3 Vertical Test ตัวอย่าง — `ChartOfAccountsPage` (ตามข้อเสนอแนะ)

**เป้าหมาย:** ยืนยันว่าสี account type 5 หมวดมาจาก `erpCategoryColors` ใน `erp_tokens.dart` ไม่ใช่ hex ในหน้า

Manual:
- [ ] เปิด `/erp/chart-of-accounts` → สังเกต section header 5 หมวด (สินทรัพย์/หนี้สิน/ทุน/รายได้/ค่าใช้จ่าย)
- [ ] ตรวจสีหมวด: เขียว/แดง/น้ำเงิน/ฟ้า/ส้ม ตรงกับ `erpCategoryColors['asset'|'liability'|'equity'|'revenue'|'expense']`
- [ ] บัญชี custom: แถบซ้าย + badge เป็น `amber` — ต้องมาจาก token เดียวกัน (ลงทะเบียนใน `erpCategoryColors['custom']`)
- [ ] เปลี่ยนเป็น Dark mode → สีหมวดยังอ่านชัด (contrast ผ่าน) — ไม่มีสีเข้มทับพื้นเข้ม

Automated (widget test):
```dart
testWidgets('ChartOfAccounts uses erpCategoryColors, not hardcoded colors', (tester) async {
  await tester.pumpWidget(providerScope(child: ChartOfAccountsPage()));
  // stub data: account type 'asset' → ค้นหา Container/BoxDecoration ที่ใช้สี
  // assert: สีที่ render === erpCategoryColors['asset'] (จาก erp_tokens.dart)
  // และ assert: ไม่มีสีอื่น (เช่น Color(0xFF...) ที่ไม่ได้มาจาก tokens) ใน tree
});
```

### 17.4 Golden Test (แนะนำ — ทางเลือก)

- สร้าง golden image ต่อ 1 หน้า list หลัก (light + dark) แล้ว commit ไว้ — เปลี่ยน spec เมื่อ golden เปลี่ยน
- ใช้กับหน้า UI-3 refactor เท่านั้น เพื่อกัน regression หลัง refactor

---

## 18. Orientation Policy (ระดับ 2 — Native-first)

> **นโยบายที่ตัดสินใจ:** แอปหมุนได้ **แนวตั้ง + แนวนอน** แต่ **ห้ามกลับหัว (portraitDown)** ใช้แนวทาง **Native-first config** — ตั้งสิทธิ์กว้างสุดที่ native แล้ว Flutter แคบลงด้วย policy app-wide ครั้งเดียว **ไม่ใช้ per-route orientation lock**

### 18.1 iOS (`ios/Runner/Info.plist`)

- **iPhone:** `UISupportedInterfaceOrientations` = `portrait`, `landscapeLeft`, `landscapeRight` (ไม่รวม `portraitUpsideDown`)
  - หมายเหตุ: iPhone ที่มี Face ID ไม่รองรับ upside-down อยู่แล้วที่ระดับ OS
- **iPad:** เลือก 1 ใน 2 ทาง
  - **(ก) รองรับ 4 ทิศทาง** (รวม upside-down) — ผ่าน Apple multitasking/review guideline
  - **(ข) ตั้ง `UIRequiresFullScreen = YES`** แล้วล็อก 3 ทิศทาง (ไม่รวม upside-down) ได้ตามต้องการ
- ปัจจุบัน Info.plist ประกาศ 4 orientations ไว้ทั้ง iPhone/iPad → ต้องปรับให้ตรงกับตัวเลือกด้านบน

### 18.2 Android (`android/app/src/main/AndroidManifest.xml`)

- **ปล่อยว่าง** — ไม่ตั้ง `android:screenOrientation` ใน `<activity>` ควบคุมที่ Flutter (Dart) อย่างเดียว
- (ปัจจุบัน manifest ไม่มี `screenOrientation` → สอดคล้องแล้ว ไม่ต้องแก้)

### 18.3 Flutter (`lib/main.dart` — เรียกครั้งเดียว app-wide)

```dart
// โทรศัพท์: portrait + landscape (ห้ามกลับหัว)
SystemChrome.setPreferredOrientations([
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
]);

// iPad/tablet: ตามตัวเลือก iOS ข้อ (ก) → เพิ่ม portraitDown ด้วย
// หรือเลือก (ข) → ใช้ชุด 3 ทิศทางเหมือนโทรศัพท์
```

- ตรวจจับ tablet ด้วย `MediaQuery` (shortest side ≥ 600dp) หรือ `device_info_plus`
- เรียกใน `main()` ครั้งเดียว — **ห้าม** เรียกซ้ำแบบ per-route/per-page

### 18.4 สิ่งที่ห้ามทำ

- ❌ **ห้าม per-route orientation lock** (RouteObserver + `setPreferredOrientations` ทุก transition) — ทำให้เกิด rotation jank ตอน pop, route ที่ไม่มีชื่อถูกมองผิด, และเสี่ยง iPad review
- ❌ ห้ามล็อก portrait ตลอดทั้งแอป — จะทำให้ spec landscape (mini rail, board 3–4 columns) ใช้ไม่ได้

### 18.5 ผลลัพธ์ต่ออุปกรณ์

| อุปกรณ์ | Portrait | Landscape | Upside-down |
|---------|:---:|:---:|:---:|
| iPhone | ✅ | ✅ | ❌ (OS + policy) |
| iPad (ทาง ก) | ✅ | ✅ | ✅ (ตาม Apple) |
| iPad (ทาง ข) | ✅ | ✅ | ❌ |
| Android โทรศัพท์ | ✅ | ✅ | ❌ |
| Android tablet | ✅ | ✅ | ตาม policy |

### 18.6 เงื่อนไขคู่ (ระดับ 1 — Responsive UI)

การอนุญาตหมุนจะสมบูรณ์ได้ต้องมี UI ที่ปรับตาม breakpoint (ระดับ 1):
- ทุกหน้า ERP ใช้ `ErpPageScaffold` + sidebar/board responsive ตาม section 3
- Dialog/bottom sheet (`showGlassDialog`) ต้อง responsive ต่อ landscape (maxWidth/maxHeight) — ป้องกัน overflow ตอนหมุน
- เพิ่มลงใน Definition of Done: "หน้าแสดงผลถูกต้องทั้ง portrait และ landscape"
