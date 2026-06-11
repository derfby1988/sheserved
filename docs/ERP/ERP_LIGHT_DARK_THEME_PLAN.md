# ERP Dashboard Light/Dark Theme Plan

ERP Dashboard รองรับโหมดสว่าง (Light) และมืด (Dark) พร้อมกัน โดย Light Theme ให้ผู้ใช้ปรับแต่งสีได้ 8 presets + custom และถูกออกแบบให้มีโทน **iOS natural pastel**; ส่วน Dark Theme ใช้ preset เดียว fixed

## โครงสร้างธีม

| โหมด | Presets | ปรับแต่งได้ | รายละเอียด |
|------|---------|-----------|-----------|
| **Light** | 8 + custom | ✅ ผู้ใช้ปรับได้ | `sheserved_default`, `ocean_blue`, `sunset_orange`, `forest_green`, `royal_purple`, `midnight_black`, `coral_pink`, `custom` |
| **Dark** | 1 preset | ❌ คงที่ | `sheserved_dark` (fixed) |

## ฐานข้อมูล

เพิ่ม column ใน `user_dashboard_themes`:

```sql
ALTER TABLE user_dashboard_themes ADD COLUMN is_dark_mode BOOLEAN DEFAULT false;
```

เพิ่ม preset ใน `theme_presets`:

```sql
INSERT INTO theme_presets (preset_key, preset_name_th, preset_name_en, primary_color, accent_color, surface_color, text_primary, text_secondary, error_color, card_bg, card_text) VALUES
('sheserved_dark', 'Sheserved Dark', 'Sheserved Dark', '#0F0F0F', '#CCFF00', '#1A1A1A', '#FFFFFF', 'rgba(255,255,255,0.5)', '#EF4444', '#1A1A1A', '#FFFFFF');
```

### สี Dark Theme (คงที่ — Lime Green)

| Token | สี | ค่า |
|-------|-----|-----|
| `primary` | Near Black | `#0F0F0F` |
| `accent` | Lime Green | `#CCFF00` |
| `surface` | Dark Gray | `#1A1A1A` |
| `text_primary` | White | `#FFFFFF` |
| `text_secondary` | Dim White | `rgba(255,255,255,0.5)` |
| `error` | Red | `#EF4444` |
| `card_bg` | Card BG | `#1A1A1A` |
| `card_text` | Card Text | `#FFFFFF` |

> **ลักษณะ:** พื้นหลังดำเข้ม (`#0F0F0F`) + Accent สี Lime Green สด (`#CCFF00`) บนปุ่ม แท็ก ไอคอน และ highlight — ตาม UI reference

## Light Mode Visual Direction

- **พื้นหลัง:** gradient แบบ pastel เย็น/อุ่นผสมกัน เช่น ฟ้าอ่อน, เขียวอ่อน, ม่วงอ่อน
- **Cards:** ใช้ glass cards ที่มี tint เฉพาะสีของแต่ละโมดูล + inner shine
- **Shape language:** เน้น rounded square, capsule และ circle มากกว่ากรอบสี่เหลี่ยมแข็ง
- **Text placement:** ข้อความของ module tile อยู่กึ่งกลาง และมีลำดับชั้นชัดเจนกว่า dark mode

## หน้า Settings (`/erp/settings/theme`)

```
┌─────────────────────────────────────────────┐
│  <- กลับ  |  ธีมสี Dashboard                  |
├─────────────────────────────────────────────┤
│  🌗 โหมดสี                                  │
│  ┌─────────────────────────────────────┐    │
│  │  ☀️ Light     |      🌙 Dark       │    │
│  │  [เลือก]      |      [เลือก]        │    │
│  └─────────────────────────────────────┘    │
│                                              │
│  [ถ้าเลือก Light]                            │
│  ┌─────────────────────────────────────┐    │
│  │ 🟢 Default  🔵 Ocean  🟠 Sunset    │    │
│  │ 🟩 Forest   🟣 Royal  ⬛ Midnight   │    │
│  │ 🩷 Coral    🎨 Custom              │    │
│  └─────────────────────────────────────┘    │
│                                              │
│  Preview ควรเป็น natural pastel + glass glow │
│  เพื่อให้สอดคล้องกับ dashboard จริง         │
│                                              │
│  [ถ้าเลือก Dark — ไม่มีตัวเลือกสี]          │
│  ┌─────────────────────────────────────┐    │
│  │ 🌙 Sheserved Dark (ค่าเริ่มต้น)    │    │
│  │ ไม่สามารถปรับแต่งสีได้             │    │
│  └─────────────────────────────────────┘    │
│                                              │
│       [💾 บันทึก]    [❌ คืนค่าเริ่มต้น]      │
└─────────────────────────────────────────────┘
```

## Flutter Logic

```dart
class ThemedCollapsibleSidebar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(userDashboardThemeProvider);
    
    // ถ้า Dark Mode → ใช้ preset 'sheserved_dark' คงที่
    // ถ้า Light Mode → ใช้ preset ที่ user เลือก
    final resolvedColors = theme.isDarkMode
      ? ThemeResolver.darkPreset()  // คงที่
      : ThemeResolver.fromUserPreset(theme.presetKey); // ปรับได้
    
    final primaryColor = resolvedColors.primary;
    final accentColor = resolvedColors.accent;
    // ...
  }
}
```

## API / RPC

```sql
-- ดึง resolved theme (light หรือ dark)
CREATE OR REPLACE FUNCTION get_resolved_dashboard_theme(
  p_user_id UUID,
  p_profession_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_is_dark BOOLEAN;
  v_preset TEXT;
BEGIN
  SELECT is_dark_mode, theme_preset INTO v_is_dark, v_preset
  FROM user_dashboard_themes
  WHERE user_id = p_user_id AND profession_id = p_profession_id;
  
  -- ถ้า dark mode → 强制ใช้ 'sheserved_dark'
  IF v_is_dark THEN
    v_preset := 'sheserved_dark';
  END IF;
  
  RETURN get_theme_preset_by_key(v_preset);
END;
$$ LANGUAGE plpgsql;

-- สลับโหมด
CREATE OR REPLACE FUNCTION toggle_dark_mode(
  p_user_id UUID,
  p_profession_id UUID
) RETURNS VOID AS $$
  UPDATE user_dashboard_themes
  SET is_dark_mode = NOT is_dark_mode,
      updated_at = now()
  WHERE user_id = p_user_id AND profession_id = p_profession_id;
$$ LANGUAGE plpgsql;
```

## กฎการทำงาน

- **สลับโหมด:** กด toggle Light/Dark ใน settings → `is_dark_mode` flip → sidebar re-build
- **Light → Dark:** preset ที่ user เลือกไว้ **ไม่หาย** เก็บไว้ใน DB รอ user กลับมา Light
- **Dark → Light:** กลับมาใช้ preset ที่ user เคยเลือกไว้ (`theme_preset`)
- **Custom colors:** ใช้ได้เฉพาะ Light mode (Dark mode ใช้ fixed colors)
- **Glassmorphism:** ใช้ได้ทั้ง Light และ Dark (opacity/blur sliders ใช้ร่วมกัน)

## สรุป

| ฟีเจอร์ | Light | Dark |
|--------|-------|------|
| Color Presets | 8 + custom | 1 (fixed) |
| Custom Colors | ✅ | ❌ |
| Glassmorphism | ✅ | ✅ |
| Opacity Sliders | ✅ | ✅ |
| Blur Slider | ✅ | ✅ |
