#!/bin/bash

echo "--- [Hysteria 2 Startup Script Inside PRoot] ---"

# --- CONFIGURATION ---
# 1. URL for this script (Required for self-update check)
SCRIPT_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"

# 2. URLs for resources
CONFIG_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/hysteria-config.yaml"
XRDP_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/xrdp.sh"

# 3. Local Paths
INSTALL_LOCK_FILE="/etc/hysteria/install_lock"
CONFIG_PATH="/etc/hysteria/config.yaml"
XRDP_PATH="/root/xrdp.sh"

# Certificate Paths
CERT_FILE="/etc/hysteria/cert.pem"
KEY_FILE="/etc/hysteria/private.key"

# --- PREPARATION ---
# Ensure the directory for config exists
mkdir -p /etc/hysteria

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
    apt-get install -y wget tmate bash curl nano sed openssl > /dev/null 2>&1
    
    echo "Installing Hysteria 2..."
    bash <(curl -fsSL https://get.hy2.sh/)
    
    # --- GENERATE FAKE CERTIFICATE ---
    echo "Generating fake SSL certificate..."
    # This creates a self-signed certificate valid for 3650 days (10 years)
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/CN=playstation.net" \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -addext "subjectAltName=DNS:playstation.net,DNS:*.playstation.net" \
        > /dev/null 2>&1

    chmod 644 "$CERT_FILE" "$KEY_FILE"
    echo "Certificate generated at: $CERT_FILE"
    echo "Private Key generated at: $KEY_FILE"
    # ---------------------------------

    echo "Installation complete. Creating lock file."
    touch "$INSTALL_LOCK_FILE"
else
    echo "Dependencies are already installed."
    
    # Check if certs exist, if not (deleted accidentally), regenerate them
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
         echo "Certificates missing. Regenerating..."
         apt-get install -y openssl > /dev/null 2>&1
         openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
            -subj "/CN=playstation.net" \
            -keyout "$KEY_FILE" \
            -out "$CERT_FILE" \
            -addext "subjectAltName=DNS:playstation.net,DNS:*.playstation.net" \
            > /dev/null 2>&1
         chmod 644 "$CERT_FILE" "$KEY_FILE"
         echo "Certificates regenerated."
    fi
fi

# --- STEP 3: Download config.yaml and Configure Port ---
echo "Downloading latest config.yaml..."
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
    echo "Error: Failed to download config.yaml"
fi

# --- STEP 4: Download xrdp.sh ---
echo "Downloading latest xrdp.sh..."
curl -fsSL -o "$XRDP_PATH" "$XRDP_URL"
chmod +x "$XRDP_PATH"
echo "xrdp.sh downloaded and made executable."

# --- STEP 5: Start Services ---
echo "--- Starting Hysteria 2 service... ---"
# Note: Ensure PUBLIC_IP and SERVER_PORT are set in the environment before running this script

# Generate Hysteria 2 connection URL
# Format: hysteria2://[password]@[server]:[port]/?insecure=1&sni=playstation.net#[name]
# You need to set a password in your config.yaml
echo "hy2://your_password@${PUBLIC_IP}:${SERVER_PORT}/?insecure=1&sni=playstation.net#nour-hysteria2"

echo "Starting Hysteria 2 server..."
# Run Hysteria 2 server with config
hysteria server --config "$CONFIG_PATH" &

# Alternative: Use systemd if available
# systemctl enable hysteria-server
# systemctl start hysteria-server
# systemctl restart hysteria-server
# systemctl stop hysteria-server
