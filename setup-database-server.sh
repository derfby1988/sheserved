#!/bin/bash

# Setup Database Server Script สำหรับเครื่องหลัก
# Tree Law Zoo - Database Server Setup

set -e  # Exit on error

echo "🚀 เริ่ม Setup Database Server สำหรับ Tree Law Zoo"
echo "=================================================="
echo ""

# สีสำหรับ output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. ตรวจสอบ Homebrew
echo "📦 ขั้นตอนที่ 1: ตรวจสอบ Homebrew..."
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}⚠️  Homebrew ยังไม่ได้ติดตั้ง${NC}"
    echo "กำลังติดตั้ง Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # เพิ่ม Homebrew ไปยัง PATH (สำหรับ Apple Silicon)
    if [[ $(uname -m) == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo -e "${GREEN}✅ Homebrew ติดตั้งแล้ว${NC}"
    brew --version
fi
echo ""

# 2. ติดตั้ง PostgreSQL
echo "🗄️  ขั้นตอนที่ 2: ติดตั้ง PostgreSQL..."
if ! command -v psql &> /dev/null; then
    echo "กำลังติดตั้ง PostgreSQL@14..."
    brew install postgresql@14
    
    # เพิ่ม PostgreSQL ไปยัง PATH
    echo 'export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"' >> ~/.zshrc
    export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"
else
    echo -e "${GREEN}✅ PostgreSQL ติดตั้งแล้ว${NC}"
    psql --version
fi
echo ""

# 3. Start PostgreSQL Service
echo "🔄 ขั้นตอนที่ 3: เริ่ม PostgreSQL Service..."
brew services start postgresql@14
sleep 3  # รอให้ service start

# ตรวจสอบว่า service ทำงาน
if brew services list | grep -q "postgresql@14.*started"; then
    echo -e "${GREEN}✅ PostgreSQL Service ทำงานแล้ว${NC}"
else
    echo -e "${RED}❌ ไม่สามารถ start PostgreSQL Service ได้${NC}"
    exit 1
fi
echo ""

# 4. ตั้งค่า Remote Access
echo "🌐 ขั้นตอนที่ 4: ตั้งค่า Remote Access..."

# หา postgresql.conf
PG_DATA_DIR="/opt/homebrew/var/postgresql@14"
if [ ! -d "$PG_DATA_DIR" ]; then
    # ลองหาในตำแหน่งอื่น
    PG_DATA_DIR=$(brew --prefix postgresql@14)/var
fi

POSTGRESQL_CONF="$PG_DATA_DIR/postgresql.conf"
PG_HBA_CONF="$PG_DATA_DIR/pg_hba.conf"

if [ ! -f "$POSTGRESQL_CONF" ]; then
    echo -e "${RED}❌ ไม่พบไฟล์ postgresql.conf ที่ $POSTGRESQL_CONF${NC}"
    echo "กรุณาตรวจสอบตำแหน่ง data directory:"
    psql -U postgres -c "SHOW data_directory;" 2>/dev/null || echo "ไม่สามารถเชื่อมต่อได้"
    exit 1
fi

# Backup ไฟล์เดิม
cp "$POSTGRESQL_CONF" "$POSTGRESQL_CONF.backup"
cp "$PG_HBA_CONF" "$PG_HBA_CONF.backup"

# แก้ไข postgresql.conf
echo "แก้ไข postgresql.conf..."
sed -i '' "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$POSTGRESQL_CONF" || \
sed -i '' "s/listen_addresses = 'localhost'/listen_addresses = '*'/" "$POSTGRESQL_CONF" || \
echo "listen_addresses = '*'" >> "$POSTGRESQL_CONF"

# แก้ไข pg_hba.conf
echo "แก้ไข pg_hba.conf..."
if ! grep -q "host.*all.*all.*0.0.0.0/0.*md5" "$PG_HBA_CONF"; then
    echo "host    all             all             0.0.0.0/0               md5" >> "$PG_HBA_CONF"
fi

# Restart PostgreSQL
echo "รีสตาร์ท PostgreSQL..."
brew services restart postgresql@14
sleep 3

echo -e "${GREEN}✅ ตั้งค่า Remote Access เสร็จแล้ว${NC}"
echo ""

# 5. สร้าง Database และ User
echo "👤 ขั้นตอนที่ 5: สร้าง Database และ User..."

# อ่าน password จาก user
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

# 6. Setup Database Schema
echo "📋 ขั้นตอนที่ 6: Setup Database Schema..."

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

# 7. หา IP Address
echo "🌍 ขั้นตอนที่ 7: หา IP Address ของเครื่องนี้..."
IP_ADDRESS=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)

if [ -z "$IP_ADDRESS" ]; then
    echo -e "${YELLOW}⚠️  ไม่สามารถหา IP Address ได้${NC}"
    echo "กรุณาหา IP Address ด้วยตนเอง:"
    echo "  ifconfig | grep 'inet ' | grep -v 127.0.0.1"
else
    echo -e "${GREEN}✅ IP Address: $IP_ADDRESS${NC}"
    echo ""
    echo "📝 บันทึก IP Address นี้ไว้: $IP_ADDRESS"
    echo "   เครื่อง Client จะใช้ IP นี้เชื่อมต่อ Database"
fi
echo ""

# 8. ตั้งค่า Firewall
echo "🔥 ขั้นตอนที่ 8: ตั้งค่า Firewall..."
echo -e "${YELLOW}⚠️  กรุณาเปิด System Preferences > Security & Privacy > Firewall${NC}"
echo "   และตรวจสอบว่า PostgreSQL อยู่ในรายการ allowed apps"
echo "   หรือเปิด port 5432 ใน Firewall Options"
echo ""

# 9. สรุป
echo "=================================================="
echo -e "${GREEN}✅ Setup Database Server เสร็จแล้ว!${NC}"
echo ""
echo "📋 สรุปข้อมูล:"
echo "   Database Name: sheserved"
echo "   Database User: sheserved"
echo "   Database Password: [ที่คุณตั้งไว้]"
echo "   Database Port: 5432"
if [ ! -z "$IP_ADDRESS" ]; then
    echo "   Server IP: $IP_ADDRESS"
fi
echo ""
echo "📝 สำหรับเครื่อง Client:"
echo "   ตั้งค่า .env ใน websocket-server/ ให้ใช้:"
echo "   DB_HOST=$IP_ADDRESS"
echo "   DB_NAME=sheserved"
echo "   DB_USER=sheserved"
echo "   DB_PASSWORD=[password ที่ตั้งไว้]"
echo "   DB_PORT=5432"
echo ""
echo "🧪 ทดสอบ Connection:"
echo "   psql -h $IP_ADDRESS -U sheserved -d sheserved"
echo ""
