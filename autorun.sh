#!/bin/bash
PARENT_DIR=$(cd .. && pwd)
TARGET_SCRIPT="${PARENT_DIR}/xray.sh"
DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate sudo util-linux openssl
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed."
else
    echo "--- [1] System Setup: Dependencies already installed. Skipping. ---"
fi

echo "--- [2] Checking for Script Updates ---"
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o /tmp/script_update_check
    if [ -s /tmp/script_update_check ]; then
        if ! cmp -s "$SELF" /tmp/script_update_check; then
            echo "New version found! Updating Master Script..."
            mv /tmp/script_update_check "$SELF"
            chmod +x "$SELF"
            echo "Restarting script..."
            exec bash "$SELF" "$@"
            exit 0
        else
            echo "Master Script is up to date."
            rm -f /tmp/script_update_check
        fi
    fi
fi

echo "--- [3] Writing xray.sh to $PARENT_DIR ---"
cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash
echo "--- [Xray Gaming Server] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"
CERT_DIR="${CONFIG_DIR}/certs"
mkdir -p "$CONFIG_DIR" "$CERT_DIR"

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

if [ -z "$SERVER_PORT" ]; then
    read -p "Enter server port: " SERVER_PORT
    if [ -z "$SERVER_PORT" ]; then
        echo "ERROR: No port provided."
        exit 1
    fi
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

# Detect public IP
server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
    || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
    || hostname -I | awk '{print $1}')

# ── Gaming kernel tuning ────────────────────────────────────────────────────
sysctl -w net.ipv4.tcp_fastopen=3              2>/dev/null  # TFO for client+server
sysctl -w net.ipv4.tcp_low_latency=1           2>/dev/null  # Prefer latency over throughput
sysctl -w net.core.rmem_max=16777216           2>/dev/null
sysctl -w net.core.wmem_max=16777216           2>/dev/null
sysctl -w net.ipv4.tcp_congestion_control=bbr  2>/dev/null  # BBR: low-latency CC
sysctl -w net.ipv4.tcp_mtu_probing=1           2>/dev/null  # Avoids PMTUD blackholes
sysctl -w net.ipv4.tcp_notsent_lowat=16384     2>/dev/null  # Reduces send-buffer bloat
sysctl -w net.ipv4.tcp_timestamps=0            2>/dev/null  # Shaves 12 bytes per packet
sysctl -w net.ipv4.tcp_sack=1                  2>/dev/null  # Fast recovery on packet loss
sysctl -w net.ipv4.tcp_no_metrics_save=1       2>/dev/null  # No cached metrics between sessions

# ── ECDSA P-256 certificate (gaming-optimized) ──────────────────────────────
# Why ECDSA over RSA:
#   RSA-2048 signature = 256 bytes  →  ECDSA-P256 = 64 bytes
#   Smaller handshake payload = less round-trip data = lower latency spike on connect
if [ ! -f "$CERT_DIR/server.crt" ]; then
    openssl req -x509 \
        -newkey ec \
        -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$CERT_DIR/server.key" \
        -out    "$CERT_DIR/server.crt" \
        -days 3650 -nodes \
        -subj "/CN=playstation.net" \
        -addext "subjectAltName=DNS:playstation.net" 2>/dev/null
    echo "ECDSA P-256 certificate generated."
fi

# ── Xray config ─────────────────────────────────────────────────────────────
cat > "$CONFIG_PATH" << JSON
{
  "log": { "loglevel": "none" },
  "inbounds": [
    {
      "port": $SERVER_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "playstation.net",
          "minVersion": "1.3",
          "alpn": ["h2"],
          "certificates": [
            {
              "certificateFile": "$CERT_DIR/server.crt",
              "keyFile": "$CERT_DIR/server.key"
            }
          ]
        },
        "sockopt": {
          "tcpFastOpen": true,
          "tcpNoDelay": true,
          "tcpKeepAliveIdle": 30,
          "tcpKeepAliveInterval": 10,
          "tcpUserTimeout": 8000,
          "mark": 255
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true,
          "tcpNoDelay": true,
          "mark": 255
        }
      }
    }
  ]
}
JSON

# allowInsecure=1 on client side (self-signed cert); fp=chrome mimics browser TLS fingerprint
VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=tls&sni=playstation.net&fp=chrome&alpn=h2&type=tcp&allowInsecure=1#Nour-Gaming"

echo "=========================================================="
echo " $VLESS_LINK"
echo " IP   : $server_ip"
echo " Port : $SERVER_PORT"
echo " UUID : $UUID"
echo "=========================================================="

xray run -c "$CONFIG_PATH"
EOF

chmod +x "$TARGET_SCRIPT"
echo "xray.sh written to $TARGET_SCRIPT"
echo ""
echo "--- Setup Complete ---"
echo "To start the Xray gaming server:"
echo "bash ../xray.sh"
echo ""
echo "To start the Hytale server:"
echo "curl -sL https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh | bash -s -- ID1 ID2 --p 5520"
