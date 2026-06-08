'use strict';

const { redis } = require('../middleware/redis-client');

const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';

/**
 * Shared BullMQ connection config.
 *
 * We reuse the existing Redis configuration source so all queue services
 * stay aligned with the same Redis endpoint and retry policy, while forcing
 * BullMQ-compatible options for blocking job processing.
 */
function createBullmqConnection() {
  return {
    ...redis.options,
    url: REDIS_URL,
    maxRetriesPerRequest: null,
  };
}

module.exports = {
  createBullmqConnection,
};
