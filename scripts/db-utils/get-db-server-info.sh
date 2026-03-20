#!/bin/bash

# Script สำหรับแสดงข้อมูล Database Server
# Tree Law Zoo - Database Server Info

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "📋 ข้อมูล Database Server"
echo "========================"
echo ""

# หา IP Address
echo "🌍 IP Address:"
IP_ADDRESS=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)

if [ -z "$IP_ADDRESS" ]; then
    echo -e "${YELLOW}⚠️  ไม่สามารถหา IP Address ได้${NC}"
    echo "ลองใช้คำสั่ง:"
    echo "  ipconfig getifaddr en0"
    echo "  หรือ"
    echo "  ifconfig | grep 'inet ' | grep -v 127.0.0.1"
else
    echo -e "${GREEN}✅ IP Address: $IP_ADDRESS${NC}"
fi
echo ""

# ตรวจสอบ PostgreSQL
echo "🗄️  PostgreSQL Status:"
if pg_isready > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PostgreSQL ทำงานอยู่${NC}"
    echo "   Port: 5432"
else
    echo -e "${YELLOW}⚠️  PostgreSQL ไม่ทำงาน${NC}"
fi
echo ""

# ตรวจสอบ Database
echo "📊 Database Info:"
PG_DATA_DIR="/Volumes/PostgreSQL/postgresql-data"
if [ -d "$PG_DATA_DIR" ]; then
    echo "   Data Directory: $PG_DATA_DIR"
    echo "   Filesystem: APFS"
else
    echo -e "${YELLOW}⚠️  ไม่พบ data directory${NC}"
fi
echo ""

# สรุปข้อมูลสำหรับ Client
echo "📝 สำหรับเครื่อง Client (.env):"
echo "================================"
if [ ! -z "$IP_ADDRESS" ]; then
    echo "DB_HOST=$IP_ADDRESS"
    echo "DB_NAME=sheserved"
    echo "DB_USER=sheserved"
    echo "DB_PASSWORD=<password ที่ตั้งไว้>"
    echo "DB_PORT=5432"
    echo ""
    echo "🧪 ทดสอบ Connection:"
    echo "  nc -zv $IP_ADDRESS 5432"
    echo "  psql -h $IP_ADDRESS -U sheserved -d sheserved"
else
    echo "กรุณาหา IP Address ก่อน"
fi
echo ""
