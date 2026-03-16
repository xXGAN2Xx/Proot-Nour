#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
XRAY_SCRIPT="${PARENT_DIR}/xray.sh"

DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate sudo ca-certificates openssl
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed."
else
    echo "--- [1] System Setup: Dependencies already installed. Skipping. ---"
fi

# ==========================================
#   GENERATOR: xray.sh
# ==========================================

generate_xray() {
    local TARGET="$1"
    cat << 'XRAY_EOF' > "$TARGET"
#!/bin/bash

echo "--- [Xray VLESS+TCP+HTTP Startup Script] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"

mkdir -p "$CONFIG_DIR"

# --- Xray Core Installation ---
echo "Checking/Installing Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

# --- Smart Config Generation ---
if [ -z "$SERVER_PORT" ]; then
    echo ""
    echo "⚠️  SERVER_PORT environment variable is not set!"
    echo "Please enter the port you want Xray to listen on:"
    read -rp "SERVER_PORT: " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! echo "$SERVER_PORT" | grep -qE '^[0-9]+$' || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "❌ Invalid port. Please enter a number between 1 and 65535:"
        read -rp "SERVER_PORT: " SERVER_PORT
    done
    echo "✅ Using port: $SERVER_PORT"
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

if [ -z "$SERVER_IP" ]; then
    echo "🔍 Auto-detecting public IP..."
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org \
             || curl -s --max-time 5 https://ifconfig.me \
             || curl -s --max-time 5 https://icanhazip.com)
    if [ -n "$SERVER_IP" ]; then
        echo "✅ Detected IP: $SERVER_IP"
    else
        echo "⚠️  Could not auto-detect IP. Please enter it manually:"
        read -rp "SERVER_IP: " SERVER_IP
    fi
fi

cat > "$CONFIG_PATH" << JSON
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
      "port": ${SERVER_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {
          "header": {
            "type": "http"
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
JSON

echo "=========================================================="
echo "Xray VLESS+TCP+HTTP Link:"
echo "vless://${UUID}@${SERVER_IP}:${SERVER_PORT}?encryption=none&type=http&host=playstation.net#Nour"
echo "=========================================================="

echo "Starting Xray..."
xray run -c "$CONFIG_PATH"
XRAY_EOF
}

# ==========================================
#   [2] Generating proxy scripts
# ==========================================

echo "--- [2] Generating proxy scripts ---"

generate_xray "$XRAY_SCRIPT"
chmod +x "$XRAY_SCRIPT"

# ==========================================
#        DONE
# ==========================================

echo ""
echo "\e[1;36m"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║         ✅  SETUP COMPLETE               ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║                                          ║"
echo "  ║  ⚙️  Xray Config      →  Ready            ║"
echo "  ║                                          ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║  ▶  To start Xray:                       ║"
echo "  ╚══════════════════════════════════════════╝"
echo "\e[0m"
echo "bash ../xray.sh"
echo ""
