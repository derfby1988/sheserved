CREATE TABLE IF NOT EXISTS watermark_configs (
    id SERIAL PRIMARY KEY,
    is_enabled BOOLEAN DEFAULT false,
    type VARCHAR(20) DEFAULT 'text', -- 'text' or 'image'
    text_content VARCHAR(255) DEFAULT 'Tree Law Zoo',
    image_url TEXT,
    position VARCHAR(20) DEFAULT 'bottom-right', -- 'top-left', 'top-right', 'bottom-left', 'bottom-right', 'center'
    animation_type VARCHAR(20) DEFAULT 'none', -- 'none', 'marquee', 'bounce', 'random'
    opacity DECIMAL(3,2) DEFAULT 0.5,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default row if it doesn't exist
INSERT INTO watermark_configs (id, is_enabled, type, text_content, position, animation_type, opacity)
SELECT 1, false, 'text', 'Tree Law Zoo', 'bottom-right', 'none', 0.5
WHERE NOT EXISTS (SELECT 1 FROM watermark_configs WHERE id = 1);
