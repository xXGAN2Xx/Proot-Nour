#!/bin/bash

set -e

# ============================================================================
# Unified Remote Desktop Installation Script
# Supports: XRDP, Chrome Remote Desktop, and noVNC
# Desktop Environment: LXQt
# ============================================================================

SCRIPT_VERSION="2.0.1"
LOG_PATH="/var/log/rdp-install.log"

# Port configuration - uses SERVER_PORT environment variable
# SERVER_PORT must be set before running this script

# Color codes
COLOR_BLUE='\033[0;34m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

output() {
  echo -e "${COLOR_BLUE}[RemoteDesktop] ${1}${COLOR_NC}"
  echo "[$(date)] $1" >> "$LOG_PATH"
}

ask() {
  echo -e -n "${COLOR_GREEN}- ${1}${COLOR_NC} "
}

error() {
  echo -e "${COLOR_RED}ERROR: ${1}${COLOR_NC}"
  echo "[$(date)] ERROR: $1" >> "$LOG_PATH"
}

success() {
  echo -e "${COLOR_GREEN}✓ ${1}${COLOR_NC}"
}

# ============================================================================
# Prerequisites Check
# ============================================================================

check_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be executed with root privileges (sudo)."
    exit 1
  fi
}

check_curl() {
  if ! command -v curl &> /dev/null; then
    error "curl is required for this script to work."
    output "Install using: apt install curl -y"
    exit 1
  fi
}

detect_distro() {
  if command -v lsb_release &> /dev/null; then
    OS=$(lsb_release -si | awk '{print tolower($0)}')
    OS_VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
    OS_VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    OS="debian"
    OS_VER=$(cat /etc/debian_version)
  else
    OS="unknown"
  fi

  OS=$(echo "$OS" | awk '{print tolower($0)}')
  OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
}

check_os() {
  detect_distro
  if [[ "$OS" == "debian" ]] || [[ "$OS" == "ubuntu" ]]; then
    output "Detected OS: $OS $OS_VER"
  else
    error "Unsupported OS: $OS"
    error "This script only supports Debian and Ubuntu."
    exit 1
  fi
}

# ============================================================================
# Desktop Environment Installation
# ============================================================================

install_lxqt() {
  output "Installing LXQt Desktop Environment..."
  
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  
  # Determine which Firefox package to install
  local firefox_pkg="firefox-esr"
  if [[ "$OS" == "ubuntu" ]]; then
    firefox_pkg="firefox"
  fi
  
  # Check if Firefox package exists
  if ! apt-cache show "$firefox_pkg" &> /dev/null; then
    output "Warning: $firefox_pkg not available, trying alternative..."
    if apt-cache show "firefox" &> /dev/null; then
      firefox_pkg="firefox"
    elif apt-cache show "firefox-esr" &> /dev/null; then
      firefox_pkg="firefox-esr"
    else
      output "Warning: No Firefox package found, skipping browser installation"
      firefox_pkg=""
    fi
  fi
  
  # Build package list
  local packages="lxqt-core lxqt-config openbox xorg dbus-x11 xterm"
  if [ -n "$firefox_pkg" ]; then
    packages="$packages $firefox_pkg"
  fi
  
  apt-get install -y --no-install-recommends $packages
  
  success "LXQt Desktop Environment installed successfully"
}

# ============================================================================
# XRDP Installation
# ============================================================================

