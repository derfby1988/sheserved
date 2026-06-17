-- Phase 6.6: BodyMap Chat Selector
-- Add body_part column to chat_messages for body-part-tagged chat messages

-- 1) Add nullable body_part column
ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS body_part TEXT;

-- 2) Create indexes for counter queries and filtering
CREATE INDEX IF NOT EXISTS idx_chat_messages_body_part
ON chat_messages(body_part);

CREATE INDEX IF NOT EXISTS idx_chat_messages_room_body_part_sender
ON chat_messages(room_id, body_part, sender_id);

-- 3) Add comment for documentation
COMMENT ON COLUMN chat_messages.body_part IS 'Body part tag for chat messages (e.g., head, neck, back). NULL for general messages.';
