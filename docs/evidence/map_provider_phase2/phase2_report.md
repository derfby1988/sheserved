# Map Provider Phase 2 — Shared Map Abstraction + Fake Tile Harness

Phase 2 of `docs/guides/map_provider_rollout_plan.md` (§10.2). Goal: a
renderer-independent map layer (model + controller facade + Google/OSM
adapters) with deterministic test infrastructure. **No production renderer
was migrated** — every existing screen still uses `google_maps_flutter`
directly.

## 1. Scope delivered

| Requirement (plan) | Delivered |
|---|---|
| Shared model (coords, camera, markers, polylines, bounds, padding, taps, capabilities, location/permission state) | `lib/shared/map/map_types.dart` |
| Controller facade (move/animate, fit bounds, dispose-safe) | `lib/shared/map/map_controller.dart` (`SheservedMapController`) |
| Fake controller for deterministic tests | `FakeSheservedMapController` (same file, records calls) |
| Google adapter (conversion internal, no Google types leak) | `lib/shared/map/adapters/google_adapter.dart` |
| OSM adapter (`flutter_map`, widget markers, injectable tile provider, attribution) | `lib/shared/map/adapters/osm_adapter.dart` |
| Renderer-selecting widget (no silent fallback) | `lib/shared/map/sheserved_map.dart` |
| Fake tile harness (no network in tests/goldens) | `lib/shared/map/testing/fake_tile_provider.dart` (embedded 256×256 PNG fixtures) |
| Unit + widget + golden tests | `test/shared/map/` — 33 tests |
| Platform smoke (Web/iOS/Android) | `tool/osm_tile_smoke/main.dart` → screenshots below |

