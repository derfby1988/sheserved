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
const { rateLimiter, defaultRateLimiter, strictRateLimiter, authRateLimiter } = require('./rate-limiter');
const { idempotencyMiddleware, checkDuplicate, clearDuplicate, duplicateCheckMiddleware } = require('./idempotency');
const { cacheAside, invalidateCache, invalidateCacheMany, getSession, setSession, deleteSession, getDonationTotal, TTL } = require('./cache-aside');

module.exports = {
  // Redis Client
  redis,
  isHealthy,

  // Rate Limiting
  rateLimiter,
  defaultRateLimiter,
  strictRateLimiter,
  authRateLimiter,

  // Idempotency & Duplicate Check
  idempotencyMiddleware,
  checkDuplicate,
  clearDuplicate,
  duplicateCheckMiddleware,

  // Cache-Aside
  cacheAside,
  invalidateCache,
  invalidateCacheMany,
  getSession,
  setSession,
  deleteSession,
  getDonationTotal,
  TTL,
};
