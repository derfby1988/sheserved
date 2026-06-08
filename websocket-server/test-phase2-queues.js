'use strict';

require('dotenv').config();

const { QueueEvents } = require('bullmq');
const { createBullmqConnection } = require('./services/bullmq-connection');
const { redis } = require('./middleware/redis-client');

const consultationQueueService = require('./services/consultation-queue');
let donationQueueService = null;
let donationQueue = null;
let donationTestSkipReason = null;
try {
  donationQueueService = require('./services/donation-queue');
  donationQueue = donationQueueService.donationQueue;
} catch (err) {
  donationTestSkipReason = err.message || 'Unknown error while loading donation queue service';
}
let videoService = null;
let videoQueue = null;
let videoTestSkipReason = null;
try {
  videoService = require('./services/video-service');
  videoQueue = videoService.videoQueue;
} catch (err) {
  videoTestSkipReason = err.message || 'Unknown error while loading video service (check optional deps like sharp/ffmpeg)';
}
const syncQueueService = require('./services/sync-queue');

const consultationQueue = consultationQueueService.consultationQueue;
const syncQueue = syncQueueService.syncQueue;

function logSection(title) {
  console.log('\n' + '─'.repeat(70));
  console.log(`🧪 ${title}`);
  console.log('─'.repeat(70));
}

async function cleanupQueue(queue) {
  await queue.drain().catch(() => {});
  const states = ['completed', 'failed', 'delayed'];
  for (const state of states) {
    await queue.clean(0, state).catch(() => {});
  }
}

async function waitForJobCompletion(queue, job, timeoutMs = 10000) {
  const queueEvents = new QueueEvents(queue.name, { connection: createBullmqConnection(), blockingTimeout: 1000 });
  await queueEvents.waitUntilReady();
  try {
    return await job.waitUntilFinished(queueEvents, timeoutMs);
  } finally {
    await queueEvents.close();
  }
}

async function testConsultationFlow() {
  logSection('Consultation Queue — finalize-consultation-request');
  await cleanupQueue(consultationQueue);

  const job = await consultationQueue.add(
    'finalize-consultation-request',
    {
      consultationId: 'integration-consult-001',
      userId: 'user-test',
      packageId: null,
      roomId: 'consult_integration_test',
    },
    { removeOnComplete: true }
  );

  const result = await waitForJobCompletion(consultationQueue, job);
  if (!result || !result.finalized) {
    throw new Error('Consultation queue job did not finalize');
  }
  console.log('✅ Consultation queue processed job successfully:', result);
}

async function testDonationEnqueue() {
  logSection('Donation Queue — enqueue-only sanity (worker paused)');

  if (!donationQueue || !donationQueueService) {
    console.log('⚠️  Skipping donation queue test:', donationTestSkipReason || 'service not available (likely missing SUPABASE_URL)');
    return;
  }

  await donationQueue.pause(true);
  await cleanupQueue(donationQueue);

  const enqueueResult = await donationQueueService.enqueueConsensusVote(
    'integration-donation-001',
    'responder-test',
    true,
    'integration test'
  );

  const counts = await donationQueue.getJobCounts('waiting', 'paused');
  if ((counts.waiting || 0) < 1) {
    throw new Error('Donation queue missing waiting job after enqueue');
  }
  console.log('✅ Donation queue accepted job (paused to avoid Supabase dependency):', enqueueResult);

  await donationQueue.removeJobs('*');
  await donationQueue.resume();
}

async function testVideoEnqueue() {
  logSection('Video Queue — enqueue-only sanity (worker paused)');
  if (!videoQueue || !videoService) {
    console.log('⚠️  Skipping video queue test:', videoTestSkipReason || 'video service not available (ffmpeg/sharp missing)');
    return;
  }
  await videoQueue.pause(true);
  await cleanupQueue(videoQueue);

  await videoService.addToQueue({
    id: 'integration-video-001',
    type: 'emergency',
    userId: 'user-test',
    filePath: '/tmp/nonexistent.mp4',
    title: 'Integration Test Video',
  });

  const counts = await videoQueue.getJobCounts('waiting', 'paused');
  if ((counts.waiting || 0) < 1) {
    throw new Error('Video queue missing waiting job after enqueue');
  }
  console.log('✅ Video queue accepted job (paused to avoid ffmpeg run)');

  await videoQueue.removeJobs('*');
  await videoQueue.resume();
}

async function testSyncEnqueue() {
  logSection('Health Sync Queue — enqueue-only sanity (worker paused)');
  await syncQueue.pause(true);
  await cleanupQueue(syncQueue);

  const enqueueResult = await syncQueueService.enqueueSync({ syncType: 'integration-test', batchSize: 10 });
  const counts = await syncQueue.getJobCounts('waiting', 'paused');
  if ((counts.waiting || 0) < 1) {
    throw new Error('Sync queue missing waiting job after enqueue');
  }
  console.log('✅ Sync queue accepted job (paused to avoid DB/Supabase requirements):', enqueueResult);

  await syncQueue.removeJobs('*');
  await syncQueue.resume();
}

async function run() {
  console.log('\n🚀 Running Phase 2 integration checks (queues + workers)');
  try {
    await testConsultationFlow();
    await testDonationEnqueue();
    await testVideoEnqueue();
    await testSyncEnqueue();
    console.log('\n🎉 Phase 2 integration checks completed successfully!');
    process.exitCode = 0;
  } catch (error) {
    console.error('\n❌ Phase 2 integration checks failed:', error.message);
    console.error(error);
    process.exitCode = 1;
  } finally {
    await redis.quit().catch(() => {});
    process.exit();
  }
}

run();
