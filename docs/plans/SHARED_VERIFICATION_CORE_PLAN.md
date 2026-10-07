# แผนพัฒนาระบบตรวจสอบหลักฐาน/สลิปส่วนกลาง (Shared Verification Core Plan)
> สถานะ: **ข้อเสนอ (proposal) — ยังไม่เริ่ม implement** · แก้ไขรอบที่ 3 (2026-10-07)
> อ้างอิงจาก: 21.7.21 ใน `Match_Sport_PLAN.md` (implement + live แล้ว), `20261010100000`–`20261015100000`
> ขอบเขตเอกสาร: ทำให้ระบบตรวจสลิปอัตโนมัติของ Sports Hub **ถูกต้อง ปลอดภัย และสลับ provider ได้** แล้วจึง (ถ้ามีระบบที่สองจริง) แยกเป็นแกนกลางที่ระบบอื่นของ Sheserved ใช้ร่วมได้ โดย**ไม่ทำให้ระบบจองสนามพัง**

## 0. อ่านก่อนเริ่ม

### 0.1 แผนนี้แบ่งเป็นสองช่วง

| ช่วง | Phase | คุณค่า | ต้องมีระบบที่สองไหม |
|---|---|---|---|
| **A — ทำให้ระบบเดิมแข็งแรงและสลับ provider ได้** | P0 – P4 | ปิดช่องโหว่ที่ **ยังเปิดอยู่บนระบบจริงวันนี้** (รวมช่องทุจริตที่เพิ่งพบ: ไม่ตรวจบัญชีผู้รับ), ทดสอบ/สังเกตการณ์ได้, เพิ่ม/สลับ provider ผ่าน UI ได้อย่างปลอดภัย | **ไม่ต้อง** — คุ้มค่าแม้ Sports เป็นระบบเดียว |
| **B — แกนกลางข้ามระบบ** | P5 – P8 | ระบบอื่นใช้ร่วมโดยไม่ copy โค้ด | **ต้อง** — เริ่มได้เมื่อผ่าน **decision gate D1** (มี domain ที่สองระบุชัดเจน) |

> **จุดหยุดที่ยอมรับได้:** หลัง P4 — ถ้าไม่มีระบบที่สอง แผนนี้ถือว่าสำเร็จครบแล้วโดยไม่ต้องสร้างแกนกลางแบบเดา requirement

### 0.2 ลำดับ phase ในหนึ่งบรรทัด

```
P0 ปิดช่องโหว่ไม่เปลี่ยนพฤติกรรม → P1 เครื่องมือพิสูจน์ว่าไม่พัง → P2 แก้ความถูกต้อง/ทุจริต/ความซ้ำซ้อน (เปลี่ยนพฤติกรรม แต่มี P1 คุ้มกัน)
→ P3 refactor ล้วน → P4 สลับ provider ผ่าน UI ───── [D1: มีระบบที่สองจริงไหม?] ─────
→ P5 แกนกลาง additive+shadow → [D2: ย้าย Sports จริงไหม?] → P6 cutover ด้วย flag → P7 domain ที่สอง → P8 เก็บกวาด
```

### 0.3 เหตุผลที่เรียงแบบนี้ (เทียบกับร่างก่อนหน้า)

| การเปลี่ยน | เหตุผล |
|---|---|
| ย้ายงานที่ **ไม่เปลี่ยนพฤติกรรม** (rotate key, adapter readiness, SSRF allowlist, audit) มาเป็น P0 | ลดความเสี่ยงทันที ต้นทุนต่ำ ทดสอบง่าย |
| **P1 (tests/observability) มาก่อนงานที่เปลี่ยนพฤติกรรม** | งานแก้ความถูกต้อง (P2) แตะเส้นทาง verify จริง — ต้องมีตาข่ายรองรับก่อน ไม่ใช่หลัง |
| แยก **P2 = hardening ที่เปลี่ยนพฤติกรรม** ออกจาก P0 | ร่างเดิมยัด HMAC/call-state ไว้ใน P0 ทั้งที่เป็นงานเสี่ยงและต้องมี test คุ้มกัน |
| **refactor (P3) หลัง hardening (P2)** | ไม่ต้อง refactor ซ้ำสองรอบ และพิสูจน์ "ไม่เปลี่ยนพฤติกรรม" ง่ายกว่าเมื่อพฤติกรรมนิ่งแล้ว |
| **UI สลับ provider (P4) มาก่อนแกนกลาง (P5)** | ตอบ need จริงที่ผู้ใช้ถาม (เพิ่ม provider) ได้ก่อน ความเสี่ยงต่ำกว่า cutover มาก และไม่ต้องรอระบบที่สอง |
| **เพิ่ม D1/D2 decision gates** ก่อน P5/P6 | กัน over-engineering: แกนกลางที่ออกแบบโดยไม่มี domain ที่สองมีโอกาสเดา scope/subject ผิด |
| ตัดการประมาณเวลาเป็นสัปดาห์ | ประเมินระยะเวลาเชิงตัวเลขไม่น่าเชื่อถือ — ใช้ dependency + gate เป็นตัวกำหนดจังหวะแทน |

> **กฎเหล็ก:** ทุก phase ต้องผ่าน gate ของตัวเองก่อนไป phase ถัดไป และทุก phase ต้องย้อนกลับได้โดยไม่ต้องแก้ข้อมูลธุรกิจ (booking/เงิน) ย้อนหลัง — ข้อยกเว้นเดียวที่ประกาศชัด: P2.b (ดู §3 ข้อ 13)

---

## 1. วัตถุประสงค์และผลลัพธ์ที่ต้องการ

### 1.1 เป้าหมาย

| # | เป้าหมาย | ตัวชี้วัดว่า "ทำได้" |
|---|---|---|
| G1 | ระบบอื่นของ Sheserved ใช้การตรวจหลักฐาน/สลิปได้โดยไม่ต้อง copy โค้ด | เพิ่ม domain ใหม่ = migration 1 ไฟล์ + adapter 1 ไฟล์ + widget policy ของ domain นั้น โดยไม่แตะแกนกลาง |
| G2 | Admin Sheserved เลือก provider แยกตามระบบได้ | มีตาราง routing ต่อ domain + UI ที่บล็อกการเลือก provider ที่ไม่มี adapter |
| G3 | ค่าใช้จ่าย provider ถูกควบคุมและตรวจสอบได้ | quota ต่อ scope + cap ต่อ provider + budget แพลตฟอร์ม + snapshot ราคาต่อ attempt + รายงานแยก domain/provider |
| G4 | ข้อมูลผู้ใช้ (สลิป/เลขธุรกรรม) ปลอดภัยและเป็นไปตามนโยบาย | ไม่เก็บ raw trans-ref; fingerprint เป็น HMAC + key version; retention + DPA อนุมัติก่อนเปิดวงกว้าง |
| **G6** | **สลิปที่ผ่านอัตโนมัติ "ใช่เงินที่โอนมาที่บัญชีนี้จริง ในเวลาที่เหมาะสม"** (ไม่ใช่แค่ยอดตรง) | ตรวจผู้รับ + เวลาโอนก่อน `verified` (P2.a) |
| G5 | **ระบบจองสนามไม่พังระหว่างการเปลี่ยนแปลง** | ทุก phase: suite เดิมเขียวครบ + rollback drill ผ่าน + live smoke บน venue ทดสอบผ่าน |

### 1.2 สิ่งที่อยู่นอกขอบเขต (explicit non-goals)

- ไม่ทำ auto-failover ระหว่าง provider ในเวอร์ชันนี้ (timeout ไม่ได้แปลว่า provider ไม่ได้รับคำขอ)
- ไม่ทำ failover/retry อัตโนมัติ และไม่ย้าย UI/ledger เงินของ domain (dedup ข้าม domain เป็นแบบ global-by-HMAC ตาม D3; ระยะเก็บรอ D7)
- ไม่ย้าย owner evidence queue / payment claim / refund ledger ของ Sports Hub ไปแกนกลาง — UI และกติกาเงินเป็นของ domain
- ไม่แตะ `strictRouteGuard`, middleware auth กลาง, หรือลำดับ middleware ที่มีอยู่
- ไม่เปลี่ยนชื่อ RPC/ตารางที่แอปที่ deploy อยู่เรียก (ใช้ shim เท่านั้น)

---

## 2. สถานะปัจจุบัน (Asset inventory)

### 2.1 สถานะการ deploy จริง (ยืนยันกับ `Match_Sport_PLAN.md` ที่ผู้ใช้แก้ล่าสุด)

| รายการ | ค่า |
|---|---|
| Global scope | `whitelist` |
| Venue allowlisted | 1 แห่ง (venue ทดสอบ) + `verify_monthly_quota = 1` + bearer `platform` |
| Provider | `slipok` enabled (endpoint `https://api.slipok.com/api/line/apikey/77918`, key ref `SLIPOK`) |
| Worker | เปิด (`SLIP_VERIFICATION_WORKER_ENABLED=true`, interval 15s) |
| Live verification | ผ่าน 1 ใบ (2026-10-07): claim → private download → SlipOK `verified` → apply → booking auto-confirm |
| Migrations | `20261010100000`–`20261015100000` apply บนฐานจริงแล้ว |
| Baseline tests | SQL smoke 395 PASS / 0 FAIL · flutter book_court 227 tests · node 55 tests · `dart analyze` clean |
| Staging | **ไม่พบ**: ไม่มี `supabase/config.toml`, ไม่มี docker ในเครื่องนี้ (มีแต่ `supabase` CLI) → local Supabase stack รันไม่ได้ (ดู D9) |

> ✅ **แก้ความไม่สอดคล้องของวันที่ (เดิมเป็น Q1):** ระบบวันที่ของเครื่อง = 2026-10-07 — วันที่ `2026-10-15` ในหมายเหตุ runbook ของ `Match_Sport_PLAN.md` เป็น **ความผิดพลาดของผู้เขียนรอบก่อน** (ไม่ใช่เหตุการณ์จริง) ได้แก้เป็น 2026-10-07 แล้วใน P0.6

### 2.2 ชั้นของระบบและระดับการผูกกับ Sports Hub

| ชั้น | ไฟล์/ตาราง | reuse ได้ | จุดที่ผูกกับ Sports |
|---|---|---|---|
| Provider registry | `slip_verification_providers`, `admin_upsert_slip_verification_provider`, `admin_list_slip_verification_providers` | ~95% | prefix `sports` ในชื่อ RPC, UI อยู่ใน `AdminCourtOwnerReviewPanel`, ไม่มี field บอกว่า provider รองรับระบบใด และ **enable provider ที่ไม่มี adapter ได้ (R5)** |
| Global scope/kill switch | `sports_venue_slip_verification_settings` (singleton, `disabled`/`whitelist`/`all`) | concept generic | ชื่อตาราง + join ผ่าน `sports_venues.verify_allowlisted` |
| Outbox + worker RPC | `slip_verification_usage`, `worker_claim_sports_venue_slip_verification`, `worker_apply_sports_venue_slip_verification` | ผูกมาก | FK `venue_id`/`booking_group_id`/`evidence_id`; gate อ่านสถานะ group/evidence; apply มี side-effect กับ booking |
| Dedup ledger | `slip_verification_transactions` (UNIQUE fingerprint) | กลไก generic | FK `booking_group_id`/`evidence_id` |
| Node worker | `websocket-server/services/slip-verification-worker.js` | ~80% | ชื่อตาราง/RPC ฮาร์ดโค้ด, bucket เป็น const, adapter `slipok` เท่านั้น |
| Upload/read gateway | `sports_venue_evidence_upload_intents`, `create/consume_sports_venue_evidence_upload_grant`, `mint_sports_venue_evidence_read_token`, `get_sports_venue_evidence_object_for_token`, `routes/sports-evidence.js`, `jobs/evidence-orphan-sweeper.js` | กลไก generic | grant ผูก `booking_group_id`, path `groups/<groupId>/…`, auth rule ฝังใน mint RPC, bucket const |
| Client | `BookCourtRepository` (`createEvidenceUploadGrant`, `uploadEvidenceViaGateway`, `mintEvidenceReadToken`, `admin*SlipProvider*`, `admin*VenueVerifyPolicy`), models `SlipVerificationProvider`/`AdminVenueVerifyPolicy` | ส่วน gateway generic | อยู่ใน repo เฉพาะ feature |
| Domain UI | `CourtOwnerEvidenceQueue`, `BookingGroupSheet`, `VenueEvidencePolicyDialog` | ไม่ reuse | ทั้งหมด — คงไว้ที่ domain |

### 2.3 RPC ที่มีอยู่ (ฐานอ้างอิงสำหรับ shim/compat)

```
worker_claim_sports_venue_slip_verification(VARCHAR, VARCHAR)
worker_apply_sports_venue_slip_verification(VARCHAR, VARCHAR, VARCHAR, NUMERIC, VARCHAR, VARCHAR, JSONB)
admin_upsert_slip_verification_provider(...)
admin_list_slip_verification_providers(UUID)
admin_get_sports_venue_verify_global_policy(UUID)
admin_set_sports_venue_verify_global_scope(UUID, VARCHAR)
admin_set_sports_venue_verify_controls(UUID, UUID, BOOLEAN, VARCHAR, INT, INT, BOOLEAN, BOOLEAN)
admin_set_sports_venue_verify_policy(UUID, UUID, VARCHAR, VARCHAR, INT, INT, BOOLEAN, BOOLEAN)
admin_list_sports_venue_verify_policies(UUID)
sports_venue_verify_scope_allows(UUID)
sports_venue_auto_verify_allowed(UUID)
create_sports_venue_evidence_upload_grant(UUID, UUID, VARCHAR, VARCHAR)
consume_sports_venue_evidence_upload_grant(VARCHAR)
mint_sports_venue_evidence_read_token(UUID, VARCHAR, INT)
get_sports_venue_evidence_object_for_token(VARCHAR)
cleanup_sports_venue_evidence_orphans()
```

### 2.4 ช่องโหว่/ความเสี่ยงที่พบจากการตรวจโค้ด (ต้องแก้ก่อนขยาย)

> เลข R เรียงตามลำดับที่พบ ไม่ใช่ลำดับความสำคัญ (ดูคอลัมน์ความเร่งด่วน); R7 (ความหมายของ cost/โควตา) ถูกรวมเข้า R11

