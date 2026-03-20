#!/bin/bash

# Script สำหรับ Format External Drive เป็น APFS
# Tree Law Zoo - Format External Drive

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "💾 Format External Drive เป็น APFS"
echo "===================================="
echo ""

# ⚠️ คำเตือน
echo -e "${RED}⚠️  คำเตือน: การ format จะลบข้อมูลทั้งหมดใน drive!${NC}"
echo ""
read -p "คุณได้ backup ข้อมูลสำคัญแล้วหรือยัง? (y/n): " BACKUP_CONFIRM

if [ "$BACKUP_CONFIRM" != "y" ] && [ "$BACKUP_CONFIRM" != "Y" ]; then
    echo -e "${YELLOW}กรุณา backup ข้อมูลก่อน format!${NC}"
    exit 0
fi

echo ""
echo "📦 External Drives ที่พบ:"
echo ""

# แสดง external drives
MOUNTED_DRIVES=()
while IFS= read -r line; do
    if [ ! -z "$line" ]; then
        MOUNTED_DRIVES+=("$line")
        echo "  $line"
    fi
done < <(df -h | grep Volumes | grep -v "/System/Volumes" | awk '{print $9 " - " $2 " (เหลือ: " $4 ")"}')

if [ ${#MOUNTED_DRIVES[@]} -eq 0 ]; then
    echo -e "${YELLOW}ไม่พบ external drives ที่ mount อยู่${NC}"
    echo ""
    echo "กรุณา mount external drive ก่อน หรือใช้คำสั่ง:"
    echo "  diskutil list"
    exit 1
fi

echo ""
read -p "กรุณาใส่ mount point ของ drive ที่ต้องการ format (เช่น /Volumes/Dave_240G): " MOUNT_POINT

if [ ! -d "$MOUNT_POINT" ]; then
    echo -e "${RED}❌ ไม่พบ directory: $MOUNT_POINT${NC}"
    exit 1
fi

# หา device name (whole disk)
VOLUME_DEVICE=$(diskutil info "$MOUNT_POINT" 2>/dev/null | grep "Device Node" | awk '{print $3}')

if [ -z "$VOLUME_DEVICE" ]; then
    echo -e "${RED}❌ ไม่สามารถหา device name ได้${NC}"
    exit 1
fi

# แปลง volume device เป็น whole disk device (เช่น /dev/disk4s1 -> /dev/disk4)
DEVICE=$(echo "$VOLUME_DEVICE" | sed 's/s[0-9]*$//')

if [ -z "$DEVICE" ] || [ "$DEVICE" = "$VOLUME_DEVICE" ]; then
    # ถ้าไม่สามารถแปลงได้ ลองหา whole disk จาก diskutil
    DISK_ID=$(diskutil info "$MOUNT_POINT" 2>/dev/null | grep "Disk / Partition" | awk '{print $2}' | cut -d's' -f1)
    if [ ! -z "$DISK_ID" ]; then
        DEVICE="/dev/$DISK_ID"
    else
        echo -e "${RED}❌ ไม่สามารถหา whole disk device ได้${NC}"
        exit 1
    fi
fi

# แสดงข้อมูล
echo ""
echo "📋 ข้อมูล Drive:"
echo "   Mount Point: $MOUNT_POINT"
echo "   Volume Device: $VOLUME_DEVICE"
echo "   Whole Disk Device: $DEVICE"
echo ""

# ยืนยันอีกครั้ง
echo -e "${RED}⚠️  คุณแน่ใจหรือไม่ว่าต้องการ format drive นี้?${NC}"
echo -e "${RED}   ข้อมูลทั้งหมดจะถูกลบและไม่สามารถกู้คืนได้!${NC}"
read -p "พิมพ์ 'YES' เพื่อยืนยัน: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo -e "${YELLOW}ยกเลิกการ format${NC}"
    exit 0
fi

# Unmount
echo ""
echo "🛑 Unmounting drive..."
diskutil unmountDisk "$DEVICE" || {
    echo -e "${YELLOW}⚠️  Unmount ไม่สำเร็จ ลอง force unmount...${NC}"
    diskutil unmountDisk force "$DEVICE" || {
        echo -e "${RED}❌ ไม่สามารถ unmount ได้${NC}"
        exit 1
    }
}

sleep 2

# Format
echo ""
echo "💾 Formatting เป็น APFS..."
diskutil eraseDisk APFS "PostgreSQL" "$DEVICE"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Format สำเร็จ!${NC}"
    echo ""
    
    # ตรวจสอบ
    sleep 2
    if [ -d "/Volumes/PostgreSQL" ]; then
        FS=$(diskutil info /Volumes/PostgreSQL | grep "File System" | awk -F: '{print $2}' | xargs)
        echo "📋 ข้อมูล Drive ใหม่:"
        echo "   Mount Point: /Volumes/PostgreSQL"
        echo "   File System: $FS"
        echo ""
        echo -e "${GREEN}✅ Drive พร้อมใช้งานแล้ว!${NC}"
        echo ""
        echo "ขั้นตอนถัดไป:"
        echo "  cd /Users/dave_macmini/tree_law_zoo"
        echo "  ./setup-postgresql-external-hfs.sh"
        echo ""
        echo "เมื่อ script ถาม external drive ให้ใส่:"
        echo "  /Volumes/PostgreSQL"
    else
        echo -e "${YELLOW}⚠️  Drive อาจยังไม่ mount อัตโนมัติ${NC}"
        echo "ลอง mount ด้วยตนเอง:"
        echo "  diskutil mount $DEVICE"
    fi
else
    echo -e "${RED}❌ Format ไม่สำเร็จ${NC}"
    exit 1
fi
