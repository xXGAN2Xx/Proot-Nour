#!/bin/bash

echo "--- [Sing-Box Startup Script Inside PRoot] ---"

# --- CONFIGURATION ---
# 1. URL for this script (Required for self-update check)
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/startup.sh"

# 2. URLs for resources
CONFIG_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/config.json"
XRDP_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/xrdp.sh"

# 3. Local Paths
INSTALL_LOCK_FILE="/etc/sing-box/install_lock"
CONFIG_PATH="/etc/sing-box/config.json"
XRDP_PATH="/root/xrdp.sh"

# --- PREPARATION ---
# Ensure the directory for config exists
mkdir -p /etc/sing-box

# --- STEP 1: Self-Update Check ---
# This checks if the script on GitHub is newer than this running script
if command -v curl >/dev/null 2>&1; then
    echo "Checking for script updates..."
    curl -fsSL "$SCRIPT_URL" -o /tmp/script_update_check
    
    # If download succeeded and file is not empty
    if [ -s /tmp/script_update_check ]; then
        # Compare current script ($0) with downloaded script
        if command -v cmp >/dev/null 2>&1; then
            if ! cmp -s "$0" /tmp/script_update_check; then
                echo "New version found! Updating script..."
                mv /tmp/script_update_check "$0"
                chmod +x "$0"
                echo "Restarting script..."
                exec "$0" "$@"
                exit 0
            else
                echo "Script is up to date."
                rm -f /tmp/script_update_check
            fi
        else
            # Fallback if 'cmp' isn't installed yet
            mv /tmp/script_update_check "$0"
            chmod +x "$0"
        fi
    else
        rm -f /tmp/script_update_check
    fi
fi

# --- STEP 2: Install Dependencies (First Run Only) ---
if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists..."
    apt-get update > /dev/null 2>&1
    # Added 'sed' to the list of packages to ensure the replacement in Step 3 works
    apt-get install -y wget tmate bash curl nano python3-minimal diffutils sed > /dev/null 2>&1
    
    echo "Installing sing-box..."
    curl -fsSL https://sing-box.app/install.sh | sh
    
    echo "Installation complete. Creating lock file."
    touch "$INSTALL_LOCK_FILE"
else
    echo "Dependencies are already installed."
fi

# --- STEP 3: Download config.json and Configure Port ---
echo "Downloading latest config.json..."
curl -fsSL -o "$CONFIG_PATH" "$CONFIG_URL"

if [ -f "$CONFIG_PATH" ]; then
    echo "Config downloaded successfully to: $CONFIG_PATH"
    
    # Check if SERVER_PORT variable exists
    if [ -n "$SERVER_PORT" ]; then
        echo "Configuring port: Replacing \${SERVER_PORT} with $SERVER_PORT"
        # Use sed to replace the literal text "${SERVER_PORT}" with the value of the variable
        sed -i "s/\${SERVER_PORT}/$SERVER_PORT/g" "$CONFIG_PATH"
    else
        echo "WARNING: SERVER_PORT environment variable is NOT set. Config file was not modified."
    fi
else
    echo "Error: Failed to download config.json"
fi

# --- STEP 4: Download xrdp.sh ---
echo "Downloading latest xrdp.sh..."
curl -fsSL -o "$XRDP_PATH" "$XRDP_URL"
chmod +x "$XRDP_PATH"
echo "xrdp.sh downloaded and made executable."

# --- STEP 5: Start Services ---
echo "--- Starting sing-box service... ---"
# Note: Ensure PUBLIC_IP and SERVER_PORT are set in the environment before running this script
echo "vless://bf000d23-0752-40b4-affe-68f7707a9661@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=none&type=httpupgrade&host=playstation.net&path=%2Fnour#nour-vless"

echo "systemctl start sing-box"
# systemctl enable sing-box
# systemctl start sing-box
# systemctl kill sing-box
# sing-box run --config /etc/sing-box/config.json &
