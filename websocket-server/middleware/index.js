/**
 * Middleware Index
 * ─────────────────────────────────────────────────────────────
 * รวม export ทั้งหมดของ Phase 1 Middleware ไว้ในจุดเดียว
 * ให้ server.js หรือ route files import ได้สะดวก
 *
 * @example
 * const {
 *   defaultRateLimiter,
 *   strictRateLimiter,
 *   idempotencyMiddleware,
 *   checkDuplicate,
 *   cacheAside,
 *   invalidateCache,
 *   TTL,
 * } = require('./middleware');
 */

'use strict';

const { redis, isHealthy }                         = require('./redis-client');
const { rateLimiter, defaultRateLimiter, strictRateLimiter, authRateLimiter,
        quotaLimiter, cooldownLimiter, lockoutLimiter, normalizeClientIp,
        userLimiter, ipLimiter, uploadQuotaLimiter, otpCooldownLimiter, loginLockoutLimiter,
} = require('./rate-limiter');
const { idempotencyMiddleware, checkDuplicate, clearDuplicate, duplicateCheckMiddleware } = require('./idempotency');
const { cacheAside, invalidateCache, invalidateCacheMany, invalidateCachePattern, getSession, setSession, deleteSession, getDonationTotal, TTL } = require('./cache-aside');
const { verifyToken, requireRole, requireAuth } = require('./auth');

module.exports = {
  // Redis Client
  redis,
  isHealthy,

  // Rate Limiting
  rateLimiter,
  defaultRateLimiter,
  strictRateLimiter,
  authRateLimiter,

  // Option A: Multi-Dimensional Rate Limiting
  quotaLimiter,
  cooldownLimiter,
  lockoutLimiter,
  normalizeClientIp,
  userLimiter,
  ipLimiter,
  uploadQuotaLimiter,
  otpCooldownLimiter,
  loginLockoutLimiter,

  // Idempotency & Duplicate Check
  idempotencyMiddleware,
  checkDuplicate,
  clearDuplicate,
  duplicateCheckMiddleware,

  // Cache-Aside
  cacheAside,
  invalidateCache,
  invalidateCacheMany,
  invalidateCachePattern,
  getSession,
  setSession,
  deleteSession,
  getDonationTotal,
  TTL,

  // Auth & RBAC (Phase 1 — Route Security)
  verifyToken,
  requireRole,
  requireAuth,
};
