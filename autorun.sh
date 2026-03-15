#!/bin/bash
# ==========================================
# MASTER SETUP SCRIPT (MODIFIED: VLESS + TCP + TLS with FAKE CERT)
# ==========================================
# 1. Determine the path for the parent directory (cd ..)
PARENT_DIR=$(cd .. && pwd)
TARGET_SCRIPT="${PARENT_DIR}/singbox.sh"

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"
if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate sudo openssl
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed (including openssl for fake cert)."
else
    echo "--- [1] System Setup: Dependencies already installed. Skipping. ---"
fi

# ==========================================
# SELF-UPDATE LOGIC (OS LEVEL)
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
# SING-BOX SCRIPT GENERATION & UPDATE
# ==========================================
echo "--- [3] Checking for singbox.sh updates in $PARENT_DIR ---"
SINGBOX_SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/singbox.sh"
curl -fsSL "$SINGBOX_SCRIPT_URL" -o /tmp/singbox_update_check 2>/dev/null
if [ -s /tmp/singbox_update_check ]; then
    if [ ! -f "$TARGET_SCRIPT" ] || ! cmp -s "$TARGET_SCRIPT" /tmp/singbox_update_check; then
        echo "New version of singbox.sh found! Updating..."
        mv /tmp/singbox_update_check "$TARGET_SCRIPT"
        chmod +x "$TARGET_SCRIPT"
        echo "singbox.sh updated successfully."
    else
        echo "singbox.sh is up to date."
        rm -f /tmp/singbox_update_check
    fi
else
    echo "Could not fetch singbox.sh from remote. Falling back to built-in template (TCP+TLS with fake cert)..."
    rm -f /tmp/singbox_update_check
    cat << 'EOF' > /tmp/singbox_builtin
#!/bin/bash
echo "--- [sing-box VLESS+TLS (Fake Cert) Startup Script - Gaming Optimized] ---"

CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
TEMP_CONFIG="/tmp/singbox_config_temp.json"
mkdir -p "$CONFIG_DIR"

# --- 1. Collect PORT first, before anything else ---
if [ -z "$SERVER_PORT" ]; then
    echo ""
    echo "Please enter the port you want sing-box to listen on (recommended: 443 for TLS):"
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

# --- 3. Detect public IP (with multiple fallbacks) ---
echo "Detecting public IP..."
server_ip=""
for url in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://checkip.amazonaws.com"; do
    server_ip=$(curl -fsSL --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
    if [[ "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
    server_ip=""
done
if [ -z "$server_ip" ]; then
    server_ip=$(hostname -I | awk '{print $1}')
fi
if [ -z "$server_ip" ]; then
    echo "❌ Could not detect server IP. Exiting."
    exit 1
fi
echo "✅ Server IP: $server_ip"

# --- 4. Generate FAKE TLS Certificate (self-signed for playstation.net) ---
DOMAIN="playstation.net"
CERT_DIR="${CONFIG_DIR}/certs"
mkdir -p "$CERT_DIR"
CERT_PATH="${CERT_DIR}/cert.pem"
KEY_PATH="${CERT_DIR}/key.pem"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "Generating fake self-signed TLS certificate for ${DOMAIN}..."
    if ! openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=${DOMAIN}" >/dev/null 2>&1; then
        echo "❌ Failed to generate fake certificate (openssl error). Exiting."
        exit 1
    fi
    echo "✅ Fake TLS certificate generated for ${DOMAIN} (valid 10 years)."
else
    echo "✅ Using existing fake certificate."
fi

# --- 5. Generate Gaming-Optimized config (VLESS + TCP + TLS) ---
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
        "server_name": "${DOMAIN}",
        "certificate": "${CERT_PATH}",
        "certificate_key": "${KEY_PATH}",
        "alpn": ["http/1.1"]
      },
      "multiplex": {
        "enabled": false
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
    echo "Updating config.json with TCP+TLS fake cert..."
    mv "$TEMP_CONFIG" "$CONFIG_PATH"
else
    echo "Config unchanged. Skipping write."
    rm -f "$TEMP_CONFIG"
fi

# --- 6. Validate config before starting ---
if ! sing-box check -c "$CONFIG_PATH" 2>&1; then
    echo "❌ Config validation failed. Check config at $CONFIG_PATH"
    exit 1
fi

# --- 7. Print VLESS+TLS link ---
VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=tls&type=tcp&sni=${DOMAIN}&fp=chrome&alpn=http/1.1#Nour"
echo ""
echo "=========================================================="
echo "sing-box VLESS+TLS Link (Gaming Optimized + Fake Cert):"
echo "$VLESS_LINK"
echo ""
echo "NOTE: Clients may need 'Allow Insecure' / 'Skip Cert Verify' enabled because this is a fake/self-signed cert."
echo "=========================================================="
echo ""

# --- 8. Start sing-box (flush output first) ---
echo "Starting sing-box..."
sleep 0.5
exec sing-box run -c "$CONFIG_PATH"
EOF

    if [ ! -f "$TARGET_SCRIPT" ] || ! cmp -s /tmp/singbox_builtin "$TARGET_SCRIPT"; then
        echo "singbox.sh is missing or differs from built-in template. Updating..."
        mv /tmp/singbox_builtin "$TARGET_SCRIPT"
        chmod +x "$TARGET_SCRIPT"
        echo "singbox.sh updated from built-in template (now uses TCP+TLS with fake certificate)."
    else
        echo "singbox.sh matches built-in template. No update needed."
        rm -f /tmp/singbox_builtin
    fi
fi

echo "--- Setup Complete ---"
echo "To start the sing-box server (VLESS+TLS with fake cert), run:"
echo "bash ../singbox.sh"
