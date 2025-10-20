#!/bin/bash

echo "--- [Sing-Box Startup Script Inside PRoot] ---"

INSTALL_LOCK_FILE="/etc/sing-box/install_lock"

mkdir -p /etc/sing-box

if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists and installing dependencies..."
    apt-get update > /dev/null 2>&1
    apt-get install -y curl tmate python3-minimal > /dev/null 2>&1

    echo "Installing sing-box for the first time..."
    curl -fsSL https://sing-box.app/install.sh | sh
    
    echo "Installation complete. Creating lock file."
    touch "$INSTALL_LOCK_FILE"
else
    echo "Dependencies are already installed. Skipping installation."
fi
echo "Creating/Updating sing-box configuration file..."
cat << EOT > /etc/sing-box/config.json
{
  "log": {
    "disabled": true,
    "level": "panic",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${SERVER_PORT},
      "tcp_fast_open": true,
      "users": [
        {
          "name": "nour",
          "uuid": "bf000d23-0752-40b4-affe-68f7707a9661"
        }
      ],
      "transport": {
        "type": "httpupgrade",
        "path": "/nour"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ],
  "route": {}
}
EOT

echo "--- Starting sing-box service... ---"
echo "sing-box service has been started."
echo "vless://bf000d23-0752-40b4-affe-68f7707a9661@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=none&type=httpupgrade&host=playstation.net&path=%2Fnour#nour-vless"
echo "systemctl start sing-box"
# systemctl enable sing-box
# systemctl start sing-box
# systemctl kill sing-box
# sing-box run --config /etc/sing-box/config.json &
