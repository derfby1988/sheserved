-- Migration: Add performance indexes for role-related queries
-- Phase 2.8: Role Management Refactor
-- Created: 2026-06-24

-- Index สำหรับ user_category_id (Phase 3A)
CREATE INDEX IF NOT EXISTS idx_users_user_category_id ON users(user_category_id);

-- Index สำหรับ profession_id (Phase 3B)
CREATE INDEX IF NOT EXISTS idx_users_profession_id ON users(profession_id);

-- Index สำหรับ role (existing - verify)
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

-- Index สำหรับ JOIN query (Phase 3)
CREATE INDEX IF NOT EXISTS idx_user_categories_id ON user_categories(id);
CREATE INDEX IF NOT EXISTS idx_professions_category ON professions(category);

-- Composite index สำหรับ query ที่ใช้บ่อย
CREATE INDEX IF NOT EXISTS idx_users_role_active ON users(role, is_active);
