#!/bin/bash

echo "--- [Sing-Box Startup Script Inside PRoot] ---"

INSTALL_LOCK_FILE="/etc/sing-box/install_lock"

mkdir -p /etc/sing-box

if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists and installing dependencies..."
    apt-get update > /dev/null 2>&1
    apt-get install -y wget tmate bash curl nano python3-minimal > /dev/null 2>&1
    echo "Installing sing-box for the first time..."
    curl -fsSL https://sing-box.app/install.sh | sh
    
    echo "Installation complete. Creating lock file."
    touch "$INSTALL_LOCK_FILE"
else
    echo "Dependencies are already installed. Skipping installation."
fi

# --- START: Code to download and set up xrdp.sh (Runs every time) ---
echo "Downloading and setting up xrdp.sh..."
wget -O /root/xrdp.sh https://github.com/xXGAN2Xx/Proot-Nour/raw/refs/heads/main/xrdp.sh
chmod +x /root/xrdp.sh
echo "xrdp.sh downloaded and made executable."
# --- END: Code to download and set up xrdp.sh ---

echo "Creating/Updating sing-box configuration file..."

echo "--- Starting sing-box service... ---"
echo "vless://bf000d23-0752-40b4-affe-68f7707a9661@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=none&type=httpupgrade&host=playstation.net&path=%2Fnour#nour-vless"
echo "systemctl start sing-box"
# systemctl enable sing-box
# systemctl start sing-box
# systemctl kill sing-box
# sing-box run --config /etc/sing-box/config.json &
