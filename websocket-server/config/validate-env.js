'use strict';

/**
 * Startup Config Validation — Fail Fast (Option A)
 * ─────────────────────────────────────────────────────
 * ปิดช่องโหว่ M1 (CORS wildcard), M9 (config ผิดแล้วยังทำงานต่อ), M15 (ไม่ตรวจ env)
 *
 * ตรวจสอบ environment variables ที่จำเป็นก่อน server start
 * ถ้าขาดหรือเป็น placeholder → process.exit(1) ทันที (fail fast)
 * ไม่ log ค่า secret เด็ดขาด
 */

const REQUIRED_IN_PRODUCTION = [
  'DB_HOST',
  'DB_NAME',
  'DB_USER',
  'DB_PASSWORD',
  'ALLOWED_ORIGINS',
  // Phase 13.0 — Supabase URL required for any environment
  'SUPABASE_URL',
];

const FORBIDDEN_VALUES = [
  'your_api_key_here',
  'changeme',
  'secret',
  'password',
  '*',
  'your-pull-zone.b-cdn.net',
  'change-me-to-256-bit-secret-1',
  'change-me-to-256-bit-secret-2',
  'your-supabase-jwt-secret',
  'your-service-role-key',
  'staging.sheserved.example.com',
  'admin@sheserved.example.com',
];

const SENSITIVE_KEY_PATTERNS = [
  /password/i,
  /secret/i,
  /api[_-]?key/i,
  /token/i,
  /anon[_-]?key/i,
];

function isSensitiveKey(key) {
  return SENSITIVE_KEY_PATTERNS.some((p) => p.test(key));
}

function validateEnv() {
  const env = process.env.NODE_ENV || 'development';
  const problems = [];

  if (env === 'production') {
    for (const key of REQUIRED_IN_PRODUCTION) {
      if (!process.env[key]) {
        problems.push(`Missing required env: ${key}`);
      }
    }

    if (process.env.ALLOWED_ORIGINS === '*') {
      problems.push('ALLOWED_ORIGINS must not be "*" in production');
    }

    if (!process.env.NODE_ENV) {
      problems.push('NODE_ENV must be explicitly set in production');
    }

    for (const [k, v] of Object.entries(process.env)) {
      if (FORBIDDEN_VALUES.includes(v)) {
        if (isSensitiveKey(k)) {
          problems.push(`Placeholder value detected in ${k} (value redacted)`);
        } else {
          problems.push(`Placeholder value in ${k}: "${v}"`);
        }
      }
    }

    if (process.env.BUNNY_CDN_API_KEY && process.env.BUNNY_CDN_API_KEY === 'your_api_key_here') {
      problems.push('BUNNY_CDN_API_KEY is still placeholder');
    }

    if (process.env.BUNNY_CDN_URL && process.env.BUNNY_CDN_URL === 'https://your-pull-zone.b-cdn.net') {
      problems.push('BUNNY_CDN_URL is still placeholder');
    }

    // Phase 13.0 — JWT validation
    if (process.env.JWT_ACTIVE_KID && process.env.JWT_PREVIOUS_KID &&
        process.env.JWT_ACTIVE_KID === process.env.JWT_PREVIOUS_KID) {
      problems.push('JWT_ACTIVE_KID and JWT_PREVIOUS_KID must not be the same');
    }

    const accessTtl = parseInt(process.env.ACCESS_TTL, 10);
    const refreshTtl = parseInt(process.env.REFRESH_TTL, 10);
    if (process.env.ACCESS_TTL && (isNaN(accessTtl) || accessTtl <= 0 || accessTtl > 3600)) {
      problems.push('ACCESS_TTL must be a positive integer ≤ 3600 (seconds)');
    }
    if (process.env.REFRESH_TTL && (isNaN(refreshTtl) || refreshTtl <= 0 || refreshTtl > 2592000)) {
      problems.push('REFRESH_TTL must be a positive integer ≤ 2592000 (30 days in seconds)');
    }

    if (process.env.JWT_ACTIVE_SECRET && process.env.JWT_ACTIVE_SECRET.length < 32) {
      problems.push('JWT_ACTIVE_SECRET must be at least 32 characters (HS256 minimum)');
    }
    if (process.env.JWT_PREVIOUS_SECRET && process.env.JWT_PREVIOUS_SECRET.length < 32) {
      problems.push('JWT_PREVIOUS_SECRET must be at least 32 characters (HS256 minimum)');
    }

    // Phase 13.0 — Service role key mandatory in production
    const serviceKey = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!serviceKey) {
      problems.push('SUPABASE_SERVICE_KEY (or SUPABASE_SERVICE_ROLE_KEY) is required in production — no silent fallback to anon');
    }

    // Phase 13.0 — SUPABASE_JWT_SECRET must not be placeholder
    if (process.env.SUPABASE_JWT_SECRET && process.env.SUPABASE_JWT_SECRET === 'your-supabase-jwt-secret') {
      problems.push('SUPABASE_JWT_SECRET is still placeholder');
    }
  }

  if (env === 'staging') {
    for (const key of REQUIRED_IN_PRODUCTION) {
      if (!process.env[key]) {
        problems.push(`Missing required env in staging: ${key}`);
      }
    }
    if (process.env.ALLOWED_ORIGINS === '*') {
      problems.push('ALLOWED_ORIGINS should not be "*" in staging');
    }
    // Phase 13.0 — Caddyfile.staging uses env-based domain/ACME email
    if (!process.env.CADDY_STAGING_DOMAIN) {
      problems.push('CADDY_STAGING_DOMAIN is required in staging (Caddyfile.staging)');
    }
    if (!process.env.CADDY_ACME_EMAIL) {
      problems.push('CADDY_ACME_EMAIL is required in staging (Let\'s Encrypt account)');
    }
    // Phase 13.0 — reject Caddy placeholder values in staging
    if (process.env.CADDY_STAGING_DOMAIN === 'staging.sheserved.example.com') {
      problems.push('CADDY_STAGING_DOMAIN is still placeholder — set real staging domain');
    }
    if (process.env.CADDY_ACME_EMAIL === 'admin@sheserved.example.com') {
      problems.push('CADDY_ACME_EMAIL is still placeholder — set real ACME email');
    }
  }

  if (problems.length > 0) {
    console.error('');
    console.error('  ══════════════════════════════════════════════════════════════');
    console.error('  ❌  [Config] Startup validation FAILED — refusing to start');
    console.error(`  Environment: ${env}`);
    console.error('  ──────────────────────────────────────────────────────────────');
    for (const p of problems) {
      console.error(`  • ${p}`);
    }
    console.error('  ══════════════════════════════════════════════════════════════');
    console.error('');
    process.exit(1);
  }

  if (env === 'production') {
    console.log('✅ [Config] Startup validation passed (production mode)');
  } else if (env === 'staging') {
    console.log('✅ [Config] Startup validation passed (staging mode)');
  } else {
    console.log('ℹ️  [Config] Startup validation skipped (development mode)');
  }
}

module.exports = { validateEnv };
