#!/bin/bash
# All-in-One PRoot Debian Setup Script for Pterodactyl Panel
# This script sets up a Debian environment using PRoot without requiring root access

# ==================== Configuration ====================
DEBIAN_VERSION="bullseye"
ARCHITECTURE="amd64"  # Change to "arm64" for ARM systems if needed
PROOT_DIR="$HOME/proot-debian"
ROOTFS_DIR="$PROOT_DIR/debian-rootfs"

# ==================== Helper Functions ====================
status_msg() {
    echo -e "\e[1;34m[*] $1\e[0m"
}

error_msg() {
    echo -e "\e[1;31m[!] $1\e[0m"
}

success_msg() {
    echo -e "\e[1;32m[+] $1\e[0m"
}

# ==================== Main Script ====================
# Create directories
status_msg "Creating directories..."
mkdir -p "$PROOT_DIR"
mkdir -p "$ROOTFS_DIR"

# Download PRoot
status_msg "Downloading PRoot..."
curl -L https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-x86_64-static -o "$PROOT_DIR/proot"
chmod +x "$PROOT_DIR/proot"
if [ ! -f "$PROOT_DIR/proot" ]; then
    error_msg "Failed to download PRoot. Exiting."
    exit 1
fi
success_msg "PRoot downloaded successfully."

# Download Debian rootfs
status_msg "Downloading Debian rootfs..."
DEBIAN_ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v3.10.0/debian-${ARCHITECTURE}.tar.gz"
curl -L "$DEBIAN_ROOTFS_URL" -o "$PROOT_DIR/debian-rootfs.tar.gz"

# Check if download succeeded
if [ ! -f "$PROOT_DIR/debian-rootfs.tar.gz" ]; then
    status_msg "Primary URL failed, trying alternative source..."
    DEBIAN_ROOTFS_URL="https://github.com/EXALAB/AnLinux-Resources/raw/master/Rootfs/Debian/${ARCHITECTURE}/debian-rootfs-${ARCHITECTURE}.tar.gz"
    curl -L "$DEBIAN_ROOTFS_URL" -o "$PROOT_DIR/debian-rootfs.tar.gz"
fi

# Check again and try Ubuntu if Debian fails
if [ ! -f "$PROOT_DIR/debian-rootfs.tar.gz" ]; then
    status_msg "Debian URLs failed, using Ubuntu minimal rootfs as fallback..."
    UBUNTU_ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v3.10.0/ubuntu-${ARCHITECTURE}.tar.gz"
    curl -L "$UBUNTU_ROOTFS_URL" -o "$PROOT_DIR/debian-rootfs.tar.gz"
fi

# Final check - create minimal rootfs if all downloads fail
if [ ! -f "$PROOT_DIR/debian-rootfs.tar.gz" ]; then
    error_msg "Failed to download any rootfs. Creating minimal busybox environment."
    
    # Download busybox
    curl -L "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox" -o "$PROOT_DIR/busybox"
    chmod +x "$PROOT_DIR/busybox"
    
    # Create minimal directory structure
    mkdir -p "$ROOTFS_DIR"/{bin,dev,etc,lib,proc,sys,usr/{bin,sbin},var/tmp,root}
    
    # Copy busybox
    cp "$PROOT_DIR/busybox" "$ROOTFS_DIR/bin/"
    ln -s "/bin/busybox" "$ROOTFS_DIR/bin/sh"
    
    # Set flag to skip extraction
    BUSYBOX_FALLBACK=1
    success_msg "Created minimal rootfs with busybox."
else
    success_msg "Rootfs downloaded successfully."
fi

