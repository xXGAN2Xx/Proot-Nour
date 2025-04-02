#!/bin/bash

# --- Configuration ---
UBUNTU_VERSION="jammy" # Ubuntu version codename (e.g., jammy, focal)
ARCH="amd64"           # Architecture (amd64, arm64)
ROOTFS_DIR="ubuntu-rootfs"
PROOT_BINARY="proot"
# Use Termux proot static builds - adjust ARCH if needed
PROOT_URL="https://github.com/xXGAN2Xx/proot-nour/raw/refs/heads/main/proot" # v5.4.0 is latest as of now, check for updates if needed
# URL for Ubuntu Base Rootfs
ROOTFS_URL="http://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-${UBUNTU_VERSION}-base-${ARCH}.tar.gz"
# --- End Configuration ---

# Function to print messages
log() {
    echo "[INFO] $1"
}

# Function to print errors and exit
error_exit() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Check Dependencies ---
log "Checking for necessary tools..."
command -v curl >/dev/null 2>&1 || error_exit "curl is required but not installed."
command -v tar >/dev/null 2>&1 || error_exit "tar is required but not installed."
command -v mkdir >/dev/null 2>&1 || error_exit "mkdir is required."
command -v chmod >/dev/null 2>&1 || error_exit "chmod is required."
log "Dependencies found."

# --- Environment Setup ---
INSTALL_DIR="/home/container" # Standard Pterodactyl directory
cd "$INSTALL_DIR" || error_exit "Cannot change to directory $INSTALL_DIR"
log "Working directory: $(pwd)"

# --- Download proot ---
if [ -f "$PROOT_BINARY" ]; then
    log "Proot binary already exists. Skipping download."
else
    log "Downloading proot for ${ARCH}..."
    curl -L "$PROOT_URL" -o "$PROOT_BINARY" || error_exit "Failed to download proot."
    log "Proot downloaded."
fi

# --- Make proot executable ---
log "Setting execute permissions for proot..."
chmod +x "$PROOT_BINARY" || error_exit "Failed to set execute permissions for proot."
log "Proot is now executable."

# --- Download Ubuntu Rootfs ---
# Check if rootfs directory exists and has content; skip download/extract if so
if [ -d "$ROOTFS_DIR" ] && [ "$(ls -A $ROOTFS_DIR)" ]; then
    log "Rootfs directory '$ROOTFS_DIR' already exists and is not empty. Skipping download and extraction."
else
    log "Creating rootfs directory: $ROOTFS_DIR"
    mkdir -p "$ROOTFS_DIR" || error_exit "Failed to create rootfs directory."

    ROOTFS_TARBALL="ubuntu-base-${UBUNTU_VERSION}-base-${ARCH}.tar.gz"
    log "Downloading Ubuntu ${UBUNTU_VERSION} (${ARCH}) rootfs..."
    curl -L "$ROOTFS_URL" -o "$ROOTFS_TARBALL" || error_exit "Failed to download Ubuntu rootfs."
    log "Ubuntu rootfs downloaded."

    # --- Extract Ubuntu Rootfs ---
    log "Extracting Ubuntu rootfs into ${ROOTFS_DIR}..."
    # Use --no-same-owner because we are likely running as non-root
    tar --no-same-owner -xzf "$ROOTFS_TARBALL" -C "$ROOTFS_DIR" || error_exit "Failed to extract Ubuntu rootfs."
    log "Rootfs extracted."

    # --- Cleanup Tarball ---
    log "Removing rootfs tarball..."
    rm "$ROOTFS_TARBALL"
    log "Tarball removed."
fi

# --- Prepare proot Command ---
log "Preparing to launch Ubuntu environment with proot..."

# Basic necessary bindings for a functional environment
# You might need to add more -b options depending on what you run inside
PROOT_CMD="./${PROOT_BINARY} \
    -S ${ROOTFS_DIR} \
    -b /dev \
    -b /sys \
    -b /proc \
    -b /etc/resolv.conf:/etc/resolv.conf \
    -b /etc/hosts:/etc/hosts \
    -b /tmp \
    -w /root \
    /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin \
    TERM=$TERM \
    LANG=C.UTF-8 \
    /bin/bash --login"

log "--------------------------------------------------"
log "Starting Ubuntu ${UBUNTU_VERSION} environment..."
log "Run 'exit' or press Ctrl+D to leave the proot environment."
log "--------------------------------------------------"

# --- Execute proot ---
eval "$PROOT_CMD"

log "--------------------------------------------------"
log "Exited proot environment."
log "--------------------------------------------------"

exit 0
