# Map Provider Phase 3 — Group Create Map (venue pin picker)

Phase 3 of `docs/guides/map_provider_rollout_plan.md` (§10, §10.2 Phase 3).
First production surface migrated to the shared adapter: the venue pin map
in `create_group_page.dart` now renders through `SheservedMap` driven by the
persisted provider config (`resolveTarget(MapFeature.groupCreate, …)`).

## 1. Scope delivered

| Requirement (plan exit gate) | Delivered |
|---|---|
| tap-to-pin on the card map | `VenueLocationMap` → `SheservedMap.onTap` → `_lat/_lng` |
| fullscreen picker (tap to move pin, confirm) | `VenueLocationPicker.show` → returns `MapLatLng?` |
| "use location" | `_acquireUserLocation` (Geolocator, shared by card + picker overlay) |
| restore พิกัดเดิม | `initial` pin seeds picker + camera zoom 17 |
| สร้างก๊วนได้ `lat/lng` เดิม | `_submit` unchanged — same fields to `createGroup` |
| Nominatim/Places flow unchanged | `_searchPlace`/`_centerMapOnAddress` untouched except `gm.LatLng`→`MapLatLng` |
| config-driven renderer, no silent fallback | `MapTarget.enabled` replaces `PlatformService.shouldShowLiveMap('group_create')`; disabled/unknown source → visible placeholder |
| Web fallback | `_buildWebMapFallback` kept; shown whenever `target.enabled == false` (any platform) |

Files:

- `lib/features/community/find_buddies/presentation/widgets/venue_location_picker.dart`
  — `VenueLocationMap` (card map) + `VenueLocationPicker.show` (fullscreen).
- `create_group_page.dart` — `gm.GoogleMapController` → `SheservedMapController`
  facade; `_loadMapConfig()` in `initState`; `_mapTarget` getter; all `gm.*`
  types removed (no `google_maps_flutter` import left in the page).
- `lib/services/platform_service.dart` — `mapPlatform` getter (single source,
  reused by `emergency_incident_map_logic.dart`).

## 2. Shared-contract additions (needed by the picker)

- `SheservedMapController.zoomBy(double delta)` — relative zoom for renderers
  without native zoom controls (`MapCapabilities.zoomControls == false`).
  Google → `CameraUpdate.zoomBy`; OSM → `move(center, zoom+delta)` clamped
  2–20; Fake records it (`lastZoomDelta`).
- `SheservedMap.capabilitiesFor(MapRendererKind)` — static lookup so a dialog
  can decide whether to draw overlay controls before the widget exists.
- `compassEnabled` passthrough (card map sets false, as before; OSM ignores).
- Adapter hardening: camera futures (`moveCamera`/`animateCamera`/`zoomBy`,
  `fitCamera`) now swallow platform errors — the facade contract is "never
  crashes after dispose / pre-layout", and a torn-down Google platform view
  or an unlaid-out `flutter_map` controller otherwise throws async.

Fullscreen picker overlays (OSM only): zoom +/- and my-location buttons are
drawn as widget overlays because `flutter_map` has none. My-location is lazy —
permission + fix happen on tap via the injected `getUserLocation`, so the
picker itself never touches Geolocator and stays testable.

## 3. Test coverage vs plan §10.2 Phase 3

| Required | Test(s) | Status |
|---|---|---|
| Widget tests: map card renders per provider | `venue_location_picker_test` — OSM→FlutterMap+pin+attribution, disabled→placeholder | ✅ |
| tap reports picked coordinate | `map tap reports the picked coordinate` | ✅ |
| fullscreen: tap→marker→confirm returns lat/lng | `osm: tap → marker → confirm returns picked coordinate` | ✅ |
| restore พิกัดเดิม | `initial pin restores and confirm returns the same point` | ✅ |
| dismiss without result | `close button dismisses without a result` | ✅ |
| my-location overlay (no puck) | `my-location overlay calls injected source and animates` | ✅ |
| Google keeps native controls | `google target keeps native controls (no overlays)` — GoogleMap + no overlay keys | ✅ |
| `zoomBy` contract | `map_controller_test` fake records; OSM adapter widget tests pass | ✅ |
| All shared-map tests | `test/shared/map/` + picker suite — **41 tests pass** | ✅ |

`flutter test` repo-wide: 812 passed, 11 skipped, 2 failed — both failures
pre-existing on clean checkout (`test/widget_test.dart` stale rename-era
assertion, `phase2_role_sync_test.dart` needs initialized Supabase; AGENTS.md).

`dart analyze` on all touched files: clean (the repo's ~2.3k pre-existing
info/error items are unrelated — verified filtered by path).

## 4. Impact assessment (§10.1, 8 ด้าน)

| ด้าน | ผล | หลักฐาน/เหตุผล |
|---|---|---|
| UI/layout/interaction | ผ่าน | widget tests: pin, fullscreen, FAB gating, overlay controls; layout/size unchanged (same 180px slot, same dialog chrome) |
| Functional/data | ผ่าน | tap/drag→`_lat/_lng` เหมือนเดิม; confirm/restore round-trip covered by tests; `_submit` payload untouched |
| Platform parity | ผ่าน (code) | OSM lacks native zoom/my-location → overlay equivalents; Google path unchanged (native controls) |
| Accessibility | ผ่าน | overlay buttons: Tooltip + semanticLabel + 44dp hit; ข้อความไทยทุกปุ่ม |
| Performance/stability | ผ่าน | facade commands never throw (dispose/pre-layout guarded); one config fetch in initState, non-blocking |
| Network/cost | ผ่าน | `logMapLoad('group_create')` kept (once per session); tile requests only when OSM enabled; tests use FakeTileProvider |
| Security/privacy/compliance | ผ่าน | no secrets in config path; OSM keeps UA + attribution layer; location fetched only on explicit user action |
| Integration/operations | ผ่าน | `MapFeature.groupCreate` key already valid server-side; feature override `group_create` resolves via Phase 1 contract |

## 5. Open items (carried to next phases)

- **Device smoke ทั้งสอง renderer บนหน้า group_create จริง** — pending; needs
  a physical/simulator run behind the config flag (Google adapter has still
  never rendered this screen on-device; OSM on web needs the CSP fix first,
  see §10.3 leftovers).
- "ไม่รองรับบนเว็บ" copy generalized to "ไม่รองรับบนแพลตฟอร์มนี้" since the
  gate is now config-driven, not web-only.
- `PlatformService.shouldShowLiveMap` remains for `home`/`rescue`/`emergency`
  until those pages migrate (Phases 4–7) — no cross-talk intended.
