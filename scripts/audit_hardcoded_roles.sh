#!/bin/bash
# Audit script: ตรวจหา hardcoded role strings ที่เหลืออยู่
# Phase 1: Role Management Refactor

echo "🔍 ตรวจหา hardcoded role strings ใน Flutter code..."

# ค้นหา 'admin', 'provider', 'consumer' ใน lib/ directory
# ยกเว้น user_roles.dart และ generated files
HARDCODED=$(grep -r "'admin'\|'provider'\|'consumer'" lib/ \
  --exclude-dir=generated \
  --exclude="*user_roles.dart" \
  --include="*.dart" \
  -n | grep -v "UserRole" | grep -v "// " | wc -l | tr -d ' ')

if [ "$HARDCODED" -eq 0 ]; then
  echo "✅ ไม่พบ hardcoded role strings ที่ไม่ถูกต้อง"
  exit 0
else
  echo "⚠️ พบ $HARDCODED จุดที่ยังมี hardcoded role strings"
  grep -r "'admin'\|'provider'\|'consumer'" lib/ \
    --exclude-dir=generated \
    --exclude="*user_roles.dart" \
    --include="*.dart" \
    -n | grep -v "UserRole" | grep -v "// "
  exit 1
fi
