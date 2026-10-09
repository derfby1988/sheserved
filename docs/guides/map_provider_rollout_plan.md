# แผนรองรับ Google Maps และ OSM-based Tiles สำหรับ Sheserved

> **วันที่สร้าง:** 2026-10-04
> **สถานะ:** อยู่ระหว่าง rollout — Phase 0/1/2 เสร็จแล้ว (หลักฐาน: `docs/evidence/map_provider_phase0..2/`); Phase 3 implement + test แล้ว รอ device smoke ([รายงาน](../evidence/map_provider_phase3/phase3_report.md)); Phase 4–8 ยังไม่เริ่ม
> **ขอบเขต:** Web, iOS, Android และระบบย่อยที่มีหรือจะมีแผนที่ใน Sheserved
> **เอกสารอ้างอิงที่ต้อง reconcile:** `docs/plans/Match_Sport_PLAN.md`, `docs/plans/VIDEO_SYSTEM_PLAN.md`, `docs/plans/Delivery_PLAN.md`, `docs/guides/ui_rendering_standards.md`, `docs/plans/ui_rendering_standards.md`, `docs/guides/flutter_web_enablement_plan.md`, `docs/secure/google_maps_key_restriction_guide.md`

---

## 1. เป้าหมายและหลักการ

เพิ่มความสามารถให้ผู้ดูแลระบบเลือกใช้แผนที่ระหว่าง Google Maps และแผนที่ที่ใช้ข้อมูล OpenStreetMap (OSM) ผ่านหน้า Platform Settings โดยไม่ผูกทั้งแอปไว้กับผู้ให้บริการรายเดียว และไม่ทำให้พฤติกรรมเดิมของระบบฉุกเฉินเสียหาย

### 1.1 หลักการบังคับ (invariants)

1. **แยกตามแพลตฟอร์ม:** Web, iOS, Android มีค่าเริ่มต้นของตนเองได้
2. **แยกตามระบบย่อย:** ระบบย่อยเลือกใช้ค่าของแพลตฟอร์ม หรือกำหนด override เองได้
3. **ไม่ผูกกับ tile source เดียว:** OSM เป็นแนวทางข้อมูล ไม่ใช่เซิร์ฟเวอร์เดียว ต้องมี registry ของ tile source ที่ตรวจสอบและอนุมัติแล้ว
4. **แยก map renderer ออกจาก tile source:** Google ใช้ Google renderer, OSM ใช้ `flutter_map` + tile source ที่เลือก
5. **แยกแผนที่ออกจากบริการประกอบ:** routing, place search, traffic เป็น provider คนละชั้นกับการแสดง basemap
6. **ห้าม fallback ไป Google อย่างเงียบ ๆ:** การสลับ provider อัตโนมัติอาจเกิดค่าใช้จ่ายและทำให้เข้าใจผิด ต้องแสดงสถานะหรือใช้ fallback ที่ admin อนุมัติเท่านั้น
7. **Platform Settings ต้องบันทึกค่าจริง:** ปัจจุบันเป็น state ในหน่วยความจำและ Save ไม่ persist
8. **ไม่ใส่ secret ใน client config:** ค่าที่ client อ่านได้ต้องไม่มี API key/credential ลับ
9. **ค่าเริ่มต้นต้องปลอดภัย:** config โหลดไม่ได้/ไม่รู้จัก ต้องถอยไปค่า default ที่ฝังมากับแอป ไม่ตีความเป็น Google Web อัตโนมัติ

### 1.2 สิ่งที่ไม่ทำใน rollout นี้

- ไม่ลบ Google Maps dependency หรือถอน Google ออกจากระบบ
- ไม่ย้าย routing (Google Directions) ไป OSRM อัตโนมัติ
- ไม่ทำ offline tile download หรือ bulk prefetch
- ไม่สร้าง interactive map ใหม่ในหน้าที่ปัจจุบันไม่มีแผนที่
- ไม่ใช้ Leaflet เป็น renderer หลัก (เป็น JavaScript renderer ไม่ใช่ Flutter ข้ามแพลตฟอร์ม)

---

## 2. สถานะปัจจุบัน (ตรวจสอบจากโค้ด)

### 2.1 Dependency

`flutter_map`, `latlong2`, `flutter_map_cancellable_tile_provider` มีอยู่ใน `pubspec.yaml` แล้ว จึงเริ่ม OSM raster renderer ได้โดยยังไม่ต้องเพิ่ม dependency พื้นฐาน (`pubspec.yaml:46-49,99`) ส่วน `google_maps_flutter` ยังคงเป็น dependency หลักของแผนที่ปัจจุบัน

**Leaflet:** เป็น JavaScript map library สำหรับเว็บ ไม่ควรเป็นตัวเลือกใน Flutter Settings เพราะต้องดูแล WebView/JS bridge แยกจากแอปมือถือ ตัวเทียบเท่าใน Flutter คือ `flutter_map` ซึ่งใช้ API กลางข้าม Web/iOS/Android ได้

### 2.2 Provider settings (อัปเดตหลัง Phase 1)

~~`PlatformService` เก็บ master switch และค่ารายหน้าของ Web ในหน่วยความจำ~~ — Phase 1 เพิ่ม provider config ที่ persist จริงแล้ว: ตาราง `map_provider_config` (+audit), endpoints `GET /api/map-config`, `GET/PUT /api/admin/map-config` + history/rollback (admin-only, optimistic revision), model `lib/features/admin/models/map_provider_config.dart` (registry + `resolveTarget(feature, platform)`), `MapConfigService` (safe default เมื่อ server ล่ม) และ section ใหม่ใน Platform Settings (draft/save/conflict/rollback)

ข้อจำกัดเดิมที่ยังอยู่: config ยังไม่ได้ขับ renderer ของ production map (Phase 3+ เป็นคนต่อ) และ `PlatformService`/`shouldShowLiveMap()` เดิมยังทำงานแยกจาก config ใหม่นี้

### 2.3 ระบบย่อยที่ใช้ Google Maps อยู่

| ระบบย่อย | สภาพปัจจุบันและผลกระทบ |
|---|---|
| Home Map | `GoogleMap` + ตำแหน่งผู้ใช้, emergency markers, polylines, camera control; controller เป็นชนิด Google โดยตรง (`home_map_background.dart:44-58,365-439`) |
| Emergency Live Map | Google markers/polylines และ `trafficEnabled: true`; ต้องรองรับ responder markers และเส้นทาง real-time (`map_background_widget.dart:37-64,139-169`) |
| Rescue Map | `GoogleMap` + Google Directions REST (`rescue_page.dart:417-451,524-538`) |
| Group Create Map | Google map ปักหมุด + fullscreen picker; Web มี fallback UI; search ใช้ Nominatim ก่อน + Google Places fallback (`create_group_page.dart:2284-2287,2454-2558`) |
| Yield Way Dialog | `GoogleMap` แสดงตำแหน่ง/เส้นทางฉุกเฉิน; ควรใช้ provider config เดียวกับ Emergency (`yield_way_map_dialog.dart:194-229`) |
| Sport Club / Book Court | Map View ของ Sport Club ถูกนำออกแล้ว; ยังไม่มี interactive map canvas ของ Book Court — ห้ามแสดง toggle ที่ไม่มีแผนที่ให้สลับ |
| Delivery | เป็นแผน ยังไม่มี renderer ในโค้ด; ต่อ shared config เมื่อเริ่มพัฒนาแผนที่ติดตามจริง |

### 2.4 Metrics และค่าใช้จ่ายมีสมมติฐานที่ต้องแก้

System Monitor คูณ `$7/1,000` กับทุก metric ที่ขึ้นต้น `map_load_` โดยไม่แยก platform/provider (`system_monitor_service.dart:95-115`) จึงรายงานผิดเมื่อมีหลาย provider ร่วมกัน และ "จำนวนครั้งเปิดแผนที่" ไม่เท่ากับจำนวน tile requests หรือ billable requests

---

## 3. แบบจำลอง provider และตัวเลือกที่รองรับ

แยกค่าตั้งออกเป็น 5 ชั้น เพื่อไม่ให้คำว่า "OSM" ถูกใช้แทนทุกชั้น:

| ชั้น | ตัวอย่างค่า | หมายเหตุ |
|---|---|---|
| Map renderer | `google_maps_flutter`, `flutter_map` | ตัววาดแผนที่ |
| Tile source | Google basemap, OSM-derived provider | แหล่ง tile เมื่อใช้ `flutter_map` |
| Place search | Nominatim, Google Places | ค้นหา/geocode |
| Routing | Google Directions, OSRM, บริการที่อนุมัติ | หาเส้นทาง |
| Traffic overlay | Google traffic, provider อื่น, ไม่มี | ข้อมูลจราจร |

### 3.1 Tile source registry

