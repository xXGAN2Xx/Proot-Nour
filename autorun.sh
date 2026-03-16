#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

PARENT_DIR=$(cd .. && pwd)
XRAY_SCRIPT="${PARENT_DIR}/xray.sh"

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate sudo
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed."
else
    echo "--- [1] System Setup: Dependencies already installed. Skipping. ---"
fi

# ==========================================
#   HELPER: check_update <target> <url> [generator_func]
#   Unified updater for ALL scripts including this one.
#   Updates in-place and continues (no restart).
# ==========================================
check_update() {
    local TARGET="$1"
    local URL="$2"
    local GENERATOR="${3:-}"
    local NAME
    NAME=$(basename "$TARGET")

    echo "  [$NAME] Checking..."
    curl -fsSL "$URL" -o /tmp/_update_check 2>/dev/null

    if [ -s /tmp/_update_check ]; then
        if [ ! -f "$TARGET" ] || ! cmp -s "$TARGET" /tmp/_update_check; then
            mv /tmp/_update_check "$TARGET"
            chmod +x "$TARGET"
            echo "  [$NAME] ✅ Updated to latest version."
        else
            rm -f /tmp/_update_check
            echo "  [$NAME] ✔  Already up to date."
        fi
    else
        rm -f /tmp/_update_check
        echo "  [$NAME] ⚠️  Could not reach remote. Skipping update."
    fi

    # If still missing and a generator was provided, create it locally
    if [ ! -f "$TARGET" ] && [ -n "$GENERATOR" ]; then
        echo "  [$NAME] Generating locally..."
        $GENERATOR "$TARGET"
        chmod +x "$TARGET"
        echo "  [$NAME] Created from built-in template."
    fi
}

# ==========================================
#   GENERATOR: xray.sh
# ==========================================
generate_xray() {
    local TARGET="$1"
    cat << 'XRAY_EOF' > "$TARGET"
#!/bin/bash

echo "--- [Xray VLESS Startup Script] ---"

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

cat > "$CONFIG_PATH" << JSON
{
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
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/ssl/certs/your_cert.crt",
              "keyFile": "/etc/ssl/private/your_key.key"
            }
          ]
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

VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=http&host=playstation.net#Nour"

echo "=========================================================="
echo "Xray VLESS Link:"
echo "vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=tls&sni=playstation.net&allowInsecure=true#Nour"
echo "=========================================================="

echo "Starting Xray..."
xray run -c "$CONFIG_PATH"
XRAY_EOF
}

# ==========================================
#   [2] CHECK FOR UPDATES
# ==========================================
echo "--- [2] Checking for Updates ---"

# autorun.sh — fetched from GitHub
check_update "$0" \
    "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

# xray.sh and singbox.sh — generated locally (no remote file)
echo "--- [3] Generating proxy scripts ---"
    generate_xray "$XRAY_SCRIPT"
    chmod +x "$XRAY_SCRIPT"

# ==========================================
#        DONE
# ==========================================
echo ""
echo "=========================================================="
echo "--- Setup Complete --- Both scripts are ready!"
echo "=========================================================="
echo ""
echo "  to start the Xray server:"
echo "bash ../../xray.sh"
echo ""
echo "=========================================================="
