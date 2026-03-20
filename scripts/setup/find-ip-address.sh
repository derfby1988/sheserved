#!/bin/bash

# Script สำหรับหา IP Address ของเครื่องนี้
# Tree Law Zoo - Find IP Address

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🌍 หา IP Address ของเครื่องนี้"
echo "=============================="
echo ""

# วิธีที่ 1: ใช้ ipconfig (en0 - Ethernet/WiFi)
echo "วิธีที่ 1: ipconfig getifaddr en0"
IP1=$(ipconfig getifaddr en0 2>/dev/null)
if [ ! -z "$IP1" ]; then
    echo -e "${GREEN}✅ IP Address: $IP1${NC}"
else
    echo -e "${YELLOW}⚠️  ไม่พบ IP ที่ en0${NC}"
fi
echo ""

# วิธีที่ 2: ใช้ ipconfig (en1 - WiFi/Ethernet อื่น)
echo "วิธีที่ 2: ipconfig getifaddr en1"
IP2=$(ipconfig getifaddr en1 2>/dev/null)
if [ ! -z "$IP2" ]; then
    echo -e "${GREEN}✅ IP Address: $IP2${NC}"
else
    echo -e "${YELLOW}⚠️  ไม่พบ IP ที่ en1${NC}"
fi
echo ""

# วิธีที่ 3: ใช้ ifconfig
echo "วิธีที่ 3: ifconfig"
IP3=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
if [ ! -z "$IP3" ]; then
    echo -e "${GREEN}✅ IP Address: $IP3${NC}"
else
    echo -e "${YELLOW}⚠️  ไม่พบ IP${NC}"
fi
echo ""

# แสดง IP ที่พบทั้งหมด
echo "📋 IP Address ที่พบ:"
ALL_IPS=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}')
if [ ! -z "$ALL_IPS" ]; then
    echo "$ALL_IPS" | while read ip; do
        echo "  - $ip"
    done
else
    echo -e "${YELLOW}⚠️  ไม่พบ IP Address${NC}"
fi
echo ""

# แนะนำ IP ที่น่าจะถูกต้อง
if [ ! -z "$IP1" ]; then
    RECOMMENDED_IP="$IP1"
elif [ ! -z "$IP2" ]; then
    RECOMMENDED_IP="$IP2"
elif [ ! -z "$IP3" ]; then
    RECOMMENDED_IP="$IP3"
else
    RECOMMENDED_IP=""
fi

if [ ! -z "$RECOMMENDED_IP" ]; then
    echo "💡 แนะนำใช้ IP: $RECOMMENDED_IP"
    echo ""
    echo "🧪 ทดสอบ Connection:"
    echo "  nc -zv $RECOMMENDED_IP 5432"
    echo "  psql -h $RECOMMENDED_IP -U sheserved -d sheserved"
else
    echo -e "${YELLOW}⚠️  ไม่สามารถหา IP Address ได้${NC}"
    echo "ลองใช้คำสั่ง:"
    echo "  ifconfig | grep 'inet '"
fi
echo ""