| # | ปัญหา | หลักฐาน | ผลกระทบ | ความเร่งด่วน | แก้ที่ |
|---|---|---|---|---|---|
| **R9** | **ไม่ตรวจบัญชีผู้รับและเวลาโอน** — verdict `verified` ตัดสินจาก (ก) provider ตอบ success และ (ข) `amount` เท่ายอดรวม เท่านั้น; ไม่มีการเทียบผู้รับกับ `payment_destination_snapshot` ของ group และไม่เทียบเวลาโอนกับเวลาสร้าง group | `_callSlipOk` อ่านแค่ `data.amount/transRef/transTimestamp`; `worker_apply_...` เงื่อนไข verified = fingerprint + amount เท่านั้น (บรรทัด ~389–396); grep `receiver`/`payment_destination` ในไฟล์ worker/apply = ไม่พบ | **สลิปจริงที่โอนให้ใครก็ได้ในยอดเท่ากัน (หรือสลิปเก่าที่ยังไม่เคยถูกใช้) ผ่านและยืนยัน booking อัตโนมัติได้** — ช่องทุจริตตรงตัว | **สูงสุด** | P2.a |
| R1 | **เก็บ raw `transRef` ใน `provider_ref`** — adapter ส่ง `providerRef` (= `data.transRef`) กลับ แล้ว `worker_apply_...` เขียนลง `sports_venue_booking_evidence.provider_ref` | `_callSlipOk`, branch `verified` ของ apply | DB dump รั่วเลขธุรกรรม | สูง | P2.b |
| R2 | **fingerprint เป็นข้อความดิบ ไม่ใช่ HMAC** — `transRef\|transTimestamp\|amount` เก็บใน `slip_verification_transactions.fingerprint` ทั้งที่ comment ของ schema ระบุว่าเป็น HMAC/normalized และ "raw trans-ref is never stored"; ไม่มี namespace/key version | `_callSlipOk`, comment ใน `20261010100000` | ละเมิดนโยบายตัวเอง + dedup ชนข้าม provider/ธนาคารได้ + ขยายข้าม domain ไม่ปลอดภัย | สูง | P2.b |
| R4 | **provider call ซ้ำหลัง apply ล้ม** — `_processAttempt` log error แล้วจบ; attempt ยัง `result IS NULL` และ claimable เมื่อ lease 2 นาทีหมด → ยิง provider ใหม่ = เสียเงินซ้ำ และ fingerprint ซ้ำอาจ mark duplicate ทำให้สลิปจริงถูกปฏิเสธ | `_processAttempt`, `worker_claim` | เสียค่าใช้จ่ายซ้ำ + false negative ที่ผู้ใช้เห็น | สูง | P2.c |
| **R10** | **ผล verified ที่ "stale" ถูกทิ้งเงียบ** — ถ้า apply มาถึงหลัง evidence ไม่ current/ไม่ใช่ `verifying` (เช่น housekeeping forfeit ไปแล้ว หรือผู้ใช้อัปโหลดใหม่) RPC ตั้ง usage = `failed` แล้วคืน `evidence_stale` **โดยไม่บันทึก dedup และไม่เก็บผล provider** | `worker_apply_...` บรรทัด 371–377 | ผู้ใช้โอนเงินจริงแต่ booking ถูกปล่อย + ไม่มีร่องรอยว่า provider ยืนยันแล้ว + สลิปนั้นยังใช้ซ้ำได้ | สูง | P2.d |
| R3 | **queue fairness** — worker poll `result IS NULL` (รวมแถวที่ worker อื่นเพิ่ง claim) แล้วเรียก claim ทีละแถวได้ `NULL` กลับ | `_tick` | เปลือง round-trip/ไม่สเกลเมื่อมีหลาย worker | กลาง | P2.e |
| R5 | **provider ที่ไม่มี adapter ถูกเลือกได้** — UI/RPC เพิ่มและ enable provider ได้ แต่ `_callProvider` รู้จักแค่ `slipok`; claim เลือกด้วย `ORDER BY priority` → provider ใหม่ priority สูงกว่าจะถูกเลือกแล้วได้ `unknown_adapter` → ตก owner review เงียบ ๆ | `_callProvider`, `admin_upsert_slip_verification_provider`, `worker_claim` | Admin เข้าใจผิดว่าระบบตรวจอัตโนมัติทำงานอยู่ | สูง — **ผิดได้ตั้งแต่วันนี้ผ่าน UI ที่มีอยู่** | P0.2 |
| R6 | **SSRF guard เป็นการตรวจข้อความ** — protocol + regex hostname; ไม่ตรวจ DNS/IP ปลายทาง ไม่มี host allowlist | `_isAllowedEndpoint` | เมื่อเพิ่ม provider ความเสี่ยง egress เพิ่ม | กลาง | P0.3 |
| R8 | **ไม่มี audit การเปลี่ยน config** — เปลี่ยน scope/provider/quota ไม่รู้ใครทำอะไร | `admin_set_*` | ตรวจย้อนหลังไม่ได้เมื่อค่าใช้จ่ายผิดปกติ | กลาง | P0.4 |
| **R11** | **ไม่มีเพดานระดับ provider/แพลตฟอร์ม และไม่มี circuit breaker** — โควตาปัจจุบันนับ **ต่อ venue**; แต่ package ของ SlipOK เป็นโควตาระดับ account (บันทึกในแผนเดิมว่า quota 100); ถ้า provider ล่มยาว ทุกใบรอ timeout 20 วินาทีเต็มก่อนตก owner review | `20261013100000` (quota block), `PROVIDER_TIMEOUT_MS` | ขยาย whitelist หลาย venue แล้วเกินโควตา account พร้อมกัน/worker ติดคิวเมื่อ provider ล่ม; `cost_estimate` เป็นประมาณการ ไม่ใช่ใบแจ้งหนี้จริง | กลาง-สูง (ก่อนขยาย whitelist) | P2.f |
| **R12** | **ไม่มี worker heartbeat** — worker ตาย/ไม่ start แล้วไม่มีสัญญาณ admin เห็นเพียงว่าใบตก owner review หลัง timeout | `server.js` start logic | ความล้มเหลวเงียบ ๆ ยาวนานได้ | กลาง | P1.d |
| **R13** | **PDPA/ข้ามพรมแดน** — ภาพสลิปมีชื่อ/เลขบัญชีถูกส่งไป provider ภายนอก; ยังไม่มีเงื่อนไขการเพิ่ม provider ที่บังคับตรวจสัญญาประมวลผลข้อมูล/ที่ตั้งข้อมูล | — | เพิ่ม provider ผ่าน UI ได้โดยไม่มีด่านกฎหมาย | กลาง (ก่อน provider ที่สอง) | P4 onboarding checklist, D7 |

---

## 3. หลักการออกแบบ (Design invariants)

ใช้เป็นเกณฑ์ตัดสินทุกการตัดสินใจในแผนนี้:

1. **Additive only** — ห้ามลบ/เปลี่ยนชนิด/เปลี่ยนความหมายของคอลัมน์ที่ระบบจริงใช้อยู่; เพิ่มคอลัมน์ nullable ได้ (ข้อยกเว้นเดียว: ข้อ 13)
2. **Signature stability** — RPC ที่แอป deploy อยู่เรียกต้องคงชื่อและ signature; ของใหม่เป็น shim ที่ delegate
3. **Fail-closed** — provider ล่ม/timeout/ไม่รู้จัก/ข้อมูลผู้รับไม่ครบ → รอ owner review เสมอ ไม่ auto-confirm และ**ไม่ auto-reject** (owner ตัดสินเอง)
4. **Single writer per attempt** — หนึ่ง attempt มี worker เดียวประมวลผล ณ เวลาหนึ่ง และ provider call ต่อ attempt มีได้ **สูงสุดหนึ่งครั้ง** (ต้องมีสถานะแยก "เรียกแล้วแต่ยังไม่ apply")
5. **No dynamic dispatch จากข้อมูล** — เลือก domain adapter ด้วย `CASE`/whitelist ที่ compile ไว้ใน migration ไม่ `EXECUTE` ชื่อฟังก์ชันจากค่าที่ admin แก้ได้
6. **Secrets อยู่นอก DB** — registry เก็บแค่ ref name; ค่าจริง (API key, HMAC key) อยู่ใน env/secret store ของ Node เท่านั้น
7. **Storage ปิด** — bucket private ไม่มี policy ให้ client เขียนตรง; ทุกไฟล์ผ่าน gateway ที่ตรวจ magic bytes + ลบ metadata
8. **One domain at a time** — เปิดใช้ทีละ domain/scope พร้อม quota และ kill switch ของตัวเอง
9. **Behavioral identity ก่อน generalization** — ทุก refactor พิสูจน์ด้วย test suite เดิม + payload diff; ทุกงานที่ *ตั้งใจ* เปลี่ยนพฤติกรรมต้องระบุ test ที่เปลี่ยนและเหตุผลใน PR
10. **ทุก phase ต้องมี rollback ที่ไม่แตะข้อมูลธุรกิจ** และมี rollback script คู่ migration (`supabase/rollbacks/<ชื่อ migration>.sql` — ไม่รันอัตโนมัติ)
11. **Ownership ของ attempt ต้องชัดเจน** — แต่ละ attempt มีเจ้าของเส้นทางเดียว (`path` ตั้งตอนสร้าง) worker สองตัวอยู่ร่วมได้เพราะเห็นคนละชุด ไม่ใช่เพราะ "ไม่รันพร้อมกัน"
12. **Switch สลับเส้นทางต้องเปลี่ยนได้โดยไม่ deploy** — cutover flag อยู่ใน DB (singleton + audit); env เป็น override ฉุกเฉินเท่านั้น
13. **ข้อยกเว้นของข้อ 1 (ประกาศชัด):** P2.b เขียนทับ `fingerprint`/`provider_ref` เดิมเป็นค่า HMAC เพราะเป้าหมายคือ *ลบ raw ออกจาก DB* — ทำได้เพียงครั้งเดียว ต้องมี PITR snapshot ก่อนเริ่ม, worker หยุด, dry-run ก่อน และมี script ที่ idempotent
14. **Observe ก่อน enforce** — กติกาใหม่ที่อาจปฏิเสธสลิปจริง (P2.a) ต้องรันโหมดสังเกตการณ์ที่บันทึกผลโดยไม่เปลี่ยน verdict ก่อน แล้วจึงเปิดบังคับ

---

## 4. สถาปัตยกรรมเป้าหมาย

### 4.1 ภาพรวม

```
                       ┌──────────────────────────────┐
                       │   Verification Core (กลาง)   │
                       │  outbox · lease · retry      │
                       │  provider adapters · quota   │
                       │  cost snapshot · audit       │
                       └───────────┬──────────────────┘
                                   │ CASE dispatch (compile-time)
        ┌──────────────────────────┼───────────────────────────┐
        │                          │                           │
┌───────▼────────┐        ┌────────▼─────────┐       ┌─────────▼────────┐
│ sports_booking │        │  <domain ใหม่>    │       │  <domain ใหม่>    │
│ gate/apply/    │        │  gate/apply/      │       │  gate/apply/      │
│ upload-auth    │        │  upload-auth      │       │  upload-auth      │
└────────────────┘        └───────────────────┘       └───────────────────┘
   ▲ ยังใช้ RPC ชื่อเดิม (shim)        ▲ domain ใหม่เรียก core ตรง
```

### 4.2 ตารางใหม่ (เพิ่ม ไม่แก้ของเดิม)

> ตารางที่สร้างตาม phase: `verification_admin_audit` (P0.4), `verification_worker_heartbeats` (P1.d), `verification_platform_budget` + คอลัมน์บน provider/usage (P2), `verification_domain_providers` (P4), `verification_requests`/`verification_scopes` (P5, หลัง D1), `verification_core_settings` + `path` (P6, หลัง D2)

```sql
-- outbox กลาง (ของใหม่; ของเดิม slip_verification_usage คงไว้ระหว่าง migration)
verification_requests (
  id UUID PK,
  attempt_id VARCHAR(80) UNIQUE NOT NULL,
  domain VARCHAR(40) NOT NULL,              -- 'sports_booking' | ...
  scope_type VARCHAR(24) NOT NULL,          -- 'venue' | 'org' | ...
  scope_id UUID,                            -- null = platform scope
  subject_type VARCHAR(40) NOT NULL,        -- 'booking_group' | ...
  subject_id UUID NOT NULL,
  storage_bucket VARCHAR(80) NOT NULL,
  storage_path VARCHAR(500) NOT NULL,
  mime VARCHAR(80),
  expected_amount NUMERIC(12,2),
  currency VARCHAR(3) NOT NULL DEFAULT 'THB',
  provider_code VARCHAR(40),
  cost_estimate NUMERIC(10,2) NOT NULL DEFAULT 0,
  cost_actual NUMERIC(10,2),
  cost_bearer VARCHAR(20),
  state VARCHAR(20) NOT NULL DEFAULT 'queued',  -- queued|call_started|response_received|applied|settled|skipped
  result VARCHAR(20),                       -- verified|failed|unavailable|timeout|rejected
  fingerprint VARCHAR(128),
  provider_ref_hash VARCHAR(128),           -- HMAC ไม่ใช่ค่าดิบ (R1)
  provider_meta JSONB NOT NULL DEFAULT '{}'::jsonb,  -- ห้ามใส่ raw trans-ref
  claimed_at TIMESTAMPTZ, claimed_by VARCHAR(80),
  call_started_at TIMESTAMPTZ, response_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ
)

-- policy ต่อ scope (ของใหม่; sports_venues.verify_* คงไว้เป็น shadow)
verification_scopes (
  domain VARCHAR(40) NOT NULL,
  scope_type VARCHAR(24) NOT NULL,
  scope_id UUID NOT NULL,
  is_allowlisted BOOLEAN NOT NULL DEFAULT false,
  monthly_quota INT, verify_timeout_minutes INT, cost_bearer VARCHAR(20),
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (domain, scope_type, scope_id)
)

-- routing: domain → provider (P4)
verification_domain_providers (
  domain VARCHAR(40) NOT NULL,
  provider_code VARCHAR(40) NOT NULL REFERENCES slip_verification_providers(code),
  is_primary BOOLEAN NOT NULL DEFAULT false,
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (domain, provider_code)
)

-- audit ของการเปลี่ยน config (R8) — สร้างตั้งแต่ P0.4 (ไม่ต้องรอแกนกลาง)
verification_admin_audit (
  id UUID PK, admin_id UUID, action VARCHAR(60),
  target_type VARCHAR(40), target_id VARCHAR(120),
  before JSONB, after JSONB, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
)

-- heartbeat ของ worker (P1.d, R12) — สร้างตั้งแต่ P1
verification_worker_heartbeats (
  worker_id VARCHAR(80) PRIMARY KEY, adapters TEXT[], version VARCHAR(40),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
)

-- เพดานงบแพลตฟอร์ม (P2.f, R11) — singleton
verification_platform_budget (
  singleton_key SMALLINT PRIMARY KEY CHECK (singleton_key = 1),
  monthly_cap_amount NUMERIC(12,2), warn_ratio NUMERIC(3,2) NOT NULL DEFAULT 0.80,
  updated_by UUID, updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
)
```

