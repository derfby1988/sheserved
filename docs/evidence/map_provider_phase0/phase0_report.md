# Phase 0 Report — Baseline & Tile-Source Decision

สถานะ: **Phase 0 complete — รอ user ตัดสินใจ Go/No-Go สำหรับ Phase 1**
วันที่: 2026-10-06 | อ้างอิง: `docs/guides/map_provider_rollout_plan.md` §10.2 Phase 0

Phase 0 เป็น decision/baseline phase เท่านั้น — **ไม่มีการแก้โค้ด production
หรือเปลี่ยนพฤติกรรมแผนที่ที่ผู้ใช้เห็น** ทุกงานทำบน scratch harness
(`tool/osm_tile_smoke/`) และ evidence เก็บในโฟลเดอร์นี้

---

## 1. วิธีทดสอบและเครื่องมือ

| ส่วน | เครื่องมือ |
|---|---|
| Google baseline | App จริง build `--dart-define=USE_BACKEND_AUTH=true` บน iPhone 16 sim (iOS 18.5), login จริงผ่าน backend `192.168.1.167:8080`, ขับด้วย `maestro/baseline_00_map_provider.yaml` |
| Tile smoke (iOS) | `tool/osm_tile_smoke/main.dart` — `flutter_map 8.3.1` + `CancellableNetworkTileProvider`, รัน `flutter run -t tool/osm_tile_smoke/main.dart -d <sim>`, ขับด้วย `maestro/smoke_osm_tiles.yaml` |
| Tile smoke (Web) | `flutter build web -t tool/osm_tile_smoke/main.dart -o build/osm_smoke` เสิร์ฟผ่าน `tool/osm_tile_smoke/Caddyfile.smoke` — CSP **เดียวกับ** `websocket-server/Caddyfile.dev` block :8081 บน port 8082 (CSP ปัจจุบัน) และ 8083 (CSP ที่เสนอเพิ่ม tile hosts) — screenshot ด้วย headless Chrome (`--headless=new`, `?src=<id>` เลือก source โดยไม่ต้อง tap) |
| HTTP checks | `curl -sI` ต่อ tile endpoint จริง (z12/x/y เดียวกันทุก provider) |

Environment: Flutter 3.41.6 / Dart 3.11.4, macOS 26 (Darwin 25.2.0), iPhone 16
sim iOS 18.5, headless Chrome (CPU-render fallback ไม่มี GPU — ไม่กระทบ
ผลลัพธ์ raster tile)

---

## 2. Google Maps baseline

พฤติกรรมที่บันทึกจาก app จริง (หลัง login admin):

| หลักฐาน | สิ่งที่เห็น |
|---|---|
| `baseline_ios_home_guest.png` / `baseline_ios_home_02_location_granted.png` | หน้า Home map โหลด Google tiles ปกติ (logo Google มุมซ้ายล่าง), location permission flow ทำงาน |
| `baseline_ios_sport_club.png` | หน้า Sport Club ปกติ |
| `baseline_ios_group_create_form.png`, `baseline_ios_group_create_map_1.png`, `baseline_ios_group_create_map_2.png` | หน้าสร้างก๊วนแสดง Google Map พร้อมช่องค้นหา (Nominatim อยู่แล้ว) และปุ่มควบคุม — logo "Google" ชัดเจนที่มุมซ้ายล่างของแผนที่ |

**ข้อจำกัดของ baseline:** ไม่ได้เก็บหลักฐาน Emergency/Rescue/Yield Way เพราะ
ต้องการภารกิจจริง/ข้อมูล realtime — จะเก็บใน Phase 5–7 บน staging ด้วย
synthetic incidents ตามแผน ไม่ fabrication

---

## 3. Candidate verification matrix

ทดสอบ tile เดียวกัน (`12/3190/1889` กรุงเทพฯ) + render จริงทั้ง iOS และ Web

