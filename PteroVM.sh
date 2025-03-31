#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Configuration variables
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
max_retries=50
timeout=5  # Increased timeout for better reliability
download_attempts=3
PROOT_URL="https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
LOG_FILE="${ROOTFS_DIR}/installation.log"

# Color definitions
CYAN='\e[0;36m'
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
RED='\e[0;31m'
WHITE='\e[0;37m'
RESET_COLOR='\e[0m'

# Function to log messages
log_message() {
  local level="$1"
  local message="$2"
  local color="$WHITE"
  
  case "$level" in
    "INFO") color="$WHITE" ;;
    "SUCCESS") color="$GREEN" ;;
    "WARNING") color="$YELLOW" ;;
    "ERROR") color="$RED" ;;
  esac
  
  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message${RESET_COLOR}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

# Function to check command availability
check_command() {
  command -v "$1" >/dev/null 2>&1 || { 
    log_message "ERROR" "Required command '$1' not found. Please install it and try again."
    exit 1
  }
}

# Function to download a file with retries
download_with_retry() {
  local url="$1"
  local output_file="$2"
  local success=false
  
  for attempt in $(seq 1 $max_retries); do
    log_message "INFO" "Downloading from $url (attempt $attempt/$max_retries)..."
    
    if wget --tries=$download_attempts --timeout=$timeout --no-hsts --quiet --show-progress -O "$output_file" "$url"; then
      if [ -s "$output_file" ]; then
        log_message "SUCCESS" "Download completed successfully."
        success=true
        break
      else
        log_message "WARNING" "Downloaded file is empty. Retrying..."
        rm -f "$output_file"
      fi
    else
      log_message "WARNING" "Download failed. Retrying in 2 seconds..."
      rm -f "$output_file"
      sleep 2
    fi
  done
  
  if [ "$success" != "true" ]; then
    log_message "ERROR" "Failed to download after $max_retries attempts."
    return 1
  fi
  
  return 0
}

# Check for required commands
check_command wget
check_command tar

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
log_message "INFO" "Starting installation process"

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
  log_message "ERROR" "Unsupported CPU architecture: ${ARCH}"
  exit 1
fi
log_message "INFO" "Detected architecture: ${ARCH} (${ARCH_ALT})"

# Check if already installed
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  echo "#######################################################################################"
  echo "#"
  echo "#                                      NOUR INSTALLER"
  echo "#"
  echo "#                           Copyright (C) 2024, RecodeStudios.Cloud"
  echo "#"
  echo "#######################################################################################"
  
  # Prompt for installation if not forced
  if [ -z "$install_ubuntu" ]; then
    read -p "Do you want to install Ubuntu rootfs? (yes/no): " install_ubuntu
  fi
else
  log_message "INFO" "Installation already completed. Skipping setup."
  install_ubuntu="NO"
fi

# Install Ubuntu rootfs if needed
case $install_ubuntu in
  [yY][eE][sS]|[yY])
    UBUNTU_URL="https://partner-images.canonical.com/core/focal/current/ubuntu-focal-core-cloudimg-${ARCH_ALT}-root.tar.gz"
    log_message "INFO" "Starting Ubuntu rootfs download from $UBUNTU_URL"
    
    if download_with_retry "$UBUNTU_URL" "/tmp/rootfs.tar.gz"; then
      log_message "INFO" "Extracting Ubuntu rootfs to $ROOTFS_DIR..."
      
      # Create a backup of existing files if directory is not empty
      if [ "$(ls -A "$ROOTFS_DIR" 2>/dev/null)" ]; then
        log_message "INFO" "Creating backup of existing files..."
        mkdir -p "${ROOTFS_DIR}.backup"
        cp -r "$ROOTFS_DIR"/* "${ROOTFS_DIR}.backup/"
      fi
      
      # Extract with progress indication
      tar -xf "/tmp/rootfs.tar.gz" -C "$ROOTFS_DIR" || {
        log_message "ERROR" "Failed to extract rootfs archive."
        exit 1
      }
      
      log_message "SUCCESS" "Ubuntu rootfs extracted successfully."
      rm -f "/tmp/rootfs.tar.gz"
    else
      log_message "ERROR" "Failed to download Ubuntu rootfs. Exiting."
      exit 1
    fi
    ;;
  *)
    log_message "INFO" "Skipping Ubuntu installation."
    ;;
esac

# Download and install proot binary
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  log_message "INFO" "Setting up proot binary..."
  mkdir -p "$ROOTFS_DIR/usr/local/bin"
  
  if download_with_retry "$PROOT_URL" "$ROOTFS_DIR/usr/local/bin/proot"; then
    chmod +x "$ROOTFS_DIR/usr/local/bin/proot"
    log_message "SUCCESS" "Proot binary installed successfully."
  else
    log_message "ERROR" "Failed to download proot binary. Exiting."
    exit 1
  fi
fi

# Final setup
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  log_message "INFO" "Finalizing installation..."
  
  # Set up DNS
  printf "nameserver 1.1.1.1\nnameserver 1.0.0.1" > "${ROOTFS_DIR}/etc/resolv.conf"
  
  # Set up basic configuration
  if [ -f "/etc/hostname" ]; then
    cp "/etc/hostname" "${ROOTFS_DIR}/etc/hostname"
  else
    echo "proot-container" > "${ROOTFS_DIR}/etc/hostname"
  fi
  
  # Create essential directories
  mkdir -p "${ROOTFS_DIR}/root"
  mkdir -p "${ROOTFS_DIR}/tmp"
  chmod 1777 "${ROOTFS_DIR}/tmp"
  
  # Clean up temporary files
  rm -rf /tmp/rootfs.tar.xz /tmp/sbin
  
  # Mark as installed
  touch "$ROOTFS_DIR/.installed"
  log_message "SUCCESS" "Installation completed successfully."
fi

# Display completion message
display_gg() {
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
  echo -e ""
  echo -e "           ${CYAN}-----> Mission Completed ! <----${RESET_COLOR}"
  echo -e ""
  echo -e "${GREEN} Ubuntu rootfs and proot are now set up.${RESET_COLOR}"
  echo -e "${WHITE} You are about to enter the proot environment.${RESET_COLOR}"
  echo -e "${WHITE} Installation Log: ${LOG_FILE}${RESET_COLOR}"
  echo -e ""
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
}

clear
display_gg

# Start proot with additional mounts for better compatibility
log_message "INFO" "Starting proot environment..."
exec "$ROOTFS_DIR/usr/local/bin/proot" \
  --rootfs="${ROOTFS_DIR}" \
  --link2symlink \
  -0 \
  -w "/root" \
  -b /dev \
  -b /proc \
  -b /sys \
  -b /etc/resolv.conf:/etc/resolv.conf \
  -b /tmp:/tmp \
  -b "$ROOTFS_DIR/.installed:/root/.installed" \
  -b "$LOG_FILE:/root/installation.log" \
  --kill-on-exit
