/**
 * SyncService - Local State Reconciliation
 *
 * This service runs on server startup to push any local interactions
 * that haven't been synchronized to Supabase Cloud yet.
 */

// Local-only columns that exist in the local PostgreSQL videos table but NOT in Cloud
const VIDEO_LOCAL_ONLY_COLUMNS = new Set([
    'is_synced',
    'category_id_synced',
    'address', 'alley', 'road', 'soi', 'village',
    'cached_like_count', 'cached_view_count',
    'incident_id',
    'peak_viewers',
    'peak_viewers_at',
    'photo_urls',
]);

function toCloudVideo(video) {
    const out = {};
    for (const [column, value] of Object.entries(video)) {
        if (!VIDEO_LOCAL_ONLY_COLUMNS.has(column)) out[column] = value;
    }
    return out;
}

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
                IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='videos' AND column_name='category_id_synced') THEN
                    ALTER TABLE videos ADD COLUMN category_id_synced BOOLEAN DEFAULT false;
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
        const { rows: pendingVideos } = await pool.query(
            `SELECT * FROM videos
             WHERE is_synced = false
                OR (category_id IS NOT NULL AND category_id_synced = false)
             ORDER BY created_at ASC`
        );
        const unsyncedVideos = pendingVideos.filter(video => !video.is_synced);
        const categoryBackfillVideos = pendingVideos.filter(
            video => video.is_synced && video.category_id && !video.category_id_synced
        );

        if (unsyncedVideos.length > 0) {
            console.log(`[Sync] Found ${unsyncedVideos.length} unsynced videos. Syncing...`);

            // Strip local-only columns before upserting to Cloud
            const videosToSync = unsyncedVideos.map(toCloudVideo);

            const { error: videoErr } = await supabase
                .from('videos')
                .upsert(videosToSync, { onConflict: 'id' });

            if (videoErr) {
                console.error(`[Sync] Video Cloud Sync failed: ${videoErr.message}`);
            } else {
                const syncedVideoIds = unsyncedVideos.map(v => v.id);
                await pool.query(
                    `UPDATE videos
                     SET is_synced = true, category_id_synced = true
                     WHERE id = ANY($1)`,
                    [syncedVideoIds]
                );
                console.log(`✅ [Sync] Successfully synced ${unsyncedVideos.length} videos.`);
            }
        }

        if (categoryBackfillVideos.length > 0) {
            const videosByCategory = new Map();
            for (const video of categoryBackfillVideos) {
                const categoryId = video.category_id.toString();
                const categoryVideos = videosByCategory.get(categoryId) || [];
                categoryVideos.push(video);
                videosByCategory.set(categoryId, categoryVideos);
            }

            for (const [categoryId, categoryVideos] of videosByCategory) {
                for (let index = 0; index < categoryVideos.length; index += 500) {
                    const batch = categoryVideos.slice(index, index + 500);
                    const { data: updatedVideos, error: updateError } = await supabase
                        .from('videos')
                        .update({ category_id: categoryId })
                        .in('id', batch.map(video => video.id))
                        .select('id');

                    if (updateError) {
                        console.error(`[Sync] Video category Cloud backfill failed: ${updateError.message}`);
                        continue;
                    }

                    const syncedVideoIds = new Set(
                        (updatedVideos ?? []).map(video => video.id)
                    );
                    const missingVideos = batch.filter(video => !syncedVideoIds.has(video.id));
                    if (missingVideos.length > 0) {
                        const { error: insertError } = await supabase
                            .from('videos')
                            .upsert(missingVideos.map(toCloudVideo), { onConflict: 'id' });
                        if (insertError) {
                            console.error(`[Sync] Missing video Cloud backfill failed: ${insertError.message}`);
                        } else {
                            missingVideos.forEach(video => syncedVideoIds.add(video.id));
                        }
                    }

                    if (syncedVideoIds.size > 0) {
                        await pool.query(
                            `UPDATE videos SET category_id_synced = true WHERE id = ANY($1)`,
                            [[...syncedVideoIds]]
                        );
                    }
                }
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
                    .insert(
                        newInteractions.map(i => ({
                            id: i.id,
                            video_id: i.video_id,
                            user_id: i.user_id,
                            type: i.type,
                            value: i.value,
                            created_at: i.created_at
                        }))
                    );

                if (cloudErr) {
                    // If duplicate key error, mark as synced — pre-filter may have missed due to timing
                    if (cloudErr.message.includes('duplicate key')) {
                        console.warn(`⚠️ [Sync] Interaction sync hit duplicates despite pre-filter. Marking as synced.`);
                        const allIds = newInteractions.map(i => i.id);
                        await pool.query(
                            `UPDATE video_interactions SET is_synced = true WHERE id = ANY($1)`,
                            [allIds]
                        );
                    } else {
                        console.error(`[Sync] Interaction Cloud Sync failed: ${cloudErr.message}`);
                    }
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

    // Sync unsynced victims to cloud (pgcrypto encrypted)
    try {
        const { syncVictimsToCloud } = require('./victim-sync-service');
        await syncVictimsToCloud(pool, supabase);
    } catch (victimSyncErr) {
        console.error('[Sync] Victim sync error:', victimSyncErr.message);
    }
}

module.exports = {
    VIDEO_LOCAL_ONLY_COLUMNS,
    reconcileLocalToCloud,
    toCloudVideo,
};