Platform Settings แสดงเฉพาะ source ที่ configure และผ่านการตรวจสอบแล้ว การเพิ่ม source ใหม่ต้องมีการเพิ่ม allowlist + CSP + เงื่อนไขการใช้ที่สอดคล้องกัน **ไม่รับ arbitrary URL จาก DB หรือผู้ใช้**

| ตัวเลือก | ขอบเขตและข้อควรพิจารณา |
|---|---|
| Google Maps | คงเป็นตัวเลือกหลักเดิม; Web ใช้ Google Maps JavaScript API เฉพาะเมื่ออนุมัติ key/budget |
| OSM Standard tiles | development/QA ปริมาณต่ำตามนโยบาย; ไม่ใช่ production แบบไม่จำกัด |
| Managed OSM-based tiles | เป็น candidate production ได้หลังประเมินราคา, quota, SLA, CORS, คุณภาพแผนที่ไทย, attribution, key restrictions, privacy |
| Self-hosted OSM-compatible tiles | ลดการพึ่ง third party; มีภาระ server/storage/update/bandwidth/monitoring |
| Vector/MapLibre | ประเมินอนาคต ไม่รวมใน rollout แรก |

### 3.2 ค่าเริ่มต้นที่แนะนำ

| แพลตฟอร์ม/ระบบ | ค่าเริ่มต้นช่วง rollout | หมายเหตุ |
|---|---|---|
| Web | OSM renderer + source ที่ผ่าน CORS/CSP | Google JS API ไม่เปิดเป็นค่าเริ่มต้น |
| iOS / Android | คง Google ก่อน | เลือก OSM ได้ต่อระบบย่อยหลัง QA |
| Emergency / Rescue | คง Google เป็นค่าเริ่มต้น | เลือก OSM ได้หลังยืนยันว่าไม่มี traffic layer และผ่าน safety gate |
| Yield Way | สืบทอดจาก Emergency | ห้ามให้ dialog กับหน้า live ใช้ basemap คนละแบบ |
| ระบบที่ยังไม่มีแผนที่ | ไม่มี selector ที่ใช้งานได้ | เพิ่ม feature key เมื่อมี map จริง |

---

## 4. Platform Settings — UX ที่แนะนำแบบครบถ้วน

> เป้าหมาย: หน้าเดียวที่ผู้ดูแลเห็นสถานะรวม แก้ค่าได้ครบทุกชั้น ตรวจผลก่อนบันทึก และย้อนกลับได้อย่างปลอดภัย

### 4.1 โครงสร้างหน้าและลำดับ section

หน้าเดิมเป็น `CustomScrollView` + `SliverAppBar` + `Column` ของการ์ด (`platform_settings_page.dart:51-193`) ให้คงโครงและ AppBar เดิม แล้วจัดลำดับ section ใหม่ดังนี้

```text
SliverAppBar("Platform Settings")
└─ SliverToBoxAdapter > Column
   1. Map Service Status Banner        (สถานะรวม + provider ที่มีผลจริง + config revision)
   2. Usage & Cost Guardrails          (ปรับจาก _buildUsageStats + _buildCostWarningCard)
   3. Provider Registry                (รายการ provider/source + readiness)
   4. Platform Defaults                (Web / iOS / Android)
   5. Feature Overrides                (Home / Emergency / Rescue / Group Create / Yield Way)
   6. Service Providers                (Routing / Place Search / Traffic)
   7. Fallback & Failure Policy
   8. Effective Configuration Preview  (ตาราง resolve platform × feature)
   9. Configuration History            (revision ล่าสุด + ปุ่มย้อนกลับ)
└─ Sticky Save Bar (ด้านล่าง, แสดงเมื่อมี unsaved changes)
```

**เหตุผลของลำดับ:** ผู้ดูแลควรเห็น "ตอนนี้ใช้อะไรอยู่" ก่อนแก้ จากนั้นตั้งค่าเป็นชั้น (platform → feature → บริการประกอบ) แล้วตรวจผลรวมก่อนบันทึก

### 4.2 สเปกแต่ละ section

#### 4.2.1 Map Service Status Banner

การ์ดด้านบนสุด แสดงสรุปแบบอ่านเร็ว:

- **สถานะรวม:** `ปกติ` / `มีคำเตือน` / `config โหลดไม่ได้`
- **Provider ที่มีผลกับเครื่องที่กำลังดู:** resolve ตามแพลตฟอร์มปัจจุบัน (Web แสดง Web default)
- **Tile source ที่มีผล** และ **Attribution ที่ต้องแสดง**
- **Config revision + แก้ไขล่าสุด:** ใคร/เมื่อไร
- ปุ่ม `รีเฟรช config` และ `ดูรายละเอียด`

สถานะเตือนตัวอย่าง: tile source ที่ config อ้างถึงไม่อยู่ใน allowlist ของเวอร์ชันแอปนี้ / Google Web key ไม่พร้อม / config โหลดไม่ได้และกำลังใช้ค่า default

#### 4.2.2 Usage & Cost Guardrails

ปรับของเดิมให้แยกมิติ:

- **Map sessions** แยก platform และ provider (ไม่ใช้ `$7/1,000` กับทุกอย่าง)
- **Tile/egress** (ถ้ามีข้อมูลจาก provider/proxy) แยกจาก session count
- **Billable events ของ Google** ตาม SKU ที่ตั้งไว้ใน rate config
- **Routing / Search** แยกเป็นอีกกลุ่ม
- แสดง `ยังประเมินต้นทุนไม่ได้` เมื่อไม่มี rate หรือ usage data แทนการแสดง `$0`
- **ห้ามแสดงพิกัดผู้ใช้/จุดเกิดเหตุ** ในส่วนนี้

#### 4.2.3 Provider Registry

ตาราง/ลิสต์ provider และ tile source พร้อม readiness badge:

| คอลัมน์ | ความหมาย |
|---|---|
| ชื่อ + ประเภท | renderer / tile source / routing / search / traffic |
| สถานะ | `พร้อมใช้` / `ต้องตั้งค่า` / `ปิดโดยนโยบาย` |
| เงื่อนไข | เช่น ต้องมี key, ต้อง deploy CSP, ต้องอนุมัติ budget |
| หมายเหตุ compliance | attribution, ข้อจำกัดการใช้งาน, region/privacy |

Registry นี้ **อ่านอย่างเดียวในหน้านี้** การเพิ่ม source ใหม่ทำผ่านโค้ด/config ที่ deploy (allowlist + CSP) แล้วจึงปรากฏให้เลือก

#### 4.2.4 Platform Defaults

การ์ดต่อแพลตฟอร์ม (Web / iOS / Android) — ปรับจาก `_buildPlatformCard` เดิม (`platform_settings_page.dart:440-564`) แต่เพิ่ม:

- `เปิดใช้แผนที่` switch (แยกจาก provider)
- `Provider` selector: `Google Maps` / `OpenStreetMap (flutter_map)`
- `Tile source` dropdown (แสดงเมื่อเลือก OSM; disable เมื่อเลือก Google)
- `ปุ่มทดสอบแผนที่` (Test map)
- `Fallback` selector (ปิดเป็นค่าเริ่มต้น)
- คำอธิบายผลกระทบและคำเตือน (เช่น Web + Google ต้องมี key/budget)

#### 4.2.5 Feature Overrides

การ์ดต่อระบบย่อย แต่ละการ์ดมีโหมด:

- `ใช้ค่าของแพลตฟอร์ม` (inherit) — ค่าเริ่มต้น
- `กำหนดเอง` (override) — เปิด selector provider/tile source เฉพาะระบบนั้น

Feature keys ที่รองรับตอนนี้: `home`, `emergency`, `rescue`, `group_create` และ `yield_way` (สืบทอด `emergency` แบบบังคับ ไม่ให้แก้แยก)

ระบบอนาคต (`sport_club_map`, `book_court_map`, `find_coach_map`, `delivery_tracking_map`) จะปรากฏเมื่อมี map จริงเท่านั้น

#### 4.2.6 Service Providers

แยกจาก basemap อย่างชัดเจน:

- **Routing:** Google Directions / OSRM / ปิด (พร้อมคำเตือน CORS บน Web)
- **Place Search:** Nominatim / Google Places fallback (พร้อม rate limit)
- **Traffic overlay:** Google / provider อื่น / ไม่มี (แสดงผลกระทบต่อ Emergency)

#### 4.2.7 Fallback & Failure Policy

- `Fallback provider`: ปิดเป็นค่าเริ่มต้น; เปิดได้เฉพาะ provider ที่อนุมัติ
- `พฤติกรรมเมื่อ tile โหลดไม่ได้`: แสดง map error / placeholder / ใช้ fallback ที่อนุมัติ
- **ห้าม fallback ไป Google อัตโนมัติ** โดยไม่แสดงสถานะและไม่บันทึก provider ที่ใช้จริง

