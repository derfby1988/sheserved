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
        // (This would normally be in a migration script, keeping here for robustness)
        await pool.query(`
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_name='video_interactions' AND column_name='is_synced'
                ) THEN
                    ALTER TABLE video_interactions ADD COLUMN is_synced BOOLEAN DEFAULT false;
                END IF;
            END $$;
        `);

        // --- 2. Synchronize Video Interactions (Likes/Views) ---
        const { rows: unsyncedInteractions } = await pool.query(
            `SELECT id, video_id, user_id, type, value, created_at 
             FROM video_interactions 
             WHERE is_synced = false 
             ORDER BY created_at ASC`
        );

        if (unsyncedInteractions.length > 0) {
            console.log(`[Sync] Found ${unsyncedInteractions.length} unsynced interactions. Syncing...`);
            
            // Push to Supabase Cloud (Batch)
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
                console.error(`[Sync] Cloud Sync failed: ${cloudErr.message}`);
                throw cloudErr;
            }

            // Mark as synced locally
            const syncedIds = unsyncedInteractions.map(i => i.id);
            await pool.query(
                `UPDATE video_interactions SET is_synced = true WHERE id = ANY($1)`,
                [syncedIds]
            );
            
            console.log(`✅ [Sync] Successfully synced ${unsyncedInteractions.length} interactions.`);
        } else {
            console.log(`[Sync] No pending video interactions to sync.`);
        }
        
        // --- 3. You can add more sync routines for IncidentResponses or GPS tracks here ---

    } catch (error) {
        console.error('❌ [Sync] Reconciliation error:', error.message);
    }
}

module.exports = {
    reconcileLocalToCloud
};