| Source | HTTP | CORS | Cache-Control | render iOS | render Web | ข้อสรุป |
|---|---|---|---|---|---|---|
| OSM Standard `tile.openstreetmap.org` | 200 PNG | `*` | `max-age=95898` + stale-while-revalidate/if-error | ✅ `smoke_ios_osm_standard.png` | ✅ `smoke_web_chrome_osm.png` | **ใช้ได้จริงไม่ต้อง key แต่ ToS จำกัด** (§4.1) |
| CARTO Light `basemaps.cartocdn.com/light_all` | 200 PNG | `*` | `public, max-age=86400` | ⚠️ **"API KEY REQUIRED" watermark** `smoke_ios_carto_light.png` | ⚠️ watermark เดียวกัน `smoke_web_carto_light.png` | **endpoint keyless ถูกยกเลิก — ต้อง API key** |
| CARTO Voyager `.../rastertiles/voyager` | 200 PNG | `*` | `public, max-age=86400` | ⚠️ watermark | ⚠️ watermark `smoke_web_carto_voyager.png` | เหมือน Light |
| OpenTopoMap `a.tile.opentopomap.org` | 200 PNG | `*` | `max-age=604800` | ✅ `smoke_ios_opentopomap.png` | ✅ `smoke_web_opentopo.png` | ใช้ได้ไม่ต้อง key แต่ style topographic รกสำหรับ app ทั่วไป + policy จำกัด |

**สำคัญ:** HTTP 200 ≠ ใช้ได้ — CARTO ตอบ 200 แต่ส่งภาพ watermark เต็ม tile
ทั้ง iOS และ Web เห็นผลเดียวกัน ตรงกับการเปลี่ยนแปลงของ CARTO ที่บังคับ API key
สำหรับ basemaps (quota ~1M tiles/เดือนสำหรับ commercial, ~5M non-commercial —
ต้องยืนยันกับ CARTO)

---

## 4. ข้อค้นพบสำคัญ

### 4.1 OSM Tile Usage Policy (ขัดแย้งกับ production load)

`tile.openstreetmap.org` คือเซิร์ฟเวอร์สาธารณะที่ **ไม่ใช่ฟรีสำหรับทุก
application** — `flutter_map` พิมพ์ warning นี้เองตอนรัน harness:

- ต้องส่ง identifying User-Agent + Referer (web), แสดง attribution
- ห้าม bulk download, ห้าม `no-cache`, cache ตาม HTTP headers อย่างน้อย 7 วัน
- **ไม่มี SLA — อาจถูก block ถ้าโหลดสูง**
- แนวทางที่ OSM แนะนำสำหรับ app จริง: switchable tile config (ตรงกับแผน §3
  tile-source registry) หรือใช้ hosted/self-hosted tiles

→ **OSM Standard เหมาะเป็น dev/staging/fallback เท่านั้น ไม่ใช่ production
basemap หลัก** เว้นแต่ปริมาณใช้ต่ำมากและเตรียม fallback

### 4.2 CSP ปัจจุบันบล็อก web tiles ทั้งหมด (ยืนยันแล้ว)

ทดสอบ 2 variants บน Caddy จริง:

- **:8082 (CSP = Caddyfile.dev ปัจจุบัน):** console เต็มไปด้วย
  `"Connecting to 'https://tile.openstreetmap.org/...' violates connect-src ...
  The action has been blocked."` — แผนที่ว่างเปล่า `smoke_web_csp_current.png`
- **:8083 (CSP + tile hosts ใน connect-src):** ไม่มี violation, tiles render
  ปกติ `smoke_web_chrome_osm.png`, `smoke_web_opentopo.png`

**บทเรียนสำคัญ:** CanvasKit โหลด tiles ผ่าน fetch/XHR → ขึ้นกับ **`connect-src`
ไม่ใช่ `img-src`** (แม้ `img-src https:` จะอนุญาตทุก host ก็ไม่ช่วย)
→ CSP change เป็น prerequisite ของทุก OSM-based provider บน web โดยเฉพาะ
flow ที่ต้องเพิ่ม host ตาม tile-source registry

