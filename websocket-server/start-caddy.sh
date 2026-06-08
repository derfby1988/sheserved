#!/bin/bash
# =============================================================
# start-caddy.sh — Phase 1: เริ่มต้น Caddy Reverse Proxy
# =============================================================
# วิธีใช้:
#   ./start-caddy.sh          → Port 8080 (ไม่ต้อง sudo, ทดสอบเร็ว)
#   sudo ./start-caddy.sh 80  → Port 80  (ต้อง sudo, ใช้กับมือถือจริง)
#
# Phase 1 — reverse_proxy_plan.md §Phase 1
# =============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOSTNAME=$(scutil --get LocalHostName 2>/dev/null || hostname)
PORT="${1:-8080}"

echo ""
echo "  ════════════════════════════════════════════════════"
echo "  🌐 Sheserved — Caddy Reverse Proxy (Phase 1)"
echo "  ════════════════════════════════════════════════════"
echo "  Hostname : ${HOSTNAME}.local"
echo "  Port     : $PORT"
echo "  ────────────────────────────────────────────────────"

# ตรวจสอบว่า Node.js server รันอยู่หรือไม่
if ! curl -s http://localhost:3000/health > /dev/null 2>&1; then
  echo "  ⚠️  Node.js server ไม่ได้รันอยู่ที่ port 3000!"
  echo "  ⚡  กรุณารัน: cd websocket-server && npm run dev"
  echo ""
fi

# ตรวจสอบว่า Caddy รันอยู่แล้วหรือไม่
if pgrep -f "caddy run" > /dev/null 2>&1; then
  echo "  ⚠️  Caddy กำลังรันอยู่แล้ว — หยุดก่อน..."
  pkill -f "caddy run" 2>/dev/null || true
  sleep 1
fi

if [ "$PORT" = "80" ]; then
  # Port 80: ใช้ Caddyfile.local (hostname binding, ต้อง sudo)
  CADDYFILE="$SCRIPT_DIR/Caddyfile.local"
  if [ "$(id -u)" != "0" ]; then
    echo "  ❌ Port 80 ต้องใช้ sudo: sudo ./start-caddy.sh 80"
    exit 1
  fi
  echo "  🔒 Starting on port 80 (root mode)..."
  echo "  Config   : $CADDYFILE"
  echo ""
  caddy run --config "$CADDYFILE"
else
  # Port 8080: ใช้ Caddyfile.dev (:8080 bind-all, ไม่ต้อง sudo)
  CADDYFILE="$SCRIPT_DIR/Caddyfile.dev"
  echo "  ✅ Starting on port ${PORT} (no sudo required)"
  echo "  Config   : $CADDYFILE"
  echo ""
  echo "  🧪 ทดสอบได้ที่:"
  echo "    curl http://localhost:${PORT}/health"
  echo "    curl http://${HOSTNAME}.local:${PORT}/health"
  echo ""
  echo "  📱 สำหรับมือถือ (Wi-Fi เดียวกัน):"
  echo "    http://${HOSTNAME}.local:${PORT}/api/..."
  echo "  ════════════════════════════════════════════════════"
  echo ""

  caddy run --config "$CADDYFILE"
fi