#### 4.2.8 Effective Configuration Preview

ตาราง resolve `platform × feature` ให้เห็นค่าที่จะถูกใช้จริง พร้อมป้าย `inherit` / `override` และป้ายเตือนถ้าค่าไม่ valid ช่วยจับ conflict ก่อนบันทึก

#### 4.2.9 Configuration History

- revision ล่าสุด N รายการ: actor, เวลา, diff สรุป, environment
- ปุ่ม `ย้อนกลับ revision นี้` (rollback) พร้อมยืนยัน
- ปุ่ม `รีเซ็ตเป็นค่า default`

### 4.3 Component spec (รายละเอียดควบคุม)

| Component | พฤติกรรม | หมายเหตุการผูกโค้ด |
|---|---|---|
| `MapStatusBanner` | อ่าน effective config + revision; ปุ่ม refresh/detail | ใช้ `AppColors` เดิม, คงสไตล์การ์ด `0xFF1a1a2e` ได้ |
| `MapEnabledSwitch` | เปิด/ปิดแผนที่ต่อแพลตฟอร์ม | คง `Switch.adaptive` เดิม |
| `MapProviderSelector` | segmented control: Google / OSM | disable ตัวเลือกที่ registry ไม่พร้อม + tooltip เหตุผล |
| `TileSourceDropdown` | เลือก source จาก registry | disable เมื่อ provider = Google; ต้องเลือกก่อน save |
| `TestMapButton` | เปิด preview แผนที่ขนาดเล็ก | ใช้พิกัดทดสอบคงที่ + แสดง attribution + ไม่ log metrics + rate limit |
| `FeatureOverrideTile` | inherit / override ต่อ feature | `yield_way` ล็อก inherit จาก emergency |
| `ServiceProviderRow` | routing/search/traffic | แยกกลุ่มชัดเจนจาก basemap |
| `EffectiveConfigTable` | ตาราง resolve | เตือน conflict แบบ inline |
| `StickySaveBar` | แสดงเมื่อ dirty: `บันทึก` / `ยกเลิก` | disabled ระหว่าง saving/validation error |
| `RevisionHistoryList` | ประวัติ + rollback | ใช้ glass dialog ยืนยัน |

**Dialog ที่ควรใช้:** ใช้ glass layer ที่มีอยู่ (`GlassConfirmDialog.show` สำหรับยืนยัน, `GlassDialog.show` สำหรับเนื้อหา custom) ให้สอดคล้องกับ Sport Club/ERP และคุมความสูงให้ scroll ได้บนจอเล็ก

### 4.4 State model และ data binding

State ที่หน้า Settings ต้องถือ:

```text
configLoading | configError | configLoaded
draftConfig (แก้ไขในหน่วยความจำ)
savedConfig  (revision ที่บันทึกแล้ว)
dirty        (draftConfig != savedConfig)
saving | saveError | saved
conflict     (revision ใหม่กว่าถูกบันทึกไปแล้ว)
previewOpen  (test map)
```

- โหลด config ตอน `initState` ผ่าน config service (ไม่ผูกกับ widget)
- `draftConfig` แยกจาก `savedConfig` เพื่อทำ unsaved-changes guard
- resolve effective config ด้วยฟังก์ชันกลางที่ใช้ร่วมกับ runtime map widget (แหล่งเดียว)
- เมื่อบันทึกสำเร็จ: อัปเดต `savedConfig` + revision + แสดง toast
- เมื่อเกิด conflict: แจ้งและให้โหลดใหม่/เทียบ diff ก่อนบันทึกทับ

### 4.5 Validation rules

บังคับใช้ทั้งฝั่ง client และ server:

1. เลือก provider/source ที่ registry ไม่พร้อม → save ไม่ได้ + แสดงเหตุผล
2. เลือก OSM แต่ไม่ระบุ tile source → save ไม่ได้
3. เปิด Google บน Web โดยไม่มี key/budget ที่อนุมัติ → เตือนและต้องยืนยัน
4. เปลี่ยน provider ของ Emergency/Rescue → ต้องยืนยัน acknowledgement ว่า traffic layer หาย (เมื่อ OSM)
5. `yield_way` ต้อง inherit จาก `emergency` เสมอ
6. ค่าใน production ต้องมี reason/หมายเหตุ และยืนยันพิเศษ
7. tile source ที่ต้อง deploy CSP แต่ยังไม่ deploy → บล็อกพร้อมข้อความ
8. feature key ที่ไม่รู้จัก → ignore พร้อม warning ไม่ทำให้ทั้ง config พัง

### 4.6 Save / apply / revision / audit

- **Transport:** บันทึกผ่าน backend admin endpoint (เช่น `PUT /api/admin/map-config`) ที่ตรวจ `requireRole('admin')` + audit — ไม่เขียนตาราง config จาก client โดยตรง
- **Concurrency:** ใช้ optimistic concurrency (revision / `If-Match`) กันเขียนทับ
- **Audit:** actor, environment, ค่าเดิม/ใหม่, revision, timestamp, reason
- **Apply policy:** มีผลกับ map instance ที่สร้างใหม่; Emergency/Rescue ที่กำลัง active ให้คง provider เดิมจนจบ flow
- **Force reload maps:** มีเฉพาะ dev/admin ขั้นสูง พร้อมคำเตือน

### 4.7 Unsaved changes และ concurrent edit

- `PopScope`/`WillPopScope` เตือนเมื่อออกทั้งที่ dirty
- ปุ่ม Save disabled จนกว่า validation ผ่าน
- ถ้า admin คนอื่นบันทึก revision ใหม่ระหว่างแก้ → ขึ้น conflict banner + ตัวเลือก `โหลดใหม่` / `ดู diff`

### 4.8 Permission และ roles

- หน้าอยู่หลัง `AuthGuardWidget(requiredRole: 'admin')` อยู่แล้ว (`lib/main.dart:298-301`)
- เพิ่ม server-side check ที่ endpoint เสมอ (client guard เป็นเพียง UX)
- อนาคต: แยก permission `platform.map.manage` ออกจาก role `admin` เมื่อระบบ permission ละเอียดพร้อม (สอดคล้องแนวทาง least-privilege ที่มีอยู่ในแผนเดิม)
- ผู้อ่านที่ไม่ใช่ admin เห็นเฉพาะข้อมูลปลอดภัย ไม่เห็น secret

### 4.9 Loading / empty / error states

| สถานะ | UI |
|---|---|
| กำลังโหลด config | skeleton ในแต่ละ section + disable Save |
| โหลด config ไม่ได้ | banner error + `ลองใหม่` + ใช้ค่า default ที่ฝั่งแอป |
| registry ว่าง/ไม่มี source พร้อม | empty state อธิบายว่าต้อง deploy allowlist/CSP |
| ไม่มี metrics | "ยังไม่มีข้อมูลการใช้งาน" (คงของเดิม) |
| save ล้มเหลว | inline error + คงค่า draft ไว้ให้ retry |

### 4.10 Accessibility

- hit target ≥ 44×44 dp ทุกปุ่ม/switch
- ทุก control มี `Semantics`/`tooltip` และ label ภาษาไทย
- ไม่พึ่งสีอย่างเดียว (ใช้ icon/ข้อความกำกับสถานะ)
- รองรับ text scaling และ keyboard navigation บน Web
- ตาราง Effective Config อ่านออกด้วย screen reader

### 4.11 Copy (ข้อความไทยแนะนำ)

| จุด | ข้อความ |
|---|---|
| หัวข้อ section 4 | `ค่าเริ่มต้นตามแพลตฟอร์ม` |
| หัวข้อ section 5 | `การตั้งค่าเฉพาะระบบ` |
| หัวข้อ section 6 | `บริการประกอบ (เส้นทาง / ค้นหา / จราจร)` |
| inherit | `ใช้ค่าของแพลตฟอร์ม` |
| override | `กำหนดเอง` |
| OSM ไม่มี traffic | `แผนที่นี้ไม่มีข้อมูลจราจรแบบเรียลไทม์` |
| Google บน Web เตือน | `การเปิด Google Maps บน Web อาจมีค่าใช้จ่าย ต้องมี key และงบที่อนุมัติ` |
| fallback ปิด | `ไม่สลับผู้ให้บริการอัตโนมัติ` |
| save | `บันทึกการตั้งค่า` |
| conflict | `มีการบันทึกจากผู้ใช้อื่นหลังจากคุณเริ่มแก้ไข` |

### 4.12 Edge cases

