/**
 * SyncService - Local State Reconciliation
 *
 * This service runs on server startup to push any local interactions
 * that haven't been synchronized to Supabase Cloud yet.
 */

// Local-only columns that exist in the local PostgreSQL videos table but NOT in Cloud
const VIDEO_LOCAL_ONLY_COLUMNS = new Set([
    'is_synced',
    'address', 'alley', 'road', 'soi', 'village',
    'cached_like_count', 'cached_view_count',
    'category_id',
]);

async function reconcileLocalToCloud(pool, supabase) {
    if (!pool || !supabase) {
        console.warn('[Sync] Cannot reconcile: Database or Supabase client missing.');
        return;
    }

    console.log('🔄 [Sync] Starting Local to Cloud Reconciliation...');

    try {
        // --- 1. Ensure schema supports syncing ---
        await pool.query(`
            DO $$
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='videos' AND column_name='is_synced') THEN
                    ALTER TABLE videos ADD COLUMN is_synced BOOLEAN DEFAULT false;
                END IF;
                IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='video_interactions' AND column_name='is_synced') THEN
                    ALTER TABLE video_interactions ADD COLUMN is_synced BOOLEAN DEFAULT false;
                END IF;
                IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='video_gps_tracks' AND column_name='is_synced') THEN
                    ALTER TABLE video_gps_tracks ADD COLUMN is_synced BOOLEAN DEFAULT false;
                END IF;
            END $$;
        `);

        // --- 2. Synchronize Videos ---
        const { rows: unsyncedVideos } = await pool.query(
            `SELECT * FROM videos WHERE is_synced = false ORDER BY created_at ASC`
        );

        if (unsyncedVideos.length > 0) {
            console.log(`[Sync] Found ${unsyncedVideos.length} unsynced videos. Syncing...`);

            // Strip local-only columns before upserting to Cloud
            const videosToSync = unsyncedVideos.map(v => {
                const out = {};
                for (const [col, val] of Object.entries(v)) {
                    if (!VIDEO_LOCAL_ONLY_COLUMNS.has(col)) out[col] = val;
                }
                return out;
            });

            const { error: videoErr } = await supabase
                .from('videos')
                .upsert(videosToSync, { onConflict: 'id' });

            if (videoErr) {
                console.error(`[Sync] Video Cloud Sync failed: ${videoErr.message}`);
            } else {
                const syncedVideoIds = unsyncedVideos.map(v => v.id);
                await pool.query(`UPDATE videos SET is_synced = true WHERE id = ANY($1)`, [syncedVideoIds]);
                console.log(`✅ [Sync] Successfully synced ${unsyncedVideos.length} videos.`);
            }
        }

        // --- 3. Synchronize Video GPS Tracks ---
        const { rows: unsyncedTracks } = await pool.query(
            `SELECT * FROM video_gps_tracks WHERE is_synced = false ORDER BY timestamp_offset ASC LIMIT 500`
        );

        // Only sync GPS tracks whose parent video already exists in Cloud (FK safety)
        const syncedVideoIdsSet = new Set((await pool.query(`SELECT id FROM videos WHERE is_synced = true`)).rows.map(r => r.id));
        const safeTracks = unsyncedTracks.filter(t => syncedVideoIdsSet.has(t.video_id));

        if (safeTracks.length > 0) {
            console.log(`[Sync] Found ${safeTracks.length} safe GPS tracks to sync (skipped ${unsyncedTracks.length - safeTracks.length} orphaned).`);

            const tracksToSync = safeTracks.map(t => {
                const { is_synced, ...rest } = t;
                return rest;
            });

            const { error: trackErr } = await supabase
                .from('video_gps_tracks')
                .upsert(tracksToSync, { onConflict: 'id' });

            if (trackErr) {
                console.error(`[Sync] GPS Tracks Cloud Sync failed: ${trackErr.message}`);
            } else {
                const syncedTrackIds = safeTracks.map(t => t.id);
                await pool.query(`UPDATE video_gps_tracks SET is_synced = true WHERE id = ANY($1)`, [syncedTrackIds]);
                console.log(`✅ [Sync] Successfully synced ${safeTracks.length} GPS tracks.`);
            }
        }

        // --- 4. Synchronize Video Interactions (Likes/Views) ---
        const { rows: unsyncedInteractions } = await pool.query(
            `SELECT id, video_id, user_id, type, value, created_at 
             FROM video_interactions 
             WHERE is_synced = false 
             ORDER BY created_at ASC`
        );

        if (unsyncedInteractions.length > 0) {
            console.log(`[Sync] Found ${unsyncedInteractions.length} unsynced interactions. Syncing...`);

            // Pre-filter duplicates against Cloud to avoid unique-constraint violations
            let existingSet = new Set();
            let fetchFailed = false;
            try {
                const { data: existingInteractions, error: fetchErr } = await supabase
                    .from('video_interactions')
                    .select('video_id, user_id, type');
                if (fetchErr) {
                    fetchFailed = true;
                } else if (existingInteractions) {
                    existingSet = new Set(
                        existingInteractions.map(r => `${r.video_id}|${r.user_id}|${r.type}`)
                    );
                }
            } catch (_) {
                fetchFailed = true;
            }

            // If we can't read Cloud state, mark local as synced to stop retrying forever
            if (fetchFailed) {
                const allIds = unsyncedInteractions.map(i => i.id);
                await pool.query(`UPDATE video_interactions SET is_synced = true WHERE id = ANY($1)`, [allIds]);
                console.log(`⚠️ [Sync] Skipped ${allIds.length} interactions (could not read Cloud state). Marked local as synced.`);
                return;
            }

            const newInteractions = unsyncedInteractions.filter(i =>
                !existingSet.has(`${i.video_id}|${i.user_id}|${i.type}`)
            );

            if (newInteractions.length > 0) {
                const { error: cloudErr } = await supabase
                    .from('video_interactions')
                    .upsert(
                        newInteractions.map(i => ({
                            id: i.id,
                            video_id: i.video_id,
                            user_id: i.user_id,
                            type: i.type,
                            value: i.value,
                            created_at: i.created_at
                        })),
                        { onConflict: 'id' }
                    );

                if (cloudErr) {
                    console.error(`[Sync] Interaction Cloud Sync failed: ${cloudErr.message}`);
                } else {
                    const syncedIds = newInteractions.map(i => i.id);
                    await pool.query(
                        `UPDATE video_interactions SET is_synced = true WHERE id = ANY($1)`,
                        [syncedIds]
                    );
                    console.log(`✅ [Sync] Successfully synced ${newInteractions.length} interactions (skipped ${unsyncedInteractions.length - newInteractions.length} duplicates).`);
                }
            } else {
                // All were duplicates — mark them synced locally so they don't retry forever
                const allIds = unsyncedInteractions.map(i => i.id);
                await pool.query(
                    `UPDATE video_interactions SET is_synced = true WHERE id = ANY($1)`,
                    [allIds]
                );
                console.log(`✅ [Sync] All ${unsyncedInteractions.length} interactions already exist in Cloud. Marked local as synced.`);
            }
        } else {
            console.log(`[Sync] No pending video interactions to sync.`);
        }

    } catch (error) {
        console.error('❌ [Sync] Reconciliation error:', error.message);
    }
}

module.exports = {
    reconcileLocalToCloud
};
