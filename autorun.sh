#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

PARENT_DIR=$(cd .. && pwd)
XRAY_SCRIPT="${PARENT_DIR}/xray.sh"
SINGBOX_SCRIPT="${PARENT_DIR}/singbox.sh"

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate
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
TEMP_CONFIG="/tmp/xray_config_temp.json"

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

# Get the server IP if not already set
if [ -z "$server_ip" ]; then
    server_ip=$(curl -fsSL https://api.ipify.org 2>/dev/null || \
                curl -fsSL https://ifconfig.me 2>/dev/null || \
                hostname -I | awk '{print $1}')
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

cat > "$TEMP_CONFIG" << JSON
{
  "inbounds": [{
    "port": ${SERVER_PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${UUID}" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "tcpSettings": { "header": { "type": "http" } }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
JSON

sed -i "s/\${SERVER_PORT}/$SERVER_PORT/g" "$TEMP_CONFIG"

if [ ! -f "$CONFIG_PATH" ] || ! cmp -s "$TEMP_CONFIG" "$CONFIG_PATH"; then
    echo "Updating config.json..."
    mv "$TEMP_CONFIG" "$CONFIG_PATH"
else
    echo "Config unchanged. Skipping write."
    rm -f "$TEMP_CONFIG"
fi

VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=http&host=playstation.net#Nour"

echo "=========================================================="
echo "Xray VLESS Link:"
echo "$VLESS_LINK"
echo "=========================================================="

echo "Starting Xray..."
exec xray run -c "$CONFIG_PATH"
XRAY_EOF
}

# ==========================================
#   GENERATOR: singbox.sh
# ==========================================
generate_singbox() {
    local TARGET="$1"
    cat << 'SINGBOX_EOF' > "$TARGET"
#!/bin/bash

echo "--- [sing-box VLESS Startup Script] ---"

CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
TEMP_CONFIG="/tmp/singbox_config_temp.json"

mkdir -p "$CONFIG_DIR"

# --- sing-box Installation ---
echo "Checking/Installing sing-box..."
curl -fsSL https://sing-box.app/install.sh | sh
echo "sing-box installed: $(sing-box version | head -1)"

# --- Smart Config Generation ---
if [ -z "$SERVER_PORT" ]; then
    echo ""
    echo "⚠️  SERVER_PORT environment variable is not set!"
    echo "Please enter the port you want sing-box to listen on:"
    read -rp "SERVER_PORT: " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! echo "$SERVER_PORT" | grep -qE '^[0-9]+$' || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "❌ Invalid port. Please enter a number between 1 and 65535:"
        read -rp "SERVER_PORT: " SERVER_PORT
    done
    echo "✅ Using port: $SERVER_PORT"
fi

# Get the server IP if not already set
if [ -z "$server_ip" ]; then
    server_ip=$(curl -fsSL https://api.ipify.org 2>/dev/null || \
                curl -fsSL https://ifconfig.me 2>/dev/null || \
                hostname -I | awk '{print $1}')
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

cat > "$TEMP_CONFIG" << JSON
{
  "log": {
    "level": "error",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${SERVER_PORT},
      "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "http",
        "host": ["playstation.net"],
        "path": "/"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON

sed -i "s/\${SERVER_PORT}/$SERVER_PORT/g" "$TEMP_CONFIG"

if [ ! -f "$CONFIG_PATH" ] || ! cmp -s "$TEMP_CONFIG" "$CONFIG_PATH"; then
    echo "Updating config.json..."
    mv "$TEMP_CONFIG" "$CONFIG_PATH"
else
    echo "Config unchanged. Skipping write."
    rm -f "$TEMP_CONFIG"
fi

VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=http&host=playstation.net&path=%2F#Nour"

echo "=========================================================="
echo "sing-box VLESS Link:"
echo "$VLESS_LINK"
echo "=========================================================="

echo "Starting sing-box..."
exec sing-box run -c "$CONFIG_PATH"
SINGBOX_EOF
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

if [ ! -f "$XRAY_SCRIPT" ]; then
    echo "  [xray.sh] Generating..."
    generate_xray "$XRAY_SCRIPT"
    chmod +x "$XRAY_SCRIPT"
    echo "  [xray.sh] ✅ Created."
else
    echo "  [xray.sh] ✔  Already exists."
fi

if [ ! -f "$SINGBOX_SCRIPT" ]; then
    echo "  [singbox.sh] Generating..."
    generate_singbox "$SINGBOX_SCRIPT"
    chmod +x "$SINGBOX_SCRIPT"
    echo "  [singbox.sh] ✅ Created."
else
    echo "  [singbox.sh] ✔  Already exists."
fi

# ==========================================
#        DONE
# ==========================================
echo ""
echo "=========================================================="
echo "--- Setup Complete --- Both scripts are ready!"
echo "=========================================================="
echo ""
echo "  to start the Xray server:"
echo "    bash ../../xray.sh"
echo ""
echo "  to start the sing-box server:"
echo "    bash ../../singbox.sh"
echo ""
echo "  to start the hytale server:"
echo "    curl -sL https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh | bash -s -- ID1 ID2 --p 5520"
echo "=========================================================="
