#!/bin/bash

# Setup PostgreSQL บน External Drive (HFS+ หรือ APFS)
# Tree Law Zoo - Database Server Setup
# ใช้สำหรับ drive ที่เป็น HFS+ หรือ APFS (ไม่ใช่ ExFAT)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🗄️  Setup PostgreSQL บน External Drive (HFS+/APFS)"
echo "=================================================="
echo ""

# ตรวจสอบ Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${RED}❌ Homebrew ยังไม่ได้ติดตั้ง${NC}"
    exit 1
fi

# แสดง External Drives พร้อม filesystem
echo "📦 External Drives ที่พบ:"
echo ""
for drive in /Volumes/*; do
    if [ -d "$drive" ] && [ "$drive" != "/Volumes/Macintosh HD" ] && [ "$drive" != "/Volumes/Data" ]; then
        fs=$(diskutil info "$drive" 2>/dev/null | grep "File System" | awk -F: '{print $2}' | xargs)
        size=$(df -h "$drive" 2>/dev/null | tail -1 | awk '{print $2}')
        free=$(df -h "$drive" 2>/dev/null | tail -1 | awk '{print $4}')
        if [ ! -z "$fs" ]; then
            if [[ "$fs" == *"HFS"* ]] || [[ "$fs" == *"APFS"* ]]; then
                echo -e "  ${GREEN}$drive - $fs - $size (เหลือ: $free) ✅ แนะนำ${NC}"
            else
                echo -e "  ${YELLOW}$drive - $fs - $size (เหลือ: $free) ⚠️  ExFAT (อาจมีปัญหา)${NC}"
            fi
        fi
    fi
done
echo ""

# เลือก External Drive
read -p "กรุณาใส่ path ของ External Drive ที่ต้องการใช้ (แนะนำ: HFS+ หรือ APFS): " EXTERNAL_DRIVE

if [ ! -d "$EXTERNAL_DRIVE" ]; then
    echo -e "${RED}❌ ไม่พบ directory: $EXTERNAL_DRIVE${NC}"
    exit 1
fi

# เช็ค filesystem
FS=$(diskutil info "$EXTERNAL_DRIVE" 2>/dev/null | grep "File System" | awk -F: '{print $2}' | xargs)

if [[ "$FS" == *"ExFAT"* ]]; then
    echo -e "${YELLOW}⚠️  ข้อเตือน: External drive นี้เป็น ExFAT${NC}"
    echo "   ExFAT อาจมีปัญหาเรื่องไฟล์ AppleDouble"
    echo "   แนะนำให้ใช้ drive ที่เป็น HFS+ หรือ APFS"
    read -p "ต้องการดำเนินการต่อหรือไม่? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        exit 0
    fi
fi

echo -e "${GREEN}✅ ใช้ External Drive: $EXTERNAL_DRIVE ($FS)${NC}"
echo ""

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

# หยุด PostgreSQL
echo "🛑 หยุด PostgreSQL service..."
brew services stop postgresql@14 2>/dev/null || true
sleep 2

# สร้าง data directory
PG_DATA_DIR="$EXTERNAL_DRIVE/postgresql-data"
echo "📁 สร้าง data directory: $PG_DATA_DIR"

if [ -d "$PG_DATA_DIR" ]; then
    echo "🗑️  ลบ data directory เก่า..."
    sudo rm -rf "$PG_DATA_DIR"
fi

mkdir -p "$PG_DATA_DIR"
sudo chown -R $(whoami) "$PG_DATA_DIR"

# ตั้งค่าให้ไม่สร้างไฟล์ AppleDouble (สำหรับ ExFAT)
if [[ "$FS" == *"ExFAT"* ]]; then
    echo "🔧 ตั้งค่าให้ไม่สร้างไฟล์ AppleDouble..."
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true 2>/dev/null || true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true 2>/dev/null || true
fi

# Initialize database cluster
echo "🔧 Initialize database cluster..."
/opt/homebrew/opt/postgresql@14/bin/initdb -D "$PG_DATA_DIR"

# ลบไฟล์ AppleDouble (ถ้ามี)
if [[ "$FS" == *"ExFAT"* ]]; then
    echo "🧹 ลบไฟล์ AppleDouble..."
    if command -v dot_clean &> /dev/null; then
        dot_clean -m "$PG_DATA_DIR" 2>/dev/null || true
    fi
    find "$PG_DATA_DIR" -name "._*" -type f -delete 2>/dev/null || true
    find "$PG_DATA_DIR" -name ".DS_Store" -type f -delete 2>/dev/null || true
fi

echo -e "${GREEN}✅ Initialize database cluster เสร็จแล้ว${NC}"
echo ""

# ตั้งค่า Environment Variable
echo "⚙️  ตั้งค่า Environment Variable..."
if ! grep -q "PGDATA=$PG_DATA_DIR" ~/.zshrc 2>/dev/null; then
    echo "export PGDATA=$PG_DATA_DIR" >> ~/.zshrc
fi
export PGDATA="$PG_DATA_DIR"
echo ""

# แก้ไข postgresql.conf
echo "📝 แก้ไข postgresql.conf..."
POSTGRESQL_CONF="$PG_DATA_DIR/postgresql.conf"
cp "$POSTGRESQL_CONF" "$POSTGRESQL_CONF.backup"

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
cp "$PG_HBA_CONF" "$PG_HBA_CONF.backup"

if ! grep -q "host.*all.*all.*0.0.0.0/0.*md5" "$PG_HBA_CONF"; then
    echo "" >> "$PG_HBA_CONF"
    echo "# Remote access for Tree Law Zoo" >> "$PG_HBA_CONF"
    echo "host    all             all             0.0.0.0/0               md5" >> "$PG_HBA_CONF"
fi

echo -e "${GREEN}✅ แก้ไข pg_hba.conf เสร็จแล้ว${NC}"
echo ""

# Start PostgreSQL
echo "🚀 เริ่ม PostgreSQL..."
/opt/homebrew/opt/postgresql@14/bin/pg_ctl -D "$PG_DATA_DIR" -l "$PG_DATA_DIR/server.log" start

# รอให้ PostgreSQL พร้อม (รอสูงสุด 10 วินาที)
echo "⏳ รอให้ PostgreSQL พร้อม..."
for i in {1..10}; do
    sleep 1
    if pg_isready -D "$PG_DATA_DIR" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PostgreSQL ทำงานแล้ว${NC}"
        break
    fi
    if [ $i -eq 10 ]; then
        echo -e "${YELLOW}⚠️  PostgreSQL เริ่มต้นแล้ว แต่ยังไม่พร้อม${NC}"
        echo "ตรวจสอบ log: tail -f $PG_DATA_DIR/server.log"
        echo "ลองตรวจสอบด้วยตนเอง: pg_isready -D $PG_DATA_DIR"
        # ไม่ exit เพราะอาจจะทำงานได้แล้ว
    fi
done
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
else
    echo -e "${GREEN}✅ IP Address: $IP_ADDRESS${NC}"
fi
echo ""

# สรุป
echo "=================================================="
echo -e "${GREEN}✅ Setup PostgreSQL บน External Drive เสร็จแล้ว!${NC}"
echo ""
echo "📋 สรุปข้อมูล:"
echo "   Data Directory: $PG_DATA_DIR"
echo "   Filesystem: $FS"
echo "   Database Name: tree_law_zoo"
echo "   Database User: sheserved"
echo "   Database Password: [ที่คุณตั้งไว้]"
echo "   Database Port: 5432"
echo "   Server IP: $IP_ADDRESS"
echo ""
echo "📝 สำหรับเครื่อง Client:"
echo "   DB_HOST=$IP_ADDRESS"
echo "   DB_NAME=sheserved"
echo "   DB_USER=sheserved"
echo "   DB_PASSWORD=[password ที่ตั้งไว้]"
echo "   DB_PORT=5432"
echo ""
