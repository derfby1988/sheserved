'use strict';
// Temporary read-only diagnostic: which users own/manage the venues that
// received venue_booking notifications, and who the notifications went to.
require('dotenv').config();
const { Client } = require('pg');

const host = process.env.SUPABASE_DB_HOST;
const isPooler = /pooler\.supabase\.com$/i.test(host || '');
const port = parseInt(process.env.SUPABASE_DB_LISTEN_PORT, 10)
  || (isPooler ? 5432 : parseInt(process.env.SUPABASE_DB_PORT, 10) || 5432);
const sslMode = (process.env.SUPABASE_DB_SSL || '').trim().toLowerCase();

const client = new Client({
  host,
  port,
  database: process.env.SUPABASE_DB_NAME || 'postgres',
  user: process.env.SUPABASE_DB_USER,
  password: process.env.SUPABASE_DB_PASSWORD,
  ssl: sslMode && sslMode !== 'false' ? { rejectUnauthorized: false } : false,
});

const TEST_USERS = [
  '5028dbc4-fa50-4818-8470-be684e928605', // iOS "sister"
  'd0396578-ddd9-4acc-bf62-6459909cba14', // Android "ttt"
  '03bb3c92-8f27-4305-b400-ea20c38b5348', // owner profile on the bookings
];

(async () => {
  await client.connect();

  const venues = await client.query(
    `SELECT v.id, v.name, op.user_id AS owner_user_id,
            COALESCE((SELECT array_agg(m.user_id)
                        FROM public.sports_venue_owner_members m
                       WHERE m.venue_id = v.id AND m.is_active), '{}') AS active_members
       FROM public.sports_venues v
       JOIN public.sports_venue_owner_profiles op ON op.id = v.owner_profile_id
      ORDER BY v.created_at DESC
      LIMIT 20`);
  console.log('VENUES\n' + JSON.stringify(venues.rows, null, 2));

  const notifs = await client.query(
    `SELECT n.recipient_id, n.title, n.created_at,
            n.payload->>'bookingId' AS booking_id
       FROM public.app_notifications n
      WHERE n.category = 'venue_booking'
      ORDER BY n.created_at DESC
      LIMIT 20`);
  console.log('NOTIFS\n' + JSON.stringify(notifs.rows, null, 2));

  const related = await client.query(
    `SELECT u.id, u.first_name, u.last_name, u.username, u.is_active,
            (SELECT count(*) FROM public.sports_venue_owner_profiles p
              WHERE p.user_id = u.id) AS owner_profiles,
            (SELECT count(*) FROM public.sports_venue_owner_members m
              WHERE m.user_id = u.id AND m.is_active) AS active_memberships
       FROM public.users u
      WHERE u.id = ANY($1::uuid[])`,
    [TEST_USERS]);
  console.log('TEST_USERS\n' + JSON.stringify(related.rows, null, 2));

  const profile = await client.query(
    `SELECT op.user_id, op.status, v.id AS venue_id, v.name AS venue_name, v.status AS venue_status
       FROM public.sports_venue_owner_profiles op
       LEFT JOIN public.sports_venues v ON v.owner_profile_id = op.id
      ORDER BY op.created_at DESC`);
  console.log('OWNER_PROFILES\n' + JSON.stringify(profile.rows, null, 2));

  await client.end();
})().catch((error) => {
  console.error('ERR', error.message);
  process.exit(1);
});
