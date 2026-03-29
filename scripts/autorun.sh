#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XRAY_SCRIPT="${SCRIPT_DIR}/xray.sh"

DEP_LOCK_FILE="/etc/os_deps_installed"

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Run as root." >&2
    exit 1
fi

# ── [1] Dependencies ─────────────────────

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y --no-install-recommends \
        curl wget sed python3-minimal tmate sudo ca-certificates
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
    # Using evaluated heredoc to bake the existing SERVER_IP into the script
    cat << EOF > "$TARGET"
#!/bin/bash

echo "--- [Xray VLESS+TCP+REALITY Startup Script] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="\${CONFIG_DIR}/config.json"

mkdir -p "\$CONFIG_DIR"

# --- Xray Core Installation ---
echo "Checking/Installing Xray-core..."
bash -c "\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

# --- Port ---
if [ -z "\${SERVER_PORT:-}" ]; then
    echo ""
    echo "⚠️  SERVER_PORT is not set!"
    read -rp "SERVER_PORT: " SERVER_PORT
    while [ -z "\$SERVER_PORT" ] || ! echo "\$SERVER_PORT" | grep -qE '^[0-9]+$' \
          || [ "\$SERVER_PORT" -lt 1 ] || [ "\$SERVER_PORT" -gt 65535 ]; do
        echo "❌ Invalid port. Enter a number between 1 and 65535:"
        read -rp "SERVER_PORT: " SERVER_PORT
    done
    echo "✅ Using port: \$SERVER_PORT"
fi

# --- REALITY static keypair ---
PRIVATE_KEY="WAknjCzrZE_OgBB3p1579an4Yy-0dkdjl0Ic70-Svl8"
PUBLIC_KEY="X-30WKOlRoYNZPDtyEys7oYKTFJoP-1k9qLfvNVPPgQ"
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

cat > "\$CONFIG_PATH" << JSON
{
  "log": { "loglevel": "none" },
  "inbounds": [
    {
      "port": \${SERVER_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "\${UUID}",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.google.com:443",
          "serverNames": [
            "playstation.net",
            "ekb.eg",
            "www.facebook.com",
            "c.whatsapp.net",
            "www.youtube.com"
          ],
          "privateKey": "\${PRIVATE_KEY}",
          "shortIds": [""]
        }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
JSON

echo ""
echo "=========================================================="
echo "  VLESS+TCP+REALITY Link:"
echo "  vless://\${UUID}@${server_ip}:\${SERVER_PORT}?encryption=none&security=reality&sni=playstation.net&fp=chrome&pbk=\${PUBLIC_KEY}&allowInsecure=1#Nour"
echo "=========================================================="
echo ""

echo "Starting Xray..."
xray run -c "\$CONFIG_PATH"
EOF
}

# ==========================================
#   [2] Generate proxy scripts
# ==========================================

echo "--- [2] Generating proxy scripts ---"

generate_xray "$XRAY_SCRIPT"
chmod +x "$XRAY_SCRIPT"

# ==========================================
#        DONE
# ==========================================

echo ""
printf "\e[1;36m"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║         ✅  SETUP COMPLETE               ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║                                          ║"
echo "  ║  🌍  Using IP        →  $server_ip"
echo "  ║  ⚙️  Xray Config      →  Ready            ║"
echo "  ║                                          ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║  ▶  To start Xray:                       ║"
echo "bash $XRAY_SCRIPT"
echo "  ╚══════════════════════════════════════════╝"
printf "\e[0m\n"
