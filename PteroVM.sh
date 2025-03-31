#!/bin/bash
# Ubuntu rootfs installer with improved error handling and robustness

# Set up environment
ROOTFS_DIR=$(pwd)
export PATH=$PATH:~/.local/usr/bin
MAX_RETRIES=5
DOWNLOAD_TIMEOUT=30
RETRY_WAIT=3

# Log function for consistent output
log() {
  local level=$1
  local message=$2
  local color=""
  local reset="\e[0m"

  case $level in
    "INFO")  color="\e[0;32m" ;;  # Green
    "WARN")  color="\e[0;33m" ;;  # Yellow
    "ERROR") color="\e[0;31m" ;;  # Red
    "TITLE") color="\e[0;36m" ;;  # Cyan
  esac

  echo -e "${color}[$level] $message${reset}"
}

display_banner() {
  echo "######################################################################################"
  echo "#"
  echo "#                                   NOUR INSTALLER"
  echo "#"
  echo "#                        Copyright (C) 2024, RecodeStudios.Cloud"
  echo "#"
  echo "######################################################################################"
  echo ""
}

# Determine system architecture
determine_architecture() {
  ARCH=$(uname -m)
  case "$ARCH" in
    "x86_64")   ARCH_ALT="amd64" ;;
    "aarch64")  ARCH_ALT="arm64" ;;
    "armv7l"|"armv7") ARCH_ALT="armhf" ;;
    "ppc64le")  ARCH_ALT="ppc64el" ;;
    "riscv64")  ARCH_ALT="riscv64" ;;
    "s390x")    ARCH_ALT="s390x" ;;
    *)
      log "ERROR" "Unsupported CPU architecture: ${ARCH}"
      exit 1
      ;;
  esac
  log "INFO" "Detected architecture: ${ARCH} (${ARCH_ALT})"
}

# Download function with retries and proper error handling
download_file() {
  local url=$1
  local destination=$2
  local attempt=1

  while [ $attempt -le $MAX_RETRIES ]; do
    log "INFO" "Download attempt $attempt/$MAX_RETRIES: $(basename "$url")"
    
    if wget --tries=3 --timeout=$DOWNLOAD_TIMEOUT --no-hsts -q --show-progress -O "$destination" "$url"; then
      if [ -s "$destination" ]; then
        log "INFO" "Download successful: $(basename "$destination")"
        return 0
      else
        log "WARN" "Downloaded file is empty, retrying..."
      fi
    else
      log "WARN" "Download failed with code $?, retrying in $RETRY_WAIT seconds..."
    fi
    
    rm -f "$destination"
    sleep $RETRY_WAIT
    attempt=$((attempt + 1))
  done
  
  log "ERROR" "Failed to download after $MAX_RETRIES attempts"
  return 1
}

# Extract tar with error handling
extract_tar() {
  local archive=$1
  local target=$2
  
  log "INFO" "Extracting $(basename "$archive") to $target"
  
  if tar -xf "$archive" -C "$target"; then
    log "INFO" "Extraction completed successfully"
    return 0
  else
    log "ERROR" "Extraction failed with code $?"
    return 1
  fi
}

# Install Ubuntu
install_ubuntu() {
  local rootfs_archive="/tmp/rootfs.tar.gz"
  
  # Use the correct URL for the detected architecture
  local download_url="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-${ARCH_ALT}-azure.vhd.tar.gz"
  
  log "INFO" "Starting Ubuntu installation process"
  
  # Download Ubuntu rootfs
  if ! download_file "$download_url" "$rootfs_archive"; then
    log "ERROR" "Failed to download Ubuntu rootfs"
    return 1
  fi
  
  # Extract the archive
  if ! extract_tar "$rootfs_archive" "$ROOTFS_DIR"; then
    log "ERROR" "Failed to extract Ubuntu rootfs"
    return 1
  fi
  
  # Clean up archive
  rm -f "$rootfs_archive"
  log "INFO" "Ubuntu installation completed"
  return 0
}

# Install proot
install_proot() {
  local proot_dir="$ROOTFS_DIR/usr/local/bin"
  local proot_path="$proot_dir/proot"
  local proot_url="https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
  
  # Create directory if it doesn't exist
  mkdir -p "$proot_dir"
  
  log "INFO" "Installing proot binary"
  
  # Download proot
  if ! download_file "$proot_url" "$proot_path"; then
    log "ERROR" "Failed to download proot"
    return 1
  fi
  
  # Make executable
  chmod +x "$proot_path"
  log "INFO" "Proot installation completed"
  return 0
}

# Configure the system
configure_system() {
  log "INFO" "Configuring system"
  
  # Set DNS
  printf "nameserver 1.1.1.1\nnameserver 1.0.0.1" > "${ROOTFS_DIR}/etc/resolv.conf"
  
  # Mark as installed
  touch "$ROOTFS_DIR/.installed"
  
  log "INFO" "System configuration completed"
}

# Display completion message
display_completion() {
  local CYAN='\e[0;36m'
  local WHITE='\e[0;37m'
  local RESET_COLOR='\e[0m'
  
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
  echo -e ""
  echo -e "           ${CYAN}-----> Mission Completed ! <----${RESET_COLOR}"
  echo -e ""
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
}

# Start proot session
start_proot() {
  log "INFO" "Starting proot session"
  
  "$ROOTFS_DIR/usr/local/bin/proot" \
    --rootfs="${ROOTFS_DIR}" \
    -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit
}

# Main execution flow
main() {
  clear
  display_banner
  determine_architecture
  
  # Check if already installed
  if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    # Ask for confirmation
    read -p "Install Ubuntu? (YES/no): " install_ubuntu
    install_ubuntu=${install_ubuntu:-YES}
    
    case $install_ubuntu in
      [yY][eE][sS])
        if ! install_ubuntu; then
          log "ERROR" "Ubuntu installation failed"
          exit 1
        fi
        
        if ! install_proot; then
          log "ERROR" "Proot installation failed"
          exit 1
        fi
        
        configure_system
        ;;
      *)
        log "INFO" "Skipping Ubuntu installation."
        ;;
    esac
  else
    log "INFO" "System already installed, proceeding to start"
  fi
  
  clear
  display_completion
  start_proot
}

# Run the script
main
