-- Migration: ERP Dashboard Theme + Light/Dark Mode + Glassmorphism
-- Created: 2026-06-11
-- Purpose: รองรับการปรับแต่งธีมสี (Light/Dark) และ Glassmorphism ใน ERP Dashboard

-- ============================================================
-- 1. theme_presets — Master color presets (managed by Sheserved Admin)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.theme_presets (
  preset_key      TEXT PRIMARY KEY,
  preset_name_th  TEXT NOT NULL,
  preset_name_en  TEXT NOT NULL,
  primary_color   TEXT NOT NULL,  -- sidebar background / app bar
  accent_color    TEXT NOT NULL,  -- toggle button, highlights, badges
  surface_color   TEXT NOT NULL,  -- active item bg, card bg
  text_primary    TEXT NOT NULL,  -- label text, title
  text_secondary  TEXT NOT NULL,  -- subtitle, hint
  error_color     TEXT NOT NULL,  -- badge, error state
  card_bg         TEXT,           -- bottom promo card bg
  card_text       TEXT,           -- bottom promo card text
  is_active       BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 2. Seed default presets (Light + Dark)
-- ============================================================

INSERT INTO public.theme_presets (preset_key, preset_name_th, preset_name_en, primary_color, accent_color, surface_color, text_primary, text_secondary, error_color, card_bg, card_text)
VALUES
  -- Light presets
  ('sheserved_default', 'Sheserved Default', 'Sheserved Default', '#00695C', '#FFC107', '#FFFFFF', '#FFFFFF', 'rgba(255,255,255,0.7)', '#F85149', '#FFFFFF', '#1F2937'),
  ('ocean_blue', 'สีฟ้ามหาสมุทร', 'Ocean Blue', '#1565C0', '#FF6F00', '#E3F2FD', '#FFFFFF', 'rgba(255,255,255,0.7)', '#D32F2F', '#BBDEFB', '#0D47A1'),
  ('sunset_orange', 'สีส้นตะวันลับ', 'Sunset Orange', '#E65100', '#FFD54F', '#FFF3E0', '#FFFFFF', 'rgba(255,255,255,0.7)', '#C62828', '#FFE0B2', '#BF360C'),
  ('forest_green', 'สีเขียวป่า', 'Forest Green', '#2E7D32', '#AED581', '#E8F5E9', '#FFFFFF', 'rgba(255,255,255,0.7)', '#B71C1C', '#C8E6C9', '#1B5E20'),
  ('royal_purple', 'สีม่วงราชา', 'Royal Purple', '#6A1B9A', '#FFD54F', '#F3E5F5', '#FFFFFF', 'rgba(255,255,255,0.7)', '#C62828', '#E1BEE7', '#4A148C'),
  ('midnight_black', 'สีดำเที่ยงคืน', 'Midnight Black', '#263238', '#FFAB40', '#ECEFF1', '#FFFFFF', 'rgba(255,255,255,0.7)', '#D84315', '#CFD8DC', '#102027'),
  ('coral_pink', 'สีชมพูปะการัง', 'Coral Pink', '#C2185B', '#FFAB91', '#FCE4EC', '#FFFFFF', 'rgba(255,255,255,0.7)', '#B71C1C', '#F8BBD0', '#880E4F'),
  -- Dark preset (fixed)
  ('sheserved_dark', 'Sheserved Dark', 'Sheserved Dark', '#0F0F0F', '#CCFF00', '#1A1A1A', '#FFFFFF', 'rgba(255,255,255,0.5)', '#EF4444', '#1A1A1A', '#FFFFFF')
ON CONFLICT (preset_key) DO UPDATE SET
  preset_name_th = EXCLUDED.preset_name_th,
  preset_name_en = EXCLUDED.preset_name_en,
  primary_color = EXCLUDED.primary_color,
  accent_color = EXCLUDED.accent_color,
  surface_color = EXCLUDED.surface_color,
  text_primary = EXCLUDED.text_primary,
  text_secondary = EXCLUDED.text_secondary,
  error_color = EXCLUDED.error_color,
  card_bg = EXCLUDED.card_bg,
  card_text = EXCLUDED.card_text;

-- ============================================================
-- 3. user_dashboard_themes — Per-user theme + glassmorphism settings
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_dashboard_themes (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  theme_preset            TEXT DEFAULT 'sheserved_default' REFERENCES public.theme_presets(preset_key),
  is_dark_mode            BOOLEAN DEFAULT false,
  module_layout_json      JSONB,
  -- Custom colors (ใช้เมื่อ theme_preset = 'custom')
  custom_primary          TEXT,
  custom_accent           TEXT,
  custom_surface          TEXT,
  custom_text_primary     TEXT,
  custom_text_secondary   TEXT,
  custom_error            TEXT,
  -- Glassmorphism settings (0.00 - 0.50, default 0.20)
  glass_opacity_sidebar   DECIMAL(5,4) DEFAULT 0.20,
  glass_opacity_cards     DECIMAL(5,4) DEFAULT 0.20,
  glass_opacity_dialog    DECIMAL(5,4) DEFAULT 0.20,
  glass_blur_level        INTEGER DEFAULT 8 CHECK (glass_blur_level BETWEEN 0 AND 20),
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, profession_id)
);

