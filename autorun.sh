#!/bin/bash

echo "--- [Sing-box Startup Script Inside PRoot] ---"

# --- CONFIGURATION ---
# 1. URL for this script (Required for self-update check)
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

# 2. URLs for resources
CONFIG_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/config.json"
XRDP_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/xrdp.sh"

# 3. Local Paths
CONFIG_DIR="/etc/sing-box"
INSTALL_LOCK_FILE="${CONFIG_DIR}/install_lock"
CONFIG_PATH="${CONFIG_DIR}/config.json"
XRDP_PATH="/root/xrdp.sh"

# Certificate paths
CERT_FILE="${CONFIG_DIR}/cert.pem"
KEY_FILE="${CONFIG_DIR}/key.pem"

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

# --- STEP 2: Install Dependencies & Setup (First Run Only) ---
if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists..."
    apt-get update > /dev/null 2>&1
    
    echo "Installing dependencies (curl, openssl, etc)..."
    apt-get install -y curl openssl ca-certificates sed python3-minimal tmate > /dev/null 2>&1

    # --- INSTALL SING-BOX (Official Script) ---
    echo "Installing Sing-box using official script..."
    curl -fsSL https://sing-box.app/install.sh | sh
    echo "Sing-box installation finished."
    # ------------------------------------------

    # --- GENERATE FREAK SSL CERTIFICATE ---
    echo "Generating self-signed SSL certificate..."
    openssl ecparam -name prime256v1 -out /tmp/ecparam.pem
    openssl req -x509 -nodes -newkey ec:/tmp/ecparam.pem \
      -keyout "$KEY_FILE" \
      -out "$CERT_FILE" \
      -subj "/CN=playstation.net" \
      -days 36500
    rm -f /tmp/ecparam.pem
    
    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"
    # --------------------------------------

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
        chmod 644 "$CERT_FILE"
        chmod 600 "$KEY_FILE"
        echo "Certificates regenerated."
    fi
fi

# --- STEP 3: Download config.json and Configure Port ---
echo "Downloading latest config.json..."
curl -fsSL -o "$CONFIG_PATH" "$CONFIG_URL"

if [ -f "$CONFIG_PATH" ]; then
    echo "Config downloaded successfully."
    
    # Check if SERVER_PORT variable exists
    if [ -n "$SERVER_PORT" ]; then
        echo "Configuring port: Replacing \${SERVER_PORT} with $SERVER_PORT"
        sed -i "s/\${SERVER_PORT}/$SERVER_PORT/g" "$CONFIG_PATH"
    else
        echo "WARNING: SERVER_PORT environment variable is NOT set."
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
echo "--- Starting Sing-box service... ---"

# Generate Client Link for display
HY2_LINK="hysteria2://123456@${PUBLIC_IP}:${SERVER_PORT}?peer=playstation.net&insecure=1&mport=${SERVER_PORT}#Nour"

echo "=========================================================="
echo " Sing-box Hysteria2 Link:"
echo " $HY2_LINK"
echo "=========================================================="

# Start Sing-box in background
echo "systemctl enable sing-box && systemctl start sing-box"
# sing-box run -c /etc/sing-box/config.json
