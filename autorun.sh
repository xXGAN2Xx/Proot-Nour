#!/bin/bash
# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/hy2.sh"
DEP_LOCK="${HOME}/.local/share/os_deps_installed"
mkdir -p "${HOME}/.local/share"

# ==========================================
#        [1] DEPENDENCIES
# ==========================================
if [ ! -f "$DEP_LOCK" ]; then
    echo "--- [1] Installing Dependencies ---"
    apt-get update -qq
    apt-get install -y curl wget openssl ca-certificates python3-minimal util-linux
    touch "$DEP_LOCK"
else
    echo "--- [1] Dependencies already installed. Skipping. ---"
fi

# ==========================================
#        [2] SELF-UPDATE
# ==========================================
echo "--- [2] Checking for Script Updates ---"
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
TMP_UPDATE="$(mktemp /tmp/autorun_update.XXXXXX)"
trap 'rm -f "$TMP_UPDATE"' EXIT

if curl -fsSL --connect-timeout 10 "$SCRIPT_URL" -o "$TMP_UPDATE" && [ -s "$TMP_UPDATE" ]; then
    if ! cmp -s "${BASH_SOURCE[0]}" "$TMP_UPDATE"; then
        echo "New version found! Updating..."
        cp "$TMP_UPDATE" "${BASH_SOURCE[0]}"
        chmod +x "${BASH_SOURCE[0]}"
        exec "${BASH_SOURCE[0]}" "$@"
    fi
fi
echo "Script is up to date."

# ==========================================
#        [3] HY2 SCRIPT — ALWAYS OVERWRITE
# ==========================================
cat > "$TARGET_SCRIPT" << 'EOF'
#!/bin/bash
set -euo pipefail
echo "--- [Hysteria2 Server] ---"

CONFIG_DIR="${HOME}/.config/hysteria"
CONFIG_PATH="${CONFIG_DIR}/config.yaml"
CERT_FILE="${CONFIG_DIR}/cert.pem"
KEY_FILE="${CONFIG_DIR}/key.pem"
HY2_BIN="${HOME}/.local/bin/hysteria"
PASSWORD="nour"
SNI="playstation.net"

mkdir -p "$CONFIG_DIR" "${HOME}/.local/bin"

# --- Port ---
if [ -z "${SERVER_PORT:-}" ]; then
    read -rp "Enter port: " SERVER_PORT
fi
echo "✅ Port: $SERVER_PORT"

echo "✅ IP: $SERVER_IP"

# --- Install Hysteria2 ---
echo "Installing Hysteria2..."
TMP_INSTALLER="$(mktemp /tmp/hy2_install.XXXXXX.sh)"
trap 'rm -f "$TMP_INSTALLER"' EXIT
curl -fsSL https://get.hy2.sh/ -o "$TMP_INSTALLER"
sed -i "s|/usr/local/bin|${HOME}/.local/bin|g" "$TMP_INSTALLER"
bash "$TMP_INSTALLER" || true
# fallback if official script ignored our sed patch
[ -f "$HY2_BIN" ] || { cp /usr/local/bin/hysteria "$HY2_BIN" && chmod +x "$HY2_BIN"; }
[ -x "$HY2_BIN" ] || { echo "❌ Hysteria2 install failed."; exit 1; }
echo "✅ Hysteria2 installed: $("$HY2_BIN" version 2>/dev/null | head -1)"

# --- Self-signed TLS cert ---
openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -days 3650 -nodes \
    -subj "/C=US/ST=California/L=San Jose/O=Sony Interactive Entertainment/OU=PlayStation Network/CN=${SNI}" \
    2>/dev/null
chmod 600 "$KEY_FILE"
echo "✅ TLS cert generated."

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

# --- Summary ---
echo ""
echo "--- Config Preview ---"
cat "$CONFIG_PATH"
echo "----------------------"
echo ""
echo "================================================"
echo "Hysteria2 Link:"
echo "hy2://${PASSWORD}@${SERVER_IP}:${SERVER_PORT}?sni=${SNI}&insecure=1#Nour"
echo "================================================"
echo "⚠️  Enable 'Allow Insecure' on client (self-signed cert)"
echo ""
echo "Starting Hysteria2..."
exec "$HY2_BIN" server -c "$CONFIG_PATH"
EOF

chmod +x "$TARGET_SCRIPT"
echo "--- Setup Complete. Run: bash ${TARGET_SCRIPT} ---"
