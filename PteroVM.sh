#!/bin/sh

# Exit immediately if a command exits with a non-zero status.
set -e

# === Configuration ===
ROOTFS_DIR="./nour" # Directory for the Ubuntu rootfs
PROOT_URL="https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot" # URL for the proot binary
ROOTFS_BASE_URL="https://raw.githubusercontent.com/EXALAB/Anlinux-Resources/refs/heads/master/Rootfs/Ubuntu" # Base URL for rootfs downloads
MAX_RETRIES=5 # Number of retries for wget
TIMEOUT=30 # Timeout for wget in seconds

# === Environment Setup ===
# Add ~/.local/usr/bin to PATH if it exists, for tools like xz
if [ -d "$HOME/.local/usr/bin" ]; then
  export PATH="$HOME/.local/usr/bin:$PATH"
fi

# === Architecture Detection ===
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_ALT=amd64 ;;
  aarch64) ARCH_ALT=arm64 ;;
  armv7l) ARCH_ALT=armhf ;;
  *)
    printf "Error: Unsupported CPU architecture: %s\n" "$ARCH" >&2
    exit 1
    ;;
esac
printf "Detected architecture: %s (%s)\n" "$ARCH" "$ARCH_ALT"

# === Directory Creation ===
mkdir -p "$ROOTFS_DIR"
printf "Rootfs directory prepared: %s\n" "$ROOTFS_DIR"

# === Installation Logic ===
INSTALL_MARKER="$ROOTFS_DIR/.installed"

if [ ! -f "$INSTALL_MARKER" ]; then
  echo "#######################################################################################"
  echo "#"
  echo "#                                NOUR INSTALLER"
  echo "#"
  echo "#######################################################################################"

  # --- Rootfs Download and Extraction ---
  ROOTFS_FILENAME="ubuntu-rootfs-${ARCH_ALT}.tar.xz"
  ROOTFS_URL="${ROOTFS_BASE_URL}/${ARCH_ALT}/${ROOTFS_FILENAME}"
  ROOTFS_TAR_PATH="./${ROOTFS_FILENAME}" # Download to current dir first

  printf "Downloading Ubuntu %s rootfs from %s...\n" "$ARCH_ALT" "$ROOTFS_URL"
  wget --tries="$MAX_RETRIES" --timeout="$TIMEOUT" -O "$ROOTFS_TAR_PATH" "$ROOTFS_URL"
  if [ $? -ne 0 ]; then
      printf "Error: Failed to download rootfs.\n" >&2
      rm -f "$ROOTFS_TAR_PATH" # Clean up partial download
      exit 1
  fi
  printf "Rootfs downloaded successfully.\n"

  # --- Ensure xz is available ---
  if ! command -v xz > /dev/null 2>&1; then
    printf "Warning: 'xz' command not found. Attempting to install xz-utils locally...\n"
    # Attempt to download and extract xz-utils (This is fragile!)
    # Note: This assumes apt and dpkg are available and configured on the host.
    # It's generally better to ensure xz-utils is installed via the system's package manager beforehand.
    XZ_DEB_FILE=""
    if apt download xz-utils; then
        XZ_DEB_FILE=$(ls xz-utils_*.deb 2>/dev/null | head -n 1)
        if [ -n "$XZ_DEB_FILE" ] && [ -f "$XZ_DEB_FILE" ]; then
            printf "Extracting %s to ~/.local/ ...\n" "$XZ_DEB_FILE"
            # Ensure target exists
            mkdir -p "$HOME/.local/usr/bin"
            # Extract using dpkg's raw extract
            dpkg -x "$XZ_DEB_FILE" "$HOME/.local/"
            # Add to PATH for this script's execution
            export PATH="$HOME/.local/usr/bin:$PATH"
            # Clean up downloaded deb
            rm "$XZ_DEB_FILE"
            printf "xz-utils extracted. Make sure %s is in your PATH for future use.\n" "$HOME/.local/usr/bin"
            # Verify again
            if ! command -v xz > /dev/null 2>&1; then
                 printf "Error: Failed to make 'xz' command available after extraction.\n" >&2
                 rm -f "$ROOTFS_TAR_PATH" # Clean up downloaded rootfs
                 exit 1
            fi
        else
            printf "Error: Failed to find downloaded xz-utils .deb file.\n" >&2
            rm -f "$ROOTFS_TAR_PATH"
            exit 1
        fi
    else
        printf "Error: 'apt download xz-utils' failed. Please install xz-utils manually.\n" >&2
        rm -f "$ROOTFS_TAR_PATH"
        exit 1
    fi
  fi

  printf "Extracting rootfs (this may take a while)...\n"
  tar -xJf "$ROOTFS_TAR_PATH" -C "$ROOTFS_DIR" --numeric-owner
  if [ $? -ne 0 ]; then
      printf "Error: Failed to extract rootfs.\n" >&2
      # Attempt cleanup, directory might have partial extraction
      # rm -rf "$ROOTFS_DIR"/* "$ROOTFS_DIR"/.[!.]* # More thorough cleanup if needed
      rm -f "$ROOTFS_TAR_PATH"
      exit 1
  fi
  printf "Rootfs extracted successfully.\n"
  rm -f "$ROOTFS_TAR_PATH" # Clean up tarball

  # --- Proot Download ---
  PROOT_DEST="$ROOTFS_DIR/usr/local/bin/proot"
  mkdir -p "$(dirname "$PROOT_DEST")"
  printf "Downloading proot binary from %s...\n" "$PROOT_URL"

  retries=0
  while [ "$retries" -lt "$MAX_RETRIES" ]; do
      wget --tries=1 --timeout="$TIMEOUT" -O "$PROOT_DEST" "$PROOT_URL"
      if [ $? -eq 0 ] && [ -s "$PROOT_DEST" ]; then
          printf "Proot downloaded successfully.\n"
          chmod +x "$PROOT_DEST"
          printf "Proot permissions set.\n"
          break
      fi
      retries=$((retries + 1))
      printf "Proot download failed or file is empty. Retrying (%d/%d)...\n" "$retries" "$MAX_RETRIES"
      rm -f "$PROOT_DEST" # Remove potentially corrupted file
      sleep 1
  done

  if [ ! -s "$PROOT_DEST" ]; then
      printf "Error: Failed to download proot after %d retries.\n" "$MAX_RETRIES" >&2
      exit 1
  fi

  # --- Final Setup ---
  # Note: Making everything executable is generally not recommended for security.
  # However, it might be required for some proot setups. Consider refining this if possible.
  printf "Setting execute permissions recursively within %s (this might be broad)...\n" "$ROOTFS_DIR"
  chmod -R +x "$ROOTFS_DIR"

  # Create marker file to indicate successful installation
  touch "$INSTALL_MARKER"
  printf "Installation complete. Marker file created: %s\n" "$INSTALL_MARKER"