### 4.3 CSP ปัจจุบันบล็อก Flutter engine เองด้วย (pre-existing bug)

รอบแรกที่เสิร์ฟด้วย CSP ปัจจุบัน **app บูตไม่ขึ้นเลย**:

```
Connecting to 'https://www.gstatic.com/flutter-canvaskit/<rev>/chromium/canvaskit.wasm'
violates connect-src ... The action has been blocked.
Loading the script 'https://www.gstatic.com/flutter-canvaskit/<rev>/canvaskit.js'
violates script-src ... The action has been blocked.
```

`flutter_bootstrap.js` default โหลด engine จาก `gstatic.com` (ไม่อยู่ใน
script-src/connect-src) — **ถ้า web build จริงเสิร์ฟผ่าน Caddy ชุดนี้ app
จะขาวเปล่าเหมือนกัน** ไม่ว่าจะใช้ map provider ไหน

แก้ด้วยการเพิ่ม `"useLocalCanvasKit":true` ใน `_flutter.buildConfig`
(engine ถูก bundle อยู่ใน `build/*/canvaskit/` อยู่แล้ว → โหลดจาก `'self'`
ผ่าน CSP ปัจจุบันได้เลย ไม่ต้องเพิ่ม gstatic) — harness แพตช์ไฟล์ที่ generate
แล้วแล้วบูตและ render tiles สำเร็จ วิธีที่สะอาดสำหรับ production คือ build
ด้วย `--dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/` หรือเพิ่ม
`canvasKitBaseUrl` ใน index.html bootstrap config — **เป็นข้อเสนอแยกจาก map
provider (pre-existing defect ที่ควรแก้ก่อน Phase 3 บน web)**

### 4.4 flutter_map_cancellable_tile_provider ถูก discontinue

