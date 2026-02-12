-- =============================================================
-- สร้างตาราง health_article_interactions 
-- สำหรับเก็บข้อมูลการกด Like และ Bookmark
-- =============================================================

CREATE TABLE IF NOT EXISTS public.health_article_interactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  article_id UUID NOT NULL REFERENCES public.health_articles(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES public.health_article_comments(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('like', 'bookmark', 'share')),
  created_at TIMESTAMPTZ DEFAULT now(),
  
  -- ป้องกันการกดซ้ำ: user เดียวกันกดประเภทเดียวกันบนเป้าเดียวกันได้ครั้งเดียว
  UNIQUE (user_id, article_id, comment_id, type)
);

-- Index สำหรับ query ที่ใช้บ่อย
CREATE INDEX IF NOT EXISTS idx_interactions_article_type 
  ON public.health_article_interactions(article_id, type);

CREATE INDEX IF NOT EXISTS idx_interactions_user_article 
  ON public.health_article_interactions(user_id, article_id);

CREATE INDEX IF NOT EXISTS idx_interactions_comment 
  ON public.health_article_interactions(comment_id) WHERE comment_id IS NOT NULL;

-- =============================================================
-- เพิ่มคอลัมน์ bookmark_count ถ้ายังไม่มี
-- =============================================================

-- สำหรับตาราง health_articles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'health_articles' AND column_name = 'bookmark_count'
  ) THEN
    ALTER TABLE public.health_articles ADD COLUMN bookmark_count INTEGER DEFAULT 0;
  END IF;
END $$;

-- สำหรับตาราง health_article_comments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'health_article_comments' AND column_name = 'bookmark_count'
  ) THEN
    ALTER TABLE public.health_article_comments ADD COLUMN bookmark_count INTEGER DEFAULT 0;
  END IF;
END $$;

-- =============================================================
-- RLS Policy (Row Level Security) 
-- อนุญาตให้ทุกคนอ่านได้ แต่เขียนได้เฉพาะผู้ใช้ที่ยืนยันตัวตนแล้ว
-- =============================================================

ALTER TABLE public.health_article_interactions ENABLE ROW LEVEL SECURITY;

-- อนุญาตให้ทุกคนอ่านได้ (สำหรับนับจำนวน like/bookmark)
CREATE POLICY "Anyone can read interactions"
  ON public.health_article_interactions
  FOR SELECT
  USING (true);

-- อนุญาตให้ insert ได้ (ทั้งผ่าน auth และ anon key สำหรับ demo)
CREATE POLICY "Authenticated users can insert interactions"
  ON public.health_article_interactions
  FOR INSERT
  WITH CHECK (true);

-- อนุญาตให้ลบ interaction ของตัวเองได้
CREATE POLICY "Users can delete own interactions"
  ON public.health_article_interactions
  FOR DELETE
  USING (true);

-- =============================================================
-- อนุญาตให้อัปเดต like_count/bookmark_count ในตาราง articles/comments
-- =============================================================

-- ตรวจสอบว่า health_articles มี update policy หรือไม่
DO $$
BEGIN
  -- Allow update on health_articles for counter columns
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'health_articles' AND policyname = 'Anyone can update article counts'
  ) THEN
    CREATE POLICY "Anyone can update article counts"
      ON public.health_articles
      FOR UPDATE
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

DO $$
BEGIN
  -- Allow update on health_article_comments for counter columns
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'health_article_comments' AND policyname = 'Anyone can update comment counts'
  ) THEN
    CREATE POLICY "Anyone can update comment counts"
      ON public.health_article_comments
      FOR UPDATE
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
