#!/bin/bash

# Script สำหรับตรวจสอบ Database Schema
# Tree Law Zoo - Check Database Schema

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "📊 ตรวจสอบ Database Schema"
echo "==========================="
echo ""

# ตรวจสอบว่า PostgreSQL ทำงานอยู่หรือไม่
if ! pg_isready > /dev/null 2>&1; then
    echo -e "${RED}❌ PostgreSQL ไม่ทำงาน${NC}"
    exit 1
fi

echo -e "${GREEN}✅ PostgreSQL ทำงานอยู่${NC}"
echo ""

# ตรวจสอบ tables
echo "📋 ตรวจสอบ Tables ใน Database:"
TABLES=$(psql -U sheserved -d sheserved -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null)

if [ -z "$TABLES" ] || [ "$TABLES" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  ยังไม่มี tables ใน database${NC}"
    echo ""
    echo "ต้องรัน database.sql:"
    echo "  cd /Users/dave_macmini/sheserved/websocket-server"
    echo "  PGPASSWORD='<password>' psql -U sheserved -d sheserved -f database.sql"
else
    echo -e "${GREEN}✅ พบ $TABLES tables ใน database${NC}"
    echo ""
    echo "รายการ Tables:"
    psql -U sheserved -d sheserved -c "\dt" 2>/dev/null || echo "ไม่สามารถแสดง tables ได้"
fi
echo ""
