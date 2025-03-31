#!/bin/bash
ROOTFS_DIR=$(pwd)
PROOT_DIR="$ROOTFS_DIR/.proot"
mkdir -p "$PROOT_DIR/bin"

max_retries=50
timeout=1

# Set Ubuntu version
UBUNTU_VERSION="22.04.5"  # Ubuntu 22.04 LTS
UBUNTU_CODENAME="jammy"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT=amd64
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT=arm64
elif [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "armv7" ]; then
  ARCH_ALT=armhf
elif [ "$ARCH" = "ppc64le" ]; then
  ARCH_ALT=ppc64el
elif [ "$ARCH" = "riscv64" ]; then
  ARCH_ALT=riscv64
elif [ "$ARCH" = "s390x" ]; then
  ARCH_ALT=s390x
else
  printf "Unsupported CPU architecture: ${ARCH}\n"
  exit 1
fi

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
case $install_ubuntu in
  [yY][eE][sS])
    echo "Downloading Ubuntu rootfs..."
    wget --tries=$max_retries --timeout=$timeout --no-hsts -O /tmp/rootfs.tar.gz \
      "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64-azure.vhd.tar.gz"
      
    if [ $? -eq 0 ] && [ -s "/tmp/rootfs.tar.gz" ]; then
      echo "Extracting rootfs..."
      mkdir -p "$ROOTFS_DIR"
      tar -xf /tmp/rootfs.tar.gz -C "$ROOTFS_DIR"
      rm -f /tmp/rootfs.tar.gz
    else
      echo "Failed to download Ubuntu rootfs. Please check your internet connection."
      exit 1
    fi
    ;;
  *)
    echo "Skipping Ubuntu installation."
    ;;
esac

# Download and install proot binary
if [ ! -e "$PROOT_DIR/bin/proot" ]; then
  echo "Setting up proot..."
  mkdir -p "$PROOT_DIR/bin"
  
  # Attempt to download proot with retries
  download_success=false
  for attempt in $(seq 1 $max_retries); do
    echo "Downloading proot (attempt $attempt/$max_retries)..."
    wget --tries=3 --timeout=$timeout --no-hsts -O "$PROOT_DIR/bin/proot" \
      "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
    
    if [ $? -eq 0 ] && [ -s "$PROOT_DIR/bin/proot" ]; then
      chmod +x "$PROOT_DIR/bin/proot"
      download_success=true
      echo "Successfully downloaded proot."
      break
    fi
    
    echo "Download failed, retrying in 1 second..."
    rm -f "$PROOT_DIR/bin/proot"
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
  printf "nameserver 1.1.1.1\nnameserver 1.0.0.1" > "${ROOTFS_DIR}/etc/resolv.conf"
  rm -rf /tmp/rootfs.tar.gz /tmp/sbin
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

# Start proot
echo "Starting proot environment..."
"$PROOT_DIR/bin/proot" \
  --rootfs="${ROOTFS_DIR}" \
  -0 -w "/root" \
  -b /dev -b /sys -b /proc \
  -b /etc/resolv.conf \
  -b /dev/shm \
  -b /run \
  -b /tmp \
  --kill-on-exit
