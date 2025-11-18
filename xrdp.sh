#!/bin/bash

# --- Configuration ---
# Defaults
DEFAULT_XRDP_PORT="${SERVER_PORT}"  # Standard RDP port
DEFAULT_DE="lxde"
SUPPORTED_DES=("lxde" "lxqt" "xfce4") # List for argument validation
RDP_USER="nour"           # Default RDP user
DEFAULT_PASSWORD="123456" # Default RDP password
STARTWM_FILE="/etc/xrdp/startwm.sh"
XRDP_INI="/etc/xrdp/xrdp.ini"
CHROME_DEB_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
CHROME_DEB_PATH="/tmp/google-chrome-stable_current_amd64.deb"
CHROME_PACKAGE="google-chrome-stable"
CHROME_EXEC="/usr/bin/google-chrome-stable" # Standard installation path for Chrome


# Function to check if a string is a valid DE
is_valid_de() {
    local de_input=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    for de in "${SUPPORTED_DES[@]}"; do
        if [ "$de_input" == "$de" ]; then
            echo "$de_input"
            return 0
        fi
    done
    return 1
}


# --- Argument Parsing: ./script.sh [PORT] [DE] OR ./script.sh [DE] [PORT] OR ./script.sh [SINGLE_ARG] ---

if [ $# -eq 0 ]; then
    # Case 0: No arguments. Use all defaults.
    XRDP_PORT="$DEFAULT_XRDP_PORT"
    DE_CHOICE="$DEFAULT_DE"
    echo "WARNING: No arguments provided. Using default port ($XRDP_PORT) and DE ($DE_CHOICE)."

elif [ $# -eq 1 ]; then
    # Case 1: One argument. Check if it's a DE name first, then a port.

    ARG1_LOWER=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    VALID_DE_RESULT=$(is_valid_de "$ARG1_LOWER")
    
    if [ $? -eq 0 ]; then
        # Argument 1 is a valid DE (e.g., ./1.sh lxde)
        DE_CHOICE="$VALID_DE_RESULT"
        XRDP_PORT="$DEFAULT_XRDP_PORT"
        echo "Detected DE '$DE_CHOICE' as the only argument. Using default port: $DEFAULT_XRDP_PORT"
    elif [[ "$1" =~ ^[0-9]+$ ]]; then
        # Argument 1 is a number (e.g., ./1.sh 25565)
        XRDP_PORT="$1"
        DE_CHOICE="$DEFAULT_DE"
        echo "Detected port '$XRDP_PORT' as the only argument. Using default DE: $DEFAULT_DE"
    else
        # Argument 1 is invalid
        echo "ERROR: Invalid single argument '$1'. Must be a supported DE (${SUPPORTED_DES[*]}) or a port number."
        exit 1
    fi

elif [ $# -eq 2 ]; then
    # Case 2: Two arguments. Check for both [PORT] [DE] and [DE] [PORT] combinations.

    ARG1_LOWER=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    ARG2_LOWER=$(echo "$2" | tr '[:upper:]' '[:lower:]')

    # Helper variables to check argument type
    IS_PORT1=0; if [[ "$1" =~ ^[0-9]+$ ]]; then IS_PORT1=1; fi
    IS_PORT2=0; if [[ "$2" =~ ^[0-9]+$ ]]; then IS_PORT2=1; fi
    
    IS_DE1=0; VALID_DE1=$(is_valid_de "$ARG1_LOWER"); if [ $? -eq 0 ]; then IS_DE1=1; fi
    IS_DE2=0; VALID_DE2=$(is_valid_de "$ARG2_LOWER"); if [ $? -eq 0 ]; then IS_DE2=1; fi

    if [ $IS_PORT1 -eq 1 ] && [ $IS_DE2 -eq 1 ]; then
        # Format 1: [PORT] [DE] (e.g., 25565 lxde)
        XRDP_PORT="$1"
        DE_CHOICE="$VALID_DE2"
        echo "Detected arguments format: [PORT] [DE] ($XRDP_PORT $DE_CHOICE)"

    elif [ $IS_DE1 -eq 1 ] && [ $IS_PORT2 -eq 1 ]; then
        # Format 2: [DE] [PORT] (e.g., lxqt 25565) <-- FIX FOR USER'S REQUEST
        DE_CHOICE="$VALID_DE1"
        XRDP_PORT="$2"
        echo "Detected arguments format: [DE] [PORT] ($DE_CHOICE $XRDP_PORT)"

    else
        # Neither combination matches
        echo "ERROR: Invalid combination of two arguments: '$1' and '$2'."
        echo "Supported combinations: [PORT] [DE] or [DE] [PORT]."
        echo "Supported DEs: ${SUPPORTED_DES[*]}"
        exit 1
    fi

else
    # Case 3: Too many arguments
    echo "ERROR: Too many arguments. Usage: ./script.sh [PORT] [DE] or ./script.sh [DE] [PORT] or ./script.sh [SINGLE_ARG]"
    exit 1
fi

# --- Desktop Environment Configuration ---
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
        DE_PACKAGE="xfce4 xfce4-goodies" # Install common XFCE components
        DE_START_COMMAND="startxfce4"
        ;;
    *)
        # Should be caught by the parsing logic, but here as a safeguard
        echo "FATAL ERROR: Desktop Environment logic failed."
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

# 1. Update system and install necessary packages
echo "[1/8] Updating system and installing $DE_PACKAGE, XRDP, D-Bus, and wget..."
# Install the chosen DE package along with XRDP, D-Bus, and wget for Chrome download
sudo apt update -y
sudo apt install -y $DE_PACKAGE xrdp dbus-x11 lxsession wget

if [ $? -ne 0 ]; then
    echo "ERROR: Core package installation failed. Exiting."
    exit 1
fi
echo "Core packages installed successfully."

# 2. Create the dedicated RDP user and set a password
echo "[2/8] Checking for user '$RDP_USER' and setting its password (CRUCIAL for XRDP login)."
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

# 3. Install Google Chrome (System-wide installation)
echo "[3/8] Installing web browser (Google Chrome) system-wide..."

# Check if Chrome is already installed
if dpkg-query -W -f='${Status}' $CHROME_PACKAGE 2>/dev/null | grep -c "ok installed" > 0; then
    echo "$CHROME_PACKAGE is already installed. Skipping installation."
else
    echo "$CHROME_PACKAGE not found. Downloading and installing..."
    
    # Download the .deb package
    if sudo wget -O "$CHROME_DEB_PATH" "$CHROME_DEB_URL"; then
        echo "Download complete. Installing package and dependencies..."
        
        # Install the package (will likely fail due to dependencies)
        sudo dpkg -i "$CHROME_DEB_PATH"
        
        # Install missing dependencies and complete the installation
        if sudo apt --fix-broken install -y; then
            echo "$CHROME_PACKAGE installed successfully."
        else
            echo "ERROR: Dependency resolution failed. $CHROME_PACKAGE may not be fully installed."
        fi
        
        # Clean up the downloaded .deb file
        sudo rm -f "$CHROME_DEB_PATH"
    else
        echo "ERROR: Failed to download Google Chrome from $CHROME_DEB_URL. Proceeding without a browser."
    fi
fi

# 4. Configure Google Chrome to autostart in DE
echo "[4/8] Configuring Google Chrome to autostart for user '$RDP_USER'..."
CHROME_AUTOSTART_DIR="/home/$RDP_USER/.config/autostart"
CHROME_AUTOSTART_FILE="$CHROME_AUTOSTART_DIR/google-chrome.desktop"

# Create the autostart directory if it doesn't exist
sudo -u $RDP_USER mkdir -p "$CHROME_AUTOSTART_DIR"

# Create the .desktop file to launch Chrome
sudo tee "$CHROME_AUTOSTART_FILE" > /dev/null << EOF
[Desktop Entry]
Type=Application
Name=Google Chrome
Exec=$CHROME_EXEC --no-sandbox --start-maximized
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# Ensure the file is owned by the user
sudo chown $RDP_USER:$RDP_USER "$CHROME_AUTOSTART_FILE"
echo "Google Chrome autostart configured in $CHROME_AUTOSTART_FILE."
echo "NOTE: '--no-sandbox' is added for compatibility in headless/proot environments."

# 5. Configure XRDP to use the new custom port
echo "[5/8] Configuring XRDP port to $XRDP_PORT..."
# Replace the port number in xrdp.ini. Using the default port as the target for sed.
sudo sed -i "s/^port=3389/port=$XRDP_PORT/" $XRDP_INI
echo "XRDP port set to $XRDP_PORT in $XRDP_INI."

# 6. Configure the XRDP session manager (sesman) to start the selected DE
echo "[6/8] Configuring XRDP to launch the $DE_CHOICE session with command: $DE_START_COMMAND"
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

# 7. Fix potential D-Bus/Sesman connection permissions
echo "[7/8] Adding user $RDP_USER to the ssl-cert group for session stability..."
# Use -a to append, -G to specify groups
sudo usermod -a -G ssl-cert $RDP_USER
echo "User added to ssl-cert group."

# 8. Restart/Start XRDP services
echo "[8/8] Stopping, Enabling, and Starting XRDP services to apply all changes..."
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
echo "You can now connect to your server via RDP client on: ${PUBLIC_IP}:$XRDP_PORT"
echo "Use Username: $RDP_USER and Password: $DEFAULT_PASSWORD"
echo "!!! IMMEDIATELY CHANGE THE PASSWORD FOR USER $RDP_USER AFTER CONNECTING !!!"
echo "----------------------------------------------"
