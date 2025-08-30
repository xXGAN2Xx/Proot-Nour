#!/bin/sh
#############################
# Linux Installation #
#############################

ROOTFS_DIR=/home/container
LOCAL_BIN_DIR="$HOME/.local/usr/bin"
max_retries=5
timeout=4

prepend_to_path() {
    local dir_to_add="$1"
    [ -d "$dir_to_add" ] && [[ ":${PATH}:" != *":${dir_to_add}:"* ]] && export PATH="${dir_to_add}:${PATH}"
}

mkdir -p "$LOCAL_BIN_DIR"
prepend_to_path "$LOCAL_BIN_DIR"

ARCH=$(uname -m)
case "$ARCH" in
    "x86_64") ARCH_ALT="amd64" ;;
    "aarch64") ARCH_ALT="arm64" ;;
    *) echo "Unsupported CPU architecture: $ARCH" && exit 1 ;;
esac

# Check if rootfs is already installed
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    echo "INFO: Attempting to install wget locally..."
    apt download wget
    deb_file_wget=$(find "$ROOTFS_DIR" -maxdepth 1 -name "wget_*.deb" -type f -print -quit)
    if [ -n "$deb_file_wget" ]; then
        dpkg -x "$deb_file_wget" "$HOME/.local/"
        rm "$deb_file_wget"
    fi

    # Check and download rootfs only if needed
    echo "INFO: Downloading rootfs..."
    wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
    "https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-${ARCH}-pd-v4.18.0.tar.xz"

    # Install packages in parallel
    REQUIRED_PKGS="curl ca-certificates xz-utils python3-minimal"
    echo "INFO: Installing required packages..."
    echo "$REQUIRED_PKGS" | xargs -n 1 -P 4 apt-get install -y

    # Extract rootfs
    echo "INFO: Extracting rootfs..."
    tar -xJf /tmp/rootfs.tar.xz -C "$ROOTFS_DIR" --strip-components=1
fi

# Download proot only if needed
if [ ! -e "$ROOTFS_DIR/usr/local/bin/proot" ]; then
    echo "INFO: Downloading proot binary..."
    wget --tries=$max_retries --timeout=$timeout -O "$ROOTFS_DIR/usr/local/bin/proot" \
        "https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    chmod 755 "$ROOTFS_DIR/usr/local/bin/proot"
fi

# Final setup
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"
    touch "$ROOTFS_DIR/.installed"
fi

# Systemctl.py setup
SYSTEMCTL_PY_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
SYSTEMCTL_PY_INSTALL_PATH="$ROOTFS_DIR/usr/local/bin/systemctl"
echo "INFO: Checking for systemctl.py..."
LATEST_VERSION_OUTPUT=$(wget -qO- "$SYSTEMCTL_PY_URL" | grep "__version__ =" | head -n1 | cut -d'"' -f2)
[ -n "$LATEST_VERSION_OUTPUT" ] && wget -O "$SYSTEMCTL_PY_INSTALL_PATH" "$SYSTEMCTL_PY_URL"

# Display headers, resources, and footer
display_header
display_resources
display_footer

# Start PRoot environment
"$ROOTFS_DIR/usr/local/bin/proot" --rootfs="${ROOTFS_DIR}" -0 -n -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
    /bin/bash -lc 'export DEBIAN_FRONTEND=noninteractive; apt-get update || true; apt-get install -y tmate screen || true; exec tmate -F'
