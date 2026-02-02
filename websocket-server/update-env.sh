#!/bin/bash

# Update .env file with correct database user

CURRENT_USER=$(whoami)

echo "Updating .env file with user: $CURRENT_USER"

cat > .env << EOF
# Database Configuration
DB_HOST=localhost
DB_NAME=sheserved
DB_USER=$CURRENT_USER
DB_PASSWORD=
DB_PORT=5432

# Server Configuration
PORT=3000

# Database Usage (set to false to disable database)
USE_DATABASE=true
EOF

echo "✅ .env file updated"
echo ""
echo "Current settings:"
echo "  DB_USER=$CURRENT_USER"
echo "  DB_NAME=sheserved"
echo "  DB_PASSWORD=(empty - no password needed)"
echo ""
echo "Restart server to apply changes:"
echo "  npm start"
