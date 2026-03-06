#!/bin/bash

# ==========================================
#        MASTER SETUP SCRIPT
# ==========================================

# 1. Determine the path for the parent directory (cd ..)
PARENT_DIR=$(cd .. && pwd)
TARGET_SCRIPT="${PARENT_DIR}/sing-box.sh"

# Lock file to track if dependencies are already installed
DEP_LOCK_FILE="/etc/os_deps_installed"

if[ ! -f "$DEP_LOCK_FILE" ]; then
    echo "--- [1] First Time Setup: Updating & Installing Dependencies ---"
    
    # Update and Install Prerequisites
    apt-get update -y
    apt-get install -y curl wget sed python3-minimal tmate dos2unix
    
    # Create the lock file
    touch "$DEP_LOCK_FILE"
    echo "Dependencies installed."
else
    echo "---[1] System Setup: Dependencies already installed. Skipping. ---"
fi

# ==========================================
#        SELF-UPDATE LOGIC (OS LEVEL)
# ==========================================
echo "--- [2] Checking for Script Updates ---"

SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

if command -v curl >/dev/null 2>&1; then
    # Download and strip Windows line endings (CRLF -> LF) to prevent syntax errors
    curl -fsSL "$SCRIPT_URL" | tr -d '\r' > /tmp/script_update_check
    
    if[ -s /tmp/script_update_check ]; then
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
echo "--- [3] Checking for sing-box.sh in $PARENT_DIR ---"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "Creating $TARGET_SCRIPT (in the parent directory)..."
    
    # We use 'EOF' to prevent variable expansion during file creation
    cat << 'EOF' > "$TARGET_SCRIPT"
#!/bin/bash

echo "--- [Sing-box VLESS Startup Script] ---"

CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
TEMP_CONFIG="/tmp/singbox_config_temp.json"

mkdir -p "$CONFIG_DIR"

# --- Sing-box Core Installation ---
echo "Checking/Installing sing-box..."
bash -c "$(curl -fsSL https://sing-box.app/install.sh)"

# --- Smart Config Generation ---
if [ -z "$SERVER_PORT" ]; then
    echo "ERROR: SERVER_PORT environment variable is not set!"
else
    # Create the template
    cat << 'JSON' > "$TEMP_CONFIG"
{
  "inbounds":[
    {
      "type": "vless",
      "listen": "0.0.0.0",
      "listen_port": ${SERVER_PORT},
      "users":[
        {
          "uuid": "a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"
        }
      ],
      "transport": {
        "type": "http",
        "host":[
          "playstation.net"
        ],
        "path": "/"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
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
fi

# --- Link Generation ---
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

# Fetch the server IP if not already set
if [ -z "$server_ip" ]; then
    server_ip=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
fi

VLESS_LINK="vless://${UUID}@${server_ip}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=http&host=playstation.net#Nour"

echo "=========================================================="
echo "Sing-box VLESS Link:"
echo "$VLESS_LINK"
echo "=========================================================="

echo "Starting Sing-box..."
sing-box run -c "$CONFIG_PATH"
EOF

    # Strip CRLF from the generated script just in case
    sed -i 's/\r$//' "$TARGET_SCRIPT" 2>/dev/null || true
    chmod +x "$TARGET_SCRIPT"
    echo "Successfully created $TARGET_SCRIPT"
else
    echo "sing-box.sh already exists in $PARENT_DIR. Skipping creation."
fi

echo "--- Setup Complete ---"
echo "to start the sing-box server type"
echo "bash ../../sing-box.sh"
echo "to start the hytale server type"
echo "curl -sL https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nourt.sh | bash -s -- ID1 ID2 --p 5520 "
# systemctl start sing-box
# systemctl kill sing-box
