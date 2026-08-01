# Secret Rotation Runbook — Plan 07 K4/K8

> **Status:** Draft
> **Date:** 2026-07-28
> **Owner:** TBD (assign with Plan 12)

---

## 1. Secret Inventory

| Secret | Classification | Location | Rotation Frequency | Owner |
|--------|---------------|----------|-------------------|-------|
| Supabase anon key | P1 | `config/*.json` (dart-define) | Quarterly | DevOps |
| Supabase service_role key | P2 | Supabase Dashboard / `.env` (backend) | Quarterly | DevOps |
| Google Maps API key | P1 | `config/*.json` (dart-define) | On-demand | DevOps |
| JWT signing secret | P2 | `.env` (backend) | Quarterly | Backend Lead |
| DB password | P2 | `.env` (backend) | Quarterly | DevOps |
| Redis password | P2 | `.env` (backend) | Quarterly | DevOps |
| Facebook app secret | P3 | `.env` (backend) | On-demand | DevOps |
| Bunny.net API key | P2 | `.env` (backend) | Quarterly | DevOps |

---

## 2. Rotation Procedures

### 2.1 Supabase Anon Key (P1)

**Dual-key overlap method:**
1. Generate new anon key in Supabase Dashboard
2. Update `config/dev.json`, `config/staging.json`, `config/prod.json` with new key
3. Build and deploy new app version
4. Verify app works with new key (monitor for 24h)
5. Revoke old anon key in Supabase Dashboard
6. Run gitleaks scan to confirm no old key in source

**Rollback:** Revert config to old key and rebuild (old key still valid until revoked)

### 2.2 Supabase service_role Key (P2)

**Dual-key overlap method:**
1. Generate new service_role key in Supabase Dashboard
2. Update `.env` on all backend instances with new key
3. Restart backend services
4. Verify health checks and critical paths (chat, consultation, video)
5. Monitor for 24h
6. Revoke old service_role key

**Rollback:** Revert `.env` to old key and restart (old key still valid until revoked)

### 2.3 JWT Signing Secret (P2)

**Dual-key overlap method:**
1. Generate new JWT secret (256-bit random)
2. Update `.env` with `JWT_SECRET_NEW=<new_secret>` alongside `JWT_SECRET=<old_secret>`
3. Deploy backend with dual-key support (verify both secrets)
4. Switch `JWT_SECRET` to new value, keep `JWT_SECRET_OLD` for grace period
5. Monitor for token refresh cycle (typically 1-7 days)
6. Remove `JWT_SECRET_OLD` and restart

**Rollback:** Revert to `JWT_SECRET_OLD` and restart

**Note:** All active JWT tokens will be invalidated when old secret is removed. Users will need to re-authenticate.

### 2.4 DB Password (P2)

**Cutover method (requires brief downtime):**
1. Generate new password
2. Update Supabase project DB password
3. Update `.env` on all backend instances
4. Restart backend services
5. Verify connection pool health

**Rollback:** Revert to old password (if still valid)

### 2.5 Google Maps API Key (P1)

**Dual-key overlap method:**
1. Create new API key in Google Cloud Console
2. Apply restrictions (bundle ID, SHA-1, API restrictions)
3. Update `config/*.json` with new key
4. Build and deploy new app version
5. Verify Maps functionality
6. Delete old API key

**Rollback:** Revert config to old key and rebuild

---

## 3. Emergency Rotation (Incident Response)

**Trigger:** Confirmed secret leak in git history, logs, or unauthorized access

**Steps:**
1. **Immediate:** Revoke compromised secret (do not wait for overlap)
2. **Notify:** Alert team via incident channel
3. **Rotate:** Follow rotation procedure above (skip overlap, direct cutover)
4. **Investigate:** Determine scope of exposure (audit logs, access logs)
5. **Document:** Record incident in `docs/secure/incident-log.md`
6. **Post-mortem:** Within 48h, identify root cause and prevention measures

---

## 4. Rotation Schedule

| Secret | Frequency | Next Due | Last Rotated |
|--------|-----------|----------|-------------|
| Supabase anon key | Quarterly | 2026-10-28 | 2026-07-28 (initial) |
| Supabase service_role | Quarterly | 2026-10-28 | 2026-07-28 (initial) |
| JWT secret | Quarterly | 2026-10-28 | 2026-07-28 (initial) |
| DB password | Quarterly | 2026-10-28 | 2026-07-28 (initial) |
| Google Maps API key | On-demand | — | 2026-07-28 (moved to dart-define) |

---

## 5. Verification Checklist

After each rotation:
- [ ] New secret is in `.env` or `config/*.json` (not in source code)
- [ ] gitleaks scan passes (no new secret in git)
- [ ] Application health check passes
- [ ] Critical user journeys pass (login, consultation, chat, video)
- [ ] Old secret is revoked/deleted
- [ ] Rotation date recorded in this runbook
- [ ] Team notified
