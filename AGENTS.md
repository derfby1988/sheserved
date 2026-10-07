# AGENTS.md

## Verification commands

- Analyze a single Dart file: `dart analyze lib/path/to/file.dart`
- Analyze whole project: `flutter analyze`
- Run tests: `flutter test`
- iOS build (no signing, fast check): `flutter build ios --no-codesign --debug`

Note: on this machine `flutter analyze` crashes ("Could not find a command named
.../dart-sdk/bin/snapshots/analysis_server.dart.snapshot" — the SDK cache only
ships the AOT snapshot). Use `dart analyze lib test` instead; it reports the same
lints (the repo carries ~2.3k pre-existing info-level ones, so filter by path).

Two tests fail on a clean checkout and are not regressions:
`test/widget_test.dart` (stale rename-era assertion for the text `SHESERVED`) and
`test/integration/phase2_role_sync_test.dart` (needs an initialized Supabase
instance). Everything else should pass (`flutter test` → ~600 passed, 11 skipped).

Before running `dart format` on a file you touched, check whether it was already
unformatted at HEAD (`git show HEAD:<path> > /tmp/x.dart && dart format
--output=none --set-exit-if-changed /tmp/x.dart`). Several video/emergency files
carry pre-existing drift, and formatting them whole adds unrelated diff noise.

## Backend machine IP changes

When the primary machine's LAN IP changes (or a report looks like an IP
mismatch — e.g. upload works but lists/WebSocket are empty), follow the
"Checklist: เมื่อเปลี่ยน Network / IP Address" section under
"Network & Configuration Runbook" in `docs/plans/VIDEO_SYSTEM_PLAN.md` instead of
improvising: update `mainMachineIp` in `lib/config/app_config.dart` (single
source — `backendApiUrl`/`localApiUrl`/`websocketUrl` are aliases), update
`LOCAL_API_URL` in `websocket-server/.env`, restart Node + ensure Caddy on
:8080, then verify with
`curl http://<new-ip>:8080/api/videos/emergency/list` from another device and
run `flutter test test/core/app_config_test.dart`.

## Secondary machine — run & Google sign-in

Minimal run on the secondary machine (legacy Supabase auth, no backend needed):

```
flutter run -d <device-id>
```

No dart-defines required for Google sign-in (`USE_BACKEND_AUTH` defaults to
`false` → `_handleSocialLogin` hits Supabase `users` directly by
`social_provider`/`social_id`). If sign-in throws `ApiException: 10`, the APK's
SHA-1 is not registered as an Android OAuth client in GCP — **always read the
SHA-1 from the built APK**, not from `~/.android/debug.keystore`, because builds
run inside Devin use a separate keystore at `~/.devin_config/.android/`
(different fingerprint):

```
~/Library/Android/sdk/build-tools/*/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-debug.apk | grep 'SHA-1'
```

Register every keystore's SHA-1 as its own Android OAuth client (additive, safe
for other machines). Full diagnosis/fix steps: "🔐 Runbook: Google Sign-In
`ApiException: 10`" in `docs/plans/VIDEO_SYSTEM_PLAN.md`.

## iOS / CocoaPods

The iOS project uses CocoaPods with the CDN trunk source. The local CDN specs
cache (`~/.cocoapods/repos/trunk`) can go stale and cause resolution failures
that look like real dependency conflicts, e.g.:

```
[!] CocoaPods could not find compatible versions for pod "GoogleUtilities/UserDefaults":
    In snapshot (Podfile.lock):
      GoogleUtilities/UserDefaults (= 8.1.3, ~> 8.0)
...
Error: CocoaPods's specs repository is too out-of-date to satisfy dependencies.
```

Diagnose by listing the cached versions:

```
ls ~/.cocoapods/repos/trunk/Specs/0/8/4/GoogleUtilities/
```

If the version required by `ios/Podfile.lock` is missing from that list, refresh
the cache instead of editing the Podfile:

```
cd ios && pod install --repo-update
```

Running plain `pod install` will not fix it — CocoaPods only checks the remote
for newer specs during a repo update, hence the "checking is only performed in
repo update" lines in the log.

After `pod install --repo-update`, only the `SPEC CHECKSUMS` entries for
path-based (Flutter plugin) pods normally change in `ios/Podfile.lock`;
resolved versions should stay identical.

Note: the `CocoaPods did not set the base configuration of your project` warning
is expected for Flutter projects and is not a failure.

## Shared glass UI (`lib/shared/widgets/glass/`)

Reusable glassmorphism layer — migrate dialogs gradually, do not restyle the
whole app at once.

- `glass_primitives.dart`: `LitGlassSurface` (dark translucent glass),
  `LitGlassSurface.frosted` (light frosted tile preset), `LitGlassTile`
  (translucent lit tile with white edge light, for light backdrops —
  the Sports Hub selected-pill look), `GlassActionButton`, `GlassBadge`,
  `GlassIconButton`
- `glass_dialog.dart`: `GlassDialog.show` — bare glass panel shell
- `glass_confirm_dialog.dart`: `GlassConfirmDialog.show` — 2-button
  cancel/confirm with async loading + error retry
