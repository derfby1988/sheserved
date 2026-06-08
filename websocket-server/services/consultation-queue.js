'use strict';

const { Queue, Worker } = require('bullmq');
const { createClient } = require('@supabase/supabase-js');
const { createBullmqConnection } = require('./bullmq-connection');
const { invalidateCacheMany } = require('../middleware');
const { resolveQueueOptions } = require('../utils/queue-config');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const SUPABASE_SERVICE_KEY =
  process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
const HAS_SERVICE_KEY = Boolean(SUPABASE_SERVICE_KEY);

const connection = createBullmqConnection();
const QUEUE_NAME = 'consultation-flow';

function createSupabaseClient(authHeader = null) {
  if (!SUPABASE_URL) return null;

  const apiKey = SUPABASE_SERVICE_KEY || SUPABASE_ANON_KEY;
  if (!apiKey) return null;

  if (!HAS_SERVICE_KEY && !authHeader) {
    return null;
  }

  return createClient(SUPABASE_URL, apiKey, {
    global: {
      headers: authHeader ? { Authorization: authHeader } : {},
    },
  });
}

function normalizeSymptoms(symptoms, requestId) {
  if (!Array.isArray(symptoms)) return [];

  return symptoms
    .map((symptom) => ({
      request_id: requestId,
      region_id: symptom.region_id ?? symptom.regionId ?? '',
      side: symptom.side ?? '',
      symptom: symptom.symptom ?? '',
      display_label: symptom.display_label ?? symptom.displayLabel ?? '',
    }))
    .filter((symptom) => symptom.region_id || symptom.symptom || symptom.display_label);
}

const queueOptions = resolveQueueOptions(QUEUE_NAME, {
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 2000 },
    removeOnComplete: { count: 100 },
    removeOnFail: { count: 200 },
  },
  concurrency: 2,
});

const consultationQueue = new Queue(QUEUE_NAME, {
  connection,
  defaultJobOptions: queueOptions.defaultJobOptions,
});

async function submitConsultationRequest(payload, authHeader) {
  const {
    userId,
    packageId,
    packageName,
    price,
    bodyArea = {},
    symptomsChart = {},
    symptoms = [],
    status = 'pending',
    useAI = false,
  } = payload || {};

  if (!userId) {
    throw new Error('userId is required');
  }
  if (!packageName) {
    throw new Error('packageName is required');
  }

  const supabase = createSupabaseClient(authHeader);
  if (!supabase) {
    throw new Error(
      'Supabase is not configured for consultation submission. Provide SUPABASE_SERVICE_KEY or an Authorization bearer token.',
    );
  }

  const now = new Date().toISOString();
  const insertData = {
    user_id: userId,
    package_id: packageId ?? null,
    package_name: packageName,
    price: Number(price ?? 0),
    body_area: bodyArea,
    symptoms_chart: symptomsChart,
    status,
    created_at: now,
    updated_at: now,
  };

  const { data: parentResponse, error: insertError } = await supabase
    .from('consultation_requests')
    .insert(insertData)
    .select()
    .single();

  if (insertError) {
    throw new Error(`Failed to create consultation request: ${insertError.message}`);
  }

  const requestId = parentResponse.id;

  if (Array.isArray(symptoms) && symptoms.length > 0) {
    const symptomRows = normalizeSymptoms(symptoms, requestId);
    if (symptomRows.length > 0) {
      const { error: symptomError } = await supabase
        .from('consultation_symptoms')
        .insert(symptomRows);

      if (symptomError) {
        throw new Error(`Failed to save consultation symptoms: ${symptomError.message}`);
      }
    }
  }

  const { data: fullRequest, error: fetchError } = await supabase
    .from('consultation_requests')
    .select('*, symptoms:consultation_symptoms(*)')
    .eq('id', requestId)
    .single();

  if (fetchError) {
    throw new Error(`Failed to reload consultation request: ${fetchError.message}`);
  }

  let roomId = `consult_${requestId}`;
  try {
    const { data: repairedRoomId, error: roomError } = await supabase.rpc('repair_consultation_chat_room', {
      p_consultation_id: requestId,
    });

    if (roomError) {
      throw roomError;
    }

    if (typeof repairedRoomId === 'string' && repairedRoomId.trim().length > 0) {
      roomId = repairedRoomId;
    } else if (fullRequest.room_id) {
      roomId = fullRequest.room_id;
    }
  } catch (roomRepairError) {
    console.warn(
      `[ConsultationQueue] repair_consultation_chat_room warning for ${requestId}: ${roomRepairError.message}`,
    );
    if (fullRequest.room_id) {
      roomId = fullRequest.room_id;
    }
  }

  const job = await consultationQueue.add(
    'finalize-consultation-request',
    {
      consultationId: requestId,
      userId,
      packageId: packageId ?? null,
      packageName,
      roomId,
    },
    {
      priority: 1,
    },
  );

  console.log(`[ConsultationQueue] Enqueued consultation ${requestId} as job ${job.id}`);

  return {
    consultationRequest: fullRequest,
    roomId: fullRequest.room_id || roomId,
    jobId: job.id,
    queued: true,
  };
}

