-- Sports Hub — one-time evidence upload grants + orphan cleanup
--
-- Closes the direct-upload gap: previously any authenticated client could
-- INSERT arbitrary objects into the private `booking-evidence` bucket and
-- only the commit RPC checked the path prefix afterwards. Uploads now go
-- through the Node gateway which redeems a single-use grant, validates
-- magic bytes, decodes/re-encodes the image (stripping EXIF/GPS), then
-- writes the sanitized object with the service role.
--
-- The bucket's permissive INSERT policy is dropped: clients no longer
-- write storage objects at all. The service-role gateway bypasses RLS.

-- ===============
-- Upload intents (one-time grants)
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_evidence_upload_intents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash VARCHAR(64) NOT NULL UNIQUE,
  booking_group_id UUID NOT NULL
    REFERENCES public.sports_venue_booking_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  purpose VARCHAR(16) NOT NULL CHECK (purpose IN ('evidence', 'claim')),
  requirement_key VARCHAR(64),
  storage_path VARCHAR(500) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sports_venue_upload_intents_expiry
  ON public.sports_venue_evidence_upload_intents (expires_at);

ALTER TABLE public.sports_venue_evidence_upload_intents
  ENABLE ROW LEVEL SECURITY;
-- No policies: grants are minted and consumed through SECURITY DEFINER
-- RPCs only, same convention as the read-token table.

