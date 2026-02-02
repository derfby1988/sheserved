#!/bin/bash

# Database Setup Script
# This script will create the database and run the schema

echo "🗄️  Setting up PostgreSQL database for Tree Law Zoo..."
echo ""

# Default values
DB_HOST=${DB_HOST:-localhost}
DB_NAME=${DB_NAME:-sheserved}
DB_USER=${DB_USER:-sheserved}
DB_PORT=${DB_PORT:-5432}

# Prompt for password
read -sp "Enter PostgreSQL password for user '$DB_USER': " DB_PASSWORD
echo ""

# Function to run SQL command
run_sql() {
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -p $DB_PORT -c "$1"
}

# Function to run SQL file
run_sql_file() {
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -p $DB_PORT -d $DB_NAME -f "$1"
}

# Step 1: Check if PostgreSQL is running
echo "Checking PostgreSQL connection..."
if ! PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -p $DB_PORT -c "SELECT 1;" > /dev/null 2>&1; then
    echo "❌ Cannot connect to PostgreSQL"
    echo "   Please check:"
    echo "   - PostgreSQL is running"
    echo "   - Host: $DB_HOST"
    echo "   - Port: $DB_PORT"
    echo "   - User: $DB_USER"
    echo "   - Password is correct"
    exit 1
fi

echo "✅ PostgreSQL connection successful"
echo ""

# Step 2: Create database
echo "Creating database '$DB_NAME'..."
run_sql "CREATE DATABASE $DB_NAME;" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Database created"
else
    echo "⚠️  Database might already exist (this is OK)"
fi
echo ""

# Step 3: Run schema
echo "Running database schema..."
if [ -f database.sql ]; then
    run_sql_file database.sql
    if [ $? -eq 0 ]; then
        echo "✅ Database schema created successfully"
    else
        echo "❌ Failed to create database schema"
        exit 1
    fi
else
    echo "❌ database.sql file not found"
    exit 1
fi

echo ""
echo "🎉 Database setup completed!"
echo ""
echo "Database information:"
echo "  Host: $DB_HOST"
echo "  Port: $DB_PORT"
echo "  Database: $DB_NAME"
echo "  User: $DB_USER"
echo ""
echo "You can now update your .env file with these credentials"