คอลัมน์เพิ่มบนตารางเดิม (nullable ทั้งหมด):

```sql
ALTER TABLE public.slip_verification_providers
  ADD COLUMN IF NOT EXISTS adapter_code VARCHAR(40),      -- 'slipok' | ...
  ADD COLUMN IF NOT EXISTS supported_domains TEXT[],      -- NULL = ยังไม่ผูก
  ADD COLUMN IF NOT EXISTS monthly_cap INT,               -- cap ต่อ provider (P2.f); NULL = ไม่จำกัด
  ADD COLUMN IF NOT EXISTS receiver_check_mode VARCHAR(10) NOT NULL DEFAULT 'off'
    CHECK (receiver_check_mode IN ('off', 'observe', 'enforce'));   -- P2.a

-- ownership ของ attempt ระหว่าง dual-write (P6.a) — NULL = แถวเดิม (legacy)
ALTER TABLE public.slip_verification_usage
  ADD COLUMN IF NOT EXISTS path VARCHAR(10)
    CHECK (path IN ('legacy', 'generic'));

-- switch สลับเส้นทาง cutover (P6.b) — อ่านโดย worker ทุก tick, แก้ผ่าน RPC + audit
CREATE TABLE IF NOT EXISTS public.verification_core_settings (
  singleton_key SMALLINT PRIMARY KEY CHECK (singleton_key = 1),
  sports_on_core BOOLEAN NOT NULL DEFAULT false,
  updated_by UUID REFERENCES public.users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

> **adapter readiness** ไม่ใช่คอลัมน์ที่ admin แก้ — คำนวณจากฟังก์ชัน `verification_adapter_known(adapter_code)` ซึ่งเป็น `CASE` ที่เปลี่ยนได้ด้วย migration เท่านั้น (P0.2) แยกจาก `is_enabled` ที่ admin แก้; เป็นฐานของ gate ทั้งใน UI และ claim (ปิด R5)

### 4.3 RPC กลาง (ของใหม่)

| RPC | หน้าที่ | หมายเหตุ |
|---|---|---|
| `verification_claim_next(p_worker_id, p_limit)` | เลือก attempt ถัดไปแบบ atomic (`FOR UPDATE SKIP LOCKED`) เฉพาะ `state IN ('queued','call_started')` ที่ lease หมดอายุ | แก้ R3 |
| `verification_claim(p_attempt_id, p_worker_id)` | lease + gate ของ domain + quota reservation ใต้ lock ของ scope | เรียก `verification_domain_gate()` |
| `verification_mark_call_started(p_attempt_id)` | บันทึกก่อนยิง provider | ทำให้ retry ไม่ยิงซ้ำเมื่อ apply ล้ม (R4) |
| `verification_apply(p_attempt_id, p_result, p_amount, p_fingerprint_hmac, p_provider_meta)` | เขียนผล + dedup + cost + เรียก `verification_domain_applied()` | idempotent |
| `verification_domain_gate(p_domain, p_request_id)` | `CASE p_domain WHEN 'sports_booking' THEN public.sports_booking_verification_gate(...)` | compile-time dispatch |
| `verification_domain_applied(p_domain, p_request_id, p_result, p_amount, p_meta)` | `CASE` → `sports_booking_verification_applied(...)` | side-effect ของ domain |
| `admin_list_verification_domains(p_admin_id)` | รายการ domain + provider ที่รองรับ + readiness | สำหรับ UI (P4) |
| `admin_set_verification_domain_provider(p_admin_id, p_domain, p_provider_code, p_is_enabled)` | ตั้ง routing + audit | บล็อกถ้า adapter ไม่รู้จัก/ไม่มี heartbeat (P4.3) |

### 4.4 Interface ของ domain adapter (สัญญาที่ต้อง implement)

Domain ใหม่ต้องมี 4 ฟังก์ชัน (ชื่อตาม `verification_domain_*` namespace) + 1 adapter ฝั่ง Node:

```sql
-- 1) ตรวจว่าคำขอนี้ยังควรตรวจไหม + คืนบริบทที่ต้องใช้
sports_booking_verification_gate(p_request_id UUID) RETURNS JSONB
--   { action: 'verify'|'skip', reason, storage_bucket, storage_path, mime,
--     expected_amount, currency, scope_locked: true }

-- 2) รับผลและปรับ state ของ domain
sports_booking_verification_applied(
  p_request_id UUID, p_result VARCHAR, p_amount NUMERIC, p_meta JSONB) RETURNS VOID

-- 3) สิทธิ์อัปโหลดหลักฐาน
verification_upload_authorized(
  p_domain VARCHAR, p_subject_id UUID, p_user_id UUID, p_purpose VARCHAR) RETURNS BOOLEAN

-- 4) สิทธิ์อ่านหลักฐาน (ใช้กับ read token)
verification_read_authorized(
  p_domain VARCHAR, p_storage_path VARCHAR, p_user_id UUID) RETURNS BOOLEAN
```

```js
// websocket-server/services/verification/adapters/<code>.js
module.exports = {
  code: 'slipok',
  supports: { domains: ['sports_booking'], mime: ['image/jpeg', 'image/png'] },
  async verify({ endpointUrl, apiKey, image, mime, expectedAmount, currency, timeoutMs }) {
    // คืน { result, amount, providerRef, meta } โดย providerRef จะถูก hash ก่อนเก็บ
  },
};
```

---

## 5. ลำดับ Phase (เรียงตามความสำคัญ + ความง่ายในการพิสูจน์ว่าไม่พัง)

| Phase | ชื่อ | ประเภท | แตะ schema? | เปลี่ยนพฤติกรรม Sports? | ความเสี่ยง | ย้อนกลับ |
|---|---|---|---|---|---|---|
| **P0** | ปิดช่องโหว่ไม่เปลี่ยนพฤติกรรม | security/ops | เพิ่มคอลัมน์/ตาราง audit/ฟังก์ชัน | ไม่ (happy path เหมือนเดิม) | ต่ำ-กลาง | revert + rollback script |
| **P1** | เครื่องมือพิสูจน์ + observability | test/infra | view + heartbeat table | ไม่ | ต่ำ | drop view/table |
| **P2** | แก้ทุจริต/privacy/ความซ้ำซ้อน (6 ข้อย่อย แยก PR/migration) | **behavior change** | ใช่ (additive + P2.b in-place) | **ใช่ — ตั้งใจ** | **กลาง-สูง** (มี P1 คุ้มกัน + observe→enforce) | รายข้อย่อย; P2.b = กู้จาก snapshot |
| **P3** | แยกโค้ด (pure refactor) | refactor | ไม่ | ไม่ (ต้องเหมือน 100%) | กลาง (ตรวจจับง่าย) | revert commit |
| **P4** | สลับ provider รายระบบผ่าน UI (Sports ระบบเดียว) | feature | เพิ่มตาราง routing | ไม่ (Sports = slipok เดิม) | ต่ำ-กลาง | ปิด routing flag |
| — | **D1 decision gate** | decision | — | — | — | — |
| **P5** | แกนกลาง additive + shadow | foundation | เพิ่มตารางใหม่ | ไม่ (ยังไม่ย้าย) | กลาง | drop ตารางใหม่ |
| — | **D2 decision gate** | decision | — | — | — | — |
| **P6** | ย้าย Sports ไปแกนกลาง (DB flag) | **cutover** | shim RPC + `path` | เปลี่ยนเส้นทางภายใน | **สูง** (มี drill บังคับ) | flip DB flag + drain-only |
| **P7** | domain ที่สอง | feature | policy ของ domain นั้น | ไม่ | กลาง | ปิด scope ของ domain |
| **P8** | เก็บกวาดของเก่า | cleanup | ลบของเลิกใช้ | คงเดิม | กลาง | forward-fix |

### 5.1 ผังการพึ่งพา (dependencies)

```
P0 ──► P1 ──► P2 ──► P3 ──► P4 ══► [D1] ══► P5 ══► [D2] ══► P6 ──► P7 ──► P8
          └─ (P1 ต้องเสร็จก่อนเริ่มข้อย่อยใด ๆ ของ P2)
