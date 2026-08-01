# RLS Audit Report — Plan 07 K2

> **Date:** 2026-07-28
> **Auditor:** Automated scan + manual review
> **Status:** ✅ Initial audit complete; phased hardening in progress

---

## 1. Summary

| Category | Count | Status |
|----------|-------|--------|
| Tables WITH RLS + proper policies | 15 | ✅ Good |
| Tables WITH RLS but USING(true) | 23 | ⚠️ Needs tightening (Phase 2) |
| Tables WITHOUT RLS | 6 | 🔴 Fixed in migration `20260728120000` |
| Tables WITHOUT RLS (non-sensitive) | 2 | 🟡 Documented |

---

## 2. Tables Missing RLS (Fixed)

| Table | Sensitivity | Risk | Fix |
|-------|------------|------|-----|
| `chat_room_members` | 🔴 High | Exposes user IDs, read state, room membership | ✅ RLS enabled + owner-based policies |
| `videos` | 🔴 High | Exposes user-generated video metadata | ✅ RLS enabled + owner/public-ready policies |
| `video_gps_tracks` | 🟡 Medium | Linked to videos, exposes location data | ✅ RLS enabled + video-owner-based policy |
| `video_interactions` | 🟡 Medium | Exposes user activity (likes, views, gifts) | ✅ RLS enabled + owner-insert + public-read |
| `medications` | 🟢 Low | Master drug database, read-only | ✅ RLS enabled + authenticated-read |

---

## 3. Tables WITH RLS but USING(true) — Phase 2 Tightening

These tables have RLS enabled but use `USING(true)` policies, meaning any authenticated user can read/write all rows. Access control is currently enforced at the application layer (AuthService).

### 3.1 High-Priority (sensitive data)

| Table | Data | Risk | Phase 2 Plan |
|-------|------|------|-------------|
| `chat_rooms` | Room metadata, participant IDs | Cross-user chat access | Replace with `auth.uid() = ANY(participant_ids)` |
| `chat_messages` | Message content, sender | Cross-user message access | Replace with `sender_id = auth.uid() OR room_id IN (SELECT id FROM chat_rooms WHERE auth.uid() = ANY(participant_ids))` |
| `consultation_requests` | Patient/provider IDs, symptoms | Cross-user medical data | Replace with `user_id = auth.uid() OR provider_id = auth.uid()` |
| `payment_transactions` | Payment amounts, status | Financial data exposure | Replace with `user_id = auth.uid()` + service_role for admin |
| `checkout_sessions` | Checkout state, user ID | Financial data exposure | Replace with `user_id = auth.uid()` |
| `provider_credentials` | Professional credentials | Credential exposure | Replace with `user_id = auth.uid()` + admin service_role |
| `donation_contributions` | Donation amounts, user IDs | Financial data exposure | Replace with `user_id = auth.uid()` |

### 3.2 Medium-Priority (operational data)

| Table | Data | Risk | Phase 2 Plan |
|-------|------|------|-------------|
| `donation_requests` | Requester ID, category | Cross-user data | Replace with `user_id = auth.uid()` + public SELECT for approved |
| `delivery_orders` | Delivery state, addresses | Address exposure | Replace with `user_id = auth.uid()` + service_role for delivery |
| `provider_profiles` | Provider info, profession | Profile exposure | Keep SELECT USING(true), restrict modify to `user_id = auth.uid()` |
| `drug_risk_overrides` | Override settings | Settings exposure | Already tightened in `20260712200000` |
| `incident_responses` | Responder info | Cross-user data | Replace with `responder_id = auth.uid()` |
| `employees` | Employee data | HR data exposure | Already has `app.can_manage_employees()` for modify; SELECT is USING(true) |

### 3.3 Low-Priority (configuration/reference)