Location/permission state is intentionally not wrapped: screens keep using
`geolocator` directly and pass the resulting `MapLatLng` via `userLocation`.
The shared contract only needs the *position*, per plan ("user location
through shared location state, not only Google's puck").

## 2. Architecture

```
screen ──► SheservedMap(target: MapTarget)          resolved by Phase 1 config
              │  (never falls back silently — disabled/unknown → visible placeholder)
              ├──► GoogleMapAdapter ──► gm.GoogleMap + GoogleAdapterController
              └──► OsmMapAdapter ──► fm.FlutterMap + OsmAdapterController
                          ▲ TileSource from TileSourceRegistry (Phase 1)
                          ▲ tileProvider injectable → FakeTileProvider in tests
```

- `MapTarget` (Phase 1 model) carries `enabled / renderer / tileSourceId` —
  resolution order (feature override → platform default → env default) is
  unchanged.
- Degenerate-bounds rule lives once in `normalizedFitBounds()`: empty →
  no-op, single point/zero-area → `moveTo`/`animateTo` at `fallbackZoom`,
  collinear → epsilon-expanded so Google never receives south≥north.
- Google conversion helpers are top-level exported functions so unit tests
  cover conversion without a platform view.

## 3. Test coverage vs plan §10.2

| Required | Test(s) | Status |
|---|---|---|
| Coordinate conversion | `map_types_test`, `google_adapter_test` latlng round-trip | ✅ |
| Bounds conversion | `toGoogleBounds` corners; `toOsmBounds` via widget tests | ✅ |
| Single-point bounds | `normalizedFitBounds` → null → caller animates | ✅ |
| Zero-area bounds | two identical points → null; `normalized()` epsilon-expands degenerate axes | ✅ |
| Invalid/empty bounds | `fromPoints` empty → null; `fitToBounds` empty → no-op | ✅ |
| Marker conversion | id/hue/label/onTap/consumeTapEvents; no-label → no InfoWindow | ✅ |
| Polyline conversion | points/color/width/round caps/dash→PatternItem | ✅ |
| Camera conversion | zoom/bearing/tilt preserved | ✅ |
| Controller lifecycle + disposal | fake records calls; OSM facade no-ops after dispose | ✅ |
| Fake controller command recording | `map_controller_test` | ✅ |
| Google adapter regression | 6 conversion tests | ✅ |
| OSM adapter conversion | render/tap/marker-tap/facade/dispose/user-dot/hue — 7 widget tests | ✅ |
| Widget tests (fake tiles, deterministic markers, tap, hit-test, dispose) | `osm_adapter_test` uses `FakeTileProvider`; `sheserved_map_test` covers renderer routing + placeholder states | ✅ |
| Golden test — local fixtures only | `osm_map_golden_test` → `goldens/osm_map_markers_route.png` (checkerboard fake tiles, primitive-drawn pins, no font/icon dependency, no network) | ✅ |
| Platform smoke Web | `smoke_web_adapter_osm_standard.png`, `smoke_web_adapter_osm_real.png` (real tiles via Caddy+recommended CSP) | ✅ |
| Platform smoke iOS | `smoke_ios_adapter_osm_standard.png` (simulator, real tiles) | ✅ |
| Platform smoke Android | `smoke_android_adapter_osm_standard.png` (SM-X135G device, real tiles, Thai labels, markers + polyline + attribution) | ✅ |
| Google regression suite | existing suite unchanged — see §5 | ✅ |

## 4. Impact review vs Google baseline (plan §10.1)

| Aspect | Google adapter | OSM adapter | Delta / note |
|---|---|---|---|
| Camera: move | `moveCamera(newLatLng[Zoom])` | `MapController.move` | parity |
| Camera: animate | `animateCamera` | **`move` — flutter_map has no built-in animated camera** (needs `flutter_map_animations` if we want animated transitions later) | known gap, acceptable for Phase 3+ simple screens; revisit before Rescue/Emergency migration |
| Bearing/tilt | full support | `initialRotation` supported; **tilt ignored** (flutter_map has no tilt) | screens using tilt must gate on `capabilities` |
| Padding | `GoogleMap.padding` shifts camera center | `padding` not propagated to adapter (only used inside `fitToBounds`) | **known difference** — screens that rely on persistent map padding must compensate before Phase 3+ migration |
| Fit bounds | animated `newLatLngBounds` | `fitCamera(CameraFit.bounds)` — synchronous jump | same semantic, different motion |
| Overlay ordering | markers above polylines (native) | `PolylineLayer` then `MarkerLayer` — markers above polylines | parity |
| Marker tap | `Marker.onTap` + `consumeTapEvents` | `GestureDetector` on marker widget | parity; `consumeTapEvents` is Google-only (no equivalent needed — OSM marker tap doesn't propagate) |
| Map tap | `onTap(LatLng)` | `MapOptions.onTap` → `MapLatLng` | parity |
| Gestures | four gesture flags off `gesturesEnabled` | `InteractiveFlag.all`/`none` | parity for enable/disable; per-gesture granularity not in shared contract yet |
| User location | native puck (`myLocationEnabled`) | dot marker from screen-supplied `MapLatLng` | by design — position source stays `geolocator` |
| Traffic | `trafficEnabled` | not available → `MapCapabilities.osm.trafficLayer = false` | UI must hide traffic UI when OSM (enforced via capabilities) |
| Platform view | AndroidView/UiKitView (native texture) | pure Flutter widgets — **no platform view** | OSM removes platform-view cost/bugs; better semantics on Web (no iframe) |
| Memory | native map + tile cache | Flutter image cache + `keepBuffer:4`/`panBuffer:1`; `retainTileCache` flag exists | watch image-cache pressure on long sessions; CancellableNetworkTileProvider already used |
| Render timing | async native surface (black flash possible) | widgets render first frame; tiles async | OSM smoke showed immediate chrome + progressive tiles |
| Controller create/dispose | `onMapCreated` → facade; `dispose()` guards + disposes inner | `onMapReady` → facade; `dispose()` guards + disposes inner | parity; both no-op after dispose (async-callback safe) |
| Tile source readiness | n/a | unknown `tileSourceId` → **visible placeholder, no silent fallback** | invariant from plan preserved |

## 5. Verification results

- `dart analyze lib/shared/map test/shared/map` → **No issues found**
- `flutter test test/shared/map` → **33/33 passed**
- Golden: `test/shared/map/goldens/osm_map_markers_route.png` generated once
  with `--update-goldens`, verified visually (checkerboard tiles, pins,
  polyline, attribution), then passing normally.
- Full `flutter test` → **680 passed, 11 skipped, 3 failed**. Two are the
  documented clean-checkout failures (`test/widget_test.dart`,
  `test/integration/phase2_role_sync_test.dart`). The third —
  `court_my_bookings_page_test.dart` ("expired shares the rejected tab…")
  — is inside the uncommitted `sport_club/book_court` WIP and unrelated to
  the map work (expects text "สนามรออนุมัติ" not found; Phase 2 touches
  nothing under `features/sport_club/`).
- Android smoke required an `adb` daemon restart (device shell was hung);
  first `flutter run` hit a transient "Dart compiler exited unexpectedly",
  `flutter build apk --debug` then succeeded and produced the screenshot.

## 6. Files

New (Phase 2):

- `lib/shared/map/map_types.dart`
- `lib/shared/map/map_controller.dart`
- `lib/shared/map/sheserved_map.dart`
- `lib/shared/map/adapters/google_adapter.dart`
- `lib/shared/map/adapters/osm_adapter.dart`
- `lib/shared/map/testing/fake_tile_provider.dart`
- `test/shared/map/{map_types,map_controller,google_adapter,osm_adapter,sheserved_map,osm_map_golden}_test.dart`
- `test/shared/map/goldens/osm_map_markers_route.png`

Modified:

- `tool/osm_tile_smoke/main.dart` — now exercises the production
  `SheservedMap`/adapters instead of a copy of flutter_map code.

Untouched on purpose: every existing `google_maps_flutter` consumer
(`home_map_background`, `rescue_page`, `emergency_live_page`,
`create_group_page`, …). Verified: `grep shared/map lib/` matches only the
shared layer itself.

## 7. Post-completion developments (2026-10-06)

หลังรายงานนี้เขียน **Incident Overview Map** (VIDEO_SYSTEM_PLAN §22, v1)
landed บน feature branch เดียวกัน — พื้นผิวที่
`widgets/incident_map/incident_map_surface.dart` ใช้ contract ของ Phase 1
(`resolveTarget(MapFeature.emergency)` + gate `incidentOverviewMapEnabled`
ที่เพิ่มเข้า `map-config` ทั้ง server validation, Dart model และ admin
toggle) แต่ **ไม่ได้ใช้ shared adapter ของ Phase 2**: surface นั้นต้องการ
cluster markers ที่ขนาดตาม count, canvas-generated Google bitmaps และ
photo-card overlay ที่วางด้วย manual projection — ทั้งหมดอยู่นอก scope ของ
shared `MapMarker`/`MapPolyline` ปัจจุบัน

ผลต่อแผน: Phase 2 contract พิสูจน์แล้วว่าขับ renderer จริงได้ แต่ incident
map เป็น documented divergence — pending decision ว่าจะขยาย shared model
รองรับ cluster/overlay แล้วย้ายกลับ หรือบันทึกเป็น carve-out ถาวร (บันทึกใน
rollout plan §10.3 แล้ว)

## 8. Known limitations / risks carried forward

1. OSM camera animation is instant, not eased — fine for Phase 3–5 screens,
   reconsider `flutter_map_animations` before Rescue/Emergency (Phase 6–7).
2. OSM ignores persistent map `padding` outside `fitToBounds`.
3. OSM has no traffic/tilt/native-puck — `MapCapabilities` gates these; UI
   must check before offering toggles.
4. `CancellableNetworkTileProvider` default keeps OSM tile policy happy
   (identifiable UA `com.sheserved.app`); production tile source still
   pending commercial decision from Phase 0.
5. Google adapter not smoke-rendered in Phase 2 — production Google code is
   untouched, so regression risk is only in the (unexercised) adapter
   itself; Phase 3 will exercise it behind the config flag.

## 9. Rollback

Phase 2 adds code but wires nothing into production paths. Rollback =
delete `lib/shared/map/`, `test/shared/map/`, revert
`tool/osm_tile_smoke/main.dart`. No config, schema, or runtime change.

## 10. Pending items (tracked in rollout plan §10.3)

- ตัดสินใจ reconcile incident map surface ↔ shared adapter (ขยาย model หรือ carve-out)
- แก้ Web CSP ใน source (tile hosts ใน `connect-src` + `useLocalCanvasKit` ถาวร) — ปัจจุบัน patch เฉพาะ generated build
- ตัดสินใจ animated camera สำหรับ OSM ก่อน Phase 6–7
- Smoke Google adapter บนอุปกรณ์จริงใน Phase 3
- Production tile source (managed/self-host) — ยังเปิดตาม §15 ข้อ 1
