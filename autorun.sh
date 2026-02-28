#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

# 1. Determine the path for the parent directory (cd ..)
PARENT_DIR=$(cd .. && pwd)
TARGET_SCRIPT="${PARENT_DIR}/xray.sh"

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    
    # Update and Install Prerequisites
    apt-get update -y
    apt-get install -y curl sed python3-minimal tmate unzip ca-certificates openssl
    
    # Create the lock file
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed."
else
    echo "--- [1] System Setup: Dependencies already installed. Skipping. ---"
fi

# ==========================================
#        SELF-UPDATE LOGIC (OS LEVEL)
# ==========================================
echo "--- [2] Checking for Script Updates ---"

SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o /tmp/script_update_check
    
    if [ -s /tmp/script_update_check ]; then
        if ! cmp -s "$0" /tmp/script_update_check; then
            echo "New version found! Updating Master Script..."
            mv /tmp/script_update_check "$0"
            chmod +x "$0"
            echo "Restarting script..."
            exec "$0" "$@"
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
    
    # We use 'EOF' to prevent variable expansion during file creation
    cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash

echo "--- [Xray VLESS Startup Script] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"
TEMP_CONFIG="/tmp/xray_config_temp.json"

mkdir -p "$CONFIG_DIR"

# --- Xray Core Installation ---
echo "Checking/Installing Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

# --- Smart Config Generation ---
if [ -z "$SERVER_PORT" ]; then
    echo "ERROR: SERVER_PORT environment variable is not set!"
else
    # Create the template
    cat << 'JSON' > "$TEMP_CONFIG"
{
  "inbounds": [{
    "port": ${SERVER_PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e" }],
      "decryption": "none"
    },
    "streamSettings": {
      "tcpSettings": { "header": { "type": "http" } }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
JSON

    # Apply the port substitution
    sed -i "s/\${SERVER_PORT}/$SERVER_PORT/g" "$TEMP_CONFIG"

    # Only overwrite if the file is different or missing
    if [ ! -f "$CONFIG_PATH" ] || ! cmp -s "$TEMP_CONFIG" "$CONFIG_PATH"; then
        echo "Updating config.json..."
        mv "$TEMP_CONFIG" "$CONFIG_PATH"
    else
        echo "Config unchanged. Skipping write."
        rm -f "$TEMP_CONFIG"
    fi
fi

# --- Link Generation ---
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"
VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=http&host=playstation.net#Nour"

echo "=========================================================="
echo "Xray VLESS Link:"
echo "$VLESS_LINK"
echo "=========================================================="

echo "Starting Xray..."
xray run -c "$CONFIG_PATH"
EOF

    chmod +x "$TARGET_SCRIPT"
    echo "Successfully created $TARGET_SCRIPT"
else
    echo "xray.sh already exists in $PARENT_DIR. Skipping creation."
fi

echo "--- Setup Complete ---"
echo "to start the xray server type"
echo "bash ../../xray.sh"
# systemctl start xray
# systemctl kill xray