# Extract rootfs if not using busybox fallback
if [ -z "$BUSYBOX_FALLBACK" ]; then
    status_msg "Extracting rootfs..."
    tar -xzf "$PROOT_DIR/debian-rootfs.tar.gz" -C "$ROOTFS_DIR"
    
    if [ $? -ne 0 ]; then
        error_msg "Extraction failed. Trying alternative extraction method..."
        mkdir -p "$PROOT_DIR/temp_extract"
        tar -xzf "$PROOT_DIR/debian-rootfs.tar.gz" -C "$PROOT_DIR/temp_extract"
        
        # Look for rootfs directory in the extracted content
        ROOTFS_SUBDIR=$(find "$PROOT_DIR/temp_extract" -type d -name "rootfs" -o -name "root" -o -name "fs" 2>/dev/null | head -1)
        
        if [ -n "$ROOTFS_SUBDIR" ]; then
            cp -r "$ROOTFS_SUBDIR"/* "$ROOTFS_DIR"/
        else
            # Just copy everything
            cp -r "$PROOT_DIR/temp_extract"/* "$ROOTFS_DIR"/
        fi
        
        rm -rf "$PROOT_DIR/temp_extract"
    fi
    
    success_msg "Rootfs extracted successfully."
fi

# Configure DNS
status_msg "Configuring DNS..."
echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
echo "nameserver 8.8.4.4" >> "$ROOTFS_DIR/etc/resolv.conf"

# Create first-run setup script
status_msg "Creating setup scripts..."
cat > "$ROOTFS_DIR/root/first-run-setup.sh" << 'EOF'
#!/bin/sh
echo "Performing first-time setup..."

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
    echo "Debian/Ubuntu detected, using apt..."
    apt-get update
    apt-get install -y wget curl nano less procps net-tools iproute2
elif command -v apk >/dev/null 2>&1; then
    echo "Alpine detected, using apk..."
    apk update
    apk add wget curl nano less procps net-tools iproute2
elif command -v yum >/dev/null 2>&1; then
    echo "RHEL/CentOS detected, using yum..."
    yum update -y
    yum install -y wget curl nano less procps net-tools iproute2
elif command -v busybox >/dev/null 2>&1; then
    echo "BusyBox detected. This is a minimal environment."
else
    echo "Unknown distribution. Install packages manually."
fi

echo "Setup complete! Delete this script with: rm ~/first-run-setup.sh"
EOF

chmod +x "$ROOTFS_DIR/root/first-run-setup.sh"

# Create .profile
cat > "$ROOTFS_DIR/root/.profile" << 'EOF'
# Check for first run
if [ -f ~/first-run-setup.sh ]; then
    echo "It appears this is your first time running this environment."
    echo "Run the setup script to install basic utilities? (y/n)"
    read -r response
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        sh ~/first-run-setup.sh
    else
        echo "You can run it later with: sh ~/first-run-setup.sh"
    fi
fi
EOF

# Create .bashrc if bash exists
if [ -f "$ROOTFS_DIR/bin/bash" ]; then
    cat > "$ROOTFS_DIR/root/.bashrc" << 'EOF'
export PS1='\[\033[1;32m\]\u@proot-debian\[\033[00m\]:\[\033[1;34m\]\w\[\033[00m\]\$ '

# Source profile for first-run check
if [ -f ~/.profile ]; then
    . ~/.profile
fi

alias ls='ls --color=auto'
alias ll='ls -la'
EOF
fi

# Create the start script
cat > "$PROOT_DIR/start-debian.sh" << 'EOF'
#!/bin/bash
# Start script for PRoot Debian environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROOT="$SCRIPT_DIR/proot"
ROOTFS_DIR="$SCRIPT_DIR/debian-rootfs"

# Check if required files exist
if [ ! -f "$PROOT" ]; then
    echo "Error: PRoot executable not found!"
    exit 1
fi

if [ ! -d "$ROOTFS_DIR" ]; then
    echo "Error: Rootfs directory not found!"
    exit 1
fi

# Detect available shell
if [ -f "$ROOTFS_DIR/bin/bash" ]; then
    SHELL_PATH="/bin/bash"
    LOGIN_PARAM="--login"
elif [ -f "$ROOTFS_DIR/bin/sh" ]; then
    SHELL_PATH="/bin/sh"
    LOGIN_PARAM=""
else
    echo "Error: No shell found in rootfs!"
    exit 1
fi

# Run PRoot with appropriate options
echo "Starting Debian environment..."
"$PROOT" -S "$ROOTFS_DIR" -w / -0 -r "$ROOTFS_DIR" \
    -b /dev -b /proc -b /sys -b /etc/resolv.conf:/etc/resolv.conf \
    /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin \
    $SHELL_PATH $LOGIN_PARAM

echo "Exited Debian environment."
EOF

chmod +x "$PROOT_DIR/start-debian.sh"

# Create a convenience link in home directory
ln -sf "$PROOT_DIR/start-debian.sh" "$HOME/start-debian.sh"

# Create a simple wrapper script for common functions
cat > "$HOME/debian.sh" << 'EOF'
#!/bin/bash
# Debian environment management script

PROOT_DIR="$HOME/proot-debian"
START_SCRIPT="$PROOT_DIR/start-debian.sh"

case "$1" in
    start)
        bash "$START_SCRIPT"
        ;;
    run)
        shift
        if [ $# -eq 0 ]; then
            echo "Usage: $0 run <command>"
            exit 1
        fi
        "$PROOT_DIR/proot" -S "$PROOT_DIR/debian-rootfs" -w / -0 -r "$PROOT_DIR/debian-rootfs" \
            -b /dev -b /proc -b /sys -b /etc/resolv.conf:/etc/resolv.conf \
            /usr/bin/env -i \
            HOME=/root \
            TERM="$TERM" \
            PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin \
            /bin/sh -c "$*"
        ;;
    update)
        "$PROOT_DIR/proot" -S "$PROOT_DIR/debian-rootfs" -w / -0 -r "$PROOT_DIR/debian-rootfs" \
            -b /dev -b /proc -b /sys -b /etc/resolv.conf:/etc/resolv.conf \
            /usr/bin/env -i \
            HOME=/root \
            TERM="$TERM" \
            PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin \
            /bin/sh -c "if command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get upgrade -y; elif command -v apk >/dev/null 2>&1; then apk update && apk upgrade; elif command -v yum >/dev/null 2>&1; then yum update -y; else echo 'Unknown package manager'; fi"
        ;;
    clean)
        rm -f "$PROOT_DIR/debian-rootfs.tar.gz"
        echo "Cleaned up downloaded archives."
        ;;
    help|*)
        echo "Usage: $0 [command]"
        echo "Commands:"
        echo "  start    - Start the Debian environment"
        echo "  run CMD  - Run a command in the Debian environment"
        echo "  update   - Update packages in the environment"
        echo "  clean    - Remove downloaded archives"
        echo "  help     - Show this help message"
        ;;
esac
EOF

chmod +x "$HOME/debian.sh"

# Clean up
rm -f "$PROOT_DIR/debian-rootfs.tar.gz"

success_msg "Debian environment setup complete!"
success_msg "Commands available:"
echo "  bash ~/start-debian.sh  - Start the Debian environment"
echo "  ~/debian.sh start       - Start the Debian environment"
echo "  ~/debian.sh run COMMAND - Run a command in the Debian environment"
echo "  ~/debian.sh update      - Update packages"
echo "  ~/debian.sh help        - Show help"