1. provider ที่ config อ้างถึงถูกถอดจาก registry → ใช้ environment default + เตือน
2. tile source ถูกปิดโดย CSP ที่ยังไม่ deploy → validation บล็อกการ save
3. เปลี่ยน provider ขณะมี Emergency active → เตือนและคง provider เดิมจนจบ flow
4. Google key หมดอายุ/ถูก restrict → banner เตือน พร้อม fallback ที่อนุมัติ (ถ้ามี)
5. config โหลดช้า → ไม่ block การ render หน้า; ใช้ค่า default ไปก่อน
6. admin สองคนแก้พร้อมกัน → conflict handling ตาม 4.7
7. เลือก OSM บน Web แต่ tile host ไม่รองรับ CORS → ตรวจใน Test map ก่อน save

---

## 5. Backend, config contract และ secrets

### 5.1 โครงสร้าง config

```text
revision: <int>
environment: dev | staging | prod
platformDefaults:
  web:     { enabled, renderer, tileSourceId }
  ios:     { enabled, renderer, tileSourceId }
  android: { enabled, renderer, tileSourceId }
featureOverrides:
  home: ...
  rescue: ...
  emergency: ...
  group_create: ...
services:
  routing:  { provider, enabled }
  search:   { primary, fallbackEnabled }
  traffic:  { provider }
fallback:
  enabled, providerId
rateConfig:
  googleWebMapPerThousand, googleDirectionsPerThousand, googlePlacesPerThousand
```

ลำดับ resolve: **feature override → platform default → environment default ที่ฝังมากับแอป**

### 5.2 ที่เก็บและการป้องกัน

- **ห้ามใช้ `app_settings` เดิมเป็น write path ตรง ๆ** เพราะ migration เปิด UPDATE/INSERT ให้ทุกคน (`20260308200500_create_system_settings.sql:8-20`) — ต้องเพิ่มตาราง/endpoint ที่มี authorization หรือแก้ policy
- **ห้ามใช้ `platform_metrics` เป็นที่เก็บ config** — เป็นตาราง counter
- public read ต้องผ่าน view/RPC ที่ส่งเฉพาะ field ที่ปลอดภัย ไม่มี secret
- key ที่ provider ตั้งใจให้เปิดเผยต่อ client ต้องจำกัด domain/app/package + quota; credential ลับอยู่ฝั่ง server
- ตรวจ Google key wiring ตาม `docs/secure/google_maps_key_restriction_guide.md` และ `ios/Runner/AppDelegate.swift` — ห้ามคัดลอก key ลงเอกสาร

---

## 6. Shared map architecture

สร้าง contract กลางก่อนแปลงทุกหน้า เพราะหลายส่วนรับ `GoogleMapController`, Google `LatLng`, `Marker`, `Polyline`, `CameraUpdate` โดยตรง

### 6.1 Data contract ที่ไม่ผูกกับ Google

model กลางสำหรับ: พิกัด/initial camera, marker (id, ตำแหน่ง, label, สี/icon, tap), polyline (จุด, สี, ความหนา, รูปแบบ), location/permission state, padding/fit bounds/tap, capability ของแต่ละ renderer ใช้ `latlong2` หรือ domain coordinate แล้วแปลงเป็นชนิดของแต่ละ renderer ภายใน adapter เท่านั้น

### 6.2 Controller facade

ให้หน้าจอเรียกคำสั่งกลาง (move camera, fit points/bounds, เปิด marker detail, รับ map tap) ไม่ส่ง `GoogleMapController` ออกไปถึง domain logic

- Google adapter: แปลง model กลางเป็น Google markers/polylines
- OSM adapter: วาด marker เป็น Flutter widget และ polyline ผ่าน `flutter_map`
- marker widget ที่ Google ใช้ bitmap ต้องมี adapter แปลง; OSM วาด widget ได้ตรง
- ตำแหน่งผู้ใช้ใช้ `Geolocator`/location state กลาง ไม่พึ่ง Google puck อย่างเดียว
- จัดการ zero-area bounds, พิกัดเดียว, controller disposed และ load failure โดยไม่ crash

---

## 7. บริการประกอบที่เกี่ยวข้อง

### 7.1 Routing

- เปลี่ยน basemap เป็น OSM **ไม่ได้ย้าย Google Directions** ออกจาก `rescue_page.dart`
- ระยะแรกคง Google Directions ตามเดิมใน platform ที่เรียกใช้อยู่
- Web ยังมีปัญหา CORS ของ Directions REST — OSM tiles ไม่ได้แก้ปัญหานี้
- หากเปิด route บน Web ต้องมี backend proxy หรือ routing provider ที่อนุมัติ
- Public OSRM demo ไม่ควรเป็น production routing backend

### 7.2 Traffic

- ปัจจุบัน Emergency เปิด Google traffic layer แต่ OSM ไม่มี traffic ในตัว
- เมื่อเลือก OSM: แสดง `แผนที่นี้ไม่มีข้อมูลจราจรแบบเรียลไทม์`
- ห้ามตีความว่าไม่มี overlay = ถนนไม่ติด
- หากต้องการ traffic บน OSM ให้ประเมิน overlay provider แยก (ค่าใช้จ่าย/สิทธิ์)
- คง Google เป็น default สำหรับงานฉุกเฉินจนกว่าจะผ่าน gate

### 7.3 Search / Geocoding

- Group Create ใช้ Nominatim อยู่แล้ว + Google Places fallback จึงไม่ต้องเปลี่ยนเพราะ renderer
- จำกัด Nominatim เป็น user-initiated search ไม่ทำ autocomplete ทุก keystroke (นโยบาย: สูงสุด 1 req/วินาที)
- แยก metrics ของ tile display กับ place search และแยก Google Places cost/key

### 7.4 เปิดแผนที่ภายนอก

เปลี่ยนข้อความ/action เป็น "เปิดในแอปแผนที่" หรือให้เลือกปลายทาง เมื่อ provider ในแอปเป็น OSM ไม่ควรให้ปุ่ม "เปิดใน Google Maps" เป็นความหมายเดียวโดยไม่มีคำอธิบาย

---

## 8. Tile usage, Attribution, Privacy และ Web deployment

### 8.1 OSM compliance

- แสดง attribution ตามที่ provider กำหนด รวม `© OpenStreetMap contributors` พร้อมลิงก์
- ใช้ HTTPS, ระบุ client ใน native requests และส่ง Referer ที่เหมาะสมบน Web
- เคารพ caching headers; ห้าม bulk download/prefetch/offline download เว้นแต่ provider อนุญาต
- ตรวจว่า cache ที่ `flutter_map` ใช้ตรงกับเงื่อนไข provider; อย่าสันนิษฐานว่า cancellable tile provider = persistent cache
- ใช้ OSM public Standard tiles สำหรับ dev/QA ปริมาณต่ำเท่านั้น; production ใช้ managed/self-hosted
- ห้ามใช้ provider สำรองเพื่อหลบ quota/ข้อห้ามของ primary โดยไม่มีข้อตกลง

นโยบายทางการ: [OSMF Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/) — ระบุ OSM data เปิดให้ใช้ แต่ tile servers ทรัพยากรจำกัด best-effort/no SLA, ต้องมี attribution, user-agent/Referer และ cache ตามข้อกำหนด

### 8.2 Web CSP / CORS

- ทดสอบ OSM tile loading บน Chrome ผ่าน Caddy dev/staging จริง
- เพิ่ม allowlist ของ tile hosts ที่เลือกใน CSP ตาม request จริง; อย่าเปิด wildcard กว้าง
- ตรวจ CORS ของ tile host และรักษา `Referrer-Policy` ที่ไม่ตัด Referer
- tile source จาก remote config ต้องอยู่ใน allowlist ที่ deploy CSP รองรับ — เปลี่ยนใน Settings อย่างเดียวเพิ่ม host ใหม่ไม่ได้
- Web กำหนด custom `User-Agent` เองไม่ได้; ใช้ origin/Referer ตามนโยบาย provider
- ปัจจุบัน CSP อยู่ที่ `websocket-server/Caddyfile.dev` และ `Caddyfile.staging`; staging ใช้ `strict-origin-when-cross-origin` และ `img-src https:` ซึ่งกว้าง ควรปรับเป็น allowlist เท่าที่เหมาะสมก่อน production

### 8.3 Location privacy

- tile requests เปิดเผย IP และพื้นที่ที่ร้องขอต่อ provider ได้
- ประเมิน retention/region/privacy terms ของ provider
- ไม่ส่งพิกัด GPS ละเอียดใน analytics/log ที่ไม่จำเป็น
- แยก public map requests จาก location telemetry
- พิจารณา self-hosted tiles หาก privacy ของระบบฉุกเฉินต้องลดการเปิดเผยต่อ third party

---

## 9. Metrics และ cost guardrails