`flutter pub get` รายงาน `flutter_map_cancellable_tile_provider 3.1.1
(discontinued — replaced by flutter_map)` — flutter_map ≥6 มี cancellable
network tile provider ในตัว (`flutter_map`'s built-in) ฝั่ง adapter ใน Phase 2
ควรเปลี่ยนมาใช้ของที่มากับ flutter_map แทน dependency แยก

### 4.5 Routing/Search/Traffic ไม่ใช่เรื่องของ tiles

ยืนยันอีกครั้งตามแผน §7: raster tiles ให้เฉพาะภาพแผนที่ — Directions (Google
Directions ปัจจุบัน), Nominatim search (มีอยู่แล้วใน group create) และ traffic
เป็น service แยก ต้องเลือก/tune ต่างหาก ไม่ได้มาฟรีกับ tile source

---

## 5. Provider comparison (รวมตัวที่ต้องมี key)

| Provider | Key | Quota free (ต้องยืนยัน) | Commercial free | SLA | Thai labels | หมายเหตุ |
|---|---|---|---|---|---|---|
| OSM Standard | ไม่ต้อง | ไม่มี quota — แต่ policy จำกัดปริมาณ | ใช้ได้แต่เสี่ยงถูก block | ไม่มี | ดี (เห็นในภาพ) | dev/staging/fallback เท่านั้น |
| CARTO basemaps | **ต้อง** (keyless ตายแล้ว — §3) | ~1M tiles/เดือน (commercial) | ได้บน free tier | ไม่มีบน free | ดี (Light/Voyager สะอาด) | candidate หลักแบบ managed |
| OpenTopoMap | ไม่ต้อง | policy จำกัด (ขออนุญาต usage สูง) | จำกัด | ไม่มี | ดี | style รก — niche fallback |
| MapTiler | ต้อง | ~5,000 sessions/เดือน + 100k req | จำกัด free | มีบน paid | ดี (vector) | raster นับหนักกว่า vector |
| Thunderforest | ต้อง | ~150k tiles/เดือน hobby | ได้ | มีบน paid (~$125/เดือนขึ้นไป) | ดี | เหมาะราคากลาง |
| Stadia Maps | ต้อง | ~200k credits/เดือน | **free ไม่อนุญาต commercial** | มีบน paid ($20+/เดือน) | ดี | ต้อง paid สำหรับ Sheserved |
| Geoapify | ต้อง | ~3,000 credits/วัน (~12k tiles) | ได้บน free | มีบน paid | ดี | quota เล็ก — เหมาะเริ่มต้น |
| Self-hosted (tile server + OSM data) | ไม่ต้อง | ไม่จำกัด | ได้เต็มที่ | ขึ้นกับ infra เรา | ขึ้นกับ style | ต้นทุน ops สูงสุด — Phase อนาคต |

*ตัวเลข quota จากการวิจัย public pricing — ต้องยืนยันสัญญาจริงก่อน Phase 3
(เงื่อนไขเปลี่ยนบ่อย)*

---

## 6. Decision record

**ตัดสินใจ (เสนอ — รอ user confirm):**

1. **Tile-source registry ต้องรองรับ ≥2 profiles ที่สลับได้ runtime** —
   ยืนยันโดยผลทดสอบ: HTTP 200 ไม่พอ (CARTO watermark), provider ตาย/เปลี่ยน
   policy ได้ตลอด
2. **OSM Standard = ค่าเริ่มต้นสำหรับ dev/staging + canary fallback เท่านั้น
   ไม่ใช่ production basemap** — เหตุผล §4.1 (ไม่มี SLA, policy จำกัด)
3. **Production basemap ที่แนะนำ: CARTO Light/Voyager แบบมี API key** —
   style สะอาดใกล้ Google สุด, quota เพียงพอสำหรับ scale เริ่มต้น, มี managed
   SLA path เมื่อขยาย — เงื่อนไข: สมัคร key + ยืนยัน commercial terms +
   เก็บ key ใน secrets ไม่ใช่ source
4. **CSP prerequisite สำหรับ web (ทุก provider):** เพิ่ม tile hosts ลง
   `connect-src` ใน `websocket-server/Caddyfile.*` ทุก env + แก้ engine
   loading (`useLocalCanvasKit`) — เป็น defect pre-existing ที่บล็อก web
   ทั้งระบบไม่ว่า provider ไหน (§4.2–4.3)
5. **ตัวเลือกถูกตัดออก:** OpenTopoMap (style ไม่เหมาะเป็น basemap หลัก),
   keyless CARTO (ตายแล้ว), provider free-commercial-no (Stadia free tier)
6. **ยังไม่ตัดสินใจ:** routing/search/traffic (แยกจาก basemap — ยังใช้ของเดิม
   จนกว่าจะถึง Phase ที่ต้องเลือก)

---

## 7. Phase 0 exit gates & thresholds (สำหรับ Go/No-Go ไป Phase 1–2)

| Gate | เกณฑ์ | สถานะ |
|---|---|---|
| Google baseline บันทึกครบ | screenshot ครบทุกหน้าที่เข้าถึงได้ + ระบุข้อจำกัดส่วนที่ทำไม่ได้ | ✅ (Emergency/Rescue ระบุไว้ใน §2) |
| ≥1 keyless source render ได้ iOS + Web | 2+ sources ต้องผ่านจริง | ✅ OSM + OpenTopoMap |
| CSP/CORS path ระบุชัด | มี evidence ก่อน/หลัง + proposed change | ✅ §4.2–4.3 |
| ไม่มี runtime change | git diff ไม่แตะ `lib/` (ยกเว้นที่ไม่เกี่ยว) | ✅ แตะเฉพาะ `tool/`, `maestro/`, `docs/` |
| ไม่มี secret ใน source | ไม่มี API key ใหม่ commit | ✅ |
| Provider decision + thresholds | §6 + ตารางด้านล่าง | ✅ รอ user confirm |

**Measurable thresholds ที่ Phase 1–2 ต้องทำให้วัดได้:**

| Metric | Threshold (เริ่มต้น) |
|---|---|
| Tile success rate (production-candidate source) | ≥ 99% ของ request ที่ไม่ใช่ 4xx/5xx/timeout >10s ในช่วง canary |
| Tile error UX | tile ล้มเหลว → แสดง placeholder + retry, **ห้าม fallback เงียบ** ไป provider อื่นกลาง flow (ตาม §4.7 แผน) |
| Attribution | เห็นได้ชัดทุก provider ทุก zoom (เทียบภาพ smoke) |
| User-Agent/Referer | ส่ง identifying UA ตาม OSM policy ทุก platform |
| Cache | เคารพ Cache-Control ของ provider (ห้าม `no-cache` default; OSM ≥7 วัน) |
| Quota monitoring | นับ tile request ต่อวัน + alert ก่อนถึง 80% quota ของ source ที่เลือก (ต้องมี dashboard ใน Phase 1 settings) |
| Rollback | สลับกลับ Google ทุก feature ด้วย config เดียว (§4.9 revision/history) |
| CI | ทุก tile test ใช้ fake/local fixture — ห้ามยิง public tile server จาก CI |

---

## 8. ข้อจำกัดและงานต่อ

- **ยังไม่ได้ทดสอบ provider ที่ต้อง key กับ key จริง** — CARTO/MapTiler/อื่น
  ต้องสมัคร + เก็บใน secrets (Phase 1 ต้องออกแบบ secrets path ตาม §5.2 แผน)
- **ยังไม่ได้ทดสอบ Android** — simulator/emulator ไม่ได้ตั้งค่าในรอบนี้;
  tile fetch เป็น standard HTTPS เชื่อว่าพฤติกรรมเหมือน iOS แต่ควรยืนยัน
  ใน Phase 2 ด้วย harness เดียวกัน
- **Web variant B CSP เป็น proposal** — ต้อง review + apply ให้
  `Caddyfile.dev/local/staging` อย่างเป็นทางการใน Phase ที่เชื่อม web จริง
- **Traffic/Directions/Places** ยังเป็น Google ทั้งหมด — แผนถัดไปต้องเลือก
  alternative (เช่น OSRM/Valhalla/self-host) แยกต่างหากก่อน Phase 6–7
- Scratch harness + scratch Caddyfile เก็บไว้เป็น non-production tooling
  (มี comment ระบุชัดในไฟล์) — ใช้ซ้ำได้ใน Phase 2 และทุกครั้งที่เพิ่ม
  tile source ใหม่

## 9. Evidence index

| ไฟล์ | เนื้อหา |
|---|---|
| `baseline_ios_home_guest.png`, `baseline_ios_home_02_location_granted.png`, `baseline_ios_home_01.png` | Home map Google baseline |
| `baseline_ios_sport_club.png` | Sport Club baseline |
| `baseline_ios_group_create_{form,map_1,map_2}.png` | Group Create Google baseline (logo Google ชัด) |
| `smoke_ios_{osm_standard,carto_light,carto_voyager,opentopomap}.png` | iOS render ต่อ source |
| `smoke_web_csp_current.png` | Web + CSP ปัจจุบัน → tiles ถูกบล็อก (แผนที่ว่าง) |
| `smoke_web_chrome_osm.png` | Web + CSP ที่เสนอ → OSM render สมบูรณ์ |
| `smoke_web_{carto_light,carto_voyager}.png` | CARTO "API KEY REQUIRED" watermark |
| `smoke_web_opentopo.png` | OpenTopoMap render สมบูรณ์บน web |
| `tool/osm_tile_smoke/main.dart`, `Caddyfile.smoke` | harness + CSP variants |
| `maestro/smoke_osm_tiles.yaml`, `maestro/baseline_00_map_provider.yaml` | flows ที่ใช้เก็บภาพ |
