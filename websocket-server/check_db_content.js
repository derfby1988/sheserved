const { Pool } = require('pg');
require('dotenv').config({ path: '/Users/dave_macmini/sheserved/websocket-server/.env' });

async function check() {
    const pool = new Pool({
        host: process.env.DB_HOST || 'localhost',
        database: process.env.DB_NAME || 'sheserved',
        user: process.env.DB_USER || 'postgres',
        password: process.env.DB_PASSWORD || 'password',
        port: process.env.DB_PORT || 5432,
    });

    try {
        const res = await pool.query('SELECT * FROM videos');
        console.log('Videos count:', res.rows.length);
        console.log('Videos:', JSON.stringify(res.rows, null, 2));

        const res2 = await pool.query('SELECT * FROM donation_categories');
        console.log('Categories count:', res2.rows.length);

        const res3 = await pool.query('SELECT * FROM incident_responses');
        console.log('Incident Responses count:', res3.rows.length);

    } catch (err) {
        console.error('Error:', err.message);
    } finally {
        await pool.end();
    }
}

check();
