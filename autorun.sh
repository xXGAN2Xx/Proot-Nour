#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT (Gaming)
# ==========================================

PARENT_DIR=$(cd .. && pwd)
TARGET_SCRIPT="${PARENT_DIR}/xray.sh"

DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate sudo util-linux
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed."
else
    echo "--- [1] System Setup: Dependencies already installed. Skipping. ---"
fi

# ==========================================
#        SELF-UPDATE LOGIC
# ==========================================
echo "--- [2] Checking for Script Updates ---"

SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

# Resolve absolute path of this script (fixes exec in proot where $0 may lack a path)
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o /tmp/script_update_check

    if [ -s /tmp/script_update_check ]; then
        if ! cmp -s "$SELF" /tmp/script_update_check; then
            echo "New version found! Updating Master Script..."
            mv /tmp/script_update_check "$SELF"
            chmod +x "$SELF"
            echo "Restarting script..."
            exec bash "$SELF" "$@"
            exit 0
        else
            echo "Master Script is up to date."
            rm -f /tmp/script_update_check
        fi
    fi
fi

# ==========================================
#        XRAY SCRIPT GENERATION
# ==========================================
echo "--- [3] Checking for xray.sh in $PARENT_DIR ---"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "Creating $TARGET_SCRIPT (in the parent directory)..."

    cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash

echo "--- [Xray Gaming Server] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"

mkdir -p "$CONFIG_DIR"

# --- Xray Core Installation ---
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

if [ -z "$SERVER_PORT" ]; then
    echo "ERROR: SERVER_PORT is not set!"
    exit 1
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

# --- Kernel TCP Tuning ---
# BBR reduces latency and recovers faster from packet loss.
# Errors are silenced — some may fail inside proot, that is fine.
echo "Applying kernel tuning..."
sysctl -w net.ipv4.tcp_fastopen=3             2>/dev/null
sysctl -w net.ipv4.tcp_low_latency=1          2>/dev/null
sysctl -w net.core.rmem_max=16777216          2>/dev/null
sysctl -w net.core.wmem_max=16777216          2>/dev/null
sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null

# --- Write Config ---
# mKCP: tunnels over UDP at OS level — handles packet loss better than TCP for gaming.
# congestion:true  = built-in flow control
# header none      = zero overhead framing
# tcpNoDelay       = no Nagle batching, packets sent instantly
# tcpFastOpen      = faster reconnect handshake
cat > "$CONFIG_PATH" << JSON
{
  "log": { "loglevel": "none" },
  "inbounds": [
    {
      "port": SERVER_PORT_VAL,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "UUID_VAL" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "uplinkCapacity": 100,
          "downlinkCapacity": 100,
          "congestion": true,
          "header": { "type": "none" }
        },
        "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
JSON

sed -i "s/SERVER_PORT_VAL/$SERVER_PORT/g" "$CONFIG_PATH"
sed -i "s/UUID_VAL/$UUID/g"               "$CONFIG_PATH"

# --- Link ---
VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=kcp&headerType=none#Nour-Gaming"

echo "=========================================================="
echo " $VLESS_LINK"
echo " Port : $SERVER_PORT"
echo " UUID : $UUID"
echo "=========================================================="

# nice -n -10  = higher CPU scheduling priority than normal processes
# taskset -c 0 = pin Xray to CPU core 0 to reduce jitter from context switches in proot
nice -n -10 taskset -c 0 xray run -c "$CONFIG_PATH"
EOF

    chmod +x "$TARGET_SCRIPT"
    echo "Successfully created $TARGET_SCRIPT"
else
    echo "xray.sh already exists in $PARENT_DIR. Skipping creation."
fi

echo ""
echo "--- Setup Complete ---"
echo "To start the Xray gaming server:"
echo "bash ../../xray.sh"
echo ""
echo "To start the Hytale server:"
echo "curl -sL https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh | bash -s -- ID1 ID2 --p 5520"
