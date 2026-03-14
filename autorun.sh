#!/bin/bash
# ==========================================
# MASTER SETUP SCRIPT - Final Gaming Version
# ==========================================
PARENT_DIR=$(cd .. && pwd)
XRAY_SCRIPT="${PARENT_DIR}/xray.sh"
SINGBOX_SCRIPT="${PARENT_DIR}/singbox.sh"

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"
if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate sudo openssl ca-certificates gnupg
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed."
else
    echo "--- [1] Dependencies already installed. Skipping. ---"
fi

# ==========================================
# HELPER: check_update <target> <url>
# ==========================================
check_update() {
    local TARGET="$1"
    local URL="$2"
    local NAME
    NAME=$(basename "$TARGET")
    echo " [$NAME] Checking..."
    curl -fsSL "$URL" -o /tmp/_update_check 2>/dev/null
    if[ -s /tmp/_update_check ]; then
        if [ ! -f "$TARGET" ] || ! cmp -s "$TARGET" /tmp/_update_check; then
            mv /tmp/_update_check "$TARGET"
            chmod +x "$TARGET"
            echo " [$NAME] ✅ Updated."
        else
            rm -f /tmp/_update_check
            echo " [$NAME] ✔ Up to date."
        fi
    else
        rm -f /tmp/_update_check
        echo " [$NAME] ⚠️ Could not reach remote. Skipping."
    fi
}

# ==========================================
# GENERATOR: xray.sh
# ==========================================
generate_xray() {
    cat << 'XRAY_EOF' > /tmp/_xray_tmp.sh
#!/bin/bash
echo "--- [Xray VLESS Startup Script] ---"
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"
mkdir -p "$CONFIG_DIR"

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

if [ -z "$SERVER_PORT" ]; then
    echo "💡 Tip for VLESS: You can use standard ports like 80, 8080, or your panel port."
    read -rp "Enter SERVER_PORT: " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] ||[ "$SERVER_PORT" -gt 65535 ]; do
        echo "Invalid port. Try again."
        read -rp "Enter SERVER_PORT: " SERVER_PORT
    done
fi

server_ip=$(curl -fsSL https://api.ipify.org 2>/dev/null || curl -fsSL https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

cat > "$CONFIG_PATH" << JSON
{
  "log": { "loglevel": "none" },
  "inbounds":[{
    "port": ${SERVER_PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${UUID}", "level": 0 }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "tcpSettings": { "header": { "type": "http" } },
      "sockopt": { "tcpFastOpen": true, "tcpNoDelay": true }
    },
    "sniffing": { "enabled": false }
  }],
  "outbounds":[{
    "protocol": "freedom",
    "settings": { "domainStrategy": "UseIPv4" }
  }]
}
JSON

VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=http&host=playstation.net#Nour"
echo "VLESS: $VLESS_LINK"
exec xray run -c "$CONFIG_PATH"
XRAY_EOF
    mv /tmp/_xray_tmp.sh "$XRAY_SCRIPT"
    chmod +x "$XRAY_SCRIPT"
    echo " [xray.sh] Ready."
}

# ==========================================
# GENERATOR: singbox.sh (final gaming optimized - proot)
# ==========================================
generate_singbox() {
    cat << 'SINGBOX_EOF' > /tmp/_singbox_tmp.sh
#!/bin/bash
echo "--- [sing-box Hysteria2 GAMING - Proot Mode] ---"
CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
CERT_PATH="${CONFIG_DIR}/server.crt"
KEY_PATH="${CONFIG_DIR}/server.key"
mkdir -p "$CONFIG_DIR"

# Install / update sing-box
if ! command -v sing-box >/dev/null 2>&1; then
    echo "Installing sing-box..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
    chmod a+r /etc/apt/keyrings/sagernet.asc
    echo 'Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc' > /etc/apt/sources.list.d/sagernet.sources
    apt-get update && apt-get install -y sing-box
else
    echo "sing-box: $(sing-box version | head -1)"
fi

# Fake TLS cert to mimic Real Sony Infrastructure and bypass inspection
if[ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "Generating Sony-mimicked TLS cert..."
    apt-get install -y openssl -qq
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$KEY_PATH" -out "$CERT_PATH" \
        -days 3650 -nodes \
        -subj "/C=US/ST=California/L=San Mateo/O=Sony Interactive Entertainment LLC/CN=playstation.net" \
        -addext "subjectAltName=DNS:playstation.net,DNS:www.playstation.net,DNS:*.playstation.net" 2>/dev/null
    echo "Cert generated."
fi

# Port
if[ -z "$SERVER_PORT" ]; then
    echo "💡 Tip for Hysteria2 Gaming Bypass: If your panel allows, try using PSN native UDP ports: 3478, 3479, or 443."
    read -rp "Enter SERVER_PORT: " SERVER_PORT
    while[ -z "$SERVER_PORT" ] || ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] ||[ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "Invalid port."
        read -rp "Enter SERVER_PORT: " SERVER_PORT
    done
fi

server_ip=$(curl -fsSL https://api.ipify.org 2>/dev/null || curl -fsSL https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
PASSWORD="nour"

# Note: Changed to 0.0.0.0 for proot compatibility, added Salamander Obfs, added Masquerade, removed invalid Singbox fields
cat > "$CONFIG_PATH" << JSON
{
  "log": { "disabled": false, "level": "info" },
  "inbounds":[
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "0.0.0.0",
      "listen_port": ${SERVER_PORT},
      "sniff": false,
      "users":[{ "password": "${PASSWORD}" }],
      "up_mbps": 1000,
      "down_mbps": 1000,
      "obfs": {
        "type": "salamander",
        "password": "${PASSWORD}"
      },
      "masquerade": "https://www.playstation.com",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    }
  ],
  "outbounds":[
    {
      "type": "direct",
      "tag": "direct",
      "tcp_fast_open": true
    }
  ]
}
JSON

HY2_LINK="hy2://${PASSWORD}@${server_ip}:${SERVER_PORT}?sni=playstation.net&alpn=h3&obfs=salamander&obfs-password=${PASSWORD}&insecure=1#Nour-Gaming"
echo "HY2 Link: $HY2_LINK"
echo "Starting sing-box..."
exec sing-box run -c "$CONFIG_PATH"
SINGBOX_EOF

    mv /tmp/_singbox_tmp.sh "$SINGBOX_SCRIPT"
    chmod +x "$SINGBOX_SCRIPT"
    echo "[singbox.sh] Ready (gaming optimized)."
}

# ==========================================
# Main logic
# ==========================================
echo "--- Checking for script updates ---"
check_update "$0" "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

echo "--- Generating proxy scripts ---"
generate_xray
generate_singbox

echo ""
echo "===================================================="
echo "               Setup Complete (Final)"
echo "===================================================="
echo ""
echo "Start Xray (VLESS TCP Bypass):"
echo "  bash ../xray.sh"
echo ""
echo "Start Hysteria2 (Gaming UDP Bypass):"
echo "  bash ../singbox.sh"
echo ""
echo "Done."
