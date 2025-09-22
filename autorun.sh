#!/bin/bash

echo "--- [Sing-Box Startup Script Inside PRoot] ---"

# Define a lock file to check if the initial setup has been completed.
INSTALL_LOCK_FILE="/etc/sing-box/install_lock"

# Create the directory for sing-box configuration and the lock file.
# The "-p" flag ensures that no error is thrown if the directory already exists.
mkdir -p /etc/sing-box

# --- One-Time Installation Steps ---
if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists and installing dependencies..."
    # Update package lists and install necessary tools quietly.
    apt-get update > /dev/null 2>&1
    apt-get install -y curl openssl tmate python3-minimal > /dev/null 2>&1

    echo "Installing sing-box for the first time..."
    # Download and execute the official sing-box installation script.
    curl -fsSL https://sing-box.app/install.sh | sh
    
    echo "Installation complete. Creating lock file."
    # Create the lock file to prevent this installation block from running again.
    touch "$INSTALL_LOCK_FILE"
else
    echo "Dependencies are already installed. Skipping installation."
fi

# --- Always-Run Configuration and Startup Steps ---

echo "sing-box will use port: ${SERVER_PORT}"

echo "Creating/Updating sing-box configuration file..."
# This configuration is written every time the script runs, ensuring it's always up-to-date.
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

# Check if a TLS certificate and key already exist. If not, generate them.
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

# Display the connection string for the user.
echo "vless://bf000d23-0752-40b4-affe-68f7707a9661@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=tls&sni=playstation.net&alpn=h3&allowInsecure=1&type=tcp&headerType=none#nour-vless"

# Enable the service to start on boot and start it now.
systemctl enable sing-box
systemctl start sing-box

echo "sing-box service has been started."
# If systemctl is not available, you can use the direct command commented out below:
# killall sing-box > /dev/null 2>&1 # Ensure no other instances are running
# sing-box run --config /etc/sing-box/config.json &
