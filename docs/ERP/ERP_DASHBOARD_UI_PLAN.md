# ERP Dashboard UI/UX Plan — Unified

แผนรวมเดียวสำหรับ UX/UI ของ ERP Dashboard รวม Glassmorphism + Light/Dark Theme + Collapsible Sidebar Navigation

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
| **Mobile** | Portrait | 56dp → 240dp | Overlay + Expandable |
| **Mobile** | Landscape | 56dp | Persistent Mini Rail |
| **Tablet** | Portrait | 56dp → 240dp | Overlay + Expandable |
| **Tablet** | Landscape | 56dp → 240dp | Persistent Expandable |
| **Desktop** | Any | 240dp | Persistent Expanded |

### Dashboard Overview Layout

- **Mobile portrait:** 2-column responsive board, mixed-size cards (บางการ์ด span 2 columns)
- **Tablet:** 3-column board, มี wide capsule cards แทรกเพื่อสร้างจังหวะสายตา
- **Desktop:** 4-column board, mix ระหว่าง square / capsule / hero tile
- **Tile spacing:** 10px สำหรับ 2 columns, 11px สำหรับ 3+ columns
- **Proportions:** square tile ~0.96, capsule tile ~0.68, hero/tall tile ~1.42
- **Radius:** square 30px, capsule 999px, tall/hero 36px
- **Tile behavior:** icon bubble ถูกวางกึ่งกลางด้านบน, label อยู่กึ่งกลาง, card content ใช้ glass glow ตามสีพาสเทลของแต่ละโมดูล

### Nav Items (14 modules)

📊 Dashboard, 🛒 POS, 📦 Inventory, 👥 HR, 💰 Accounting, 📊 CRM, 🔔 Notifications, 💬 Messages, ⚙️ Settings, 🏥 HIS, 🔬 LIS, 📞 Telemedicine, 🚚 Logistics, 🛍️ Commerce

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
