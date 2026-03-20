-- Create Chat Rooms table
CREATE TABLE chat_rooms (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  participant_ids UUID[] NOT NULL,
  last_message TEXT,
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create Chat Messages table
CREATE TABLE chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES auth.users(id),
  content TEXT NOT NULL,
  type TEXT DEFAULT 'text',
  attachment_url TEXT,
  attachment_type TEXT,
  read_by JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for searching rooms by participant
CREATE INDEX idx_chat_rooms_participants ON chat_rooms USING GIN (participant_ids);

-- Index for fetching messages by room
CREATE INDEX idx_chat_messages_room_id ON chat_messages(room_id);

-- Row Level Security (RLS)
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- Policies for chat_rooms
CREATE POLICY "Users can view their own rooms" 
ON chat_rooms FOR SELECT 
USING (auth.uid() = ANY(participant_ids));

-- Policies for chat_messages
CREATE POLICY "Users can view messages in their rooms" 
ON chat_messages FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM chat_rooms 
    WHERE id = chat_messages.room_id 
    AND auth.uid() = ANY(participant_ids)
  )
);

CREATE POLICY "Users can send messages to their rooms" 
ON chat_messages FOR INSERT 
WITH CHECK (
  auth.uid() = sender_id AND
  EXISTS (
    SELECT 1 FROM chat_rooms 
    WHERE id = room_id 
    AND auth.uid() = ANY(participant_ids)
  )
);
