-- Migration: Setup Chat System (Compatible with Deterministic IDs)
-- Date: 2026-02-26

-- 1. Create chat_rooms table with TEXT ID to support 'consult_xxxx' format
CREATE TABLE IF NOT EXISTS public.chat_rooms (
  id TEXT PRIMARY KEY, 
  participant_ids UUID[] NOT NULL,
  last_message TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Create chat_messages table
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  room_id TEXT NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.users(id),
  content TEXT NOT NULL,
  type TEXT DEFAULT 'text',
  attachment_url TEXT,
  attachment_type TEXT,
  read_by JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Enable Realtime
COMMIT;
BEGIN;
  -- Remove if already exists to avoid errors
  DO $$
  BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_rooms;
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
    END IF;
  END
  $$;
COMMIT;

-- 4. Row Level Security
ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- Dev Policy: Allow all for now
DROP POLICY IF EXISTS "Dev access chat_rooms" ON public.chat_rooms;
CREATE POLICY "Dev access chat_rooms" ON public.chat_rooms FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Dev access chat_messages" ON public.chat_messages;
CREATE POLICY "Dev access chat_messages" ON public.chat_messages FOR ALL USING (true) WITH CHECK (true);
