#!/bin/bash

# Test Remote Database Connection Script
# สำหรับทดสอบการเชื่อมต่อไปยัง Remote Database Server

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "❌ .env file not found"
    echo "   Please create .env file first or copy from .env.example"
    exit 1
fi

echo "🔍 Testing Remote Database Connection..."
echo ""
echo "Configuration:"
echo "  Host: ${DB_HOST:-localhost}"
echo "  Database: ${DB_NAME:-sheserved}"
echo "  User: ${DB_USER:-sheserved}"
echo "  Port: ${DB_PORT:-5432}"
echo ""

# Test 1: Network connectivity
echo "1️⃣  Testing network connectivity..."
if command -v ping &> /dev/null; then
    if ping -c 1 -W 2 "${DB_HOST}" &> /dev/null; then
        echo "   ✅ Network reachable"
    else
        echo "   ⚠️  Cannot ping ${DB_HOST} (may be normal if ping is disabled)"
    fi
else
    echo "   ⚠️  ping command not available"
fi

# Test 2: Port connectivity
echo ""
echo "2️⃣  Testing port connectivity..."
if command -v nc &> /dev/null; then
    if nc -zv -w 2 "${DB_HOST}" "${DB_PORT:-5432}" 2>&1 | grep -q "succeeded"; then
        echo "   ✅ Port ${DB_PORT:-5432} is open"
    else
        echo "   ❌ Cannot connect to port ${DB_PORT:-5432}"
        echo "   ⚠️  Check firewall and Database Server status"
    fi
else
    echo "   ⚠️  nc (netcat) command not available, skipping port test"
fi

# Test 3: PostgreSQL connection (using psql)
echo ""
echo "3️⃣  Testing PostgreSQL connection..."
if command -v psql &> /dev/null; then
    export PGPASSWORD="${DB_PASSWORD}"
    if psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" -p "${DB_PORT:-5432}" -c "SELECT NOW();" &> /dev/null; then
        echo "   ✅ PostgreSQL connection successful!"
        echo ""
        echo "   Database info:"
        psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" -p "${DB_PORT:-5432}" -c "SELECT version();" 2>/dev/null | head -3
    else
        echo "   ❌ PostgreSQL connection failed"
        echo "   ⚠️  Check credentials and Database Server configuration"
        exit 1
    fi
    unset PGPASSWORD
else
    echo "   ⚠️  psql command not available"
    echo "   Install PostgreSQL client: brew install libpq"
fi

# Test 4: Node.js connection test
echo ""
echo "4️⃣  Testing via Node.js (WebSocket Server method)..."
if command -v node &> /dev/null; then
    node -e "
    require('dotenv').config();
    const {Pool} = require('pg');
    const pool = new Pool({
        host: process.env.DB_HOST,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_NAME,
        port: process.env.DB_PORT || 5432,
    });
    pool.query('SELECT NOW() as current_time, current_database() as database_name')
        .then(result => {
            console.log('   ✅ Node.js connection successful!');
            console.log('   Database:', result.rows[0].database_name);
            console.log('   Server time:', result.rows[0].current_time);
            pool.end();
            process.exit(0);
        })
        .catch(err => {
            console.error('   ❌ Node.js connection failed:', err.message);
            pool.end();
            process.exit(1);
        });
    " 2>&1 | grep -v "node_modules" || true
else
    echo "   ⚠️  node command not available"
    echo "   Install Node.js: brew install node"
fi

echo ""
echo "✅ All tests completed!"
echo ""
echo "If all tests passed, you can start the WebSocket server:"
echo "  npm start"
