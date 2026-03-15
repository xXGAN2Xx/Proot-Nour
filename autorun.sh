#!/bin/bash
echo "--- [sing-box VLESS TLS Startup Script - Gaming Optimized] ---"

CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
CERT_DIR="/usr/local/etc/sing-box/tls"
TEMP_CONFIG="/tmp/singbox_config_temp.json"
mkdir -p "$CONFIG_DIR" "$CERT_DIR"

# --- 1. Collect PORT ---
if [ -z "$SERVER_PORT" ]; then
    echo ""
    echo "Please enter the port you want sing-box to listen on:"
    read -rp "SERVER_PORT: " SERVER_PORT
fi
while [ -z "$SERVER_PORT" ] || ! echo "$SERVER_PORT" | grep -qE '^[0-9]+$' || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; do
    echo "❌ Invalid port. Please enter a number between 1 and 65535:"
    read -rp "SERVER_PORT: " SERVER_PORT
done
echo "✅ Using port: $SERVER_PORT"

# --- 2. Install sing-box ---
echo "Checking/Installing sing-box..."
curl -fsSL https://sing-box.app/install.sh | sh
if ! command -v sing-box &>/dev/null; then
    echo "❌ sing-box installation failed. Exiting."
    exit 1
fi
echo "sing-box installed: $(sing-box version | head -1)"

# --- 3. Install openssl if missing ---
if ! command -v openssl &>/dev/null; then
    echo "Installing openssl..."
    apt-get install -y openssl 2>/dev/null || apk add openssl 2>/dev/null
fi

# --- 4. Generate lightweight ECDSA P-256 self-signed certificate ---
FAKE_SNI="xbox.com"
CERT_KEY="${CERT_DIR}/server.key"
CERT_CRT="${CERT_DIR}/server.crt"

if [ ! -f "$CERT_KEY" ] || [ ! -f "$CERT_CRT" ]; then
    echo "Generating lightweight ECDSA P-256 certificate..."
    openssl req -x509 -newkey ec \
        -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$CERT_KEY" \
        -out "$CERT_CRT" \
        -days 3650 -nodes \
        -subj "/CN=${FAKE_SNI}/O=Microsoft/C=US"
    echo "✅ Certificate generated (ECDSA P-256 - fast & lightweight)."
else
    echo "✅ Existing certificate found. Skipping generation."
fi

# --- 5. Detect public IP ---
echo "Detecting public IP..."
server_ip=""
for url in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://checkip.amazonaws.com"; do
    server_ip=$(curl -fsSL --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
    if [[ "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
    server_ip=""
done
[ -z "$server_ip" ] && server_ip=$(hostname -I | awk '{print $1}')
if [ -z "$server_ip" ]; then
    echo "❌ Could not detect server IP. Exiting."
    exit 1
fi
echo "✅ Server IP: $server_ip"

# --- 6. Generate Gaming-Optimized TLS config ---
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

cat > "$TEMP_CONFIG" << JSON
{
  "log": {
    "level": "fatal",
    "timestamp": false
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${SERVER_PORT},
      "tcp_fast_open": true,
      "udp_fragment": true,
      "reuse_addr": true,
      "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_CRT}",
        "key_path": "${CERT_KEY}"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "tcp_fast_open": true,
      "udp_fragment": true,
      "reuse_addr": true,
      "tcp_multi_path": false
    }
  ],
  "route": {
    "rules": [],
    "final": "direct"
  }
}
JSON

if [ ! -f "$CONFIG_PATH" ] || ! cmp -s "$TEMP_CONFIG" "$CONFIG_PATH"; then
    echo "Updating config.json..."
    mv "$TEMP_CONFIG" "$CONFIG_PATH"
else
    echo "Config unchanged. Skipping write."
    rm -f "$TEMP_CONFIG"
fi

# --- 7. Validate config ---
if ! sing-box check -c "$CONFIG_PATH" 2>&1; then
    echo "❌ Config validation failed. Check config at $CONFIG_PATH"
    exit 1
fi

# --- 8. Print VLESS TLS link ---
VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=tls&sni=${FAKE_SNI}&allowInsecure=1&type=tcp&fp=chrome#Nour-TLS"
echo ""
echo "=========================================================="
echo "sing-box VLESS TLS Link (Gaming Optimized):"
echo "$VLESS_LINK"
echo "=========================================================="
echo "⚠️  Client must have 'Allow Insecure' / 'skip-cert-verify' enabled."
echo "=========================================================="
echo ""

# --- 9. Start sing-box ---
echo "Starting sing-box..."
sleep 0.5
exec sing-box run -c "$CONFIG_PATH"
