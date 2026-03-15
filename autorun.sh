#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

PARENT_DIR=$(cd .. && pwd)
TARGET_SCRIPT="${PARENT_DIR}/hy2.sh"
DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget openssl ca-certificates 
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
#        HY2 SCRIPT — ALWAYS OVERWRITE
# ==========================================
cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash
echo "--- [Hysteria2 Server] ---"

CONFIG_DIR="/etc/hysteria"
CONFIG_PATH="$CONFIG_DIR/config.yaml"
CERT_FILE="$CONFIG_DIR/cert.pem"
KEY_FILE="$CONFIG_DIR/key.pem"
PASSWORD="nour"
SNI="playstation.net"
HY2_BIN="/usr/local/bin/hysteria"

mkdir -p "$CONFIG_DIR"

# --- Port ---
if [ -z "$SERVER_PORT" ]; then
    read -rp "Enter port: " SERVER_PORT
fi
echo "✅ Port: $SERVER_PORT"

# --- Install Hysteria2 ---
echo "Installing Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/)
if [ ! -f "$HY2_BIN" ]; then
    echo "❌ Hysteria2 install failed."
    exit 1
fi
echo "✅ Hysteria2 installed: $($HY2_BIN version 2>/dev/null | head -1)"

# --- Self-signed TLS cert ---
openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -days 3650 -nodes \
    -subj "/C=US/ST=California/L=San Jose/O=Sony Interactive Entertainment/OU=PlayStation Network/CN=${SNI}" \
    2>/dev/null
echo "✅ TLS cert generated."

echo "✅ IP: $server_ip"

# --- Config ---
cat > "$CONFIG_PATH" << YAML
listen: :${SERVER_PORT}

tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}

auth:
  type: password
  password: ${PASSWORD}

YAML

# --- Print config for verification ---
echo ""
echo "--- Config Preview ---"
cat "$CONFIG_PATH"
echo "----------------------"
echo ""

echo "================================================"
echo "Hysteria2 Link:"
echo "hy2://${PASSWORD}@${server_ip}:${SERVER_PORT}?sni=${SNI}&insecure=1#Nour"
echo "================================================"
echo "⚠️  Enable 'Allow Insecure' on client (self-signed cert)"
echo ""

echo "Starting Hysteria2..."
exec "$HY2_BIN" server -c "$CONFIG_PATH"
EOF

chmod +x "$TARGET_SCRIPT"

echo "--- Setup Complete. Run: bash ../hy2.sh ---"
