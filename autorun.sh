#!/bin/bash

echo "--- [Sing-box VLESS (TCP+HTTP Injection) Startup Script Inside PRoot] ---"

# --- CONFIGURATION ---
# 1. URLs
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
CONFIG_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/config.json"
XRDP_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/xrdp.sh"

# 2. Local Paths
# CONFIG_DIR and CONFIG_PATH variables removed
INSTALL_LOCK_FILE="/usr/local/etc/sing-box/install_lock"
XRDP_PATH="/root/xrdp.sh"

# Ensure Public IP is detected
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl --silent -L checkip.pterodactyl-installer.se)
fi

# --- PREPARATION ---
mkdir -p "/usr/local/etc/sing-box"

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
    apt-get install -y curl sed python3-minimal tmate ca-certificates > /dev/null 2>&1
    
    touch "$INSTALL_LOCK_FILE"
else
    echo "OS dependencies are already installed."
fi

# B. Sing-box Installation/Update (RUNS EVERY TIME)
echo "Checking for Sing-box updates and installing..."
curl -fsSL https://sing-box.app/install.sh | sh

# --- STEP 3: Download config.json and Configure ---
echo "Downloading latest config.json..."
curl -fsSL -o "/usr/local/etc/sing-box/config.json" "$CONFIG_URL"

if [ -f "/usr/local/etc/sing-box/config.json" ]; then
    # Configure PORT
    if [ -n "$SERVER_PORT" ]; then
        echo "Configuring port: Replacing \${SERVER_PORT} with $SERVER_PORT"
        sed -i "s/\${SERVER_PORT}/$SERVER_PORT/g" "/usr/local/etc/sing-box/config.json"
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
echo "--- Starting Sing-box (Gaming + Injection Mode)... ---"

# UUID from your config.json
UUID="a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e"

# VLESS Link Generation
VLESS_LINK="vless://${UUID}@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=none&type=tcp&headerType=http&host=playstation.net#Nour"
echo "=========================================================="
echo "Sing-box VLESS Link (Tcp + Http Injection)"
echo "$VLESS_LINK"
echo "=========================================================="

# Start Sing-box
echo "to start Sing-box core type the next command in console"
echo "sing-box run -c /usr/local/etc/sing-box/config.json"
# systemctl enable sing-box && systemctl start sing-box
# systemctl stop sing-box && systemctl kill sing-box