P0.2 (adapter readiness) บล็อก P4 | P2.a/P2.b/P2.c บล็อก "เปิด whitelist เพิ่ม" | P6 drill ต้องมี P1 (fake provider) + P2.c
```

### 5.2 ทำไม P2 ถึงอยู่ก่อน refactor และก่อนแกนกลาง

- งาน P2 แก้ **ความถูกต้องของการยืนยันเงิน** บนเส้นทางที่ใช้งานจริงอยู่ — เลื่อนไปไม่ได้เพราะแกนกลางจะ *สืบทอดช่องโหว่* ไปด้วย
- เมื่อ P2 นิ่ง semantics ของ claim/apply (จะเป็นสิ่งที่ P3 refactor ห่อ และ P5 shadow เทียบ) จึงชัดและไม่เปลี่ยนซ้ำ

### 5.3 Decision gates

| Gate | อยู่ก่อน | ต้องมีอะไรจึงผ่าน | ถ้าไม่ผ่าน |
|---|---|---|---|
| **D1** | P5 | ระบุ **domain ที่สองจริง** พร้อม: subject type, scope owner (ใครจ่าย/จำกัดโควตา), ความหมายของยอดเงิน/สกุลเงิน, ใครเป็น reviewer, ผู้รับเงิน (บัญชี) จะเทียบกับอะไร, retention ที่ legal อนุมัติ | **หยุดที่ P4** — ถือว่าแผนสำเร็จ; ไม่สร้างแกนกลาง |
| **D2** | P6 | P5 shadow parity = 0 mismatch + มี domain ที่สองใกล้ launch จริง (กำหนดวันแล้ว) | คง Sports บน legacy path ต่อไป (strangler ค้าง) และให้ domain ที่สองใช้แกนกลางตรง — ยอมรับสองเส้นทางชั่วคราวโดยมีเจ้าของรับผิดชอบ |

---

### Phase 0 — ปิดช่องโหว่ที่ไม่เปลี่ยนพฤติกรรม (ทำก่อนทุกอย่าง)

**เป้าหมาย:** ลดความเสี่ยงทันทีด้วยงานต้นทุนต่ำที่ **happy path ไม่เปลี่ยน** (สลิปที่ผ่านวันนี้ต้องผ่านเหมือนเดิม)

| งาน | รายละเอียด | ไฟล์ |
|---|---|---|
| P0.1 | **Rotate SlipOK key** — key เคยปรากฏในแชท/ภาพหน้าจอ: ออก key ใหม่ที่ provider, **เพิกถอน key เดิม**, ตั้งใน `.env`, restart Node, ยืนยัน `GET /quota` = 200 และ key เดิม = 401/403 | `websocket-server/.env` (ops เท่านั้น ไม่ commit) |
| P0.2 | **Adapter readiness (ปิด R5)** — เพิ่ม `adapter_code`, `supported_domains` บน `slip_verification_providers` + ฟังก์ชัน `verification_adapter_known(code)` (CASE list ที่แก้ได้ด้วย migration เท่านั้น เริ่มที่ `'slipok'`); backfill แถว `slipok`; claim/`sports_venue_auto_verify_allowed`/นับ provider ทุกจุด **กรองเฉพาะ provider ที่ adapter รู้จัก**; `admin_upsert_slip_verification_provider` ปฏิเสธการ **enable** provider ที่ adapter ไม่รู้จัก (`ADAPTER_NOT_AVAILABLE`) แต่ยังบันทึกเป็นร่าง (disabled) ได้ | migration + `admin_court_owner_review_page.dart` (แสดงเหตุผล) |
| P0.3 | **SSRF host allowlist (ปิด R6)** — env `VERIFICATION_ALLOWED_HOSTS` (comma-separated, ค่าเริ่มต้น `api.slipok.com`); ตรวจ hostname ∈ allowlist, ปฏิเสธ IP literal/userinfo/พอร์ตที่ไม่ใช่ 443, `dns.lookup` ก่อนเรียกและปฏิเสธถ้าได้ address private/loopback/link-local (best-effort — ระบุข้อจำกัด TOCTOU ในโค้ด), `redirect:'error'` คงเดิม; ถ้า env ไม่ตั้ง → ใช้กติกาเดิม + log เตือนชัดเจน | `services/slip-verification-worker.js` |
| P0.4 | **Audit การเปลี่ยน config (ปิด R8)** — ตาราง `verification_admin_audit` (RLS + REVOKE) + เขียนใน `admin_set_sports_venue_verify_*`, `admin_set_sports_venue_verify_global_scope`, `admin_upsert_slip_verification_provider` (before/after; ไม่เก็บค่า secret — เก็บแค่ ref name) + RPC อ่านสำหรับ admin | migration (redef ด้วย `CREATE OR REPLACE` คง signature) |
| P0.5 | **Baseline + environment readiness** — บันทึกผล suite ปัจจุบันใน PR; **ตัดสิน D9 (staging)** ก่อนเข้า P2: ไม่มี docker/`config.toml` → ต้องมี Supabase project ที่สอง หรือยอมรับ "reduced-drill mode" (ดู §6.2) | — |
| P0.6 | **แก้เอกสาร** — แก้วันที่ผิดใน `Match_Sport_PLAN.md` runbook (2026-10-15 → 2026-10-07), เพิ่มหัวข้อ "Shared verification core" ใน `AGENTS.md` (คำสั่ง verify, env ที่เพิ่ม, ลำดับ deploy Node-ก่อน-migration สำหรับ adapter ใหม่) | docs |

**Deploy order rule (สำคัญ):** ของที่ทำให้ DB "รู้จัก adapter ใหม่" ต้อง deploy **Node (มี adapter) ก่อน** แล้วค่อย apply migration ที่เพิ่ม code เข้า `verification_adapter_known` — ถ้ากลับด้านจะเกิดช่วงที่ DB เลือก provider ที่ Node ยังเรียกไม่ได้

**Gate P0 (ต้องผ่านครบ):**
1. `database/sports_hub_rpc_smoke_test.sql` → PASS ≥ 395, FAIL 0, ERROR 0 + assertion ใหม่: เพิ่ม provider ปลอม priority 1 (ไม่มี adapter) → claim ยังเลือก `slipok`; enable provider ไม่มี adapter → `ADAPTER_NOT_AVAILABLE`; audit row ถูกสร้างและไม่มี secret; non-admin → `NOT_ADMIN`
2. `npm test` → ≥ 55 pass + test ใหม่: host นอก allowlist/IP literal/พอร์ตแปลก/DNS→private → `endpoint_blocked`; host ใน allowlist ผ่านเหมือนเดิม
3. `dart analyze lib test` ไม่มี error ในไฟล์ที่แตะ; `flutter test test/features/sport_club/book_court` → 227 ผ่านเท่าเดิม
4. **Live smoke 1 ใบ** (venue ทดสอบ): `verified` → auto-confirm เหมือนเดิม; key เก่าใช้ไม่ได้
5. **Rollback drill:** ปิด provider ใน registry → claim คืน `no_provider` → ใบใหม่ตก owner review

**Rollback P0:** revert Node commit + รัน rollback script ของ migration (ฟังก์ชันกลับนิยามเดิม; ตาราง audit ปล่อยทิ้งได้); key ใหม่ไม่ต้อง rollback

---

### Phase 1 — เครื่องมือพิสูจน์ + observability (ก่อนแตะพฤติกรรมใด ๆ)

**เป้าหมาย:** ทำให้ "พังหรือไม่พัง" ตอบได้ด้วยคำสั่ง และ **ล็อกพฤติกรรมปัจจุบันไว้เป็นหลักฐาน** ก่อนที่ P2 จะเปลี่ยนมัน

| งาน | รายละเอียด |
|---|---|
| P1.a | **Characterization tests ของพฤติกรรมปัจจุบัน** — ตารางผล claim ครบทุกกิ่ง (stale / scope_disabled / no_provider / quota_exceeded / verify) และตารางผล apply ครบทุกกรณี (verified / amount ไม่ตรง / failed / unavailable / timeout / fingerprint ซ้ำ / stale / apply ซ้ำ) ใน SQL smoke — **รวมพฤติกรรมที่เป็นช่องโหว่ (R9: โอนผิดบัญชีแต่ยอดตรง → verified; R10: stale → ทิ้งผล)** ติดป้าย `-- CURRENT (known gap R9)` เพื่อให้ P2 เปลี่ยนด้วยเจตนาและอัปเดต test ที่ระบุชื่อเท่านั้น |
| P1.b | **Fake provider server + adapter contract tests** — http server จำลอง: 200 verified, 200 amount ผิด, ไม่มี receiver/เวลา, 4xx, 5xx, timeout, JSON เพี้ยน, redirect, ช้ากว่า timeout, ตอบหลังถูก abort; host ของ fake อนุญาตเฉพาะ `NODE_ENV=test` ผ่าน allowlist override |
| P1.c | **Concurrency test จริง** — สคริปต์ `database/verification_concurrency_test.sh` ใช้ **สอง psql session** (smoke script เป็น single session จึงพิสูจน์ race ไม่ได้): claim พร้อมกัน → ได้ verify หนึ่ง/อีกอัน NULL; quota race (โควตา 1, สอง claim) → `quota_exceeded` หนึ่ง; apply พร้อมกันบน attempt เดียว → `already_done` หนึ่ง |
| P1.d | **Observability** — view `verification_metrics_daily` (provider, scope, ผลตรวจ, skip reason, queue age p50/p95, cost_estimate) + ตาราง `verification_worker_heartbeats` (worker_id, adapters ที่โหลด, version, last_seen) เขียนทุก tick + RPC admin อ่านสถานะ worker + **ตัวตรวจคิวค้าง** (queue age > เกณฑ์ → log ระดับ error และแจ้ง admin ผ่านช่องทางแจ้งเตือนที่มีอยู่ — ต้องยืนยันกลไกกับระบบ notification ก่อน implement ห้ามเดา) (ปิด R12) |
| P1.e | **Rollout flags (env)** — `verificationRoutingEnabled`, ฯลฯ ใน `config/rollout-flags.js` (default off). *สวิตช์ cutover เป็น DB-backed สร้างตอน P6.b ไม่ใช่ที่นี่* |
| P1.f | **Device QA script (Maestro)** — upload → รอตรวจ → ดูสถานะ → owner review fallback บน Android/iOS |
| P1.g | **Guard test ของ route** — ยืนยัน `/api/sports/evidence*` และ route ใหม่ใด ๆ ไม่ผ่อน auth จากเดิม |

**Gate P1:** suite ทั้งหมดเขียว + characterization tests ผ่านบนโค้ดปัจจุบันโดย **ไม่แก้โค้ด production** + contract tests ครบทุกเคส + concurrency test เขียวซ้ำ ≥ 3 รอบ (กัน flaky) + heartbeat/metrics คืนค่าถูกบน fixture

**Rollback P1:** ลบ view/table/flags (ไม่มีผลกับ runtime)

---

### Phase 2 — แก้ทุจริต / privacy / ความซ้ำซ้อน (เปลี่ยนพฤติกรรมโดยตั้งใจ)

**เงื่อนไขเริ่ม:** P1 gate ผ่าน (โดยเฉพาะ characterization + concurrency tests)
**กติกา:** แต่ละข้อย่อย = **PR + migration + gate ของตัวเอง** ห้ามรวม; test ที่ P1.a ติดป้าย known gap จะถูกอัปเดตเฉพาะที่ข้อย่อยนั้น ๆ ระบุไว้

ลำดับตามความสำคัญ:

#### P2.a ตรวจบัญชีผู้รับ + เวลาโอน (ปิด R9) — **สำคัญที่สุด**

| รายการ | รายละเอียด |
|---|---|
| ข้อมูลที่ต้องมี | response ของ provider ต้องมีผู้รับ (ชื่อ/บัญชี/proxy) และเวลาโอน — **ต้องยืนยันกับเอกสาร/sandbox ของ SlipOK ก่อนเขียนโค้ด ห้ามเดาชื่อ field**; ถ้า provider ไม่ส่ง → ผล `unknown` → owner review |
| กติกาเทียบผู้รับ | เทียบกับ `payment_destination_snapshot` ของ group; **เลขบัญชีบนสลิปมักถูกปิดบางหลัก** → เทียบเฉพาะหลักที่มองเห็น + ชนิด (บัญชี/พร้อมเพย์) + ชื่อ (ถ้ามี) โดยมี normalizer ที่ทดสอบด้วยข้อมูลจริงหลายรูปแบบ; ผลเป็น `match` / `mismatch` / `unknown` |
| กติกาเวลา | เวลาโอน ≥ `group.created_at` − ค่าเผื่อ clock skew (ค่าคงที่ตั้งชื่อชัด) และ ≤ now + ค่าเผื่อ — flow จริงชำระ **หลัง** hold ดังนั้นสลิปเก่ากว่า group ไม่ควรผ่านอัตโนมัติ |
| ผลต่อ verdict | `mismatch`/`unknown`/เวลาผิด → **ไม่ใช่ `verified`** → `pending` ให้ owner ตัดสิน (ไม่ auto-reject, ไม่ forfeit); บันทึกเหตุผลใน `provider_meta` แบบ whitelist (`receiverMatch`, `slipAgeOk`) **โดยไม่เก็บเลขบัญชีดิบ** |
| โหมด | คอลัมน์ `receiver_check_mode` บน provider: `off` → **`observe`** (คำนวณและบันทึก แต่ verdict ไม่เปลี่ยน) → **`enforce`** (invariant ข้อ 14) |
| เกณฑ์เปลี่ยน observe → enforce | ผลสังเกตการณ์: สลิปจริงที่ถูกต้อง ≥ 2 ใบ ได้ `match`; สลิปโอนผิดบัญชี (ตั้งใจทดสอบ) ≥ 1 ใบ ได้ `mismatch`; ไม่มี false-mismatch ในสลิปจริงที่ owner อนุมัติตามปกติ |

#### P2.b Privacy: HMAC fingerprint + hash provider_ref + backfill (ปิด R1, R2)

| รายการ | รายละเอียด |
|---|---|
| สูตร | `fingerprint = hmac_sha256(K_v1, 'slipok' \| legacy_string)` โดย `legacy_string` = รูปแบบเดิม `transRef\|transTimestamp\|amount` → **backfill คำนวณจากค่าที่มีอยู่ได้ตรง ๆ ทำให้ dedup history ของสลิปเก่าไม่หาย** (แก้ข้อผิดพลาดของร่างก่อนที่จะ prefix `legacy:` แล้วทำให้สลิปเก่าใช้ซ้ำได้) |
| `provider_ref` | เก็บเป็น HMAC (key คนละ context) หรือ NULL; **adapter ห้ามส่ง `transRef` ดิบออกนอก worker** — hash ใน worker ก่อนเรียก apply; ห้าม log ค่าดิบ |
| key | `VERIFICATION_FINGERPRINT_KEY_V1` อยู่ใน secret store ของ Node (ไม่อยู่ DB); เก็บ `fingerprint_key_version` คู่กับแถว; **ไม่ลบ key เก่าเด็ดขาด** (ลบ = dedup history ใช้ไม่ได้); rotation = คำนวณทั้ง V_old และ V_new ตอนตรวจซ้ำ; สำรอง key นอกเครื่อง |
| backfill | script `websocket-server/scripts/verification-fingerprint-backfill.js`: **dry-run ก่อน**, worker หยุด (kill switch), batch ตาม `fingerprint_key_version IS NULL`, idempotent, ตรวจจำนวนก่อน/หลัง + สุ่มคำนวณซ้ำ; ปริมาณปัจจุบันน้อยมาก (ใบ live ไม่กี่ใบ) — **ทำตอนนี้ต้นทุนต่ำสุด เลื่อนยิ่งแพง** |
| ความปลอดภัยของ migration | เป็นข้อยกเว้นของ invariant ข้อ 1/13: **ต้องมี PITR/backup snapshot ก่อน**; backup ที่มี raw ห้ามเก็บเป็นตารางสำเนาใน DB (จะทำให้ raw ยังอยู่) |
| ผลต่อ client | ไม่มี — `provider_ref` ไม่ได้แสดงใน UI (ตรวจ `grep providerRef lib/` ก่อนเสมอ) |

#### P2.c State machine ของ provider call (ปิด R4)

```
queued ─claim→ claimed ─mark_call_started→ call_started ─save response→ response_received ─apply→ settled
                   │                            │                              │
                   └ lease หมด (ยังไม่ยิง)       └ lease หมด ไม่มี response     └ lease หมด: apply จาก meta ที่บันทึก
                     → claim ใหม่ได้             → settle `unavailable`          (ห้ามยิง provider ใหม่)
                                                   reason `lost_response`
