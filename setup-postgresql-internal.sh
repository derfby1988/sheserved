#!/bin/bash

# Setup PostgreSQL บน Internal Drive (แนะนำ)
# Tree Law Zoo - Database Server Setup

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🗄️  Setup PostgreSQL บน Internal Drive (แนะนำ)"
echo "=============================================="
echo ""

# ตรวจสอบ Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${RED}❌ Homebrew ยังไม่ได้ติดตั้ง${NC}"
    exit 1
fi

# ตรวจสอบ PostgreSQL
if ! command -v psql &> /dev/null; then
    echo "📦 ติดตั้ง PostgreSQL@14..."
    brew install postgresql@14
    echo 'export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"' >> ~/.zshrc
    export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"
else
    echo -e "${GREEN}✅ PostgreSQL ติดตั้งแล้ว${NC}"
    psql --version
fi
echo ""

# ใช้ default data directory ของ Homebrew
PG_DATA_DIR="/opt/homebrew/var/postgresql@14"

# ตรวจสอบว่า database cluster มีอยู่แล้วหรือไม่
if [ -f "$PG_DATA_DIR/PG_VERSION" ]; then
    echo -e "${YELLOW}⚠️  Database cluster มีอยู่แล้วที่ $PG_DATA_DIR${NC}"
    read -p "ต้องการลบและสร้างใหม่หรือไม่? (y/n): " RECREATE
    if [ "$RECREATE" = "y" ] || [ "$RECREATE" = "Y" ]; then
        echo "🛑 หยุด PostgreSQL service..."
        brew services stop postgresql@14 2>/dev/null || true
        sleep 2
        echo "🗑️  ลบ database cluster เก่า..."
        sudo rm -rf "$PG_DATA_DIR"
        echo "🔧 Initialize database cluster ใหม่..."
        /opt/homebrew/opt/postgresql@14/bin/initdb --locale=en_US.UTF-8 -E UTF-8 "$PG_DATA_DIR"
        echo -e "${GREEN}✅ Initialize database cluster เสร็จแล้ว${NC}"
    else
        echo "ใช้ database cluster ที่มีอยู่แล้ว"
    fi
else
    echo "🔧 Initialize database cluster..."
    /opt/homebrew/opt/postgresql@14/bin/initdb --locale=en_US.UTF-8 -E UTF-8 "$PG_DATA_DIR"
    echo -e "${GREEN}✅ Initialize database cluster เสร็จแล้ว${NC}"
fi
echo ""

# แก้ไข postgresql.conf
echo "📝 แก้ไข postgresql.conf..."
POSTGRESQL_CONF="$PG_DATA_DIR/postgresql.conf"

# Backup
if [ ! -f "$POSTGRESQL_CONF.backup" ]; then
    cp "$POSTGRESQL_CONF" "$POSTGRESQL_CONF.backup"
fi

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
if [ ! -f "$PG_HBA_CONF.backup" ]; then
    cp "$PG_HBA_CONF" "$PG_HBA_CONF.backup"
fi

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
echo "🚀 เริ่ม PostgreSQL service..."
brew services start postgresql@14
sleep 3

# ตรวจสอบว่า start สำเร็จ
if brew services list | grep -q "postgresql@14.*started"; then
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

psql -U postgres <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'sheserved') THEN
        CREATE USER sheserved WITH PASSWORD '$DB_PASSWORD';
    ELSE
        ALTER USER sheserved WITH PASSWORD '$DB_PASSWORD';
    END IF;
END
\$\$;

SELECT 'CREATE DATABASE sheserved OWNER sheserved'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'sheserved')\gexec

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
    IP_ADDRESS="<กรุณาหาด้วยตนเอง>"
    echo -e "${YELLOW}⚠️  ไม่สามารถหา IP Address ได้${NC}"
else
    echo -e "${GREEN}✅ IP Address: $IP_ADDRESS${NC}"
fi
echo ""

# สรุป
echo "=============================================="
echo -e "${GREEN}✅ Setup PostgreSQL บน Internal Drive เสร็จแล้ว!${NC}"
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
echo "💡 หมายเหตุ:"
echo "   - ใช้ internal drive ซึ่งไม่มีปัญหาเรื่อง AppleDouble"
echo "   - PostgreSQL จะ auto-start เมื่อ boot"
echo "   - ถ้าต้องการย้ายไป external drive ทีหลัง สามารถทำได้"
echo ""
