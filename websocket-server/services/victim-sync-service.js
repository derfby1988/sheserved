'use strict';

const PGCRYPTO_KEY = process.env.VICTIM_PGCRYPTO_KEY || process.env.SUPABASE_SERVICE_KEY || '';

async function syncVictimsToCloud(pool, supabaseClient) {
  if (!pool || !supabaseClient) {
    console.warn('[VictimSync] Pool or Supabase client not available, skipping');
    return;
  }
  if (!PGCRYPTO_KEY) {
    console.warn('[VictimSync] VICTIM_PGCRYPTO_KEY not set, skipping cloud sync');
    return;
  }

  try {
    const result = await pool.query(
      `SELECT id, incident_id, prefix, first_name, last_name, masked_name,
              triage_level, triaged_by, triaged_at, triage_note,
              triaged_by_profession_id, triaged_by_profession_category,
              verify_status, is_deleted, reported_by, created_at, updated_at
         FROM incident_victims
        WHERE is_synced = FALSE
        ORDER BY updated_at ASC
        LIMIT 100`
    );

    if (result.rows.length === 0) return;

    const cloudRows = [];
    const syncedIds = [];

    for (const row of result.rows) {
      let firstNameEnc = null;
      let lastNameEnc = null;

      if (row.first_name) {
        const encRes = await pool.query(
          `SELECT encrypt_victim_name($1, $2) AS enc`,
          [row.first_name, PGCRYPTO_KEY]
        );
        firstNameEnc = encRes.rows[0]?.enc;
      }
      if (row.last_name) {
        const encRes = await pool.query(
          `SELECT encrypt_victim_name($1, $2) AS enc`,
          [row.last_name, PGCRYPTO_KEY]
        );
        lastNameEnc = encRes.rows[0]?.enc;
      }

      cloudRows.push({
        id: row.id,
        incident_id: row.incident_id,
        prefix: row.prefix,
        first_name_enc: firstNameEnc,
        last_name_enc: lastNameEnc,
        masked_name: row.masked_name,
        triage_level: row.triage_level,
        triaged_by: row.triaged_by,
        triaged_at: row.triaged_at,
        triage_note: row.triage_note,
        triaged_by_profession_id: row.triaged_by_profession_id,
        triaged_by_profession_category: row.triaged_by_profession_category,
        verify_status: row.verify_status,
        is_deleted: row.is_deleted,
        reported_by: row.reported_by,
        created_at: row.created_at,
        updated_at: row.updated_at,
        synced_at: new Date().toISOString(),
      });
      syncedIds.push(row.id);
    }

    const { error } = await supabaseClient
      .from('cloud_incident_victims')
      .upsert(cloudRows, { onConflict: 'id' });

    if (error) {
      console.error('[VictimSync] Supabase upsert error:', error.message);
      return;
    }

    await pool.query(
      `UPDATE incident_victims SET is_synced = TRUE WHERE id = ANY($1::uuid[])`,
      [syncedIds]
    );

    console.log(`[VictimSync] Synced ${syncedIds.length} victim records to cloud`);
  } catch (err) {
    console.error('[VictimSync] Error:', err.message);
  }
}

module.exports = { syncVictimsToCloud };
