#!/bin/bash

# Setup Java 17 สำหรับ Android Build
# Tree Law Zoo - Java 17 Setup

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "☕ Setup Java 17 สำหรับ Android Build"
echo "======================================"
echo ""

# ตรวจสอบ Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${RED}❌ Homebrew ยังไม่ได้ติดตั้ง${NC}"
    exit 1
fi

# ตรวจสอบว่า Java 17 ติดตั้งแล้วหรือยัง
if [ -d "/opt/homebrew/opt/openjdk@17" ]; then
    echo -e "${GREEN}✅ Java 17 ติดตั้งแล้ว${NC}"
else
    echo "📦 ติดตั้ง Java 17..."
    brew install openjdk@17
fi

# หา Java home path ที่ถูกต้อง
echo ""
echo "🔍 หา Java Home Path..."

# วิธีที่ 1: ใช้ brew --prefix
BREW_PREFIX=$(brew --prefix openjdk@17)
JAVA_HOME_PATH=""

# ลองหา path ต่างๆ
if [ -d "$BREW_PREFIX/libexec/openjdk.jdk/Contents/Home" ]; then
    JAVA_HOME_PATH="$BREW_PREFIX/libexec/openjdk.jdk/Contents/Home"
elif [ -d "$BREW_PREFIX/Contents/Home" ]; then
    JAVA_HOME_PATH="$BREW_PREFIX/Contents/Home"
elif [ -d "$BREW_PREFIX" ]; then
    # ลองหาใน subdirectories
    JAVA_HOME_PATH=$(find "$BREW_PREFIX" -name "java" -type f 2>/dev/null | head -1 | xargs dirname | xargs dirname | xargs dirname 2>/dev/null || echo "")
fi

if [ -z "$JAVA_HOME_PATH" ] || [ ! -d "$JAVA_HOME_PATH" ]; then
    echo -e "${YELLOW}⚠️  ไม่สามารถหา Java Home Path ได้${NC}"
    echo "ลองใช้ path มาตรฐาน:"
    echo "  $BREW_PREFIX"
    
    # ใช้ path มาตรฐาน
    JAVA_HOME_PATH="$BREW_PREFIX"
fi

# ตรวจสอบว่า path ถูกต้อง
if [ -f "$JAVA_HOME_PATH/bin/java" ]; then
    echo -e "${GREEN}✅ พบ Java Home: $JAVA_HOME_PATH${NC}"
    "$JAVA_HOME_PATH/bin/java" -version 2>&1 | head -1
else
    echo -e "${YELLOW}⚠️  ไม่พบ java binary ที่ $JAVA_HOME_PATH${NC}"
    echo "ลองหา path อื่น..."
    
    # ลองหา java binary
    JAVA_BIN=$(find "$BREW_PREFIX" -name "java" -type f 2>/dev/null | head -1)
    if [ ! -z "$JAVA_BIN" ]; then
        JAVA_HOME_PATH=$(dirname "$JAVA_BIN" | xargs dirname)
        echo -e "${GREEN}✅ พบ Java Home: $JAVA_HOME_PATH${NC}"
    else
        echo -e "${RED}❌ ไม่สามารถหา Java Home ได้${NC}"
        exit 1
    fi
fi

echo ""

# แก้ไข gradle.properties
GRADLE_PROPERTIES="android/gradle.properties"
if [ ! -f "$GRADLE_PROPERTIES" ]; then
    echo -e "${RED}❌ ไม่พบไฟล์ $GRADLE_PROPERTIES${NC}"
    exit 1
fi

# Backup
cp "$GRADLE_PROPERTIES" "$GRADLE_PROPERTIES.backup"

# แก้ไข Java home path
if grep -q "^org.gradle.java.home=" "$GRADLE_PROPERTIES"; then
    # แทนที่ path เดิม
    sed -i '' "s|^org.gradle.java.home=.*|org.gradle.java.home=$JAVA_HOME_PATH|" "$GRADLE_PROPERTIES"
    echo -e "${GREEN}✅ แก้ไข Java Home Path ใน gradle.properties${NC}"
else
    # เพิ่ม path ใหม่
    echo "org.gradle.java.home=$JAVA_HOME_PATH" >> "$GRADLE_PROPERTIES"
    echo -e "${GREEN}✅ เพิ่ม Java Home Path ใน gradle.properties${NC}"
fi

echo ""
echo "📋 Java Home Path ที่ตั้งค่า:"
echo "   $JAVA_HOME_PATH"
echo ""
echo "📝 ไฟล์ที่แก้ไข:"
echo "   $GRADLE_PROPERTIES"
echo ""
echo -e "${GREEN}✅ Setup Java 17 เสร็จแล้ว!${NC}"
echo ""
echo "🧪 ทดสอบ:"
echo "   cd android"
echo "   ./gradlew --version"
echo ""