- เก็บ `platform`, `feature`, `renderer`, `tileSourceId` และนับหนึ่งครั้งต่อ map session ที่พร้อมใช้จริง (ไม่นับทุก rebuild)
- แยกประเภท: map session / tile-egress / Google billable events / routing-search events
- ปรับ System Monitor ไม่ให้คูณ `$7/1,000` กับทุก `map_load_` และไม่ตีความ OSM public tiles เป็น "ฟรีไม่จำกัด"
- ถ้าไม่มี rate/usage data แสดง `ยังประเมินต้นทุนไม่ได้` แทน `$0`
- ห้ามบันทึกพิกัดผู้ใช้/จุดเกิดเหตุใน usage metrics

---

## 10. ลำดับ rollout ตามความสำคัญและความง่ายในการทดสอบ

| Phase | Priority / ความยากทดสอบ | สถานะ | ขอบเขตและ exit gate |
|---|---|---|---|
| 0. Baseline + เลือก tile-source profile | P0 / ง่ายมาก | ✅ เสร็จ 2026-10-06 — commit `0226c9f` ([รายงาน](../evidence/map_provider_phase0/phase0_report.md)) | ยืนยันตัวเลือก provider, key restrictions, attribution, CSP/CORS, privacy, defaults; เก็บ screenshot/behavior baseline ของ Google; เลือก production source จากหลายตัวเลือก (ไม่ hardcode OSM Standard) |
| 1. Settings model + persistence | P0 / ง่าย | ✅ เสร็จ 2026-10-06 — commits `0226c9f`, `13fc938` ([รายงาน](../evidence/map_provider_phase1/phase1_report.md)) | config resolver, platform defaults, feature overrides, validation, revision, backend admin path; UI เลือก Google/OSM + source; unit/API/widget tests พิสูจน์ save/reload, permission, fallback config ก่อนเปลี่ยน renderer |
| 2. Shared adapter + fake tile harness | P0 / ปานกลาง | ✅ เสร็จ 2026-10-06 — commit `0d952b7` ([รายงาน](../evidence/map_provider_phase2/phase2_report.md)) | map model/controller facade + Google/OSM adapter; automated tests ใช้ fake/local tiles; Google behavior เดิมผ่าน regression |
| 3. Group Create Map | P1 / ง่ายสุดในกลุ่มแผนที่จริง | 🟡 implement + widget tests ผ่านแล้ว ([รายงาน](../evidence/map_provider_phase3/phase3_report.md)) — รอ device smoke ทั้งสอง renderer | tap/drag pin, use location, fullscreen, restore พิกัด, สร้างก๊วนได้ `lat/lng` เดิม; Nominatim/Places flow ไม่เปลี่ยน |
| 4. Home Map | P1 / ง่าย–ปานกลาง | ⬜ ยังไม่เริ่ม | initial camera, user location, nearest emergency, event markers, re-center, route polyline; permission denied + network interruption |
| 5. Yield Way Dialog | P1 / ปานกลาง | ⬜ ยังไม่เริ่ม | inherit จาก Emergency; alert fixtures, fit bounds, route line, marker, ปุ่มให้ทาง/ไม่สะดวก, callback |
| 6. Rescue Map | P1 / ยาก | ⬜ ยังไม่เริ่ม | แยก renderer จาก Directions; native Directions/polyline ไม่เปลี่ยน; Web route ตามสถานะจริงจนมี routing backend; loading/error + zero-area bounds |
| 7. Emergency Live Map | P0 safety / ยากสุด | ⬜ ยังไม่เริ่ม (ส่วนย่อย §22 incident map ทำแล้ว — ดู §10.3) | markers, responder routes, profession colors, live location, camera fit, overlays; ผ่าน Mission Lock, websocket, response state, controller lifecycle; OSM แสดงว่าไม่มี traffic; ห้าม production rollout ก่อน safety gate |
| 8. Map systems อนาคต | P2 / ง่ายต่อระบบ | ⬜ ยังไม่เริ่ม | register feature key + ใช้ selector/config เดียวกันเมื่อมี map จริง; ไม่ reintroduce Sport Club Map View เพียงเพราะมี OSM |

### 10.3 สถานะจริงหลัง Phase 0–2 และงานที่ค้าง (อัปเดต 2026-10-07)

**VCS state:** งาน Phase 0–2 + เอกสารนี้ commit ครบแล้ว —
`0226c9f` (Phase 0/1: migration, map-config route, model, service,
settings UI, evidence, smoke harness, maestro baseline), `13fc938`
(Phase 1 report), `0d952b7` (Phase 2: `lib/shared/map/`, tests, report,
harness → shared adapter) และ `6f2d524` (VIDEO_SYSTEM_PLAN §22 notes +
incident map glue) — commit เหล่านี้รวมงานขนานอื่นไว้ด้วย ไม่ใช่ commit
เฉพาะ phase; working tree เหลือเฉพาะ `pubspec.lock` drift จาก pub
resolution (ไม่เกี่ยวกับงานนี้)

**งานขนานที่ลงจอดก่อนกำหนด — Incident Overview Map (VIDEO_SYSTEM_PLAN §22):**
`widgets/incident_map/incident_map_surface.dart` เป็นพื้นผิวสอง renderer
(Google canvas-bitmap markers / flutter_map widget markers) ที่ gate ด้วย
`resolveTarget(MapFeature.emergency)` + feature gate
`features.incidentOverviewMap.enabled` — พิสูจน์แล้วว่า contract ของ Phase 1
ขับ renderer จริงได้ แต่ surface นี้ **ไม่ได้ใช้ shared adapter ของ Phase 2**
เพราะต้องการสิ่งที่ shared model ยังไม่มี: cluster markers ขนาดตาม count,
canvas-generated bitmaps, photo-card overlay ที่วางตำแหน่งด้วย manual
projection — งานค้าง: ตัดสินใจว่าจะย้ายมาใช้ shared layer (ขยาย model ให้รองรับ
cluster/overlay) หรือบันทึกเป็น documented carve-out

**งานค้างจาก Phase 0–2:**