```

- เพิ่ม `call_started_at`, `response_at`, `provider_meta` บน `slip_verification_usage` (additive)
- `mark_call_started` ต้อง atomic กับการตรวจ `claimed_by` = worker นี้; ทำ **ก่อน** `fetch`
- response ที่ได้รับ → บันทึกลง `provider_meta` (whitelist, ไม่มี raw ref) ก่อนเรียก apply
- ถ้า provider รองรับ idempotency key → ส่ง `attempt_id` (ต้องยืนยันเป็นรายผู้ให้บริการ) แต่ **ไม่พึ่งเป็นกลไกหลัก**
- นโยบาย retry: **ไม่ retry อัตโนมัติหลังยิงแล้ว** (D6) — ล้ม = `unavailable` → owner review

#### P2.d กู้ผล verified ที่ stale (ปิด R10)

- ใน branch stale ของ apply: ถ้า provider ตอบ `verified` → **บันทึก fingerprint (dedup) + ตั้ง usage.result = `verified_stale`** (ขยาย CHECK constraint ผ่าน migration) + เก็บ `provider_meta`; ไม่ยืนยัน booking, ไม่คืนเงินอัตโนมัติ
- แจ้ง owner ของ venue และ admin ว่ามี "สลิปที่ provider ยืนยันแต่ booking ปล่อยไปแล้ว" ผ่านช่องทางแจ้งเตือนเดิม; ผู้จองใช้ flow payment-claim/refund ที่มีอยู่แล้ว (ไม่สร้าง flow เงินใหม่ — **ต้องให้เจ้าของแผนตัดสินว่าจะ surface อย่างไรใน owner queue**)
- test: housekeeping forfeit ระหว่าง provider call → ผลสุดท้าย = `verified_stale` + dedup มีแถว + ไม่มี confirm

#### P2.e Queue fairness (ปิด R3)

- RPC ใหม่ `worker_claim_next_sports_venue_slip_verification(worker_id, limit)`: เลือกแถว `result IS NULL` ที่ยังไม่ถูก claim หรือ lease หมดอายุด้วย `FOR UPDATE SKIP LOCKED` แล้ว claim ในคำสั่งเดียว; ของเดิมคงไว้เป็น shim (signature stability)
- worker เปลี่ยนมาใช้ตัวใหม่; พิสูจน์ด้วย concurrency test P1.c (สอง worker ไม่ได้แถวเดียวกัน)

#### P2.f เพดานค่าใช้จ่ายและความทนทานต่อ provider ล่ม (ปิด R11)

| รายการ | รายละเอียด |
|---|---|
| Provider cap | คอลัมน์ `monthly_cap` บน provider — claim นับ usage ต่อ `provider_code` ในเดือน ใต้ lock; เกิน → skip reason `provider_cap_exceeded` → owner review |
| Platform budget | ตาราง singleton `verification_platform_budget` (`monthly_cap_amount`, `warn_ratio`) นับ `cost_estimate` รวมทุก provider; **ค่าเริ่มต้นต้องตั้งโดย admin ก่อนขยาย whitelist** (D8); แสดงเป็น "ประมาณการ" ใน UI เสมอ |
| Circuit breaker | ล้มติดกัน N ครั้ง (timeout/5xx) → เปิดวงจร M วินาที: claim คืน skip `provider_unhealthy` ทันทีโดยไม่รอ timeout → owner review; half-open ลองหนึ่งใบ; สถานะเก็บใน worker + metric |
| ผลต่อ owner | ใบที่ตก review เพราะ cap/breaker ต้องมีข้อความชัดเจนใน owner queue ว่า "ระบบตรวจอัตโนมัติไม่พร้อม — โปรดตรวจเอง" (ไม่ใช่ "สลิปไม่ถูกต้อง") |

**Gate P2 (ต่อข้อย่อย + รวม):**
1. P1.a characterization tests: เฉพาะ test ที่ติดป้าย known gap ของข้อนั้นเปลี่ยนค่า — **ที่เหลือต้องผ่านโดยไม่แก้**
2. SQL smoke ≥ baseline + assertion ใหม่ของข้อนั้น; concurrency test เขียวซ้ำ ≥ 3 รอบ; `npm test`/`flutter test` book_court/`dart analyze` ผ่านเท่าเดิม
3. **P2.a:** observe→enforce ตามเกณฑ์ข้างบน + ยืนยันว่า `mismatch` ตกเป็น `pending` (ไม่ forfeit)
4. **P2.b:** dry-run ผ่าน, snapshot ยืนยันแล้ว, หลัง backfill: `SELECT count(*) WHERE fingerprint ~ '\|'` = 0 (ไม่มีรูปแบบ raw เหลือ), `provider_ref` ไม่ใช่ค่าดิบ, สลิปที่เคย verified แล้วส่งซ้ำ → ถูก dedup ปฏิเสธ (พิสูจน์ว่า history ไม่หาย)
5. **P2.c:** test "apply ล้ม → ไม่ยิง provider ซ้ำ" และ "lease หมดหลัง call_started → `unavailable` ไม่ยิงซ้ำ"
6. **Live smoke ตามงบ §6.2** ทุกข้อย่อยที่แตะเส้นทาง verify
7. **Rollback drill ต่อข้อย่อย** (flag/mode กลับ `observe`/`off` หรือ revert Node; P2.b = กู้ snapshot — ซ้อมบน scratch DB)

**Rollback P2:** ต่อข้อย่อยตาม gate ข้อ 7 — P2.a ลดเป็น `observe`/`off` ได้ทันที (ไม่ต้อง deploy), P2.c/e/f revert Node + rollback script, P2.d revert RPC (แถว `verified_stale` ที่เกิดแล้วคงไว้เป็นหลักฐาน)

---

### Phase 3 — แยกโค้ด (pure refactor, พฤติกรรมเหมือนเดิม 100%)

**เงื่อนไขเริ่ม:** P2 เสร็จ — refactor ต้องห่อพฤติกรรม **หลัง** hardening ไม่ใช่ก่อน (ไม่งั้น refactor ซ้ำสองรอบ)

**เป้าหมาย:** จัดโครงสร้างให้พร้อม generalize **โดยไม่แตะ schema และไม่เปลี่ยนพฤติกรรม**

| งาน | จาก → ไป |
|---|---|
| P3.1 | `services/slip-verification-worker.js` → `services/verification/worker.js` (loop กลาง) + `services/verification/adapters/slipok.js` + `services/verification/adapters/index.js`; คง `services/slip-verification-worker.js` เป็น re-export shim เพื่อไม่แตะ `server.js` |
| P3.2 | `routes/sports-evidence.js` → แยก `middleware/evidence-upload.js` (multer + magic byte + sharp pipeline) เป็น util กลางที่ route เดิมเรียก; **route path และ response shape คงเดิม** |
| P3.3 | Dart: แยก `EvidenceGateway` service (createGrant/uploadViaGateway/mintReadToken/urlForToken) ออกจาก `BookCourtRepository` — repo delegate, signature เดิม |
| P3.4 | Dart: แยก `SlipProviderRegistryCard` (+ `SlipVerificationProvider` model) ออกจาก `admin_court_owner_review_page.dart` เป็น widget กลาง — rendering เดิม |
| P3.5 | Bucket/mime/path prefix ย้ายเป็นค่าที่อ่านจาก claim payload/parameter (ค่า default ยังเป็นค่าปัจจุบัน) |

**Gate P3 (เข้มที่สุดในแผน เพราะเป็นด่านพิสูจน์ "ไม่พัง"):**
1. `npm test` ผ่านเท่าเดิม + test ใหม่ยืนยันว่า shim path ให้ผลเท่าเดิม
2. `flutter test` ทั้ง project ผ่านเท่าเดิม; widget test ของ admin panel/provider card และ `booking_group_sheet_test.dart` ผ่านโดยไม่แก้ test
3. **Payload diff:** รัน claim/apply บน fixture เดียวกันก่อน-หลัง refactor แล้ว diff JSON payload → ต้องเท่ากันทุก key
4. `dart analyze lib test` clean
5. Upload/read E2E บนเครื่องจริง: อัปโหลดผ่าน gateway → เปิดดูผ่าน read token → orphan sweeper ไม่ลบไฟล์ที่ยังถูกอ้าง
6. **ไม่มีการเปลี่ยน migration ใน phase นี้** (ถ้าจำเป็นให้ย้ายไป P5)

**Rollback P3:** revert commit (ไม่มี migration ให้ย้อน)

**หมายเหตุ:** Phase นี้ไม่ควรทำพร้อม P5 ใน PR เดียว — ถ้าพังจะแยกไม่ออกว่าเกิดจาก refactor หรือ schema

---

### Phase 4 — สลับ provider รายระบบผ่าน UI (Sports ระบบเดียวก่อน)

**เงื่อนไขเริ่ม:** P0.2 (adapter readiness) + P1.d (heartbeat) + P2.f (cap/breaker) เสร็จ
**เป้าหมาย:** Admin Sheserved เพิ่ม/สลับ provider ได้อย่างปลอดภัย และ **เลือกผิดไม่ได้**; ออกแบบ routing ให้ keyed ด้วย `domain` ตั้งแต่ต้น แต่ใช้จริงกับ `sports_booking` เพียงตัวเดียว

| งาน | รายละเอียด |
|---|---|
| P4.1 | ตาราง `verification_domain_providers` (domain, provider_code FK, is_primary, is_enabled) + RPC `admin_list_verification_domains`, `admin_set_verification_domain_provider` (+audit P0.4) |
| P4.2 | **Claim อ่าน routing:** มีแถว primary ที่ enabled → ใช้ตัวนั้น; **ไม่มี routing → พฤติกรรมเดิม (priority order)** เพื่อ compat; **ไม่มี failover อัตโนมัติ** (D6) |
| P4.3 | **บล็อกที่ backend:** ปฏิเสธ routing ถ้า `verification_adapter_known(adapter_code)` เป็นเท็จ, domain ไม่อยู่ใน `supported_domains`, หรือไม่มี heartbeat ล่าสุดที่รายงาน adapter นั้น (worker ยังไม่รู้จัก) |
| P4.4 | UI ส่วน "ผู้ให้บริการตรวจสอบรายระบบ": ตาราง domain × provider, สถานะ adapter/secret/worker heartbeat, cost โดยประมาณ (ระบุว่าเป็นประมาณการ), quota/cap/budget ที่ใช้ไป, `receiver_check_mode` |
| P4.5 | คำเตือนก่อนสลับ: "มีผลกับคำขอใหม่เท่านั้น; คำขอที่ claim แล้วยึด provider เดิมจนจบ" + แสดงจำนวนคำขอที่ค้างคิว |
| P4.6 | ปุ่ม **Test connection** แยกจาก "เปิดใช้งาน": เรียก endpoint ตรวจสถานะ/โควตาของ provider (ไม่ส่งสลิปจริง ไม่คิดค่าใช้จ่ายถ้าเป็นไปได้) + แสดงผลที่ไม่เปิดเผย secret |
| P4.7 | ปรับ `admin_court_owner_review_page.dart` ให้ใช้ widget กลางจาก P3 (ลบโค้ดซ้ำ) |
| P4.8 | **Provider onboarding checklist (ปิด R13)** — ต้องครบก่อน `adapter_code` ใหม่เข้า `verification_adapter_known`: (1) adapter + contract tests ผ่านบน fake server (2) sandbox/สัญญาทดสอบจริง (3) ยืนยัน field ผู้รับ/เวลา/idempotency/ราคา/SLA ตามเอกสาร (4) **สัญญาประมวลผลข้อมูล (DPA) + ที่ตั้งข้อมูล/การส่งข้ามพรมแดนผ่านการตรวจของเจ้าของข้อมูล** (5) host ใส่ใน `VERIFICATION_ALLOWED_HOSTS` (6) ตั้ง cap เริ่มต้นต่ำ (7) live smoke ตามงบ §6.2 — บันทึกผลเป็นไฟล์ในโฟลเดอร์ plans |

**Gate P4:** widget tests (render, save forwards params, ปฏิเสธ provider ไม่พร้อม/ไม่มี heartbeat) + SQL smoke (NOT_ADMIN, routing ไม่ผ่านเมื่อ adapter ไม่รู้จัก, audit row, ไม่มี routing → ใช้ priority เดิม) + **Sports ยังใช้ `slipok` เหมือนเดิมหลังตั้ง routing** + สลับไป–กลับระหว่างสอง provider ได้บน fake server โดยไม่กระทบใบที่ claim ค้าง

**Rollback P4:** ปิด `verificationRoutingEnabled` → claim กลับไปใช้ priority order เดิม (P4.2 ข้อ compat); แถว routing ปล่อยทิ้งได้

---

### Decision gates D1 / D2 (ตรวจก่อนเข้า Phase ช่วง B)

**D1 — "มีระบบที่สองจริงไหม?"** (ก่อน P5) ต้องเขียนลงเอกสารแนบแผน (ไฟล์สั้นหนึ่งหน้า) ให้ครบ:

| หัวข้อ | ต้องตอบ |
|---|---|
| ระบบที่สอง | ชื่อระบบ + เจ้าของ + แผน launch |
| subject | อะไรคือ "คำขอที่ต้องตรวจ" (ตัวอย่าง: order, การบริจาค, การส่งของ) และใครส่งหลักฐาน |
| scope | หน่วยที่จำกัดโควตา/ค่าใช้จ่าย (ร้าน? องค์กร? ผู้ใช้?) และใครเป็นผู้จ่าย |
| ยอดเงิน | ยอดที่คาดหวังมาจากไหน, สกุลเงิน, ยอมรับผลต่างหรือไม่ |
| ผู้รับเงิน | บัญชีผู้รับที่ต้องตรงมาจากไหน (P2.a ต้องใช้กับ domain นี้ได้) |
| reviewer | ใครตัดสินเมื่อ provider ไม่ยืนยัน และ SLA เท่าไร |
| ข้อมูล/กฎหมาย | retention ที่ legal อนุมัติแล้ว + DPA ของ provider ที่จะใช้ |

**ผล:** ตอบไม่ครบ/ไม่มี → **จบแผนที่ P4** (บันทึกในเอกสารว่าทำไม ไม่ถือเป็นความล้มเหลว)

**D2 — "ย้าย Sports เข้าแกนกลางจริงไหม?"** (ก่อน P6) ผ่านเมื่อ P5 shadow parity = 0 mismatch และ domain ที่สองมีกำหนด launch แล้ว; ไม่ผ่าน → Sports อยู่ legacy path ต่อ และ domain ที่สองเรียกแกนกลางตรง (ยอมรับสองเส้นทางโดยมีเจ้าของระบุชื่อ)

---

### Phase 5 — แกนกลางแบบ additive + shadow comparison (เริ่มเมื่อผ่าน D1 เท่านั้น)

**เงื่อนไขเริ่ม:** ผ่าน decision gate **D1** (มี domain ที่สองระบุชัดเจน) — ห้ามสร้างแกนกลางแบบเดา requirement

**เป้าหมาย:** สร้างแกนกลางและพิสูจน์ความเทียบเท่าโดยที่ Sports Hub ยังเดินบนเส้นทางเดิม

| งาน | รายละเอียด |
|---|---|
| P5.1 | สร้างตาราง `verification_requests`, `verification_scopes`, `verification_admin_audit` (§4.2) + RLS enable + REVOKE จาก `anon, authenticated` |
| P5.2 | เขียน RPC กลางตาม §4.3 (ยังไม่มีผู้เรียกใน production) |
| P5.3 | เขียน `sports_booking_verification_gate/applied/upload_authorized/read_authorized` โดย **ย้าย logic เดิมมาใช้ซ้ำ** ไม่ copy |
| P5.4 | **Shadow mirror:** เมื่อ `submit_sports_venue_booking_evidence` สร้าง usage row ให้สร้าง `verification_requests` row คู่กัน (state `queued`) แต่ **worker ยังไม่ประมวลผล** |
| P5.5 | **Parity job (offline):** RPC `verification_shadow_compare()` เทียบผลที่ legacy apply กับที่ generic gate จะตัดสิน (scope/quota/provider/expected amount) → คืนรายการที่ไม่ตรง |

**Gate P5:**
1. smoke ผ่าน + assertion ใหม่: RLS/REVOKE ของตารางใหม่, `verification_domain_gate` คืนค่าตรงกับ legacy gate บน fixture ≥ 6 กรณี (scope disabled / whitelist miss / quota exceeded / no provider / stale / verify)
2. `verification_shadow_compare()` บนข้อมูลจริง ≥ 20 รายการ → 0 ความไม่ตรง (ถ้ามี ต้องอธิบายได้ทีละรายการ)
3. Sports flow เดิม: live smoke ผ่านเท่าเดิม

**Rollback P5:** drop ตาราง/ฟังก์ชันใหม่ + ลบ shadow insert (Sports ไม่เคยพึ่งพาแกนกลางใน phase นี้)

---

### Phase 6 — ย้าย Sports Hub ไปแกนกลาง (flag-gated, เริ่มเมื่อผ่าน D1–D2)

**เงื่อนไขเริ่ม:** P5 เสร็จ + ผ่าน **D2** (ตัดสินแล้วว่าจะย้าย Sports จริง ไม่ปล่อยเป็น legacy ถาวร)

**เป้าหมาย:** Sports Hub เดินบนแกนกลางจริง โดยปิด/เปิดได้ด้วย flag เดียว **โดยไม่ต้อง deploy**


#### P6.a โมเดลความเป็นเจ้าของ attempt (ownership) — กัน double-processing

ปัญหา: mirror row ใน `slip_verification_usage` มี `result IS NULL` จนกว่า generic จะ settle — ถ้า legacy worker
ยังรันอยู่ มันจะหยิบ mirror row ไปประมวลผลซ้ำ (provider call ซ้ำ = เสียเงินซ้ำ)

| งาน | รายละเอียด |
|---|---|
| P6.a1 | เพิ่มคอลัมน์ `path VARCHAR(10)` บน `slip_verification_usage` (`'legacy'` / `'generic'`; แถวเดิม = NULL ถือเป็น legacy) — ตั้งค่า **ตอนสร้างแถว** ไม่ใช่ตอน claim |
| P6.a2 | Legacy claim กรอง `path IS DISTINCT FROM 'generic'`; generic claim กรองเฉพาะ `path = 'generic'` — worker สองตัวอยู่ร่วมกันได้อย่างปลอดภัยเพราะแต่ละตัวเห็นเฉพาะของตัวเอง |
| P6.a3 | Advisory lock ต่อ `attempt_id` ใน claim-next กลาง (`FOR UPDATE SKIP LOCKED`) — กัน generic worker หลาย instance ชนกัน |
| P6.a4 | Idempotent cross-path: legacy shim apply บน attempt ที่ generic settle ไปแล้วต้องคืน `already_done` (และกลับกัน) |

#### P6.b Flag สลับเส้นทาง — ต้องเปลี่ยนได้โดยไม่ deploy

| งาน | รายละเอียด |
|---|---|
| P6.b1 | ตาราง `verification_core_settings` (singleton): `sports_on_core BOOLEAN DEFAULT false`, `updated_by`, `updated_at` — **นี่คือ switch จริง** ที่ worker อ่านทุก tick (select ถูก ๆ) |
| P6.b2 | Env override ฉุกเฉิน: `VERIFICATION_CORE_FORCE_LEGACY=true` บังคับ legacy ทั้งหมด (ใช้เมื่อ DB flag เขียนไม่ได้) — ต้องมี log ชัดเจนเมื่อ override ทำงาน |
| P6.b3 | Worker กลาง: ถ้า `sports_on_core = false` → ไม่ claim domain `sports_booking` (แต่ยัง drain แถวที่ตัวเองเป็นเจ้าของ — ดู P6.d) |
| P6.b4 | Legacy worker: ถ้า `sports_on_core = true` → ออกจาก loop การ claim ใหม่ (แต่ยัง drain แถว legacy ที่ตัวเอง claim ค้าง) |
| P6.b5 | RPC `admin_set_verification_core_path(p_admin_id, p_domain, p_on_core)` + audit (ใช้ `verification_admin_audit` จาก P0.4) |

#### P6.c Mirror atomicity และ source of truth ระหว่าง dual-write

| งาน | รายละเอียด |
|---|---|
| P6.c1 | `verification_apply` (กลาง) เขียน **ใน transaction เดียว**: `verification_requests` + mirror `slip_verification_usage` (result/cost/finished_at) + `slip_verification_transactions` (dedup) + เรียก `verification_domain_applied` — mirror ห้ามตก transaction แยก |
| P6.c2 | **Quota นับจาก `slip_verification_usage` เสมอ** (ทั้งสอง path เขียนตารางนี้) — ห้ามนับจาก `verification_requests` ระหว่าง dual-write ไม่งั้นโควตาจะนับซ้ำ/ขาด; สลับไปนับตารางกลางตอน P8 เท่านั้น |
| P6.c3 | Dedup (`slip_verification_transactions`) เขียนโดย generic path ด้วย fingerprint format เดียวกับ P2.b — rollback ต้องไม่ทำให้ dedup history ขาดหาย |
| P6.c4 | Cost snapshot: `cost_estimate` ตั้งตอน claim (เหมือน legacy), `cost_actual` ตั้งตอน settle — ทั้งสองตารางเขียนค่าเดียวกัน |

#### P6.d In-flight handover (ทั้งสองทิศทาง)

| สถานการณ์ | กติกา |
|---|---|
| **ก่อน flip ขึ้น (legacy → generic)** | Precondition: คิว legacy ว่าง (`result IS NULL` ใน usage = 0) **หรือ** แถวที่เหลือมี lease สด → รอให้ settle ก่อน (สูงสุด lease 2 นาที + timeout provider); ห้าม flip ขณะมี `call_started_at` ที่ยังไม่มี `response_at` |
| **หลัง flip ขึ้น** | คำขอใหม่ทั้งหมดสร้าง mirror row `path='generic'` → generic worker รับผิดชอบ; แถว legacy เก่าถ้ายังค้าง (ไม่ควรมีตาม precondition) ให้ legacy drain |
| **Rollback กลับลง (generic → legacy)** | คำขอใหม่กลับไป legacy; แถว generic ที่ยังไม่ settle → generic worker เข้าโหมด **drain-only** (ประมวลผลเฉพาะแถวที่ตัวเองเป็นเจ้าของ ไม่รับใหม่) จนคิวว่างแล้วหยุด; ห้าม settle เป็น `unavailable` ทิ้งถ้ายังไม่จำเป็น |
| **Attempt ค้าง `call_started` ไม่มี response** | ทั้งสอง path: หลัง lease หมดอายุ → settle `unavailable` + owner review (ตาม P2.c) — ไม่ยิง provider ซ้ำ |

#### P6.e Parity ของ side-effect (พิสูจน์ด้วย state diff ไม่ใช่แค่ payload diff)

Payload diff ของ P3 ครอบแค่ claim; apply มี side-effect ที่ต้องพิสูจน์แยก:

| งาน | รายละเอียด |
|---|---|
| P6.e1 | **State-diff test บน fixture คู่** — รัน legacy apply บน DB A และ generic apply บน DB B (fixture เหมือนกัน) แล้ว diff: `sports_venue_booking_evidence` (ทุกคอลัมน์), `sports_venue_booking_groups` (status/decided_at/payment_*), `slip_verification_transactions`, แถว usage — ต้องเหมือนกันทุกคอลัมน์ (ยกเว้น timestamp ที่ต่างวินาทีได้) |
| P6.e2 | **Notification parity** — `sports_hub_notify` ที่ยิงตอน confirm ต้องมี channel/type/payload เดียวกันทั้งสอง path (จับจาก fixture) |
| P6.e3 | **Client visibility** — evidence row JSON ที่แอปอ่าน (ผ่าน `list_my_sports_venue_booking_groups`/queue RPC) ต้องเท่าเดิมทุก key — ไม่มีการเปลี่ยนที่ client มองเห็น |

#### P6.f Cutover runbook (ลำดับที่ต้องทำตาม ห้ามข้าม)

```
เงื่อนไขก่อนเริ่ม (ทั้งหมดต้องจริง):
  □ P0–P4 gate ผ่านครบ + P5 shadow parity = 0 mismatch
  □ คิว legacy ว่าง (ไม่มี result IS NULL) — ตรวจ: SELECT count(*) FROM slip_verification_usage WHERE result IS NULL
  □ ไม่มี attempt ที่ call_started โดยไม่มี response
  □ metrics 24 ชม.ล่าสุด: error rate ปกติ, cost ต่อวัน ≤ baseline
  □ deploy Node ที่มี worker กลางแล้ว (flag ยังปิด) + /health ผ่าน
  □ migration ของ P6 apply บนสำเนาข้อมูลจริงแล้วผ่าน (gate ข้อ 1)
  □ เลือกช่วง traffic ต่ำ + ผู้ดำเนินการ 1 คน + บันทึกเวลาใน audit

