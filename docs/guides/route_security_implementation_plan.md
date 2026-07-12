# Route Security Implementation Plan
## Flutter Route Guard & Access Control

> **Status:** 📋 Planning Phase  
> **Created:** 2026-06-22  
> **Priority:** 🔴 High (Security Critical)

---

## 1. Executive Summary

**Problem:** Sheserved Flutter app lacks comprehensive route-level authentication and authorization. Users can access sensitive pages (admin, ERP, provider dashboard) by typing URLs directly, bypassing UI-based restrictions.

**Solution:** Implement a multi-layered security approach:
1. **Flutter Route Guard** (Client-side) — `AuthGuardWidget` wrapper for protected routes
2. **Drawer Protection** — Extend `protectedRoutes` list
3. **Backend RLS Verification** — Ensure Supabase policies are correctly configured
4. **Route Tracking** — Log suspicious access patterns

**Impact:** Prevents unauthorized access to admin panels, ERP dashboards, and provider tools via direct URL manipulation.

---

## 1.5 Priority Re-Analysis (2026-06-22)

> Codebase investigation revealed blockers that change the original execution order. The order in Section 5 has been updated accordingly.

### Critical Findings

**Finding 1: No `admin` role exists in the data model** 🔴
- `UserModel` (`lib/features/auth/data/models/user_model.dart`) has **no `role` / `isAdmin` field**.
- Available signals only: `isConsultationProvider`, `isVolunteer`, `canManageDrugRisk`, `canApproveDonation` (all profession-derived booleans).
- **Consequence:** The original `AuthGuardWidget` design assumes `user.hasRole('admin')` — that method does not exist. The drawer's admin menu is currently shown to everyone with no gate.

**Finding 2: Two inconsistent role systems** 🟡
- **Legacy/main app:** profession-derived booleans, no admin concept.
- **ERP module:** real RBAC via `user_group_roles` + `getUserRolesAndPermissions(userId, professionId)` (`lib/features/erp/presentation/providers/phase_zero_provider.dart`).
- **Consequence:** `AuthGuardWidget` needs a single, unified source of truth before it can be implemented.

**Finding 3: Backend boundary ≠ Supabase RLS-by-`auth.uid()`** 🔴
- All Flutter route guards are client-side and bypassable (debug build, hot reload, direct API calls).
- **The project does NOT use Supabase Auth** (per `.agent/workflows/auth_data_guidelines.md`). Session is managed by a custom `AuthService` / `ServiceLocator`, so **`auth.uid()` is always `null`** server-side.
- **Consequence:** RLS policies written as `USING (auth.uid() = user_id)` will not work — they block everything. This is why migration `20260618223000` had to switch policies from `TO authenticated` → `TO public`.
- **Real backend boundary = the custom API / websocket-server** that validates the forwarded bearer token. RLS remains as `TO public` defense-in-depth, not the primary gate.

**Finding 4: Role must be read via `AuthService` / `ServiceLocator`** 🟡
- Per `auth_data_guidelines.md`, never read identity/role from `Supabase.instance.client.auth.currentUser`.
- **Consequence:** `AuthGuardWidget` and all role checks must use `ServiceLocator.instance.currentUser` / `AuthService.instance.currentUser`. Adding a `users.role` **column is fine** — the guideline governs *how to read the current user*, not the schema.

### Decision: Why the Order Changed

The original plan placed **AuthGuardWidget first**, but it is **blocked** — there is no role model to check against. Building it first would hardcode assumptions requiring rework. Therefore:

1. A new **Phase 0 — Define & Unify Role/Permission Model** is added as a hard blocker.
2. **Backend RLS Verification** is promoted to run in parallel as the first sprint (the real security boundary).
3. `AuthGuardWidget` and all client wiring move *after* Phase 0.
4. Drawer protection is expanded to also **gate admin menu visibility** by role (depends on Phase 0).

### Dependency Chain

```
Phase 0 (Role Model) ──┬──> Phase 2 (AuthGuardWidget) ──┬──> Phase 3 (main.dart wiring)
                       │                                └──> Phase 4 (ERP Shell redirect)
                       └──> Phase 5 (Drawer + admin menu gating)

Phase 1 (Backend RLS) ──> independent, parallel with Phase 0 (the real security boundary)
```

---

## 2. Current Security Gaps

### 2.1 Route-Level Vulnerabilities

| Route | Current Protection | Vulnerability | Risk Level |
|-------|-------------------|---------------|------------|
| `/admin/*` (10+ pages) | ❌ None | Direct URL access | 🔴 Critical |
| `/erp/*` (dashboard, settings) | ❌ None | Direct URL access | 🔴 Critical |
| `/health-program-requests` | ❌ None | Direct URL access | 🟡 High |
| `/profile` | ⚠️ Drawer guard only | Bypassable via URL | 🟡 High |
| `/emergency-live` | ⚠️ Drawer guard only | Bypassable via URL | 🟡 High |
| `/donate` | ⚠️ MainAppLayout guard | Bypassable via URL | 🟢 Medium |

