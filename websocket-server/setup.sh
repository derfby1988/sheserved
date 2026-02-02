#!/bin/bash

# Setup Script for WebSocket Server
# This script will help you setup the WebSocket server and database

echo "🚀 Setting up WebSocket Server for Tree Law Zoo..."
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js first."
    echo "   Visit: https://nodejs.org/"
    exit 1
fi

echo "✅ Node.js version: $(node --version)"

# Check if PostgreSQL is installed
if ! command -v psql &> /dev/null; then
    echo "❌ PostgreSQL is not installed. Please install PostgreSQL first."
    echo "   Visit: https://www.postgresql.org/download/"
    exit 1
fi

echo "✅ PostgreSQL is installed"
echo ""

# Step 1: Install npm dependencies
echo "📦 Installing npm dependencies..."
npm install

if [ $? -ne 0 ]; then
    echo "❌ Failed to install dependencies"
    exit 1
fi

echo "✅ Dependencies installed"
echo ""

# Step 2: Setup environment variables
echo "⚙️  Setting up environment variables..."

if [ ! -f .env ]; then
    echo "Creating .env file..."
    cat > .env << EOF
# Database Configuration
DB_HOST=localhost
DB_NAME=sheserved
DB_USER=sheserved
DB_PASSWORD=
DB_PORT=5432

# Server Configuration
PORT=3000
EOF
    echo "✅ .env file created"
    echo "⚠️  Please edit .env file with your database credentials"
else
    echo "✅ .env file already exists"
fi

echo ""

# Step 3: Setup database
echo "🗄️  Setting up database..."

read -p "Enter PostgreSQL password (default: postgres): " db_password
db_password=${db_password:-postgres}

read -p "Enter database name (default: sheserved): " db_name
db_name=${db_name:-sheserved}

read -p "Enter database user (default: sheserved): " db_user
db_user=${db_user:-sheserved}

echo ""
echo "Creating database..."

# Create database
PGPASSWORD=$db_password psql -U $db_user -h localhost -c "CREATE DATABASE $db_name;" 2>/dev/null || echo "Database might already exist"

# Run SQL script
echo "Running database schema..."
PGPASSWORD=$db_password psql -U $db_user -h localhost -d $db_name -f database.sql

if [ $? -eq 0 ]; then
    echo "✅ Database setup completed"
else
    echo "⚠️  Database setup had some issues. Please check manually."
fi

echo ""
echo "🎉 Setup completed!"
echo ""
echo "Next steps:"
echo "1. Edit .env file with your database credentials"
echo "2. Run: npm start (or npm run dev for development)"
echo "3. Server will run on http://localhost:3000"
