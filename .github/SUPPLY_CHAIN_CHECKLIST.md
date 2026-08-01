# Supply Chain Hardening Checklist — Plan 06 Option E (baseline)
# Approved as policy/checklist from 2026-07-28
# Review every new dependency addition and quarterly audit

## New Dependency Addition Checklist

Before adding any new package to `pubspec.yaml`, `package.json`, or native build files:

- [ ] **Necessity**: Is this package truly necessary, or can the functionality be written in < 200 lines?
- [ ] **Maintenance**: Last updated within 12 months? Has an active maintainer (more than 1 person or an organization)?
- [ ] **Download volume**: Reasonable download count (not a typosquat with low downloads)?
- [ ] **License**: Compatible with MIT/BSD-3-Clause/Apache-2.0? No GPL/AGPL in commercial product?
- [ ] **CVE check**: No unpatched CVEs? Checked via `npm audit` / OSV-Scanner / `flutter pub outdated`?
- [ ] **Transitive dependencies**: Not excessive? Reviewed the dependency tree?
- [ ] **Postinstall scripts**: Does the package have `postinstall` or `preinstall` scripts? If yes, reviewed the script content?
- [ ] **Alternatives**: If this package disappears, is there a viable alternative?
- [ ] **Security-sensitive path**: If this package touches auth, OAuth, payment, file upload, media parsing, or PHI — requires additional code-owner review

## GitHub Actions Hardening

- [ ] All third-party actions pinned to full commit SHA (not tags)
- [ ] Workflow permissions set to `contents: read` by default
- [ ] No `pull_request_target` trigger used with secrets

## npm Registry Hardening

- [ ] `.npmrc` in `websocket-server/` enforces lockfile v3 and no auto-save
- [ ] Integrity hashes verified in `package-lock.json`
- [ ] No `--legacy-peer-deps` in CI or production install

## Flutter/Dart Hardening

- [ ] `pubspec.lock` committed and reviewed in every PR that changes dependencies
- [ ] `flutter pub get` uses lockfile (not `pub upgrade` in CI)
- [ ] Deprecated/maintenance-mode packages tracked (e.g., `hive` v2 → consider `hive_ce` or `isar`)

## Native (iOS/Android) Hardening

- [ ] `Podfile.lock` committed and reviewed when iOS dependencies change
- [ ] Gradle dependency report reviewed when Android dependencies change
- [ ] Native smoke tests run for camera, location, health, WebRTC, and OAuth after dependency updates

## Quarterly Audit

- [ ] Run `flutter pub outdated --show-all` and review all outdated packages
- [ ] Run `npm audit --prefix websocket-server` and review all vulnerabilities
- [ ] Review `Podfile.lock` and Gradle dependencies for outdated/deprecated packages
- [ ] Check for packages that have been deprecated or archived since last audit
- [ ] Review vulnerability exception register — remove expired exceptions, renew if still needed
- [ ] Verify all GitHub Actions are still pinned to valid commit SHAs

## Vulnerability Exception Register

When a vulnerability cannot be immediately fixed, document:

| Field | Required |
|-------|----------|
| CVE/Advisory ID | Yes |
| Package + Version | Yes |
| Severity (CVSS) | Yes |
| Affected surface | Which module/endpoint uses this? |
| Exploitability assessment | Is the vulnerable code path reachable in production? |
| Compensating controls | What mitigations are in place? |
| Owner | Who is responsible for the fix? |
| Ticket/Issue | Tracking link |
| Expiry date | Must be < 90 days, renewable with review |
| Approval | Code-owner sign-off |