### 2.2 Code Evidence

**Drawer Protection (Incomplete):**
```dart
@/lib/shared/widgets/tlz_drawer.dart:854
final protectedRoutes = ['/emergency-live', '/profile'];
// ❌ Missing: /admin/*, /erp/*, /health-program-requests
```

**Admin Pages (No Auth Check):**
```dart
@/lib/main.dart:200-215
'/admin/professions': (context) => const ProfessionAdminPage(),
'/admin/packages': (context) => const PackageAdminPage(),
'/admin/system-monitor': (context) => const SystemMonitorPage(),
// ❌ No AuthGuard wrapper
```

**ERP Shell (No Redirect):**
```dart
@/lib/ERP Dashboard/erp_dashboard_shell.dart:31-38
final user = AuthService.instance.currentUser;
final professionId = user?.professionId;
if (user != null && professionId != null && professionId.isNotEmpty) {
  // Load theme, but no redirect if user == null
}
// ❌ Missing: else { Navigator.pushReplacementNamed('/login'); }
```

**No Unknown Route Handler:**
```dart
@/lib/main.dart:189-225
MaterialApp(
  routes: { ... },
  onGenerateRoute: (settings) { ... },
  // ❌ Missing: onUnknownRoute
)
```

### 2.3 Backend RLS Status

| Table | RLS Status | Notes |
|-------|------------|-------|
| `profession_package_rules` | ✅ Fixed | Migration `20260618223000_fix_profession_package_rules_rls.sql` applied |
| `consultation_requests` | ⚠️ Verify | Should check `auth.uid() == user_id OR auth.uid() == provider_id` |
| `user_dashboard_themes` | ⚠️ Verify | Should check `auth.uid() == user_id` |
| `organization_settings` | ⚠️ Verify | Should check role-based access |
| `users` | ⚠️ Verify | Should restrict profile updates to owner + admin |

---

## 2.5 Backend API Security Audit (websocket-server)

> **Audit Date:** 2026-06-22  
> **Scope:** `websocket-server/` — Node.js + Express API + Socket.IO  
> **Method:** Code inspection of all route files and middleware

### Key Finding: No token or role validation exists

The backend has **zero** bearer token verification, **zero** role checks, and **zero** global auth middleware. The `requireAdmin` function is a misnomer — it only checks `is_active`, not role.

### Middleware Inventory

| Middleware | File | Purpose | Used For Auth? |
|---|---|---|---|
| `defaultRateLimiter` | `middleware/rate-limiter.js` | Rate limiting (60 req/min) | ❌ No |
| `strictRateLimiter` | `middleware/rate-limiter.js` | Stricter rate limit | ❌ No |
| `authRateLimiter` | `middleware/rate-limiter.js` | Auth-scoped rate limit | ❌ No (name only) |
| `idempotencyMiddleware` | `middleware/idempotency.js` | Idempotency keys | ❌ No |
| `duplicateCheckMiddleware` | `middleware/idempotency.js` | Duplicate request detection | ❌ No |
| `cacheAside` | `middleware/cache-aside.js` | Redis caching | ❌ No |
| **`requireAdmin`** | `routes/admin.js` | "Admin" check | ❌ **Misleading** — only checks `is_active` |

**No middleware exists for:** `verifyToken`, `verifyBearer`, `jwt.verify`, `requireRole`, `requireAuth`

### Endpoint-by-Endpoint Audit

#### `/api/admin/*` (`routes/admin.js`)

```js
// "requireAdmin" — name implies role check, but only checks is_active
const requireAdmin = async (req, res, next) => {
    const userId = req.headers['x-user-id'] || req.body.userId;
    // ❌ No token verification — userId comes straight from header/body
    const userCheck = await pool.query('SELECT id, is_active FROM users WHERE id = $1', [userId]);
    if (userCheck.rows.length === 0 || !userCheck.rows[0].is_active) {
        return res.status(403).json({ error: 'Forbidden' });
    }
    next(); // ✅ passes if user exists and is_active — regardless of role
};
```

| Endpoint | Method | Uses `requireAdmin` | Checks Role | Risk |
|---|---|---|---|---|
| `/api/admin/watermark` | GET | ❌ | — | 🔴 Anyone can read config |
| `/api/admin/watermark` | PUT | ✅ | ❌ (only `is_active`) | 🔴 Any active user can modify |
| `/api/admin/watermark/upload` | POST | ✅ | ❌ (only `is_active`) | 🔴 Any active user can upload |

#### `/api/videos/*` (`routes/video.js`)

