ALTER TABLE public.videos
    ADD COLUMN IF NOT EXISTS category_id UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'videos_category_id_fkey'
          AND conrelid = 'public.videos'::regclass
    ) THEN
        ALTER TABLE public.videos
            ADD CONSTRAINT videos_category_id_fkey
            FOREIGN KEY (category_id)
            REFERENCES public.donation_categories(id)
            ON DELETE SET NULL
            NOT VALID;
    END IF;
END
$$;

ALTER TABLE public.videos
    VALIDATE CONSTRAINT videos_category_id_fkey;

CREATE INDEX IF NOT EXISTS idx_videos_category_id
    ON public.videos(category_id);

NOTIFY pgrst, 'reload schema';
