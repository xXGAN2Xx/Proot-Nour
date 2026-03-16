#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT (Gaming)
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

echo "--- [Xray VLESS+TCP+HTTP Gaming Server] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"

mkdir -p "$CONFIG_DIR"

# --- Xray Core Installation ---
echo "Checking/Installing Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

# --- Port Detection ---
if [ -z "$SERVER_PORT" ]; then
    echo ""
    echo "WARNING: SERVER_PORT environment variable is not set!"
    echo "Please enter the port you want Xray to listen on:"
    read -rp "SERVER_PORT: " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! echo "$SERVER_PORT" | grep -qE '^[0-9]+$' || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "Invalid port. Please enter a number between 1 and 65535:"
        read -rp "SERVER_PORT: " SERVER_PORT
    done
    echo "Using port: $SERVER_PORT"
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

# --- IP Detection ---
if [ -z "$SERVER_IP" ]; then
    echo "Auto-detecting public IP..."
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org \
             || curl -s --max-time 5 https://ifconfig.me \
             || curl -s --max-time 5 https://icanhazip.com)
    if [ -n "$SERVER_IP" ]; then
        echo "Detected IP: $SERVER_IP"
    else
        echo "Could not auto-detect IP. Please enter it manually:"
        read -rp "SERVER_IP: " SERVER_IP
    fi
fi

cat > "$CONFIG_PATH" << JSON
{
  "log": {
    "loglevel": "none"
  },

  "dns": {
    "servers": [
      "1.1.1.1"
    ],
    "queryStrategy": "UseIPv4",
    "disableFallback": true,
    "disableFallbackIfMatch": true
  },

  "policy": {
    "levels": {
      "0": {
        "handshakeTimeout": 2,
        "connIdle": 60,
        "uplinkOnly": 1,
        "downlinkOnly": 1,
        "statsUserUplink": false,
        "statsUserDownlink": false,
        "bufferSize": 0
      }
    },
    "system": {
      "statsInboundUplink": false,
      "statsInboundDownlink": false
    }
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
          "acceptProxyProtocol": false,
          "header": {
            "type": "http",
            "request": {
              "version": "1.1",
              "method": "GET",
              "path": ["/", "/download", "/stream"],
              "headers": {
                "User-Agent": [
                  "Mozilla/5.0 (PlayStation; PlayStation 5/3.00) AppleWebKit/605.1.15"
                ],
                "Accept-Encoding": ["identity"],
                "Connection": ["keep-alive"],
                "Pragma": ["no-cache"],
                "Cache-Control": ["no-cache"]
              }
            },
            "response": {
              "version": "1.1",
              "status": "200",
              "reason": "OK",
              "headers": {
                "Content-Type": ["application/octet-stream"],
                "Transfer-Encoding": ["chunked"],
                "Connection": ["keep-alive"],
                "Cache-Control": ["no-store"]
              }
            }
          }
        },
        "sockopt": {
          "mark": 255,
          "tcpFastOpen": true,
          "tcpNoDelay": true,
          "tcpKeepAliveInterval": 30,
          "tcpKeepAliveIdle": 60,
          "domainStrategy": "UseIPv4",
          "tcpMaxSeg": 1440
        }
      },
      "sniffing": {
        "enabled": false
      }
    }
  ],

  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4",
        "noises": []
      },
      "streamSettings": {
        "sockopt": {
          "mark": 255,
          "tcpFastOpen": true,
          "tcpNoDelay": true,
          "tcpKeepAliveInterval": 30,
          "tcpKeepAliveIdle": 60,
          "tcpMaxSeg": 1440
        }
      },
      "mux": {
        "enabled": false
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {
        "response": { "type": "none" }
      }
    }
  ],

  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  }
}
JSON

echo "=========================================================="
echo "Xray VLESS+TCP+HTTP (Gaming) Link:"
echo "vless://${UUID}@${SERVER_IP}:${SERVER_PORT}?encryption=none&type=http&host=playstation.net#Nour-Gaming"
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
echo "  ╔══════════════════════════════════════════╗"
echo "  ║      GAMING SETUP COMPLETE               ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║                                          ║"
echo "  ║  Xray Config      ->  Ready              ║"
echo "  ║  Mode             ->  Gaming Optimized   ║"
echo "  ║  Transport        ->  VLESS+TCP+HTTP     ║"
echo "  ║  Nagle            ->  Disabled           ║"
echo "  ║  TCP Fast Open    ->  Enabled            ║"
echo "  ║  Buffer Size      ->  0 (immediate)      ║"
echo "  ║  TCP KeepAlive    ->  30s interval       ║"
echo "  ║  TCP MSS          ->  1440 bytes         ║"
echo "  ║  Mux              ->  Disabled           ║"
echo "  ║  DNS              ->  1.1.1.1            ║"
echo "  ║  Bogon Blocking   ->  Enabled            ║"
echo "  ║                                          ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║  To start Xray:                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""
echo "bash ../xray.sh"
echo ""
