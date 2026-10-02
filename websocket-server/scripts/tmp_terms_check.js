'use strict';
require('dotenv').config();
const { Client } = require('pg');
const host = process.env.SUPABASE_DB_HOST;
const isPooler = /pooler\.supabase\.com$/i.test(host || '');
const port = parseInt(process.env.SUPABASE_DB_LISTEN_PORT, 10)
  || (isPooler ? 5432 : parseInt(process.env.SUPABASE_DB_PORT, 10) || 5432);
const sslMode = (process.env.SUPABASE_DB_SSL || '').trim().toLowerCase();
const client = new Client({
  host, port,
  database: process.env.SUPABASE_DB_NAME || 'postgres',
  user: process.env.SUPABASE_DB_USER,
  password: process.env.SUPABASE_DB_PASSWORD,
  ssl: sslMode && sslMode !== 'false' ? { rejectUnauthorized: false } : false,
});
(async () => {
  await client.connect();
  const tables = await client.query(
    `SELECT tablename FROM pg_tables WHERE schemaname='public'
       AND (tablename ILIKE '%term%' OR tablename ILIKE '%venue%') ORDER BY 1`);
  console.log('TABLES', tables.rows.map(r => r.tablename).join(', '));
  for (const t of ['sports_venue_terms','sports_venue_platform_terms']) {
    try {
      const cols = await client.query(
        `SELECT column_name FROM information_schema.columns
          WHERE table_schema='public' AND table_name=$1 ORDER BY ordinal_position`, [t]);
      console.log(t, 'cols:', cols.rows.map(r=>r.column_name).join(','));
      const rows = await client.query(`SELECT * FROM public.${t} LIMIT 10`);
      console.log(t, JSON.stringify(rows.rows, null, 1));
    } catch (e) { console.log(t, 'ERR', e.message); }
  }
  await client.end();
})().catch(e => { console.error(e); process.exit(1); });
