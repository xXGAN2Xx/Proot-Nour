#!/bin/bash
# ==========================================
# MASTER SETUP SCRIPT - Proot Gaming (Fixed)
# ==========================================

SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PARENT_DIR=$(dirname "$SCRIPT_DIR")
XRAY_SCRIPT="${PARENT_DIR}/xray.sh"
SINGBOX_SCRIPT="${PARENT_DIR}/singbox.sh"

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
            echo " [$NAME] Updated."
        else
            rm -f /tmp/_update_check
            echo " [$NAME] Up to date."
        fi
    else
        rm -f /tmp/_update_check
        echo " [$NAME] Could not reach remote. Skipping."
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
    read -rp "Enter SERVER_PORT (1025-65535 for proot): " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1025 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "Invalid port. Must be 1025-65535."
        read -rp "Enter SERVER_PORT: " SERVER_PORT
    done
fi

server_ip=$(curl -fsSL https://api.ipify.org 2>/dev/null || curl -fsSL https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

cat > "$CONFIG_PATH" << JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${SERVER_PORT},
    "listen": "0.0.0.0",
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
echo ""
echo "=============================="
echo " VLESS Link: $VLESS_LINK"
echo "=============================="
echo ""
exec xray run -c "$CONFIG_PATH"
XRAY_EOF
    mv /tmp/_xray_tmp.sh "$XRAY_SCRIPT"
    chmod +x "$XRAY_SCRIPT"
    echo " [xray.sh] Ready."
}

# ==========================================
# GENERATOR: singbox.sh
# FIX SUMMARY:
#   1. Direct binary install — apt fails in proot
#   2. DNS block with ipv4_only — proot has no IPv6 stack
#   3. domain_strategy: ipv4_only — prefer_ipv4 still tries IPv6 first
#   4. auto_detect_interface: false — proot can't detect interfaces → crash/no route
#   5. Port validation requires >1024 — proot can't bind privileged ports
#   6. Logging enabled (warn) — needed to diagnose failures
# ==========================================
generate_singbox() {
    cat << 'SINGBOX_EOF' > /tmp/_singbox_tmp.sh
#!/bin/bash
echo "--- [sing-box Hysteria2 GAMING - Proot Mode Fixed] ---"
CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
CERT_PATH="${CONFIG_DIR}/server.crt"
KEY_PATH="${CONFIG_DIR}/server.key"
SINGBOX_BIN="/usr/local/bin/sing-box"
mkdir -p "$CONFIG_DIR"

# -------------------------------------------------------
# FIX 1: Install sing-box via direct binary download.
# apt install fails in proot because systemd/dbus hooks
# run during package post-install and break everything.
# -------------------------------------------------------
install_singbox_binary() {
    echo "Installing sing-box binary directly..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)          ARCH_TAG="amd64" ;;
        aarch64|arm64)   ARCH_TAG="arm64" ;;
        armv7l)          ARCH_TAG="armv7" ;;
        *)
            echo "Unsupported CPU arch: $ARCH"
            exit 1
            ;;
    esac

    # Fetch latest stable version tag
    VER=$(curl -fsSL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" \
          | grep '"tag_name"' | cut -d'"' -f4 | sed 's/v//')
    [ -z "$VER" ] && VER="1.9.7"   # fallback if GitHub rate-limits

    TARBALL="sing-box-${VER}-linux-${ARCH_TAG}.tar.gz"
    URL="https://github.com/SagerNet/sing-box/releases/download/v${VER}/${TARBALL}"

    echo "Downloading sing-box v${VER} (${ARCH_TAG})..."
    curl -fsSL "$URL" -o "/tmp/${TARBALL}" || { echo "Download failed."; exit 1; }
    tar -xzf "/tmp/${TARBALL}" -C /tmp/
    mv "/tmp/sing-box-${VER}-linux-${ARCH_TAG}/sing-box" "$SINGBOX_BIN"
    chmod +x "$SINGBOX_BIN"
    rm -rf "/tmp/${TARBALL}" "/tmp/sing-box-${VER}-linux-${ARCH_TAG}"
    echo "sing-box installed: $($SINGBOX_BIN version | head -1)"
}

