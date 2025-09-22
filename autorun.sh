#!/bin/bash
# Shebang: Specifies that this script should be run with the Bash interpreter.

# --- Script Introduction ---
# This script is designed to run inside a PRoot environment to automate the
# installation, configuration, and startup of the sing-box service. It handles
# one-time setup and ensures the service is correctly configured and running
# every time the script is executed.
echo "--- [Sing-Box Startup Script Inside PRoot] ---"

# --- Variable Definitions ---
# Define a path for a "lock file". This empty file acts as a flag to indicate
# that the initial, one-time installation steps have already been completed.
INSTALL_LOCK_FILE="/etc/sing-box/install_lock"

# --- Directory Setup ---
# Create the directory where sing-box configurations and certificates will be stored.
# The "-p" flag ensures that the command doesn't fail if the directory (or its
# parent directories) already exists.
mkdir -p /etc/sing-box

# --- One-Time Installation Steps ---
# Check if the lock file does NOT exist. This 'if' block will only run once.
if [ ! -f "$INSTALL_LOCK_FILE" ]; then
    echo "First time setup: Updating package lists and installing dependencies..."
    
    # Update the local package repository lists.
    # The output is redirected to /dev/null to keep the console clean and show only our messages.
    apt-get update > /dev/null 2>&1
    
    # Install essential tools: curl (for downloads), openssl (for certificates),
    # tmate (for remote terminal access), and python3.
    # The "-y" flag automatically answers "yes" to any installation prompts.
    apt-get install -y curl openssl tmate python3-minimal > /dev/null 2>&1

    echo "Installing sing-box for the first time..."
    # Download the official sing-box installation script and execute it immediately.
    # The script is piped directly into the 'sh' shell interpreter.
    curl -fsSL https://sing-box.app/install.sh | sh
    
    echo "Installation complete. Creating lock file to prevent re-installation."
    # Create the empty lock file. On the next run, the 'if' condition at the start
    # of this block will be false, and these installation steps will be skipped.
    touch "$INSTALL_LOCK_FILE"
else
    # This message is shown on every subsequent run after the first setup.
    echo "Dependencies are already installed. Skipping installation."
fi

# --- Always-Run Configuration and Startup Steps ---

# Inform the user which port sing-box will be configured to use.
# This relies on an environment variable ${SERVER_PORT} being set before running the script.
echo "sing-box will use port: ${SERVER_PORT}"

echo "Creating/Updating sing-box configuration file..."
# Use a "here document" (cat << EOT) to write a multi-line configuration file.
# This file is overwritten every time the script runs, ensuring any changes
# to the script's configuration are applied immediately.
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

# --- TLS Certificate Generation ---
# Check if a TLS certificate OR a private key does not exist.
# This block will only run if the necessary files are missing.
if [ ! -f /etc/sing-box/cert.pem ] || [ ! -f /etc/sing-box/key.pem ]; then
    echo "Generating new self-signed TLS certificate..."
    # Use OpenSSL to generate a new self-signed certificate and private key.
    # -x509:         Create a self-signed certificate.
    # -newkey rsa:4096: Generate a new 4096-bit RSA private key.
    # -keyout/-out:  Specify the output files for the key and certificate.
    # -days 365:     Set the certificate's validity period to one year.
    # -nodes:        "No DES", meaning don't encrypt the private key (no passphrase).
    # -subj:         Provide subject information non-interactively.
    # -addext:       Add Subject Alternative Names (SANs) for modern TLS compatibility.
    openssl req -x509 -newkey rsa:4096 -keyout /etc/sing-box/key.pem \
    -out /etc/sing-box/cert.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=FakeOrg/OU=FakeUnit/CN=fake.local" \
    -addext "subjectAltName=DNS:playstation.net,DNS:localhost,IP:127.0.0.1"
else
    echo "Certificate and key already exist. Skipping generation."
fi

# --- Service Startup ---
echo "--- Starting sing-box service... ---"

# Display the full VLESS connection URL for the user to easily copy.
# It uses environment variables ($PUBLIC_IP, $SERVER_PORT) to construct the final URL.
echo "vless://bf000d23-0752-40b4-affe-68f7707a9661@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=tls&sni=playstation.net&alpn=h3&allowInsecure=1&type=tcp&headerType=none#nour-vless"

# Use systemd to manage the sing-box service.
# 'enable' ensures the service starts automatically on system boot.
systemctl enable sing-box
# 'start' runs the service immediately.
systemctl start sing-box

echo "sing-box service has been started."

# --- Fallback Option (for non-systemd environments) ---
# The commands below are a manual way to run sing-box. They are commented out
# but can be used if systemd is not available in the PRoot environment.
#
# First, kill any existing sing-box processes to avoid conflicts.
# killall sing-box > /dev/null 2>&1
#
# Run sing-box in the background (&) using the configuration file we just created.
# sing-box run --config /etc/sing-box/config.json &
