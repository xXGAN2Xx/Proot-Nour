#!/bin/bash
# ==========================================
# MASTER SETUP SCRIPT - Final Gaming Version (Fixed)
# ==========================================

# FIX 1: Use script's own directory, not CWD
SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PARENT_DIR=$(dirname "$SCRIPT_DIR")
XRAY_SCRIPT="${PARENT_DIR}/xray.sh"
SINGBOX_SCRIPT="${PARENT_DIR}/singbox.sh"

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"
if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate sudo openssl
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
    if [ -s /tmp/_update_check ]; then
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
    read -rp "Enter SERVER_PORT: " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "Invalid port. Try again."
        read -rp "Enter SERVER_PORT: " SERVER_PORT
    done
fi

server_ip=$(curl -fsSL https://api.ipify.org 2>/dev/null || curl -fsSL https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

cat > "$CONFIG_PATH" << JSON
{
  "log": { "loglevel": "none" },
  "inbounds": [{
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
  "outbounds": [{
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
# GENERATOR: singbox.sh (gaming optimized - proot fixed)
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

# TLS cert
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "Generating self-signed TLS cert..."
    apt-get install -y openssl -qq
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$KEY_PATH" -out "$CERT_PATH" \
        -days 3650 -nodes \
        -subj "/CN=playstation.net" \
        -addext "subjectAltName=DNS:playstation.net,DNS:www.playstation.net" 2>/dev/null
    echo "Cert generated."
fi

# Port
if [ -z "$SERVER_PORT" ]; then
    read -rp "Enter SERVER_PORT: " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "Invalid port."
        read -rp "Enter SERVER_PORT: " SERVER_PORT
    done
fi

server_ip=$(curl -fsSL https://api.ipify.org 2>/dev/null || curl -fsSL https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
PASSWORD="nour"

# FIX 2: listen "0.0.0.0" instead of "::" — proot does not support IPv6 binding
# FIX 3: Removed up_mbps/down_mbps — they conflict with ignore_client_bandwidth: true
# FIX 4: Removed tcp_fast_open/udp_fragment from direct outbound — invalid fields there
# FIX 5: Added domain_strategy to direct outbound for proper IPv4 resolution
# FIX 6: Added route block — required for traffic to actually flow
cat > "$CONFIG_PATH" << JSON
{
  "log": { "disabled": true },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "0.0.0.0",
      "listen_port": ${SERVER_PORT},
      "sniff": false,
      "users": [{ "password": "${PASSWORD}" }],
      "ignore_client_bandwidth": true,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "route": {
    "final": "direct"
  }
}
JSON

HY2_LINK="hy2://${PASSWORD}@${server_ip}:${SERVER_PORT}?sni=playstation.net&alpn=h3&insecure=1#Nour-Gaming"
echo ""
echo "=============================="
echo " HY2 Link: $HY2_LINK"
echo "=============================="
echo ""
echo "Starting sing-box..."
exec sing-box run -c "$CONFIG_PATH"
SINGBOX_EOF

    mv /tmp/_singbox_tmp.sh "$SINGBOX_SCRIPT"
    chmod +x "$SINGBOX_SCRIPT"
    echo " [singbox.sh] Ready (gaming optimized)."
}

# ==========================================
# Main logic
# FIX 7: Do NOT self-update $0 while it is running — update a copy instead
# ==========================================
echo "--- Checking for script updates (non-destructive) ---"
check_update "${SCRIPT_DIR}/autorun_new.sh" "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

echo "--- Generating proxy scripts ---"
generate_xray
generate_singbox

echo ""
echo "===================================================="
echo "               Setup Complete (Final)"
echo "===================================================="
echo ""
echo "Start Xray (VLESS):"
echo "  bash ${XRAY_SCRIPT}"
echo ""
echo "Start Hysteria2 (Gaming):"
echo "  bash ${SINGBOX_SCRIPT}"
echo ""
echo "Done."
