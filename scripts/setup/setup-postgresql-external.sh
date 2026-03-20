#!/bin/bash

# Setup PostgreSQL บน External Drive
# Tree Law Zoo - Database Server Setup

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🗄️  Setup PostgreSQL บน External Drive"
echo "======================================"
echo ""

# ตรวจสอบ Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${RED}❌ Homebrew ยังไม่ได้ติดตั้ง${NC}"
    echo "กรุณาติดตั้ง Homebrew ก่อน:"
    echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

# แสดง External Drives ที่มี
echo "📦 External Drives ที่พบ:"
df -h | grep -E "^/dev/disk" | grep Volumes | awk '{print "  " $9 " - " $2 " (เหลือ: " $4 ")"}'
echo ""

# เลือก External Drive
read -p "กรุณาใส่ path ของ External Drive ที่ต้องการใช้ (เช่น /Volumes/Dave_1T): " EXTERNAL_DRIVE

if [ ! -d "$EXTERNAL_DRIVE" ]; then
    echo -e "${RED}❌ ไม่พบ directory: $EXTERNAL_DRIVE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ ใช้ External Drive: $EXTERNAL_DRIVE${NC}"
echo ""

# ตรวจสอบ PostgreSQL
if ! command -v psql &> /dev/null; then
    echo "📦 ติดตั้ง PostgreSQL@14..."
    brew install postgresql@14
    
    # เพิ่ม PostgreSQL ไปยัง PATH
    echo 'export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"' >> ~/.zshrc
    export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"
else
    echo -e "${GREEN}✅ PostgreSQL ติดตั้งแล้ว${NC}"
    psql --version
fi
echo ""

# หยุด PostgreSQL (ถ้ากำลังรันอยู่)
echo "🛑 หยุด PostgreSQL service..."
brew services stop postgresql@14 2>/dev/null || true
sleep 2

# สร้าง data directory
PG_DATA_DIR="$EXTERNAL_DRIVE/postgresql-data"
echo "📁 สร้าง data directory: $PG_DATA_DIR"

# ลบ directory เก่า (ถ้ามี) เพื่อเริ่มใหม่
if [ -d "$PG_DATA_DIR" ]; then
    echo "🗑️  ลบ data directory เก่า..."
    sudo rm -rf "$PG_DATA_DIR"
fi

mkdir -p "$PG_DATA_DIR"

# ตั้งค่า ownership
echo "🔐 ตั้งค่า ownership..."
sudo chown -R $(whoami) "$PG_DATA_DIR"

# ป้องกันการสร้างไฟล์ AppleDouble บน external drive
echo "🔧 ป้องกันการสร้างไฟล์ AppleDouble..."
# ตั้งค่าให้ macOS ไม่สร้างไฟล์ ._* บน external drive
defaults write com.apple.desktopservices DSDontWriteNetworkStores true 2>/dev/null || true

# Initialize database cluster
if [ ! -f "$PG_DATA_DIR/PG_VERSION" ]; then
    echo "🔧 Initialize database cluster..."
    
    # ตั้งค่าให้ macOS ไม่สร้างไฟล์ AppleDouble (สำหรับ ExFAT drives)
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true 2>/dev/null || true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true 2>/dev/null || true
    
    # Initialize
    /opt/homebrew/opt/postgresql@14/bin/initdb -D "$PG_DATA_DIR"
    
    # ใช้ dot_clean เพื่อลบไฟล์ AppleDouble (ถ้ามี)
    if command -v dot_clean &> /dev/null; then
        echo "🧹 ใช้ dot_clean เพื่อลบไฟล์ AppleDouble..."
        dot_clean -m "$PG_DATA_DIR" 2>/dev/null || true
    fi
    
    # ลบไฟล์ AppleDouble ที่เหลืออยู่
    find "$PG_DATA_DIR" -name "._*" -type f -delete 2>/dev/null || true
    find "$PG_DATA_DIR" -name ".DS_Store" -type f -delete 2>/dev/null || true
    
    echo -e "${GREEN}✅ Initialize database cluster เสร็จแล้ว${NC}"
else
    echo -e "${YELLOW}⚠️  Database cluster มีอยู่แล้วที่ $PG_DATA_DIR${NC}"
fi
echo ""

# ตั้งค่า Environment Variable
echo "⚙️  ตั้งค่า Environment Variable..."
if ! grep -q "PGDATA=$PG_DATA_DIR" ~/.zshrc 2>/dev/null; then
    echo "export PGDATA=$PG_DATA_DIR" >> ~/.zshrc
    echo -e "${GREEN}✅ เพิ่ม PGDATA ใน ~/.zshrc${NC}"
fi
export PGDATA="$PG_DATA_DIR"
echo ""

# แก้ไข postgresql.conf
echo "📝 แก้ไข postgresql.conf..."
POSTGRESQL_CONF="$PG_DATA_DIR/postgresql.conf"

# Backup
cp "$POSTGRESQL_CONF" "$POSTGRESQL_CONF.backup"

# แก้ไข listen_addresses
if grep -q "^listen_addresses" "$POSTGRESQL_CONF"; then
    sed -i '' "s/^listen_addresses.*/listen_addresses = '*'/" "$POSTGRESQL_CONF"
else
    echo "listen_addresses = '*'" >> "$POSTGRESQL_CONF"
fi

