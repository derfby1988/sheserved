# ERP Glassmorphism Plan Integration — Document Organization

ผนวกแผน Glassmorphism + Opacity Control จาก `.windsurf/plans/full-glassmorphism-opacity-plan-552304.md` เข้าสู่เอกสาร ERP อย่างเป็นทางการ โดยสร้างเอกสารลูก `ERP_GLASSMORPHISM_PLAN.md` ใน `/docs/ERP/` และให้ `ERP_CORE_ARCHITECTURE.md` อ้างอิง

## งานที่ต้องทำ

### 1. สร้าง `ERP_GLASSMORPHISM_PLAN.md` ใน `/docs/ERP/`

ย้ายเนื้อหาจาก `full-glassmorphism-opacity-plan-552304.md` ไปยังเอกสารถาวร:

- **Glassmorphism Widgets** — `GlassCard`, `GlassSidebar`, `GlassDialog`, `GlassButton`
- **Opacity Sliders** — 3 sliders: Sidebar / Cards / Dialog (ช่วง 0-50%, default 20%)
- **Blur Slider** — รวม 2-20px (default 8px)
- **Preview Box** — อัปเดตเรียลไทม์ในหน้า settings
- **DB Schema** — `glass_opacity_*` + `glass_blur_level` columns ใน `user_dashboard_themes`
- **API/RPC** — `get_user_glass_settings()` + `save_user_glass_settings()`
- **Performance** — BackdropFilter limits, fallback logic

### 2. อัปเดต `ERP_CORE_ARCHITECTURE.md`

เพิ่มส่วนอ้างอิงหลัง "การปรับแต่งธีมสี Dashboard" (`:289-560`):

```markdown
### 4.6 การปรับแต่งระดับความโปร่งใส (Glassmorphism)

ผู้ใช้สามารถปรับระดับความโปร่งใส (Opacity) และความเบลอ (Blur) ของ UI แบบแก้วโปร่งใสได้
ดูรายละเอียดใน [ERP_GLASSMORPHISM_PLAN.md](ERP_GLASSMORPHISM_PLAN.md)
```

### 3. สอดคล้องกับเอกสารอื่น

| เอกสาร | การอ้างอิง |
|--------|-----------|
| `ERP_CORE_ARCHITECTURE.md` | อ้างอิง `ERP_GLASSMORPHISM_PLAN.md` |
| `CRM_SYSTEM_PLAN.md` | ใช้ `GlassCard` ใน CollapsibleSidebar (อัปเดต code skeleton ให้ใช้ dynamic opacity) |
| `ERP_NOTIFICATION_SYSTEM_PLAN.md` | Badge บน sidebar ใช้ `errorColor` จาก theme (ไม่กระทบ glass) |

## สรุปเวลา

| งาน | เวลา |
|-----|------|
| สร้าง `ERP_GLASSMORPHISM_PLAN.md` | 1-2 ชม |
| อัปเดต `ERP_CORE_ARCHITECTURE.md` | 15 นาที |
| อัปเดต `CRM_SYSTEM_PLAN.md` code skeleton | 30 นาที |
| **รวม** | **~2-3 ชม** |
