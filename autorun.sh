#!/bin/bash

echo "--- [Sing-box VLESS (Gaming) Startup Script Inside PRoot] ---"

# --- CONFIGURATION ---
# 1. URLs
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
CONFIG_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/config.json"
XRDP_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/xrdp.sh"

# 2. Local Paths
CONFIG_DIR="/etc/sing-box"
INSTALL_LOCK_FILE="${CONFIG_DIR}/install_lock"
CONFIG_PATH="${CONFIG_DIR}/config.json"
XRDP_PATH="/root/xrdp.sh"

# Certificate paths
CERT_FILE="${CONFIG_DIR}/cert.pem"
KEY_FILE="${CONFIG_DIR}/key.pem"

# Ensure Public IP is detected
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s https://api.ipify.org)
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

# --- STEP 2: Install Dependencies & Setup (First Run Only) ---
if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists..."
    apt-get update > /dev/null 2>&1
    
    echo "Installing dependencies..."
    apt-get install -y curl openssl ca-certificates sed python3-minimal tmate > /dev/null 2>&1

    echo "Installing Sing-box..."
    curl -fsSL https://sing-box.app/install.sh | sh
    
    # --- GENERATE SSL CERTIFICATE ---
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
    
    echo "Setup complete. Creating lock file."
    touch "$INSTALL_LOCK_FILE"
else
    echo "Dependencies are installed."
    # Regenerate certs if missing
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
    fi
fi

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
echo "--- Starting Sing-box (Gaming Mode)... ---"

# VLESS Link Generation (Gaming optimized tag)
VLESS_LINK="vless://ca9a6ff3-c5fa-3eb9-b7c8-2b6bf9252f14@${PUBLIC_IP}:${SERVER_PORT}?security=tls&sni=roblox.com&allowInsecure=1&type=tcp&encryption=none#Nour"
echo "=========================================================="
echo " Sing-box VLESS Link (Tcp+Tls)"
echo " Hash marked as #Nour for client optimization"
echo ""
echo " $VLESS_LINK"
echo "=========================================================="

# Start Sing-box
echo "systemctl enable sing-box && systemctl start sing-box"
# sing-box run -c /etc/sing-box/config.json
