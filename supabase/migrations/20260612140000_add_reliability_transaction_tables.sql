-- Migration: ERP Phase 0 Extension — Reliability & Transaction Boundary Tables
-- Date: 2026-06-12
-- Prerequisites: Phase 0 reliability core (outbox_events, idempotency_keys, inbox_events, transaction_contexts)

-- ============================================================
-- 1. TRANSACTION AUDIT LOG (append-only change tracking)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.transaction_audit_log (
    id              BIGSERIAL PRIMARY KEY,
    table_name      TEXT NOT NULL,                       -- 'orders', 'inventory_reservations', 'payments'
    record_id       UUID NOT NULL,                      -- ID ของ record ที่ถูกเปลี่ยนแปลง
    action          TEXT NOT NULL                        -- 'INSERT', 'UPDATE', 'DELETE'
                      CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values      JSONB,                               -- ค่าก่อนเปลี่ยนแปลง (NULL สำหรับ INSERT)
    new_values      JSONB,                               -- ค่าหลังเปลี่ยนแปลง (NULL สำหรับ DELETE)
    actor_id        UUID REFERENCES public.users(id) ON DELETE SET NULL,
    actor_type      TEXT NOT NULL DEFAULT 'user'        -- 'user', 'system', 'worker', 'webhook'
                      CHECK (actor_type IN ('user', 'system', 'worker', 'webhook')),
    profession_id   UUID REFERENCES public.professions(id) ON DELETE SET NULL,
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    session_id      TEXT,                                -- สำหรับ trace request ข้าม service
    ip_address      INET,
    user_agent      TEXT,
    reason          TEXT,                                -- หมายเหตุการเปลี่ยนแปลง
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_table_record
    ON public.transaction_audit_log(table_name, record_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_profession
    ON public.transaction_audit_log(profession_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_session
    ON public.transaction_audit_log(session_id);
CREATE INDEX IF NOT EXISTS idx_audit_created_at
    ON public.transaction_audit_log(created_at DESC);

-- ============================================================
-- 2. DEAD LETTER EVENTS (failed outbox / inbox events)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.dead_letter_events (
    id              BIGSERIAL PRIMARY KEY,
    source_table    TEXT NOT NULL,                       -- 'outbox_events' หรือ 'inbox_events'
    source_event_id BIGINT NOT NULL,
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    error_message   TEXT NOT NULL,
    retry_count     INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dead_letter_source
    ON public.dead_letter_events(source_table, source_event_id);
CREATE INDEX IF NOT EXISTS idx_dead_letter_created
    ON public.dead_letter_events(created_at DESC);

-- ============================================================
-- 3. CIRCUIT BREAKER STATES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.circuit_breaker_states (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id     UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    service_name      TEXT NOT NULL,                         -- 'payment_gateway', 'omise', 'promptpay_batch', 'supabase'
    circuit_state     TEXT NOT NULL DEFAULT 'closed'
                        CHECK (circuit_state IN ('closed', 'open', 'half_open')),
    failure_count     INTEGER NOT NULL DEFAULT 0,
    success_count     INTEGER NOT NULL DEFAULT 0,
    last_failure_at   TIMESTAMPTZ,
    last_success_at   TIMESTAMPTZ,
    opened_at         TIMESTAMPTZ,
    half_open_at      TIMESTAMPTZ,
    max_failures      INTEGER NOT NULL DEFAULT 5,
    reset_timeout_sec INTEGER NOT NULL DEFAULT 1800,         -- 30 นาที
    created_at        TIMESTAMPTZ DEFAULT NOW(),
    updated_at        TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, service_name)
);

CREATE INDEX IF NOT EXISTS idx_circuit_breaker_profession
    ON public.circuit_breaker_states(profession_id, service_name);
CREATE INDEX IF NOT EXISTS idx_circuit_breaker_state
    ON public.circuit_breaker_states(circuit_state, updated_at DESC);

DROP TRIGGER IF EXISTS trg_circuit_breaker_updated_at ON public.circuit_breaker_states;
CREATE TRIGGER trg_circuit_breaker_updated_at
    BEFORE UPDATE ON public.circuit_breaker_states
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 4. RETRY ATTEMPTS (cross-queue / cross-service)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.retry_attempts (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id     UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    operation_type    TEXT NOT NULL,                         -- 'payment_transfer', 'inventory_sync', 'email_send'
    target_id         UUID NOT NULL,                         -- ID ของ record ที่ถูก retry
    attempt_number    INTEGER NOT NULL DEFAULT 1,
    status            TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'success', 'permanent_failure')),
    error_message     TEXT,
    backoff_ms        INTEGER NOT NULL DEFAULT 2000,
    next_attempt_at   TIMESTAMPTZ,
    succeeded_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_retry_attempts_target
    ON public.retry_attempts(operation_type, target_id, attempt_number DESC);
CREATE INDEX IF NOT EXISTS idx_retry_attempts_next
    ON public.retry_attempts(status, next_attempt_at) WHERE status = 'pending';

-- ============================================================
-- 5. RATE LIMIT POLICIES (configuration + audit)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rate_limit_policies (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id     UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    endpoint_pattern  TEXT NOT NULL,                         -- '/api/orders', '/api/login'
    window_sec        INTEGER NOT NULL DEFAULT 60,
    max_requests      INTEGER NOT NULL DEFAULT 60,
    key_type          TEXT NOT NULL DEFAULT 'ip'
                        CHECK (key_type IN ('ip', 'user_id', 'api_key')),
    is_active         BOOLEAN DEFAULT true,
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_profession
    ON public.rate_limit_policies(profession_id, endpoint_pattern);

-- ============================================================
-- 6. QUEUE JOB AUDIT (BullMQ / background worker traceability)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.queue_job_audit (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id     UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    queue_name        TEXT NOT NULL,                         -- 'payment-transfers', 'donation-escrow', 'sync-queue'
    job_id            TEXT NOT NULL,                         -- BullMQ job ID
    job_name          TEXT NOT NULL,
    job_data          JSONB,
    status            TEXT NOT NULL
                        CHECK (status IN ('queued', 'processing', 'completed', 'failed', 'dead_letter')),
    attempts_made     INTEGER NOT NULL DEFAULT 0,
    error_message     TEXT,
    worker_host       TEXT,                                  -- hostname ของ worker
    started_at        TIMESTAMPTZ,
    completed_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_queue_job_audit_queue
    ON public.queue_job_audit(queue_name, status);
CREATE INDEX IF NOT EXISTS idx_queue_job_audit_profession
    ON public.queue_job_audit(profession_id, created_at DESC);

-- ============================================================
-- 7. DEAD LETTER RECORDS (formalized)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.dead_letter_records (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id     UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    source_queue      TEXT NOT NULL,                         -- ชื่อ queue ต้นทาง
    original_job_id   TEXT,
    aggregate_type    TEXT NOT NULL,                         -- 'order', 'payment', 'inventory'
    aggregate_id      UUID NOT NULL,
    event_type        TEXT NOT NULL,
    payload           JSONB NOT NULL,
    error_message     TEXT NOT NULL,
    retry_count       INTEGER NOT NULL DEFAULT 0,
    resolution        TEXT DEFAULT 'unresolved'
                        CHECK (resolution IN ('unresolved', 'manual_retry', 'compensated', 'ignored')),
    resolved_by       UUID REFERENCES public.users(id) ON DELETE SET NULL,
    resolved_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dead_letter_unresolved
    ON public.dead_letter_records(resolution, created_at) WHERE resolution = 'unresolved';
CREATE INDEX IF NOT EXISTS idx_dead_letter_aggregate
    ON public.dead_letter_records(aggregate_type, aggregate_id);

-- ============================================================
-- 8. RLS POLICIES
-- ============================================================
ALTER TABLE public.transaction_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dead_letter_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circuit_breaker_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.retry_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rate_limit_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.queue_job_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dead_letter_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_select" ON public.transaction_audit_log;
CREATE POLICY "audit_select" ON public.transaction_audit_log FOR SELECT USING (true);
DROP POLICY IF EXISTS "audit_modify" ON public.transaction_audit_log;
CREATE POLICY "audit_modify" ON public.transaction_audit_log FOR ALL USING (true);

DROP POLICY IF EXISTS "dead_letter_events_select" ON public.dead_letter_events;
CREATE POLICY "dead_letter_events_select" ON public.dead_letter_events FOR SELECT USING (true);
DROP POLICY IF EXISTS "dead_letter_events_modify" ON public.dead_letter_events;
CREATE POLICY "dead_letter_events_modify" ON public.dead_letter_events FOR ALL USING (true);

DROP POLICY IF EXISTS "circuit_breaker_select" ON public.circuit_breaker_states;
CREATE POLICY "circuit_breaker_select" ON public.circuit_breaker_states FOR SELECT USING (true);
DROP POLICY IF EXISTS "circuit_breaker_modify" ON public.circuit_breaker_states;
CREATE POLICY "circuit_breaker_modify" ON public.circuit_breaker_states FOR ALL USING (true);

DROP POLICY IF EXISTS "retry_attempts_select" ON public.retry_attempts;
CREATE POLICY "retry_attempts_select" ON public.retry_attempts FOR SELECT USING (true);
DROP POLICY IF EXISTS "retry_attempts_modify" ON public.retry_attempts;
CREATE POLICY "retry_attempts_modify" ON public.retry_attempts FOR ALL USING (true);

DROP POLICY IF EXISTS "rate_limit_select" ON public.rate_limit_policies;
CREATE POLICY "rate_limit_select" ON public.rate_limit_policies FOR SELECT USING (true);
DROP POLICY IF EXISTS "rate_limit_modify" ON public.rate_limit_policies;
CREATE POLICY "rate_limit_modify" ON public.rate_limit_policies FOR ALL USING (true);

DROP POLICY IF EXISTS "queue_job_select" ON public.queue_job_audit;
CREATE POLICY "queue_job_select" ON public.queue_job_audit FOR SELECT USING (true);
DROP POLICY IF EXISTS "queue_job_modify" ON public.queue_job_audit;
CREATE POLICY "queue_job_modify" ON public.queue_job_audit FOR ALL USING (true);

DROP POLICY IF EXISTS "dead_letter_records_select" ON public.dead_letter_records;
CREATE POLICY "dead_letter_records_select" ON public.dead_letter_records FOR SELECT USING (true);
DROP POLICY IF EXISTS "dead_letter_records_modify" ON public.dead_letter_records;
CREATE POLICY "dead_letter_records_modify" ON public.dead_letter_records FOR ALL USING (true);

-- ============================================================
-- 9. RPC FUNCTIONS
-- ============================================================

-- Record audit log entry
CREATE OR REPLACE FUNCTION record_audit_log(
    p_table_name TEXT,
    p_record_id UUID,
    p_action TEXT,
    p_old_values JSONB DEFAULT NULL,
    p_new_values JSONB DEFAULT NULL,
    p_actor_id UUID DEFAULT NULL,
    p_actor_type TEXT DEFAULT 'user',
    p_profession_id UUID DEFAULT NULL,
    p_branch_id UUID DEFAULT NULL,
    p_session_id TEXT DEFAULT NULL,
    p_reason TEXT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO public.transaction_audit_log (
        table_name, record_id, action, old_values, new_values,
        actor_id, actor_type, profession_id, branch_id, session_id, reason
    )
    VALUES (
        p_table_name, p_record_id, p_action, p_old_values, p_new_values,
        p_actor_id, p_actor_type, p_profession_id, p_branch_id, p_session_id, p_reason
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update circuit breaker state
CREATE OR REPLACE FUNCTION update_circuit_breaker(
    p_profession_id UUID,
    p_service_name TEXT,
    p_result TEXT -- 'success' or 'failure'
)
RETURNS TEXT AS $$
DECLARE
    v_state public.circuit_breaker_states%ROWTYPE;
    v_new_state TEXT;
BEGIN
    SELECT * INTO v_state
    FROM public.circuit_breaker_states
    WHERE profession_id = p_profession_id AND service_name = p_service_name;

    IF v_state.id IS NULL THEN
        INSERT INTO public.circuit_breaker_states (
            profession_id, service_name,
            failure_count, success_count,
            last_success_at, last_failure_at
        )
        VALUES (
            p_profession_id, p_service_name,
            CASE WHEN p_result = 'failure' THEN 1 ELSE 0 END,
            CASE WHEN p_result = 'success' THEN 1 ELSE 0 END,
            CASE WHEN p_result = 'success' THEN NOW() END,
            CASE WHEN p_result = 'failure' THEN NOW() END
        )
        RETURNING * INTO v_state;
        RETURN v_state.circuit_state;
    END IF;

    -- State machine
    IF v_state.circuit_state = 'closed' THEN
        IF p_result = 'failure' THEN
            v_state.failure_count := v_state.failure_count + 1;
            v_state.last_failure_at := NOW();
            IF v_state.failure_count >= v_state.max_failures THEN
                v_state.circuit_state := 'open';
                v_state.opened_at := NOW();
            END IF;
        ELSE
            v_state.failure_count := 0;
            v_state.success_count := v_state.success_count + 1;
            v_state.last_success_at := NOW();
        END IF;
    ELSIF v_state.circuit_state = 'open' THEN
        IF v_state.opened_at + (v_state.reset_timeout_sec || ' seconds')::INTERVAL <= NOW() THEN
            v_state.circuit_state := 'half_open';
            v_state.half_open_at := NOW();
            v_state.failure_count := 0;
            v_state.success_count := 0;
        END IF;
        -- In open state, still record failure but don't change state
        IF p_result = 'failure' THEN
            v_state.last_failure_at := NOW();
        END IF;
    ELSIF v_state.circuit_state = 'half_open' THEN
        IF p_result = 'failure' THEN
            v_state.circuit_state := 'open';
            v_state.opened_at := NOW();
            v_state.failure_count := v_state.failure_count + 1;
            v_state.last_failure_at := NOW();
        ELSE
            v_state.success_count := v_state.success_count + 1;
            v_state.last_success_at := NOW();
            IF v_state.success_count >= 3 THEN
                v_state.circuit_state := 'closed';
                v_state.failure_count := 0;
            END IF;
        END IF;
    END IF;

    UPDATE public.circuit_breaker_states
    SET circuit_state = v_state.circuit_state,
        failure_count = v_state.failure_count,
        success_count = v_state.success_count,
        last_failure_at = v_state.last_failure_at,
        last_success_at = v_state.last_success_at,
        opened_at = v_state.opened_at,
        half_open_at = v_state.half_open_at,
        updated_at = NOW()
    WHERE id = v_state.id;

    RETURN v_state.circuit_state;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create retry attempt
CREATE OR REPLACE FUNCTION create_retry_attempt(
    p_profession_id UUID,
    p_operation_type TEXT,
    p_target_id UUID,
    p_backoff_ms INTEGER DEFAULT 2000
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_last_attempt INTEGER;
BEGIN
    SELECT COALESCE(MAX(attempt_number), 0) INTO v_last_attempt
    FROM public.retry_attempts
    WHERE profession_id = p_profession_id
      AND operation_type = p_operation_type
      AND target_id = p_target_id;

    INSERT INTO public.retry_attempts (
        profession_id, operation_type, target_id,
        attempt_number, backoff_ms, next_attempt_at
    )
    VALUES (
        p_profession_id, p_operation_type, p_target_id,
        v_last_attempt + 1, p_backoff_ms, NOW() + (p_backoff_ms || ' milliseconds')::INTERVAL
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Resolve dead letter record
CREATE OR REPLACE FUNCTION resolve_dead_letter(
    p_dead_letter_id UUID,
    p_resolution TEXT,
    p_resolved_by UUID DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.dead_letter_records
    SET resolution = p_resolution,
        resolved_by = p_resolved_by,
        resolved_at = NOW()
    WHERE id = p_dead_letter_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
