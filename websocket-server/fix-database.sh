#!/bin/bash

# Fix Database Schema Script
# This script will update the database schema to remove FOREIGN KEY constraint

echo "🔧 Fixing database schema..."

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

DB_HOST=${DB_HOST:-localhost}
DB_NAME=${DB_NAME:-sheserved}
DB_USER=${DB_USER:-sheserved}
DB_PORT=${DB_PORT:-5432}

read -sp "Enter PostgreSQL password for user '$DB_USER': " DB_PASSWORD
echo ""

# Drop and recreate locations table without FOREIGN KEY
echo "Updating locations table..."

PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -p $DB_PORT -d $DB_NAME << EOF
-- Drop existing table if exists
DROP TABLE IF EXISTS locations CASCADE;

-- Recreate locations table without FOREIGN KEY constraint
CREATE TABLE locations (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    accuracy DECIMAL(10, 2),
    speed DECIMAL(10, 2),
    heading DECIMAL(5, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Recreate indexes
CREATE INDEX IF NOT EXISTS idx_locations_user_id ON locations(user_id);
CREATE INDEX IF NOT EXISTS idx_locations_created_at ON locations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_locations_user_created ON locations(user_id, created_at DESC);
EOF

if [ $? -eq 0 ]; then
    echo "✅ Database schema updated successfully"
else
    echo "❌ Failed to update database schema"
    exit 1
fi