async function processConsultationRequest(job) {
  const {
    consultationId,
    userId,
    packageId,
    roomId,
  } = job.data || {};

  if (!consultationId) {
    throw new Error('consultationId is required');
  }

  console.log(`[ConsultationWorker] Processing consultation ${consultationId} (job ${job.id})`);

  const resolvedRoomId = roomId || `consult_${consultationId}`;

  // Ensure expert placeholders exist so provider dashboards and room access can resolve.
  // Only run this RPC when a service key is available; otherwise the Flutter
  // client-side fallback will populate experts on demand.
  if (packageId && HAS_SERVICE_KEY) {
    const supabase = createSupabaseClient();
    try {
      await supabase.rpc('ensure_room_experts', {
        p_consultation_id: consultationId,
        p_package_id: packageId,
        p_room_id: resolvedRoomId,
      });
    } catch (error) {
      console.warn(
        `[ConsultationWorker] ensure_room_experts failed for ${consultationId}: ${error.message}`,
      );
    }
  } else if (packageId) {
    console.log(
      `[ConsultationWorker] Skipping ensure_room_experts for ${consultationId} (no service key configured)`,
    );
  }

  // Warm / invalidate future cache keys so read paths stay consistent.
  try {
    await invalidateCacheMany(
      `consultation:request:${consultationId}`,
      `consultation:room:${resolvedRoomId}`,
      `consultation:active-count:${userId || 'all'}`,
      `chat:active:${consultationId}:50`,
    );
  } catch (error) {
    console.warn(
      `[ConsultationWorker] cache invalidation warning for ${consultationId}: ${error.message}`,
    );
  }

  return {
    consultationId,
    roomId: resolvedRoomId,
    finalized: true,
  };
}

const consultationWorker = new Worker(
  QUEUE_NAME,
  async (job) => processConsultationRequest(job),
  {
    connection,
    concurrency: queueOptions.concurrency,
  },
);

consultationWorker.on('completed', (job, result) => {
  console.log(
    `[ConsultationWorker] ✅ Job ${job.id} completed — consultationId=${result.consultationId} roomId=${result.roomId}`,
  );
});

consultationWorker.on('failed', (job, err) => {
  console.error(
    `[ConsultationWorker] ❌ Job ${job?.id} failed (attempt ${job?.attemptsMade}): ${err.message}`,
  );
});

consultationWorker.on('error', (err) => {
  console.error('[ConsultationWorker] Worker error:', err.message);
});

async function shutdown() {
  await Promise.allSettled([
    consultationWorker.close(),
    consultationQueue.close(),
  ]);
}

module.exports = {
  QUEUE_NAME,
  consultationQueue,
  consultationWorker,
  submitConsultationRequest,
  shutdown,
};
