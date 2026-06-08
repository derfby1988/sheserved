'use strict';

const DEFAULT_ATTEMPTS = 3;
const DEFAULT_BACKOFF_TYPE = 'fixed';
const DEFAULT_BACKOFF_DELAY_MS = 2000;
const DEFAULT_CONCURRENCY = 1;

function normalizeQueueName(queueName) {
  return queueName.replace(/[^a-zA-Z0-9]/g, '_').toUpperCase();
}

function envKey(queueName, suffix) {
  return `QUEUE_${normalizeQueueName(queueName)}_${suffix}`;
}

function getNumberEnv(key, fallback) {
  if (!(key in process.env)) return fallback;
  const value = Number(process.env[key]);
  return Number.isFinite(value) ? value : fallback;
}

function resolveQueueOptions(queueName, defaults = {}) {
  const defaultJobOptions = { ...(defaults.defaultJobOptions || {}) };

  const attemptsDefault =
    defaultJobOptions.attempts ?? defaults.attempts ?? DEFAULT_ATTEMPTS;
  if (attemptsDefault !== undefined) {
    defaultJobOptions.attempts = getNumberEnv(
      envKey(queueName, 'ATTEMPTS'),
      attemptsDefault,
    );
  }

  const hasBackoffDefaults =
    defaultJobOptions.backoff || defaults.backoff || defaults.backoffType || defaults.backoffDelayMs;
  if (hasBackoffDefaults || process.env[envKey(queueName, 'BACKOFF_TYPE')] || process.env[envKey(queueName, 'BACKOFF_DELAY_MS')]) {
    const resolvedBackoff = {
      ...(defaultJobOptions.backoff || defaults.backoff || {}),
    };
    if (!resolvedBackoff.type) {
      resolvedBackoff.type = defaults.backoffType || DEFAULT_BACKOFF_TYPE;
    }
    if (resolvedBackoff.delay == null) {
      resolvedBackoff.delay = defaults.backoffDelayMs ?? DEFAULT_BACKOFF_DELAY_MS;
    }
    const envType = process.env[envKey(queueName, 'BACKOFF_TYPE')];
    if (envType) resolvedBackoff.type = envType;
    const envDelay = getNumberEnv(envKey(queueName, 'BACKOFF_DELAY_MS'), null);
    if (envDelay != null) resolvedBackoff.delay = envDelay;
    defaultJobOptions.backoff = resolvedBackoff;
  }

  const concurrencyDefault = defaults.concurrency ?? DEFAULT_CONCURRENCY;
  const concurrency = getNumberEnv(
    envKey(queueName, 'CONCURRENCY'),
    concurrencyDefault,
  );

  return { concurrency, defaultJobOptions };
}

function resolveHealthThresholds(queueName, defaults = {}) {
  const maxWaitingDefault = defaults.maxWaiting ?? 1000;
  const maxFailedDefault = defaults.maxFailed ?? 100;
  return {
    maxWaiting: getNumberEnv(envKey(queueName, 'MAX_WAITING'), maxWaitingDefault),
    maxFailed: getNumberEnv(envKey(queueName, 'MAX_FAILED'), maxFailedDefault),
  };
}

module.exports = {
  resolveQueueOptions,
  resolveHealthThresholds,
};
