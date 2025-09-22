#!/bin/bash

echo "--- [Sing-Box Startup Script Inside PRoot] ---"

echo "Updating package lists and installing dependencies ..."
# Ensure python3 is installed for the systemctl replacement, even though we bypass it for starting
apt-get update > /dev/null 2>&1
apt-get install -y curl openssl tmate screen python3 > /dev/null 2>&1

if ! command -v sing-box &> /dev/null; then
    echo "Installing sing-box for the first time..."
    # The installer will likely try to interact with systemd and fail, which is okay.
    # We only need it to place the binary in /usr/local/bin/
    curl -fsSL https://sing-box.app/install.sh | sh
else
    echo "sing-box is already installed."
fi

SERVER_PORT=${SERVER_PORT}
echo "sing-box will use port: $SERVER_PORT"

mkdir -p /etc/sing-box

echo "Creating/Updating sing-box configuration file..."
cat << EOT > /etc/sing-box/config.json
{
  "log": {
    "disabled": true,
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
          "uuid": "bf000d23-0752-40b4-affe-68f7707a9661"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/key.pem"
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
echo "vless://bf000d23-0752-40b4-affe-68f7707a9661@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=tls&sni=playstation.net&alpn=h3&allowInsecure=1&type=tcp&headerType=none#nour-vless"
systemctl enable sing-box
systemctl start sing-box
#sing-box run --config /etc/sing-box/config.json &
echo "sing-box started in the background."
