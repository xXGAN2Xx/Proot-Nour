#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT (Gaming)
# ==========================================

PARENT_DIR=$(cd .. && pwd)
TARGET_SCRIPT="${PARENT_DIR}/xray.sh"

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
#        SELF-UPDATE LOGIC
# ==========================================
echo "--- [2] Checking for Script Updates ---"

SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o /tmp/script_update_check

    if [ -s /tmp/script_update_check ]; then
        if ! cmp -s "$0" /tmp/script_update_check; then
            echo "New version found! Updating Master Script..."
            mv /tmp/script_update_check "$0"
            chmod +x "$0"
            echo "Restarting script..."
            exec "$0" "$@"
            exit 0
        else
            echo "Master Script is up to date."
            rm -f /tmp/script_update_check
        fi
    fi
fi

# ==========================================
#        XRAY SCRIPT GENERATION
# ==========================================
echo "--- [3] Checking for xray.sh in $PARENT_DIR ---"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "Creating $TARGET_SCRIPT (in the parent directory)..."

    cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash

echo "--- [Xray VLESS Gaming Server Startup] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"
TEMP_CONFIG="/tmp/xray_config_temp.json"

mkdir -p "$CONFIG_DIR"

# --- Xray Core Installation ---
echo "Checking/Installing Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

# --- Validate Required Variables ---
if [ -z "$SERVER_PORT" ]; then
    echo "ERROR: SERVER_PORT is not set!"
    exit 1
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

# --- Gaming-Optimized Config ---
# Key decisions:
#  • Single inbound handles both TCP + UDP on SERVER_PORT
#  • Raw TCP/UDP (no HTTP header) → lower latency for game packets
#  • sniffing enabled → Xray can detect & route game protocols
#  • freedom outbound with domainStrategy=UseIPv4 → avoids IPv6 DNS delay
#  • bufferSize 4 MB on TCP socket → handles burst game data better
#  • sockopt: tcpFastOpen, tcpNoDelay → kernel-level latency reduction

cat > "$TEMP_CONFIG" << JSON
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-gaming",
      "port": ${SERVER_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "level": 0,
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "tcpSettings": {
          "acceptProxyProtocol": false,
          "header": { "type": "none" }
        },
        "sockopt": {
          "tcpFastOpen": true,
          "tcpNoDelay": true,
          "mark": 255,
          "tcpKeepAliveInterval": 30
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": false
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4",
        "userLevel": 0
      },
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true,
          "tcpNoDelay": true,
          "mark": 255
        }
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "network": "tcp,udp"
      }
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 5,
        "downlinkOnly": 30,
        "bufferSize": 4096
      }
    },
    "system": {
      "statsInboundUplink": false,
      "statsInboundDownlink": false
    }
  }
}
JSON

    # Substitute real values
    sed -i "s/\${SERVER_PORT}/$SERVER_PORT/g" "$TEMP_CONFIG"
    sed -i "s/\${UUID}/$UUID/g"               "$TEMP_CONFIG"

    # Only overwrite config if changed
    if [ ! -f "$CONFIG_PATH" ] || ! cmp -s "$TEMP_CONFIG" "$CONFIG_PATH"; then
        echo "Writing new config.json..."
        mv "$TEMP_CONFIG" "$CONFIG_PATH"
    else
        echo "Config unchanged. Skipping write."
        rm -f "$TEMP_CONFIG"
    fi

# --- Link Generation ---
VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=none#Nour-Gaming"

echo "=========================================================="
echo " Xray VLESS Gaming Link (TCP + UDP on same port)"
echo "=========================================================="
echo " $VLESS_LINK"
echo "=========================================================="
echo " Port : $SERVER_PORT  (TCP & UDP)"
echo " UUID : $UUID"
echo "=========================================================="

echo "Starting Xray..."
xray run -c "$CONFIG_PATH"
EOF

    chmod +x "$TARGET_SCRIPT"
    echo "Successfully created $TARGET_SCRIPT"
else
    echo "xray.sh already exists in $PARENT_DIR. Skipping creation."
fi

echo ""
echo "--- Setup Complete ---"
echo "To start the Xray gaming server:"
echo "  bash ../../xray.sh"
echo ""
echo "To start the Hytale server:"
echo "  curl -sL https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh | bash -s -- ID1 ID2 --p 5520"
