# Google Maps API Key Restriction Guide — Plan 07 K9

> **Date:** 2026-07-28
> **Status:** Pending manual action in Google Cloud Console

---

## 1. Current State

- Google Maps API key was previously hardcoded in `lib/config/app_config.dart`
- Key `AIzaSyB_cex2WRkdTKElFJ-Cjgsfhm0kk1AZkcQ` found in git history (commits `0139a72`, `463b632`)
- Key has been moved to `config/*.json` via dart-define (Option A)
- Key is still in git history but gitleaks audit confirmed no active P2/P3 secrets

## 2. Required Actions (Google Cloud Console)

### 2.1 Restrict Existing API Key

1. Go to [Google Cloud Console → APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials)
2. Find the API key `AIzaSyB_cex2WRkdTKElFJ-Cjgsfhm0kk1AZkcQ`
3. Click **Edit API Key**
4. Under **Application restrictions**:
   - Select **iOS apps**
   - Add bundle identifier: `com.example.treeLawZoo`
   - (Optional) Add additional bundle IDs for staging/prod if different
5. Under **API restrictions**:
   - Select **Restrict key**
   - Enable only: **Maps SDK for iOS**
   - Disable all other APIs
6. Click **Save**

### 2.2 Create Separate Keys per Environment (Recommended)

| Environment | Key Purpose | Bundle ID | APIs |
|-------------|-----------|-----------|------|
| Dev | Development | `com.example.treeLawZoo.dev` | Maps SDK for iOS |
| Staging | Staging | `com.example.treeLawZoo.staging` | Maps SDK for iOS |
| Prod | Production | `com.example.treeLawZoo` | Maps SDK for iOS |

### 2.3 Verify Restriction

1. Build app with the key
2. Verify Maps loads correctly in the app
3. Test from a different bundle ID — should get API error
4. Monitor Google Cloud Console for unauthorized usage

## 3. Monitoring

- Set up billing alerts in Google Cloud Console
- Monitor API usage weekly for unexpected spikes
- If unauthorized usage detected: rotate key immediately

## 4. Rotation

If key needs to be rotated:
1. Create new restricted key in Google Cloud Console
2. Update `config/*.json` with new key
3. Build and deploy new app version
4. Verify Maps functionality
5. Delete old key
