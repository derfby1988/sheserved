# Full Glassmorphism + Per-Section Opacity Control — ERP Dashboard

ใช้แก้วโปร่งใส (Glassmorphism) เต็มรูปแบบใน ERP Dashboard พร้อมให้ผู้ใช้งานปรับระดับความโปร่งใส (opacity) แยกตามส่วนได้ในหน้า Dashboard Settings ช่วง 0-50% ค่าเริ่มต้น 12%

Light mode ของ dashboard ใช้โทน **iOS natural pastel** พร้อม background blobs เบลอ และการ์ดโมดูลแบบ **mixed-size / capsule / rounded cards** เพื่อให้ใกล้ reference image มากที่สุด

## 1. องค์ประกอบที่ใช้ Glassmorphism

| ส่วน | Glass Effect | Border | Blur | Default Opacity |
|------|-------------|--------|------|-----------------|
| **AppBar** | transparent — ไม่มีสีทึบ | — | — | — |
| **Sidebar** | โปร่ง + blur + shine | 1.5px ขาว | 12px | 12% |
| **Module Cards** | โปร่ง + blur + shine + pastel tint | 1.5px ขาว | 12px | 12% |
| **Dialogs** | โปร่ง + blur + shine | 1.5px ขาว | 12px | 12% |
| **Notification Panel** | โปร่ง + blur | 1.5px ขาว | 12px | 12% |
| **Bottom Promo Card** | โปร่ง + glow | 1.5px ขาว | 12px | 12% |

### AppBar (ERP Shell)

- **Light mode:** `backgroundColor: Colors.transparent`, `elevation: 0`, `extendBodyBehindAppBar: true`
- **Title text:** `#1D2733` (dark gray)
- **Icons:** น้ำเงิน `#4F7DF3` (theme toggle, notification, back)
- **Branch selector:** pill `#F5FBFF` + border `#D7E8F6`, radius 999px
- **Dark mode:** text/icon สี lime `#CCFF00`

### 1.1 Module Board Visual Language

- **Square tiles:** ใช้กับโมดูลที่ต้องการความสมดุลและอ่านง่าย
- **Capsule tiles:** ใช้กับโมดูลสำคัญหรือโมดูลที่ต้องการเน้นความยาว
- **Hero/tall tiles:** ใช้กับโมดูลที่ควรดึงสายตาเป็นพิเศษ
- **Icon bubble:** ใช้วงกลมไล่สีพาสเทลอยู่กลางการ์ด
- **Text:** อยู่กึ่งกลางและมี hierarchy ที่นุ่มกว่า style เดิม
- **Fine-tuned geometry:** spacing 10px (2 columns) / 11px (3+ columns), square radius 30px, capsule radius 999px, tall/hero radius 36px
- **Relative proportions:** square 0.96, capsule 0.68, tall/hero 1.42

## 2. ฐานข้อมูล (Opacity ต่อผู้ใช้งาน)

เพิ่ม columns ใน `user_dashboard_themes` (ตารางเดิม):

```sql
ALTER TABLE user_dashboard_themes ADD COLUMN glass_opacity_sidebar  DECIMAL(5,4) DEFAULT 0.12;
ALTER TABLE user_dashboard_themes ADD COLUMN glass_opacity_cards     DECIMAL(5,4) DEFAULT 0.12;
ALTER TABLE user_dashboard_themes ADD COLUMN glass_opacity_dialog    DECIMAL(5,4) DEFAULT 0.12;
ALTER TABLE user_dashboard_themes ADD COLUMN glass_blur_level        INTEGER DEFAULT 12;
-- Range: 0.00 - 0.50 (0-50%), default 0.12 (12%)
-- Blur: 2-20px, default 12px
```

## 3. หน้า Dashboard Settings — Glassmorphism Tab (`/erp/settings/glass`)

