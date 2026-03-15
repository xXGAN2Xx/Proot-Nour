#!/bin/bash

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

echo "--- [2] Checking for Script Updates ---"

SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
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

echo "--- [3] Writing xray.sh to $PARENT_DIR ---"

cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash

echo "--- [Xray Gaming Server] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"

mkdir -p "$CONFIG_DIR"

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

if [ -z "$SERVER_PORT" ]; then
    read -p "Enter server port: " SERVER_PORT
    if [ -z "$SERVER_PORT" ]; then
        echo "ERROR: No port provided."
        exit 1
    fi
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

sysctl -w net.ipv4.tcp_fastopen=3             2>/dev/null
sysctl -w net.ipv4.tcp_low_latency=1          2>/dev/null
sysctl -w net.core.rmem_max=16777216          2>/dev/null
sysctl -w net.core.wmem_max=16777216          2>/dev/null
sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null

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

VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=kcp&headerType=none#Nour-Gaming"

echo "=========================================================="
echo " $VLESS_LINK"
echo " Port : $SERVER_PORT"
echo " UUID : $UUID"
echo "=========================================================="

nice -n -10 taskset -c 0 xray run -c "$CONFIG_PATH"
EOF

chmod +x "$TARGET_SCRIPT"
echo "xray.sh written to $TARGET_SCRIPT"

echo ""
echo "--- Setup Complete ---"
echo "To start the Xray gaming server:"
echo "bash ../xray.sh"
echo ""
echo "To start the Hytale server:"
echo "curl -sL https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh | bash -s -- ID1 ID2 --p 5520"
