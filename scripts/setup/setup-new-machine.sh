#!/bin/bash

# Setup script for new Client Machine
# สำหรับ macOS - Client Machine ที่เชื่อมต่อไปที่ Remote Database Server

set -e  # Exit on error

echo "🚀 Starting setup for new Client Machine..."

# ตรวจสอบว่าเป็น macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script is for macOS only"
    exit 1
fi

# 1. Flutter dependencies
echo ""
echo "📦 Installing Flutter dependencies..."
if ! command -v flutter &> /dev/null; then
    echo "⚠️  Flutter not found. Please install Flutter first:"
    echo "   brew install flutter"
    exit 1
fi
flutter pub get

# 2. iOS pods
echo ""
echo "🍎 Installing iOS pods..."
if [ -d "ios" ]; then
    cd ios
    if ! command -v pod &> /dev/null; then
        echo "⚠️  CocoaPods not found. Installing..."
        sudo gem install cocoapods
    fi
    pod install
    cd ..
else
    echo "⚠️  iOS directory not found, skipping..."
fi

# 3. macOS pods
echo ""
echo "💻 Installing macOS pods..."
if [ -d "macos" ]; then
    cd macos
    pod install
    cd ..
else
    echo "⚠️  macOS directory not found, skipping..."
fi

# 4. WebSocket server dependencies
echo ""
echo "🔌 Installing WebSocket server dependencies..."
cd websocket-server

if ! command -v npm &> /dev/null; then
    echo "❌ npm not found. Please install Node.js first:"
    echo "   brew install node"
    exit 1
fi

npm install

# 5. Create .env from template
echo ""
echo "📝 Setting up .env file..."
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        echo "📋 Copying from .env.example..."
        cp .env.example .env
    else
        echo "⚠️  .env.example not found. Creating new .env file..."
    fi
    
    echo ""
    echo "⚠️  Please enter Remote Database Server information:"
    read -p "DB Server IP (from Database Server admin): " db_host
    read -p "DB User (default: sheserved): " db_user
    read -sp "DB Password: " db_password
    echo ""
    
    # Update .env file
    if [ -f .env ]; then
        # Update existing .env
        sed -i '' "s|^DB_HOST=.*|DB_HOST=${db_host}|" .env
        sed -i '' "s|^DB_USER=.*|DB_USER=${db_user:-sheserved}|" .env
        sed -i '' "s|^DB_PASSWORD=.*|DB_PASSWORD=${db_password}|" .env
        sed -i '' "s|^DB_NAME=.*|DB_NAME=sheserved|" .env
    else
        # Create new .env
        cat > .env << EOF
# Database Configuration - Remote Database Server
DB_HOST=${db_host}
DB_NAME=sheserved
DB_USER=${db_user:-sheserved}
DB_PASSWORD=${db_password}
DB_PORT=5432

# Server Configuration
PORT=3000

# Database Usage
USE_DATABASE=true

# JWT (สำหรับอนาคต)
JWT_SECRET=change_this_in_production
JWT_EXPIRES_IN=7d
EOF
    fi
    
    echo "✅ Created .env file. Please verify the values."
else
    echo "✅ .env file already exists. Skipping creation."
    echo "⚠️  Please verify that DB_HOST points to Remote Database Server"
fi

cd ..

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Verify websocket-server/.env points to Remote Database Server"
echo "2. Test database connection:"
echo "   cd websocket-server && ./test-remote-db.sh"
echo "3. Start WebSocket server: cd websocket-server && npm start"
echo "4. Run Flutter app: flutter run -d chrome"
echo ""
echo "⚠️  Make sure Database Server is running and accessible!"
