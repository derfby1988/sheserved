require('dotenv').config();
const { Pool } = require('pg');

async function runSeed() {
  if (process.env.NODE_ENV !== 'development') {
    console.error('❌ CRITICAL ERROR: This script can only be run in development environment.');
    console.error('Make sure NODE_ENV=development is set in your .env file.');
    process.exit(1);
  }

  const userId = process.argv[2];
  if (!userId) {
    console.error('Usage: node dev-seed.js <userId>');
    process.exit(1);
  }

  const USE_DATABASE = process.env.USE_DATABASE !== 'false';
  if (!USE_DATABASE) {
    console.log('Database disabled, skipping seed.');
    process.exit(0);
  }

  const pool = new Pool({
    host: process.env.DB_HOST || 'localhost',
    database: process.env.DB_NAME || 'sheserved',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'password',
    port: process.env.DB_PORT || 5432,
  });

  try {
    const username = `user_${userId.substring(0, 5)}`;
    // 1. Ensure user exists
    await pool.query(
      `INSERT INTO users (id, first_name, username, verification_status) 
       VALUES ($1, $2, $3, 'verified')
       ON CONFLICT (id) DO NOTHING`,
      [userId, 'Dev User', username]
    );

    // 2. Ensure consumer profile exists (for volunteer_active status)
    await pool.query(
      `INSERT INTO consumer_profiles (user_id, is_volunteer_active) 
       VALUES ($1, true)
       ON CONFLICT (user_id) DO NOTHING`,
      [userId]
    );

    // 3. Ensure they have a volunteer role
    await pool.query(
      `INSERT INTO user_group_roles (user_id, profession_id) 
       VALUES ($1, '4d4101e0-7bd3-4f87-bc35-b5371f21432c')
       ON CONFLICT DO NOTHING`,
      [userId]
    );
    console.log(`✅ [Dev] Auto-seeded user ${userId} as Rescuer successfully.`);
  } catch (err) {
    console.warn('⚠️ [Dev] Auto-seed failed:', err.message);
  } finally {
    pool.end();
  }
}

runSeed();
