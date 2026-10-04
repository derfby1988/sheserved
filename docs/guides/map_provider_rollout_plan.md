# แผนรองรับ Google Maps และ OSM-based Tiles สำหรับ Sheserved

> **วันที่สร้าง:** 2026-10-04
> **สถานะ:** ข้อเสนอ implementation plan — ยังไม่ได้ implement
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

### 2.2 Provider settings ยังไม่ครบวงจร

`PlatformService` เก็บ master switch และค่ารายหน้าของ Web ในหน่วยความจำ และ `shouldShowLiveMap()` ตัดสินใจจากค่านั้น ยังไม่มี provider selection, tile source หรือ persistence (`lib/services/platform_service.dart:18-67`)

หน้า Platform Settings มี Web on/off และรายหน้า แต่ iOS/Android toggles เปลี่ยนเฉพาะ widget state และ Save แสดง success SnackBar โดยไม่บันทึก (`lib/features/admin/presentation/pages/platform_settings_page.dart:71-183,566-585`)

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

| Phase | Priority / ความยากทดสอบ | ขอบเขตและ exit gate |
|---|---|---|
| 0. Baseline + เลือก tile-source profile | P0 / ง่ายมาก | ยืนยันตัวเลือก provider, key restrictions, attribution, CSP/CORS, privacy, defaults; เก็บ screenshot/behavior baseline ของ Google; เลือก production source จากหลายตัวเลือก (ไม่ hardcode OSM Standard) |
| 1. Settings model + persistence | P0 / ง่าย | config resolver, platform defaults, feature overrides, validation, revision, backend admin path; UI เลือก Google/OSM + source; unit/API/widget tests พิสูจน์ save/reload, permission, fallback config ก่อนเปลี่ยน renderer |
| 2. Shared adapter + fake tile harness | P0 / ปานกลาง | map model/controller facade + Google/OSM adapter; automated tests ใช้ fake/local tiles; Google behavior เดิมผ่าน regression |
| 3. Group Create Map | P1 / ง่ายสุดในกลุ่มแผนที่จริง | tap/drag pin, use location, fullscreen, restore พิกัด, สร้างก๊วนได้ `lat/lng` เดิม; Nominatim/Places flow ไม่เปลี่ยน |
| 4. Home Map | P1 / ง่าย–ปานกลาง | initial camera, user location, nearest emergency, event markers, re-center, route polyline; permission denied + network interruption |
| 5. Yield Way Dialog | P1 / ปานกลาง | inherit จาก Emergency; alert fixtures, fit bounds, route line, marker, ปุ่มให้ทาง/ไม่สะดวก, callback |
| 6. Rescue Map | P1 / ยาก | แยก renderer จาก Directions; native Directions/polyline ไม่เปลี่ยน; Web route ตามสถานะจริงจนมี routing backend; loading/error + zero-area bounds |
| 7. Emergency Live Map | P0 safety / ยากสุด | markers, responder routes, profession colors, live location, camera fit, overlays; ผ่าน Mission Lock, websocket, response state, controller lifecycle; OSM แสดงว่าไม่มี traffic; ห้าม production rollout ก่อน safety gate |
| 8. Map systems อนาคต | P2 / ง่ายต่อระบบ | register feature key + ใช้ selector/config เดียวกันเมื่อมี map จริง; ไม่ reintroduce Sport Club Map View เพียงเพราะมี OSM |

### เงื่อนไข rollout ทั่วไป

- Google adapter และ OSM adapter อยู่ร่วมกันได้
- เปิดทีละแพลตฟอร์ม/ทีละ feature
- เปลี่ยนค่าผ่าน remote config ได้โดยไม่ต้องออกแอปใหม่
- Active Emergency/Rescue คง provider ที่เริ่มไว้จนจบ flow
- ตรวจ network/CSP/cache/attribution/quota ใน staging ก่อน production
- automated tests ใช้ fake/local tiles; ห้ามยิง tile server สาธารณะซ้ำใน CI

---

## 11. Test matrix

### Settings / config
- resolver เลือก `feature override → platform default → environment default` ถูกต้อง
- provider/source ที่ไม่ configure ถูก disable + validation; ไม่ fallback เงียบ
- save แล้วเปิดแอปใหม่/โหลดใหม่ได้ค่าที่บันทึก
- ผู้ไม่มีสิทธิ์อ่านได้เฉพาะ config ปลอดภัย เขียนไม่ได้
- concurrent update/revision conflict ไม่เขียนทับ
- unsaved changes guard ทำงาน; conflict banner แสดง

### Shared adapters
- markers, polylines, tap, padding, camera move, fit bounds ตาม contract
- zero-area bounds, พิกัดเดียว, controller disposed, load failure ไม่ crash
- attribution ไม่ถูก overlay สำคัญบัง
- automated test ไม่พึ่ง live tile endpoint

### ระบบย่อย
- **Group Create:** tap/drag pin, location denied, fullscreen, search result, submit พิกัด
- **Home:** permission, event marker, nearest event, auto focus, reset camera
- **Yield Way:** 1/2 markers, route line, bounds, yield/decline callback
- **Rescue:** route line, Directions error, Web CORS, distance/duration fallback
- **Emergency:** responder marker/color, decoded + fallback polylines, live update, traffic-unavailable indicator, mission lock, เปลี่ยนเหตุการณ์
- **Web:** Chrome ผ่าน Caddy, ตรวจ CSP/CORS ใน devtools, ไม่โหลด Google JS โดยไม่เลือก/อนุมัติ
- **iOS/Android:** Google และ OSM แยกกันบน simulator/device; memory, overlays, app resume, permission states

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

---

## 14. แหล่งอ้างอิง

- [OpenStreetMap Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/)
- [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/)
- [flutter_map: Tile Layer](https://docs.fleaflet.dev/layers/tile-layer)
- [flutter_map: Attribution Layer](https://docs.fleaflet.dev/layers/attribution-layer)
- [flutter_map: Web installation / CORS notes](https://docs.fleaflet.dev/getting-started/installation)

---

## 15. จุดตัดสินใจที่ต้องยืนยันก่อน implement

1. **Tile source สำหรับ production:** เลือก managed provider รายใด หรือ self-host (ต้องประเมินราคา/quota/คุณภาพแผนที่ไทย/privacy)
2. **Web default:** เปิด OSM ให้ทุกหน้าหรือเปิดเฉพาะบาง feature ในช่วงแรก
3. **Emergency/Rescue:** ยอมรับการไม่มี traffic layer บน OSM หรือคง Google จนกว่าจะมี traffic provider
4. **Routing บน Web:** จะทำ backend proxy/OSRM หรือคงปิด route drawing บน Web
5. **Storage ของ config:** ตารางใหม่ + backend endpoint หรือใช้ `app_settings` เดิมที่แก้ policy
6. **Permission:** ใช้ role `admin` ต่อก่อน แล้วค่อยแยก `platform.map.manage`