ขั้นตอน:
  1. apply migration P6 (path column + settings + shim redef) บนฐานจริง
  2. ยืนยัน shim: เรียก legacy RPC บน fixture → พฤติกรรมเดิม (flag ยังปิด)
  3. flip: admin_set_verification_core_path('sports_booking', true)
  4. ตรวจ 5 นาทีแรก: worker กลาง log claim ได้, legacy worker log "core active — idle"
  5. สลิปจริง 1 ใบบน venue ทดสอบ → verified → auto-confirm (เกณฑ์เดิมของ 21.7.21)
  6. เข้า observation window (ดู P6.g)

จุดยกเลิกทันที (abort → rollback ตาม P6.h):
  - booking ใดถูก confirm โดยไม่มี evidence verified      → ระดับวิกฤต ย้อนทันที
  - provider call ซ้ำต่อ attempt เดียว                     → ย้อนทันที
  - คิว generic ค้าง > 5 นาที โดยไม่มี worker claim         → ย้อนทันที
  - parity/state diff ไม่ตรงบนข้อมูลจริง                    → ย้อนทันที
  - cost ต่อชั่วโมง > 2× baseline                          → ย้อนทันที
```

#### P6.g Observation window

| รายการ | ค่า |
|---|---|
| ระยะเวลา | ≥ 24 ชม. (ครอบคลุมรอบ housekeeping/cron อย่างน้อย 1 รอบเต็ม) |
| เกณฑ์ผ่าน | (ก) ทุก attempt ที่ settle มีผลตรงกับที่ legacy จะให้ (สุ่มตรวจ ≥ 10 รายการด้วย `verification_shadow_compare`) (ข) ไม่มี abort criteria เกิดขึ้น (ค) queue age p95 < 2 นาที (ง) ไม่มี owner review ที่ผู้ใช้ร้องเรียนว่าสลิปถูกต้องแต่ถูกปฏิเสธ |
| ระหว่าง window | ห้ามเปลี่ยน provider/scope/quota อื่น (แยกสาเหตุเมื่อเกิดปัญหา) |
| หลังผ่าน | บันทึกผลใน audit + อัปเดต `Match_Sport_PLAN.md` 21.7.21 |

#### P6.h Rollback drill และ rollback จริง

**Drill (บังคับก่อน flip จริง — ทำบน venue ทดสอบ):**
1. flip ขึ้น → สลิปจริง 1 ใบผ่าน → flip กลับ **ขณะมี attempt generic ยังไม่ settle** (สร้างสถานการณ์นี้เอง)
2. ยืนยัน: legacy รับใหม่ทันที (≤ 1 รอบ polling); generic เข้า drain-only และ settle แถวตัวเองจนว่าง; ไม่มี provider call ซ้ำ; ไม่มี booking ถูกยืนยันซ้ำ
3. ยืนยัน re-cutover: flip ขึ้นอีกครั้งหลังคิวว่าง → ทำงานปกติ

**กฎ re-cutover หลัง rollback จริง:** รอให้ (ก) คิวว่าง (ข) 24 ชม.เสถียร (ค) ระบุ root cause และแก้แล้ว — ถ้า rollback ครบ 2 ครั้งแล้วยังพัง ให้หยุดแผนนี้และประเมินใหม่ (อาจอยู่กับ legacy path ถาวรชั่วคราว)

**Rollback จริง (หน้างาน):**
```
1. admin_set_verification_core_path('sports_booking', false)   ← ไม่ต้อง deploy
2. ยืนยัน legacy worker ยังรันอยู่ (ถ้าไม่ → เปิด + VERIFICATION_CORE_FORCE_LEGACY=true)
3. generic worker เข้า drain-only อัตโนมัติ (แถว path='generic' ที่ยังไม่ settle)
4. ตรวจ 10 นาที: ใหม่ไหลผ่าน legacy, ไม่มี double-claim (path filter กันอยู่แล้ว)
5. บันทึกเหตุการณ์ใน verification_admin_audit + แจ้งทีม
```

#### Gate P6 (ต้องผ่านครบก่อนประกาศเสร็จ)

1. **Migration ordering test:** apply migration ชุดใหม่บน dump ข้อมูลจริง → smoke ผ่าน + แถว usage เดิมถูกตีความเป็น `path=NULL(legacy)` ถูกต้อง
2. **State-diff parity (P6.e1–e3):** 0 ความต่างบน fixture ครบทุกกรณี (verified/failed/unavailable/timeout/duplicate/quota-exceeded/stale)
3. **Cutover drill:** สลิปจริง 1 ใบ → `verified` → auto-confirm; ใบที่ 2 → `quota_exceeded` → owner review (ไม่เรียก provider)
4. **Rollback drill ตาม P6.h ผ่านครบทั้ง 3 ข้อ** (รวม drain-only และ re-cutover)
5. **ไม่มี provider call ซ้ำ:** นับ `call_started_at` ต่อ attempt_id ทั้งสองตาราง = สูงสุด 1 (ยกเว้นกรณี timeout ที่ settle เป็น unavailable แล้ว)
6. **Shim test:** legacy RPC ชื่อเดิมบน flag on/off ให้ผลถูกทั้งสองกรณี
7. `flutter test` book_court + node test ผ่านเท่าเดิม; `dart analyze` clean
8. **Observation window 24 ชม.ผ่าน** ตาม P6.g

**Rollback P6:** ตาม P6.h — flip DB flag (ไม่ต้อง deploy) + drain-only; mirror ทำให้ข้อมูล audit ครบทั้งสอง path; ข้อมูลธุรกิจ (booking/evidence/dedup) ไม่ต้องแก้ย้อนหลัง

#### P6.i งบสลิปจริงสำหรับ drill (ข้อจำกัดเชิงปฏิบัติ)

- สลิปจริงใช้ซ้ำไม่ได้ (dedup) → **ทุก live drill = โอนจริงใหม่ 1 ใบ** (ยอด 1 บาทตามที่ใช้ทดสอบมา) และกินโควตา SlipOK ของ account
- venue ทดสอบตั้ง `verify_monthly_quota = 1` → drill ที่ต้องใช้หลายใบ (cutover → rollback → re-cutover) ต้อง **ยกโควตาชั่วคราวเป็น ≥ 5** แล้วคืนค่าหลังจบ drill (บันทึกใน audit)
- drill ที่ไม่ต้องการ provider จริง (drain-only, ownership, shim) ให้ใช้ **fake provider** ใน staging/scratch ก่อน แล้วค่อยยืนยันด้วยสลิปจริงขั้นสุดท้าย 1 ใบ
- ดูตารางงบรวมใน §6.2

---

### Phase 7 — รับ domain ที่สอง (gated ด้วย D1 + ผู้ใช้จริง)

**เงื่อนไขเริ่ม:** มีระบบที่สองที่ต้องการจริง + ตกลง retention/privacy ของ domain นั้นแล้ว + P0–P6 (ตาม D2) เสร็จและเสถียร ≥ 1 release

| งาน | รายละเอียด |
|---|---|
| P7.1 | ระบุ canonical identity ของ subject (อะไรคือ "คำขอที่ต้องตรวจ" ของ domain นั้น) และ scope owner (ใครจ่าย/ใครจำกัดโควตา) |
| P7.2 | เขียน domain adapter 4 ฟังก์ชัน + Node adapter (ถ้า provider ต่างจาก SlipOK) |
| P7.3 | `verification_scopes` ของ domain ใหม่ default **ปิด** + quota เริ่ม 1 |
| P7.4 | Retention ของ domain ใหม่แยกจาก Sports (bucket prefix ต่อ domain) |
| P7.5 | Pilot กับผู้ใช้กลุ่มเล็ก + วัด metric ตาม P1.d |

**Gate P7:** pilot ผ่าน, ไม่มี cross-domain leakage (test: user ของ domain A อ่านหลักฐาน domain B ไม่ได้), quota/cost แยกกันจริง

**Rollback P7:** ปิด scope ของ domain ใหม่ (Sports ไม่กระทบ)

---

### Phase 8 — เก็บกวาดของเก่า

| งาน | เงื่อนไขก่อนทำ |
|---|---|
| P8.1 ลบ shim RPC เก่า (`worker_*_sports_*`) | ไม่มี client/worker รุ่นเก่าเรียก ≥ 1 release + ยืนยันจาก log |
| P8.2 เลิก mirror `slip_verification_usage` | parity 100% ต่อเนื่อง ≥ 30 วัน |
| P8.3 ย้าย `sports_venues.verify_*` เป็น view/computed | owner editor รุ่นเก่าไม่อยู่ในสนามแล้ว |
| P8.4 รวม `slip_verification_providers` → `verification_providers` | **ทางเลือก** — ถ้าต้นทุน rename สูงกว่า benefit ให้คงชื่อเดิมและบันทึกว่าเป็นชื่อในอดีต |
| P8.5 อัปเดต cross-link ใน `Match_Sport_PLAN.md` และ `AGENTS.md` | ทุก phase ที่เปลี่ยนวิธี verify |

> P8 ทุกข้อเป็น **forward-fix** เท่านั้น ห้ามลบข้อมูล audit/fingerprint (ลบ dedup ledger = เปิดช่องใช้สลิปซ้ำ)

---

## 6. การตรวจสอบ (Verification)

### 6.1 Verification matrix

| คำสั่ง/การตรวจ | ใช้เมื่อ | เกณฑ์ผ่าน |
|---|---|---|
| `cd database && psql … -f sports_hub_rpc_smoke_test.sql` (scratch DB เท่านั้น) | ทุก phase ที่แตะ SQL | PASS ≥ baseline, FAIL 0, ERROR 0 |
| `database/verification_concurrency_test.sh` (สอง session) | P1 เป็นต้นไป ทุก phase ที่แตะ claim/apply | เขียวซ้ำ ≥ 3 รอบ |
| `cd websocket-server && npm test` | ทุก phase ที่แตะ Node | ผ่านครบ + test ใหม่ |
| `dart analyze lib test` | ทุก phase ที่แตะ Dart | ไม่มี error ในไฟล์ที่แตะ |
| `flutter test test/features/sport_club/book_court` | ทุก phase | 227 ผ่านเท่าเดิม (ห้ามลด) |
| `flutter test` (ทั้ง project) | P3, P6 | ไม่มี test ตกเพิ่ม |
| Characterization diff (P1.a) | P2 ทุกข้อย่อย | เปลี่ยนเฉพาะ test ที่ติดป้ายของข้อนั้น |
| Payload diff (claim/apply บน fixture) | P3, P6 | JSON เท่ากันทุก key |
| `verification_shadow_compare()` | P5 | 0 mismatch บน ≥ 20 รายการจริง |
| State-diff test (apply side-effects คู่ fixture) | P6 | evidence/group/dedup/usage/notification เท่ากันทุกคอลัมน์ |
| Shim test / Drain-only test | P6 | ผลถูกทั้ง flag on/off; settle ของตัวเองจนว่าง ไม่รับใหม่ ไม่ยิงซ้ำ |
| Rollback drill | P0, P2, P6 | ย้อนกลับแล้วสลิปใหม่ทำงานได้ภายใน 1 รอบ polling |
| Live smoke บน venue ทดสอบ | ตาม §6.2 | `verified` → auto-confirm; ใบถัดไปตามโควตา → owner review |
| Maestro flow (upload→verify→review) | P1, P6 | ผ่านบน Android + iOS |
| `curl /health` (3000 และ 8080) | ทุก deploy | 200 |

> **หมายเหตุเครื่องนี้:** `flutter analyze` crash (ขาด `analysis_server.dart.snapshot`) → ใช้ `dart analyze` ตาม `AGENTS.md`

### 6.2 งบสลิปจริงและโหมดทดสอบ (ข้อจำกัดเชิงปฏิบัติ)

สลิปจริงใช้ซ้ำไม่ได้ (dedup) และกินโควตา account ของ SlipOK (บันทึกในแผนเดิมว่า 100) — **ทุก live smoke = โอนจริงใหม่ 1 ใบ** ดังนั้นต้องวางงบล่วงหน้า:

| Phase | จำนวนสลิปจริง (ประมาณการ — ปรับตามจริง) | วัตถุประสงค์ |
|---|---|---|
| P0 | 1 | smoke หลัง key ใหม่ + adapter filter + SSRF allowlist |
| P2.a | ≥ 3 (บวกถูกต้อง ≥ 2, โอนผิดบัญชี ≥ 1) | observe → enforce |
| P2.b | 1 + (ส่งซ้ำใบเดิม = 0 สลิปใหม่) | พิสูจน์ dedup history ไม่หาย |
| P2.c–f | 1–2 | smoke ต่อข้อ |
| P4 | 1–2 (ต่อ provider ใหม่) | onboarding smoke |
| P6 (ถ้าทำ) | 3–5 | cutover / rollback / re-cutover |
| **รวมโดยประมาณ** | **≈ 10–15 จาก 100** | เหลือ headroom ให้ใช้งานจริง |

**โหมดทดสอบโดยไม่ใช้สลิปจริง:** fake provider server (P1.b) ใช้กับ drain-only/ownership/shim/state machine ได้ทั้งหมด; สลิปจริงใช้เฉพาะการยืนยันขั้นสุดท้ายของแต่ละข้อ

**Reduced-drill mode (ถ้าไม่มี staging — D9):** ทำ drill บน venue ทดสอบใน production โดย (1) allowlist เฉพาะ venue นั้น (2) quota ยกเป็น ≥ 5 ชั่วคราว (3) ถ่าย PITR snapshot ก่อนข้อที่เปลี่ยนข้อมูล (4) เลือกช่วง traffic ต่ำ (5) มีผู้ดำเนินการหนึ่งคน + จุด abort ชัดเจน — **ห้ามใช้โหมดนี้กับ P6 cutover ถ้าไม่มี scratch DB ที่ซ้อม migration บน dump จริงแล้ว**

---

## 7. การควบคุมรัศมีผลกระทบ (Blast radius control)

### 7.1 ต่อระบบจองสนาม (สำคัญที่สุด)

- ไม่มีการแก้ตาราง `sports_venue_booking_groups`, `sports_venue_booking_evidence`, `sports_venues` แบบทำลาย — เพิ่มคอลัมน์ nullable เท่านั้น
- RPC ที่แอป/worker เรียกอยู่คงชื่อ+signature; ของใหม่เป็น shim
- `verify_scope` shadow ยังถูกอัปเดตเหมือนเดิมจนกว่า owner editor รุ่นเก่าจะเลิกใช้
- ระหว่าง P6 ทั้งสองเส้นทาง (legacy/generic) ต้องไม่ประมวลผล attempt เดียวกันพร้อมกัน (advisory lock + claim-next)
- ถ้าแกนกลางล่ม Sports ต้องยังทำงานได้: worker generic ที่ error ไม่ block legacy; attempt ตก owner review ไม่ใช่ปล่อย hold

### 7.2 ต่อส่วนอื่นของ Sheserved

| ส่วนที่เสี่ยง | มาตรการ |
|---|---|
| Auth/middleware กลาง | ไม่แตะ `strictRouteGuard`/`verifyToken`/ลำดับ middleware; เพิ่ม guard test ว่า route ใหม่ไม่ผ่อน auth |
| `server.js` startup | service ใหม่ start หลัง env validation และใช้ `unref()` timers; ถ้า env ไม่ครบ → log แล้วไม่ start (ไม่ throw) |
| DB performance | ตารางใหม่มี index เฉพาะที่ใช้ (`state, created_at`), partial index สำหรับ `state='queued'`; query ของระบบอื่นไม่ถูกแตะ |
| RLS/permission | ตารางใหม่ `ENABLE ROW LEVEL SECURITY` + `REVOKE ALL` จาก `anon, authenticated`; เข้าถึงผ่าน RPC เท่านั้น |
| Cost ของ provider | quota ต่อ scope + platform budget; provider ที่ไม่พร้อมถูกกรองออก; cost เป็น estimate ชัดเจนใน UI |
| Storage | bucket เดียว private, namespace path ต่อ domain; ห้ามเปิด direct upload กลับมาไม่ว่ากรณีใด |
| ข้อมูลผู้ใช้ | P2.b ปิด raw trans-ref; retention ต้องมี sign-off ก่อน P7 |
| Test suite ของทีมอื่น | ไม่ลบ/แก้ test เดิม; test ใหม่แยกไฟล์ |

### 7.3 สิ่งที่ห้ามทำ (hard no)

1. ห้าม `EXECUTE` ชื่อฟังก์ชันที่มาจากค่าที่ admin แก้ได้
2. ห้าม auto-failover ระหว่าง provider ในเวอร์ชันนี้ (D6)
3. ห้ามลบ/แก้ข้อมูล booking, payment claim, refund เพื่อ "ทำให้ migration ผ่าน"
4. ห้ามรัน smoke test บน production/shared project (ต้อง scratch DB)
5. ห้ามรวม P3 (refactor) / P5 (core) / P6 (cutover) ใน PR เดียว และห้ามรวมหลายข้อย่อยของ P2 ใน PR/migration เดียว
6. ห้าม enforce กติกาที่อาจปฏิเสธสลิปจริง (P2.a) ก่อนผ่านโหมด observe
7. ห้ามขยาย whitelist (เกิน venue ทดสอบ) หรือเปิด `verify_scope = 'all'` ก่อน **P2.a/b/c เสร็จ + P2.f ตั้ง cap/budget แล้ว** (เดิมผูกกับ cutover ซึ่งอาจไม่เกิดขึ้น — เงื่อนไขใหม่ผูกกับความถูกต้องจริง)
8. ห้ามเริ่ม P5 โดยไม่ผ่าน D1 และห้ามเริ่ม P6 โดยไม่ผ่าน D2
9. ห้ามเก็บ/พิมพ์เลขธุรกรรม เลขบัญชี หรือ key ดิบลง DB/log/PR/ภาพหน้าจอ
10. ห้ามเปิด direct upload ของ client กลับมาไม่ว่ากรณีใด

---

## 8. ความเสี่ยงและมาตรการ

| ความเสี่ยง | โอกาส | ผลกระทบ | มาตรการ | ตรวจจับด้วย |
|---|---|---|---|---|
| **สลิปโอนผิดบัญชี/สลิปเก่าผ่านอัตโนมัติ (R9)** | กลาง (มีอยู่จริงวันนี้) | สูงมาก | P2.a ตรวจผู้รับ+เวลา, observe→enforce, `unknown` ไป owner review | P1.a (ล็อกช่องโหว่ไว้เป็น test), P2 gate ข้อ 3 |
| Receiver check ปฏิเสธสลิปจริง (false mismatch) | กลาง | กลาง | observe ก่อน enforce; mismatch = `pending` ไม่ใช่ reject; ปิดโหมดได้ทันทีไม่ต้อง deploy | P2.a เกณฑ์เปลี่ยนโหมด |
| Refactor ทำพฤติกรรมเปลี่ยนเงียบ ๆ | กลาง | สูง | P1.a characterization + payload diff | P3 gate |
| provider call ซ้ำ = เสียเงินซ้ำ (R4) | กลาง | กลาง | P2.c state machine | P2 gate ข้อ 5 |
| ผล verified หายเมื่อ stale (R10) | ต่ำ-กลาง | สูง (เงินจริง) | P2.d บันทึก dedup + verified_stale + แจ้ง | P2.d test |
| Privacy รั่วเลขธุรกรรม (R1/R2) | กลาง | สูง | P2.b + backfill; ห้าม log ค่าดิบ | P2 gate ข้อ 4 |
| HMAC key หาย/รั่ว | ต่ำ | สูง | secret store, version, ไม่ลบ key เก่า, สำรองนอกเครื่อง; ถ้า key หาย → dedup history ใช้ไม่ได้ ต้องมี runbook ให้ owner review ทุกใบจนกว่าจะตั้ง V ใหม่ | runbook §9 [F] |
| Backfill ผิดพลาด (P2.b) | ต่ำ | สูง | PITR snapshot + dry-run + worker หยุด + ตรวจนับ + ซ้อมบน scratch | P2.b gate |
| Admin เลือก provider ที่ไม่มี adapter (R5) | **สูง (ผิดได้วันนี้)** | กลาง | P0.2 + บล็อกใน P4.3 | P0 gate ข้อ 1 |
| SSRF/egress (R6) | ต่ำ-กลาง | สูง | P0.3 allowlist + DNS check | P0 gate ข้อ 2 |
| ค่าใช้จ่ายเกิน / โควตา account หมดทุก venue พร้อมกัน (R11) | กลาง | กลาง | P2.f provider cap + platform budget + แสดงเป็นประมาณการ | metric + audit |
| Provider ล่มยาว → worker ติดคิว/owner ถูกท่วม | กลาง | กลาง | circuit breaker + ข้อความชัดใน owner queue + heartbeat | P1.d, P2.f |
| Worker ตายเงียบ (R12) | กลาง | กลาง | heartbeat + ตัวตรวจคิวค้าง | P1.d |
| PDPA/ข้ามพรมแดนเมื่อเพิ่ม provider (R13) | กลาง | สูง | P4.8 onboarding checklist + D7/D10 | checklist เป็น gate ของ `adapter_code` ใหม่ |
| Migration พังบนข้อมูลจริง | ต่ำ | สูง | rollback script คู่ทุก migration, ทดสอบบน dump, ordering test | gate ที่แตะ migration |
| ไม่มี staging | **สูง (เป็นจริงวันนี้)** | กลาง | D9 + reduced-drill mode + snapshot | P0.5 |
| สร้างแกนกลางโดยไม่มี domain ที่สอง (scope creep) | กลาง | กลาง | D1 gate; จุดหยุดที่ P4 | ทบทวนก่อน P5 |
| Mirror row ถูก claim ซ้ำข้าม path (P6) | กลาง | สูง | คอลัมน์ `path` ตั้งตอนสร้าง + filter ทั้งสอง worker + lock | P6 gate (นับ call_started ต่อ attempt) |
| Cutover ขณะมี attempt in-flight (P6) | กลาง | สูง | precondition คิวว่าง + กติกา P6.d + drill บังคับ | P6.f checklist |
| Env override `FORCE_LEGACY` ถูกลืมเปิดค้าง | ต่ำ | กลาง | log ชัด + ตรวจใน observation window + audit | P6.g |
| สลิปจริงสำหรับทดสอบหมดโควตา provider | ต่ำ | ต่ำ-กลาง | งบ §6.2 + ใช้ fake provider เป็นหลัก | ตาราง §6.2 |

---

## 9. Rollback playbook (ใช้ได้จริงหน้างาน)

```
[A] สลิปไม่ถูกตรวจแต่ควรถูกตรวจ / ตรวจผิด
    1) ตรวจ metric: queue age, skip reason, provider outcome
    2) ถ้าอยู่ P6: `admin_set_verification_core_path('sports_booking', false)` (DB flag — ไม่ต้อง deploy) → generic เข้า drain-only → รอ 1 รอบ polling (15s) → ยืนยันใบใหม่ผ่าน legacy
    3) ถ้ายังผิด: ปิด provider ใน registry → ใบใหม่ตก owner review (ปลอดภัย)
    4) เปิด provider กลับเมื่อแก้เสร็จ; ใบที่ตก review ให้ owner ตัดสินตามปกติ

