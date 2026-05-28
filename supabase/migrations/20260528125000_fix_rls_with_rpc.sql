-- Fix: RLS blocks provider from INSERT/UPDATE into consultation_room_experts
-- Solution: Use SECURITY DEFINER RPC functions that bypass RLS

-- 1. RPC to ensure consultation_room_experts rows exist from package data
CREATE OR REPLACE FUNCTION public.ensure_room_experts(
  p_consultation_id UUID,
  p_package_id TEXT,
  p_room_id TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_expert_groups JSONB;
  v_group JSONB;
  v_count INT;
BEGIN
  -- Check if rows already exist
  SELECT COUNT(*) INTO v_count
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id;

  IF v_count > 0 THEN
    RETURN;
  END IF;

  -- Get expert_groups from package
  SELECT expert_groups INTO v_expert_groups
  FROM public.consultation_packages
  WHERE id = p_package_id;

  IF v_expert_groups IS NOT NULL AND jsonb_typeof(v_expert_groups) = 'array' THEN
    FOR v_group IN SELECT * FROM jsonb_array_elements(v_expert_groups)
    LOOP
      INSERT INTO public.consultation_room_experts (
        consultation_id, room_id, expert_group_id, expert_group_name,
        expert_group_role, max_experts, is_required, status
      ) VALUES (
        p_consultation_id, p_room_id,
        v_group->>'id',
        v_group->>'name',
        v_group->>'role',
        COALESCE((v_group->>'maxExperts')::INT, 1),
        COALESCE((v_group->>'isRequired')::BOOLEAN, false),
        'waiting'
      );
    END LOOP;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. RPC to sync provider into consultation_room_experts after legacy assignProvider
CREATE OR REPLACE FUNCTION public.sync_provider_to_room_experts(
  p_consultation_id UUID,
  p_provider_id UUID,
  p_profession_id UUID DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_package_id TEXT;
  v_room_id TEXT;
  v_expert_groups JSONB;
  v_group JSONB;
  v_provider_role TEXT := 'doctor';
  v_profession_name TEXT;
  v_existing_rows INT;
  v_matched_row RECORD;
  v_waiting_row RECORD;
  v_matched_group JSONB;
BEGIN
  -- Get package_id and room_id from consultation
  SELECT package_id, room_id INTO v_package_id, v_room_id
  FROM public.consultation_requests
  WHERE id = p_consultation_id;

  IF v_package_id IS NULL THEN
    RETURN;
  END IF;

  -- Get profession name and map to role
  IF p_profession_id IS NOT NULL THEN
    SELECT name INTO v_profession_name
    FROM public.professions
    WHERE id = p_profession_id;

    IF v_profession_name IS NOT NULL THEN
      v_profession_name := lower(v_profession_name);
      IF v_profession_name LIKE '%เภสัช%' OR v_profession_name LIKE '%pharmacist%' THEN
        v_provider_role := 'pharmacist';
      ELSIF v_profession_name LIKE '%เฉพาะทาง%' OR v_profession_name LIKE '%specialist%' THEN
        v_provider_role := 'specialist';
      ELSIF v_profession_name LIKE '%อาจารย์%' OR v_profession_name LIKE '%professor%' THEN
        v_provider_role := 'professor';
      ELSIF v_profession_name LIKE '%หมอ%' OR v_profession_name LIKE '%แพทย์%' OR v_profession_name LIKE '%doctor%' THEN
        v_provider_role := 'doctor';
      END IF;
    END IF;
  END IF;

  -- Check existing rows
  SELECT COUNT(*) INTO v_existing_rows
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id;

  IF v_existing_rows > 0 THEN
    -- Try to match by role
    SELECT * INTO v_matched_row
    FROM public.consultation_room_experts
    WHERE consultation_id = p_consultation_id
      AND lower(expert_group_role) = lower(v_provider_role)
    LIMIT 1;

    IF FOUND THEN
      UPDATE public.consultation_room_experts
      SET provider_id = p_provider_id,
          status = 'joined',
          joined_at = now()
      WHERE id = v_matched_row.id;
      RETURN;
    END IF;

    -- Fallback: update first waiting row
    SELECT * INTO v_waiting_row
    FROM public.consultation_room_experts
    WHERE consultation_id = p_consultation_id
      AND status = 'waiting'
    ORDER BY id
    LIMIT 1;

    IF FOUND THEN
      UPDATE public.consultation_room_experts
      SET provider_id = p_provider_id,
          status = 'joined',
          joined_at = now()
      WHERE id = v_waiting_row.id;
      RETURN;
    END IF;
  ELSE
    -- No rows exist: insert from package
    SELECT expert_groups INTO v_expert_groups
    FROM public.consultation_packages
    WHERE id = v_package_id;

    IF v_expert_groups IS NOT NULL AND jsonb_typeof(v_expert_groups) = 'array' THEN
      FOR v_group IN SELECT * FROM jsonb_array_elements(v_expert_groups)
      LOOP
        IF lower(v_group->>'role') = lower(v_provider_role) THEN
          v_matched_group := v_group;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    IF v_matched_group IS NOT NULL THEN
      INSERT INTO public.consultation_room_experts (
        consultation_id, room_id, expert_group_id, expert_group_name,
        expert_group_role, max_experts, is_required, provider_id, status, joined_at
      ) VALUES (
        p_consultation_id, v_room_id,
        v_matched_group->>'id',
        v_matched_group->>'name',
        v_matched_group->>'role',
        COALESCE((v_matched_group->>'maxExperts')::INT, 1),
        COALESCE((v_matched_group->>'isRequired')::BOOLEAN, false),
        p_provider_id, 'joined', now()
      );
    ELSE
      INSERT INTO public.consultation_room_experts (
        consultation_id, room_id, expert_group_id, expert_group_name,
        expert_group_role, max_experts, is_required, provider_id, status, joined_at
      ) VALUES (
        p_consultation_id, v_room_id,
        'fallback_' || p_provider_id,
        'ผู้ให้คำปรึกษา',
        v_provider_role,
        1, true,
        p_provider_id, 'joined', now()
      );
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Relax RLS policies for INSERT/UPDATE using direct auth.uid() check
-- (RPC functions bypass RLS anyway, but keep policies for direct client access)

-- Drop old policies and create new ones
DO $$
BEGIN
  -- Insert policy: allow if user is patient or provider of the consultation
  DROP POLICY IF EXISTS allow_consultation_participants_insert
    ON public.consultation_room_experts;
  CREATE POLICY allow_consultation_participants_insert
    ON public.consultation_room_experts
    FOR INSERT
    TO authenticated
    WITH CHECK (
      consultation_id IN (
        SELECT id FROM public.consultation_requests
        WHERE user_id = auth.uid() OR provider_id = auth.uid()
      )
    );

  -- Update policy: allow if user is the assigned provider or the patient
  DROP POLICY IF EXISTS allow_consultation_participants_update
    ON public.consultation_room_experts;
  CREATE POLICY allow_consultation_participants_update
    ON public.consultation_room_experts
    FOR UPDATE
    TO authenticated
    USING (
      provider_id = auth.uid() OR
      consultation_id IN (
        SELECT id FROM public.consultation_requests
        WHERE user_id = auth.uid()
      )
    )
    WITH CHECK (
      provider_id = auth.uid() OR
      consultation_id IN (
        SELECT id FROM public.consultation_requests
        WHERE user_id = auth.uid()
      )
    );
END $$;
