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
    apt-get install -y curl wget sed python3-minimal tmate sudo
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed."
else
    echo "--- [1] System Setup: Dependencies already installed. Skipping. ---"
fi

# ==========================================
#   HELPER: check_update <target> <url>
#   Unified updater for autorun.sh from GitHub.
# ==========================================
check_update() {
    local TARGET="$1"
    local URL="$2"
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
}

# ==========================================
#   GENERATOR: xray.sh
# ==========================================
generate_xray() {
    cat << 'XRAY_EOF' > /tmp/_xray_tmp.sh
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

echo "Updating config.json..."
cat > "$CONFIG_PATH" << JSON
{
  "log": { "loglevel": "error" },
  "policy": {
    "levels": {
      "0": {
        "handshake": 2,
        "connIdle": 120,
        "uplinkOnly": 0,
        "downlinkOnly": 0,
        "bufferSize": 512
      }
    },
    "system": {
      "statsInboundUplink": false,
      "statsInboundDownlink": false
    }
  },
  "inbounds": [{
    "port": ${SERVER_PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${UUID}", "level": 0 }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "tcpSettings": { "header": { "type": "http" } },
      "sockopt": {
        "tcpFastOpen": true,
        "tcpNoDelay": true
      }
    },
    "sniffing": { "enabled": false }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": { "domainStrategy": "UseIPv4" },
    "streamSettings": {
      "sockopt": {
        "tcpFastOpen": true,
        "tcpNoDelay": true
      }
    }
  }]
}
JSON

VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=http&host=playstation.net#Nour"

echo "=========================================================="
echo "Xray VLESS Link:"
echo "$VLESS_LINK"
echo "=========================================================="

echo "Starting Xray..."
exec xray run -c "$CONFIG_PATH"
XRAY_EOF
    mv /tmp/_xray_tmp.sh "$XRAY_SCRIPT"
    chmod +x "$XRAY_SCRIPT"
    echo "  [xray.sh] ✅ Written."
}

# ==========================================
#   GENERATOR: singbox.sh
# ==========================================
generate_singbox() {
    cat << 'SINGBOX_EOF' > /tmp/_singbox_tmp.sh
#!/bin/bash

echo "--- [sing-box VLESS Startup Script] ---"

CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"

mkdir -p "$CONFIG_DIR"

# --- sing-box Installation / Version Check ---
if ! command -v sing-box >/dev/null 2>&1; then
    echo "sing-box not found. Installing..."
    mkdir -p /etc/apt/keyrings &&
    curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc &&
    chmod a+r /etc/apt/keyrings/sagernet.asc &&
    echo 'Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc' > /etc/apt/sources.list.d/sagernet.sources &&
    apt-get update &&
    apt-get install -y sing-box
    echo "✅ sing-box installed: $(sing-box version | head -1)"
else
    INSTALLED_VER=$(sing-box version | grep -oP 'sing-box version \K[^\s]+')
    LATEST_VER=$(apt-cache policy sing-box 2>/dev/null | grep Candidate | awk '{print $2}')
    echo "✔  sing-box already installed: v${INSTALLED_VER}"
    if [ -n "$LATEST_VER" ] && [ "$LATEST_VER" != "$INSTALLED_VER" ]; then
        echo "⬆️  New version available: v${LATEST_VER}. Upgrading..."
        apt-get install -y sing-box
        echo "✅ sing-box upgraded to: $(sing-box version | head -1)"
    else
        echo "✔  sing-box is up to date."
    fi
fi

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

echo "Updating config.json..."
cat > "$CONFIG_PATH" << JSON
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
      "tcp_fast_open": true,
      "sniff": false,
      "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "http",
        "host": ["playstation.net"],
        "path": "/",
        "idle_timeout": "60s",
        "ping_timeout": "15s"
      }
    }
  ],
  "route": {
    "default_domain_strategy": "prefer_ipv4"
  },
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "tcp_fast_open": true
    }
  ]
}
JSON

VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=http&host=playstation.net&path=%2F#Nour"

echo "=========================================================="
echo "sing-box VLESS Link:"
echo "$VLESS_LINK"
echo "=========================================================="

echo "Starting sing-box..."
exec sing-box run -c "$CONFIG_PATH"
SINGBOX_EOF
    mv /tmp/_singbox_tmp.sh "$SINGBOX_SCRIPT"
    chmod +x "$SINGBOX_SCRIPT"
    echo "  [singbox.sh] ✅ Written."
}

# ==========================================
#   [2] CHECK FOR UPDATES
# ==========================================
echo "--- [2] Checking for Updates ---"
check_update "$0" \
    "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

# ==========================================
#   [3] SYNC PROXY SCRIPTS (always compare)
# ==========================================
echo "--- [3] Syncing proxy scripts ---"
generate_xray
generate_singbox

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
echo "  to start the sing-box server:"
echo "bash ../../singbox.sh"
echo ""
echo "  to start the hytale server:"
echo "    curl -sL https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh | bash -s -- ID1 ID2 --p 5520"
echo "=========================================================="
