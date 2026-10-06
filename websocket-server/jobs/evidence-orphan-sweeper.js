'use strict';

/**
 * Evidence orphan sweeper — deletes bucket objects in `booking-evidence`
 * that no evidence row, payment claim, refund receipt, or live upload
 * intent references (e.g. the client uploaded then never committed, or
 * the grant flow died mid-way).
 *
 * The DB side (`cleanup_sports_venue_evidence_orphans`) decides which
 * paths are orphans and purges dead intents; this job only removes the
 * storage objects it names — SQL never deletes storage rows directly.
 *
 * Kill switch: EVIDENCE_ORPHAN_SWEEP_ENABLED=false disables the loop.
 * Interval: EVIDENCE_ORPHAN_SWEEP_INTERVAL_MS (default 6h).
 */

const BUCKET = 'booking-evidence';
const REMOVE_CHUNK = 100;

function start({ supabaseForSync } = {}) {
  if (process.env.EVIDENCE_ORPHAN_SWEEP_ENABLED === 'false') {
    console.log('[EvidenceSweeper] disabled by EVIDENCE_ORPHAN_SWEEP_ENABLED');
    return () => {};
  }
  if (!supabaseForSync) {
    console.log('[EvidenceSweeper] no Supabase client — disabled');
    return () => {};
  }
  const intervalMs = parseInt(
    process.env.EVIDENCE_ORPHAN_SWEEP_INTERVAL_MS || `${6 * 60 * 60 * 1000}`,
    10,
  );
  let running = false;

  async function sweep() {
    if (running) return;
    running = true;
    try {
      const { data, error } = await supabaseForSync.rpc(
        'cleanup_sports_venue_evidence_orphans',
        {},
      );
      if (error) throw error;
      const paths = Array.isArray(data?.paths) ? data.paths : [];
      for (let i = 0; i < paths.length; i += REMOVE_CHUNK) {
        const chunk = paths.slice(i, i + REMOVE_CHUNK);
        const { error: rmError } = await supabaseForSync.storage
          .from(BUCKET)
          .remove(chunk);
        if (rmError) throw rmError;
      }
      if (paths.length || data?.intentsPurged) {
        console.log(
          `[EvidenceSweeper] removed ${paths.length} orphan objects, ` +
            `purged ${data?.intentsPurged || 0} dead intents`,
        );
      }
    } catch (err) {
      console.error('[EvidenceSweeper] sweep failed:', err.message);
    } finally {
      running = false;
    }
  }

  const timer = setInterval(sweep, intervalMs);
  if (timer.unref) timer.unref();
  // First pass after a short delay so startup stays fast.
  const first = setTimeout(sweep, 60_000);
  if (first.unref) first.unref();
  console.log(`[EvidenceSweeper] started (every ${intervalMs}ms)`);
  return () => {
    clearInterval(timer);
    clearTimeout(first);
  };
}

module.exports = { start, REMOVE_CHUNK };
