-- Ensure trigger exists and RLS policies are complete
-- Problem: consultation_room_experts rows not created when new consultation is inserted
-- Cause: trigger binding may have been dropped; missing INSERT/UPDATE RLS policies

-- 1. Ensure function has SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.init_consultation_room_experts()
RETURNS TRIGGER AS $$
DECLARE
  v_expert_groups JSONB;
  v_group JSONB;
BEGIN
  SELECT expert_groups INTO v_expert_groups
  FROM public.consultation_packages
  WHERE id = NEW.package_id;

  IF v_expert_groups IS NOT NULL AND jsonb_typeof(v_expert_groups) = 'array' THEN
    FOR v_group IN SELECT * FROM jsonb_array_elements(v_expert_groups)
    LOOP
      INSERT INTO public.consultation_room_experts (
        consultation_id, room_id, expert_group_id, expert_group_name,
        expert_group_role, max_experts, is_required, status
      ) VALUES (
        NEW.id, NEW.room_id,
        v_group->>'id',
        v_group->>'name',
        v_group->>'role',
        COALESCE((v_group->>'maxExperts')::INT, 1),
        COALESCE((v_group->>'isRequired')::BOOLEAN, false),
        'waiting'
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Drop and recreate trigger to ensure it exists
DROP TRIGGER IF EXISTS on_consultation_request_created ON public.consultation_requests;
CREATE TRIGGER on_consultation_request_created
  AFTER INSERT ON public.consultation_requests
  FOR EACH ROW EXECUTE FUNCTION public.init_consultation_room_experts();

-- 3. Ensure RLS SELECT policy exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'consultation_room_experts'
      AND policyname = 'allow_consultation_participants_select'
  ) THEN
    CREATE POLICY allow_consultation_participants_select
      ON public.consultation_room_experts
      FOR SELECT
      TO authenticated
      USING (
        consultation_id IN (
          SELECT id FROM public.consultation_requests
          WHERE user_id = auth.uid()
             OR provider_id = auth.uid()
        )
      );
  END IF;
END $$;

-- 4. Ensure RLS INSERT policy exists (for syncProviderToRoomExperts fallback)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'consultation_room_experts'
      AND policyname = 'allow_consultation_participants_insert'
  ) THEN
    CREATE POLICY allow_consultation_participants_insert
      ON public.consultation_room_experts
      FOR INSERT
      TO authenticated
      WITH CHECK (
        consultation_id IN (
          SELECT id FROM public.consultation_requests
          WHERE user_id = auth.uid()
             OR provider_id = auth.uid()
        )
      );
  END IF;
END $$;

-- 5. Ensure RLS UPDATE policy exists (for syncProviderToRoomExperts)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'consultation_room_experts'
      AND policyname = 'allow_consultation_participants_update'
  ) THEN
    CREATE POLICY allow_consultation_participants_update
      ON public.consultation_room_experts
      FOR UPDATE
      TO authenticated
      USING (
        consultation_id IN (
          SELECT id FROM public.consultation_requests
          WHERE user_id = auth.uid()
             OR provider_id = auth.uid()
        )
      )
      WITH CHECK (
        consultation_id IN (
          SELECT id FROM public.consultation_requests
          WHERE user_id = auth.uid()
             OR provider_id = auth.uid()
        )
      );
  END IF;
END $$;
