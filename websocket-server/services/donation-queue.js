'use strict';

/**
 * Donation Escrow Queue
 *
 * Wraps the synchronous escrow-release-service logic into a BullMQ queue
 * so that consensus voting and escrow release run async, with retry,
 * circuit-breaker protection, and cache invalidation on completion.
 */

const { Queue, Worker, QueueEvents } = require('bullmq');
const { createBullmqConnection } = require('./bullmq-connection');
const { invalidateCacheMany } = require('../middleware');
const escrowReleaseService = require('./escrow-release-service');
const { resolveQueueOptions } = require('../utils/queue-config');

const connection = createBullmqConnection();
const QUEUE_NAME = 'donation-escrow';

const queueOptions = resolveQueueOptions(QUEUE_NAME, {
  defaultJobOptions: {
    attempts: 5,
    backoff: { type: 'linear', delay: 60000 },
    removeOnComplete: { count: 100 },
    removeOnFail: { count: 200 },
  },
  concurrency: 2,
});

const donationQueue = new Queue(QUEUE_NAME, {
  connection,
  defaultJobOptions: queueOptions.defaultJobOptions,
});
const donationQueueEvents = new QueueEvents(QUEUE_NAME, { connection });
donationQueueEvents.on('error', (err) => {
  console.warn('[DonationQueue] QueueEvents error:', err.message);
});

// ── API Helpers ────────────────────────────────────────────

async function enqueueConsensusVote(requestId, responderId, canContinue, note = null) {
  const job = await donationQueue.add(
    'process-consensus-vote',
    { requestId, responderId, canContinue, note },
    { priority: 1 }
  );
  console.log(`[DonationQueue] Enqueued consensus vote job ${job.id} for request=${requestId}`);
  return { jobId: job.id, queued: true };
}

async function enqueueEscrowRelease(requestId, triggeredBy = 'consensus') {
  const job = await donationQueue.add(
    'process-escrow-release',
    { requestId, triggeredBy },
    { priority: 1 }
  );
  console.log(`[DonationQueue] Enqueued escrow release job ${job.id} for request=${requestId}`);
  return { jobId: job.id, queued: true };
}

// ── Worker ─────────────────────────────────────────────────

const donationWorker = new Worker(
  QUEUE_NAME,
  async (job) => {
    const { name, data } = job;

    if (name === 'process-consensus-vote') {
      const { requestId, responderId, canContinue, note } = data;
      console.log(`[DonationWorker] Processing consensus vote for request=${requestId}`);

      const result = await escrowReleaseService.handleConsensusVote(
        requestId,
        responderId,
        canContinue,
        note
      );

      // Cache invalidation after consensus state changes
      await _invalidateDonationCache(requestId);

      return { type: 'consensus', requestId, result };
    }

    if (name === 'process-escrow-release') {
      const { requestId, triggeredBy } = data;
      console.log(`[DonationWorker] Processing escrow release for request=${requestId}`);

      const result = await escrowReleaseService.releaseEscrow(requestId, { triggeredBy });

      // Cache invalidation after escrow release
      await _invalidateDonationCache(requestId);

      return { type: 'escrow-release', requestId, result };
    }

    throw new Error(`Unknown job name: ${name}`);
  },
  { connection, concurrency: queueOptions.concurrency }
);

// ── Cache Invalidation ───────────────────────────────────

async function _invalidateDonationCache(requestId) {
  try {
    await invalidateCacheMany(
      `donation:request:${requestId}`,
      `donation:escrow:${requestId}`,
      `donation:leaderboard`,
      `donation:summary`
    );
  } catch (err) {
    console.warn(`[DonationWorker] Cache invalidation warning for ${requestId}:`, err.message);
  }
}

// ── Event Handlers ─────────────────────────────────────────

donationWorker.on('completed', (job, result) => {
  console.log(
    `[DonationWorker] ✅ Job ${job.id} completed — ${result.type} requestId=${result.requestId} result=${result.result?.result || 'ok'}`
  );
});

donationWorker.on('failed', (job, err) => {
  console.error(
    `[DonationWorker] ❌ Job ${job?.id} failed (attempt ${job?.attemptsMade}): ${err.message}`
  );
});

donationWorker.on('error', (err) => {
  console.error('[DonationWorker] Worker error:', err.message);
});

// ── Shutdown ───────────────────────────────────────────────

async function shutdown() {
  await Promise.allSettled([
    donationWorker.close(),
    donationQueue.close(),
    donationQueueEvents.close(),
  ]);
}

// ── Exports ────────────────────────────────────────────────

module.exports = {
  QUEUE_NAME,
  donationQueue,
  donationWorker,
  enqueueConsensusVote,
  enqueueEscrowRelease,
  donationQueueEvents,
  shutdown,
};
