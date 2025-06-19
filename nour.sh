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
case "$(uname -m)" in
  x86_64)  ARCH_ALT="amd64" ;;
  aarch64) ARCH_ALT="arm64" ;;
  riscv64) ARCH_ALT="riscv64" ;;
  *)
    echo -e "${BOLD_RED}Unsupported CPU architecture: $(uname -m)${NC}" >&2
    exit 1
    ;;
esac
# --- Dependency Installation ---
if [ ! -f "${ROOTFS_DIR}/.installed" ]; then
  echo -e "${BOLD_YELLOW}First time setup: Installing pkgs...${NC}"
    apt download xz-utils bash curl ca-certificates iproute2 bzip2 sudo
find "$ROOTFS_DIR" -name '*.deb' -type f | while IFS= read -r deb; do
  echo "Unpacking $deb → ~/.local/"
  dpkg -x "$deb" ~/.local/
  echo "Removing $deb"
  rm "$deb"
done
# Install PRoot
    mkdir -p ${ROOTFS_DIR}/usr/local/bin && \
    proot_url="https://github.com/ysdragon/proot-static/releases/download/v${PROOT_VERSION}/proot-${ARCH}-static" && \
    curl -Ls "$proot_url" -o ${ROOTFS_DIR}/usr/local/bin/proot && \
    chmod +x ${ROOTFS_DIR}/usr/local/bin/proot
    # Install files
    urls=(
  "https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/entrypoint.sh"
  "https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/helper.sh"
  "https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/install.sh"
  "https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/run.sh"
)

for url in "${urls[@]}"; do
  curl -O "$url"
done
  fi
  bash entrypoint.sh
