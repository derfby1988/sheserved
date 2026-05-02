/**
 * SyncService - Local State Reconciliation
 *
 * This service runs on server startup to push any local interactions
 * that haven't been synchronized to Supabase Cloud yet.
 */

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
            
            // Map to Supabase structure (remove is_synced)
            const videosToSync = unsyncedVideos.map(v => {
                const { is_synced, ...rest } = v;
                return rest;
            });

            const { error: videoErr } = await supabase
                .from('videos')
                .upsert(videosToSync, { onConflict: 'id' });

            if (videoErr) {
                console.error(`[Sync] Video Cloud Sync failed: ${videoErr.message}`);
                // Don't throw, try interactions anyway (some might work)
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

        if (unsyncedTracks.length > 0) {
            console.log(`[Sync] Found ${unsyncedTracks.length} unsynced GPS tracks. Syncing...`);
            
            const tracksToSync = unsyncedTracks.map(t => {
                const { is_synced, ...rest } = t;
                return rest;
            });

            const { error: trackErr } = await supabase
                .from('video_gps_tracks')
                .upsert(tracksToSync, { onConflict: 'id' });

            if (trackErr) {
                console.error(`[Sync] GPS Tracks Cloud Sync failed: ${trackErr.message}`);
            } else {
                const syncedTrackIds = unsyncedTracks.map(t => t.id);
                await pool.query(`UPDATE video_gps_tracks SET is_synced = true WHERE id = ANY($1)`, [syncedTrackIds]);
                console.log(`✅ [Sync] Successfully synced ${unsyncedTracks.length} GPS tracks.`);
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
            
            const { error: cloudErr } = await supabase
                .from('video_interactions')
                .upsert(
                    unsyncedInteractions.map(i => ({
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
                // If it fails due to FK, it's likely because some videos are still missing in Cloud
                // In production, we might want to retry later or handle specifically
            } else {
                const syncedIds = unsyncedInteractions.map(i => i.id);
                await pool.query(
                    `UPDATE video_interactions SET is_synced = true WHERE id = ANY($1)`,
                    [syncedIds]
                );
                console.log(`✅ [Sync] Successfully synced ${unsyncedInteractions.length} interactions.`);
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
