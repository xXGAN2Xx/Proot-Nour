#!/bin/bash

echo "--- [Xray VLESS (TCP+HTTP Injection) Startup Script Inside PRoot] ---"

# --- CONFIGURATION ---
# 1. URLs
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
CONFIG_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/config.json"
XRDP_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/xrdp.sh"

# 2. Local Paths
# Standard Xray config path
CONFIG_DIR="/usr/local/etc/xray"
INSTALL_LOCK_FILE="${CONFIG_DIR}/install_lock"
CONFIG_PATH="${CONFIG_DIR}/config.json"
XRDP_PATH="/root/xrdp.sh"

# Ensure Public IP is detected
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl --silent -L checkip.pterodactyl-installer.se)
fi

# --- PREPARATION ---
mkdir -p "$CONFIG_DIR"

# --- STEP 1: Self-Update Check ---
if command -v curl >/dev/null 2>&1; then
    echo "Checking for script updates..."
    curl -fsSL "$SCRIPT_URL" -o /tmp/script_update_check
    
    if [ -s /tmp/script_update_check ]; then
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
            mv /tmp/script_update_check "$0"
            chmod +x "$0"
        fi
    else
        rm -f /tmp/script_update_check
    fi
fi

# --- STEP 2: Install Dependencies & Setup ---

# A. OS Dependencies (Only runs once to save time)
if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists..."
    apt-get update > /dev/null 2>&1
    
    echo "Installing OS dependencies..."
    apt-get install -y curl sed python3-minimal tmate > /dev/null 2>&1
    
    touch "$INSTALL_LOCK_FILE"
else
    echo "OS dependencies are already installed."
fi

# B. Xray-core Installation/Update (RUNS EVERY TIME)
echo "Checking for Xray-core updates and installing..."
# This command will update Xray if a new version is available, or reinstall it.
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# --- STEP 3: Download config.json and Configure ---
echo "Downloading latest config.json..."
curl -fsSL -o "$CONFIG_PATH" "$CONFIG_URL"

if [ -f "$CONFIG_PATH" ]; then
    # Configure PORT
    if [ -n "$SERVER_PORT" ]; then
        echo "Configuring port: Replacing \${SERVER_PORT} with $SERVER_PORT"
        sed -i "s/\${SERVER_PORT}/$SERVER_PORT/g" "$CONFIG_PATH"
    else
        echo "WARNING: SERVER_PORT variable is NOT set."
    fi
else
    echo "Error: Failed to download config.json"
fi

# --- STEP 4: Download xrdp.sh ---
echo "Downloading latest xrdp.sh..."
curl -fsSL -o "$XRDP_PATH" "$XRDP_URL"
chmod +x "$XRDP_PATH"

# --- STEP 5: Start Services ---
echo "--- Starting Xray (Gaming + Injection Mode)... ---"

# UUID from your config.json
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

# VLESS Link Generation (Updated for TCP + HTTP Header Injection)
VLESS_LINK="vless://${UUID}@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=http&host=playstation.net#Nour"
echo "=========================================================="
echo "Xray VLESS Link (Tcp + Http Injection)"
echo ""
echo "$VLESS_LINK"
echo "=========================================================="

# Start Xray
echo "to start Xray core type the next command in console"
echo "systemctl enable xray && systemctl start xray"
# xray run -c /usr/local/etc/xray/config.json