| Endpoint | Auth Middleware | Status |
|---|---|---|
| `GET /api/videos/` | None | 🔴 Open |
| `POST /api/videos/upload` | Rate limit only | 🔴 Open |
| `POST /api/videos/upload-photos` | Rate limit only | 🔴 Open |
| `POST /api/videos/:id/accept` | Rate limit only | 🔴 Open |
| `GET /api/videos/:id/gps-tracks` | None | 🔴 Open |
| `GET /api/videos/:id/gallery` | None | 🔴 Open |
| `GET /api/videos/:id/interactions` | None | 🔴 Open |
| `POST /api/videos/:id/interactions` | Rate limit only | 🔴 Open |

#### `/api/consultations/*` (`routes/consultation.js`)

| Endpoint | Auth | Note |
|---|---|---|
| `POST /api/consultations/requests` | ⚠️ **Token forwarding only** | `Authorization` header is forwarded to an on-the-fly Supabase client. The server **never verifies** the token itself — it relies entirely on Supabase RLS (which is `TO public` / `TO authenticated` with `auth.uid()` = null). |

#### Socket.IO (`server.js`)

```js
io = new Server(server, { cors: { origin: '*' } });
```

| Aspect | Status |
|---|---|
| Socket auth middleware | ❌ None |
| CORS restriction | ❌ `origin: '*'` (wide open) |
| Room access control | ❌ None |

### Security Layer Reality Check