-- ===============
-- Grant mint: binds user + group + purpose + requirement to one
-- pre-assigned private path for 10 minutes.
-- ===============
CREATE OR REPLACE FUNCTION public.create_sports_venue_evidence_upload_grant(
  p_user_id UUID,
  p_booking_group_id UUID,
  p_purpose VARCHAR,
  p_requirement_key VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group RECORD;
  v_req JSONB;
  v_subdir VARCHAR;
  v_token VARCHAR;
  v_path VARCHAR;
  v_expires TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_purpose NOT IN ('evidence', 'claim') THEN
    RAISE EXCEPTION 'INVALID_PURPOSE';
  END IF;
  SELECT g.* INTO v_group
  FROM public.sports_venue_booking_groups g
  WHERE g.id = p_booking_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;
  IF v_group.user_id <> p_user_id THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  IF p_purpose = 'claim' THEN
    -- Mirror report_sports_venue_booking_payment_claim's status gate.
    IF v_group.status NOT IN (
      'forfeited', 'rejected', 'cancelled', 'expired', 'confirmed',
      'partially_cancelled', 'completed') THEN
      RAISE EXCEPTION 'GROUP_CLAIM_NOT_ALLOWED';
    END IF;
    v_subdir := 'claim';
  ELSE
    IF v_group.status NOT IN ('pending', 'awaiting_evidence') THEN
      RAISE EXCEPTION 'GROUP_NOT_OPEN';
    END IF;
    IF p_requirement_key IS NULL
       OR p_requirement_key !~ '^[a-zA-Z0-9_-]{1,64}$' THEN
      RAISE EXCEPTION 'REQUIREMENT_NOT_FOUND';
    END IF;
    SELECT r INTO v_req
    FROM jsonb_array_elements(
      COALESCE(v_group.evidence_policy_snapshot->'requirements', '[]'::jsonb)
    ) r
    WHERE r->>'key' = p_requirement_key;
    IF v_req IS NULL THEN
      RAISE EXCEPTION 'REQUIREMENT_NOT_FOUND';
    END IF;
    v_subdir := p_requirement_key;
  END IF;

  -- Opportunistic sweep of dead intents (bounded work).
  DELETE FROM public.sports_venue_evidence_upload_intents
  WHERE expires_at < now() - INTERVAL '1 day'
     OR used_at < now() - INTERVAL '1 day';

  -- Abuse bound: a booker cannot mint unlimited live grants per group.
  IF (SELECT count(*) FROM public.sports_venue_evidence_upload_intents i
      WHERE i.booking_group_id = v_group.id
        AND i.used_at IS NULL AND i.expires_at > now()) >= 10 THEN
    RAISE EXCEPTION 'TOO_MANY_UPLOADS';
  END IF;

  v_token := replace(
    gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_expires := now() + INTERVAL '10 minutes';
  v_path := 'groups/' || v_group.id::text || '/' || v_subdir || '/'
    || gen_random_uuid()::text || '.jpg';
  INSERT INTO public.sports_venue_evidence_upload_intents (
    token_hash, booking_group_id, user_id, purpose, requirement_key,
    storage_path, expires_at
  ) VALUES (
    md5(v_token), v_group.id, p_user_id, p_purpose,
    CASE WHEN p_purpose = 'evidence' THEN p_requirement_key END,
    v_path, v_expires
  );

  RETURN JSONB_BUILD_OBJECT(
    'token', v_token, 'path', v_path, 'expiresAt', v_expires);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_sports_venue_evidence_upload_grant(
  UUID, UUID, VARCHAR, VARCHAR
) TO anon, authenticated;

-- ===============
-- Grant consume: single-use, atomic. Service-role only — the Node
-- gateway redeems the token right before writing the sanitized object.
-- ===============
CREATE OR REPLACE FUNCTION public.consume_sports_venue_evidence_upload_grant(
  p_token_hash VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_intent RECORD;
BEGIN
  UPDATE public.sports_venue_evidence_upload_intents
  SET used_at = now()
  WHERE token_hash = p_token_hash
    AND used_at IS NULL
    AND expires_at > now()
  RETURNING * INTO v_intent;
  IF v_intent IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN JSONB_BUILD_OBJECT(
    'path', v_intent.storage_path,
    'groupId', v_intent.booking_group_id,
    'userId', v_intent.user_id,
    'purpose', v_intent.purpose,
    'requirementKey', v_intent.requirement_key);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.consume_sports_venue_evidence_upload_grant(
  VARCHAR
) FROM PUBLIC, anon, authenticated;

-- ===============
-- Orphan cleanup: purges dead intents and lists bucket objects that no
-- evidence row, claim, refund receipt, or live intent references. The
-- Node job deletes the returned paths via the storage API — SQL never
-- touches storage.objects directly so this is safe on scratch databases.
-- ===============
CREATE OR REPLACE FUNCTION public.cleanup_sports_venue_evidence_orphans(
  p_min_age INTERVAL DEFAULT INTERVAL '24 hours'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_intents INT;
  v_paths JSONB;
BEGIN
  DELETE FROM public.sports_venue_evidence_upload_intents
  WHERE expires_at < now() - INTERVAL '1 day'
     OR used_at < now() - INTERVAL '1 day';
  GET DIAGNOSTICS v_intents = ROW_COUNT;

  IF to_regclass('storage.objects') IS NULL THEN
    RETURN JSONB_BUILD_OBJECT('paths', '[]'::jsonb,
                              'intentsPurged', v_intents);
  END IF;

  EXECUTE $q$
    SELECT COALESCE(jsonb_agg(o.name), '[]'::jsonb)
    FROM storage.objects o
    WHERE o.bucket_id = 'booking-evidence'
      AND o.created_at < now() - $1
      AND o.name LIKE 'groups/%'
      AND NOT EXISTS (
        SELECT 1 FROM public.sports_venue_booking_evidence e
        WHERE e.storage_path = o.name)
      AND NOT EXISTS (
        SELECT 1 FROM public.sports_venue_booking_payment_claims cl
        WHERE cl.evidence_path = o.name)
      AND NOT EXISTS (
        SELECT 1 FROM public.sports_venue_booking_refund_cases rc
        WHERE rc.receipt_path = o.name)
      AND NOT EXISTS (
        SELECT 1 FROM public.sports_venue_evidence_upload_intents i
        WHERE i.storage_path = o.name
          AND i.used_at IS NULL AND i.expires_at > now())
  $q$ INTO v_paths USING p_min_age;

  RETURN JSONB_BUILD_OBJECT('paths', COALESCE(v_paths, '[]'::jsonb),
                            'intentsPurged', v_intents);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_sports_venue_evidence_orphans(
  INTERVAL
) FROM PUBLIC, anon, authenticated;

-- ===============
-- Fail closed: drop the permissive client INSERT policy on the bucket.
-- All writes now go through the Node gateway (service role, bypasses
-- RLS). Guarded for scratch databases without the storage schema.
-- ===============
DO $$
BEGIN
  IF to_regclass('storage.objects') IS NOT NULL THEN
    DROP POLICY IF EXISTS booking_evidence_insert ON storage.objects;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
