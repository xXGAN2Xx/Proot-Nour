#!/bin/bash

# --- Configuration ---
# Directory to store the extracted Ubuntu rootfs
ROOTFS_DIR="ubuntu-rootfs"
# Directory to store the proot binary
PROOT_DIR="proot-bin"
# Ubuntu Rootfs Tarball URL (Minimal Jammy AMD64)
# You can find others here: https://cloud-images.ubuntu.com/minimal/releases/
# Ensure you pick the right architecture (amd64, arm64, etc.)
# Using .tar.gz instead of .tar.xz to avoid dependency on 'xz' if not present
ROOTFS_URL="https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64-root.tar.gz"
ROOTFS_TARBALL="ubuntu-rootfs.tar.gz"
# Proot Static Binary URL (Termux provides static builds - check for latest versions/architectures)
# Check releases: https://github.com/termux/proot/releases
# Ensure you pick the right architecture (x86_64 corresponds to amd64)
PROOT_URL="https://github.com/termux/proot/releases/download/v5.4.0/proot-v5.4.0-x86_64-static"
PROOT_BINARY="proot"

# --- Helper Function for Downloading ---
download() {
  local url=$1
  local output=$2
  echo "Attempting to download $url to $output..."
  if command -v curl &> /dev/null; then
    curl -L -o "$output" "$url"
  elif command -v wget &> /dev/null; then
    wget -O "$output" "$url"
  else
    echo "Error: Neither curl nor wget is available. Cannot download files."
    exit 1
  fi
  # Check if download was successful (basic check: file exists and is not empty)
  if [ -s "$output" ]; then
    echo "Download successful."
  else
    echo "Error: Download failed or resulted in an empty file."
    # Clean up potentially empty file
    rm -f "$output"
    exit 1
 fi
}


# --- Main Execution ---
echo "--- Starting Ubuntu Proot Setup ---"

# 1. Create directories
echo "[1/5] Creating directories..."
mkdir -p "$ROOTFS_DIR"
mkdir -p "$PROOT_DIR"
echo "Directories created."

# 2. Download Ubuntu Rootfs
echo "[2/5] Downloading Ubuntu Rootfs..."
if [ -f "$ROOTFS_TARBALL" ]; then
    echo "Rootfs tarball ($ROOTFS_TARBALL) already exists. Skipping download."
else
    download "$ROOTFS_URL" "$ROOTFS_TARBALL"
fi

# 3. Download Proot
echo "[3/5] Downloading Proot..."
PROOT_PATH="$PROOT_DIR/$PROOT_BINARY"
if [ -f "$PROOT_PATH" ]; then
    echo "Proot binary ($PROOT_PATH) already exists. Skipping download."
else
    download "$PROOT_URL" "$PROOT_PATH"
fi

# 4. Extract Rootfs
echo "[4/5] Extracting Ubuntu Rootfs..."
# Check if extraction is needed (e.g., if a key file like 'etc/os-release' exists)
if [ -f "$ROOTFS_DIR/etc/os-release" ]; then
    echo "Rootfs seems already extracted in $ROOTFS_DIR. Skipping extraction."
else
    # Clear directory before extracting in case of partial previous extraction
    rm -rf "${ROOTFS_DIR:?}"/* # Safety check: only proceed if ROOTFS_DIR is set and not empty
    echo "Extracting $ROOTFS_TARBALL to $ROOTFS_DIR..."
    if tar -xzf "$ROOTFS_TARBALL" -C "$ROOTFS_DIR"; then
        echo "Extraction successful."
    else
        echo "Error: Extraction failed."
        exit 1
    fi
fi

# 5. Prepare and Launch Proot
echo "[5/5] Preparing and launching Proot..."
# Make proot executable
chmod +x "$PROOT_PATH"
echo "Made proot executable."

# Set up necessary resolv.conf for networking inside proot
# Pterodactyl often uses 1.1.1.1 or Google DNS. Copying host's might work too.
# If /etc/resolv.conf is not readable, create a basic one.
mkdir -p "$ROOTFS_DIR/etc"
if [ -r "/etc/resolv.conf" ]; then
    cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
    echo "Copied host /etc/resolv.conf to rootfs."
else
    echo "nameserver 1.1.1.1" > "$ROOTFS_DIR/etc/resolv.conf"
    echo "nameserver 8.8.8.8" >> "$ROOTFS_DIR/etc/resolv.conf"
    echo "Created basic /etc/resolv.conf in rootfs."
fi


echo "--- Setup Complete ---"
echo "Launching Ubuntu environment via Proot..."
echo "You can exit the proot environment by typing 'exit'."
echo "-----------------------------------------"

# Execute proot
# -S $ROOTFS_DIR: Sets the root directory for the proot environment
# --bind mounts directories from the host system into the proot environment
# /usr/bin/env -i: Starts a clean environment, clearing most variables
# We explicitly set HOME, PATH, and TERM for a usable shell
# /bin/bash --login: Starts a login shell in bash
"$PROOT_PATH" \
    -S "$ROOTFS_DIR" \
    -b /dev \
    -b /proc \
    -b /sys \
    -b /dev/pts \
    -b /tmp \
    -b /etc/resolv.conf:/etc/resolv.conf \
    -b $HOME \
    -w /root \
    /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/bash --login

echo "--- Proot session finished ---"