install_xrdp() {
  output "Installing XRDP..."
  
  apt-get update
  apt-get install -y xrdp
  
  # Add xrdp to ssl-cert group
  usermod -a -G ssl-cert xrdp
  
  # Configure XRDP port
  if [ -n "$SERVER_PORT" ]; then
    output "Configuring XRDP to use port: $SERVER_PORT"
    sed -i "s/\(port *= *\).*/\1$SERVER_PORT/" /etc/xrdp/xrdp.ini
  fi
  
  # Install desktop environment
  install_lxqt
  
  # Configure session for all users
  echo "startlxqt" > /etc/skel/.xsession
  chmod +x /etc/skel/.xsession
  
  # Apply to existing users (with user existence check for proot compatibility)
  for user_home in /home/*; do
    if [ -d "$user_home" ]; then
      username=$(basename "$user_home")
      # Check if user actually exists before proceeding
      if id "$username" &>/dev/null; then
        echo "startlxqt" > "$user_home/.xsession"
        chown "$username:$username" "$user_home/.xsession"
        chmod +x "$user_home/.xsession"
        output "Configured session for user: $username"
      else
        output "Skipping $user_home - user $username does not exist (proot/container environment)"
      fi
    fi
  done
  
  # Configure firewall if UFW is installed and active
  if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
      ufw allow "$SERVER_PORT"/tcp
      output "Firewall rule added for port $SERVER_PORT"
    else
      output "UFW is installed but not active, skipping firewall configuration"
    fi
  else
    output "UFW not found, skipping firewall configuration"
  fi
  
  # Restart XRDP service
  systemctl enable xrdp
  systemctl restart xrdp
  
  # Get server IP (IPv4 only)
  SERVER_IP=$(curl -4 -s https://api64.ipify.org/ || hostname -I | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
  
  success "XRDP installation completed!"
  output "================================================"
  output "Connect using: $SERVER_IP:$SERVER_PORT"
  output "================================================"
}

# ============================================================================
# Chrome Remote Desktop Installation
# ============================================================================

create_crd_user() {
  ask "Enter username for Chrome Remote Desktop: "
  read -r username
  
  if [ "$username" == "root" ]; then
    error "Root user is not allowed!"
    return 1
  fi
  
  if id "$username" &>/dev/null; then
    output "User $username already exists."
    ask "Continue with this user? (y/N): "
    read -r continue
    if [[ ! "$continue" =~ ^[Yy]$ ]]; then
      error "User already exists. Exiting."
      return 1
    fi
  else
    ask "Enter password for user $username: "
    read -s password
    echo
    
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    
    success "User $username created successfully"
  fi
  
  echo "$username"
}

install_chrome_remote_desktop() {
  output "Installing Chrome Remote Desktop..."
  
  username=$(create_crd_user)
  [ -z "$username" ] && return 1
  
  # Install dependencies
  apt-get update
  if [[ $(lsb_release --codename --short) == "stretch" ]]; then
    apt-get install -y libgbm1/stretch-backports
  fi
  
  # Download and install Chrome Remote Desktop
  TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR"
  
  output "Downloading Chrome Remote Desktop package..."
  curl -Lo chrome-remote-desktop.deb https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
  apt-get install -y "$TEMP_DIR/chrome-remote-desktop.deb" || {
    apt-get install -f -y
    apt-get install -y "$TEMP_DIR/chrome-remote-desktop.deb"
  }
  
  cd "$HOME"
  rm -rf "$TEMP_DIR"
  
  # Install desktop environment
  install_lxqt
  
  # Configure Chrome Remote Desktop session
  bash -c 'echo "exec /etc/X11/Xsession /usr/bin/startlxqt" > /etc/chrome-remote-desktop-session'
  
  # Setup authorization
  output "================================================"
  output "Please follow these steps:"
  output "1. Go to: https://remotedesktop.google.com/headless"
  output "2. Click 'Begin' -> 'Next' -> 'Authorize'"
  output "3. Copy the command for Debian Linux"
  output "================================================"
  ask "Paste the authorization command here: "
  read -r auth_code
  
  # Execute authorization as the user
  cat > /tmp/crd_auth.sh << EOF
$auth_code --user-name=$username
EOF
  
  if su - "$username" -c "bash /tmp/crd_auth.sh"; then
    rm -f /tmp/crd_auth.sh
    systemctl enable "chrome-remote-desktop@$username"
    
    success "Chrome Remote Desktop installation completed!"
    output "================================================"
    output "Access your desktop at: https://remotedesktop.google.com/access"
    output "================================================"
  else
    rm -f /tmp/crd_auth.sh
    error "Authorization failed. Please try again."
    return 1
  fi
}

# ============================================================================
# noVNC Installation
# ============================================================================

install_novnc() {
  output "Installing noVNC..."
  
  # Install dependencies
  apt-get update
  apt-get install -y \
    x11vnc \
    xvfb \
    git \
    python3 \
    python3-numpy \
    net-tools \
    websockify
  
  # Install desktop environment
  install_lxqt
  
  # Clone noVNC
  NOVNC_DIR="/opt/novnc"
  if [ -d "$NOVNC_DIR" ]; then
    output "Removing existing noVNC installation..."
    rm -rf "$NOVNC_DIR"
  fi
  
  git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
  git clone https://github.com/novnc/websockify.git "$NOVNC_DIR/utils/websockify"
  
  # Create VNC password
  ask "Set VNC password (8 characters): "
  read -s vnc_password
  echo
  
  mkdir -p ~/.vnc
  x11vnc -storepasswd "$vnc_password" ~/.vnc/passwd
  
  # Create systemd service for x11vnc
  cat > /etc/systemd/system/x11vnc.service << 'EOF'
[Unit]
Description=X11VNC Remote Desktop
After=display-manager.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -forever -loop -noxdamage -repeat -rfbauth /root/.vnc/passwd -rfbport 5900 -shared
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  # Create systemd service for noVNC
  cat > /etc/systemd/system/novnc.service << EOF
[Unit]
Description=noVNC Web VNC Client
After=x11vnc.service

[Service]
Type=simple
ExecStart=$NOVNC_DIR/utils/novnc_proxy --vnc localhost:5900 --listen ${SERVER_PORT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  # Start X server on boot
  cat > /etc/systemd/system/xvfb.service << 'EOF'
[Unit]
Description=Virtual Frame Buffer
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :0 -screen 0 1920x1080x24
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  # Enable and start services
  systemctl daemon-reload
  systemctl enable xvfb x11vnc novnc
  systemctl start xvfb
  sleep 2
  
  # Start desktop session
  DISPLAY=:0 startlxqt &
  sleep 3
  
  systemctl start x11vnc novnc
  
  # Configure firewall if UFW is installed and active
  if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
      ufw allow "$SERVER_PORT"/tcp
      ufw allow 5900/tcp
      output "Firewall rules added for ports $SERVER_PORT and 5900"
    else
      output "UFW is installed but not active, skipping firewall configuration"
    fi
  else
    output "UFW not found, skipping firewall configuration"
  fi
  
  # Get server IP
  SERVER_IP=$(curl -s https://api64.ipify.org/ || hostname -I | awk '{print $1}')
  
  success "noVNC installation completed!"
  output "================================================"
  output "Access noVNC via browser: http://$SERVER_IP:$SERVER_PORT"
  output "VNC Port: 5900"
  output "noVNC Port: $SERVER_PORT"
  output "================================================"
}

# ============================================================================
# Main Menu
# ============================================================================

show_banner() {
  cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     Unified Remote Desktop Installation Script           ║
║                                                           ║
║     Supports: XRDP | Chrome Remote Desktop | noVNC       ║
║     Desktop Environment: LXQt                             ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
}

main_menu() {
  show_banner
  
  output "Script Version: $SCRIPT_VERSION"
  output "Configured Port: $SERVER_PORT"
  output ""
  
  PS3=$(echo -e "${COLOR_GREEN}Select an option (1-4): ${COLOR_NC}")
  
  options=(
    "Install XRDP (Remote Desktop Protocol)"
    "Install Chrome Remote Desktop"
    "Install noVNC (Web-based VNC)"
    "Exit"
  )
  
  select opt in "${options[@]}"; do
    case $REPLY in
      1)
        output "Starting XRDP installation..."
        install_xrdp
        break
        ;;
      2)
        output "Starting Chrome Remote Desktop installation..."
        install_chrome_remote_desktop
        break
        ;;
      3)
        output "Starting noVNC installation..."
        install_novnc
        break
        ;;
      4)
        output "Exiting..."
        exit 0
        ;;
      *)
        error "Invalid option. Please select 1-4."
        ;;
    esac
  done
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  # Initialize log file
  touch "$LOG_PATH"
  
  output "Starting Remote Desktop Installation Script..."
  
  # Run prerequisite checks
  check_root
  check_curl
  check_os
  
  # Show main menu
  main_menu
  
  success "Installation process completed!"
}

# Run main function
main