else
  printf "NOUR already installed (found %s). Skipping installation.\n" "$INSTALL_MARKER"
fi

# === Display Functions ===
# Define colors (ensure TERM supports colors)
if [ -t 1 ]; then
  CYAN='\033[0;36m'
  WHITE='\033[0;37m'
  RESET_COLOR='\033[0m'
  BOLD_RED='\033[1;31m'
  BOLD_YELLOW='\033[1;33m'
  BOLD_GREEN='\033[1;32m'
  BOLD_CYAN='\033[1;36m'
  BOLD_BLUE='\033[1;34m'
  BOLD_MAGENTA='\033[1;35m'
  BOLD_WHITE='\033[1;37m'
  YELLOW='\033[0;33m'
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  MAGENTA='\033[0;35m'
else
  # No colors if not a TTY
  CYAN='' WHITE='' RESET_COLOR='' BOLD_RED='' BOLD_YELLOW='' BOLD_GREEN=''
  BOLD_CYAN='' BOLD_BLUE='' BOLD_MAGENTA='' BOLD_WHITE='' YELLOW='' GREEN=''
  RED='' MAGENTA=''
fi

display_gg() {
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
  echo -e ""
  echo -e "           ${CYAN}-----> Mission Completed ! <----${RESET_COLOR}"
  echo -e ""
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
}

fun_header() {
  echo -e "${BOLD_RED}   __      __        ______"
  echo -e "${BOLD_YELLOW}   \\ \\    / /        |  ____|"
  echo -e "${BOLD_GREEN}    \\ \\  / / __  ___| |__ _ __ ___  ___    ___  ___"
  echo -e "${BOLD_CYAN}     \\ \\/ / '_ \\/ __|  __| '__/ _ \\/ _ \\ / _ \\/ __|"
  echo -e "${BOLD_BLUE}      \\  /| |_) \\__ \\ |  | | |  __/  __/|  __/\\__ \\"
  echo -e "${BOLD_MAGENTA}       \\/ | .__/|___/_|  |_|  \\___|\\___(_)___||___/"
  echo -e "${BOLD_WHITE}          | |"
  echo -e "${BOLD_YELLOW}          |_|"
  echo -e "${BOLD_GREEN}___________________________________________________"
  echo -e "            ${BOLD_CYAN}-----> Fun System Resources <----${RESET_COLOR}"
  echo -e "${BOLD_RED}                Powered by ${BOLD_WHITE}NOUR${RESET_COLOR}"
}

