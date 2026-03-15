#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

PARENT_DIR=$(cd .. && pwd)
TARGET_SCRIPT="${PARENT_DIR}/singbox.sh"
DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget openssl
    touch "$DEP_LOCK_FILE"
else
    echo "--- [1] Dependencies already installed. Skipping. ---"
fi

# ==========================================
#        SELF-UPDATE LOGIC
# ==========================================
echo "--- [2] Checking for Script Updates ---"

SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
curl -fsSL "$SCRIPT_URL" -o /tmp/script_update_check
if [ -s /tmp/script_update_check ] && ! cmp -s "$0" /tmp/script_update_check; then
    echo "New version found! Updating..."
    mv /tmp/script_update_check "$0"
    chmod +x "$0"
    exec "$0" "$@"
    exit 0
fi
rm -f /tmp/script_update_check
echo "Script is up to date."

# ==========================================
#        SING-BOX SCRIPT UPDATE
# ==========================================
echo "--- [3] Checking for singbox.sh updates ---"

SINGBOX_SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/singbox.sh"
curl -fsSL "$SINGBOX_SCRIPT_URL" -o /tmp/singbox_update_check 2>/dev/null

if [ -s /tmp/singbox_update_check ]; then
    if [ ! -f "$TARGET_SCRIPT" ] || ! cmp -s "$TARGET_SCRIPT" /tmp/singbox_update_check; then
        echo "Updating singbox.sh..."
        mv /tmp/singbox_update_check "$TARGET_SCRIPT"
        chmod +x "$TARGET_SCRIPT"
    else
        echo "singbox.sh is up to date."
        rm -f /tmp/singbox_update_check
    fi
else
    echo "Could not fetch singbox.sh. Using built-in template..."
    rm -f /tmp/singbox_update_check

    cat << 'EOF' > /tmp/singbox_builtin
#!/bin/bash
echo "--- [sing-box VLESS TCP+TLS] ---"

CONFIG_DIR="/usr/local/etc/sing-box"
CERT_DIR="$CONFIG_DIR/tls"
CONFIG_PATH="$CONFIG_DIR/config.json"
CERT_FILE="$CERT_DIR/cert.pem"
KEY_FILE="$CERT_DIR/key.pem"
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"
SNI="playstation.net"

mkdir -p "$CERT_DIR"

# --- Port ---
if [ -z "$SERVER_PORT" ]; then
    read -rp "Enter port: " SERVER_PORT
fi
echo "✅ Port: $SERVER_PORT"

# --- Install sing-box ---
curl -fsSL https://sing-box.app/install.sh | sh
command -v sing-box &>/dev/null || { echo "❌ sing-box install failed."; exit 1; }

# --- Self-signed TLS cert ---
openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -days 3650 -nodes -subj "/CN=${SNI}" 2>/dev/null
echo "✅ TLS cert generated."

# --- Detect IP ---
for url in https://api.ipify.org https://ifconfig.me https://icanhazip.com; do
    IP=$(curl -fsSL --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
    [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break || IP=""
done
[ -z "$IP" ] && IP=$(hostname -I | awk '{print $1}')
[ -z "$IP" ] && { echo "❌ Could not detect IP."; exit 1; }
echo "✅ IP: $IP"

# --- Config ---
cat > "$CONFIG_PATH" << JSON
{
  "inbounds": [{
    "type": "vless",
    "listen": "::",
    "listen_port": ${SERVER_PORT},
    "users": [{ "uuid": "${UUID}" }],
    "tls": {
      "enabled": true,
      "server_name": "${SNI}",
      "certificate_path": "${CERT_FILE}",
      "key_path": "${KEY_FILE}"
    }
  }],
  "outbounds": [{ "type": "direct" }]
}
JSON

# --- Validate & Start ---
sing-box check -c "$CONFIG_PATH" || { echo "❌ Config invalid."; exit 1; }

echo ""
echo "================================================"
echo "VLESS Link:"
echo "vless://${UUID}@${IP}:${SERVER_PORT}?security=tls&type=tcp&sni=${SNI}&allowInsecure=1#Nour"
echo "================================================"
echo "⚠️  Enable 'Allow Insecure' on client (self-signed cert)"
echo ""

exec sing-box run -c "$CONFIG_PATH"
EOF

    if [ ! -f "$TARGET_SCRIPT" ] || ! cmp -s /tmp/singbox_builtin "$TARGET_SCRIPT"; then
        mv /tmp/singbox_builtin "$TARGET_SCRIPT"
        chmod +x "$TARGET_SCRIPT"
        echo "singbox.sh updated from built-in."
    else
        rm -f /tmp/singbox_builtin
    fi
fi

echo "--- Setup Complete. Run: bash ../singbox.sh ---"
