# Triage System — E2E Test Plan & PDPA Compliance Checklist

## E2E Test Scenarios

### Test 1: Add Victim (Consumer)
1. Login as consumer
2. Open incident → tap "คัดแยก" tab
3. Tap "แจ้งชื่อผู้ป่วย"
4. Fill prefix=นาย, firstName=สมชาย, lastName=ใจดี, consent=true
5. Verify: victim appears in list with masked name "นาย ส"
6. Verify: consent log entry created in `victim_report_consent_logs`

### Test 2: Assign Triage (Responder)
1. Login as responder (volunteer with profession category 'provider')
2. Open incident → tap "คัดแยก" tab
3. Tap color lens icon on victim card
4. Select "critical" (red)
5. Verify: triage level updated, card shows red badge
6. Verify: WebSocket event `victim-triage-updated` broadcast to room
7. Verify: `incident_victim_triage_logs` has new entry

### Test 3: Assign Black Tag (Deceased) — Provider Only
1. Login as responder with profession category='provider'
2. Open triage dialog → select "deceased"
3. Verify: reason field appears (≥ 10 chars required)
4. Verify: "ยืนยัน" text confirmation required
5. Fill reason="หมดสติ ไม่มีชีพจร นานเกิน 10 นาที", type "ยืนยัน"
6. Verify: triage level = deceased, deceased_confirmed_by set
7. Login as consumer → verify deceased victim NOT visible in list

### Test 4: Assign Black Tag — Non-Provider (Should Fail)
1. Login as responder with profession category='consumer'
2. Open triage dialog → verify "deceased" option is disabled
3. Verify: tooltip shows "เฉพาะผู้ให้บริการสุขภาพ (provider)"

### Test 5: Dispute Victim Name
1. Login as responder
2. Swipe left on victim card → tap "โต้แย้ง"
3. Enter reason ≥ 10 chars
4. Verify: verify_status = 'disputed', ⚠️ icon on card
5. Verify: WebSocket event `victim-disputed` broadcast

### Test 6: Edit Name After Dispute
1. Responder taps disputed victim card
2. Edit name → save
3. Verify: verify_status = 'confirmed', dispute icon cleared
4. Verify: WebSocket event `victim-name-updated` broadcast

### Test 7: Soft Delete Victim
1. Swipe left → tap "ลบ"
2. Enter reason ≥ 10 chars
3. Verify: victim disappears from list
4. Verify: is_deleted=TRUE in DB, deleted_reason recorded

### Test 8: Rate Limit
1. Set `victimReportRateLimitPerIncident=2` in app_settings
2. Consumer adds 2 victims → success
3. Consumer tries 3rd victim → 429 error

### Test 9: Masking — Thai Name
1. Add victim: prefix=นาย, firstName=สมชาย
2. Verify masked_name = "นาย ส"
3. Add victim: prefix=นางสาว, firstName=เกษม
3. Verify masked_name = "นางสาว ก" (skips leading vowel เ)

### Test 10: Retention Anonymization
1. Set `victimRetentionDays=1` in app_settings
2. Set `retention_countdown_started_at` to 2 days ago for a victim
3. Run anonymizer job
4. Verify: first_name=NULL, last_name=NULL for non-deceased, non-disputed victims
5. Verify: deceased victims are NOT anonymized
6. Verify: disputed victims are NOT anonymized

### Test 11: Cloud Sync
1. Add victim locally
2. Trigger sync
3. Verify: `cloud_incident_victims` has row with encrypted first_name_enc/last_name_enc
4. Verify: `is_synced=TRUE` in local table
5. Decrypt with key → verify matches original name

### Test 12: Health Data Unlock
1. Victim with linked_user_id, no health_data_consent_verified
2. Responder calls POST /api/victims/:id/health-data/unlock
3. Verify: 403 (no released session)
4. Create emergency_health_release_session with status='released'
5. Call unlock again → 200, health_data_consent_verified=TRUE
6. Verify: health_data_access_logs has new entry

---

## PDPA Compliance Checklist

- [x] **PII Masking**: Non-responders see masked_name only (first letter + prefix)
- [x] **Consent Logging**: Every victim insert logs consent in `victim_report_consent_logs`
- [x] **Health Data Access Logging**: Every health data access logged in `health_data_access_logs`
- [x] **Deceased Privacy**: Deceased victims hidden from non-responders/non-admins
- [x] **Deceased Health Lock**: Health data cannot be unlocked for deceased victims (DB CHECK constraint)
- [x] **Retention Period**: PII nulled after configurable retention days
- [x] **Retention Exclusions**: Deceased and disputed victims excluded from anonymization
- [x] **Cloud Encryption**: PII encrypted with pgcrypto before cloud sync
- [x] **Key Management**: pgcrypto key from environment variable (VICTIM_PGCRYPTO_KEY)
- [x] **Row-Level Security**: cloud_incident_victims has RLS (service_role only)
- [x] **Authenticated userId**: All mutations use `req.userId` from verifyToken, never from request body
- [x] **Role-Based Authorization**: Admin checks use `role='admin' AND is_active=TRUE`
- [x] **Responder Verification**: Uses `incident_responses.volunteer_id` with active statuses
- [x] **Rate Limiting**: Per-incident/per-reporter victim report limit enforced in DB function
- [x] **Audit Trail**: Triage level changes tracked in `incident_victim_triage_logs`
- [x] **Soft Delete**: Victims are soft-deleted with reason, not hard-deleted
- [x] **Dispute Audit**: Dispute reason, disputed_by, disputed_at recorded
- [x] **Edit Audit**: Name edits reset verify_status to 'confirmed', logged via updated_at
- [x] **Black Tag Authorization**: Only profession category='provider' can assign deceased
- [x] **Black Tag Reason**: Deceased requires clinical reason ≥ 10 characters
- [x] **Black Tag Confirmation**: UI requires typed "ยืนยัน" confirmation