fun_resources() {
  echo -e "${BOLD_WHITE}--- Host System Resources ---${RESET_COLOR}"
  # Use command -v to check for command existence gracefully
  if command -v grep >/dev/null && [ -f /proc/cpuinfo ]; then
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ *//g' || echo "N/A")
    CPU_CORES=$(grep -c 'processor' /proc/cpuinfo || echo "N/A")
    echo -e "${BOLD_MAGENTA} CPU Model -> ${YELLOW}${CPU_MODEL}${RESET_COLOR}"
    echo -e "${BOLD_CYAN} CPU Cores -> ${GREEN}${CPU_CORES}${RESET_COLOR}"
  else
    echo -e "${BOLD_MAGENTA} CPU Info -> ${YELLOW}N/A (check /proc/cpuinfo)${RESET_COLOR}"
  fi

  if command -v free >/dev/null; then
    TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}' || echo "N/A")
    USED_RAM=$(free -m | awk '/Mem:/ {print $3}' || echo "N/A")
    FREE_RAM=$(free -m | awk '/Mem:/ {print $4}' || echo "N/A")
    echo -e "${BOLD_BLUE} RAM Total -> ${RED}${TOTAL_RAM} MB${RESET_COLOR}"
    echo -e "${BOLD_YELLOW} RAM Used  -> ${MAGENTA}${USED_RAM} MB${RESET_COLOR}"
    echo -e "${BOLD_GREEN} RAM Free  -> ${CYAN}${FREE_RAM} MB${RESET_COLOR}"
  else
     echo -e "${BOLD_BLUE} RAM Info -> ${RED}N/A ('free' command not found)${RESET_COLOR}"
  fi

  if command -v df >/dev/null; then
    DISK_USAGE=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " used out of " $2 " (" $5 ")"}' || echo "N/A")
    echo -e "${BOLD_RED} Disk Usage (/) -> ${BOLD_WHITE}${DISK_USAGE}${RESET_COLOR}"
  else
    echo -e "${BOLD_RED} Disk Usage -> ${BOLD_WHITE}N/A ('df' command not found)${RESET_COLOR}"
  fi

  if [ -f /proc/uptime ]; then
    UPTIME_SECS=$(cut -d'.' -f1 /proc/uptime)
    UPTIME_HOURS=$((UPTIME_SECS / 3600))
    UPTIME_MINS=$(( (UPTIME_SECS % 3600) / 60 ))
    UPTIME="${UPTIME_HOURS} hours, ${UPTIME_MINS} minutes"
    echo -e "${BOLD_YELLOW} Uptime -> ${BOLD_GREEN}${UPTIME}${RESET_COLOR}"
  else
    echo -e "${BOLD_YELLOW} Uptime -> ${BOLD_GREEN}N/A (check /proc/uptime)${RESET_COLOR}"
  fi
  echo -e "${BOLD_WHITE}-----------------------------${RESET_COLOR}"
}

# === Execution ===
# Clear screen (optional, consider if running non-interactively)
# clear

# Display header and resources
fun_header
fun_resources
display_gg # Display "Mission Completed" before starting proot

# --- Start Proot ---
PROOT_BINARY="${ROOTFS_DIR}/usr/local/bin/proot"
if [ ! -x "$PROOT_BINARY" ]; then
    printf "Error: Proot binary not found or not executable at %s\n" "$PROOT_BINARY" >&2
    exit 1
fi

printf "Starting proot environment...\n"
# Note: Binding the entire host root (/:/) can be a security risk
# and might expose sensitive host files within the guest environment.
# Consider binding only necessary directories like:
# -b /dev -b /proc -b /sys -b /tmp -b /etc/resolv.conf
# Adjust according to your needs.
"$PROOT_BINARY" \
  --rootfs="$ROOTFS_DIR" \
  -0 \
  -w /root \
  -b /:/ \
  --kill-on-exit

# Script finishes when proot exits
exit_code=$?
printf "Proot environment exited with code %d.\n" "$exit_code"
exit "$exit_code"
