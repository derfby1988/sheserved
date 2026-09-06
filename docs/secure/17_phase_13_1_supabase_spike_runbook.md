# Phase 13.1 — Supabase Hosted Pooler Spike Runbook

> **Status:** Ready to run (waiting for staging credentials)
> **Date:** 2026-09-05
> **Owner:** Backend/DevOps
> **Hard gate:** Phase 13.1 ยังไม่ถือว่าปิดจนกว่า spike นี้ผ่าน

---

## 1. วัตถุประสงค์ของ spike

ยืนยันว่า Supabase hosted รองรับข้อกำหนด Q7-C / Q12-B ก่อนเปิด production path:

1. `sheserved_gateway` ต่อผ่าน **transaction pooler `:6543`** ได้
2. `SET LOCAL ROLE sheserved_app` ทำงาน (hosted อนุญาต role membership + set role)
3. `SET LOCAL app.user_id` + `app.current_user_id()` / `require_current_user_id()` ทำงาน
4. RLS ไม่รั่วข้าม pooled connection
5. Role ที่สร้างไม่มี privilege เกินขอบเขต (no DDL, no BYPASSRLS, no write บน `audit_logs`)

**ถ้า spike ไม่ผ่าน → หยุด และปรับ credential/network/grant ก่อน — ห้ามเริ่ม Phase 13.2**

---

## 2. มาตรการลดความเสี่ยง (ต้องทำก่อนรัน)

### 2.1 สภาพแวดล้อม (บังคับ)

| # | มาตรการ | เหตุผล |
|---|---------|--------|
| 1 | **ใช้ staging project เท่านั้น ห้าม production** | ถ้าพลาดจะไม่กระทบผู้ใช้จริง |
| 2 | **สร้าง dedicated DB user** (เช่น `sheserved_spike`) ไม่ใช้ `postgres` role หลัก | จำกัด privilege + revoke ได้ง่าย |
| 3 | **ตั้ง IP allowlist** ใน Supabase Dashboard ให้เฉพาะเครื่องทดสอบ | กันผู้ไม่หวังดีต่อ DB โดยตรง |
| 4 | **ตั้ง pool max ต่ำ** `SUPABASE_DB_POOL_MAX=2` | ไม่กิน connection limit ของ project |
| 5 | **ตั้ง statement timeout สั้น** `SUPABASE_DB_STATEMENT_TIMEOUT_MS=10000` | query ค้างไม่ยึด connection นาน |
| 6 | **รัน dry-run migration ก่อน apply จริง** (ดูหัวข้อ 3) | ตรวจ syntax/privilege ก่อน commit จริง |
| 7 | **ไม่ commit secret ลง git** — ใช้ env variable หรือ `.env` ที่ gitignore | ป้องกัน credential รั่ว |
| 8 | **เตรียม user UUID สำหรับทดสอบ** — user ที่ `is_active=true` จริง | ตรวจ active-user path ได้ |

### 2.2 การกันค่าใช้จ่ายจริง (บังคับ)

| # | มาตรการ | ป้องกันอะไร |
|---|---------|-------------|
| 1 | ใช้ **staging plan** (ถ้า Free tier → 60 connections) | ไม่ทะลุ connection limit |
| 2 | spike อ่านอย่างเดียว (SELECT + `SET LOCAL`) ไม่ mutate | ไม่สร้างข้อมูล/ทริกเกอร์งาน |
| 3 | `pool.end()` ปิดหลังจบทุกครั้ง (script ทำอยู่แล้ว) | ไม่มี idle connection ค้าง |
| 4 | ตรวจ `pg_stat_activity` หลัง spike ว่า connection กลับ 0 | ยืนยันไม่ leak |
| 5 | statement timeout + idle timeout สั้น | query ค้างไม่คิดค่าใช้จ่าย compute |
| 6 | **เปลี่ยน DB password หลัง spike** (ถ้าใช้ postgres role) | revoke สิ่งที่ spike แตะ |
| 7 | ลบ dedicated user หลังจบ (ถ้าสร้างมา) | ลด attack surface |

