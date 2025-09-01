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

# --- IMPROVEMENT: Updated architecture check for x86_64, aarch64, and arm ---
# Detect the machine architecture.
ARCH=$(uname -m)

# Check for supported architectures and standardize the name if needed.
case "$ARCH" in
    x86_64)
        echo "INFO: Detected x86_64 (64-bit) architecture."
        ;;
    aarch64)
        echo "INFO: Detected aarch64 (64-bit) architecture."
        ;;
    arm | armv7l | armv8l)
        ARCH="arm" # Standardize to 'arm' for consistency in download URLs
        echo "INFO: Detected arm (32-bit) architecture."
        ;;
    *)
        printf "Unsupported CPU architecture: %s\n" "$ARCH"
        exit 1
        ;;
esac
# --- END IMPROVEMENT ---

# Download & decompress the Linux root file system if not already installed.
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    echo "#######################################################################################"
    echo "#"
    echo "#                                  Nour PteroVM"
    echo "#"
    echo "#######################################################################################"
    echo ""
    echo "INFO: Auto-selecting Ubuntu (no user input required)..."

    # Consolidated package download
    BOOTSTRAP_PKGS="wget bash ca-certificates xz-utils python3-minimal"
    echo "INFO: Attempting to install required bootstrap packages locally: $BOOTSTRAP_PKGS"

    if ! apt download $BOOTSTRAP_PKGS; then
        echo "ERROR: Failed to download one or more bootstrap packages. Cannot proceed."
        exit 1
    fi

    find "$ROOTFS_DIR" -maxdepth 1 -name "*.deb" -type f -print0 | while IFS= read -r -d '' deb_file; do
        echo "INFO: Extracting $(basename "$deb_file")..."
        dpkg -x "$deb_file" "$HOME/.local/"
        rm "$deb_file"
    done

    prepend_to_path "$LOCAL_BIN_DIR"

    if ! command -v wget >/dev/null 2>&1; then
        echo "ERROR: wget could not be installed or found in PATH. Cannot proceed."
        exit 1
    fi

    # Download Ubuntu rootfs
    wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
    "https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-${ARCH}-pd-v4.18.0.tar.xz"

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
SYSTEMCTL_PY_TEMP_PATH="/tmp/systemctl.py"

echo "INFO: Checking for systemctl.py..."
mkdir -p "$SYSTEMCTL_PY_INSTALL_DIR"

if ! wget -qO "$SYSTEMCTL_PY_TEMP_PATH" "$SYSTEMCTL_PY_URL"; then
    echo "WARN: Could not download systemctl.py to check for updates."
else
    LATEST_VERSION=$(grep "__version__ =" "$SYSTEMCTL_PY_TEMP_PATH" | head -n1 | cut -d'"' -f2)

    if [ -n "$LATEST_VERSION" ]; then
        if [ ! -f "$SYSTEMCTL_PY_INSTALL_PATH" ] || ! grep -q "$LATEST_VERSION" "$SYSTEMCTL_PY_INSTALL_PATH"; then
            echo "INFO: Installing/updating systemctl.py to version $LATEST_VERSION"
            mv "$SYSTEMCTL_PY_TEMP_PATH" "$SYSTEMCTL_PY_INSTALL_PATH"
            chmod 755 "$SYSTEMCTL_PY_INSTALL_PATH"
        else
            echo "INFO: systemctl.py is already up to date."
            rm "$SYSTEMCTL_PY_TEMP_PATH"
        fi
    else
        echo "WARN: Could not determine latest version of systemctl.py."
        rm "$SYSTEMCTL_PY_TEMP_PATH"
    fi
fi
echo ""

###################################################
# Fancy Output                                    #
###################################################
GREEN='\e[0;32m'; RED='\e[0;31m'; YELLOW='\e[0;33m'; MAGENTA='\e[0;35m'; RESET='\e[0m'

display_header() {
    cat << EOF
${MAGENTA} __      __        ______
 \\ \\    / /       |  ____|
  \\ \\  / / __  ___| |__ _ __ ___  ___
   \\ \\/ / '_ \\/ __|  __| '__/ _ \\/ _ \\
    \\  /| |_) \\__ \\ |  | | |  __/  __/
     \\/ | .__/|___/_|  |_|  \\___\\___|
        | |
        |_|${RESET}
___________________________________________________
           ${YELLOW}-----> System Resources <----${RESET}
Installation complete! For help, type 'help'
EOF
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
    -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
    /bin/bash -lc 'export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y && apt-get install -y tmate screen || echo "WARNING: Failed to install tmate/screen."; \
    exec tmate -F'
