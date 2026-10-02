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
  const r = await client.query(
    `SELECT b.id, b.status, b.starts_at, b.ends_at,
            b.cancellation_cutoff_minutes_snapshot AS cutoff_min,
            b.starts_at - make_interval(mins => b.cancellation_cutoff_minutes_snapshot) AS cutoff_at,
            now() AS db_now,
            (now() >= b.starts_at - make_interval(mins => b.cancellation_cutoff_minutes_snapshot)) AS cutoff_passed,
            v.name AS venue_name, v.timezone, c.name AS court_name,
            b.accepted_terms_version, b.created_at
       FROM public.sports_venue_bookings b
       JOIN public.sports_venues v ON v.id = b.venue_id
       JOIN public.sports_venue_courts c ON c.id = b.court_id
      WHERE b.status IN ('pending','confirmed')
      ORDER BY b.created_at DESC
      LIMIT 15`);
  for (const row of r.rows) console.log(JSON.stringify(row));
  await client.end();
})().catch(e => { console.error(e); process.exit(1); });
