# Bounded Gateway Design — Plan 07 K10 / Option C

> **Date:** 2026-07-28
> **Status:** Design document (not yet implemented)

---

## 1. Purpose

The bounded gateway (Option C) is a backend proxy that holds P2/P3 secrets (service_role key, payment credentials, bank API keys, HIS/LAB credentials) and exposes only scoped, audited operations to the client. The client never sees these secrets.

## 2. Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Flutter App │────▶│  Bounded Gateway  │────▶│  Supabase (RLS)  │
│  (anon key)  │     │  (service_role)   │     │  PostgreSQL      │
└─────────────┘     └────────┬─────────┘     └─────────────────┘
                              │
                    ┌─────────┼─────────┐
                    │         │         │
              ┌─────▼──┐ ┌───▼──┐ ┌───▼───┐
              │Payment │ │Bank  │ │HIS/LAB│
              │Gateway │ │API   │ │API    │
              └────────┘ └──────┘ └───────┘
```

## 3. Scope

### 3.1 Phase 1 — service_role Proxy (blocks K10)

| Operation | Current | After Gateway |
|-----------|---------|---------------|
| Admin user management | Direct Supabase call with anon key | Gateway validates admin role, uses service_role |
| ERP data sync | Direct Supabase call | Gateway validates org membership, uses service_role |
| Payroll approval | Direct Supabase call | Gateway validates HR admin role, uses service_role |
| Procurement operations | Direct Supabase call | Gateway validates procurement role, uses service_role |

### 3.2 Phase 2 — External Integration Proxy

| Integration | Secret Level | Gateway Endpoint |
|-------------|-------------|-----------------|
| Payment (PromptPay, credit card) | P3 | `POST /gateway/payment/charge` |
| Bank (transfer, verify) | P3 | `POST /gateway/bank/transfer` |
| e-Tax (invoice submission) | P2 | `POST /gateway/etax/submit` |
| HIS/LAB (patient data sync) | P3 | `POST /gateway/his/sync` |

## 4. Security Requirements

1. **Authentication:** Gateway validates JWT from Supabase Auth or custom AuthService
2. **Authorization:** Gateway checks role/permission before forwarding request
3. **Audit:** All gateway requests logged with: user ID, action, timestamp, request hash, response status
4. **Rate limiting:** Per-user and per-IP rate limits
5. **Input validation:** All inputs validated before forwarding
6. **Secret isolation:** P2/P3 secrets only in gateway `.env`, never sent to client
7. **Network isolation:** Gateway runs on private network, not directly exposed

## 5. Implementation Plan

### Phase 1 (with Plan 09 — AuthN/AuthZ)
- [ ] Create gateway service (Node.js/Express or Supabase Edge Function)
- [ ] Move service_role key to gateway `.env`
- [ ] Implement admin user management proxy
- [ ] Implement ERP data sync proxy
- [ ] Add audit logging
- [ ] Add rate limiting
- [ ] Test with Maestro

### Phase 2 (with ERP modules)
- [ ] Implement payment gateway proxy
- [ ] Implement bank API proxy
- [ ] Implement e-Tax proxy
- [ ] Implement HIS/LAB proxy
- [ ] Add circuit breaker pattern
- [ ] Add retry with idempotency

## 6. Rollback

- Gateway can be bypassed by reverting to direct Supabase calls
- service_role key can be rotated independently
- Client config points to gateway URL via dart-define

## 7. Relationship to Other Plans

| Plan | Dependency |
|------|-----------|
| Plan 09 (AuthN/AuthZ) | Gateway needs role-based authorization |
| Plan 12 (Least Privilege) | Gateway enforces least privilege for P2/P3 operations |
| ERP (payment, bank, HIS, LAB) | Gateway is prerequisite for P3 integrations |
| Plan 08 (Session/Token) | Gateway validates JWT tokens |
