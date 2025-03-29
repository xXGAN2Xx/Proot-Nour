#!/bin/bash

#############################
# Linux Installation Script #
#############################

ROOTFS_DIR="/home/container"
export PATH="$PATH:$HOME/.local/usr/bin"

max_retries=50
timeout=3

# Detect the machine architecture.
ARCH=$(uname -m)

# Determine package architecture.
case "$ARCH" in
  x86_64) PACKAGE_ARCH="amd64" ;;  # changed to match Debian naming
  aarch64) PACKAGE_ARCH="aarch64" ;;
  i686 | i386) PACKAGE_ARCH="i386" ;;
  armv7l | armhf) PACKAGE_ARCH="arm" ;;
  *)
    echo "Unsupported CPU architecture: ${ARCH}"
    exit 1
    ;;
esac

# Download & install Linux root filesystem if not done already
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    echo "#######################################################################################"
    echo "#"
    echo "#                                Nour PteroVM Installer"
    echo "#"
    echo "#                           Copyright © VPSFREE.ES"
    echo "#"
    echo "#######################################################################################"
    echo ""
    echo "[!] Defaulting to Debian (no input)..."

    echo "[!] Downloading Debian netboot rootfs..."
    NETBOOT_URL="https://mirrors.tuna.tsinghua.edu.cn/debian/dists/bookworm/main/installer-${ARCH}/current/images/netboot/netboot.tar.gz"
    wget --tries=$max_retries --timeout=$timeout -O /tmp/netboot.tar.gz "$NETBOOT_URL"

    echo "[!] Installing gzip utils..."
    apt update && apt install -y gzip tar

    echo "[!] Extracting netboot rootfs..."
    mkdir -p "$ROOTFS_DIR"
    tar -xzf /tmp/netboot.tar.gz -C "$ROOTFS_DIR"
fi

################################
# Package Installation & Setup #
################################

if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    mkdir -p "$ROOTFS_DIR/usr/local/bin"

    echo "[!] Downloading proot binary..."
    proot_url="https://github.com/xXGAN2Xx/proot-nour/raw/refs/heads/main/proot"
    proot_bin="$ROOTFS_DIR/usr/local/bin/proot"

    attempt=0
    until [ -s "$proot_bin" ] || [ "$attempt" -ge "$max_retries" ]; do
        wget --timeout=$timeout -O "$proot_bin" "$proot_url"
        chmod +x "$proot_bin"
        ((attempt++))
        if [ ! -s "$proot_bin" ]; then
            echo "[!] proot download failed, retrying... ($attempt/$max_retries)"
            sleep 1
        fi
    done

    if [ ! -s "$proot_bin" ]; then
        echo "[ERROR] Failed to download proot after $max_retries attempts."
        exit 1
    fi
fi

# Final setup & mark as installed
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    echo "[!] Finalizing installation..."

    # Fix DNS settings inside chroot
    echo -e "nameserver 1.1.1.1\nnameserver 1.0.0.1" > "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null || true

    # Cleanup
    rm -f /tmp/netboot.tar.gz

    # Mark as installed
    touch "$ROOTFS_DIR/.installed"
fi

####################################
# Display system resources summary #
####################################

# Define color escape codes
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
MAGENTA='\e[1;35m'
RESET_COLOR='\e[0m'

# Optional: check if these environment variables are set
SERVER_MEMORY=${SERVER_MEMORY:-"Unknown"}
SERVER_PORT=${SERVER_PORT:-"Unknown"}
P_SERVER_ALLOCATION_LIMIT=${P_SERVER_ALLOCATION_LIMIT:-"Unknown"}
P_SERVER_UUID=${P_SERVER_UUID:-"Unknown"}
P_SERVER_LOCATION=${P_SERVER_LOCATION:-"Unknown"}

display_header() {
    echo -e "${MAGENTA} __      __        ______"
    echo -e " \\ \\    / /       |  ____|"
    echo -e "  \\ \\  / / __  ___| |__ _ __ ___  ___   ___  ___"
    echo -e "   \\ \\/ / '_ \\/ __|  __| '__/ _ \\/ _ \\ / _ \\/ __|"
    echo -e "    \\  /| |_) \\__ \\ |  | | |  __/  __/|  __/\\__ \\"
    echo -e "     \\/ | .__/|___/_|  |_|  \\___|\\___(_)___||___/"
    echo -e "        | |"
    echo -e "        |_|"
    echo -e "__________________________________________________________"
    echo -e "        ${YELLOW}-----> System Resources <-----${RESET_COLOR}"
    echo
}

display_resources() {
    echo -e " INSTALLER OS -> ${RED}$(grep 'PRETTY_NAME' /etc/os-release | cut -d\" -f2)${RESET_COLOR}"
    echo -e " CPU          -> ${YELLOW}$(grep 'model name' /proc/cpuinfo | head -n1 | cut -d ':' -f2 | sed 's/^ *//')${RESET_COLOR}"
    echo -e " RAM          -> ${GREEN}${SERVER_MEMORY}MB${RESET_COLOR}"
    echo -e " PRIMARY PORT -> ${GREEN}${SERVER_PORT}${RESET_COLOR}"
    echo -e " EXTRA PORTS  -> ${GREEN}${P_SERVER_ALLOCATION_LIMIT}${RESET_COLOR}"
    echo -e " SERVER UUID  -> ${GREEN}${P_SERVER_UUID}${RESET_COLOR}"
    echo -e " LOCATION     -> ${GREEN}${P_SERVER_LOCATION}${RESET_COLOR}"
}

display_footer() {
    echo -e "${MAGENTA}__________________________________________________________${RESET_COLOR}"
    echo -e ""
    echo -e "         ${YELLOW}-----> VPS HAS STARTED <-----${RESET_COLOR}"
}

clear
display_header
display_resources
display_footer

####################################
# Start PRoot Linux environment   #
####################################

"$ROOTFS_DIR/usr/local/bin/proot" \
  --rootfs="${ROOTFS_DIR}" -0 -w "/root" \
  -b /dev -b /sys -b /proc -b /etc/resolv.conf \
  --kill-on-exit