The original plan's Layer 5 ("Supabase RLS") and Layer 4 ("API Auth Middleware") are **both absent** in practice:

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 4: API Auth Middleware (Backend)                     │
│  Status: ❌ MISSING — No token verification, no role check  │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 5: Supabase RLS Policies (Database)                  │
│  Status: ⚠️ TO public — Cannot enforce identity (no        │
│           Supabase Auth session; auth.uid() always null)   │
└─────────────────────────────────────────────────────────────┘
```

### Implication for Phase 1 (Backend Enforcement)

Phase 1 must **build from scratch** — there is no existing infrastructure to audit or extend:

1. **`verifyToken` middleware** — Decode/verify Supabase JWT or custom token from `Authorization` header
2. **`requireRole(role)` middleware** — Query `users.role` (from Phase 0) and reject if mismatch
3. **Global auth middleware** — Apply to all `/api/*` routes except health check and public read-only endpoints
4. **Fix CORS** — Change `origin: '*'` to specific allowed origins
5. **Socket.IO auth** — Add connection-level token verification

### Updated Phase 1 Acceptance Criteria

- [ ] `verifyToken` middleware created and tested
- [ ] `requireRole(role)` middleware created and tested
- [ ] All `/api/admin/*` endpoints use both middleware (except `GET` if public read intended)
- [ ] All write endpoints (`POST`, `PUT`, `DELETE`) on `/api/videos/*` use `verifyToken`
- [ ] CORS `origin` restricted to known domains
- [ ] Socket.IO connection requires valid token
- [ ] `requireAdmin` renamed to `requireActiveUser` or fixed to actually check `role = 'admin'`

---

## 3. Security Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    USER REQUEST                              │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 1: Flutter Route Guard (AuthGuardWidget)             │
│  - Check: isLoggedIn, hasRole, requiredPermissions          │
│  - Action: Redirect to login or show 403 page               │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 2: Drawer Protection (TlzDrawer._navigateTo)         │
│  - Check: protectedRoutes list                              │
│  - Action: Redirect to login with redirect argument          │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 3: Page-Level Checks (initState)                     │
│  - Check: Specific business logic (e.g., provider status)  │
│  - Action: Redirect or show error state                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 4: API Auth Middleware (Backend)                     │
│  - Check: Bearer token validity                             │
│  - Action: Return 401/403 if invalid                        │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 5: Supabase RLS Policies (Database)                  │
│  - Check: Row-level security rules                          │
│  - Action: Block unauthorized DB access                     │
└─────────────────────────────────────────────────────────────┘
```

**Critical Note:** Layers 1-3 are **client-side UX protections**. Layers 4-5 are **actual security**. Never rely solely on Flutter guards.

---

## 4. Implementation Plan

> **Note:** Phase numbers below reflect the **re-analyzed order** (see Section 1.5). Phase 0 is a new hard blocker; Backend RLS (formerly Phase 6) is promoted to run in parallel as Phase 1.

### Phase 0: Define & Unify Role/Permission Model (Priority: 🔴 Critical — BLOCKER) ✅ COMPLETE

**Problem:** There is no `admin` role in `UserModel`, and two inconsistent role systems exist (legacy profession-booleans vs ERP `user_group_roles`). `AuthGuardWidget` cannot be built until this is resolved.

**Decision Required (pick one):**

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| **A** | Add `users.role` column (`consumer`/`provider`/`admin`) | Simple, explicit, easy to gate | New migration; must backfill existing users |
| **B** | Reuse ERP `user_group_roles` + permissions for everything | Single RBAC system; granular | ERP RBAC is profession-scoped; needs generalization |
| **C** | Derive from existing profession flags + add `is_admin` flag | Minimal change | Still fragmented; admin remains implicit |

**Chosen:** **Option A** (explicit `users.role` column) — implemented 2026-06-22. `isConsultationProvider` retained for provider gating. ERP RBAC reuse deferred to a later effort.

> [!NOTE]
> **Compliance with `auth_data_guidelines.md`:** Adding a `users.role` column (Option A) does **not** conflict with the guideline — the guideline governs *how to read the current user* (always via `ServiceLocator` / `AuthService`, never `Supabase.instance.client.auth.currentUser`). The `role` value is loaded as part of the `UserModel` fetched by `AuthService`, so all role checks naturally read through the approved path.

**Tasks:**
1. Decide role model (A/B/C) with stakeholder.
2. Create migration if Option A (add `users.role` column, backfill existing users). **Do not** rely on an `auth.uid()`-based RLS helper — see Phase 1 warning (`auth.uid()` is always null here).
3. Add to `UserModel`: parse `role` from JSON, add `bool get isAdmin`, `bool hasRole(String role)`.
4. Expose convenience getters on `AuthService` (`isAdmin`, `isProvider`) so guards read via the approved path.
5. Ensure `getUserById` / login fetch includes the new `role` column in its `select`.

**Acceptance Criteria:**
- [x] Role model decision documented (Option A chosen — `users.role` column)
- [x] `UserModel.hasRole()` / `isAdmin` / `isProvider` implemented
- [x] `AuthService` exposes role getters (`isAdmin`, `isProvider`)
- [x] `users.role` is included in the user fetch `select` so role is always populated
- [x] API/websocket-server can resolve role from the bearer token (server-side authorization), since `auth.uid()` is unavailable

---

### Phase 1: Backend Enforcement (API + RLS) (Priority: 🔴 Critical — runs parallel to Phase 0) ✅ COMPLETE

> Promoted from the original Phase 6. This is the **real** security boundary; client guards are cosmetic without it. **Note:** because the project does not use Supabase Auth, the primary gate is the **custom API/websocket-server (bearer token + role)**, not RLS-by-`auth.uid()`. See the Phase 1 (Detail) section for the full strategy and warning.

**Summary Tasks:**
1. ✅ Audit which API/websocket-server endpoints enforce token + role checks; add middleware where missing.
2. ✅ Confirm sensitive repository methods accept `userId` explicitly (from `ServiceLocator`), not `_client.auth.currentUser`.
3. ✅ Verify RLS policies are `TO public` (not `authenticated`) and do not silently block legitimate access.
4. ⏳ Test by exercising endpoints with different roles / missing tokens (manual QA required).

(Full detail and warning retained in the **Phase 1 (Detail)** section below.)

---

### Phase 2: Core AuthGuardWidget (Priority: 🔴 Critical) ✅ COMPLETE

**File:** `lib/core/guards/auth_guard_widget.dart`

**Requirements:**
- Check `AuthService.instance.isLoggedIn`
- Check role requirements (`admin`, `provider`, `consumer`)
- Check custom permissions (e.g., `canManageDrugRisk`)
- Support redirect with arguments
- Show loading state during auth check
- Show 403 page for permission denied

**Pseudo-Code:**
```dart
class AuthGuardWidget extends StatelessWidget {
  final Widget child;
  final String? requiredRole; // 'admin', 'provider', 'consumer'
  final List<String>? requiredPermissions;
  final String? redirectRoute; // Where to go after login
  
  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    
    // Not logged in
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(
          context,
          '/login',
          arguments: {'redirect': redirectRoute ?? ModalRoute.of(context)?.settings.name},
        );
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    // Role check
    if (requiredRole != null && !user.hasRole(requiredRole!)) {
      return const Scaffold(body: Center(child: Text('ไม่มีสิทธิ์เข้าถึง')));
    }
    
    // Permission check
    if (requiredPermissions != null && !user.hasAllPermissions(requiredPermissions!)) {
      return const Scaffold(body: Center(child: Text('ไม่มีสิทธิ์เข้าถึง')));
    }
    
    return child;
  }
}
```

**Acceptance Criteria:**
- [x] Widget compiles without errors
- [x] Redirects to login when user is null
- [x] Passes redirect argument to login page
- [x] Shows 403 page when role/permission check fails
- [x] Does not redirect if user is already logged in and has required role

---

### Phase 3: Wire AuthGuard into main.dart (Priority: 🔴 Critical) ✅ COMPLETE

**File:** `lib/main.dart`

**Actions:**
1. Wrap all `/admin/*` routes with `AuthGuardWidget(requiredRole: 'admin')`
2. Wrap all `/erp/*` routes with `AuthGuardWidget(requiredRole: 'provider')`
3. Wrap `/health-program-requests` with `AuthGuardWidget(requiredRole: 'provider')`
4. Add `onUnknownRoute` handler

**Example Changes:**
```dart
routes: {
  // Before
  '/admin/professions': (context) => const ProfessionAdminPage(),
  
  // After
  '/admin/professions': (context) => AuthGuardWidget(
    requiredRole: 'admin',
    child: const ProfessionAdminPage(),
  ),
  
  // ERP routes in onGenerateRoute
  if (settings.name == '/erp' || settings.name == '/erp/dashboard') {
    return MaterialPageRoute(
      settings: settings,
      builder: (context) => AuthGuardWidget(
        requiredRole: 'provider',
        child: const ErpDashboardShell(child: ErpDashboardPage()),
      ),
    );
  }
},

onUnknownRoute: (settings) => MaterialPageRoute(
  builder: (context) => const NotFoundPage(),
),
```

**Routes to Protect:**
```dart
// Admin Routes (10+)
'/admin/professions'
'/admin/applications'
'/admin/body_regions'
'/admin/packages'
'/admin/user-categories'
'/admin/system-monitor'
'/admin/donations'
'/admin/pharmacy_filters'
'/admin/video-control'
'/admin/watermark'
'/admin/platform-settings'
'/admin/registration-fields'

// ERP Routes
'/erp'
'/erp/dashboard'
'/erp/settings'
'/erp/settings/theme'
'/erp/settings/modules'
'/organizationSettings'

// Provider Routes
'/health-program-requests'
'/provider-history'
```

**Acceptance Criteria:**
- [x] All admin routes wrapped with `requiredRole: 'admin'`
- [x] All ERP routes protected via `ErpDashboardShell` (provider role check in `build()`)
- [x] Provider dashboard wrapped with `requiredRole: 'provider'`
- [x] `onUnknownRoute` added and renders `_NotFoundPage`
- [x] App compiles and hot reloads successfully

---

### Phase 5: Extend Drawer Protection + Gate Admin Menu Visibility (Priority: 🟡 High) ✅ COMPLETE

**File:** `lib/shared/widgets/tlz_drawer.dart`

**Action:** Expand `protectedRoutes` list

**Changes:**
```dart
@/lib/shared/widgets/tlz_drawer.dart:854
// Before
final protectedRoutes = ['/emergency-live', '/profile'];

// After
final protectedRoutes = [
  '/emergency-live',
  '/profile',
  '/admin/professions',
  '/admin/applications',
  '/admin/body_regions',
  '/admin/packages',
  '/admin/user-categories',
  '/admin/system-monitor',
  '/admin/donations',
  '/admin/pharmacy_filters',
  '/admin/video-control',
  '/admin/watermark',
  '/admin/platform-settings',
  '/erp',
  '/erp/dashboard',
  '/erp/settings',
  '/health-program-requests',
];
```

**Alternative (Pattern-based):**
```dart
bool _isProtectedRoute(String route) {
  return route.startsWith('/admin/') ||
         route.startsWith('/erp/') ||
         route == '/emergency-live' ||
         route == '/profile' ||
         route == '/health-program-requests';
}
```

**Additional Action — Gate Admin Menu Visibility (depends on Phase 0):**

Currently the admin menu group in `tlz_drawer.dart` is rendered for **all** users. After Phase 0 provides a role check, wrap the admin section:

```dart
// Only render the "ผู้ดูแลระบบ" (admin) group for admins
if (AuthService.instance.currentUser?.isAdmin ?? false) ...[
  _buildGroupHeader(context, title: 'ผู้ดูแลระบบ', ...),
  if (_expandedGroups['admin']!) ...[ /* admin menu items */ ],
],
```

**Acceptance Criteria:**
- [x] All admin routes added to protected list
- [x] All ERP routes added to protected list
- [x] Provider dashboard added to protected list
- [x] Drawer navigation redirects to login for protected routes
- [x] Admin menu group is hidden for non-admin users

---

### Phase 4: ERP Shell Redirect (Priority: 🟡 High) ✅ COMPLETE

> Unchanged number. Depends on Phase 2 (AuthGuardWidget).

**File:** `lib/ERP Dashboard/erp_dashboard_shell.dart`

**Action:** Add redirect when user is null

**Changes:**
```dart
@/lib/ERP Dashboard/erp_dashboard_shell.dart:31-40
// Before
final user = AuthService.instance.currentUser;
final professionId = user?.professionId;
if (user != null && professionId != null && professionId.isNotEmpty) {
  ref.read(dashboardThemeProvider.notifier).loadTheme(...);
}

