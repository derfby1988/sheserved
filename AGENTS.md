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
