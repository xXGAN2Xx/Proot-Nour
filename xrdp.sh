#!/bin/bash

# =============================================================================
# XRDP & Headless Browser Setup Script (Proot/Container Friendly)
# Supports: LXDE, XFCE4
# Features: Chrome Autostart, Proot Compatibility
# =============================================================================

# --- Configuration Defaults ---
DEFAULT_PORT="${SERVER_PORT:-3389}" # Default to 3389 if SERVER_PORT not set
DEFAULT_DE="xfce4"
DEFAULT_USER="nour"
DEFAULT_PASSWORD="123456" 
SUPPORTED_DES=("lxde" "xfce4")
XRDP_INI="/etc/xrdp/xrdp.ini"
STARTWM_FILE="/etc/xrdp/startwm.sh"

# Colors for prettier output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Helper Functions ---

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

check_status() {
    if [ $? -ne 0 ]; then
        log_err "Step failed: $1"
        exit 1
    fi
}

check_root() {
    # In proot, you are effectively root (uid 0) inside the container
    if [ "$(id -u)" -ne 0 ]; then
        log_err "Please run as root (sudo ./script.sh)"
        exit 1
    fi
}

usage() {
    echo "Usage: $0 [-p PORT] [-d DE] [-u USER]"
    echo "  -p  XRDP Port (default: $DEFAULT_PORT)"
    echo "  -d  Desktop Environment: 'lxde' or 'xfce4' (default: xfce4)"
    echo "  -u  RDP Username (default: nour)"
    echo "  -h  Show this help"
    exit 1
}

# --- Argument Parsing (getopts) ---

XRDP_PORT="$DEFAULT_PORT"
DE_CHOICE="$DEFAULT_DE"
RDP_USER="$DEFAULT_USER"

while getopts "p:d:u:h" opt; do
    case ${opt} in
        p) XRDP_PORT="$OPTARG" ;;
        d) DE_CHOICE=$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]') ;;
        u) RDP_USER="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate DE
if [[ ! " ${SUPPORTED_DES[*]} " =~ " ${DE_CHOICE} " ]]; then
    log_err "Invalid DE: $DE_CHOICE. Supported: ${SUPPORTED_DES[*]}"
    exit 1
fi

# Validate Port
if ! [[ "$XRDP_PORT" =~ ^[0-9]+$ ]] || [ "$XRDP_PORT" -lt 1 ] || [ "$XRDP_PORT" -gt 65535 ]; then
    log_err "Invalid Port: $XRDP_PORT"
    exit 1
fi

# --- Main Logic ---

check_root

echo "-------------------------------------------------------"
echo -e "   ${GREEN}Starting XRDP Setup (Proot Mode)${NC}"
echo -e "   DE: $DE_CHOICE | Port: $XRDP_PORT | User: $RDP_USER"
echo "-------------------------------------------------------"

# 1. System Update & Dependencies
log_info "Updating system and installing components..."
export DEBIAN_FRONTEND=noninteractive

# Removed 'ufw' and added 'net-tools' for netstat if needed
apt update -y && apt install -y xrdp dbus-x11 lxsession wget sudo curl net-tools
check_status "System Update"

# Install DE specific packages
if [ "$DE_CHOICE" == "lxde" ]; then
    apt install -y lxde
    DE_START="startlxde"
elif [ "$DE_CHOICE" == "xfce4" ]; then
    apt install -y xfce4 xfce4-goodies
    DE_START="startxfce4"
fi
check_status "DE Installation"

# 2. Swap Creation (SKIPPED FOR PROOT)
log_warn "Running in proot environment: Skipping Swap creation (not supported)."
log_warn "Skipping Firewall configuration (handled by host)."

# 3. User Creation & Password
log_info "Configuring user '$RDP_USER'..."
if id "$RDP_USER" &>/dev/null; then
    log_warn "User exists. Updating password to default."
else
    # Ensure home dir is created
    useradd -m -s /bin/bash "$RDP_USER"
    check_status "User Creation"
    usermod -aG sudo "$RDP_USER"
fi

# Set the Default Password
echo "$RDP_USER:$DEFAULT_PASSWORD" | chpasswd
check_status "Password Set"

# Add to ssl-cert for xRDP stability
usermod -a -G ssl-cert "$RDP_USER"

# 4. Chrome Installation
log_info "Installing Google Chrome..."
if ! dpkg -l | grep -q google-chrome-stable; then
    wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt install -y /tmp/chrome.deb
    rm /tmp/chrome.deb
    check_status "Chrome Install"
else
    log_info "Chrome is already installed."
fi

# 5. Chrome Autostart
log_info "Configuring Autostart..."
AUTOSTART_DIR="/home/$RDP_USER/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

# Note: In proot, --no-sandbox is absolutely mandatory for Chrome
cat <<EOF > "$AUTOSTART_DIR/google-chrome.desktop"
[Desktop Entry]
Type=Application
Name=Google Chrome
Exec=/usr/bin/google-chrome-stable --no-sandbox --disable-gpu --start-maximized
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
EOF

chown -R "$RDP_USER:$RDP_USER" "/home/$RDP_USER/.config"
chmod +x "$AUTOSTART_DIR/google-chrome.desktop"

# 6. XRDP Configuration
log_info "Configuring XRDP internals..."

# Configure Port
sed -i "s/^port=[0-9]*/port=$XRDP_PORT/" $XRDP_INI

# Configure StartWM
cp $STARTWM_FILE "${STARTWM_FILE}.bak"
cat <<EOF > $STARTWM_FILE
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi
# Fix for some proot DBUS issues
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Start DE
exec $DE_START
EOF
chmod +x $STARTWM_FILE

# 7. Restart Services (PROOT METHOD)
log_info "Starting XRDP manually (Systemd not available)..."

# Kill existing processes (if re-running script)
pkill -u root xrdp
pkill -u root xrdp-sesman

# Clean up stale pid files (Common issue in containers)
rm -rf /var/run/xrdp.pid
rm -rf /var/run/xrdp-sesman.pid
rm -rf /var/run/xrdp/xrdp-sesman.pid
rm -rf /var/run/xrdp/xrdp.pid

# Start SESMAN first, then XRDP
# We run them in the background
/usr/sbin/xrdp-sesman &
sleep 2
/usr/sbin/xrdp &
sleep 2

# Check if running
if pgrep -x "xrdp" > /dev/null; then
    log_info "XRDP started successfully."
else
    log_err "XRDP failed to start. Check /var/log/xrdp.log"
fi

# --- Final Output ---
PUBLIC_IP=$(curl --silent -L checkip.pterodactyl-installer.se || echo "SERVER_IP")

echo ""
echo "======================================================="
echo -e "${GREEN}   INSTALLATION COMPLETE ${NC}"
echo "======================================================="
echo -e "Connection Address : ${YELLOW}${PUBLIC_IP}:${XRDP_PORT}${NC}"
echo -e "Username           : ${YELLOW}${RDP_USER}${NC}"
echo -e "Password           : ${YELLOW}${DEFAULT_PASSWORD}${NC}"
echo "======================================================="
echo -e "${RED}IMPORTANT:${NC} If you restart this container, XRDP will stop."
echo -e "To start it again, run: ${YELLOW}/usr/sbin/xrdp-sesman && /usr/sbin/xrdp${NC}"
echo "======================================================="
