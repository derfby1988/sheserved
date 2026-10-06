'use strict';

/**
 * Incident Overview Map — age bucket policy + coordinate validation
 * (VIDEO_SYSTEM_PLAN.md §22.1, §22.4)
 *
 * Buckets are elapsed time from `videos.created_at` to "now" (UTC) and are
 * contiguous — no gap, no overlap:
 *   red    : 0 .. 24h          (inclusive at 24h)
 *   orange : > 24h .. 7d
 *   gold   : > 7d  .. 35d
 *   gray   : > 35d .. 365d
 *   black  : > 365d
 *
 * Rows whose `created_at` is missing, unparseable or in the future are NOT
 * bucketed (they must never be painted red) — the caller excludes them from
 * the normal markers and counts them in `excludedCount`.
 */

const HOUR_MS = 3_600_000;
const DAY_MS = 24 * HOUR_MS;

const BUCKET_ORDER = Object.freeze(['red', 'orange', 'gold', 'gray', 'black']);

/** Upper bound of each bucket, exclusive, in milliseconds of age. */
const BUCKET_BOUNDS_MS = Object.freeze([
  24 * HOUR_MS, // red    ends at 24h (inclusive)
  7 * DAY_MS,   // orange ends at 7d
  35 * DAY_MS,  // gold   ends at 35d
  365 * DAY_MS, // gray   ends at 365d
]);

/**
 * Map a non-negative age (ms) to a bucket key.
 * @param {number} ageMs elapsed milliseconds, must be >= 0
 * @returns {string|null} bucket key, or null when the age is negative/invalid
 */
function bucketForAge(ageMs) {
  if (typeof ageMs !== 'number' || !Number.isFinite(ageMs) || ageMs < 0) {
    return null;
  }
  for (let i = 0; i < BUCKET_BOUNDS_MS.length; i++) {
    if (ageMs <= BUCKET_BOUNDS_MS[i]) return BUCKET_ORDER[i];
  }
  return 'black';
}

/**
 * Map a `created_at` value to a bucket relative to [nowMs].
 * Returns null when the timestamp is missing/unparseable/in the future —
 * such rows are excluded from markers and reported via excludedCount.
 * @param {Date|string|number|null} createdAt
 * @param {number} nowMs epoch milliseconds
 */
function bucketForCreatedAt(createdAt, nowMs) {
  if (createdAt === null || createdAt === undefined) return null;
  const t = createdAt instanceof Date ? createdAt.getTime() : Date.parse(createdAt);
  if (!Number.isFinite(t)) return null;
  const age = nowMs - t;
  if (age < 0) return null; // future timestamp — never red
  return bucketForAge(age);
}

/**
 * Canonical incident coordinate validation (§22.4.4): finite, in range, and
 * not the (0,0) sentinel. DECIMAL columns already bound the range; this is
 * the defensive check shared by Local API and Supabase paths.
 */
function isValidCoordinate(lat, lng) {
  if (lat === null || lat === undefined || lat === '' ||
      lng === null || lng === undefined || lng === '') return false;
  const a = Number(lat);
  const b = Number(lng);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return false;
  if (a < -90 || a > 90 || b < -180 || b > 180) return false;
  if (a === 0 && b === 0) return false; // (0,0) sentinel — never a real pin
  return true;
}

module.exports = {
  HOUR_MS,
  DAY_MS,
  BUCKET_ORDER,
  BUCKET_BOUNDS_MS,
  bucketForAge,
  bucketForCreatedAt,
  isValidCoordinate,
};
