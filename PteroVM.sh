#!/bin/bash
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
max_retries=50
timeout=10

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
  install_debian=YES
fi

# Install Debian rootfs if needed
case $install_debian in
  [yY][eE][sS])
    echo "Downloading Debian rootfs..."
    wget --tries=$max_retries --timeout=$timeout --no-hsts -O /tmp/rootfs.tar.gz \
      "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-${ARCH_ALT}.tar.xz"
    
    if [ $? -eq 0 ] && [ -s "/tmp/rootfs.tar.gz" ]; then
      echo "Extracting rootfs..."
      tar -xf /tmp/rootfs.tar.gz -C "$ROOTFS_DIR"
      rm -f /tmp/rootfs.tar.gz
    else
      echo "Failed to download Debian rootfs. Please check your internet connection."
      exit 1
    fi
    ;;
  *)
    echo "Skipping Debian installation."
    ;;
esac

# Download and install proot binary
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  echo "Setting up proot..."
  mkdir -p "$ROOTFS_DIR/usr/local/bin"
  
  # Attempt to download proot with retries
  download_success=false
  for attempt in $(seq 1 $max_retries); do
    echo "Downloading proot (attempt $attempt/$max_retries)..."
    wget --tries=3 --timeout=$timeout --no-hsts -O "$ROOTFS_DIR/usr/local/bin/proot" \
      "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
    
    if [ $? -eq 0 ] && [ -s "$ROOTFS_DIR/usr/local/bin/proot" ]; then
      chmod +x "$ROOTFS_DIR/usr/local/bin/proot"
      download_success=true
      echo "Successfully downloaded proot."
      break
    fi
    
    echo "Download failed, retrying in 1 second..."
    rm -f "$ROOTFS_DIR/usr/local/bin/proot"
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
  rm -rf /tmp/rootfs.tar.xz /tmp/sbin
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
"$ROOTFS_DIR/usr/local/bin/proot" \
  --rootfs="${ROOTFS_DIR}" \
  -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit
