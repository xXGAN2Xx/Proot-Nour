#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

# 1. Determine the path for the parent directory (cd ..)
PARENT_DIR=$(cd .. && pwd)
TARGET_SCRIPT="${PARENT_DIR}/singbox.sh"

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"

if [ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    
    # Update and Install Prerequisites
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate
    
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
#        SING-BOX SCRIPT GENERATION
# ==========================================
echo "--- [3] Checking for singbox.sh in $PARENT_DIR ---"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "Creating $TARGET_SCRIPT (in the parent directory)..."
    
    # We use 'EOF' to prevent variable expansion during file creation
    cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash

echo "--- [sing-box VLESS Startup Script] ---"

CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
TEMP_CONFIG="/tmp/singbox_config_temp.json"

mkdir -p "$CONFIG_DIR"

# --- sing-box Installation ---
echo "Checking/Installing sing-box..."
curl -fsSL https://sing-box.app/install.sh | sh
echo "sing-box installed: $(sing-box version | head -1)"

# --- Smart Config Generation ---
if [ -z "$SERVER_PORT" ]; then
    echo "ERROR: SERVER_PORT environment variable is not set!"
    exit 1
fi

# Get the server IP if not already set
if [ -z "$server_ip" ]; then
    server_ip=$(curl -fsSL https://api.ipify.org 2>/dev/null || \
                curl -fsSL https://ifconfig.me 2>/dev/null || \
                hostname -I | awk '{print $1}')
fi

UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

# Create the sing-box config with VLESS + HTTP transport
cat > "$TEMP_CONFIG" << JSON
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${SERVER_PORT},
      "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "http",
        "host": ["playstation.net"],
        "path": "/"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
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

# --- Link Generation ---
VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=http&host=playstation.net&path=%2F#Nour"

echo "=========================================================="
echo "sing-box VLESS Link:"
echo "$VLESS_LINK"
echo "=========================================================="

echo "Starting sing-box..."
exec sing-box run -c "$CONFIG_PATH"
EOF

    chmod +x "$TARGET_SCRIPT"
    echo "Successfully created $TARGET_SCRIPT"
else
    echo "singbox.sh already exists in $PARENT_DIR. Skipping creation."
fi

echo "--- Setup Complete ---"
echo "to start the sing-box server type:"
echo "bash ../../singbox.sh"
echo "to start the hytale server type:"
echo "curl -sL https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh | bash -s -- ID1 ID2 --p 5520"
