#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

PARENT_DIR=$(cd .. && pwd)
XRAY_SCRIPT="${PARENT_DIR}/xray.sh"

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate sudo openssl
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
#   GENERATOR: ssl cert
# ==========================================
generate_ssl() {
    local CERT_PATH="$1"
    local KEY_PATH="$2"

    if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
        echo "  [SSL] ✔  Certificate already exists. Skipping."
        return
    fi

    echo "  [SSL] Generating self-signed certificate..."
    openssl req -x509 -newkey ec \
        -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH" \
        -days 365 -nodes \
        -subj "/CN=n" 2>/dev/null

    chmod +x "$CERT_PATH"
    chmod +x "$KEY_PATH"
    echo "  [SSL] ✅ Certificate generated."
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
SSL_DIR="/usr/local/etc/ssl"
CERT_PATH="${SSL_DIR}/cert.crt"
KEY_PATH="${SSL_DIR}/key.key"

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

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

cat > "$CONFIG_PATH" << JSON
{
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
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_PATH}",
              "keyFile": "${KEY_PATH}"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
JSON

echo "=========================================================="
echo "Xray VLESS Link:"
echo "vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=tls&sni=playstation.net&allowInsecure=true#Nour"
echo "=========================================================="

echo "Starting Xray..."
xray run -c "$CONFIG_PATH"
XRAY_EOF
}

# ==========================================
#   [2] CHECK FOR UPDATES
# ==========================================
echo "--- [2] Checking for Updates ---"

check_update "$0" \
    "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

# ==========================================
#   [3] Generating proxy scripts & SSL
# ==========================================
echo "--- [3] Generating proxy scripts ---"

SSL_DIR="/usr/local/etc/ssl"
CERT_PATH="${SSL_DIR}/cert.crt"
KEY_PATH="${SSL_DIR}/key.key"
mkdir -p "$SSL_DIR"

generate_ssl "$CERT_PATH" "$KEY_PATH"
generate_xray "$XRAY_SCRIPT"
chmod +x "$XRAY_SCRIPT"

# ==========================================
#        DONE
# ==========================================
echo ""
echo -e "\e[1;36m"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║         ✅  SETUP COMPLETE               ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║                                          ║"
echo "  ║  🔐 SSL Certificate  →  Ready            ║"
echo "  ║  ⚙️  Xray Config      →  Ready            ║"
echo "  ║                                          ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║  ▶  To start Xray:                       ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "\e[0m"
echo -e "\e[1;37m  bash ../xray.sh\e[0m"
echo ""
