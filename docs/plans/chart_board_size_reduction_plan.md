# ChartBoardPage — แผนลดบรรทัดต่อเนื่องหลัง Refactor

ไฟล์: `lib/features/consultation/presentation/pages/chart_board_page.dart`
ขนาดปัจจุบัน: **~4,211 บรรทัด**
เป้าหมายสุดท้าย: **~1,800-2,000 บรรทัด**

---

## หลักการ
- ทำทีละ phase
- Build + Run + Smoke test หลังแต่ละ phase
- ห้ามเปลี่ยน behavior
- ใช้ `flutter analyze` เป็น guard rail

---

## Phase A: Remove Dead Code

### Goal
ลบ method ที่ analyzer แจ้ง `unused_element`

### Targets
| Method | บรรทัด | แหล่งที่มา |
|--------|--------|-----------|
| `_buildFinishButton` | ~20 | `unused_element` |
| `_showQuickReplies` | ~50 | `unused_element` |
| `_buildReviewCard` | ~80 | `unused_element` |

### ขั้นตอน
1. `flutter analyze` → note line numbers
2. `grep -n "_buildFinishButton\|_showQuickReplies\|_buildReviewCard" chart_board_page.dart`
3. ลบ method ทั้งบล็อก
4. `flutter analyze` อีกครั้ง

### Test
- Build ผ่าน
- App เปิดได้

### ผลลัพธ์: **~150 บรรทัด**

---

## Phase B: Extract Pure Utility Helpers

### Goal
ย้าย helper functions ที่ไม่พึ่ง BuildContext หรือ state ไป utility files

### New Files
```
utils/
  chart_metric_helpers.dart    → formatMetricValue, formatMetricDate, metricNameTh, metricChartColor, buildSpots
  timer_formatter.dart         → formatTimer(int seconds)
  body_area_formatter.dart     → resolveBodyAreaText(bodyAreas)
```

### ขั้นตอน
1. สร้าง utility file
2. Copy method (pure only — ไม่ใช้ widget., setState, context)
3. เปลี่ยน `_` prefix → public
4. Replace call site + ลบเดิม

### Test
- Chart metric แสดงถูก (ค่า, สี, label)
- Timer badge "MM:SS" ถูกต้อง
- Body area text ถูกต้อง

### ผลลัพธ์: **~350 บรรทัด**

---

## Phase C: Extract Health Data Display Widgets

### Goal
แยก UI ข้อมูลสุขภาพที่ผู้ป่วยอนุญาตแล้ว เป็น stateless widgets

### New Files (widgets/health_data/)
```
granted_health_sections.dart      → _buildGrantedHealthSections + _buildGrantedSectionCard
general_section_content.dart      → _buildGeneralSectionContent + _buildHealthDataChip
weight_history_card.dart          → _buildWeightHistoryCard + chart helpers
metric_group_card.dart            → _buildMetricGroup + _buildMetricLineChartData
history_tile.dart                 → _buildHistoryTile
medication_tile.dart              → _buildMedicationTile
health_data_error_view.dart       → _buildHealthDataError
```

### ขั้นตอน
1. สร้าง file ทีละตัว
2. เปลี่ยน method → widget class
3. ส่ง data ผ่าน constructor (ไม่ใช้ widget state)
4. แทนที่ใน `_openGrantedHealthDataSheet()`

### Test
- Provider เปิด health data sheet → ข้อมูลครบ
- กราฟ weight + metrics แสดงผล
- Chart tooltip ทำงาน

### ผลลัพธ์: **~900 บรรทัด**

---

## Phase D: Extract Banner & Card Widgets

### Goal
แยก UI ที่แสดงตาม state ออกเป็น widgets แยก

### New Files (widgets/)
```
expert_status_banner.dart              → _buildExpertStatusBanner
health_permission_status_banner.dart   → _buildHealthPermissionStatusBanner
pain_level_selector.dart               → _buildPainLevelSelector
payment_card.dart                      → _buildPaymentCard
prescription_card.dart                 → _buildPrescriptionCard
summary_card.dart                      → _buildSummaryCard
message_bubble.dart                    → _buildMessageBubble (text only)
```

### ขั้นตอน
1. เริ่มจาก banner (ไม่มี callback)
2. รับ data + callback ผ่าน constructor
3. แทนที่ใน build / _buildXxx

### Test
- Provider banner แสดง expert status ถูก
- Patient เห็น pain level + payment card
- Prescription/summary cards ข้อมูลถูก
- Click handlers ทำงาน

### ผลลัพธ์: **~750 บรรทัด**

---

## Phase E: Extract Health Permission Mixin (Optional)

### Goal
ย้าย health permission realtime + polling เป็น mixin

### New File
```
mixins/health_permission_mixin.dart
```

Content: `healthPermissionRequest`, `lastShownId`, `dialogOpen`, `pollTimer`, `channel`, `subscribe`, `loadLatest`, `requestPermission`, `showDialog`, `openSheet`

### ขั้นตอน
1. สร้าง mixin
2. ย้าย state + methods + lifecycle hooks
3. `_ChartBoardPageState with HealthPermissionMixin`
4. ทดสอบ provider + patient ละเอียด

### Test
- Provider ขอ health data → patient dialog ทันที
- Patient approve → provider sheet อัปเดต
- Reject → provider เห็น rejected

### ผลลัพธ์: **~400 บรรทัด**

---

## Summary of Impact

| Phase | ลดบรรทัด | ความเสี่ยง | Cumulative |
|-------|----------|-----------|------------|
| Current | — | — | 4,211 |
| A: Dead code | ~150 | ต่ำมาก | ~4,060 |
| B: Utilities | ~350 | ต่ำ | ~3,710 |
| C: Health data widgets | ~900 | ต่ำ | ~2,810 |
| D: Banner & cards | ~750 | ต่ำ-กลาง | ~2,060 |
| E: Mixin (optional) | ~400 | กลาง | ~1,660 |

**ถ้าทำ A+B+C+D:** เหลือ ~2,060 บรรทัด
**ถ้าทำทั้งหมด:** เหลือ ~1,660 บรรทัด

---

## Verification Checklist หลังแต่ละ Phase

- [ ] `flutter analyze` ผ่าน (0 error)
- [ ] `flutter run` เปิดได้
- [ ] Provider flow: รับงาน → เข้าห้อง → เห็น chat + health banner
- [ ] Patient flow: กด submit → chat unlock → back → profile tab 2
- [ ] Timer: นับถอยหลัง + badge เปลี่ยนสี
- [ ] Health permission: provider ขอ → patient อนุมัติ → provider เห็น data
- [ ] No crash on hot reload

---

## Rollback Strategy

- แต่ละ phase ทำบน branch แยก หรือ commit ทีละ phase
- ถ้า phase ใด fail → `git revert <commit>` แล้วข้ามไป phase ถัดไป
- ไม่รวบหลาย phase ใน commit เดียว
