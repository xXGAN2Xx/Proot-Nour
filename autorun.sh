#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    
    # 1. Update and Install Prerequisites
    apt-get update -y
    apt-get install -y curl sed python3-minimal tmate unzip ca-certificates openssl
    
    # Create the lock file so this block doesn't run again
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed and lock file created."
else
    echo "--- [1] System Setup: Dependencies already installed. Skipping. ---"
fi

# ==========================================
#        SELF-UPDATE LOGIC (OS LEVEL)
# ==========================================
echo "--- [2] Checking for Script Updates ---"

# URL of THIS Master Script
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

# We check if curl exists (just in case the lock file exists but curl was removed)
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o /tmp/script_update_check
    
    if [ -s /tmp/script_update_check ]; then
        # Check if the downloaded file is different from the current running script
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
    else
        rm -f /tmp/script_update_check
    fi
fi

# ==========================================
#        XRAY SCRIPT GENERATION
# ==========================================
# Explicitly using ./xray.sh to ensure it is in the current directory
TARGET_SCRIPT="./xray.sh"

echo "--- [3] Checking for $TARGET_SCRIPT ---"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "$TARGET_SCRIPT not found. Creating it in current directory..."
    
    # Start of Heredoc - This writes the content into ./xray.sh
    cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash

echo "--- [Xray VLESS (TCP+HTTP Injection) Startup Script] ---"

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_PATH="${CONFIG_DIR}/config.json"
TEMP_CONFIG="/tmp/xray_config_temp.json"

mkdir -p "$CONFIG_DIR"

# --- Xray Core Installation ---
echo "Checking for Xray-core updates and installing..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata

# --- Config Generation Logic ---
if [ -z "$SERVER_PORT" ]; then
    echo "WARNING: SERVER_PORT variable is NOT set. Config generation may fail."
else
    # 1. Write the template to a temporary file first
    # We use 'JSON' (quoted) to keep ${SERVER_PORT} literal for now
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

    # 2. Perform the port substitution on the TEMP file
    sed -i "s/\${SERVER_PORT}/$SERVER_PORT/g" "$TEMP_CONFIG"

    # 3. Compare Temp file with Actual Config
    # If config.json doesn't exist OR if the content is different
    if [ ! -f "$CONFIG_PATH" ] || ! cmp -s "$TEMP_CONFIG" "$CONFIG_PATH"; then
        echo "Config changed or missing. Updating config.json..."
        mv "$TEMP_CONFIG" "$CONFIG_PATH"
    else
        echo "Config is up to date. No changes made."
        rm -f "$TEMP_CONFIG"
    fi
fi

echo "--- Starting Xray (Gaming + Injection Mode)... ---"

# --- Link Generation ---
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"
# Note: server_ip must be defined in the environment or it will be blank
VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=http&host=playstation.net#Nour"

echo "=========================================================="
echo "Xray VLESS Link (Tcp + Http Injection)"
echo "$VLESS_LINK"
echo "=========================================================="

echo "To start Xray core manually, type:"
echo "xray run -c /usr/local/etc/xray/config.json"

# Auto-start Xray
xray run -c /usr/local/etc/xray/config.json
EOF
    # End of Heredoc

    chmod +x "$TARGET_SCRIPT"
    echo "$TARGET_SCRIPT created successfully."
else
    echo "$TARGET_SCRIPT already exists. Skipping creation."
fi

echo "--- Setup Complete. ---"
# systemctl start xray
# systemctl kill xray
