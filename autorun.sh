#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XRAY_SCRIPT="${SCRIPT_DIR}/xray.sh"
HY2_SCRIPT="${SCRIPT_DIR}/hy2.sh"

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
        curl wget sed python3-minimal tmate sudo ca-certificates openssl
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
    cat << 'XRAY_EOF' > "$TARGET"
#!/bin/bash

echo "--- [Xray VLESS+TCP+TLS Startup Script] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"
CERT_DIR="/etc/hysteria"

mkdir -p "$CONFIG_DIR"

# --- Xray Core Installation ---
echo "Checking/Installing Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

# --- Port ---
if [ -z "${SERVER_PORT:-}" ]; then
    echo ""
    echo "⚠️  SERVER_PORT is not set!"
    read -rp "SERVER_PORT: " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! echo "$SERVER_PORT" | grep -qE '^[0-9]+$' \
          || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "❌ Invalid port. Enter a number between 1 and 65535:"
        read -rp "SERVER_PORT: " SERVER_PORT
    done
    echo "✅ Using port: $SERVER_PORT"
fi

# --- IP ---
if [ -z "${SERVER_IP:-}" ]; then
    echo "🔍 Auto-detecting public IP..."
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org \
             || curl -s --max-time 5 https://ifconfig.me \
             || curl -s --max-time 5 https://icanhazip.com || true)
    if [ -n "$SERVER_IP" ]; then
        echo "✅ Detected IP: $SERVER_IP"
    else
        echo "⚠️  Could not auto-detect IP. Please enter it manually:"
        read -rp "SERVER_IP: " SERVER_IP
    fi
fi

# --- TLS certificate (shared with Hysteria2) ---
mkdir -p "$CERT_DIR"
if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
    echo "Generating self-signed TLS certificate..."
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$CERT_DIR/server.key" \
        -out    "$CERT_DIR/server.crt" \
        -days 3650 -nodes \
        -subj "/C=JP/ST=Tokyo/O=Sony Interactive Entertainment/CN=playstation.net" \
        -addext "subjectAltName=IP:${SERVER_IP}"
    chmod 600 "$CERT_DIR/server.key"
    chmod 644 "$CERT_DIR/server.crt"
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

cat > "$CONFIG_PATH" << JSON
{
  "log": { "loglevel": "none" },
  "inbounds": [
    {
      "port": ${SERVER_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "level": 0 } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_DIR}/server.crt",
              "keyFile": "${CERT_DIR}/server.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
JSON

echo "=========================================================="
echo "Xray VLESS+TCP+TLS Link:"
echo "vless://${UUID}@${SERVER_IP}:${SERVER_PORT}?encryption=none&security=tls&sni=playstation.net&allowInsecure=1#Nour"
echo "=========================================================="

echo "Starting Xray..."
xray run -c "$CONFIG_PATH"
XRAY_EOF
}

# ==========================================
#   GENERATOR: hy2.sh
# ==========================================

generate_hy2() {
    local TARGET="$1"
    cat << 'HY2_EOF' > "$TARGET"
#!/bin/bash

echo "--- [Hysteria2 Startup Script] ---"

# --- Port ---
if [ -z "${SERVER_PORT:-}" ]; then
    echo ""
    echo "⚠️  SERVER_PORT is not set!"
    read -rp "SERVER_PORT: " SERVER_PORT
    while [ -z "$SERVER_PORT" ] || ! echo "$SERVER_PORT" | grep -qE '^[0-9]+$' \
          || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; do
        echo "❌ Invalid port. Enter a number between 1 and 65535:"
        read -rp "SERVER_PORT: " SERVER_PORT
    done
    echo "✅ Using port: $SERVER_PORT"
fi

# --- IP ---
if [ -z "${SERVER_IP:-}" ]; then
    echo "🔍 Auto-detecting public IP..."
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org \
             || curl -s --max-time 5 https://ifconfig.me \
             || curl -s --max-time 5 https://icanhazip.com || true)
    if [ -n "$SERVER_IP" ]; then
        echo "✅ Detected IP: $SERVER_IP"
    else
        echo "⚠️  Could not auto-detect IP. Please enter it manually:"
        read -rp "SERVER_IP: " SERVER_IP
    fi
fi

HY2_PASS="nour"
CERT_DIR="/etc/hysteria"

# --- Architecture detection ---
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        if grep -q avx /proc/cpuinfo 2>/dev/null; then
            BIN="hysteria-linux-amd64-avx"
        else
            BIN="hysteria-linux-amd64"
        fi ;;
    i386|i686)      BIN="hysteria-linux-386"    ;;
    aarch64|arm64)  BIN="hysteria-linux-arm64"  ;;
    armv7*|armv6*)  BIN="hysteria-linux-arm"    ;;
    armv5*)         BIN="hysteria-linux-armv5"  ;;
    riscv64)        BIN="hysteria-linux-riscv64";;
    loongarch64)    BIN="hysteria-linux-loong64";;
    s390x)          BIN="hysteria-linux-s390x"  ;;
    *)
        echo "[!] Unsupported architecture: $ARCH" >&2
        exit 1 ;;
