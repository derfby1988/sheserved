#!/bin/bash

# แก้ไขปัญหา AppleDouble files บน External Drive
# สำหรับ PostgreSQL

EXTERNAL_DRIVE="/Volumes/Dave_240G"
PG_DATA_DIR="$EXTERNAL_DRIVE/postgresql-data"

echo "🔧 แก้ไขปัญหา AppleDouble files..."

# วิธีที่ 1: ใช้ dot_clean (แนะนำ)
if command -v dot_clean &> /dev/null; then
    echo "ใช้ dot_clean เพื่อลบไฟล์ AppleDouble..."
    dot_clean -m "$PG_DATA_DIR" 2>/dev/null || true
fi

# วิธีที่ 2: ลบไฟล์ ._* ทั้งหมด
echo "ลบไฟล์ ._* ทั้งหมด..."
find "$PG_DATA_DIR" -name "._*" -type f -delete 2>/dev/null || true
find "$PG_DATA_DIR" -name ".DS_Store" -type f -delete 2>/dev/null || true

# วิธีที่ 3: ตั้งค่าให้ macOS ไม่สร้างไฟล์เหล่านี้
echo "ตั้งค่าให้ macOS ไม่สร้างไฟล์ AppleDouble..."
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

echo "✅ เสร็จแล้ว"
