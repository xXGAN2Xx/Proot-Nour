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

# Try using a more direct method to create a rootfs
status_msg "Creating minimal rootfs directly..."

# Create basic directory structure
mkdir -p "$ROOTFS_DIR"/{bin,dev,etc,home,lib,lib64,proc,root,sbin,sys,tmp,usr,var}
mkdir -p "$ROOTFS_DIR/usr"/{bin,lib,lib64,sbin,share}
mkdir -p "$ROOTFS_DIR/var"/{cache,lib,log,tmp}

# Download a statically linked busybox binary
status_msg "Downloading static busybox..."
curl -L "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox" -o "$ROOTFS_DIR/bin/busybox"
chmod +x "$ROOTFS_DIR/bin/busybox"

# Create symlinks for busybox applets
cd "$ROOTFS_DIR/bin"
for cmd in ash sh bash cat chmod cp dd df ls mkdir mount umount rm touch echo grep ln ps mv vi tar; do
    ln -sf busybox "$cmd"
done

# Now try to download a working static bash
status_msg "Downloading static bash..."
curl -L "https://github.com/robxu9/bash-static/releases/download/5.1.016-1.2.3/bash-linux-x86_64" -o "$ROOTFS_DIR/bin/bash-static"
chmod +x "$ROOTFS_DIR/bin/bash-static"
# Make it the default shell if download was successful
if [ -f "$ROOTFS_DIR/bin/bash-static" ]; then
    mv "$ROOTFS_DIR/bin/bash-static" "$ROOTFS_DIR/bin/bash"
fi

# Configure a basic environment
status_msg "Setting up basic configuration..."

# /etc/passwd
cat > "$ROOTFS_DIR/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
EOF

# /etc/group
cat > "$ROOTFS_DIR/etc/group" << 'EOF'
root:x:0:
EOF

# Configure DNS
status_msg "Configuring DNS..."
echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
echo "nameserver 8.8.4.4" >> "$ROOTFS_DIR/etc/resolv.conf"

# Create first-run setup script
status_msg "Creating setup scripts..."
cat > "$ROOTFS_DIR/root/setup-debian.sh" << 'EOF'
#!/bin/sh
echo "Setting up a Debian environment in PRoot..."

# Create a temporary directory for debootstrap
mkdir -p /tmp/debootstrap

# Download debootstrap
echo "Downloading debootstrap..."
busybox wget -q https://raw.githubusercontent.com/AndronixApp/AndronixOrigin/master/Installer/Debian/debian.sh -O /tmp/debian-installer.sh
chmod +x /tmp/debian-installer.sh

# Run the installer
echo "Running Debian installer (this might take a while)..."
sh /tmp/debian-installer.sh

echo "If the installer didn't work, you can try setting up manually:"
echo "1. Download a Debian rootfs"
echo "2. Extract it to replace this minimal environment"
echo "3. Restart the PRoot session"

EOF

chmod +x "$ROOTFS_DIR/root/setup-debian.sh"

# Create .profile
cat > "$ROOTFS_DIR/root/.profile" << 'EOF'
# This is a minimal environment
echo "Welcome to the minimal PRoot environment!"
echo "To set up a full Debian system, run: sh /root/setup-debian.sh"
EOF

# Create the start script
cat > "$PROOT_DIR/start-debian.sh" << 'EOF'
#!/bin/bash
# Start script for PRoot environment

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
elif [ -f "$ROOTFS_DIR/bin/sh" ]; then
    SHELL_PATH="/bin/sh"
else
    echo "Error: No shell found in rootfs!"
    exit 1
fi

# Run PRoot with appropriate options
echo "Starting PRoot environment..."
"$PROOT" -S "$ROOTFS_DIR" -w / -0 -r "$ROOTFS_DIR" \
    -b /dev -b /proc -b /sys -b /etc/resolv.conf:/etc/resolv.conf \
    /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin \
    $SHELL_PATH

echo "Exited PRoot environment."
EOF

chmod +x "$PROOT_DIR/start-debian.sh"

# Create a convenience link in home directory
ln -sf "$PROOT_DIR/start-debian.sh" "$HOME/start-debian.sh"

# Create a simple wrapper script for common functions
cat > "$HOME/debian.sh" << 'EOF'
#!/bin/bash
# PRoot environment management script

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
    help|*)
        echo "Usage: $0 [command]"
        echo "Commands:"
        echo "  start    - Start the PRoot environment"
        echo "  run CMD  - Run a command in the PRoot environment"
        echo "  help     - Show this help message"
        ;;
esac
EOF

chmod +x "$HOME/debian.sh"

# Add a script to download a full Debian rootfs directly
cat > "$PROOT_DIR/download-rootfs.sh" << 'EOF'
#!/bin/bash
# Script to download and install a Debian rootfs

PROOT_DIR="$HOME/proot-debian"
ROOTFS_DIR="$PROOT_DIR/debian-rootfs"
TEMP_DIR="$PROOT_DIR/temp"

echo "[*] Setting up a proper Debian rootfs..."

# Create temp directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Try to download from a direct source
echo "[*] Downloading Debian rootfs (this might take a while)..."
wget -q https://github.com/EXALAB/AnLinux-Resources/raw/master/Rootfs/Debian/amd64/debian-rootfs-amd64.tar.xz -O rootfs.tar.xz

if [ $? -ne 0 ]; then
    echo "[!] Primary download failed, trying alternative source..."
    wget -q https://raw.githubusercontent.com/AndronixApp/AndronixOrigin/master/Installer/Debian/debian.sh -O debian.sh
    chmod +x debian.sh
    echo "[*] Running Andronix Debian installer..."
    ./debian.sh
    exit 0
fi

# Extract the rootfs
echo "[*] Extracting rootfs..."
mkdir -p "$TEMP_DIR/extract"
tar -xf rootfs.tar.xz -C "$TEMP_DIR/extract"

# Backup the current rootfs
echo "[*] Backing up current rootfs..."
mv "$ROOTFS_DIR" "$ROOTFS_DIR.bak"

# Move the new rootfs into place
echo "[*] Installing new rootfs..."
mv "$TEMP_DIR/extract" "$ROOTFS_DIR"

# Clean up
echo "[*] Cleaning up..."
rm -rf "$TEMP_DIR"

echo "[+] Debian rootfs installation complete!"
echo "[*] You can now start your Debian environment with: ~/start-debian.sh"
EOF

chmod +x "$PROOT_DIR/download-rootfs.sh"

success_msg "Basic PRoot environment setup complete!"
success_msg "This is a minimal environment. To install a full Debian system:"
echo "  1. Start the environment:  bash ~/start-debian.sh"
echo "  2. Inside the environment, run:  sh /root/setup-debian.sh"
echo ""
echo "Or you can try directly downloading a Debian rootfs with:"
echo "  bash $PROOT_DIR/download-rootfs.sh"
echo ""
echo "Commands available:"
echo "  bash ~/start-debian.sh  - Start the PRoot environment"
echo "  ~/debian.sh start       - Start the PRoot environment"
echo "  ~/debian.sh run COMMAND - Run a command in the PRoot environment"
echo "  ~/debian.sh help        - Show help"
