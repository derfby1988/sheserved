const { Queue, Worker, QueueEvents } = require('bullmq');
const { createClient } = require('@supabase/supabase-js');
const { createBullmqConnection } = require('./bullmq-connection');
const { resolveQueueOptions } = require('../utils/queue-config');

// Shared BullMQ connection config (reuses the existing Redis source of truth)
const connection = createBullmqConnection();

// Setup Supabase (Service Role for transfers)
const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_ANON_KEY
);

// Create the Transfer Queue
const QUEUE_NAME = 'payment-transfers';
const queueOptions = resolveQueueOptions(QUEUE_NAME, {
    defaultJobOptions: {
        attempts: 5,
        backoff: { type: 'exponential', delay: 60000 },
        removeOnComplete: { count: 100 },
        removeOnFail: { count: 200 },
    },
    concurrency: 1,
});

const transferQueue = new Queue(QUEUE_NAME, {
    connection,
    defaultJobOptions: queueOptions.defaultJobOptions,
});
const transferQueueEvents = new QueueEvents(QUEUE_NAME, { connection });
transferQueueEvents.on('error', (err) => {
    console.warn('[PaymentQueue] QueueEvents error:', err.message);
});

// Circuit Breaker State
let failureCount = 0;
const MAX_FAILURES = 5;
let isCircuitOpen = false;

// Worker to gracefully process escrow transfers using Payment API (e.g., PromptPay Batch)
const transferWorker = new Worker('payment-transfers', async job => {
    const { transactionId, amount, targetAccount } = job.data;
    
    if (isCircuitOpen) {
        throw new Error('Circuit Breaker is OPEN. Halting all transfers temporarily.');
    }

    try {
        console.log(`[PaymentQueue] Processing transfer for TX: ${transactionId} Amount: ${amount}`);
        
        // ---------------------------------------------------------
        // TODO: Call your actual Payment Gateway / Bank API here
        // const response = await paymentGateway.transfer(amount, targetAccount);
        // if (!response.success) throw new Error('Gateway Rejected');
        // ---------------------------------------------------------
        
        // Simulate API latency
        await new Promise(resolve => setTimeout(resolve, 800));

        // If successful, reset circuit breaker
        failureCount = 0;
        console.log(`[PaymentQueue] Transfer SUCCESS for TX: ${transactionId}`);
        
    } catch (error) {
        failureCount++;
        console.warn(`[PaymentQueue] Transfer FAILED for TX: ${transactionId}. Failure count: ${failureCount}`);
        
        if (failureCount >= MAX_FAILURES) {
            isCircuitOpen = true;
            console.error('🚨 [PaymentQueue] CIRCUIT BREAKER TRIPPED! Stopping transfers. Requires Admin intervention.');
            
            // Notify Admin via WebSocket / Push Notification here (omitted for brevity)
            setTimeout(() => {
                // Auto half-open after 30 minutes
                isCircuitOpen = false;
                failureCount = 0;
                console.log('✅ [PaymentQueue] Circuit Breaker reset (Half-Open)');
            }, 30 * 60 * 1000);
        }
        
        throw error; // Let BullMQ handle the retry based on backoff settings
    }
}, { connection, concurrency: queueOptions.concurrency });

// Listeners for Job State
transferWorker.on('completed', job => {
    console.log(`[PaymentQueue] Job ${job.id} has completed!`);
});

transferWorker.on('failed', async (job, err) => {
    console.error(`[PaymentQueue] Job ${job.id} has failed with ${err.message}`);
    // If all retries exhausted, update status to 'transfer_failed' for Admin Dashboard
    if (job.attemptsMade >= job.opts.attempts) {
        console.error(`[PaymentQueue] Job ${job.id} EXHAUSTED ALL RETRIES. Flagging as transfer_failed.`);
        await supabase
            .from('donation_transactions')
            .update({ status: 'transfer_failed', updated_at: new Date().toISOString() })
            .eq('id', job.data.transactionId);
    }
});

/**
 * Enqueue a transfer task
 */
async function enqueueTransfer(transactionId, amount, targetAccount) {
    await transferQueue.add('process-transfer', { transactionId, amount, targetAccount }, {
        attempts: 5, // Retry up to 5 times
        backoff: {
            type: 'exponential',
            delay: 60000 // Start with 1 min delay -> 2m -> 4m -> 8m
        }
    });
    console.log(`[PaymentQueue] Job enqueued for TX ${transactionId}`);
}

async function shutdown() {
    await Promise.allSettled([
        transferWorker.close(),
        transferQueue.close(),
        transferQueueEvents.close(),
    ]);
}

module.exports = {
    enqueueTransfer,
    transferQueue,
    transferWorker,
    transferQueueEvents,
    shutdown,
};