esac

# --- Install Hysteria2 binary ---
echo "Installing Hysteria2 (${BIN})..."
curl -fsSL "https://github.com/apernet/hysteria/releases/latest/download/${BIN}" \
    -o /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria

# --- TLS certificate ---
mkdir -p "$CERT_DIR"
if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
    echo "Generating self-signed TLS certificate..."
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
        -keyout "$CERT_DIR/server.key" \
        -out    "$CERT_DIR/server.crt" \
        -days 3650 -nodes \
        -subj "/C=JP/ST=Tokyo/O=Sony Interactive Entertainment/CN=playstation.net" \
        -addext "subjectAltName=IP:${SERVER_IP}"
    chmod 600 "$CERT_DIR/server.key"
    chmod 644 "$CERT_DIR/server.crt"
fi

# --- Config ---
cat > /etc/hysteria/config.yaml << YAML
listen: :${SERVER_PORT}
tls:
  cert: ${CERT_DIR}/server.crt
  key:  ${CERT_DIR}/server.key
auth:
  type: password
  password: ${HY2_PASS}
ignoreClientBandwidth: true
YAML

echo ""
echo "══════════════════════════════════════"
echo "  Hysteria2 is up on port ${SERVER_PORT}"
echo "  Server IP : ${SERVER_IP}"
echo "  Password  : ${HY2_PASS}"
echo "══════════════════════════════════════"
echo ""
echo "  NekoBox client snippet:"
echo "  hy2://${HY2_PASS}@${SERVER_IP}:${SERVER_PORT}?insecure=1&sni=playstation.net#hy2"
echo ""

echo "[*] Starting Hysteria2..."
HYSTERIA_LOG_LEVEL=error hysteria server --config /etc/hysteria/config.yaml
HY2_EOF
}

# ==========================================
#   [2] Generate proxy scripts
# ==========================================

echo "--- [2] Generating proxy scripts ---"

generate_xray "$XRAY_SCRIPT"
chmod +x "$XRAY_SCRIPT"

generate_hy2 "$HY2_SCRIPT"
chmod +x "$HY2_SCRIPT"

# ==========================================
#        DONE
# ==========================================

echo ""
printf "\e[1;36m"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║         ✅  SETUP COMPLETE               ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║         By Nour                           ║"
echo "  ║  ⚙️  Xray Config      →  Ready            ║"
echo "  ║  ⚙️  Hysteria2 Config →  Ready            ║"
echo "  ║                                          ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║  ▶  To start Xray:                       ║"
echo "  ║     bash ../xray.sh                      ║"
echo "  ║                                          ║"
echo "  ║  ▶  To start Hysteria2:                  ║"
echo "  ║     bash ../hy2.sh                       ║"
echo "  ╚══════════════════════════════════════════╝"
printf "\e[0m\n"
