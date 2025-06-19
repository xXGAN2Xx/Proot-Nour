#!/bin/bash
# --- Configuration ---
HOME=/home/container
ROOTFS_DIR="$HOME"
DEBIAN_FRONTEND=noninteractive
PROOT_VERSION=5.4.0
# --- Colors (Consolidated) ---
RED='\033[0;31m'; BOLD_RED='\033[1;31m'
GREEN='\033[0;32m'; BOLD_GREEN='\033[1;32m'
YELLOW='\033[0;33m'; BOLD_YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'
# --- Architecture Check ---
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT="amd64"
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT="arm64"
else
  printf "Unsupported CPU architecture: ${ARCH}"
  exit 1
fi
# --- Dependency Installation ---
if [ ! -f "${ROOTFS_DIR}/.installed" ]; then
  echo -e "${BOLD_YELLOW}First time setup: Installing pkgs...${NC}"
  # Use a temporary file for the download to ensure clean, safe handling.
  DEB_FILE=$(mktemp --suffix=.deb)
  trap 'rm -f "$DEB_FILE"' EXIT # Ensure temp file is deleted even on script error

  XZ_URL="http://ftp.de.debian.org/debian/pool/main/x/xz-utils/xz-utils_5.2.5-2.1~deb11u1_${ARCH_ALT}.deb"
  BASH_URL="http://ftp.de.debian.org/debian/pool/main/b/bash/bash_5.1-2+deb11u1_${ARCH_ALT}.deb"
  
  if curl -Lfo "$DEB_FILE" "$XZ_URL" "BASH_URL"; then
    dpkg -x "$DEB_FILE" "$ROOTFS_DIR/.local/"
    echo -e "${BOLD_GREEN}Installation complete.${NC}"
  else
    echo -e "${BOLD_RED}Failed to download pkgs.${NC}" >&2
    exit 1
  fi
  fi
