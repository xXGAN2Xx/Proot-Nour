#!/bin/bash

echo "--- [Xray Startup Script Inside PRoot] ---"

# --- CONFIGURATION ---
# 1. URL for this script (Required for self-update check)
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

# 2. URLs for resources
CONFIG_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/config.json"
XRDP_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/xrdp.sh"

# 3. Local Paths
INSTALL_LOCK_FILE="/usr/local/etc/xray/install_lock"
CONFIG_PATH="/usr/local/etc/xray/config.json"
XRDP_PATH="/root/xrdp.sh"
CERT_FILE="/usr/local/etc/xray/cert.crt"
KEY_FILE="/usr/local/etc/xray/key.key"

# --- PREPARATION ---
# Ensure the directory for config exists
mkdir -p /usr/local/etc/xray

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

# --- STEP 2: Install Dependencies & Setup (First Run Only) ---
if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists..."
    apt-get update > /dev/null 2>&1
    
    # ADDED 'openssl' here for certificate generation
    echo "Installing dependencies (curl, openssl, etc)..."
    apt-get install -y wget tmate bash curl nano python3 diffutils sed openssl > /dev/null 2>&1
    
    echo "Installing Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    # --- GENERATE FAKE CERTIFICATE ---
    echo "Generating fake SSL certificate..."
    # Generate EC parameters first, then use them
    openssl ecparam -name prime256v1 -out /tmp/ecparam.pem
    openssl req -x509 -nodes -newkey ec:/tmp/ecparam.pem \
      -keyout "$KEY_FILE" \
      -out "$CERT_FILE" \
      -subj "/CN=playstation.net" \
      -days 36500
    rm -f /tmp/ecparam.pem

    chmod +x "$CERT_FILE" "$KEY_FILE"
    # ---------------------------------

    echo "Installation complete. Creating lock file."
    touch "$INSTALL_LOCK_FILE"
else
    echo "Dependencies are already installed."
    
    # Check if certs exist, if not (deleted accidentally), regenerate them
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        echo "Certificates missing. Regenerating..."
        openssl ecparam -name prime256v1 -out /tmp/ecparam.pem
        openssl req -x509 -nodes -newkey ec:/tmp/ecparam.pem \
          -keyout "$KEY_FILE" \
          -out "$CERT_FILE" \
          -subj "/CN=playstation.net" \
          -days 36500
        rm -f /tmp/ecparam.pem
        chmod +x "$CERT_FILE" "$KEY_FILE"
        echo "Certificates regenerated."
    fi
fi

# --- STEP 3: Download config.json and Configure Port ---
echo "Downloading latest config.json..."
curl -fsSL -o "$CONFIG_PATH" "$CONFIG_URL"

if [ -f "$CONFIG_PATH" ]; then
    echo "Config downloaded successfully to: $CONFIG_PATH"
    
    # Check if SERVER_PORT variable exists
    if [ -n "$SERVER_PORT" ]; then
        echo "Configuring port: Replacing \${SERVER_PORT} with $SERVER_PORT"
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
echo "--- Starting Xray service... ---"
# Note: Ensure PUBLIC_IP and SERVER_PORT are set in the environment before running this script
echo "vless://a4af6a92-4dba-4cd1-841d-8ac7b38f9d6e@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=tls&sni=playstation.net&insecure=1&allowInsecure=1&type=tcp&headerType=none#Nour"
# Start Xray with the configuration
# xray run -config /usr/local/etc/xray/config.json
# xray run -config "$CONFIG_PATH" &
# systemctl enable xray
# systemctl start xray