[B] ค่าใช้จ่ายพุ่งผิดปกติ
    1) ตั้ง scope=whitelist / ปิด allowlist ของ venue ที่ไม่ต้องใช้
    2) ลด verify_monthly_quota เป็น 0 (เท่ากับปิดการเรียก provider ของ scope นั้น)
    3) ปิด provider ที่สงสัยใน registry
    4) ตรวจ verification_admin_audit + verification_requests ที่ provider_code นั้น

[C] ระบบจองสนามผิดปกติหลัง deploy
    1) ถ้าอยู่ P6: flip DB flag กลับ legacy ก่อน (admin_set_verification_core_path → false)
       แล้วจึงพิจารณาหยุด worker — ห้ามหยุด worker ทั้งคู่ก่อน flip เพราะคิวจะค้าง
    2) ปิด SLIP_VERIFICATION_WORKER_ENABLED (หยุดทั้ง legacy/generic) เมื่อ flip แล้ว
    3) ยืนยันว่าการจองแบบไม่มี evidence policy ยังทำงาน (legacy per-slot flow)
    4) revert commit ของ phase ล่าสุด (P3 refactor ไม่มี migration → revert ได้ตรง; P0/P1/P2/P4 มี migration — ใช้ rollback script)
    5) ถ้าเป็น P0/P1/P4: migration เป็น additive → ปิด feature ไม่ต้องย้อน schema
    6) เปิด owner_review ให้เจ้าของตรวจเองระหว่างซ่อม (ไม่มีค่าใช้จ่าย)
    7) attempt ค้างทั้งสอง path: settle เป็น unavailable + owner review ตาม P0.4/P6.d