if ! command -v sing-box >/dev/null 2>&1 || ! sing-box version >/dev/null 2>&1; then
    install_singbox_binary
else
    echo "sing-box already present: $(sing-box version | head -1)"
fi

# -------------------------------------------------------
# TLS cert (self-signed, SNI = playstation.net)
# -------------------------------------------------------
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "Generating self-signed TLS cert..."
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$KEY_PATH" -out "$CERT_PATH" \
        -days 3650 -nodes \
        -subj "/CN=playstation.net" \
        -addext "subjectAltName=DNS:playstation.net,DNS:www.playstation.net" 2>/dev/null
    echo "Cert generated."
fi

# -------------------------------------------------------
# FIX 5: Port — proot can't bind ports < 1025
# -------------------------------------------------------
if [ -z "$SERVER_PORT" ]; then
    read -rp "Enter SERVER_PORT (1025-65535): " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] \
          || [ "$SERVER_PORT" -lt 1025 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "Invalid. Must be 1025-65535 (proot cannot bind privileged ports)."
        read -rp "Enter SERVER_PORT: " SERVER_PORT
    done
fi

server_ip=$(curl -fsSL https://api.ipify.org 2>/dev/null \
          || curl -fsSL https://ifconfig.me 2>/dev/null \
          || hostname -I | awk '{print $1}')
PASSWORD="nour"

# -------------------------------------------------------
# Config — all proot-specific fixes applied
# -------------------------------------------------------
cat > "$CONFIG_PATH" << JSON
{
  "log": {
    "disabled": false,
    "level": "warn",
    "timestamp": true
  },

  "dns": {
    "servers": [
      {
        "tag": "dns-direct",
        "address": "udp://8.8.8.8",
        "detour": "direct"
      },
      {
        "tag": "dns-fallback",
        "address": "udp://1.1.1.1",
        "detour": "direct"
      }
    ],
    "final": "dns-direct",
    "strategy": "ipv4_only"
  },

  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "0.0.0.0",
      "listen_port": ${SERVER_PORT},
      "sniff": false,
      "sniff_override_destination": false,
      "users": [
        { "password": "${PASSWORD}" }
      ],
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
      "domain_strategy": "ipv4_only"
    }
  ],

  "route": {
    "final": "direct",
    "auto_detect_interface": false
  }
}
JSON

HY2_LINK="hy2://${PASSWORD}@${server_ip}:${SERVER_PORT}?sni=playstation.net&alpn=h3&insecure=1#Nour-Gaming"
echo ""
echo "=============================="
echo " HY2 Link:"
echo " $HY2_LINK"
echo "=============================="
echo ""

# Validate config before starting
echo "Validating config..."
if ! sing-box check -c "$CONFIG_PATH"; then
    echo "Config validation FAILED. Check the config above."
    exit 1
fi

echo "Starting sing-box..."
exec sing-box run -c "$CONFIG_PATH"
SINGBOX_EOF

    mv /tmp/_singbox_tmp.sh "$SINGBOX_SCRIPT"
    chmod +x "$SINGBOX_SCRIPT"
    echo " [singbox.sh] Ready (proot gaming fixed)."
}

# ==========================================
# Main
# ==========================================
echo "--- Checking for script updates (non-destructive) ---"
check_update "${SCRIPT_DIR}/autorun_new.sh" \
    "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

echo "--- Generating proxy scripts ---"
generate_xray
generate_singbox

echo ""
echo "===================================================="
echo "          Setup Complete - Proot Gaming"
echo "===================================================="
echo ""
echo "Start Xray (VLESS):"
echo "  bash ${XRAY_SCRIPT}"
echo ""
echo "Start Hysteria2 (Gaming):"
echo "  bash ${SINGBOX_SCRIPT}"
echo ""
echo "Done."