```
┌──────────────────────────────────────────────┐
│  pastel gradient bg (transparent AppBar)     │
│  <- กลับ  |  ตั้งค่าความโปร่งใส Dashboard    │
├──────────────────────────────────────────────┤
│  ┌───────────────────────────────────────┐   │
│  │  🎛️ ระดับความโปร่งใส                 │   │  ← GlassCard tint ฟ้า
│  │  ปรับความโปร่งใสแยกตามส่วน          │   │
│  └───────────────────────────────────────┘   │
│                                              │
│  ┌───────────────────────────────────────┐   │
│  │  Sidebar                              │   │  ← GlassCard tint เหลือง
│  │  ━━━━━━●━━━━━━━━━━  12%              │   │
│  │  [ทึบ 0%]        [โปร่ง 50%]         │   │
│  │  ───────────────────────────────────  │   │
│  │  Module Cards                         │   │
│  │  ━━━━━━●━━━━━━━━━━  12%              │   │
│  │  ───────────────────────────────────  │   │
│  │  Dialog / Popup                       │   │
│  │  ━━━━━━●━━━━━━━━━━  12%              │   │
│  └───────────────────────────────────────┘   │
│                                              │
│  ┌───────────────────────────────────────┐   │
│  │  Blur Intensity (ทุกส่วน)            │   │  ← GlassCard tint เขียว
│  │  ━━━━●━━━━━━━━━━━━  12px             │   │
│  └───────────────────────────────────────┘   │
│                                              │
│  ┌───────────────────────────────────────┐   │
│  │  [Preview Box — แสดงตัวอย่างเรียลไทม์] │   │
│  │  sidebar mini + square + capsule      │   │
│  └───────────────────────────────────────┘   │
│                                              │
│    [  💾 บันทึก  ]    [  ❌ คืนค่าเริ่มต้น ]   │  ← Glass capsule buttons
│     tint: #4F7DF3      tint: #FF8A65        │
└──────────────────────────────────────────────┘
```

## 4. Flutter Widgets

### A. GlassCard (แก้วโปร่งใสพื้นฐาน — Stack 3 ชั้น)

```dart
class GlassCard extends ConsumerWidget {
  final Widget child;
  final double borderRadius; // default 20
  final GlassSection section; // sidebar / card / dialog
  final Color? tintColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(dashboardThemeProvider).theme;
    final opacity = theme.getOpacityFor(section).clamp(0.15, 0.50);
    final blur = theme.glassBlurLevel.toDouble(); // default 12
    final isDark = theme.isDarkMode;
    final baseColor = isDark ? Colors.black : Colors.white;
    final surfaceTint = isDark ? baseColor : (tintColor ?? baseColor);

    final glassGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(surfaceTint, Colors.white, 0.25)!.withOpacity(opacity * 0.55),
        Color.lerp(surfaceTint, Colors.white, 0.15)!.withOpacity(opacity),
        Color.lerp(surfaceTint, Colors.white, 0.08)!.withOpacity(opacity * 0.85),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.5) : Colors.black.withOpacity(0.12),
            blurRadius: blur + 8,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Stack(
            children: [
              Container(decoration: BoxDecoration(gradient: glassGradient)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(isDark ? 0.12 : 0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              if (!isDark && tintColor != null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      gradient: RadialGradient(
                        center: Alignment.topLeft,
                        radius: 1.15,
                        colors: [
                          tintColor!.withOpacity(0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              Container(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

enum GlassSection { sidebar, card, dialog }
```

### B. GlassSidebar

```dart
class GlassSidebar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(userDashboardThemeProvider);
    final opacity = theme.glassOpacitySidebar;
    final blur = theme.glassBlurLevel.toDouble();
    
    return Stack(
      children: [
        // Layer 1: Gradient Background (จำเป็นสำหรับ glass effect)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _hexToColor(theme.primaryColor, fallback: const Color(0xFF00695C)),
                _hexToColor(theme.primaryColor, fallback: const Color(0xFF00695C))
                  .withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // Layer 2: Glass Sidebar
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            width: _isExpanded ? 240 : 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(opacity),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withOpacity(0.1 + opacity * 0.4),
                  width: 1,
                ),
              ),
            ),
            child: SidebarContent(),
          ),
        ),
      ],
    );
  }
}
```

### C. GlassDialog

```dart
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetRef ref,
  required WidgetBuilder builder,
}) {
  final theme = ref.read(userDashboardThemeProvider);
  final opacity = theme.glassOpacityDialog;
  final blur = theme.glassBlurLevel.toDouble();
  
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.4),
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          section: GlassSection.dialog,
          borderRadius: 20,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: builder(ctx),
          ),
        ),
      ),
    ),
  );
}
```

### D. Opacity Slider Widget

```dart
class GlassOpacitySlider extends ConsumerWidget {
  final String label;
  final GlassSection section;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(userDashboardThemeProvider);
    final currentOpacity = theme.getOpacityFor(section);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Row(
          children: [
            const Text('ทึบ', style: TextStyle(fontSize: 11)),
            Expanded(
              child: Slider(
                value: currentOpacity,
                min: 0.0,
                max: 0.5,
                divisions: 50, // ทีละ 1%
                label: '${(currentOpacity * 100).toInt()}%',
                onChanged: (value) {
                  ref.read(userDashboardThemeProvider.notifier)
                    .setOpacity(section, value);
                },
              ),
            ),
            const Text('โปร่ง', style: TextStyle(fontSize: 11)),
          ],
        ),
        Text('${(currentOpacity * 100).toInt()}%', 
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
```

### E. Real-time Preview Box

