#!/bin/bash

# --- Configuration ---
# Use the SERVER_PORT environment variable, or fall back to 14212 if not set.
XRDP_PORT="${SERVER_PORT}"
RDP_USER="nour"         # Default RDP user
DEFAULT_PASSWORD="123456" # Default RDP password
STARTWM_FILE="/etc/xrdp/startwm.sh"
XRDP_INI="/etc/xrdp/xrdp.ini"
# ---------------------

echo "--- LXDE/XRDP Headless Server Setup Script (NO UFW) ---"
echo "Dedicated RDP User: $RDP_USER"
echo "Custom XRDP Port: $XRDP_PORT"
echo "!!! SECURITY WARNING: Default password '$DEFAULT_PASSWORD' is used for the new user. Change it immediately after connecting. !!!"
echo "WARNING: Local UFW firewall is NOT installed/configured. All ports will be open."
echo "-------------------------------------------------------"

# 1. Update system and install necessary packages
echo "[1/6] Updating system and installing LXDE, XRDP, and D-Bus components..."
sudo apt update -y
sudo apt install -y lxde xrdp dbus-x11 lxsession

if [ $? -ne 0 ]; then
    echo "ERROR: Package installation failed. Exiting."
    exit 1
fi
echo "Packages installed successfully."

# 2. Create the dedicated RDP user and set a password
echo "[2/6] Checking for user '$RDP_USER' and setting its password (CRUCIAL for XRDP login)."
if id "$RDP_USER" &>/dev/null; then
    echo "User '$RDP_USER' already exists. Skipping user creation."
else
    echo "User '$RDP_USER' does not exist. Creating new user..."
    # Add the user and set up home directory permissions
    sudo adduser --disabled-password --gecos "" $RDP_USER
    sudo usermod -d /home/$RDP_USER $RDP_USER
    sudo mkdir -p /home/$RDP_USER
    sudo chown $RDP_USER:$RDP_USER /home/$RDP_USER
    
    # Set the default password non-interactively
    echo "$RDP_USER:$DEFAULT_PASSWORD" | sudo chpasswd
    echo "Default password set for user '$RDP_USER'."
fi

# 3. Configure XRDP to use the new custom port
echo "[3/6] Configuring XRDP port to $XRDP_PORT..."
sudo sed -i "s/^port=3389/port=$XRDP_PORT/" $XRDP_INI
echo "XRDP port set to $XRDP_PORT in $XRDP_INI."

# 4. Configure the XRDP session manager (sesman) to start LXDE
echo "[4/6] Configuring XRDP to launch the LXDE session..."
# Backup the original file
sudo cp $STARTWM_FILE "${STARTWM_FILE}.bak"

# Overwrite the session execution part with a clean LXDE launch
sudo tee $STARTWM_FILE > /dev/null << EOF
#!/bin/sh

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# Launch the LXDE desktop
startlxde
EOF

# Ensure the script is executable
sudo chmod +x $STARTWM_FILE
echo "LXDE launch configured in $STARTWM_FILE."

# 5. Fix potential D-Bus/Sesman connection permissions
echo "[5/6] Adding user $RDP_USER to the ssl-cert group for session stability..."
# Use -a to append, -G to specify groups
sudo usermod -a -G ssl-cert $RDP_USER
echo "User added to ssl-cert group."

# 6. Restart XRDP service
echo "[6/6] Restarting XRDP service to apply all changes..."
sudo systemctl restart xrdp
sudo systemctl status xrdp | grep Active

echo "----------------------------------------------"
echo "--- SETUP COMPLETE ---"
echo "You can now connect to your server via RDP client on: ${PUBLIC_IP}:$XRDP_PORT"
echo "Use Username: $RDP_USER and Password: $DEFAULT_PASSWORD"
echo "!!! IMMEDIATELY CHANGE THE PASSWORD FOR USER $RDP_USER AFTER CONNECTING !!!"
echo "----------------------------------------------"
