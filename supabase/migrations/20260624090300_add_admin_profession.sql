-- Migration: Add admin profession
-- Phase 2.4: Role Management Refactor (สำหรับแนวทาง B)
-- Created: 2026-06-24

-- เพิ่ม profession สำหรับ admin
INSERT INTO professions (id, name, name_en, description, icon_name, category, is_built_in, requires_verification, display_order, is_active)
VALUES ('00000000-0000-0000-0000-000000000999', 'ผู้ดูแลระบบ', 'System Admin', 'ผู้ดูแลระบบทั้งหมด', 'admin_panel_settings', 'admin', true, false, 999, true)
ON CONFLICT (id) DO NOTHING;
