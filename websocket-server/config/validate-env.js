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
];

const FORBIDDEN_VALUES = [
  'your_api_key_here',
  'changeme',
  'secret',
  'password',
  '*',
  'your-pull-zone.b-cdn.net',
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