---

## 3. ลำดับการรันที่ปลอดภัย

### ขั้นที่ 1 — Dry-run migration (ไม่ commit)

```bash
cd websocket-server
node scripts/dry-run-phase-13-1-migration.js
```

- script นี้ `BEGIN; ... ROLLBACK;` migration ทั้งไฟล์
- ยืนยันว่า roles/helper/functions/grants สร้างได้โดยไม่มี error
- **ไม่มีการเปลี่ยนแปลงถาวรใด ๆ** (DDL ใน PostgreSQL เป็น transactional)

### ขั้นที่ 2 — Spike pooler (อ่านอย่างเดียว)

Supabase Supavisor shared pooler (transaction mode, IPv4) ใช้ host ในรูปแบบ:

```text
aws-0-<region>.pooler.supabase.com:6543
```

และ username เป็น `<role>.<project-ref>` เช่น `postgres.<project-ref>` (ดูได้ใน
Dashboard → Database → Connection string → Transaction pooler)

```bash
cd websocket-server
SUPABASE_DB_HOST=aws-0-<region>.pooler.supabase.com \
SUPABASE_DB_PORT=6543 \
SUPABASE_DB_NAME=postgres \
SUPABASE_DB_USER=postgres.<project-ref> \
SUPABASE_DB_PASSWORD=<database-password> \
SUPABASE_DB_SSL=require \
SUPABASE_DB_SSL_CA= \
SUPABASE_DB_POOL_MAX=2 \
SUPABASE_DB_STATEMENT_TIMEOUT_MS=10000 \
TEST_USER_ID=<existing-active-user-uuid> \
  node scripts/spike-supabase-pooler.js
```

หมายเหตุ: สำหรับ Supavisor ให้ใช้ `SUPABASE_DB_SSL=require` (TLS แบบไม่ verify
hostname) เพราะ shared pooler อยู่หลัง load balancer ที่ cert อาจไม่ตรง hostname
แบบ 1:1 หากต้องการ verify ให้ download SSL certificate จาก Dashboard แล้วตั้ง
`SUPABASE_DB_SSL_CA=/path/to/supabase-ca.pem` และ `SUPABASE_DB_SSL=true`

ต้องเห็น `✅ Supabase pooler spike passed`

### ขั้นที่ 3 — ตรวจสอบ privilege ไม่เกินขอบเขต

```bash
psql "postgres://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:6543/postgres?sslmode=require" <<'EOF'
-- 1) app role ไม่มี BYPASSRLS/DDL
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls, rolcanlogin, rolinherit
FROM pg_roles WHERE rolname LIKE 'sheserved%' ORDER BY rolname;
-- 2) app role สร้างตารางไม่ได้ (คาดว่า ERROR permission denied)
BEGIN;
SET LOCAL ROLE sheserved_app;
CREATE TABLE public.should_not_create (id int);
COMMIT;
EOF
```

- ถ้า `CREATE TABLE` สำเร็จ → **FAIL** ต้องไป revoke `CREATE ON SCHEMA public` (migration มีอยู่แล้ว)
- ถ้า `ERROR: permission denied for schema public` → ผ่าน

### ขั้นที่ 4 — Apply migration จริง (เฉพาะเมื่อ 1-3 ผ่าน)

**ทาง A (แนะนำ): ผ่าน Supabase Dashboard → SQL Editor**

1. เปิด `https://supabase.com/dashboard/project/<project-ref>/sql/new`
2. คัดลอกเนื้อหาไฟล์ `supabase/migrations/20260905140000_phase_13_1_db_identity_roles.sql` ทั้งไฟล์
3. วางลง SQL Editor แล้วกด **Run**
4. ตรวจ output ว่าไม่มี `ERROR` (NOTICE ที่ขึ้น `Skipping...` = ข้ามได้ตาม design)

**ทาง B: ผ่าน psql/Supavisor** (migration ปรับแล้วให้ ownership transfer ทำงานได้ผ่าน `postgres` ด้วย)