[D] ต้องย้อน migration
    - P0/P1/P2(ยกเว้น P2.b)/P4/P5 = additive → ห้าม drop ทันทีถ้ามีข้อมูล; ให้ปิดการใช้งานก่อน
    - ข้อมูลในตารางใหม่ไม่ใช่ source of truth ของ booking → ลบได้หลังยืนยันว่าไม่มีใครอ่าน
    - ห้ามลบ slip_verification_transactions (dedup ledger) — ถ้าลบจะเปิดช่องใช้สลิปซ้ำ

[E] สลิปจริงถูกปฏิเสธ/ตกเป็น pending มากผิดปกติหลังเปิด P2.a enforce
    1) ตั้ง receiver_check_mode = 'observe' (ไม่ต้อง deploy) → verdict กลับเหมือนก่อน enforce
    2) ตรวจ provider_meta (receiverMatch/slipAgeOk) ของใบที่ตก เพื่อหา pattern ของ normalizer ที่ผิด
    3) แก้ normalizer + เพิ่มเคสใน test → กลับ observe ซ้ำจนผ่านเกณฑ์ก่อน enforce อีกครั้ง
    (ใบที่ตก pending ให้ owner ตัดสินตามปกติ — ไม่มีใบไหนถูก forfeit เพราะกติกานี้เพียงอย่างเดียว)

[F] ต้องย้อน/กู้ P2.b หรือ HMAC key หาย
    - backfill ผิดพลาด: หยุด worker → กู้จาก PITR snapshot ที่ถ่ายก่อนเริ่ม (ยืนยันแล้วใน gate) → ตรวจนับ → แก้ script → dry-run ใหม่
    - HMAC key หาย/รั่ว: ตั้ง K ใหม่เป็นเวอร์ชันถัดไป; dedup ของใบเก่า (key เดิม) ใช้ไม่ได้ → **ระหว่างนั้นให้ทุกใบตก owner review** (ตั้ง scope=disabled ชั่วคราว) จนกว่าจะตัดสินใจเรื่องช่องว่างของ dedup history
    - ห้ามลบ key เวอร์ชันเก่าจาก secret store แม้ rotate แล้ว
```

---

## 10. นิยามเสร็จ (Definition of Done) ของแผนนี้

**ช่วง A (คุ้มค่าแม้มีระบบเดียว):**
- [ ] P0: key ถูก rotate และ key เก่าเพิกถอนแล้ว; provider ไม่มี adapter enable ไม่ได้; host allowlist ทำงาน; audit ทำงาน; เอกสาร/วันที่แก้แล้ว; live smoke ผ่าน
- [ ] P1: characterization + contract + concurrency tests ครบและนิ่ง; heartbeat/metrics/ตัวตรวจคิวค้างทำงาน
- [ ] P2.a: ตรวจผู้รับ+เวลา **enforce** แล้วหลังผ่าน observe; โอนผิดบัญชีไม่ผ่านอัตโนมัติ
- [ ] P2.b: ไม่มี raw ref ใน DB/log; dedup history คงอยู่; key สำรองแล้ว
- [ ] P2.c–f: ไม่ยิง provider ซ้ำ; ผล stale ไม่หาย; claim-next; provider cap + platform budget + circuit breaker ทำงาน
- [ ] P3: โค้ดแยกชั้น พฤติกรรมเหมือนเดิม (payload diff ผ่าน) ไม่มี migration
- [ ] P4: สลับ provider รายระบบผ่าน UI ได้ เลือกผิดไม่ได้ + onboarding checklist ใช้ได้จริง
- [ ] **ถ้า D1 ไม่ผ่าน: แผนนี้ถือว่าเสร็จที่นี่** และบันทึกเหตุผลใน §11

**ช่วง B (เมื่อผ่าน D1):**
- [ ] P5: แกนกลาง + shadow parity 0 mismatch
- [ ] P6 (ถ้า D2 ผ่าน): Sports บนแกนกลางด้วย DB flag + ownership `path` + state-diff parity 0 + rollback drill (drain-only + re-cutover) ผ่าน + observation window 24 ชม.ผ่าน + ไม่มี provider call ซ้ำ
- [ ] P7: domain ที่สอง pilot ผ่าน ไม่มี cross-domain leakage
- [ ] P8: shim/mirror ถูกเก็บกวาดโดยไม่เสีย audit/fingerprint
- [ ] เอกสาร: `Match_Sport_PLAN.md` และ `AGENTS.md` อัปเดตตรงกับเส้นทางใหม่

---

## 11. จุดที่รอตัดสินใจ — ข้อเสนอและสถานะ

**สถานะ:** ✅ = ตัดสินตามข้อเสนอ (เปลี่ยนได้ถ้ามีเหตุผล) · ❓ = **ต้องการคำตอบจากเจ้าของระบบ** (บล็อก phase ที่ระบุ)

| # | หัวข้อ | ข้อเสนอ + เหตุผล | สถานะ | บล็อก |
|---|---|---|---|---|
| D0 | วันที่ใน runbook ไม่สอดคล้อง (เดิม Q1) | เครื่องรายงาน 2026-10-07 → `2026-10-15` เป็นความผิดพลาดของผู้เขียนรอบก่อน แก้ใน P0.6 | ✅ แก้แล้ว | — |
| D1 | มีระบบที่สองจริงไหม | ใช้เป็น gate (§5.3) ไม่ลงมือสร้างแกนกลางแบบเดา | ❓ | P5 |
| D2 | ย้าย Sports เข้าแกนกลางจริงไหม | ตัดสินตอน P5 เสร็จ จากกำหนด launch ของ domain ที่สอง; ถ้าไม่ย้าย ยอมรับสองเส้นทางโดยมีเจ้าของ | ❓ (ตัดสินภายหลัง) | P6 |
| D3 | Dedup ข้าม domain | **global:** unique เดียวบน HMAC ที่มี provider-namespace (สลิปเป็นเหตุการณ์โอนจริงหนึ่งครั้ง ไม่ควรถูกใช้ซ้ำข้ามระบบ); เริ่มแบบ global ตั้งแต่ P2.b เพราะตอนนี้มีระบบเดียว ต้นทุนศูนย์ — เปลี่ยนทีหลังยากกว่า; ตอบผู้ใช้เพียง "สลิปนี้ถูกใช้แล้ว" ไม่บอกที่ใช้; HMAC key policy ตาม P2.b | ✅ (ระยะเวลาเก็บ fingerprint รอ D7) | — |
| D4 | Bucket | bucket เดียว + prefix; Sports คง `groups/<id>/…` ไม่เปลี่ยน; domain ใหม่ใช้ `d/<domain>/…`; แยก lifecycle ที่ sweeper ตาม prefix | ✅ | — |
| D5 | Cost bearer | คง enum `platform`/`owner` (CHECK เดิม) — "owner" = เจ้าของ scope ของ domain นั้น, label ใน UI ตาม domain; ไม่เพิ่มค่าใหม่ | ✅ | — |
| D6 | Retry/failover | **ไม่ retry อัตโนมัติหลังยิงแล้ว และไม่ failover** — timeout ≠ provider ไม่ได้รับคำขอ (เสี่ยงคิดเงินซ้ำ); ล้ม = owner review | ✅ | — |
| D7 | Retention + DPA | ต้องให้ legal/data-governance ตัดสิน: ระยะเก็บ (ก) ภาพสลิป (ข) fingerprint (ค) audit; DPA/ที่ตั้งข้อมูลของ provider; **ระหว่างรอ: ไม่ขยายเกิน venue ทดสอบ และไม่เพิ่ม provider ตัวที่สอง** | ❓ | ขยาย whitelist, P4.8 (provider ใหม่) |
| D8 | Platform budget | ผู้ตั้งค่า = admin Sheserved; ตั้งเพดานรายเดือน (บาท) + เตือนที่ 80%; **ค่าเริ่มต้น = ไม่ขยาย whitelist จนกว่าจะตั้ง**; ต้องระบุผู้อนุมัติงบ | ❓ | ขยาย whitelist, scope=`all` |
| D9 | Staging | เครื่องนี้ไม่มี docker/`config.toml` → local Supabase รันไม่ได้; **ข้อเสนอ: สร้าง Supabase project ที่สอง (staging) + Node staging (`Caddyfile.staging` มีอยู่แล้ว)**; ถ้าไม่ทำ → reduced-drill mode (§6.2) ใช้ได้กับ P0–P4 แต่ **ห้ามใช้กับ P6** | ❓ | P2.b ซ้อมบน scratch, P6 |
| D10 | provider ตัวที่สอง | ระบุชื่อ provider/ผู้ติดต่อ/ราคา/ที่ตั้งข้อมูล ก่อนเริ่ม P4.8; ไม่ระบุ → P4 ใช้ fake provider เป็นหลักฐานว่าสลับได้ | ❓ | P4.8 |
| D11 | เจ้าของปฏิบัติการ | ระบุผู้ดำเนินการ cutover/rollback (หนึ่งคน), ช่องทางแจ้งเตือนเมื่อคิวค้าง/งบเกิน/worker ตาย | ❓ | P1.d, P6 |
| D12 | P2.d จะ surface "verified_stale" ที่ owner queue อย่างไร | เสนอ: แสดงเป็นแถบเตือนในหน้า payment-claim ของ group นั้น + แจ้ง admin; ไม่คืนเงิน/ไม่ยืนยัน booking อัตโนมัติ | ❓ (UX/ธุรกิจ) | P2.d |

**ลำดับที่ควรตอบ:** D9, D8, D7 → ปลดล็อกการทำงานช่วง A อย่างปลอดภัย; D10/D11 ก่อนเริ่ม P4; D1/D2 ค่อยตัดสินเมื่อถึงเวลา

---

## 12. ความสัมพันธ์กับแผนอื่น

| แผน | ความสัมพันธ์ |
|---|---|
| `Match_Sport_PLAN.md` 21.7.21 | ระบบต้นทาง; แผนนี้ต้องไม่เปลี่ยน acceptance ของ 21.7.21 และต้องอัปเดต cross-link เมื่อ P2 และ P4 เสร็จ (และ P6 ถ้ามี) |
| `Delivery_PLAN.md` (POD) | ผู้ใช้ที่มีศักยภาพของแกนกลาง (หลักฐานการส่ง) — ยังไม่ยืนยัน |
| `DONATION_SYSTEM_PLAN.md` | ผู้ใช้ที่มีศักยภาพ (หลักฐานโอนบริจาค) — ยังไม่ยืนยัน |
| `AGENTS.md` | เพิ่มหัวข้อ "Shared verification core" ใน P0.6 (คำสั่ง verify, env ที่เพิ่ม, ลำดับ deploy Node-ก่อน-migration) |

---

## 13. ลำดับเริ่มงานที่แนะนำ (ตาม dependency ไม่ใช่ระยะเวลา)

```
เริ่มได้ทันที (ไม่ต้องรอคำตอบ):  P0.1 rotate key · P0.2 adapter readiness · P0.3 SSRF allowlist · P0.4 audit · P0.6 แก้เอกสาร
ต้องตอบ D9 ก่อน:               P0.5 staging/reduced-drill → เข้า P1/P2
P1 ทั้งหมด                       ← ก่อนข้อย่อยใดของ P2
P2.a (observe) → P2.b → P2.c → P2.d (ต้อง D12) → P2.e → P2.f → P2.a (enforce)
ก่อนขยาย whitelist:             P2.a/b/c เสร็จ + P2.f ตั้ง cap/budget (D8) + D7
P3 → P4 (ต้อง D10/D11) ──► D1
ถ้า D1 ผ่าน: P5 → D2 → P6 → P7 → P8
```

**จุดหยุดและประเมินใหม่:** ก่อนเริ่ม P2 (P1 gate ต้องเขียวนิ่ง), ก่อนเปิด `enforce` ของ P2.a, ก่อน P2.b (ต้องมี snapshot), ก่อน D1, ก่อน D2/P6 (ต้องมี rollback drill ผ่านบน scratch), ก่อน P8 (ต้องมั่นใจว่าไม่มี client รุ่นเก่า)

**สิ่งที่ทำได้ทันทีและคุ้มที่สุด:** P0.1 (ปิดความเสี่ยง key รั่ว) และ P0.2 (UI วันนี้เพิ่ม provider ที่ไม่มี adapter ได้) — ทั้งสองไม่เปลี่ยนพฤติกรรมของสลิปที่ผ่านอยู่
