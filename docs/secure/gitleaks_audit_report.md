# Gitleaks Full-History Audit Report — Plan 07 K7

> **Date:** 2026-07-28
> **Tool:** gitleaks v8.21.2
> **Scope:** Full git history (302 commits, ~40 MB scanned)
> **Config:** `.gitleaks.toml`

---

## 1. Summary

| Metric | Value |
|--------|-------|
| Commits scanned | 302 |
| Bytes scanned | ~40.28 MB |
| Total findings | 15 |
| P2/P3 active secrets found | **0** |
| P1 keys in history (already handled) | 3 |
| False positives (variable names) | 1 |
| Placeholder values in documentation | 11 |

**Conclusion:** No active P2/P3 secrets found in git history. All findings are either placeholder values in documentation files or P1 keys (Google Maps API key) that have already been moved to dart-define. No rotation/revoke required at this time.

---

## 2. Findings Breakdown

### 2.1 P1 Keys in Git History (Already Handled)

| # | File | Match | Commit | Status |
|---|------|-------|--------|--------|
| 1 | `lib/config/app_config.dart` | `AIzaSyB_cex2WRkdTKElFJ-Cjgsfhm0kk1AZkcQ` | `0139a72` | ✅ Moved to dart-define in current code |
| 2 | `lib/config/app_config.dart` | `AIzaSyB_cex2WRkdTKElFJ-Cjgsfhm0kk1AZkcQ` | `463b632` | ✅ Same key, older commit |
| 3 | `lib/config/app_config.dart` | `DEVELOPMENT_MOCK_KEY` | `8be05a58` | ✅ Allowlisted (mock value) |

**Action:** Google Maps API key is P1 (public by design, restricted by bundle ID/SHA). Already removed from source code. Key restriction must be verified in Google Cloud Console (K9).

### 2.2 False Positives (Variable Names)

| # | File | Match | Commit | Reason |
|---|------|-------|--------|--------|
| 4 | `websocket-server/services/consultation-queue.js` | `apiKey = SUPABASE_SERVICE_KEY` | `e13bf615` | Variable assignment from env var, not actual secret value |

**Action:** Added to `.gitleaksignore` to suppress future false positives.

### 2.3 Placeholder Values in Documentation

| # | File | Match | Commit | Type |
|---|------|-------|--------|------|
| 5 | `setup-new-machine.sh` | `JWT_SECRET=change_this_in_production` | `ce2c5e4` | Placeholder |
| 6 | `SETUP_NEW_MACHINE.md` | `PASSWORD=your_secure_password` | `ce2c5e4` | Placeholder |
| 7 | `SETUP_NEW_MACHINE.md` | `SECRET=your_facebook_app_secret` | `ce2c5e4` | Placeholder |
| 8 | `SETUP_NEW_MACHINE.md` | `JWT_SECRET=your_super_secret_key_change_this_in_production` | `ce2c5e4` | Placeholder |
| 9 | `SETUP_PLAN_SUMMARY.md` | `SECRET=your_facebook_app_secret` | `866ae05` | Placeholder |
| 10 | `SETUP_PLAN_SUMMARY.md` | `JWT_SECRET=your_super_secret_key_change_this_in_production` | `866ae05` | Placeholder |
| 11 | `websocket-server/QUICK_START.md` | `PASSWORD=your_actual_password` | `fb8aac4` | Placeholder |
| 12 | `.cursor/plans/...plan.md` | `PASSWORD=your_secure_password` | `b6ce434` | Placeholder |
| 13 | `.cursor/plans/...plan.md` | `SECRET=your_facebook_app_secret` | `b6ce434` | Placeholder |
| 14 | `.cursor/plans/...plan.md` | `JWT_SECRET=your_super_secret_key_change_this_in_production` | `b6ce434` | Placeholder |
| 15 | `.cursor/plans/...plan.md` | `JWT_SECRET=change_this_in_production` | `b6ce434` | Placeholder |

**Action:** All are placeholder values (e.g., "change_this_in_production", "your_secure_password"). No actual secrets. Added documentation paths to `.gitleaksignore`.

---

## 3. Risk Assessment

| Risk | Level | Details |
|------|-------|---------|
| Active P2/P3 secret in history | ✅ None found | No DB passwords, service_role keys, or real credentials in git history |
| P1 key in history (Google Maps) | 🟡 Low | Key is public by design; must verify restriction in Google Cloud Console |
| JWT secret placeholder | ✅ Safe | All are placeholder values, not real secrets |
| Facebook app secret placeholder | ✅ Safe | Placeholder only; no real Facebook integration yet |
| DB password placeholder | ✅ Safe | Placeholder only; real DB password is in `.env` (not committed) |

---

## 4. Actions Taken

1. **Created `.gitleaksignore`** — suppresses false positives and documentation placeholders
2. **Verified current source** — no hardcoded secrets in current codebase (Option A already done)
3. **Updated `.gitleaks.toml`** — documentation paths added to allowlist
4. **No rotation required** — no active secrets found in history

---

## 5. Recommendations

1. **K9:** Verify Google Maps API key restriction in Google Cloud Console (bundle ID/SHA)
2. **Documentation cleanup:** Replace placeholder values in setup docs with references to `.env.example`
3. **CI gate:** Gitleaks CI job is already configured as blocking gate for new secrets
4. **Periodic re-scan:** Run full-history audit quarterly or before major releases
