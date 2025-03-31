#!/bin/bash
set -e  # Exit immediately if a command exits with non-zero status

# Define directory variables
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
max_retries=50
timeout=5

# Set Ubuntu version
UBUNTU_VERSION="22.04.5"  # Ubuntu 22.04 LTS
UBUNTU_CODENAME="jammy"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  "x86_64")  ARCH_ALT=amd64 ;;
  "aarch64") ARCH_ALT=arm64 ;;
  "armv7l"|"armv7") ARCH_ALT=armhf ;;
  "ppc64le") ARCH_ALT=ppc64el ;;
  "riscv64") ARCH_ALT=riscv64 ;;
  "s390x")   ARCH_ALT=s390x ;;
  *)
    printf "Unsupported CPU architecture: ${ARCH}\n"
    exit 1
    ;;
esac

# Create required directories
mkdir -p "$ROOTFS_DIR"

# Check if already installed
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  echo "#######################################################################################"
  echo "#"
  echo "#                                      NOUR INSTALLER"
  echo "#"
  echo "#                           Copyright (C) 2024, RecodeStudios.Cloud"
  echo "#"
  echo "#######################################################################################"
  install_ubuntu=YES
fi

# Install Ubuntu rootfs if needed
if [ "$install_ubuntu" = "YES" ]; then
  echo "Downloading Ubuntu rootfs..."
  
  # Create a temporary directory for downloads
  TMP_DIR=$(mktemp -d)
  ROOTFS_TAR="$TMP_DIR/rootfs.tar.gz"
  
  wget --tries=$max_retries --timeout=$timeout --no-hsts -O "$ROOTFS_TAR" \
    "http://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-${UBUNTU_VERSION}-base-${ARCH_ALT}.tar.gz"
  
  if [ $? -eq 0 ] && [ -s "$ROOTFS_TAR" ]; then
    echo "Extracting rootfs..."
    tar -xf "$ROOTFS_TAR" -C "$ROOTFS_DIR"
    rm -f "$ROOTFS_TAR"
  else
    echo "Failed to download Ubuntu rootfs. Please check your internet connection."
    rm -rf "$TMP_DIR"
    exit 1
  fi
  
  rm -rf "$TMP_DIR"
else
  echo "Skipping Ubuntu installation."
fi

# Download and install proot binary
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  echo "Setting up proot..."
  PROOT_DIR="$ROOTFS_DIR/usr/local/bin"
  mkdir -p "$PROOT_DIR"
  
  # Attempt to download proot with retries
  download_success=false
  for attempt in $(seq 1 $max_retries); do
    echo "Downloading proot (attempt $attempt/$max_retries)..."
    wget --tries=3 --timeout=$timeout --no-hsts -O "$PROOT_DIR/proot" \
      "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
    
    if [ $? -eq 0 ] && [ -s "$PROOT_DIR/proot" ]; then
      chmod +x "$PROOT_DIR/proot"
      download_success=true
      echo "Successfully downloaded proot."
      break
    fi
    
    echo "Download failed, retrying in 1 second..."
    rm -f "$PROOT_DIR/proot"
    sleep 1
  done
  
  if [ "$download_success" != "true" ]; then
    echo "Failed to download proot after $max_retries attempts. Exiting."
    exit 1
  fi
fi

# Final setup
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  echo "Finalizing installation..."
  # Backup existing resolv.conf if it exists
  if [ -e "${ROOTFS_DIR}/etc/resolv.conf" ]; then
    cp "${ROOTFS_DIR}/etc/resolv.conf" "${ROOTFS_DIR}/etc/resolv.conf.bak"
  fi
  
  # Configure DNS
  printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"
  
  # Mark as installed
  touch "$ROOTFS_DIR/.installed"
fi

# Display completion message
CYAN='\e[0;36m'
WHITE='\e[0;37m'
RESET_COLOR='\e[0m'
display_gg() {
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
  echo -e ""
  echo -e "           ${CYAN}-----> Mission Completed ! <----${RESET_COLOR}"
  echo -e ""
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
}

clear
display_gg

# Start proot with the correct path
echo "Starting proot environment..."
PROOT_BIN="$ROOTFS_DIR/usr/local/bin/proot"

if [ ! -x "$PROOT_BIN" ]; then
  echo "Error: proot binary not found or not executable at $PROOT_BIN"
  exit 1
fi

"$PROOT_BIN" \
  --rootfs="$ROOTFS_DIR" \
  -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit
