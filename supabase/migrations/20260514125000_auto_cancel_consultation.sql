-- Phase 4: History & Auto-Refund
-- 1. Create a function to cancel expired consultation requests
CREATE OR REPLACE FUNCTION public.cancel_expired_consultations()
RETURNS void AS $$
DECLARE
    expired_req RECORD;
BEGIN
    FOR expired_req IN
        SELECT cr.id, cr.user_id, cr.package_id, cp.expire_minutes
        FROM public.consultation_requests cr
        JOIN public.consultation_packages cp ON cr.package_id = cp.id
        WHERE cr.status = 'pending'
        AND cr.created_at + (cp.expire_minutes || ' minutes')::interval < NOW()
    LOOP
        -- 1. Update status to 'cancelled'
        UPDATE public.consultation_requests
        SET status = 'cancelled',
            updated_at = NOW()
        WHERE id = expired_req.id;
        
        -- 2. TODO: Implement Refund Logic
        -- e.g. Call Stripe/Omise API via Edge Function, or update internal wallet balance
        -- INSERT INTO public.refund_queue(request_id, amount, status) VALUES (expired_req.id, ...);
        
        -- 3. Optionally create a system message in the chat room to notify the patient
        -- that the consultation request has expired
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Setup pg_cron to run every 1 minute (Requires pg_cron extension enabled in Supabase)
-- WARNING: If pg_cron is not enabled, this block will fail. 
-- In Supabase dashboard, go to Database -> Extensions -> Enable pg_cron
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Unschedule if already exists to avoid duplicates
        PERFORM cron.unschedule('auto_cancel_consultations_job');
        
        -- Schedule the job to run every minute
        PERFORM cron.schedule(
            'auto_cancel_consultations_job',
            '* * * * *',
            'SELECT public.cancel_expired_consultations();'
        );
    ELSE
        RAISE NOTICE 'pg_cron extension is not enabled. Cannot schedule auto-cancel job.';
    END IF;
END
$$;