| Table | Data | Risk | Phase 2 Plan |
|-------|------|------|-------------|
| `professions` | Profession list | None (public reference) | Keep USING(true) for SELECT |
| `donation_categories` | Category list | None (public reference) | Keep USING(true) for SELECT |
| `communities` | Community list | None (public reference) | Keep USING(true) for SELECT |
| `community_leader_roles` | Role reference | None | Keep USING(true) for SELECT |
| `app_settings` | System settings | Low (non-sensitive) | Keep USING(true) for SELECT |
| `theme_presets` | Theme config | None | Keep USING(true) |
| `inbox_events` | Event log | Low (operational) | Replace with service_role only |
| `transaction_contexts` | Transaction metadata | Low (operational) | Replace with service_role only |
| `organization_roles` | Role assignments | Medium (RBAC) | Replace with `auth.uid() = user_id` + admin service_role |
| `role_module_permissions` | Permission config | Low (reference) | Replace with admin service_role only |
| `employee_roles` | Role assignments | Medium (HR) | Replace with `auth.uid() = user_id` + admin service_role |
| `organization_feature_flags` | Feature flags | Low (config) | Replace with service_role only |
| `registration_application_attachments` | Application files | Medium (PII) | Replace with `application_id IN (SELECT id FROM registration_applications WHERE user_id = auth.uid())` |

---

## 4. Tables WITH RLS + Proper Policies

| Table | Policy Type | Status |
|-------|------------|--------|
| `consultation_notes` | `provider_id = auth.uid()` / `patient_id = auth.uid()` | ✅ Good |
| `prescriptions` | `provider_id = auth.uid()` / `patient_id = auth.uid()` | ✅ Good |
| `doctor_quick_replies` | `provider_id = auth.uid()` | ✅ Good |
| `emergency_health_data_settings` | `auth.uid() = user_id` | ✅ Good |
| `emergency_health_release_sessions` | `auth.uid() = patient_id` | ✅ Good |
| `emergency_health_access_tokens` | `auth.uid() = responder_id` | ✅ Good |
| `health_data_access_logs` | `auth.uid() = patient_id` | ✅ Good |
| `emergency_health_dead_man_checkins` | `auth.uid() = user_id` | ✅ Good |
| `health_data_logs` | `auth.uid() = user_id` | ✅ Good |
| `consultation_symptoms` | `auth.uid() = user_id` (database/migrations) | ✅ Good |
| `consultation_reviews` | `auth.uid() = user_id OR provider_id` | ✅ Good |
| `device_health_metrics` | `auth.uid() = user_id` | ✅ Good |
| `platform_metrics` | Public read/upsert | ✅ Acceptable (analytics) |
| `consultation_room_experts` | `consultation_id IN (SELECT ... WHERE user_id = auth.uid() OR provider_id = auth.uid())` | ✅ Good |
| `employees` (modify) | `app.can_manage_employees(profession_id)` | ✅ Good (SELECT still USING(true)) |
| `donation_credits_ledger` | `user_id = auth.uid()` | ✅ Good |
| `payment_channels` | `profession_id`-based | ✅ Good |
| `user_dashboard_themes` | service_role + owner | ✅ Good |
| `app_notifications` | `recipient_id = auth.uid()` | ✅ Good |
| `registration_applications` | `user_id = auth.uid()` | ✅ Good |

---

## 5. Storage Buckets

| Bucket | Public Read | Write | Status |
|--------|------------|-------|--------|
| `donations` | Yes | Authenticated | ⚠️ Verify write restrictions |
| `avatars` | Yes | Owner only | ⚠️ Verify write restrictions |
| `video-thumbnails` | Yes | Owner only | ⚠️ Verify write restrictions |
| `consultation-attachments` | No | Participants only | ⚠️ Verify manually |

---

## 6. Edge Functions

Edge functions using `service_role` key must be audited for:
- [ ] Authorization header validation
- [ ] Rate limiting
- [ ] Input validation
- [ ] No embedded P2/P3 secrets

---

## 7. Phased Hardening Plan

### Phase 1 (Done — 2026-07-28)
- Enable RLS on tables missing it entirely
- Add owner-based policies for `chat_room_members`, `videos`, `video_gps_tracks`, `video_interactions`, `medications`
- Add tighter SELECT policy for `consultation_requests`

### Phase 2 (After staging environment — K3)
- Replace `USING(true)` policies with `auth.uid()`-based policies for high-priority tables
- Test with role-based regression matrix (consumer, provider, admin, unauthenticated)
- Phased rollout with rollback migration

### Phase 3 (After Supabase Auth migration — Plan 09)
- Complete migration from custom AuthService to Supabase Auth native
- All policies use `auth.uid()` directly
- Remove `USING(true)` policies entirely

---

## 8. Migration File

- `supabase/migrations/20260728120000_rls_audit_hardening.sql` — Phase 1 fixes (idempotent)