ALTER TABLE public.user_dashboard_themes
  ADD COLUMN IF NOT EXISTS module_layout_json JSONB;

-- Index เพื่อ query เร็ว
CREATE INDEX IF NOT EXISTS idx_user_dashboard_themes_user_id ON public.user_dashboard_themes(user_id);
CREATE INDEX IF NOT EXISTS idx_user_dashboard_themes_profession_id ON public.user_dashboard_themes(profession_id);

-- RLS
ALTER TABLE public.user_dashboard_themes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.theme_presets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role full access user_dashboard_themes" ON public.user_dashboard_themes;
CREATE POLICY "service_role full access user_dashboard_themes" ON public.user_dashboard_themes
  FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "service_role full access theme_presets" ON public.theme_presets;
CREATE POLICY "service_role full access theme_presets" ON public.theme_presets
  FOR ALL USING (true) WITH CHECK (true);

-- ============================================================
-- 4. RPC Functions
-- ============================================================

-- ดึง resolved theme (light หรือ dark) ของ user
CREATE OR REPLACE FUNCTION public.get_resolved_dashboard_theme(
  p_user_id UUID,
  p_profession_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_theme public.user_dashboard_themes%ROWTYPE;
  v_preset_key TEXT;
  v_preset_record JSONB;
BEGIN
  -- ดึง theme ของ user
  SELECT * INTO v_theme
  FROM public.user_dashboard_themes
  WHERE user_id = p_user_id AND profession_id = p_profession_id;

  -- ถ้ายังไม่มี → สร้าง default
  IF v_theme IS NULL THEN
    INSERT INTO public.user_dashboard_themes (user_id, profession_id)
    VALUES (p_user_id, p_profession_id)
    RETURNING * INTO v_theme;
  END IF;

  -- ถ้า dark mode → 强制ใช้ 'sheserved_dark'
  IF v_theme.is_dark_mode THEN
    v_preset_key := 'sheserved_dark';
  ELSE
    v_preset_key := v_theme.theme_preset;
  END IF;

  -- ดึง preset
  SELECT jsonb_build_object(
    'preset_key', preset_key,
    'preset_name_th', preset_name_th,
    'preset_name_en', preset_name_en,
    'primary_color', primary_color,
    'accent_color', accent_color,
    'surface_color', surface_color,
    'text_primary', text_primary,
    'text_secondary', text_secondary,
    'error_color', error_color,
    'card_bg', card_bg,
    'card_text', card_text
  ) INTO v_preset_record
  FROM public.theme_presets
  WHERE preset_key = v_preset_key;

  RETURN jsonb_build_object(
    'is_dark_mode', v_theme.is_dark_mode,
    'theme_preset', v_theme.theme_preset,
    'module_layout_json', v_theme.module_layout_json,
    'custom_primary', v_theme.custom_primary,
    'custom_accent', v_theme.custom_accent,
    'custom_surface', v_theme.custom_surface,
    'custom_text_primary', v_theme.custom_text_primary,
    'custom_text_secondary', v_theme.custom_text_secondary,
    'custom_error', v_theme.custom_error,
    'glass_opacity_sidebar', v_theme.glass_opacity_sidebar,
    'glass_opacity_cards', v_theme.glass_opacity_cards,
    'glass_opacity_dialog', v_theme.glass_opacity_dialog,
    'glass_blur_level', v_theme.glass_blur_level,
    'resolved_preset', v_preset_record
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- บันทึก layout ของการ์ดโมดูลใน ERP Dashboard
CREATE OR REPLACE FUNCTION public.save_dashboard_module_layout(
  p_user_id UUID,
  p_profession_id UUID,
  p_module_layout_json JSONB
) RETURNS VOID AS $$
BEGIN
  INSERT INTO public.user_dashboard_themes (
    user_id, profession_id, module_layout_json
  )
  VALUES (
    p_user_id, p_profession_id, p_module_layout_json
  )
  ON CONFLICT (user_id, profession_id)
  DO UPDATE SET
    module_layout_json = p_module_layout_json,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- สลับ Light/Dark mode
CREATE OR REPLACE FUNCTION public.toggle_dark_mode(
  p_user_id UUID,
  p_profession_id UUID
) RETURNS VOID AS $$
BEGIN
  INSERT INTO public.user_dashboard_themes (user_id, profession_id)
  VALUES (p_user_id, p_profession_id)
  ON CONFLICT (user_id, profession_id)
  DO UPDATE SET
    is_dark_mode = NOT public.user_dashboard_themes.is_dark_mode,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- บันทึก theme preset
CREATE OR REPLACE FUNCTION public.save_dashboard_theme_preset(
  p_user_id UUID,
  p_profession_id UUID,
  p_preset_key TEXT
) RETURNS VOID AS $$
BEGIN
  INSERT INTO public.user_dashboard_themes (user_id, profession_id, theme_preset)
  VALUES (p_user_id, p_profession_id, p_preset_key)
  ON CONFLICT (user_id, profession_id)
  DO UPDATE SET
    theme_preset = p_preset_key,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- บันทึก custom colors
CREATE OR REPLACE FUNCTION public.save_dashboard_custom_colors(
  p_user_id UUID,
  p_profession_id UUID,
  p_custom_primary TEXT,
  p_custom_accent TEXT,
  p_custom_surface TEXT,
  p_custom_text_primary TEXT,
  p_custom_text_secondary TEXT,
  p_custom_error TEXT
) RETURNS VOID AS $$
BEGIN
  INSERT INTO public.user_dashboard_themes (
    user_id, profession_id, theme_preset,
    custom_primary, custom_accent, custom_surface,
    custom_text_primary, custom_text_secondary, custom_error
  )
  VALUES (
    p_user_id, p_profession_id, 'custom',
    p_custom_primary, p_custom_accent, p_custom_surface,
    p_custom_text_primary, p_custom_text_secondary, p_custom_error
  )
  ON CONFLICT (user_id, profession_id)
  DO UPDATE SET
    theme_preset = 'custom',
    custom_primary = p_custom_primary,
    custom_accent = p_custom_accent,
    custom_surface = p_custom_surface,
    custom_text_primary = p_custom_text_primary,
    custom_text_secondary = p_custom_text_secondary,
    custom_error = p_custom_error,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ดึง glass settings
CREATE OR REPLACE FUNCTION public.get_user_glass_settings(
  p_user_id UUID,
  p_profession_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_theme public.user_dashboard_themes%ROWTYPE;
BEGIN
  SELECT * INTO v_theme
  FROM public.user_dashboard_themes
  WHERE user_id = p_user_id AND profession_id = p_profession_id;

  IF v_theme IS NULL THEN
    RETURN jsonb_build_object(
      'glass_opacity_sidebar', 0.20,
      'glass_opacity_cards', 0.20,
      'glass_opacity_dialog', 0.20,
      'glass_blur_level', 8
    );
  END IF;

  RETURN jsonb_build_object(
    'glass_opacity_sidebar', v_theme.glass_opacity_sidebar,
    'glass_opacity_cards', v_theme.glass_opacity_cards,
    'glass_opacity_dialog', v_theme.glass_opacity_dialog,
    'glass_blur_level', v_theme.glass_blur_level
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- บันทึก glass settings
CREATE OR REPLACE FUNCTION public.save_user_glass_settings(
  p_user_id UUID,
  p_profession_id UUID,
  p_sidebar_opacity DECIMAL(5,4),
  p_cards_opacity DECIMAL(5,4),
  p_dialog_opacity DECIMAL(5,4),
  p_blur_level INTEGER
) RETURNS VOID AS $$
BEGIN
  INSERT INTO public.user_dashboard_themes (
    user_id, profession_id,
    glass_opacity_sidebar, glass_opacity_cards, glass_opacity_dialog, glass_blur_level
  )
  VALUES (
    p_user_id, p_profession_id,
    p_sidebar_opacity, p_cards_opacity, p_dialog_opacity, p_blur_level
  )
  ON CONFLICT (user_id, profession_id)
  DO UPDATE SET
    glass_opacity_sidebar = p_sidebar_opacity,
    glass_opacity_cards = p_cards_opacity,
    glass_opacity_dialog = p_dialog_opacity,
    glass_blur_level = p_blur_level,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ดึงรายการ presets ทั้งหมด
CREATE OR REPLACE FUNCTION public.get_all_theme_presets()
RETURNS JSONB AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'preset_key', preset_key,
        'preset_name_th', preset_name_th,
        'preset_name_en', preset_name_en,
        'primary_color', primary_color,
        'accent_color', accent_color,
        'surface_color', surface_color,
        'text_primary', text_primary,
        'text_secondary', text_secondary,
        'error_color', error_color,
        'card_bg', card_bg,
        'card_text', card_text
      ) ORDER BY preset_key
    )
    FROM public.theme_presets
    WHERE is_active = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. Trigger: อัปเดต updated_at อัตโนมัติ
-- ============================================================

CREATE OR REPLACE FUNCTION public.trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_user_dashboard_themes_updated_at ON public.user_dashboard_themes;
CREATE TRIGGER trg_user_dashboard_themes_updated_at
  BEFORE UPDATE ON public.user_dashboard_themes
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();
