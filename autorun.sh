#!/bin/bash

echo "--- [Sing-Box Startup Script Inside PRoot] ---"

INSTALL_LOCK_FILE="/etc/sing-box/install_lock"

mkdir -p /etc/sing-box

if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists and installing dependencies..."
    apt-get update > /dev/null 2>&1
    apt-get install -y curl openssl tmate python3-minimal > /dev/null 2>&1

    echo "Installing sing-box for the first time..."
    curl -fsSL https://sing-box.app/install.sh | sh
    
    echo "Installation complete. Creating lock file."
    touch "$INSTALL_LOCK_FILE"
else
    echo "Dependencies are already installed. Skipping installation."
fi

echo "sing-box will use port: ${SERVER_PORT}"

echo "Creating/Updating sing-box configuration file..."
cat << EOT > /etc/sing-box/config.json
{
  "log": {
    "disabled": false,
    "level": "trace",
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
          "uuid": "bf000d23-0752-40b4-affe-68f7707a9661",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/key.pem"
      },
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

if [ ! -f /etc/sing-box/cert.pem ] || [ ! -f /etc/sing-box/key.pem ]; then
    echo "Generating new self-signed TLS certificate..."
    openssl req -x509 -newkey rsa:4096 -keyout /etc/sing-box/key.pem \
    -out /etc/sing-box/cert.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=FakeOrg/OU=FakeUnit/CN=fake.local" \
    -addext "subjectAltName=DNS:playstation.net,DNS:localhost,IP:127.0.0.1"
else
    echo "Certificate and key already exist."
fi

echo "--- Starting sing-box service... ---"
echo "sing-box service has been started."
echo "vless://bf000d23-0752-40b4-affe-68f7707a9661@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&flow=xtls-rprx-vision&security=tls&sni=playstation.net&allowInsecure=1&type=tcp&headerType=none#nour-vless"
systemctl enable sing-box
systemctl start sing-box
# systemctl kill sing-box
# sing-box run --config /etc/sing-box/config.json &
