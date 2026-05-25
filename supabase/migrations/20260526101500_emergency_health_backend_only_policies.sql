-- Tighten emergency health tables after moving reads/writes to backend service endpoints
-- Keeps the owner policies for compatibility, but removes the temporary public policies
-- that were only needed while the Flutter client wrote directly to Supabase.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_data_settings'
          AND policyname = 'Emergency settings public select'
    ) THEN
        DROP POLICY "Emergency settings public select" ON emergency_health_data_settings;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_data_settings'
          AND policyname = 'Emergency settings public insert'
    ) THEN
        DROP POLICY "Emergency settings public insert" ON emergency_health_data_settings;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_data_settings'
          AND policyname = 'Emergency settings public update'
    ) THEN
        DROP POLICY "Emergency settings public update" ON emergency_health_data_settings;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_dead_man_checkins'
          AND policyname = 'Dead man public select'
    ) THEN
        DROP POLICY "Dead man public select" ON emergency_health_dead_man_checkins;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_dead_man_checkins'
          AND policyname = 'Dead man public insert'
    ) THEN
        DROP POLICY "Dead man public insert" ON emergency_health_dead_man_checkins;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_dead_man_checkins'
          AND policyname = 'Dead man public update'
    ) THEN
        DROP POLICY "Dead man public update" ON emergency_health_dead_man_checkins;
    END IF;
END$$;
