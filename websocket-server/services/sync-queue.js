'use strict';

/**
 * Health Sync Pipeline Queue
 *
 * Wraps sync-service reconciliation into a BullMQ queue so that
 * local-to-cloud sync runs async, with distributed locking and
 * batch writes to prevent duplicate syncs and race conditions.
 */

const { Queue, Worker } = require('bullmq');
const { createBullmqConnection } = require('./bullmq-connection');
const { redis, invalidateCacheMany } = require('../middleware');
const { reconcileLocalToCloud } = require('./sync-service');
const { resolveQueueOptions } = require('../utils/queue-config');

const connection = createBullmqConnection();
const QUEUE_NAME = 'health-sync';

const syncDependencies = {
  pool: null,
  supabase: null,
};

// Distributed lock key prefix
const LOCK_PREFIX = 'sync:lock:';
const LOCK_TTL_MS = 300_000; // 5 minutes

const queueOptions = resolveQueueOptions(QUEUE_NAME, {
  defaultJobOptions: {
    attempts: 2,
    backoff: { type: 'fixed', delay: 30_000 },
    removeOnComplete: { count: 50 },
    removeOnFail: { count: 100 },
  },
  concurrency: 1,
});

const syncQueue = new Queue(QUEUE_NAME, {
  connection,
  defaultJobOptions: queueOptions.defaultJobOptions,
});

// ── API Helpers ────────────────────────────────────────────

async function enqueueSync(options = {}) {
  const { batchSize = 100, syncType = 'full' } = options;

  const job = await syncQueue.add(
    'reconcile-local-to-cloud',
    { batchSize, syncType },
    { priority: 1 }
  );

  console.log(`[SyncQueue] Enqueued sync job ${job.id} (type=${syncType})`);
  return { jobId: job.id, queued: true };
}

// ── Distributed Lock ───────────────────────────────────────

async function _acquireLock(lockKey, ttlMs = LOCK_TTL_MS) {
  if (!redis) return true; // no Redis = no lock, proceed

  try {
    const acquired = await redis.set(`${LOCK_PREFIX}${lockKey}`, '1', 'PX', ttlMs, 'NX');
    return acquired === 'OK';
  } catch (err) {
    console.warn(`[SyncQueue] Lock error for ${lockKey}:`, err.message);
    return true; // fail open
  }
}

async function _releaseLock(lockKey) {
  if (!redis) return;

  try {
    await redis.del(`${LOCK_PREFIX}${lockKey}`);
  } catch (err) {
    console.warn(`[SyncQueue] Unlock error for ${lockKey}:`, err.message);
  }
}

// ── Worker ─────────────────────────────────────────────────

const syncWorker = new Worker(
  QUEUE_NAME,
  async (job) => {
    const { batchSize, syncType } = job.data || {};
    const lockKey = `reconcile-${syncType}`;

    // 1. Try to acquire distributed lock
    const hasLock = await _acquireLock(lockKey);
    if (!hasLock) {
      console.log(`[SyncWorker] Job ${job.id} skipped — another reconcile is already running`);
      throw new Error('Sync already in progress — distributed lock held');
    }

    try {
      console.log(`[SyncWorker] Starting reconcile (job ${job.id}, type=${syncType})`);

      if (!syncDependencies.pool || !syncDependencies.supabase) {
        throw new Error('Sync dependencies not initialized — call init() first');
      }

      await reconcileLocalToCloud(syncDependencies.pool, syncDependencies.supabase);

      // 3. Invalidate sync-related caches
      await invalidateCacheMany(
        `sync:status`,
        `video:list:*`,
        `video:meta:*`
      );

      console.log(`[SyncWorker] Reconcile completed (job ${job.id})`);
      return { syncType, completed: true };
    } finally {
      await _releaseLock(lockKey);
    }
  },
  { connection, concurrency: queueOptions.concurrency } // concurrency 1 = only one sync at a time
);

// ── Event Handlers ─────────────────────────────────────────

syncWorker.on('completed', (job, result) => {
  console.log(`[SyncWorker] ✅ Job ${job.id} completed — type=${result.syncType}`);
});

syncWorker.on('failed', (job, err) => {
  console.error(
    `[SyncWorker] ❌ Job ${job?.id} failed (attempt ${job?.attemptsMade}): ${err.message}`
  );
});

syncWorker.on('error', (err) => {
  console.error('[SyncWorker] Worker error:', err.message);
});

// ── Init / Shutdown ────────────────────────────────────────

function init(pool, supabase) {
  syncDependencies.pool = pool;
  syncDependencies.supabase = supabase;
  console.log('[SyncQueue] Initialized with pool and supabase');
}

async function shutdown() {
  await Promise.allSettled([
    syncWorker.close(),
    syncQueue.close(),
  ]);
}

// ── Exports ────────────────────────────────────────────────

module.exports = {
  QUEUE_NAME,
  syncQueue,
  syncWorker,
  enqueueSync,
  init,
  shutdown,
};
