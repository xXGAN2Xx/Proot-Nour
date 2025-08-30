#!/bin/sh

# Exit immediately if a command exits with a non-zero status.
set -e

#############################
# Linux Installation #
#############################

# Define the root directory to /home/container.
ROOTFS_DIR=/home/container
# Define the directory for locally installed binaries
LOCAL_BIN_DIR="$HOME/.local/usr/bin"

# --- Optimized Variables ---
MAX_RETRIES=5
TIMEOUT=4
PROOT_DISTRO_VERSION="v4.18.0"

# Function to prepend a directory to PATH if it's not already there and the directory exists
prepend_to_path() {
    local dir_to_add="$1"
    if [ -d "$dir_to_add" ]; then
        case ":${PATH}:" in
            *":${dir_to_add}:"*) :;;
            *) export PATH="${dir_to_add}:${PATH}" ;;
        esac
    fi
}

mkdir -p "$LOCAL_BIN_DIR"
prepend_to_path "$LOCAL_BIN_DIR"

# Detect the machine architecture.
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH_ALT="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH_ALT="arm64"
else
    printf "Unsupported CPU architecture: %s\n" "$ARCH"
    exit 1
fi

# Download & decompress the Linux root file system if not already installed.
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    echo "#######################################################################################"
    echo "#"
    echo "#                                  Nour PteroVM"
    echo "#"
    echo "#######################################################################################"
    echo ""
    echo "INFO: Starting first-time setup..."

    # --- IMPROVEMENT 1: Consolidate all package downloads into a single command ---
    echo "INFO: Downloading required host packages (wget, curl, etc.)..."
    REQUIRED_PKGS="wget curl ca-certificates xz-utils python3-minimal"
    apt download ${REQUIRED_PKGS}

    # --- IMPROVEMENT 2: Extract all downloaded .deb files in a single loop ---
    # This avoids repeatedly calling `find`.
    echo "INFO: Extracting host packages..."
    for deb_file in *.deb; do
        if [ -f "$deb_file" ]; then
            dpkg -x "$deb_file" "$HOME/.local/"
            rm "$deb_file"
        fi
    done
    # Ensure our new binaries are available
    prepend_to_path "$LOCAL_BIN_DIR"
    
    # Verify wget is available before proceeding
    if ! command -v wget >/dev/null 2>&1; then
        echo "ERROR: wget could not be installed. Cannot proceed."
        exit 1
    fi

    # --- IMPROVEMENT 3: Download proot and rootfs in parallel ---
    echo "INFO: Downloading proot and rootfs simultaneously..."
    PROOT_URL="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/${PROOT_DISTRO_VERSION}/ubuntu-noble-${ARCH}-pd-${PROOT_DISTRO_VERSION}.tar.xz"
    
    mkdir -p "$ROOTFS_DIR/usr/local/bin"
    PROOT_PATH="$ROOTFS_DIR/usr/local/bin/proot"

    # Start proot download in the background
    wget --tries=$MAX_RETRIES --timeout=$TIMEOUT -O "$PROOT_PATH" "$PROOT_URL" &
    PROOT_PID=$!

    # --- IMPROVEMENT 4: Stream rootfs extraction to avoid saving the tarball ---
    echo "INFO: Streaming and extracting rootfs..."
    wget --tries=$MAX_RETRIES --timeout=$TIMEOUT -O - "$ROOTFS_URL" | tar -xJf - -C "$ROOTFS_DIR" --strip-components=1
    
    # Wait for the proot download to finish and check if it was successful
    wait $PROOT_PID
    if [ ! -s "$PROOT_PATH" ]; then
        echo "ERROR: Failed to download proot. Exiting."
        exit 1
    fi
    chmod 755 "$PROOT_PATH"

    # --- IMPROVEMENT 5: Move systemctl.py setup into the one-time installation ---
    # This prevents a network call on every container start.
    echo "INFO: Setting up systemctl replacement..."
    SYSTEMCTL_PY_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
    SYSTEMCTL_PY_INSTALL_PATH="$ROOTFS_DIR/usr/local/bin/systemctl"
    wget -O "$SYSTEMCTL_PY_INSTALL_PATH" "$SYSTEMCTL_PY_URL"
    chmod 755 "$SYSTEMCTL_PY_INSTALL_PATH"

    # --- IMPROVEMENT 6: Move package installation inside proot to the one-time setup ---
    # This ensures the environment is fully ready on subsequent starts.
    echo "INFO: Installing tmate and screen inside the environment..."
    "$PROOT_PATH" --rootfs="${ROOTFS_DIR}" -0 -w "/root" \
        -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
        /bin/bash -lc 'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y tmate screen'

    # Final clean-up
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"
    rm -rf /tmp/*
    touch "$ROOTFS_DIR/.installed"
    echo "INFO: First-time setup complete."
fi

###################################################
# Fancy Output                                    #
###################################################
GREEN='\e[0;32m'; RED='\e[0;31m'; YELLOW='\e[0;33m'; MAGENTA='\e[0;35m'; RESET='\e[0m'

display_header() {
    echo -e "${MAGENTA} __      __        ______"
    echo -e " \\ \\    / /       |  ____|"
    echo -e "  \\ \\  / / __  ___| |__ _ __ ___  ___"
    echo -e "   \\ \\/ / '_ \\/ __|  __| '__/ _ \\/ _ \\"
    echo -e "    \\  /| |_) \\__ \\ |  | | |  __/  __/"
    echo -e "     \\/ | .__/|___/_|  |_|  \\___\\___|"
    echo -e "        | |"
    echo -e "        |_|"
    echo -e "___________________________________________________${RESET}"
    echo -e "           ${YELLOW}-----> System Resources <----${RESET}"
    echo "Installation complete! For help, type 'help'"
}

display_resources() {
    local os_pretty_name="N/A"
    [ -f "$ROOTFS_DIR/etc/os-release" ] && os_pretty_name=$(grep "PRETTY_NAME" "$ROOTFS_DIR/etc/os-release" | cut -d'"' -f2)
    local cpu_model="N/A"
    [ -f "/proc/cpuinfo" ] && cpu_model=$(grep 'model name' /proc/cpuinfo | head -n 1 | cut -d':' -f2-)
    echo -e " INSTALLED OS -> ${RED}${os_pretty_name}${RESET}"
    echo -e " CPU -> ${YELLOW}${cpu_model}${RESET}"
    echo -e " RAM -> ${GREEN}${SERVER_MEMORY:-N/A}MB${RESET}"
    echo -e " PRIMARY PORT -> ${GREEN}${SERVER_PORT:-N/A}${RESET}"
}

display_footer() {
    echo -e "___________________________________________________${RESET}"
    echo -e "           ${YELLOW}-----> VPS HAS STARTED <----${RESET}"
}

display_header
display_resources
display_footer

###########################
# Start PRoot environment #
###########################

# --- IMPROVEMENT 7: The final command is now much simpler and faster ---
# It no longer runs apt-get update/install on every start.
exec "$ROOTFS_DIR/usr/local/bin/proot" --rootfs="${ROOTFS_DIR}" -0 -n -w "/root" \
    -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
    /bin/bash -lc 'exec tmate -F'
