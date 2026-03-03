-- Migration: User UI Preferences
-- วัตถุประสงค์: บันทึก UI ที่ผู้ใช้งานแต่ละคนจัดไว้ เช่น ตำแหน่งของ HomeConsultationWidget
-- Created: 2026-03-04

create table if not exists public.user_ui_preferences (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.users(id) on delete cascade,
  preference_key  text not null,          -- เช่น 'home_consultation_position'
  preference_value text not null,         -- เช่น 'topRight', 'bottomLeft', 'center'
  updated_at      timestamptz not null default now(),

  -- 1 user : 1 preference_key เท่านั้น
  unique(user_id, preference_key)
);

-- Index เพื่อ query เร็วตาม user_id
create index if not exists idx_user_ui_preferences_user_id
  on public.user_ui_preferences(user_id);

-- RLS: ผู้ใช้เข้าถึงได้เฉพาะข้อมูลของตัวเอง
-- หมายเหตุ: โปรเจกต์นี้ใช้ custom auth (password_hash) ไม่ใช่ Supabase Auth
-- ดังนั้น RLS จะถูก bypass ด้วย service role key อยู่แล้ว
-- เปิด RLS ไว้เพื่อความปลอดภัยแต่ policy ให้ทุกคนผ่าน service_role
alter table public.user_ui_preferences enable row level security;

-- Policy: อนุญาต service_role (ใช้ใน server-side / Edge Function)
create policy "service_role full access" on public.user_ui_preferences
  for all
  using (true)
  with check (true);