- Production tile source ยังไม่ตัดสิน — OSM Standard อนุมัติเฉพาะ
  dev/staging/smoke; CARTO keyless endpoint ตายแล้ว (HTTP 200 + "API KEY
  REQUIRED" watermark) ต้องสมัคร key/ยืนยัน commercial terms หรือเลือก
  managed provider/self-host (§15 ข้อ 1 ยังเปิด)
- **Web CSP ยังไม่แก้ใน source** — หลักฐาน Phase 0/2 patch เฉพาะ generated
  build; `web/index.html` (หรือต้นทาง `flutter_bootstrap.js`) ต้องเพิ่ม tile
  hosts ลง `connect-src` และตั้ง `useLocalCanvasKit` ถาวรก่อนเชื่อม OSM บน
  web จริง ไม่เช่นนั้น CanvasKit boot ล้มตั้งแต่ก่อนแผนที่
- OSM adapter: `animateTo` เป็น instant move (ไม่มี animated camera), persistent
  `padding` ไม่ propagate นอก `fitToBounds`, ไม่มี tilt — ต้องตัดสินใจว่าพอหรือ
  เพิ่ม `flutter_map_animations` ก่อน Phase 6–7 (Rescue/Emergency)
- Google adapter ยังไม่เคย render จริงบนอุปกรณ์ (smoke เฉพาะ OSM) — Phase 3
  migrate `create_group_page` มาใช้ shared adapter แล้ว ([รายงาน](../evidence/map_provider_phase3/phase3_report.md))
  แต่ยังต้อง smoke ทั้งสอง renderer บนอุปกรณ์หลัง config flag ก่อนถือว่า phase ปิดสนิท
- Semantics/keyboard-traversal test ของ settings UI ยัง partial → Phase 8
- ยืนยัน deploy path ของ `database/migrations/04_create_map_provider_config.sql`
  เมื่อจะเปิด staging/prod
- Incident map (§22) ค้างตามแผนของมันเอง: device verification ทั้งสอง
  renderer, load test, canary metric `map_load_emergency_overview`, cluster
  tap zoom-in animation

### เงื่อนไข rollout ทั่วไป

- Google adapter และ OSM adapter อยู่ร่วมกันได้
- เปิดทีละแพลตฟอร์ม/ทีละ feature
- เปลี่ยนค่าผ่าน remote config ได้โดยไม่ต้องออกแอปใหม่
- Active Emergency/Rescue คง provider ที่เริ่มไว้จนจบ flow
- ตรวจ network/CSP/cache/attribution/quota ใน staging ก่อน production
- automated tests ใช้ fake/local tiles; ห้ามยิง tile server สาธารณะซ้ำใน CI
- ทุก phase ต้องผ่าน **Phase Completion Review** ใน §10.1 และแนบหลักฐานก่อนทำเครื่องหมายเสร็จ

### 10.1 Phase Completion Review — บังคับทุก phase

ทุก phase (รวม Phase 0 และระบบอนาคตใน Phase 8) ต้องมีบันทึกก่อน/หลังใน PR หรือ release record โดยระบุ `phase`, feature, platform, renderer, tile source, app/config revision, environment, อุปกรณ์/viewport, network และ permission state ที่ใช้ทดสอบ

**ก่อน implement (baseline):**

- เก็บภาพหน้าจอ/วิดีโอของ flow ปัจจุบันในระบบย่อยที่กระทบ; ใช้ข้อมูล fixture ที่ทำซ้ำได้
- บันทึกผล test เดิม, error/exception, map-ready time, camera/marker behavior และค่าใช้จ่าย/จำนวน request ที่วัดได้
- กำหนด acceptance threshold ของ phase จาก baseline และ SLO ของระบบก่อนเริ่ม rollout; ห้ามเลือก threshold หลังเห็นผลเพื่อทำให้ผลผ่าน

**หลัง implement (impact assessment):** เปรียบเทียบภายใต้เงื่อนไขเดียวกับ baseline และสรุปอย่างน้อย 8 ด้าน:

1. UI/layout/interaction — ตำแหน่งแผนที่, overlay, hit target, loading/error/empty state
2. Functional/data — พิกัด, marker, route, camera, form submit และ side effects ที่เกี่ยวข้อง
3. Platform parity — ความต่าง Web/iOS/Android และความสามารถที่ provider ไม่มี
4. Accessibility — semantics, keyboard, text scale, contrast และ touch target
5. Performance/stability — first usable map, frame jank, memory, crash, controller lifecycle
6. Network/cost — tile requests/egress, Google billable events, routing/search events แยกกัน
7. Security/privacy/compliance — role, CSP/CORS, attribution, tile terms, location exposure
8. Integration/operations — websocket, mission/booking workflows, metrics, logging และ rollback

ให้ระบุแต่ละด้านเป็น `ผ่าน`, `ไม่ผ่าน`, `ไม่เกี่ยวข้อง` พร้อมหลักฐาน/เหตุผลและ action owner; `ไม่เกี่ยวข้อง` ต้องมีเหตุผล ไม่ใช้แทนการทดสอบที่ยังไม่ได้ทำ

**Go / No-Go:**

- **No-Go ทันที:** P0/P1 defect, พิกัดหรือ route ผิด, mission/booking state ผิด, unauthorized config write, attribution/security failure, crash, หรือมีค่าใช้จ่ายจาก provider ที่ไม่ได้อนุมัติ
- **No-Go ตาม threshold:** metric หลังเปลี่ยนเกิน acceptance threshold ที่กำหนดใน baseline (เช่น map-ready time, tile failure, memory, cost) หรือยังวัด impact สำคัญไม่ได้
- P2/P3 ที่ยอมรับชั่วคราวต้องมีเหตุผล, owner, due date, workaround และห้ามกระทบความปลอดภัย/accessibility; P2 ที่ทำให้ UI ใช้ไม่ได้ถือเป็น No-Go
- ผ่านเฉพาะเมื่อ test ที่ระบุรันครบ, impact review มีหลักฐาน, ไม่มี P0/P1 ค้าง และ rollback path ใช้ได้จริง

### 10.2 ผลกระทบและ UI verification เฉพาะแต่ละ phase

#### Phase 0 — Baseline + เลือก tile-source profile

- **Impact review:** เป็น decision/baseline phase จึงยังไม่มี code impact; หลังจบต้องมี provider decision record ที่ครอบคลุมราคา/ToS/coverage/privacy/CORS/CSP และระบุ SLO/threshold สำหรับ phase ถัดไป
- **UI verification:** บันทึก Google baseline ของ Home, Group Create, Rescue, Yield Way และ Emergency บน platform ที่รองรับ; ทำ low-volume smoke กับ candidate OSM source บน Chrome/Caddy และอย่างน้อยหนึ่ง iOS/Android device โดยเก็บ attribution, console/network errors และ provider response
- **Defect handling:** source ที่ไม่ผ่าน CORS, attribution, cache policy, key restriction หรือ privacy review ให้ตัดออกจาก registry; ห้าม workaround ด้วย wildcard CSP หรือเปลี่ยนไปใช้ OSM public endpoint เป็น production โดยอัตโนมัติ
- **Exit evidence:** baseline screenshots/video, timing/error snapshot, candidate comparison และ threshold ที่อนุมัติก่อนเริ่ม implement

#### Phase 1 — Settings model + persistence

- **Impact review:** ตรวจ config resolution, admin permission, revision conflict, saved-vs-draft, default เมื่อ config โหลดไม่ได้ และผลต่อ map instance ที่กำลังเปิด; ยังไม่ควรเปลี่ยน renderer ของ production map ใน phase นี้
- **UI verification:** widget tests ของ loading/error/empty/dirty/saving/saved/conflict/rollback states; test Web compact 320×568 หรือขนาดเล็กสุดที่แอปรองรับ, 393×852, Web 1280×800 และ text scale 1.3; ทดสอบ keyboard navigation, semantics, save/cancel, unsaved guard และ role rejection ด้วย API/integration test
- **Defect handling:** stale draft, config overwrite, tile source ที่ไม่พร้อมแต่กด save ได้ หรือ unauthorized write เป็น P0/P1; เพิ่ม regression test ให้ fail ก่อนแก้; ถ้า config server ใช้ไม่ได้ต้องเห็น safe default พร้อมข้อความ ไม่แสดง success ปลอม
- **Exit evidence:** config หลัง reload เท่ากับค่าที่ save, conflict ไม่เขียนทับ, non-admin เขียนไม่ได้, ไม่มี renderer behavior เปลี่ยนโดยไม่ตั้งใจ

#### Phase 2 — Shared adapter + fake tile harness

- **Impact review:** ตรวจ camera semantics, padding, marker/polyline conversion, overlay ordering, gesture handling, platform view behavior, memory และ render timing เทียบ Google baseline
- **UI verification:** unit tests สำหรับ coordinate/bounds conversion; widget tests ด้วย FakeMapController/FakeTileProvider; golden tests ใช้ tile fixture และ marker fixture คงที่ (ห้ามใช้ภาพจาก live tile server); Google adapter regression บนทุก platform ที่มี Google renderer และ OSM adapter smoke บน Web/iOS/Android
- **Defect handling:** controller lifecycle/zero-area bounds/map tap/overlay hit-testing ผิด ให้ทำ test ซ้ำได้ก่อนแก้; ห้ามแก้ golden ด้วยการอัปเดตรูปทับโดยไม่อธิบายสาเหตุและตรวจ layout จริง
- **Exit evidence:** widget tree/semantics ไม่ overflow, camera command ให้ผลเทียบ contract, renderer ปล่อย/dispose controller ถูกต้อง

#### Phase 3 — Group Create Map

- **Impact review:** ตรวจความถูกต้อง `lat/lng` ระหว่าง tap/drag/location/search/fullscreen/restore และการ persist ไป group; ยืนยัน Nominatim/Google Places ไม่เปลี่ยน provider เพียงเพราะเปลี่ยน basemap
- **UI verification:** widget/golden tests สำหรับ map card และ fullscreen picker; integration/UI flow เลือกจุด → กลับฟอร์ม → save group → reload แล้วพิกัดเดิม; ทดสอบ pin ไม่มีพิกัดเริ่มต้น, location denied, loading/error tiles และจอแคบ; browser + iOS/Android สำหรับ provider ที่เปิดใช้
- **Defect handling:** พิกัดคลาด, marker ไม่ตรงตำแหน่งแตะ, fullscreen คืนค่าหาย หรือ save พิกัดคนละจุดเป็น P1; เพิ่ม regression test ที่ assert latitude/longitude (ใช้ fixtures ไม่ใช้ GPS จริง)
- **Rollback:** override `group_create` กลับ Google โดยคงข้อมูลพิกัดใน DB เดิม ไม่ลบ/เขียนทับพิกัดผู้ใช้

#### Phase 4 — Home Map

- **Impact review:** ตรวจ user location, permission denied, nearest emergency selection, camera auto-focus/re-center, event polling, overlay/header layout, battery/network และ location privacy
- **UI verification:** fake repository/location stream สำหรับ deterministic widget tests; golden screenshots ของ loading/normal/event-focused/permission-denied/error states; integration smoke บน iOS/Android + Web ที่เปิดใช้ โดยทดสอบ resume/app lifecycle และ event เข้ามาระหว่างเปิดหน้า
- **Defect handling:** auto-focus ผิด event, location marker ไม่ sync, camera move หลัง dispose หรือ overlay บัง control เป็น P1; ใช้ fake clock/stream และ regression test แทนการพึ่ง timing จาก production backend
- **Rollback:** สลับ `home` override กลับ Google; location/event data flow ต้องคงเดิม

#### Phase 5 — Yield Way Dialog

- **Impact review:** ตรวจการแสดง route/incident/user markers, fit bounds, dialog size, CTA visibility/tap และยืนยันว่า map renderer ไม่มี side effect ต่อการกดช่วย/ปฏิเสธ
- **UI verification:** widget + golden tests สำหรับ 0/1/2 markers, route ยาว/สั้น, error/loading, จอเล็กและ text scale; integration test ยืนยันปุ่มช่วยทาง/ไม่สะดวกเรียก callback เดิมและ dialog ปิดตาม contract
- **Defect handling:** เส้นทางหรือจุดเกิดเหตุผิด, CTA ถูกบัง/กดไม่ได้, dialog ล้น หรือเปิด map แล้วส่ง interaction เองเป็น P0/P1; regression tests ต้องยืนยันว่าเปิด/ปิด dialog ไม่สร้าง response ซ้ำ
- **Rollback:** provider ของ Yield Way ต้องคืนตาม `emergency`; ห้ามปล่อย dialog แยก provider ชั่วคราว

#### Phase 6 — Rescue Map

- **Impact review:** แยกผลของ renderer จาก Google Directions; ตรวจ route polyline, distance/duration, API calls/cost, Web CORS behavior และกรณี route unavailable โดยไม่อ้างว่าการใช้ OSM แก้ routing
- **UI verification:** fake Directions response สำหรับ success/empty/timeout/HTTP error; widget/golden tests ของ map, route, loading/error และข้อความ Web fallback; integration smoke บน mobile และ Chrome/Caddy เมื่อ route provider รองรับ
- **Defect handling:** route endpoint error ต้องไม่ทำให้ marker/หน้ากู้ภัยพัง; response ซ้ำ/ค่าเก่า/route สลับจุดให้เพิ่ม regression test; ห้ามเปิด Directions บน Web ผ่าน direct REST หากยังติด CORS
- **Rollback:** คืน map renderer เป็น Google โดยคง service routing provider เดิมและไม่เรียก API เพิ่มจาก fallback

#### Phase 7 — Emergency Live Map

- **Impact review:** safety review ครอบ responder tracking, websocket update, mission lock, response state, route/marker consistency, camera lifecycle, traffic messaging, data/cost และ privacy; ต้องตรวจการทำงานของ flow ฉุกเฉินครบตั้งแต่เปิดเหตุจนออกจากภารกิจ
- **UI verification:** ใช้ staging + synthetic incidents/responders เท่านั้น (ห้ามยิงเหตุฉุกเฉินจริง); integration tests สำหรับ websocket/location/mission transitions; widget/golden tests ของ marker/route/traffic-unavailable/empty/error overlays; Maestro/manual device smoke บน platform-provider combinations ที่จะ rollout; Google regression ต้องผ่านก่อน OSM canary
- **Defect handling:** พิกัด/route ผิด, responder หาย, mission lock หลุด, ปุ่มช่วยทางผิด flow, map interaction ขวาง emergency controls หรือ traffic absence ทำให้เข้าใจผิดเป็น P0 — halt/rollback ทันที; ทุก P0/P1 ต้องมี regression test และผ่าน incident-flow retest ครบก่อนเปิดใหม่
- **Post-rollout:** canary ทีละ platform/feature; เฝ้า map/tile error, websocket update delay, map-ready time, crash, traffic disclaimer, provider usage/cost; หยุด rollout เมื่อเกิน threshold จาก Phase 0
- **Rollback:** เปลี่ยน config กลับ provider ที่ผ่าน gate โดยไม่ dispose map กลางภารกิจ; active mission คง provider snapshot จนจบ

#### Phase 8 — Map systems อนาคต

- **Impact review:** ก่อนเพิ่ม map ให้ระบุ data owner, location sensitivity, service dependencies, provider capabilities และสิ่งที่ feature เดิมจะได้รับผล
- **UI verification:** ใช้ checklist §11 และ test template ของ phase นี้; ต้องกำหนด platform/provider matrix, fixture states, viewport/accessibility, network failure และ feature-specific integration ก่อนเริ่ม implement
- **Defect handling:** ห้ามใช้ข้อความ "ใช้ shared map" แทนการทดสอบ flow/domain ของ Sport Club, Book Court, Coach หรือ Delivery; bug ของ feature ต้องมี owner และ regression test ใน module เดียวกัน
- **Exit evidence:** map feature ใหม่ผ่าน Phase Completion Review แยกของตนเอง; ไม่ inherit ว่า phase เก่าผ่านแล้วจึงผ่านอัตโนมัติ

---

## 11. Test matrix และวิธีแก้ defect

ทุก phase ต้องเลือก test ใน matrix ด้านล่างตามขอบเขตที่เปลี่ยน และอ้างหลักฐานกลับไปยัง Phase Completion Review (§10.1–10.2)

### 11.1 ระดับการทดสอบ UI ที่ต้องใช้

1. **Unit:** config resolution, provider capability, coordinate conversion, bounds, metrics parsing; ไม่เปิด network
2. **Widget:** Flutter `WidgetTester` + fake map renderer/controller/tile provider; ตรวจ interaction, semantics, loading/error/empty/permission/disabled states
3. **Golden/visual regression:** ใช้ tile/marker fixtures คงที่และ font ที่โหลดแน่นอน; เปรียบเทียบ layout, overlay, attribution, dialog, clipping; ห้ามอัปเดต golden เพื่อกลบ bug โดยไม่ตรวจ screenshot จริง
4. **Integration:** repository/backend/config + map widget; ทดสอบ save/reload, route/search, location state และ side effects ด้วย staging/fixtures
5. **Browser/device smoke:** Web ผ่าน Caddy dev/staging + Chrome DevTools; iOS/Android อย่างน้อย simulator และ physical device ก่อน release ที่แตะ native/real location
6. **Acceptance automation:** ใช้ Maestro สำหรับ user journeys ที่รองรับ และ manual QA สำหรับ map gestures, native platform view, provider branding/attribution ที่ automation ตรวจได้ไม่ครบ

### 11.2 Coverage matrix โดยไม่สร้าง Cartesian test เกินจำเป็น

- ทุก feature ที่แก้ต้องทดสอบ renderer ที่เลือกใหม่และ regression ของ renderer เดิมบน platform ที่ feature ใช้งานจริง
- OSM renderer ต้องมี smoke test อย่างน้อย Web, iOS, Android ใน Phase 2; เมื่อ feature ใดเปิด OSM บน platform เพิ่ม ต้องทดสอบ feature-platform นั้นเพิ่ม
- Google regression ต้องรันบน platform ที่ยังเปิด Google; Google Web ทดสอบเฉพาะกรณี key/budget/config เปิดไว้ ถ้าไม่เปิดให้ assert ว่าไม่มี Google Maps JS request
- Emergency Phase 7 ต้องครอบทุก combination ที่จะ rollout จริง (feature × platform × provider) พร้อม test synthetic mission; ใช้ pairwise ได้เฉพาะ control ที่ไม่เกี่ยวกับ safety และต้องระบุเหตุผล
- Real tile provider smoke ทำเฉพาะ staging/QA ที่ควบคุม request; CI ใช้ fake/local tiles เท่านั้น
- Viewport ขั้นต่ำ: compact phone 320×568 หรือ viewport ต่ำสุดที่รองรับ, phone 393×852, Web 1280×800; ทดสอบ text scale 1.0 และ 1.3, safe area, keyboard และ orientation ที่แอปรองรับ

### 11.3 Defect reproduction และ root-cause fix loop

ใช้ขั้นตอนเดียวกันทุก phase:

1. **Reproduce:** ระบุ build/config revision, platform, feature, provider/source, viewport/device, network, permission, account role และขั้นตอนซ้ำที่แน่นอน
2. **Capture evidence:** screenshot/recording, Flutter log, browser console/network หรือ device log; redact token, key, user ID และพิกัดจริงก่อนแนบ
3. **Classify:** แยก config/resolver, renderer/controller, tile/CSP/CORS, data/location, UI/layout/accessibility, service (routing/search/traffic), security/mission; ระบุ P0–P3 และ owner
4. **Write a failing regression test:** P0/P1/P2 ต้องมี test ที่ reproduce defect ก่อนแก้; สำหรับ visual issue ใช้ fixture + golden หรือ widget assertion ที่เจาะจง
5. **Fix root cause:** ห้ามแก้เฉพาะ screenshot/ซ่อน error/ลด test coverage; ห้าม fallback ไป provider อื่นเพื่อกลบ error โดยไม่ผ่าน config/policy
6. **Rerun affected tests:** targeted failing test → unit/widget → integration/acceptance ของ feature → platform/provider regression → UI smoke บน device/browser ที่กระทบ
7. **Reassess impact:** เทียบ evidence กับ baseline และ threshold; บันทึก defect ที่แก้, residual risk, rollback decision และผล post-implementation ใน PR/release record

**Severity / release policy:**

- **P0:** safety, security, privacy, พิกัด/route ผิด, mission/booking side effect ผิด หรือ crash ใน critical flow — หยุด rollout และ rollback
- **P1:** core map ใช้ไม่ได้, save พิกัดผิด, responder/marker/route สำคัญหาย, config unauthorized หรือ UI ทำให้ดำเนิน flow หลักไม่ได้ — ห้ามขยาย canary
- **P2:** visual/accessibility/performance regression ที่เกิน threshold — แก้ก่อน rollout; ยอมรับชั่วคราวได้เฉพาะมี workaround/owner/due date และไม่ลด accessibility/safety
- **P3:** copy/visual detail ที่ไม่กระทบการใช้งาน — บันทึก issue และกำหนดรอบแก้

### 11.4 Post-implementation Go/No-Go checklist

ก่อน phase complete ผู้รับผิดชอบตอบ `ผ่าน/ไม่ผ่าน/ไม่เกี่ยวข้อง + หลักฐาน` ทุกข้อ:

- [ ] Functional flow และ data invariant เทียบ baseline ผ่าน
- [ ] UI golden/interaction, semantics, touch/keyboard และ text scale ผ่านตาม scope
- [ ] Google/OSM provider behavior และ attribution ถูกต้อง
- [ ] CSP/CORS/network/cache และ external service error behavior ผ่าน
- [ ] map-ready/error/crash/memory และ cost metrics อยู่ใน threshold ที่ล็อกไว้ก่อนเริ่ม phase
- [ ] security/privacy/role และ location handling ไม่มี regression
- [ ] ไม่มี P0/P1 ค้าง; P2/P3 มี owner/due date และได้รับอนุมัติ
- [ ] rollback/config override ผ่านการทดสอบ
- [ ] หลักฐานก่อน/หลังและผลกระทบแนบใน PR/release record

---

## 12. แผนปรับเอกสารเดิม

ให้เอกสารนี้เป็น provider contract กลาง แล้วแก้เอกสารเดิมตาม phase โดยไม่ลบประวัติการตัดสินใจ

| เอกสาร | สิ่งที่ต้องทำให้สอดคล้อง |
|---|---|
| `docs/plans/Match_Sport_PLAN.md` | แก้มติ Phase 14.3 จาก Web-off/mobile-Google-only เป็น provider-per-platform/per-feature; แก้ข้อความเก่าว่าอนาคตค่อยเพิ่ม `flutter_map`; re-baseline Dev OSM/MapAdapter และ Phase 1 ที่ระบุ OSM MapCard แต่ implementation เป็น Google; คงข้อ Phase 14.5 ที่ลบ Map View และไม่เพิ่ม selector สำหรับหน้าที่ยังไม่มีแผนที่ |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | แก้ cost prevention ให้แยก renderer/tile source/routing/search/traffic; ปรับ Map Badge จาก Google-only bitmap เป็น renderer-specific; ระบุว่า Directions/CORS ไม่หายเมื่อใช้ OSM; ปรับ Google-specific camera rules เป็น contract กลาง; คง Mission Lock + Emergency invariants |
| `docs/plans/Delivery_PLAN.md` | คงกฎไม่เรียก Google Maps API จาก backend โดยไม่อนุมัติงบ; เปิดทาง Delivery Web Dashboard ใช้ shared OSM renderer เมื่อมี map จริง; OSRM/Valhalla เป็น routing decision แยกจาก tiles |
| `docs/plans/ui_rendering_standards.md`, `docs/guides/ui_rendering_standards.md` | ติดป้ายว่า Platform View workarounds (compositing/clip/offset) ใช้กับ Google renderer เท่านั้น; OSM widget ไม่ต้องใช้ workaround นั้น |
| `docs/guides/flutter_web_enablement_plan.md` | อัปเดต C1 ให้ไม่จำกัดแผนที่ Web เป็น fallback image เมื่อ OSM ผ่าน gate; คง Google JS ปิดเป็น default; เพิ่ม CSP/CORS/referrer/attribution/route test gates |
| `docs/secure/google_maps_key_restriction_guide.md` | ระบุขอบเขต Google key ที่ยังต้องใช้หลังมี OSM; แยก web key/budget จาก iOS/Android; ตรวจ wiring จริงก่อนเผยแพร่ |
| `docs/plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md` | คง Kotlin compatibility note ตราบเท่าที่ Google Maps Android plugin ยังเลือกใช้งานได้ |
| `docs/guides/TEST_PLAN.md` | เพิ่ม ADM-09 scenario สำหรับ provider selection/save/restore, provider ที่ยังไม่ configure, tile preview, Web CSP/CORS |

หมายเหตุ: Phase 20 (Trending Panel filter) ใน `VIDEO_SYSTEM_PLAN.md` ไม่ต้องเปลี่ยน behavior แต่คง regression gate ว่าการสลับ provider ไม่กระทบ map/mission state

---

## 13. Rollback และเกณฑ์ประกาศใช้งาน

### 13.1 Rollback

- ตั้ง feature/platform override กลับเป็น Google ได้จาก Platform Settings
- ถ้า Web OSM ล่ม ให้ปิดแผนที่เฉพาะ feature หรือแสดง map-unavailable fallback — **อย่ากลับไป Google JS อัตโนมัติ** หากยังไม่อนุมัติ key/งบ
- ถ้า OSM source หนึ่งมีปัญหา สลับไป managed/self-hosted ที่อนุมัติแล้วเท่านั้น
- เก็บ Google adapter + config เก่าจนผ่าน production soak; ไม่ถอน Google dependency ใน rollout นี้

### 13.2 Acceptance criteria รวม

- ผู้ดูแลสลับ Google/OSM ได้แยก Web/iOS/Android และ override รายระบบย่อยได้
- เพิ่ม OSM tile source ใน allowlist ได้โดยไม่ต้องเขียน renderer ใหม่ และไม่บังคับ source เดียว
- ไม่มี secret หรือ arbitrary URL ใน client configuration
- attribution, cache, Referer, CSP/CORS, tile terms ผ่าน gate ก่อน production
- routing, search, traffic, map renderer มี config/metrics แยกกัน
- ไม่ประเมินค่าใช้จ่ายจาก map session count ด้วยราคาเดียวทุก provider
- Home, Group Create, Rescue, Yield Way, Emergency ผ่าน test gate ของตนเองก่อนเปิดใช้
- ทุก phase มีผล impact assessment ก่อน/หลังพร้อมหลักฐาน, ผ่าน UI verification ตาม scope และไม่มี P0/P1 defect ค้าง
- ค่า performance, error rate, provider usage/cost และ rollback threshold ถูกกำหนดก่อน rollout และตรวจผ่านตาม Phase Completion Review (§10.1)

---

## 14. แหล่งอ้างอิง

- [OpenStreetMap Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/)
- [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/)
- [flutter_map: Tile Layer](https://docs.fleaflet.dev/layers/tile-layer)
- [flutter_map: Attribution Layer](https://docs.fleaflet.dev/layers/attribution-layer)
- [flutter_map: Web installation / CORS notes](https://docs.fleaflet.dev/getting-started/installation)

---

## 15. จุดตัดสินใจที่ต้องยืนยันก่อน implement

1. **Tile source สำหรับ production:** เลือก managed provider รายใด หรือ self-host (ต้องประเมินราคา/quota/คุณภาพแผนที่ไทย/privacy) — **ค้างอยู่** (Phase 0 ตัด CARTO keyless + OpenTopoMap ออกจาก production candidates แล้ว; OSM Standard อนุมัติเฉพาะ dev/staging)
2. **Web default:** เปิด OSM ให้ทุกหน้าหรือเปิดเฉพาะบาง feature ในช่วงแรก — **ค้างอยู่** (ตอนนี้ config default ปิด OSM บน web ไว้ก่อน)
3. **Emergency/Rescue:** ยอมรับการไม่มี traffic layer บน OSM หรือคง Google จนกว่าจะมี traffic provider — **ค้างอยู่** (ตอนนี้ `MapCapabilities` รายงาน `trafficLayer:false` พร้อมให้ UI ซ่อน toggle)
4. **Routing บน Web:** จะทำ backend proxy/OSRM หรือคงปิด route drawing บน Web — **ค้างอยู่**
5. **Storage ของ config:** ตารางใหม่ + backend endpoint หรือใช้ `app_settings` เดิมที่แก้ policy — **ตัดสินใจแล้ว:** ตาราง `map_provider_config` + endpoints เฉพาะ (Phase 1) ไม่เขียน `app_settings`
6. **Permission:** ใช้ role `admin` ต่อก่อน แล้วค่อยแยก `platform.map.manage` — **ตัดสินใจแล้วชั่วคราว:** `requireRole('admin')` (Phase 1); แยก scope เป็นงานอนาคต
