# Phase 1 Impact Review — Map Provider Settings Model + Persistence

Date: 2026-03-xx · Phase: 1 (Settings model + persistence) · Status: **complete**
Scope per rollout plan §10.2 Phase 1 and Phase Completion Review §10.1.

---

## 1. What was implemented

| Component | Location | Notes |
|---|---|---|
| DB tables | `database/migrations/04_create_map_provider_config.sql` | `map_provider_config` (singleton per environment, `revision`, `config jsonb`) + `map_provider_config_audit` + index. Applied to local `sheserved` DB; revision 1 seeded for `dev`. |
| Backend route | `websocket-server/routes/map-config.js`, mounted in `server.js` | `GET /api/map-config` (public, safe fields + registry), `GET/PUT /api/admin/map-config`, `GET /api/admin/map-config/history`, `POST /api/admin/map-config/rollback`. Auth: `verifyToken` + `requireRole('admin')`. |
| Server validation | same file | Mirrors plan §4.5: required reason in prod, `osmNoTraffic` ack, `googleWebBudget` confirm, `yield_way` override rejected, tile readiness (`needs_key`, `dev_only` in prod), unknown-feature warning, stable reason codes. |
| Dart model + registry + resolution | `lib/features/admin/models/map_provider_config.dart` | `MapProviderConfig`, `MapTarget`, `FeatureOverride`, `ServicesConfig`, `FallbackConfig`, `TileSourceRegistry`, embedded `kEmbeddedMapConfig`. Resolution order: feature override → platform default → env default. |
| Client service | `lib/services/map_config_service.dart` | Load/save via `AuthenticatedHttpClient` (Bearer + 401 refresh), `expectedRevision`/`If-Match`, safe fallback to embedded defaults on load failure, 409 conflict + 422 server validation surfaces. |
| Admin UI | `lib/features/admin/presentation/widgets/map_provider_settings_section.dart`, mounted in `platform_settings_page.dart` | Sections per §4.1–4.12: status banner, platform defaults (Web/iOS/Android), feature overrides (`yield_way` locked), services (routing/search/traffic), fallback policy, effective config preview, revision history + rollback, sticky save bar, draft vs saved state, conflict banner, validation inline. |
| Tests | `websocket-server/test/map-config.test.js`, `test/features/admin/map_provider_config_test.dart`, `test/features/admin/map_provider_settings_section_test.dart` | See §3. |

**No production renderer was changed.** The new config is configuration-only; `google_maps_flutter` screens and `flutter_map` usage are untouched (verified: no diff under `lib/` outside admin feature + service).

**`app_settings` was not used** as write path (existing RLS is fully open; dedicated tables + backend-only writes instead).

## 2. Impact assessment (per §10.1 checklist)

| Dimension | Result |
|---|---|
| Production map behavior | Unchanged — nothing consumes `MapProviderConfig` for rendering yet. |
| Network | New endpoints only; no change to existing request paths. Public GET exposes only safe fields (no credentials in registry entries — `needsKey` flag only, never key material). |
| Security | Writes gated server-side by `requireRole('admin')`; client UI additionally behind `AuthGuardWidget(requiredRole: 'admin')`. Optimistic concurrency via `revision` (+ `If-Match` alt). Audit rows record actor, revision, reason, and diff snapshot for every save/rollback. |
| Cost/rate limits | `rateConfig` persisted; save-time guardrails: Google-on-Web requires budget confirmation; OSM requires no-realtime-traffic acknowledgement. |
| Emergency | `yield_way` locked to inherit from `emergency` (server rejects independent override). No emergency code touched. |
| Failure modes | Server down → embedded defaults + visible banner, no fake success, no fake save. Stale revision → 409 → conflict banner + reload CTA; other admin's config is not overwritten. 422 → errors inline, draft preserved. |
| Privacy | No PII in config; audit stores actor id only. |

## 3. Verification evidence

### Backend (`cd websocket-server && npm test`) — 28/28 pass

16 map-config cases:
- `GET /api/map-config` returns config + registry without auth
- PUT rejects anonymous (401) and non-admin (403)
- stale revision → 409, no write; matching revision → bump + audit row
- `If-Match` header as `expectedRevision` alternative
- validation: osm without tileSourceId, `needs_key` source (carto_light) rejected until key configured, `yield_way` override rejected, Google-on-Web requires budget confirm, OSM requires `osmNoTraffic` ack, `dev_only` source blocked in prod, prod requires reason
- history newest-first; rollback restores as a new revision (not overwrite)
- unknown feature key → warning not failure; stable reason codes + safe rejection diagnostics
- Live check during dev (backend up): `PUT` with stale revision returned HTTP 409; audit + history rows confirmed in DB

### Dart unit/widget (`flutter test test/features/admin/`) — 22/22 pass

Model/registry/resolution (15):
- default config round-trips through json; resolution precedence override→platform→env; unknown feature override warns; `needsKey`/`devOnly` gating; `usesOsm` flag; server-readiness overrides embedded registry defaults

Widget (7):
- loads config and renders all sections without save bar
- server down → app-default banner, no fake success
- enabling a platform → dirty → save asks Google budget confirmation
- 409 → conflict banner instead of overwrite
- 422 → server validation errors inline, draft kept
- responsive, no `RenderFlex` overflow at **320×568 @ textScale 1.3**, **393×852**, **1280×800**

Analyzer: `dart analyze` clean on all changed files (only pre-existing info-level deprecations in `platform_settings_page.dart`).

### Layout defects found & fixed by the responsive test

- header/section title Rows → wrapped/`Expanded`
- feature inherit/custom `SegmentedButton` → `Wrap` + `ChoiceChip`
- renderer `SegmentedButton`s → `FittedBox(scaleDown)`
- tile-source/fallback/service dropdowns → `isExpanded: true`
- `Places fallback` trailing Row → `Flexible` label + moved under dropdown (last remaining 9.8px overflow at 320px/1.3×)

## 4. Known limitations / deferred

- Semantics/keyboard-navigation test coverage is partial (tooltips + Semantics labels present; full focus traversal test deferred to Phase 8 stabilization).
- `GET /api/admin/map-config/history` pagination is capped server-side; UI shows recent items only.
- Android smoke of settings UI not run (widget tests cover layout; platform renderers unchanged anyway).
- Migration lives in `database/migrations/` (local pool) — confirm deploy path applies it to staging/prod before enabling UI there.

## 5. Gate decision

**Go for Phase 2** (shared map adapter + fake tile harness). Phase 1 exit criteria met: config persists server-side with revision/audit, admin-only writes verified end-to-end, conflict + validation + safe-default behaviors tested, zero production-renderer impact.
