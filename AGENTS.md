# AGENTS.md

## Verification commands

- Analyze a single Dart file: `dart analyze lib/path/to/file.dart`
- Analyze whole project: `flutter analyze`
- Run tests: `flutter test`
- iOS build (no signing, fast check): `flutter build ios --no-codesign --debug`

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
  `LitGlassSurface.frosted` (light frosted tile preset), `GlassActionButton`,
  `GlassBadge`, `GlassIconButton`
- `glass_dialog.dart`: `GlassDialog.show` — bare glass panel shell
- `glass_confirm_dialog.dart`: `GlassConfirmDialog.show` — 2-button
  cancel/confirm with async loading + error retry
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