- `GlassDatePicker`/`GlassTimePicker` live in
  `thai_address_picker/glass_date_time_picker.dart` (grouped with the other
  Thai pickers; they are glass-styled and import back into `glass/`)
- ERP pages keep using `showGlassDialog` (adapts dashboard theme to the shell)

### Migration checklist (pick before converting a dialog)

1. Simple text + buttons in one file → `GlassConfirmDialog.show`
2. Custom content with self-owned (light) colours → `GlassDialog.show`
   (default = dark translucent glass) + recolor the dialog's own chrome to
   white/mint
3. Content reuses shared widgets or hardcodes dark colours → `GlassDialog.show`
   + wrap that content in `LitGlassSurface.frosted` (do not restyle the inner
   widgets)

Rule of thumb: the panel is always dark translucent glass (like the
closed-ended confirm dialog). Light-themed inner content rides on frosted
tiles — never raise `panelFillOpacity` to make the panel itself light/milky.

## Court booking availability

- `CourtBookingDialog.show` takes `loadAvailability` (pass the repository's
  `getCourtAvailability` method) and returns a list of start/end ranges.
- Reuse `CourtAvailabilityPicker` with `freeOnly: true` and `selectedStarts`
  for booking selection; the detail sheet keeps the full status view.
- Adjacent selected hours merge into one range; disjoint ranges create separate
  bookings through the existing RPC. `bookSlots` stops on the first error and
  reports the confirmed prefix; terms retries reuse the remaining ranges' keys.
- Moving an existing pending booking uses `allowDisjoint: false` and keeps the
  single-booking change-slot RPC. Multi-range creation is not atomic.

## Court card styles (Book Court feed)

The venue card chrome is admin-selectable: **จัดการกีฬา → tab "รูปแบบการ์ด"**
(`ReviewProposedSportsPage` → `CourtCardStylePanel`).

- `CourtCardStyle` (`book_court/domain/court_card_style.dart`) — `classic`
  (flat, default) plus three 3D styles: `painter_3d`, `shader_glass`,
  `lottie_cubes`. Unknown/missing values fall back to `classic`.
- The choice is stored in `app_settings` key `court_card_style` as
  `{"style": "<wireValue>"}` and read/written by `CourtCardStyleService`
  (same admin-config table the donation/video panels write to — no migration).
  `CourtCard` listens to the service, so a change repaints the feed immediately.
- `CourtCard.styleOverride` renders one specific style — that is how the admin
  tab previews all styles side by side.
- The 3D styles must never render blank: `CourtCardCubeArt` falls back to the
  CustomPainter art when the sprite sheet or `FragmentProgram.fromAsset` fails
  (which is exactly what happens inside widget tests).
- Assets: `shaders/court_card_glass.frag` (registered under `flutter: shaders:`)
  and `assets/cubes/court_card_cubes_sheet.png` — a 4x4 sprite sheet of 16
  256px frames rendered by the glass ray tracer in
  `tool/render_court_card_cubes.py` (numpy + Pillow only, no Blender needed).
  Regenerate it with `python3 tool/render_court_card_cubes.py`; frame 0 is the
  hero still used by `painter_3d`/`shader_glass`.
- `flutter test` cannot compile shaders, so validate shader edits with
  `flutter build bundle` (it runs impellerc) and check
  `build/flutter_assets/shaders/court_card_glass.frag` exists.

## websocket-server (Node)

- `npm test` runs `node --test 'test/**/*.test.js'` (built-in runner, no extra deps). Unit
  tests stub `middleware/redis-client` and `services/room-authorization` in
  `require.cache` before loading the module under test — its `require()` calls
  are lazy, so no real Redis is needed.
- `npm run dev` uses nodemon watching `*.*`, so saving a file under
  `websocket-server/` auto-restarts the server — read its log to confirm behaviour.
- Runtime checks: `curl localhost:3000/health` (Node) and `curl localhost:8080/health`
  (Caddy); `redis-cli info clients` / `redis-cli client list` to catch connection
  leaks; publish to a channel with `redis-cli publish <channel> '<json>'`.

## SQL smoke test (Sports Hub)

`database/sports_hub_rpc_smoke_test.sql` creates real fixture users/venues/bookings,
so never point it at production or a shared project — use a scratch database.

It needs PostgreSQL 15+ (the migrations use `WITH (security_invoker = on)`), and it
loads the migrations itself via `\ir`, so run it from the `database/` directory:

```
/opt/homebrew/opt/postgresql@15/bin/psql -h <host> -p <port> -d <scratch> \
  -v ON_ERROR_STOP=1 -q -f sports_hub_rpc_smoke_test.sql > smoke.log 2>&1
grep -c 'PASS:' smoke.log   # failures print `FAIL:` / `ERROR:`
```

The Homebrew `postgresql@15` formula is keg-only, so call its binaries by full path;
it does not disturb a system PostgreSQL 14 installation. When adding a migration,
add the matching `\ir` line to the smoke script and extend the phase assertions.
