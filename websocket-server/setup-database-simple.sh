#!/bin/bash

# Simple Database Setup Script
# Uses current system user instead of 'postgres'

echo "🗄️  Setting up database with current user..."

# Get current username
CURRENT_USER=$(whoami)
echo "Using user: $CURRENT_USER"

# Database name
DB_NAME=${DB_NAME:-sheserved}

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo "❌ psql not found"
    echo ""
    echo "Please install PostgreSQL first:"
    echo "  brew install postgresql@14"
    echo "  brew services start postgresql@14"
    exit 1
fi

# Create database
echo "Creating database '$DB_NAME'..."
createdb $DB_NAME 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Database created"
else
    echo "⚠️  Database might already exist (this is OK)"
fi

# Run schema
echo "Running database schema..."
psql -d $DB_NAME -f database.sql

if [ $? -eq 0 ]; then
    echo "✅ Database schema created successfully"
    echo ""
    echo "Update your .env file:"
    echo "  DB_USER=$CURRENT_USER"
    echo "  DB_NAME=$DB_NAME"
    echo "  DB_PASSWORD="
else
    echo "❌ Failed to create database schema"
    exit 1
fi
