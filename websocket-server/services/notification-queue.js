'use strict';

/**
 * Notification Queue
 *
 * Centralizes multi-channel notifications (Socket.io for now) so that
 * high-volume alert fan-outs do not block the WebSocket event loop.
 */

const { Queue, Worker } = require('bullmq');
const { createBullmqConnection } = require('./bullmq-connection');
const socketService = require('./socket-service');
const { resolveQueueOptions } = require('../utils/queue-config');

const connection = createBullmqConnection();
const QUEUE_NAME = 'notification-events';

const queueOptions = resolveQueueOptions(QUEUE_NAME, {
  defaultJobOptions: {
    attempts: 5,
    backoff: { type: 'fixed', delay: 15000 },
    removeOnComplete: { count: 500 },
    removeOnFail: { count: 200 },
  },
  concurrency: 5,
});

const notificationQueue = new Queue(QUEUE_NAME, {
  connection,
  defaultJobOptions: queueOptions.defaultJobOptions,
});

function requireSocketInstance() {
  const io = socketService.getIO?.();
  if (!io) {
    throw new Error('Socket service not initialized yet');
  }
  return io;
}

async function deliverToUser({ userId, event, payload = {} }) {
  if (!userId) throw new Error('userId is required for socket-user notifications');
  if (!event) throw new Error('event is required for socket-user notifications');
  const io = requireSocketInstance();
  io.to(`user-${userId}`).emit(event, payload);
  return { deliveredTo: `user-${userId}`, event };
}

async function deliverToRoom({ room, event, payload = {} }) {
  if (!room) throw new Error('room is required for socket-room notifications');
  if (!event) throw new Error('event is required for socket-room notifications');
  const io = requireSocketInstance();
  io.to(room).emit(event, payload);
  return { deliveredTo: room, event };
}

const notificationWorker = new Worker(
  QUEUE_NAME,
  async (job) => {
    if (job.name === 'socket-user') {
      return deliverToUser(job.data);
    }

    if (job.name === 'socket-room') {
      return deliverToRoom(job.data);
    }

    throw new Error(`Unknown notification job: ${job.name}`);
  },
  { connection, concurrency: queueOptions.concurrency }
);

notificationWorker.on('completed', (job, result) => {
  console.log(`[NotificationWorker] ✅ Job ${job.id} completed —`, result);
});

notificationWorker.on('failed', (job, err) => {
  console.error(
    `[NotificationWorker] ❌ Job ${job?.id} failed (attempt ${job?.attemptsMade}): ${err.message}`
  );
});

notificationWorker.on('error', (err) => {
  console.error('[NotificationWorker] Worker error:', err.message);
});

function enqueueSocketToUser(userId, event, payload = {}, opts = {}) {
  return notificationQueue.add(
    'socket-user',
    { userId, event, payload },
    {
      priority: opts.priority ?? 5,
      delay: opts.delay ?? 0,
    }
  );
}

function enqueueSocketToRoom(room, event, payload = {}, opts = {}) {
  return notificationQueue.add(
    'socket-room',
    { room, event, payload },
    {
      priority: opts.priority ?? 5,
      delay: opts.delay ?? 0,
    }
  );
}

async function shutdown() {
  await Promise.allSettled([
    notificationWorker.close(),
    notificationQueue.close(),
  ]);
}

module.exports = {
  QUEUE_NAME,
  notificationQueue,
  notificationWorker,
  enqueueSocketToUser,
  enqueueSocketToRoom,
  shutdown,
};
