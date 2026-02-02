#!/bin/bash

# Continue PostgreSQL Setup หลังจาก start แล้ว
# Tree Law Zoo - Database Server Setup

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🗄️  Continue PostgreSQL Setup"
echo "=============================="
echo ""

# ตั้งค่า PGDATA
PG_DATA_DIR="/Volumes/PostgreSQL/postgresql-data"
export PGDATA="$PG_DATA_DIR"

# ตรวจสอบว่า PostgreSQL ทำงานอยู่หรือไม่
echo "🔍 ตรวจสอบ PostgreSQL..."
if pg_isready > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PostgreSQL ทำงานอยู่${NC}"
else
    echo -e "${YELLOW}⚠️  PostgreSQL ยังไม่ทำงาน กำลังเริ่มต้น...${NC}"
    /opt/homebrew/opt/postgresql@14/bin/pg_ctl -D "$PG_DATA_DIR" -l "$PG_DATA_DIR/server.log" start
    sleep 3
fi
echo ""

# ใช้ username ของผู้ใช้เป็น superuser (macOS Homebrew)
SUPERUSER=$(whoami)
echo "👤 ใช้ superuser: $SUPERUSER (macOS Homebrew ไม่มี role 'postgres')"
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
psql -U "$SUPERUSER" -d postgres <<EOF
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
    IP_ADDRESS="<กรุณาหาด้วยตนเอง>"
    echo -e "${YELLOW}⚠️  ไม่สามารถหา IP Address ได้${NC}"
else
    echo -e "${GREEN}✅ IP Address: $IP_ADDRESS${NC}"
fi
echo ""

# สรุป
echo "=============================="
echo -e "${GREEN}✅ PostgreSQL Setup เสร็จแล้ว!${NC}"
echo ""
echo "📋 สรุปข้อมูล:"
echo "   Data Directory: $PG_DATA_DIR"
echo "   Database Name: sheserved"
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
