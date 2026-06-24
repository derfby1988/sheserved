-- Migration: Add 'admin' to user_categories
-- Phase 2.1: Role Management Refactor
-- Created: 2026-06-24

-- เพิ่ม 'admin' ใน user_categories
INSERT INTO user_categories (id, name, icon_name, display_order, is_active)
VALUES ('admin', 'ผู้ดูแลระบบ', 'admin_panel_settings', 999, true)
ON CONFLICT (id) DO NOTHING;