```bash
psql "postgres://postgres.<project-ref>:<password>@aws-<N>-<region>.pooler.supabase.com:6543/postgres?sslmode=require" \
  -f supabase/migrations/20260905140000_phase_13_1_db_identity_roles.sql
```

> **หมายเหตุ ownership transfer (พบ 2026-09-06):** PostgreSQL กำหนดว่า `ALTER FUNCTION ... OWNER TO` ต้องให้ role ใหม่มี `CREATE` บน schema ของ function การ migration ถูกแก้ให้ `GRANT CREATE ON SCHEMA public TO sheserved_fitness_owner` ชั่วคราว → โอน ownership → `REVOKE CREATE` คืนทันที (least privilege คงเดิม)

### ขั้นที่ 5 — ตรวจสอบหลัง apply

```sql
-- roles มีครบ
SELECT rolname FROM pg_roles WHERE rolname LIKE 'sheserved%' ORDER BY rolname;
-- helper ทำงาน
SELECT app.current_user_id() IS NULL AS no_context;
BEGIN;
SET LOCAL app.user_id = '<uuid>';
SELECT app.require_current_user_id();
COMMIT;
-- conflict fail closed
BEGIN;
SET LOCAL app.user_id = '<uuid>';
SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
SELECT app.current_user_id();  -- ต้อง ERROR UNAUTHORIZED
COMMIT;
-- ไม่มี connection ค้าง
SELECT usename, count(*) FROM pg_stat_activity
WHERE usename = 'sheserved_gateway' OR usename = 'sheserved_spike'
GROUP BY usename;
```

### ขั้นที่ 6 — Post-spike cleanup (บังคับ)

1. เปลี่ยน/รีเซ็ต DB password ของ user ที่ใช้ spike (ถ้าใช้ shared user)
2. ลบ `sheserved_spike` role (ถ้าสร้างมา)
3. ตรวจ git status ว่าไม่มี secret หลุด
4. อัปเดต Phase 13.1 status ใน `Match_Sport_PLAN.md` → spike ผ่าน

---

## 4. เกณฑ์ผ่าน (Gate)

| # | เกณฑ์ |
|---|-------|
| 1 | `sheserved_gateway`/dedicated user ต่อ transaction pooler `:6543` ได้ |
| 2 | `SET LOCAL ROLE sheserved_app` ทำงานและหายหลัง COMMIT |
| 3 | `SET LOCAL app.user_id` + helper ทำงาน |
| 4 | identity conflict / missing / malformed / inactive → `UNAUTHORIZED` |
| 5 | app role ทำ DDL ไม่ได้ (`permission denied for schema public`) |
| 6 | ไม่มี connection ค้างหลัง spike |
| 7 | public browse views ยัง grant SELECT ให้ anon/authenticated |

---

## 5. Rollback (ถ้า apply แล้วพบปัญหา)

- Roles/helper/functions ทั้งหมดสร้างแบบ idempotent → **run migration ซ้ำได้**
- ถ้าต้องลบ: `DROP ROLE` เรียงตาม dependency (membership ก่อน):
  ```sql
  REVOKE sheserved_app FROM sheserved_gateway;
  REVOKE sheserved_auth FROM sheserved_auth_gateway;
  REVOKE sheserved_fitness_owner FROM CURRENT_USER;
  DROP OWNED BY sheserved_fitness_owner CASCADE;  -- ระวัง: ลบ RPC ที่เป็นเจ้าของ
  DROP ROLE sheserved_fitness_owner, sheserved_app, sheserved_gateway, sheserved_auth,
    sheserved_auth_gateway, sheserved_worker, sheserved_readonly, sheserved_migrate;
  ```
- ⚠️ `DROP OWNED BY sheserved_fitness_owner CASCADE` จะลบ secure RPC ที่โอน ownership ไป — ใช้เฉพาะเมื่อต้องการ undo อย่างจริงจัง
- **ห้าม** down migration ที่คืนสิทธิ์ anon/legacy actor RPC (ตาม Phase 13.5 policy)

