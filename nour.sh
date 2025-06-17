#!/bin/sh
# --- Configuration ---
HOME=/home/container
ROOTFS_DIR="$HOME"
# --- Colors (Consolidated) ---
RED='\033[0;31m'; BOLD_RED='\033[1;31m'
GREEN='\033[0;32m'; BOLD_GREEN='\033[1;32m'
YELLOW='\033[0;33m'; BOLD_YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD_BLUE='\033[1;34m'
MAGENTA='\033[0;35m'; BOLD_MAGENTA='\033[1;35m'
CYAN='\033[0;36m'; BOLD_CYAN='\033[1;36m'
WHITE='\033[0;37m'; BOLD_WHITE='\033[1;37m'
NC='\033[0m' # No Color / Reset

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
  echo -e "${BOLD_YELLOW}First time setup: Installing xz-utils...${NC}"
  # Use a temporary file for the download to ensure clean, safe handling.
  DEB_FILE=$(mktemp --suffix=.deb)
  trap 'rm -f "$DEB_FILE"' EXIT # Ensure temp file is deleted even on script error

  XZ_URL="http://ftp.de.debian.org/debian/pool/main/x/xz-utils/xz-utils_5.4.1-1_${ARCH_ALT}.deb"
  
  if curl -Lfo "$DEB_FILE" "$XZ_URL"; then
    dpkg -x "$DEB_FILE" "$ROOTFS_DIR/.local/"
    echo -e "${BOLD_GREEN}Installation complete.${NC}"
  else
    echo -e "${BOLD_RED}Failed to download xz-utils.${NC}" >&2
    exit 1
  fi
################################
# installing script            #
################################

fi
################################
# Package Installation & Setup #
################################
if [ ! -e ${ROOTFS_DIR}/.installed ]; then
PROOT_BINARY="${ROOTFS_DIR}/usr/local/bin/proot"
PROOT_URL="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"

# Create target directory.
mkdir -p "$(dirname "$PROOT_BINARY")"

# Download proot, retrying until the command succeeds and the file is not empty.
until curl -L --fail -o "$PROOT_BINARY" "$PROOT_URL" && [ -s "$PROOT_BINARY" ]; do
    echo "Download failed or file is empty. Retrying in 1 seconds..." >&1
    sleep 1
done
fi

# Clean-up after installation complete & finish up.
if [ ! -e ${ROOTFS_DIR}/.installed ]; then
chmod -R +x "${ROOTFS_DIR}/usr/local/bin" "${ROOTFS_DIR}"
rm -rf /tmp/rootfs.tar.xz /tmp/sbin
touch "${ROOTFS_DIR}/.installed"
fi

# Function to print initial banner
print_banner() {
    printf "\033c"
    printf "${GREEN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                           ${PURPLE}Done (s)! For help, type "help" change this text${GREEN}                            ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                          ${RED}© 2025 - $(date +%Y) ${PURPLE}@xXGAN2Xx${GREEN}                            ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃ INSTALLER OS -> ${RED} $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)${NC}\n"
    printf "${GREEN}┃ CPU -> ${YELLOW} $(cat /proc/cpuinfo | grep 'model name' | cut -d':' -f2- | sed 's/^ *//;s/  \+/ /g' | head -n 1)${NC}\n"
    printf "${GREEN}┃ RAM -> ${BOLD_GREEN}${SERVER_MEMORY}MB${NC}\n"
    printf "${GREEN}┃ PRIMARY PORT -> ${BOLD_GREEN}${SERVER_PORT}${NC}\n"
    printf "${GREEN}┃ EXTRA PORTS -> ${BOLD_GREEN}${P_SERVER_ALLOCATION_LIMIT}${NC}\n"
    printf "${GREEN}┃ LOCATION -> ${BOLD_GREEN}${P_SERVER_LOCATION}${NC}\n"
    printf "${GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
    echo "nameserver 1.1.1.1\nnameserver 1.0.0.1" > "${ROOTFS_DIR}/etc/resolv.conf"
}
###########################
# Start PRoot environment #
###########################
cd /home/container
MODIFIED_STARTUP=$(eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g'))
export INTERNAL_IP=$(ip route get 1 | awk '{print $NF;exit}')
rm -rf ${ROOTFS_DIR}/rootfs.tar.xz /tmp/*
print_banner()
# Execute PRoot environment
    ${ROOTFS_DIR}/usr/local/bin/proot \
    --rootfs="${ROOTFS_DIR}" \
    -0 -w "${ROOTFS_DIR}/root" \
    -b /dev -b /sys -b /proc -b /etc/resolv.conf \
    --kill-on-exit \
    /bin/bash "run.sh" || exit 1