```dart
class GlassPreviewBox extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(userDashboardThemeProvider);
    final isDark = theme.isDarkMode;
    
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0F0F0F), const Color(0xFF1A1A1A)]
              : [const Color(0xFFDFF8FF), const Color(0xFFDFF7E8), const Color(0xFFF4E4FB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          if (!isDark) ...[
            Positioned(top: -18, left: -12, child: _GlowBlob(color: Color(0xFFBFE7FF), size: 90)),
            Positioned(bottom: -16, right: 6, child: _GlowBlob(color: Color(0xFFCFEFBA), size: 110)),
          ],
          // Preview: Sidebar mini
          Positioned(
            left: 12, top: 12, bottom: 12,
            child: GlassCard(
              section: GlassSection.sidebar,
              tintColor: const Color(0xFFBFE7FF),
              borderRadius: 22,
              child: const SizedBox(width: 56, child: Center(child: Icon(Icons.menu))),
            ),
          ),
          // Preview: Card
          Positioned(
            left: 80, top: 12, right: 12, height: 74,
            child: GlassCard(
              section: GlassSection.card,
              tintColor: const Color(0xFFBFE7FF),
              borderRadius: 22,
              child: const Center(child: Text('Card Preview')),
            ),
          ),
          // Preview: Capsule card
          Positioned(
            left: 80, top: 94, right: 12, height: 72,
            child: GlassCard(
              section: GlassSection.card,
              tintColor: const Color(0xFFF7C9A9),
              borderRadius: 999,
              child: const Center(child: Text('Capsule Preview')),
            ),
          ),
        ],
      ),
    );
  }
}
```

## 5. API / RPC

```sql
-- ดึง glass settings ของ user
CREATE OR REPLACE FUNCTION get_user_glass_settings(
  p_user_id UUID,
  p_profession_id UUID
) RETURNS JSONB AS $$
  SELECT jsonb_build_object(
    'sidebar_opacity', glass_opacity_sidebar,
    'cards_opacity', glass_opacity_cards,
    'dialog_opacity', glass_opacity_dialog,
    'blur_level', glass_blur_level
  )
  FROM user_dashboard_themes
  WHERE user_id = p_user_id AND profession_id = p_profession_id;
$$ LANGUAGE plpgsql;

-- บันทึก glass settings
CREATE OR REPLACE FUNCTION save_user_glass_settings(
  p_user_id UUID,
  p_profession_id UUID,
  p_sidebar_opacity DECIMAL(5,4),
  p_cards_opacity DECIMAL(5,4),
  p_dialog_opacity DECIMAL(5,4),
  p_blur_level INTEGER
) RETURNS VOID AS $$
  UPDATE user_dashboard_themes
  SET 
    glass_opacity_sidebar = p_sidebar_opacity,
    glass_opacity_cards = p_cards_opacity,
    glass_opacity_dialog = p_dialog_opacity,
    glass_blur_level = p_blur_level,
    updated_at = now()
  WHERE user_id = p_user_id AND profession_id = p_profession_id;
$$ LANGUAGE plpgsql;
```

## 6. Performance Considerations

| ปัญหา | แนวทางแก้ |
|-------|----------|
| **BackdropFilter กิน GPU** | จำกัด blur ≤ 12px (default 8px) |
| **หลาย layer glass ซ้อนกัน** | ใช้ `RepaintBoundary` แยก render layer |
| **Device เก่า** | ถ้า blur > 12px ให้ fallback เป็น solid color โดยอัตโนมัติ |
| **Animation lag** | ใช้ `AnimatedContainer` แทน `setState` ตรงๆ |

## 7. สรุปเวลาประมาณการ

| งาน | เวลา |
|-----|------|
| GlassCard widget + GlassSidebar | 4-6 ชม |
| GlassDialog + GlassButton | 3-4 ชม |
| Opacity Slider UI + Preview Box | 4-5 ชม |
| DB Schema + RPC + Provider | 3-4 ชม |
| Performance tuning + Testing | 4-6 ชม |
| **รวม** | **~20-28 ชม** |

## 8. ขั้นตอนการพัฒนา

1. **Phase 1:** สร้าง `GlassCard` widget + `GlassSection` enum
2. **Phase 2:** แก้ไข Sidebar ให้เป็น `GlassSidebar`
3. **Phase 3:** แก้ไข Module Cards ให้ใช้ `GlassCard`
4. **Phase 4:** สร้าง `showGlassDialog` helper
5. **Phase 5:** สร้างหน้า Settings — Glass Tab + Sliders + Preview
6. **Phase 6:** สร้าง DB columns + RPC + Provider (Riverpod)
7. **Phase 7:** Performance test บน device เก่า + fallback logic