echo -e "${GREEN}✅ แก้ไข postgresql.conf เสร็จแล้ว${NC}"
echo ""

# แก้ไข pg_hba.conf
echo "📝 แก้ไข pg_hba.conf..."
PG_HBA_CONF="$PG_DATA_DIR/pg_hba.conf"

# Backup
cp "$PG_HBA_CONF" "$PG_HBA_CONF.backup"

# เพิ่ม rule สำหรับ remote access (ถ้ายังไม่มี)
if ! grep -q "host.*all.*all.*0.0.0.0/0.*md5" "$PG_HBA_CONF"; then
    echo "" >> "$PG_HBA_CONF"
    echo "# Remote access for Tree Law Zoo" >> "$PG_HBA_CONF"
    echo "host    all             all             0.0.0.0/0               md5" >> "$PG_HBA_CONF"
    echo -e "${GREEN}✅ เพิ่ม remote access rule ใน pg_hba.conf${NC}"
else
    echo -e "${YELLOW}⚠️  Remote access rule มีอยู่แล้ว${NC}"
fi
echo ""

# Start PostgreSQL
echo "🚀 เริ่ม PostgreSQL..."
/opt/homebrew/opt/postgresql@14/bin/pg_ctl -D "$PG_DATA_DIR" -l "$PG_DATA_DIR/server.log" start

sleep 3

# ตรวจสอบว่า start สำเร็จ
if pg_isready -D "$PG_DATA_DIR" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PostgreSQL ทำงานแล้ว${NC}"
else
    echo -e "${RED}❌ PostgreSQL ไม่สามารถ start ได้${NC}"
    echo "ตรวจสอบ log: tail -f $PG_DATA_DIR/server.log"
    exit 1
fi
echo ""

# สร้าง Database และ User
echo "👤 สร้าง Database และ User..."
read -sp "กรุณาใส่ password สำหรับ sheserved: " DB_PASSWORD
echo ""
read -p "ยืนยัน password อีกครั้ง: " DB_PASSWORD_CONFIRM

if [ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]; then
    echo -e "${RED}❌ Password ไม่ตรงกัน${NC}"
    exit 1
fi

# สร้าง user และ database
psql -U postgres <<EOF
-- สร้าง user (ถ้ายังไม่มี)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'sheserved') THEN
        CREATE USER sheserved WITH PASSWORD '$DB_PASSWORD';
    ELSE
        ALTER USER sheserved WITH PASSWORD '$DB_PASSWORD';
    END IF;
END
\$\$;

-- สร้าง database (ถ้ายังไม่มี)
SELECT 'CREATE DATABASE sheserved OWNER sheserved'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'sheserved')\gexec

-- ให้สิทธิ์
GRANT ALL PRIVILEGES ON DATABASE sheserved TO sheserved;
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ สร้าง Database และ User เสร็จแล้ว${NC}"
else
    echo -e "${RED}❌ ไม่สามารถสร้าง Database และ User ได้${NC}"
    exit 1
fi
echo ""

# Setup Database Schema
echo "📋 Setup Database Schema..."
SCHEMA_FILE="websocket-server/database.sql"
if [ ! -f "$SCHEMA_FILE" ]; then
    echo -e "${RED}❌ ไม่พบไฟล์ $SCHEMA_FILE${NC}"
    exit 1
fi

PGPASSWORD="$DB_PASSWORD" psql -U sheserved -d sheserved -f "$SCHEMA_FILE"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Setup Database Schema เสร็จแล้ว${NC}"
else
    echo -e "${RED}❌ ไม่สามารถ setup schema ได้${NC}"
    exit 1
fi
echo ""

# หา IP Address
echo "🌍 หา IP Address..."
IP_ADDRESS=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)

if [ -z "$IP_ADDRESS" ]; then
    echo -e "${YELLOW}⚠️  ไม่สามารถหา IP Address ได้${NC}"
    IP_ADDRESS="<กรุณาหาด้วยตนเอง>"
else
    echo -e "${GREEN}✅ IP Address: $IP_ADDRESS${NC}"
fi
echo ""

# สรุป
echo "======================================"
echo -e "${GREEN}✅ Setup PostgreSQL บน External Drive เสร็จแล้ว!${NC}"
echo ""
echo "📋 สรุปข้อมูล:"
echo "   Data Directory: $PG_DATA_DIR"
echo "   Database Name: tree_law_zoo"
echo "   Database User: sheserved"
echo "   Database Password: [ที่คุณตั้งไว้]"
echo "   Database Port: 5432"
echo "   Server IP: $IP_ADDRESS"
echo ""
echo "📝 สำหรับเครื่อง Client:"
echo "   ตั้งค่า .env ใน websocket-server/ ให้ใช้:"
echo "   DB_HOST=$IP_ADDRESS"
echo "   DB_NAME=sheserved"
echo "   DB_USER=sheserved"
echo "   DB_PASSWORD=[password ที่ตั้งไว้]"
echo "   DB_PORT=5432"
echo ""
echo "⚠️  หมายเหตุ:"
echo "   - External drive ($EXTERNAL_DRIVE) ต้อง mount อยู่เสมอ"
echo "   - ตั้งค่า auto-mount ใน System Preferences > Users & Groups > Login Items"
echo "   - ตรวจสอบ disk space เป็นประจำ: df -h"
echo ""
