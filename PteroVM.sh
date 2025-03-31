#!/bin/bash

set -e  # Exit on error

ROOTFS_DIR="$(pwd)"
export PATH="$PATH:$HOME/.local/usr/bin"
MAX_RETRIES=50
TIMEOUT=1

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)   ARCH_ALT="amd64" ;;
  aarch64)  ARCH_ALT="arm64" ;;
  armv7l|armv7) ARCH_ALT="armhf" ;;
  ppc64le)  ARCH_ALT="ppc64el" ;;
  riscv64)  ARCH_ALT="riscv64" ;;
  s390x)    ARCH_ALT="s390x" ;;
  *)
    echo "Unsupported CPU architecture: $ARCH"
    exit 1
    ;;
esac

# If not installed, begin installation
if [ ! -f "$ROOTFS_DIR/.installed" ]; then
  echo "#######################################################################################"
  echo "#"
  echo "#                                      NOUR INSTALLER"
  echo "#"
  echo "#                           Copyright (C) 2024, RecodeStudios.Cloud"
  echo "#"
  echo "#######################################################################################"

  INSTALL_UBUNTU="yes"
fi

# Download and extract Ubuntu rootfs
if [[ "$INSTALL_UBUNTU" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
  echo "[*] Downloading Ubuntu rootfs..."
  wget --tries="$MAX_RETRIES" --timeout="$TIMEOUT" --no-hsts -O /tmp/rootfs.tar.gz \
    "https://partner-images.canonical.com/core/focal/current/ubuntu-focal-core-cloudimg-${ARCH_ALT}-root.tar.gz"

  echo "[*] Extracting rootfs..."
  tar -xf /tmp/rootfs.tar.gz -C "$ROOTFS_DIR"
else
  echo "[*] Skipping Ubuntu installation."
fi

# Download proot binary
if [ ! -f "$ROOTFS_DIR/.installed" ]; then
  echo "[*] Downloading proot binary..."
  mkdir -p "$ROOTFS_DIR/usr/local/bin"

  PROOT_URL="https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
  PROOT_BIN="$ROOTFS_DIR/usr/local/bin/proot"

  while true; do
    wget --tries="$MAX_RETRIES" --timeout="$TIMEOUT" --no-hsts -O "$PROOT_BIN" "$PROOT_URL"

    if [ -s "$PROOT_BIN" ]; then
      chmod +x "$PROOT_BIN"
      break
    else
      echo "[!] proot download failed or file is empty. Retrying..."
      rm -f "$PROOT_BIN"
      sleep 1
    fi
  done
fi

# Finalize installation
if [ ! -f "$ROOTFS_DIR/.installed" ]; then
  echo "[*] Finalizing installation..."

  mkdir -p "$ROOTFS_DIR/etc"
  echo -e "nameserver 1.1.1.1\nnameserver 1.0.0.1" > "$ROOTFS_DIR/etc/resolv.conf"

  rm -f /tmp/rootfs.tar.gz
  touch "$ROOTFS_DIR/.installed"
fi

# Colors
CYAN='\e[0;36m'
WHITE='\e[0;37m'
RESET_COLOR='\e[0m'

# Display success message
display_success() {
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
  echo -e ""
  echo -e "           ${CYAN}-----> Mission Completed ! <----${RESET_COLOR}"
  echo -e ""
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
}

clear
display_success

# Run proot
exec "$ROOTFS_DIR/usr/local/bin/proot" \
  --rootfs="$ROOTFS_DIR" \
  -0 -w "/root" \
  -b /dev -b /sys -b /proc -b /etc/resolv.conf \
  --kill-on-exit
