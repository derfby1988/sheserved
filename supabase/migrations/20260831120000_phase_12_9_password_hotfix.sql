-- Phase 12.9 — Password hotfix: plaintext inventory + metadata columns
-- Compatibility: adds columns only if they do not exist and does NOT revoke
-- the legacy direct password_hash query. Old Flutter clients continue to work.

-- 1. Add metadata columns required for lazy rehash / backstop in Phase 13.2.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS password_algo VARCHAR(20) DEFAULT 'sha256',
  ADD COLUMN IF NOT EXISTS password_updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS password_migrated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS requires_password_reset BOOLEAN DEFAULT false;

-- 2. Mark rows that are NOT a valid 64-char SHA-256 hex hash and NOT an
-- Argon2id-formatted hash as plaintext / unrecognised. These must be forced
-- to reset rather than auto-hashed, per Q4-B and Phase 12.9 plan.
UPDATE public.users
SET requires_password_reset = true
WHERE password_hash IS NOT NULL
  AND password_hash <> ''
  AND (
    length(password_hash) <> 64
    OR password_hash !~ '^[0-9a-fA-F]{64}$'
  )
  AND password_hash NOT LIKE '$argon2%';

-- 3. Default existing SHA-256 hashes to the sha256 algo.
UPDATE public.users
SET password_algo = 'sha256',
    password_updated_at = COALESCE(password_updated_at, updated_at),
    password_migrated_at = COALESCE(password_migrated_at, updated_at)
WHERE password_hash IS NOT NULL
  AND password_hash <> ''
  AND length(password_hash) = 64
  AND password_hash ~ '^[0-9a-fA-F]{64}$'
  AND requires_password_reset = false;
