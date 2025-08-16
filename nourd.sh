#!/bin/sh

#############################
# Linux Installation #
#############################

# Define the root directory to /home/container.
# We can only write in /home/container and /tmp in the container.
ROOTFS_DIR=/home/container
# Define the directory for locally installed binaries
LOCAL_BIN_DIR="$HOME/.local/usr/bin"

max_retries=5
timeout=4

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
    echo "INFO: Attempting to install wget locally..."
    apt download wget
    
    deb_file_wget=$(find "$ROOTFS_DIR" -maxdepth 1 -name "wget_*.deb" -type f -print -quit)
    if [ -n "$deb_file_wget" ]; then
        echo "INFO: Extracting wget from $deb_file_wget to $HOME/.local/"
        dpkg -x "$deb_file_wget" "$HOME/.local/"
        rm "$deb_file_wget"
        if ! command -v wget >/dev/null 2>&1; then
            echo "WARN: wget installed but still not found in PATH."
        else
            echo "INFO: Custom wget is now available in PATH."
        fi
    elif ! command -v wget >/dev/null 2>&1; then
        echo "ERROR: wget is not available. Cannot proceed."
        exit 1
    fi

    echo "#######################################################################################"
    echo "#"
    echo "#                                  VPSFREE.ES PteroVM"
    echo "#"
    echo "#                           Copyright (C) 2022 - 2023"
    echo "#"
    echo "#######################################################################################"
    echo ""
    echo "INFO: Auto-selecting Ubuntu (no user input required)..."

    # Always Ubuntu
    wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
    "https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-${ARCH}-pd-v4.18.0.tar.xz"

    echo "INFO: Attempting to install required packages locally (curl, ca-certificates, xz-utils, python3-minimal)..."

    # List of required packages
    REQUIRED_PKGS="curl ca-certificates xz-utils python3-minimal"

    for pkg in $REQUIRED_PKGS; do
        echo "INFO: Downloading $pkg..."
        apt download "$pkg"

        deb_file=$(find "$ROOTFS_DIR" -maxdepth 1 -name "${pkg}_*.deb" -type f -print -quit)
        if [ -n "$deb_file" ]; then
            echo "INFO: Extracting $pkg..."
            dpkg -x "$deb_file" "$HOME/.local/"
            rm "$deb_file"

            # Try to verify the binary is in PATH
            if ! command -v "$pkg" >/dev/null 2>&1; then
                prepend_to_path "$LOCAL_BIN_DIR"
                echo "WARN: $pkg installed but not detected in PATH (might be provided under different name)."
            else
                echo "INFO: $pkg available in PATH."
            fi
        else
            echo "WARN: Failed to download $pkg (not found?)."
        fi
    done

    echo "INFO: Extracting rootfs..."
    tar -xJf /tmp/rootfs.tar.xz -C "$ROOTFS_DIR" --strip-components=1
fi

################################
# Package Installation & Setup #
################################

# Download static proot
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    mkdir -p "$ROOTFS_DIR/usr/local/bin"
    echo "INFO: Downloading proot static binary..."
    proot_path="$ROOTFS_DIR/usr/local/bin/proot"
    proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    
    current_try=0
    max_download_retries=3
    while [ ! -s "$proot_path" ]; do
        current_try=$((current_try + 1))
        if [ "$current_try" -gt "$max_download_retries" ]; then
            echo "ERROR: Failed to download proot. Exiting."
            exit 1
        fi
        wget --tries=$max_retries --timeout=$timeout -O "$proot_path" "$proot_url"
        [ -s "$proot_path" ] || sleep 2
    done
    chmod 755 "$proot_path"
fi

# Clean-up
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"
    rm -rf /tmp/*
    touch "$ROOTFS_DIR/.installed"
fi

###################################################
# systemctl.py (systemctl replacement) Setup      #
###################################################
SYSTEMCTL_PY_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
SYSTEMCTL_PY_INSTALL_DIR="$ROOTFS_DIR/usr/local/bin"
SYSTEMCTL_PY_INSTALL_PATH="$SYSTEMCTL_PY_INSTALL_DIR/systemctl"

echo "INFO: Checking for systemctl.py..."
mkdir -p "$SYSTEMCTL_PY_INSTALL_DIR"
LATEST_VERSION_OUTPUT=$(wget -qO- "$SYSTEMCTL_PY_URL" | grep "__version__ =" | head -n1 | cut -d'"' -f2)

if [ -n "$LATEST_VERSION_OUTPUT" ]; then
    if [ ! -f "$SYSTEMCTL_PY_INSTALL_PATH" ] || ! grep -q "$LATEST_VERSION_OUTPUT" "$SYSTEMCTL_PY_INSTALL_PATH"; then
        wget -O "$SYSTEMCTL_PY_INSTALL_PATH" "$SYSTEMCTL_PY_URL"
        chmod 755 "$SYSTEMCTL_PY_INSTALL_PATH"
        echo "INFO: systemctl.py updated to $LATEST_VERSION_OUTPUT"
    else
        echo "INFO: systemctl.py already up to date."
    fi
fi
echo ""

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
"$ROOTFS_DIR/usr/local/bin/proot" --rootfs="${ROOTFS_DIR}" -0 -n -w "/root" \
    -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit
