#!/bin/bash

# =====================================================
# Sheserved - Local Database Setup Script
# =====================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================
Sheserved - Local Database Setup
=====================================================${NC}"

# Default values
DB_NAME="${DB_NAME:-sheserved}"
DB_USER="${DB_USER:-sheserved}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo -e "${RED}❌ psql ไม่พบ กรุณาติดตั้ง PostgreSQL ก่อน${NC}"
    echo "   brew install postgresql@14"
    exit 1
fi

echo -e "${YELLOW}📋 ข้อมูล Database:${NC}"
echo "   Host: $DB_HOST"
echo "   Port: $DB_PORT"
echo "   Database: $DB_NAME"
echo "   User: $DB_USER"
echo ""

# Prompt for action
echo -e "${YELLOW}เลือกการทำงาน:${NC}"
echo "  1) Fresh Install - สร้าง schema ใหม่ทั้งหมด"
echo "  2) Migration - อัพเกรดจาก schema เดิม"
echo "  3) Check Status - ตรวจสอบสถานะ database"
echo "  4) Exit"
echo ""
read -p "เลือก (1-4): " choice

case $choice in
    1)
        echo -e "\n${BLUE}🔧 Fresh Install - สร้าง schema ใหม่...${NC}"
        
        # Check if database exists
        if psql -h "$DB_HOST" -p "$DB_PORT" -U postgres -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
            echo -e "${YELLOW}⚠️  Database '$DB_NAME' มีอยู่แล้ว${NC}"
            read -p "ต้องการลบและสร้างใหม่หรือไม่? (y/n): " confirm
            if [ "$confirm" = "y" ]; then
                echo "กำลังลบ database เดิม..."
                psql -h "$DB_HOST" -p "$DB_PORT" -U postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
            else
                echo "ยกเลิก"
                exit 0
            fi
        fi
        
        # Create database
        echo "กำลังสร้าง database..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U postgres -c "CREATE DATABASE $DB_NAME;"
        
        # Create user if not exists
        echo "กำลังสร้าง user..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U postgres -c "CREATE USER $DB_USER WITH PASSWORD 'sheserved123';" 2>/dev/null || true
        psql -h "$DB_HOST" -p "$DB_PORT" -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
        
        # Run schema
        echo "กำลังสร้าง tables..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$(dirname "$0")/schema.sql"
        
        echo -e "${GREEN}✅ Fresh Install เสร็จสมบูรณ์!${NC}"
        ;;
        
    2)
        echo -e "\n${BLUE}🔄 Migration - อัพเกรดจาก schema เดิม...${NC}"
        
        if ! psql -h "$DB_HOST" -p "$DB_PORT" -U postgres -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
            echo -e "${RED}❌ Database '$DB_NAME' ไม่พบ${NC}"
            echo "กรุณาใช้ Fresh Install แทน"
            exit 1
        fi
        
        # Backup reminder
        echo -e "${YELLOW}⚠️  สำคัญ: กรุณา backup database ก่อน!${NC}"
        echo "   pg_dump -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME > backup.sql"
        read -p "Backup แล้วหรือยัง? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            echo "ยกเลิก"
            exit 0
        fi
        
        # Run migration
        echo "กำลัง migrate..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$(dirname "$0")/migrate-from-old-schema.sql"
        
        echo -e "${GREEN}✅ Migration เสร็จสมบูรณ์!${NC}"
        ;;
        
    3)
        echo -e "\n${BLUE}📊 ตรวจสอบสถานะ Database...${NC}"
        
        if ! psql -h "$DB_HOST" -p "$DB_PORT" -U postgres -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
            echo -e "${RED}❌ Database '$DB_NAME' ไม่พบ${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}✅ Database '$DB_NAME' พบแล้ว${NC}"
        echo ""
        echo -e "${YELLOW}📋 รายการ Tables:${NC}"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "\dt"
        
        echo ""
        echo -e "${YELLOW}📊 จำนวนข้อมูล:${NC}"
        
        # Count rows in each table
        for table in professions users locations registration_field_configs; do
            count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "N/A")
            echo "   $table: $count rows"
        done
        ;;
        
    4)
        echo "ออก"
        exit 0
        ;;
        
    *)
        echo -e "${RED}❌ ตัวเลือกไม่ถูกต้อง${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}=====================================================
Connection Info:
=====================================================
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=sheserved123
=====================================================${NC}"
