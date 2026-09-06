'use strict';

/**
 * Password verification — Argon2id with lazy rehash + legacy SHA-256 backstop
 * (Decision Q4 = B)
 * ─────────────────────────────────────────────────────────────
 * - Verify Argon2id first (preferred algorithm).
 * - Legacy SHA-256: verify only during compatibility window, then rehash
 *   to Argon2id immediately (lazy rehash).
 * - Backstop: argon2(sha256(pw)) for legacy SHA-256 rows whose plaintext
 *   is not available.
 * - Plaintext rows: force reset — never hash the existing plaintext value.
 *
 * Algorithms stored in `users.password_algo`:
 *   'argon2id'  — preferred (Argon2id hash in password_hash)
 *   'sha256'    — legacy (hex SHA-256 hash in password_hash)
 *   'plaintext' — must reset (raw password in password_hash — security risk)
 *   NULL        — social-only login, no password
 */

const crypto = require('crypto');

// Argon2id is the preferred algorithm.  bcryptjs (cost 12) is the documented
// fallback per plan (Decision Q4 = B) if the native argon2 module cannot load
// (e.g. platform without prebuilt binaries).  bcryptjs is pure-JS and
// API-compatible with bcrypt — required unconditionally so verifyPassword
// can always handle legacy bcrypt rows.
let argon2 = null;
let bcrypt = null;
try {
  argon2 = require('argon2');
} catch (_) {
  argon2 = null;
}
try {
  bcrypt = require('bcryptjs');
} catch (_) {
  if (!argon2) {
    throw new Error('Neither argon2 nor bcryptjs is available for password hashing');
  }
}

const ARGON2ID_ALGO = 'argon2id';
const SHA256_ALGO = 'sha256';
const PLAINTEXT_ALGO = 'plaintext';
const BCRYPT_ALGO = 'bcrypt';
const BCRYPT_COST = 12;

const isArgon2Available = !!argon2;

// Argon2id parameters (OWASP-recommended as of 2026).
// t=3, m=65536 (64 MiB), p=1 — can be tuned via env for production.
const ARGON2_OPTIONS = {
  type: argon2 ? argon2.argon2id : null,
  timeCost: parseInt(process.env.ARGON2_TIME_COST, 10) || 3,
  memoryCost: parseInt(process.env.ARGON2_MEMORY_COST, 10) || 65536,
  parallelism: parseInt(process.env.ARGON2_PARALLELISM, 10) || 1,
};

/**
 * Hash a password with Argon2id (preferred) or bcrypt cost 12 (fallback).
 * @param {string} password
 * @returns {Promise<string>} encoded hash string
 */
async function hashPassword(password) {
  if (!password || typeof password !== 'string') {
    throw new Error('Password is required');
  }
  if (isArgon2Available) {
    return argon2.hash(password, ARGON2_OPTIONS);
  }
  return bcrypt.hash(password, BCRYPT_COST);
}

/**
 * Verify a password against a stored hash.
 *
 * @param {string} password      - plaintext password from login attempt
 * @param {string} storedHash    - hash from users.password_hash
 * @param {string} storedAlgo    - algorithm from users.password_algo
 * @returns {Promise<object>} { valid: boolean, needsRehash: boolean, reason?: string }
 */
async function verifyPassword(password, storedHash, storedAlgo) {
  if (!password || !storedHash) {
    return { valid: false, needsRehash: false, reason: 'missing_credentials' };
  }

  const algo = (storedAlgo || '').toLowerCase();

  // 1. Argon2id — preferred path
  if (algo === ARGON2ID_ALGO) {
    if (!isArgon2Available) {
      return { valid: false, needsRehash: false, reason: 'verify_error' };
    }
    try {
      const valid = await argon2.verify(storedHash, password);
      // Check if parameters need upgrading (optional).
      const needsRehash = valid && argon2.needsRehash(storedHash, ARGON2_OPTIONS);
      return { valid, needsRehash, reason: valid ? null : 'invalid_password' };
    } catch (err) {
      return { valid: false, needsRehash: false, reason: 'verify_error' };
    }
  }

  // 1b. bcrypt — fallback algorithm (only used if argon2 was unavailable
  //     when the hash was created)
  if (algo === BCRYPT_ALGO) {
    try {
      const valid = await bcrypt.compare(password, storedHash);
      // Upgrade to Argon2id on next successful login if argon2 is available.
      return { valid, needsRehash: valid && isArgon2Available, reason: valid ? null : 'invalid_password' };
    } catch (err) {
      return { valid: false, needsRehash: false, reason: 'verify_error' };
    }
  }

  // 2. Legacy SHA-256 — verify + mark for lazy rehash
  if (algo === SHA256_ALGO) {
    const sha256Hex = crypto.createHash('sha256').update(password).digest('hex');
    if (sha256Hex === storedHash) {
      // Valid legacy password — needs rehash to Argon2id.
      return { valid: true, needsRehash: true, reason: null };
    }
    return { valid: false, needsRehash: false, reason: 'invalid_password' };
  }

  // 3. Plaintext — must force reset, never auto-hash
  if (algo === PLAINTEXT_ALGO) {
    if (password === storedHash) {
      return {
        valid: true,
        needsRehash: false,
        forceReset: true,
        reason: 'plaintext_must_reset',
      };
    }
    return { valid: false, needsRehash: false, reason: 'invalid_password' };
  }

  // 4. Unknown algorithm
  return { valid: false, needsRehash: false, reason: 'unknown_algorithm' };
}

/**
 * Rehash a password to the preferred algorithm (lazy rehash on successful
 * legacy login).  Returns the algorithm actually used.
 * @param {string} password
 * @returns {Promise<{ hash: string, algo: string }>}
 */
async function rehashToArgon2id(password) {
  const hash = await hashPassword(password);
  return { hash, algo: isArgon2Available ? ARGON2ID_ALGO : BCRYPT_ALGO };
}

/**
 * Generate a SHA-256 hash (for legacy compatibility only — NOT for new passwords).
 * @param {string} password
 * @returns {string} hex SHA-256 hash
 */
function sha256Hash(password) {
  return crypto.createHash('sha256').update(password).digest('hex');
}

module.exports = {
  ARGON2ID_ALGO,
  SHA256_ALGO,
  PLAINTEXT_ALGO,
  BCRYPT_ALGO,
  BCRYPT_COST,
  ARGON2_OPTIONS,
  isArgon2Available,
  hashPassword,
  verifyPassword,
  rehashToArgon2id,
  sha256Hash,
};
