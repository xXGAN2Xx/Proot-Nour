#!/bin/bash
# PRoot Debian Environment Setup Script for Pterodactyl
# This script sets up a Debian environment using PRoot without requiring root access

# Configuration
DEBIAN_VERSION="bullseye"
ARCHITECTURE="amd64"  # Change to "arm64" for ARM systems if needed
PROOT_DIR="$HOME/proot-debian"
ROOTFS_DIR="$PROOT_DIR/debian-rootfs"

# Function to display colored status messages
status_msg() {
    echo -e "\e[1;34m[*] $1\e[0m"
}

error_msg() {
    echo -e "\e[1;31m[!] $1\e[0m"
}

success_msg() {
    echo -e "\e[1;32m[+] $1\e[0m"
}

# Create directories
status_msg "Creating directories..."
mkdir -p "$PROOT_DIR"
mkdir -p "$ROOTFS_DIR"

# Download and install proot if not already installed
if [ ! -f "$PROOT_DIR/proot" ]; then
    status_msg "Downloading PRoot..."
    curl -L https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-x86_64-static -o "$PROOT_DIR/proot"
    chmod +x "$PROOT_DIR/proot"
    if [ ! -f "$PROOT_DIR/proot" ]; then
        error_msg "Failed to download PRoot. Exiting."
        exit 1
    fi
    success_msg "PRoot downloaded successfully."
else
    status_msg "PRoot is already installed."
fi

# Download Debian rootfs if not already downloaded
if [ ! -f "$PROOT_DIR/debian-rootfs.tar.xz" ]; then
    status_msg "Downloading Debian rootfs..."
    # Using the official Debian repository for the rootfs
    DEBIAN_ROOTFS_URL="https://debootstrap.alioth.debian.org/cgi-bin/storage/archive/${DEBIAN_VERSION}/amd64.tar.xz"
    
    # If the above URL fails, try this alternative
    if ! curl -L "$DEBIAN_ROOTFS_URL" -o "$PROOT_DIR/debian-rootfs.tar.xz"; then
        status_msg "Primary URL failed, trying alternative source..."
        # Alternative source from a public mirror
        DEBIAN_ROOTFS_URL="https://mirrors.ocf.berkeley.edu/debian/pool/main/d/debootstrap/debootstrap_${DEBIAN_VERSION}.tar.gz"
        
        if ! curl -L "$DEBIAN_ROOTFS_URL" -o "$PROOT_DIR/debian-rootfs.tar.gz"; then
            # If both fail, use a minimal ubuntu rootfs as a fallback
            status_msg "Debian URLs failed, using Ubuntu minimal rootfs as fallback..."
            UBUNTU_ROOTFS_URL="http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04-base-amd64.tar.gz"
            
            if ! curl -L "$UBUNTU_ROOTFS_URL" -o "$PROOT_DIR/rootfs.tar.gz"; then
                error_msg "Failed to download any rootfs. Attempting to build one from scratch..."
                
                # Let's try to build a minimal rootfs using busybox
                status_msg "Downloading busybox..."
                curl -L "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox" -o "$PROOT_DIR/busybox"
                chmod +x "$PROOT_DIR/busybox"
                
                status_msg "Creating minimal rootfs with busybox..."
                mkdir -p "$ROOTFS_DIR/bin" "$ROOTFS_DIR/dev" "$ROOTFS_DIR/etc" "$ROOTFS_DIR/lib" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys" "$ROOTFS_DIR/usr/bin" "$ROOTFS_DIR/usr/sbin" "$ROOTFS_DIR/var/tmp"
                cp "$PROOT_DIR/busybox" "$ROOTFS_DIR/bin/"
                ln -s /bin/busybox "$ROOTFS_DIR/bin/sh"
                
                # Create a script to install additional packages
                cat > "$ROOTFS_DIR/bin/setup.sh" << 'EOL'
