-- Fitness Buddies: auto-reject expired pending bookings
-- Date: 2026-08-23
--
-- Phase 5 goal:
-- - Reject pending bookings automatically when they exceed the timeout window.
-- - Keep the database as the source of truth.
-- - Use pg_cron to schedule periodic cleanup.

CREATE OR REPLACE FUNCTION public.auto_reject_expired_fitness_bookings()
RETURNS INTEGER AS $$
DECLARE
  v_updated_count INTEGER := 0;
  v_booking RECORD;
  v_admin_ids UUID[];
  v_recipient_ids UUID[];
BEGIN
  FOR v_booking IN
    WITH updated AS (
      UPDATE public.fitness_group_bookings b
      SET
        status = 'rejected',
        cancelled_at = now(),
        cancelled_by = 'system',
        cancel_reason = 'AUTO_TIMEOUT'
      FROM public.fitness_group_sessions s
      WHERE b.session_id = s.id
        AND b.status = 'pending'
        AND (
          b.created_at <= now() - interval '24 hours'
          OR s.starts_at <= now() + interval '1 hour'
        )
      RETURNING
        b.id,
        b.user_id,
        b.session_id
    )
    SELECT
      u.id,
      u.user_id,
      u.session_id,
      s.group_id,
      COALESCE(g.name, 'Fitness Group') AS group_name,
      s.starts_at
    FROM updated u
    JOIN public.fitness_group_sessions s ON s.id = u.session_id
    LEFT JOIN public.fitness_groups g ON g.id = s.group_id
  LOOP
    SELECT COALESCE(array_agg(DISTINCT m.user_id), ARRAY[]::UUID[])
    INTO v_admin_ids
    FROM public.fitness_group_members m
    WHERE m.group_id = v_booking.group_id
      AND m.is_active = true
      AND m.role = 'admin';

    SELECT ARRAY(
      SELECT DISTINCT recipient_id
      FROM unnest(COALESCE(v_admin_ids, ARRAY[]::UUID[]) || ARRAY[v_booking.user_id]) AS recipient(recipient_id)
    ) INTO v_recipient_ids;

    PERFORM pg_notify(
      'fitness_booking_status_updates',
      jsonb_build_object(
        'bookingId', v_booking.id,
        'booking_id', v_booking.id,
        'sessionId', v_booking.session_id,
        'session_id', v_booking.session_id,
        'groupId', v_booking.group_id,
        'group_id', v_booking.group_id,
        'groupName', v_booking.group_name,
        'group_name', v_booking.group_name,
        'userId', v_booking.user_id,
        'user_id', v_booking.user_id,
        'status', 'rejected',
        'cancelledBy', 'system',
        'cancelled_by', 'system',
        'cancelReason', 'AUTO_TIMEOUT',
        'cancel_reason', 'AUTO_TIMEOUT',
        'reason', 'AUTO_TIMEOUT',
        'message', 'คำขอเข้าร่วมถูกยกเลิกอัตโนมัติเนื่องจากครบกำหนดอนุมัติ',
        'recipientUserIds', to_jsonb(v_recipient_ids),
        'recipient_user_ids', to_jsonb(v_recipient_ids),
        'updatedAt', now(),
        'updated_at', now()
      )::text
    );

    v_updated_count := v_updated_count + 1;
  END LOOP;

  RETURN v_updated_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END $$;

DO $$
DECLARE
  v_job_id BIGINT;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_namespace n
    WHERE n.nspname = 'cron'
  ) THEN
    SELECT jobid
    INTO v_job_id
    FROM cron.job
    WHERE jobname = 'fitness-buddies-auto-reject-expired-bookings'
    LIMIT 1;

    IF v_job_id IS NOT NULL THEN
      PERFORM cron.unschedule(v_job_id);
    END IF;

    PERFORM cron.schedule(
      'fitness-buddies-auto-reject-expired-bookings',
      '*/10 * * * *',
      $cron$SELECT public.auto_reject_expired_fitness_bookings();$cron$
    );
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
