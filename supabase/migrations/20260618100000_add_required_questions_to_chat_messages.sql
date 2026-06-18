-- Phase 6.7: Required Questions
-- Add columns to chat_messages for required question functionality

-- 1) Add is_required flag
ALTER TABLE public.chat_messages
ADD COLUMN IF NOT EXISTS is_required BOOLEAN DEFAULT false;

-- 2) Add required_status enum as TEXT
ALTER TABLE public.chat_messages
ADD COLUMN IF NOT EXISTS required_status TEXT;

-- 3) Add required_answer (patient's answer)
ALTER TABLE public.chat_messages
ADD COLUMN IF NOT EXISTS required_answer TEXT;

-- 4) Add required_answered_at timestamp
ALTER TABLE public.chat_messages
ADD COLUMN IF NOT EXISTS required_answered_at TIMESTAMP WITH TIME ZONE;

-- 5) Add required_owner_id (expert who created/edited the question)
ALTER TABLE public.chat_messages
ADD COLUMN IF NOT EXISTS required_owner_id UUID REFERENCES public.users(id);

-- 6) Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_chat_messages_is_required
ON public.chat_messages(is_required);

CREATE INDEX IF NOT EXISTS idx_chat_messages_required_status
ON public.chat_messages(required_status);

CREATE INDEX IF NOT EXISTS idx_chat_messages_room_required
ON public.chat_messages(room_id, is_required, required_status);

-- 7) Create required_question_edits table for edit history
CREATE TABLE IF NOT EXISTS public.required_question_edits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  previous_content TEXT NOT NULL,
  edited_by UUID NOT NULL REFERENCES public.users(id),
  edited_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 8) Add comments for documentation
COMMENT ON COLUMN public.chat_messages.is_required IS 'True if this message is a required question that must be answered';
COMMENT ON COLUMN public.chat_messages.required_status IS 'Status: unread | reading | answered';
COMMENT ON COLUMN public.chat_messages.required_answer IS 'Patient answer to the required question';
COMMENT ON COLUMN public.chat_messages.required_answered_at IS 'Timestamp when patient answered';
COMMENT ON COLUMN public.chat_messages.required_owner_id IS 'Expert who owns/last edited this required question';

-- 9) Update Realtime publication
BEGIN;
  DO $$
  BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.required_question_edits;
    END IF;
  END
  $$;
COMMIT;
