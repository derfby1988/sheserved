-- Migration: Add role flags to user_categories
-- Phase 2.2: Role Management Refactor
-- Created: 2026-06-24

-- เพิ่ม flags สำหรับกำหนดสิทธิ์
ALTER TABLE user_categories ADD COLUMN IF NOT EXISTS can_access_admin_panel BOOLEAN DEFAULT false;
ALTER TABLE user_categories ADD COLUMN IF NOT EXISTS can_access_provider_dashboard BOOLEAN DEFAULT false;
ALTER TABLE user_categories ADD COLUMN IF NOT EXISTS can_access_erp BOOLEAN DEFAULT false;

-- อัปเดต flags สำหรับ admin
UPDATE user_categories
SET can_access_admin_panel = true,
    can_access_erp = true
WHERE id = 'admin';

-- อัปเดต flags สำหรับ provider
UPDATE user_categories
SET can_access_provider_dashboard = true
WHERE id = 'provider';