#!/bin/sh
echo "Minimal rootfs created. You will need to manually install packages."
EOL
                chmod +x "$ROOTFS_DIR/bin/setup.sh"
                
                # Set BUSYBOX_FALLBACK flag
                BUSYBOX_FALLBACK=1
                success_msg "Created minimal rootfs with busybox."
            else
                mv "$PROOT_DIR/rootfs.tar.gz" "$PROOT_DIR/debian-rootfs.tar.xz"
                success_msg "Downloaded Ubuntu rootfs as fallback."
            fi
        else
            mv "$PROOT_DIR/debian-rootfs.tar.gz" "$PROOT_DIR/debian-rootfs.tar.xz"
            success_msg "Debian rootfs downloaded using alternative source."
        fi
    else
        success_msg "Debian rootfs downloaded successfully."
    fi
else
    status_msg "Debian rootfs is already downloaded."
fi

# Extract rootfs if not already extracted and not using busybox fallback
if [ ! -f "$ROOTFS_DIR/bin/bash" ] && [ -z "$BUSYBOX_FALLBACK" ]; then
    status_msg "Extracting rootfs..."
    # Determine the correct extraction command based on file type
    file_type=$(file -b "$PROOT_DIR/debian-rootfs.tar.xz")
    
    if [[ "$file_type" == *"XZ compressed data"* ]]; then
        tar -xf "$PROOT_DIR/debian-rootfs.tar.xz" -C "$ROOTFS_DIR"
    elif [[ "$file_type" == *"gzip compressed data"* ]]; then
        tar -xzf "$PROOT_DIR/debian-rootfs.tar.xz" -C "$ROOTFS_DIR"
    else
        status_msg "Unknown archive format. Attempting to extract with tar..."
        tar -xf "$PROOT_DIR/debian-rootfs.tar.xz" -C "$ROOTFS_DIR"
    fi
    
    if [ ! -f "$ROOTFS_DIR/bin/bash" ]; then
        # If extraction failed or the file structure is different, try to extract to a temp dir first
        status_msg "Standard extraction failed. Trying alternative extraction method..."
        mkdir -p "$PROOT_DIR/temp_extract"
        
        if tar -xf "$PROOT_DIR/debian-rootfs.tar.xz" -C "$PROOT_DIR/temp_extract"; then
            # Look for the actual rootfs directory inside the extracted contents
            ROOTFS_SUBDIR=$(find "$PROOT_DIR/temp_extract" -type d -name "rootfs" -o -name "root" -o -name "fs" 2>/dev/null | head -1)
            
            if [ -n "$ROOTFS_SUBDIR" ] && [ -d "$ROOTFS_SUBDIR" ]; then
                status_msg "Found rootfs at $ROOTFS_SUBDIR, copying contents..."
                cp -r "$ROOTFS_SUBDIR"/* "$ROOTFS_DIR"/
            else
                # Just copy everything and hope for the best
                cp -r "$PROOT_DIR/temp_extract"/* "$ROOTFS_DIR"/
            fi
            
            rm -rf "$PROOT_DIR/temp_extract"
        else
            error_msg "Failed to extract rootfs. Creating minimal environment instead."
            
            # Create a minimal environment using debootstrap if available
            if command -v debootstrap >/dev/null 2>&1; then
                status_msg "Using debootstrap to create minimal environment..."
                debootstrap --variant=minbase "$DEBIAN_VERSION" "$ROOTFS_DIR"
            else
                # Create basic directory structure
                mkdir -p "$ROOTFS_DIR/bin" "$ROOTFS_DIR/dev" "$ROOTFS_DIR/etc" "$ROOTFS_DIR/lib" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys" "$ROOTFS_DIR/usr/bin" "$ROOTFS_DIR/usr/sbin" "$ROOTFS_DIR/var/tmp"
                
                # Copy system bash if available
                if [ -f "/bin/bash" ]; then
                    cp "/bin/bash" "$ROOTFS_DIR/bin/"
                    # Try to copy required libraries
                    ldd /bin/bash | grep -o '/lib.*\.so[^ ]*' | while read -r lib; do
                        mkdir -p "$ROOTFS_DIR$(dirname "$lib")"
                        cp "$lib" "$ROOTFS_DIR$lib"
                    done
                fi
            fi
        fi
    fi
    
    if [ -f "$ROOTFS_DIR/bin/bash" ]; then
        success_msg "Rootfs extracted successfully."
    else
        status_msg "Could not find bash in rootfs. The environment may be minimal."
    fi
elif [ -n "$BUSYBOX_FALLBACK" ]; then
    status_msg "Using busybox minimal rootfs."
else
    status_msg "Rootfs is already extracted."
fi

# Configure DNS
status_msg "Configuring DNS..."
mkdir -p "$ROOTFS_DIR/etc"
echo "nameserver 8.8.8.8" > "$ROOTFS_DIR/etc/resolv.conf"
echo "nameserver 8.8.4.4" >> "$ROOTFS_DIR/etc/resolv.conf"

# Create startup script
status_msg "Creating startup script..."
cat > "$PROOT_DIR/start-debian.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROOT="$SCRIPT_DIR/proot"
ROOTFS_DIR="$SCRIPT_DIR/debian-rootfs"

# Check if directories exist
if [ ! -f "$PROOT" ]; then
    echo "Error: PRoot executable not found!"
    exit 1
fi

if [ ! -d "$ROOTFS_DIR" ]; then
    echo "Error: Rootfs directory not found!"
    exit 1
fi

# Detect shell
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

# Run proot with appropriate options
echo "Starting Debian/Linux environment..."
"$PROOT" -S "$ROOTFS_DIR" -w / -0 -r "$ROOTFS_DIR" \
    -b /dev -b /proc -b /sys -b /etc/resolv.conf:/etc/resolv.conf \
    /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin \
    $SHELL_PATH $LOGIN_PARAM

echo "Exited Linux environment."
EOF

chmod +x "$PROOT_DIR/start-debian.sh"

# Create a convenience link in the home directory
ln -sf "$PROOT_DIR/start-debian.sh" "$HOME/start-debian.sh"

# Create a first-run setup script inside the rootfs
mkdir -p "$ROOTFS_DIR/root"
cat > "$ROOTFS_DIR/root/first-run-setup.sh" << 'EOF'
#!/bin/sh
echo "Performing first-time setup of Linux environment..."

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
    echo "You can download and use busybox applets for additional functionality."
else
    echo "Unknown distribution. You'll need to install packages manually."
fi

echo "Basic setup complete!"
echo "Delete this script with: rm ~/first-run-setup.sh"
EOF

chmod +x "$ROOTFS_DIR/root/first-run-setup.sh"

# Create .profile for the root user
cat > "$ROOTFS_DIR/root/.profile" << 'EOF'
# Check for first run
if [ -f ~/first-run-setup.sh ]; then
    echo "It looks like this is your first time running this environment."
    echo "Would you like to run the first-time setup script to install basic utilities? (y/n)"
    read -r response
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        sh ~/first-run-setup.sh
    else
        echo "You can run it later with: sh ~/first-run-setup.sh"
    fi
fi
EOF

# Create .bashrc if bash is available
if [ -f "$ROOTFS_DIR/bin/bash" ]; then
    cat > "$ROOTFS_DIR/root/.bashrc" << 'EOF'
export PS1='\[\033[1;32m\]\u@proot-env\[\033[00m\]:\[\033[1;34m\]\w\[\033[00m\]\$ '

# Source profile for first-run check
if [ -f ~/.profile ]; then
    . ~/.profile
fi

alias ls='ls --color=auto'
alias ll='ls -la'
EOF
fi

success_msg "Linux environment setup complete!"
status_msg "To start your environment, run: bash $HOME/start-debian.sh"
