#!/bin/bash

# --- Configuration ---
# Use the SERVER_PORT environment variable, or fall back to 14212 if not set.
XRDP_PORT="${SERVER_PORT}"
RDP_USER="nour"           # Default RDP user
DEFAULT_PASSWORD="123456" # Default RDP password
STARTWM_FILE="/etc/xrdp/startwm.sh"
XRDP_INI="/etc/xrdp/xrdp.ini"
WATERFOX_FLATPAK_ID="net.waterfox.waterfox" # Flatpak App ID for Waterfox

# --- Desktop Environment Configuration ---
# Check if an argument was passed for the DE, otherwise default to lxde
if [ -n "$1" ]; then
    DE_CHOICE=$(echo "$1" | tr '[:upper:]' '[:lower:]')
else
    DE_CHOICE="lxde" # Default desktop environment
fi

# Define the installation package and start command based on choice
case "$DE_CHOICE" in
    "lxde")
        DE_PACKAGE="lxde"
        DE_START_COMMAND="startlxde"
        ;;
    "lxqt")
        DE_PACKAGE="lxqt"
        DE_START_COMMAND="startlxqt"
        ;;
    "xfce4")
        DE_PACKAGE="xfce4"
        DE_START_COMMAND="startxfce4"
        ;;
    *)
        echo "ERROR: Invalid Desktop Environment choice: $1"
        echo "Supported options are: lxde, lxqt, xfce4."
        exit 1
        ;;
esac
# ---------------------

echo "--- LXDE/XRDP Headless Server Setup Script (NO UFW) ---"
echo "Selected Desktop Environment: $DE_CHOICE (Package: $DE_PACKAGE)"
echo "Dedicated RDP User: $RDP_USER"
echo "Custom XRDP Port: $XRDP_PORT"
echo "!!! SECURITY WARNING: Default password '$DEFAULT_PASSWORD' is used for the new user. Change it immediately after connecting. !!!"
echo "WARNING: Local UFW firewall is NOT installed/configured. All ports will be open."
echo "-------------------------------------------------------"

# 1. Update system and install necessary packages (including flatpak)
echo "[1/7] Updating system and installing $DE_PACKAGE, XRDP, D-Bus, and Flatpak..."
# Install the chosen DE package along with XRDP, D-Bus, and flatpak
sudo apt update -y
# flatpak is included here
sudo apt install -y $DE_PACKAGE xrdp dbus-x11 lxsession flatpak

if [ $? -ne 0 ]; then
    echo "ERROR: Core package installation failed. Exiting."
    exit 1
fi
echo "Core packages (including flatpak) installed successfully."

# 2. Install Waterfox using Flatpak
echo "[2/7] Installing Waterfox browser using Flatpak..."

# Check if Waterfox is already installed via Flatpak
if flatpak info --installed $WATERFOX_FLATPAK_ID &>/dev/null; then
    echo "Waterfox ($WATERFOX_FLATPAK_ID) is already installed via Flatpak. Skipping installation."
else
    echo "Waterfox not found. Proceeding with Flatpak setup and installation."

    # 2a. Add the Flathub repository (if not already added)
    echo "Adding Flathub repository..."
    # Using --system for system-wide installation, which is generally better for server setups
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    # 2b. Install Waterfox from Flathub
    echo "Installing Waterfox from Flathub..."
    if sudo flatpak install flathub $WATERFOX_FLATPAK_ID -y; then
        echo "Waterfox installed successfully via Flatpak."
    else
        echo "WARNING: Waterfox Flatpak installation failed."
    fi
fi

# 3. Create the dedicated RDP user and set a password
echo "[3/7] Checking for user '$RDP_USER' and setting its password (CRUCIAL for XRDP login)."
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

# 4. Configure XRDP to use the new custom port
echo "[4/7] Configuring XRDP port to $XRDP_PORT..."
# Use sed to safely replace the port number in xrdp.ini
sudo sed -i "s/^port=3389/port=$XRDP_PORT/" $XRDP_INI
echo "XRDP port set to $XRDP_PORT in $XRDP_INI."

# 5. Configure the XRDP session manager (sesman) to start the selected DE
echo "[5/7] Configuring XRDP to launch the $DE_CHOICE session with command: $DE_START_COMMAND"
# Backup the original file
sudo cp $STARTWM_FILE "${STARTWM_FILE}.bak"

# Overwrite the session execution part with a clean DE launch
sudo tee $STARTWM_FILE > /dev/null << EOF
#!/bin/sh

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# Launch the selected desktop environment
$DE_START_COMMAND
EOF

# Ensure the script is executable
sudo chmod +x $STARTWM_FILE
echo "$DE_CHOICE launch configured in $STARTWM_FILE."

# 6. Fix potential D-Bus/Sesman connection permissions
echo "[6/7] Adding user $RDP_USER to the ssl-cert group for session stability..."
# Use -a to append, -G to specify groups
sudo usermod -a -G ssl-cert $RDP_USER
echo "User added to ssl-cert group."

# 7. Restart/Start XRDP services
echo "[7/7] Stopping, Enabling, and Starting XRDP services to apply all changes..."
sudo systemctl stop xrdp
sudo systemctl stop xrdp-sesman 2>/dev/null || true

sudo systemctl enable xrdp
sudo systemctl enable xrdp-sesman 2>/dev/null || true

sudo systemctl start xrdp
sudo systemctl start xrdp-sesman 2>/dev/null || true

# Verify status
echo "XRDP Status:"
sudo systemctl status xrdp | grep Active
echo "Sesman Status (If separate):"
sudo systemctl status xrdp-sesman | grep Active 2>/dev/null || echo "xrdp-sesman is likely integrated with xrdp."

echo "----------------------------------------------"
echo "--- SETUP COMPLETE ---"
echo "You can now connect to your server via RDP client on: \${PUBLIC_IP}:$XRDP_PORT"
echo "Use Username: $RDP_USER and Password: $DEFAULT_PASSWORD"
echo "!!! IMMEDIATELY CHANGE THE PASSWORD FOR USER $RDP_USER AFTER CONNECTING !!!"
echo "----------------------------------------------"