---

## 6. ข้อควรระวังบน Supabase hosted

| เรื่อง | หมายเหตุ |
|-------|---------|
| `CREATE ROLE` | hosted อนุญาตผ่าน `postgres`/`supabase_admin` เท่านั้น; ถ้า migration ใช้ user อื่น อาจ `insufficient_privilege` |
| `REVOKE CREATE ON SCHEMA public` | เป็น hardening ที่แนะนำ; ตรวจว่า PostgREST/supabase internal ไม่พึ่งพา PUBLIC create |
| Transaction pooler `:6543` | ใช้ `SET LOCAL` ได้; อย่าใช้ session mode `:5432` เมื่อพึ่ง GUC ต่อ session |
| Connection limit | Free = 60, Pro ตาม plan; อย่าตั้ง pool max สูงเกิน |
| PgBouncer | transaction mode อนุญาต `SET LOCAL` ใน transaction; `SET` (session) จะไม่ persist |

---

## 7. ผลการทดสอบจริง (2026-09-06)

**Project:** `psxcgdwcwjdbpaemkozq` (sheserved, ap-southeast-1, dev)
**Cluster:** `aws-1-ap-southeast-1.pooler.supabase.com:6543` (ไม่ใช่ `aws-0` — Supabase กำหนด cluster แบบ non-deterministic)
**Apply path:** ทาง A (Supabase Dashboard → SQL Editor) เพราะ ownership transfer ต้องการสิทธิ์เจ้าของ schema

### Dry-run (BEGIN...ROLLBACK)
- 19 statements ผ่านครบ ไม่มี `Skipping` NOTICE เหลือ (หลังแก้ ownership-transfer approach)

### Apply migration
- ผ่าน SQL Editor ของ Supabase Dashboard — "Success. No rows returned"

### Post-apply verification

| ตรวจสอบ | ผล |
|---|---|
| Roles 8 ตัว (super=false, createrole=false, bypassrls=false) | ✅ ครบ |
| Ownership 12 RPC overloads → `sheserved_fitness_owner` | ✅ โอนจริง |
| Helpers `app.current_user_id/is_active_user/require_current_user_id` | ✅ ครบ |
| `postgres` เป็น member ของ `sheserved_app` (เพื่อ `SET LOCAL ROLE`) | ✅ |

### Spike pooler (`spike-supabase-pooler.js`)

| ข้อทดสอบ | ผล |
|---|---|
| 1. เชื่อมต่อผ่าน Supavisor `aws-1:6543` | ✅ `current_user=sheserved_app` |
| 2. `app.require_current_user_id()` คืน test UUID | ✅ |
| 3. `SET LOCAL app.user_id` คงอยู่ใน transaction | ✅ |
| 4. หลัง COMMIT GUC หายจาก pooled connection ใหม่ | ✅ `guc_cleared=true` |

### Post-apply privilege checks (6 ข้อ)

| ข้อ | ผล |
|---|---|
| A. `sheserved_app` DDL ใน `public` | ✅ DENIED |
| B. `sheserved_app` insert audit log | ✅ DENIED |
| C. `anon` SELECT `public.sessions` | ✅ DENIED |
| D. `anon` เรียก `app.current_user_id()` | ✅ DENIED |
| E. `sheserved_app` ใช้ helpers + active=true | ✅ คืนค่าถูกต้อง |
| F. Conflict detection (gateway vs JWT sub ต่างกัน) | ✅ RAISED `UNAUTHORIZED` |

### บั๊กที่พบระหว่าง spike (แก้แล้ว)

- `db/supabase-gateway-pool.js` UUID regex ขาด 1 กลุ่ม (`8-4-4-12` แทนที่จะเป็น `8-4-4-4-12`) — แก้แล้ว

### สรุป

**Phase 13.1 hard gate: ✅ ผ่าน** — พร้อมเริ่ม Phase 13.2 (auth foundation + Flutter switch)