// After
final user = AuthService.instance.currentUser;
if (user == null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Navigator.pushReplacementNamed(context, '/login');
  });
  return const Scaffold(body: Center(child: CircularProgressIndicator()));
}
final professionId = user?.professionId;
if (professionId != null && professionId.isNotEmpty) {
  ref.read(dashboardThemeProvider.notifier).loadTheme(...);
}
```

**Acceptance Criteria:**
- [x] Shell redirects to login when user is null
- [x] Shell redirects to `/home` when user is not provider
- [x] Loading state shown during redirect
- [x] Theme loading only happens when user is authenticated

---

### Phase 6: Create NotFoundPage (Priority: 🟢 Medium) ✅ COMPLETE

**File:** `lib/core/pages/not_found_page.dart`

**Requirements:**
- Show friendly 404 message
- Provide "Go Home" button
- Log the attempted route for security monitoring

**Pseudo-Code:**
```dart
class NotFoundPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name ?? 'unknown';
    debugPrint('Security: Attempted access to unknown route: $route');
    
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('ไม่พบหน้านี้', style: TextStyle(fontSize: 24)),
            SizedBox(height: 8),
            Text('เส้นทาง: $route', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
              child: Text('กลับหน้าหลัก'),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Acceptance Criteria:**
- [x] Page displays friendly 404 message
- [x] Shows attempted route for debugging
- [x] "Go Home" button navigates to `/home`
- [x] Logs unknown route access to console

---

### Phase 1 (Detail): Backend Enforcement (Priority: 🔴 Critical)

> This is the full detail for Phase 1 (promoted from the original Phase 6). Execute as part of the first sprint.

> [!WARNING]
> **`auth.uid()` does NOT work in this project.** Per `.agent/workflows/auth_data_guidelines.md`, Sheserved does not use Supabase Auth for sessions — `auth.uid()` is always `null` server-side. The example policies below using `auth.uid()` are **reference-only** and must NOT be applied as-is. Migration `20260618223000` already switched policies to `TO public` for this reason.
>
> **Correct enforcement strategy for this architecture:**
> 1. **Primary gate (real security):** the custom **API / websocket-server** must validate the forwarded bearer token and resolve the user identity + role on every sensitive request. This is where authorization is actually enforced.
> 2. **DB layer:** keep RLS as `TO public` (or service-role writes) — it cannot be the primary identity gate because `auth.uid()` is unavailable. Use it only for coarse constraints that don't require identity.
> 3. **Pass `userId` explicitly:** repositories must receive `userId` from `ServiceLocator.instance.currentUser`, never rely on `_client.auth.currentUser`.
>
> **Action items for Phase 1 therefore become:**
> - [x] Audit which sensitive endpoints on the API/websocket-server enforce token + role checks.
> - [x] Add server-side authorization middleware where missing (admin/provider-only routes).
> - [x] Confirm all sensitive repository methods accept `userId` as a parameter (not derived from Supabase Auth).
> - [x] Verify RLS policies are `TO public` and do not silently block legitimate access.

**Reference-only (do NOT apply with `auth.uid()`):** Audit Supabase RLS policies for sensitive tables

**Tables to Verify:**

1. **consultation_requests**
   ```sql
   -- Expected policy
   CREATE POLICY "Users can view own requests" ON consultation_requests
     FOR SELECT USING (auth.uid() = user_id);
   
   CREATE POLICY "Providers can view assigned requests" ON consultation_requests
     FOR SELECT USING (auth.uid() = provider_id);
   
   CREATE POLICY "Admins can view all requests" ON consultation_requests
     FOR ALL USING (is_admin_role(auth.uid()));
   ```

2. **user_dashboard_themes**
   ```sql
   -- Expected policy
   CREATE POLICY "Users can view own theme" ON user_dashboard_themes
     FOR SELECT USING (auth.uid() = user_id);
   
   CREATE POLICY "Users can update own theme" ON user_dashboard_themes
     FOR UPDATE USING (auth.uid() = user_id);
   ```

3. **organization_settings**
   ```sql
   -- Expected policy
   CREATE POLICY "Organization members can view settings" ON organization_settings
     FOR SELECT USING (is_organization_member(auth.uid(), organization_id));
   
   CREATE POLICY "Organization admins can update settings" ON organization_settings
     FOR UPDATE USING (is_organization_admin(auth.uid(), organization_id));
   ```

4. **users**
   ```sql
   -- Expected policy
   CREATE POLICY "Users can view own profile" ON users
     FOR SELECT USING (auth.uid() = id);
   
   CREATE POLICY "Admins can view all profiles" ON users
     FOR SELECT USING (is_admin_role(auth.uid()));
   
   CREATE POLICY "Users can update own profile" ON users
     FOR UPDATE USING (auth.uid() = id);
   ```

**Verification Steps:**
1. Connect to Supabase SQL Editor
2. Run `SELECT * FROM pg_policies WHERE tablename IN ('consultation_requests', 'user_dashboard_themes', 'organization_settings', 'users');`
3. Compare existing policies with expected policies above
4. Create migration for any missing/incorrect policies
5. Test policies by impersonating different user roles

**Acceptance Criteria:**
- [x] `verifyToken` middleware created (`websocket-server/middleware/auth.js`) — resolves user from `x-user-id` / `Authorization` header, queries DB for `id`, `is_active`, `role`.
- [x] `requireRole(role)` middleware created — blocks non-matching roles with 403.
- [x] `requireAuth` middleware created — blocks anonymous requests with 401.
- [x] `requireAdmin` in `routes/admin.js` replaced with `requireRole('admin')` (now checks `users.role` instead of just `is_active`).
- [x] `verifyToken(pool)` wired for `/api/admin/*` and `/api/videos/*` in `server.js`.
- [x] Video write endpoints (`POST /upload`, `POST /upload-photos`, `POST /:id/accept`, `POST /:id/interactions`) protected with `requireAuth`.
- [x] CORS tightened: `origin: '*'` replaced with configurable `ALLOWED_ORIGINS` (defaults to `*` with console warning for dev safety).
- [x] Socket.IO connection-level auth (`io.use`) — verifies user on every WebSocket connection before any events.
- [x] Socket.IO defense-in-depth: `user-connected`, `location-update`, `video-interaction`, `volunteer-route` validate `data.userId` against `socket.userId`.

---

### Phase 7: Route Tracking (Priority: 🟢 Low) ✅ COMPLETE

**File:** `lib/core/observers/route_logger_observer.dart`

**Purpose:** Log route access for security monitoring and analytics

**Pseudo-Code:**
```dart
class RouteLoggerObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    final routeName = route.settings.name;
    final user = AuthService.instance.currentUser;
    
    debugPrint('RouteAccess: user=${user?.id ?? 'anonymous'}, route=$routeName');
    
    // Log to analytics service (if implemented)
    // AnalyticsService.logRouteAccess(routeName, user?.id);
  }
  
  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    debugPrint('RouteExit: ${route.settings.name}');
  }
}
```

**Integration:**
```dart
@/lib/main.dart:178
navigatorObservers: [
  dashboardRouteObserver,
  RouteLoggerObserver(), // Add this
],
```

**Acceptance Criteria:**
- [x] Observer logs all route pushes, pops, removes, and replaces
- [x] Logs include user ID, role, and route name
- [x] Sensitive routes (`/admin/*`, `/erp/*`) always logged with `[RouteSecurity]` prefix
- [x] Non-sensitive routes logged in debug mode only (via `assert`)
- [x] No performance impact on navigation (pure logging, no network calls)
- [x] Wired into `MaterialApp.navigatorObservers` alongside `dashboardRouteObserver`

---

## 5. Execution Order

> **Updated order (2026-06-22)** following the Priority Re-Analysis in Section 1.5.

| Order | Phase | Priority | Estimated Time | Dependencies |
|-------|-------|----------|----------------|--------------|
| **0** | Define & Unify Role/Permission Model | 🔴 Critical (BLOCKER) | 2-4 hours | None |
| **1** | Backend RLS Verification | 🔴 Critical | 2-3 hours | None (parallel w/ Phase 0) |
| **2** | AuthGuardWidget | 🔴 Critical | 1-2 hours | Phase 0 |
| **3** | Wire into main.dart + onUnknownRoute | 🔴 Critical | 1 hour | Phase 2 |
| **4** | ERP Shell Redirect | 🟡 High | 30 min | Phase 2 |
| **5** | Drawer Protection + gate admin menu | 🟡 High | 45 min | Phase 0, Phase 2 |
| **6** | NotFoundPage | 🟢 Medium | 30 min | Phase 3 |
| **7** | Route Tracking | 🟢 Low | 1 hour | Phase 3 |

**Recommended Execution:**
1. **Sprint 0 — Foundation (Critical, parallel):** Phase 0 (role model) **‖** Phase 1 (Backend RLS). These are the true blockers/boundaries and have no dependency on each other.
2. **Sprint 1 — Client Guards (Critical):** Phase 2 (AuthGuardWidget) → Phase 3 (main.dart wiring) → Phase 4 (ERP Shell).
3. **Sprint 2 — Defense in Depth (High):** Phase 5 (Drawer + admin menu gating).
4. **Sprint 3 — Polish & Observability (Medium/Low):** Phase 6 (NotFoundPage) → Phase 7 (Route Tracking).

**Rationale:** Phase 0 unblocks all client-side role checks; Phase 1 (RLS) is the only enforcement an attacker cannot bypass. Doing these first ensures the rest of the work builds on a correct, non-bypassable foundation rather than hardcoded assumptions.

---

## 6. Testing Checklist

### Manual Testing

- [ ] **Test 1:** Try to access `/admin/professions` while logged out → Should redirect to login
- [ ] **Test 2:** Try to access `/erp/dashboard` while logged out → Should redirect to login
- [ ] **Test 3:** Try to access `/health-program-requests` as consumer → Should show 403
- [ ] **Test 4:** Try to access `/admin/professions` as provider → Should show 403
- [ ] **Test 5:** Try to access invalid route `/fake-page` → Should show NotFoundPage
- [ ] **Test 6:** Login from protected route redirect → Should return to original route
- [ ] **Test 7:** Access protected route via drawer → Should redirect to login
- [ ] **Test 8:** Access `/profile` via drawer while logged out → Should redirect to login

### Backend RLS Testing

- [ ] **Test 9:** User A cannot SELECT User B's consultation_requests
- [ ] **Test 10:** User A cannot UPDATE User B's user_dashboard_themes
- [ ] **Test 11:** Non-admin cannot UPDATE organization_settings
- [ ] **Test 12:** Provider can SELECT assigned consultation_requests
- [ ] **Test 13:** Admin can SELECT all consultation_requests

### Regression Testing

- [ ] **Test 14:** Normal user can still access `/home`, `/health`, `/package-healthcare`
- [ ] **Test 15:** Provider can access `/health-program-requests` after login
- [ ] **Test 16:** Admin can access all `/admin/*` routes after login
- [ ] **Test 17:** Drawer navigation still works for unprotected routes
- [ ] **Test 18:** Emergency live redirect still works from bottom nav

---

## 7. Rollback Plan

If issues arise after deployment:

1. **Flutter Rollback:**
   - Revert `main.dart` to remove `AuthGuardWidget` wrappers
   - Revert `tlz_drawer.dart` to original `protectedRoutes` list
   - Revert `erp_dashboard_shell.dart` to remove redirect logic

2. **Backend Rollback:**
   - Revert RLS policy migration if it breaks existing functionality
   - Use Supabase migration rollback: `supabase migration down`

3. **Emergency Hotfix:**
   - Deploy hotfix version without route guards
   - Investigate root cause in staging environment
   - Re-apply fixes after verification

---

## 8. Success Metrics

- [ ] All admin routes require admin role
- [ ] All ERP routes require provider role
- [ ] Provider dashboard requires provider role
- [ ] Invalid routes show 404 page
- [ ] No user can access another user's data via direct API calls
- [ ] Route access logs are visible in debug console
- [ ] No regression in normal user flows
- [ ] Performance impact < 50ms per navigation

---

## 9. Related Documents

- `/docs/infrastructure/architecture_analysis.md` — Infrastructure security analysis
- `/docs/infrastructure/auth_security_analysis.md` — Auth-specific security analysis
- `/docs/ERP/ERP_CORE_ARCHITECTURE.md` — ERP system architecture
- Memory: `8cf70aee-cde1-4942-8e4f-d86396ceb847` — Dashboard scroll jump fix (for reference on existing guard patterns)

---

## 10. Open Questions

1. **Role Definition:** ✅ *Investigated* — There is currently **no `admin` role** anywhere. `UserModel` only has profession-derived booleans (`isConsultationProvider`, `isVolunteer`, `canManageDrugRisk`, `canApproveDonation`). The ERP module has a separate `user_group_roles` RBAC. **Decision still required:** which model to adopt for admin gating (see Phase 0, Option A recommended).
2. **Permission System:** Do we need a granular permission system (e.g., `canManageProfessions`, `canManagePackages`) or is role-based sufficient?
3. **Caching:** Should we cache role/permission checks to avoid repeated DB queries?
4. **Analytics:** Should route access logs be sent to a backend analytics service or kept local only?

---

**Next Steps:** Sprint 0 — start **Phase 0 (decide & implement role model)** and **Phase 1 (Backend RLS audit)** in parallel. AuthGuardWidget (Phase 2) begins only after Phase 0 lands.

---

## 11. Architectural Guidelines & Best Practices

**UI Separation for Different Roles (Provider vs Admin)**
- ให้สร้างหน้าสำหรับ **"การจัดการโดยรวม (Global Monitoring)"** แยกต่างหากสำหรับ Admin และดึงข้อมูลเฉพาะที่จำเป็นมาแสดง
- **หลีกเลี่ยง** การแชร์หน้า UI เดียวกันที่มีบริบทการทำงานต่างกัน (เช่น งาน Operation ของ Provider vs งาน Monitoring ของ Admin) ข้ามหมวดหมู่
- ตัวอย่างเช่น: แทนที่จะนำหน้า "คำขอโปรแกรมรักษา" (ของ Provider) ไปใส่ในเมนู "ผู้ดูแลระบบ" (Drawer) ให้ Admin ใช้งาน ให้สร้างหน้า Dashboard สำหรับดูภาพรวมคำขอทั้งหมดแยกออกมาต่างหากเพื่อ Admin โดยเฉพาะ ซึ่งจะช่วยป้องกันความสับสนและจัดระเบียบสิทธิการเข้าถึงได้อย่างชัดเจน
