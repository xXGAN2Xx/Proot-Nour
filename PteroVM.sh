#!/bin/sh

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
set -eu

# --- Configuration ---
ROOTFS_DIR="/home/container" # Base directory for the root filesystem
MAX_RETRIES=50             # Maximum download retries for wget
WGET_TIMEOUT=5             # Timeout for wget connections (seconds)
PROOT_URL="https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot" # URL for proot binary
UBUNTU_BASE_URL="https://raw.githubusercontent.com/EXALAB/Anlinux-Resources/refs/heads/master/Rootfs/Ubuntu" # Base URL for Ubuntu rootfs

# --- Environment Setup ---
# Ensure the local bin directory is in PATH
# Using $HOME is generally more reliable than ~ in scripts
LOCAL_BIN_DIR="${HOME}/.local/usr/bin"
mkdir -p "$LOCAL_BIN_DIR"
export PATH="${PATH}:${LOCAL_BIN_DIR}"

# --- Architecture Detection ---
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_ALT=amd64 ;;
  aarch64) ARCH_ALT=arm64 ;;
  armv7l)  ARCH_ALT=armhf ;;
  *)
    printf "Error: Unsupported CPU architecture: %s\n" "$ARCH" >&2
    exit 1
    ;;
esac

# --- Installation ---
# Only run installation if the marker file doesn't exist
INSTALL_MARKER="$ROOTFS_DIR/.installed"
if [ ! -e "$INSTALL_MARKER" ]; then
  printf "#######################################################################################\n"
  printf "#\n"
  printf "#                                NOUR INSTALLER\n"
  printf "#\n"
  printf "#######################################################################################\n\n"

  # --- Download and Extract Ubuntu Rootfs ---
  printf ">>> Downloading Ubuntu Rootfs for %s...\n" "$ARCH_ALT"
  ROOTFS_TAR_XZ="rootfs-${ARCH_ALT}.tar.xz"
  # Construct the correct download URL using the detected architecture
  UBUNTU_ROOTFS_URL="${UBUNTU_BASE_URL}/${ARCH_ALT}/ubuntu-rootfs-${ARCH_ALT}.tar.xz"

  # Download the rootfs archive
  # Use curl for downloading the rootfs
  if ! curl -sSLo "$ROOTFS_TAR_XZ" "$UBUNTU_ROOTFS_URL"; then
      printf "Error: Failed to download Ubuntu rootfs from %s\n" "$UBUNTU_ROOTFS_URL" >&2
      exit 1
  fi
  printf ">>> Ubuntu Rootfs downloaded: %s\n" "$ROOTFS_TAR_XZ"

  # --- Install xz-utils (Dependency for extraction) ---
  # Note: This assumes 'apt' and 'dpkg' are available in the *host* environment.
  # This might fail in minimal containers. Consider bundling a static xz if needed.
  printf ">>> Ensuring xz-utils is available...\n"
  if ! command -v xz > /dev/null; then
      printf "    xz command not found. Attempting to install xz-utils...\n"
      # Clean up any previous deb file attempt
      rm -f xz-utils_*.deb
      # Download the package
      if ! apt-get download xz-utils; then
          printf "Error: Failed to download xz-utils package using apt-get download.\n" >&2
          printf "       Please ensure apt is configured or install xz-utils manually.\n" >&2
          rm -f "$ROOTFS_TAR_XZ" # Clean up downloaded rootfs
          exit 1
      fi
      # Find the downloaded deb file (handle potential version variations)
      DEB_FILE=$(find . -maxdepth 1 -name 'xz-utils_*.deb' -print -quit)
      if [ -z "$DEB_FILE" ]; then
          printf "Error: Could not find downloaded xz-utils deb file.\n" >&2
          rm -f "$ROOTFS_TAR_XZ"
          exit 1
      fi
      printf "    Extracting %s...\n" "$DEB_FILE"
      # Extract the deb file to the local directory
      dpkg -x "$DEB_FILE" "$HOME/.local/"
      # Clean up the deb file
      rm -f "$DEB_FILE"
      # Verify xz is now in the PATH
      if ! command -v xz > /dev/null; then
           printf "Error: Failed to install xz command even after extracting package.\n" >&2
           rm -f "$ROOTFS_TAR_XZ"
           exit 1
      fi
      printf "    xz command installed successfully to %s\n" "$LOCAL_BIN_DIR"
  else
      printf "    xz command already available.\n"
  fi

  # --- Extract Rootfs ---
  printf ">>> Extracting Ubuntu Rootfs (this may take a while)...\n"
  # Ensure the target directory exists
  mkdir -p "$ROOTFS_DIR"
  # Extract using tar with xz support
  if ! tar -xJf "$ROOTFS_TAR_XZ" -C "$ROOTFS_DIR"; then
      printf "Error: Failed to extract %s\n" "$ROOTFS_TAR_XZ" >&2
      # Attempt cleanup of potentially partially extracted files
      rm -rf "${ROOTFS_DIR:?}"/* # Safety check: ensure ROOTFS_DIR is set
      rm -f "$ROOTFS_TAR_XZ"
      exit 1
  fi
  printf ">>> Rootfs extracted successfully.\n"

  # --- Download Proot ---
  printf ">>> Downloading proot...\n"
  PROOT_DEST="$ROOTFS_DIR/usr/local/bin/proot"
  mkdir -p "$(dirname "$PROOT_DEST")"

  # Retry loop for downloading proot
  retries=0
  while [ "$retries" -lt "$MAX_RETRIES" ]; do
    # Use wget for downloading proot with retries and timeout
    wget --tries=1 --timeout="$WGET_TIMEOUT" --no-hsts -O "$PROOT_DEST" "$PROOT_URL"

    # Check if download was successful and file is not empty
    if [ -s "$PROOT_DEST" ]; then
      printf ">>> proot downloaded successfully.\n"
      break
    fi

    retries=$((retries + 1))
    printf "    Download attempt %d/%d failed or resulted in empty file. Retrying in 1 second...\n" "$retries" "$MAX_RETRIES"
    rm -f "$PROOT_DEST" # Remove potentially empty file
    sleep 1
  done

  # Check if proot was successfully downloaded after retries
  if [ ! -s "$PROOT_DEST" ]; then
    printf "Error: Failed to download proot after %d retries from %s\n" "$MAX_RETRIES" "$PROOT_URL" >&2
    rm -rf "${ROOTFS_DIR:?}"/* # Clean up extracted rootfs
    rm -f "$ROOTFS_TAR_XZ"
    exit 1
  fi

  # Make proot executable
  chmod +x "$PROOT_DEST"
  printf ">>> proot made executable.\n"

  # --- Cleanup ---
  printf ">>> Cleaning up downloaded archive...\n"
  rm -f "$ROOTFS_TAR_XZ"

  # --- Create Installation Marker ---
  touch "$INSTALL_MARKER"
  printf ">>> Installation complete. Marker file created: %s\n" "$INSTALL_MARKER"

else
  printf ">>> Installation marker found (%s). Skipping installation steps.\n" "$INSTALL_MARKER"
fi

# --- Display Functions ---

# Define Colors (using printf compatible codes)
RESET_COLOR='\033[0m'
WHITE='\033[0;37m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'

# Define Bold Colors
BOLD_WHITE='\033[1;37m'
BOLD_CYAN='\033[1;36m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_RED='\033[1;31m'
BOLD_BLUE='\033[1;34m'
BOLD_MAGENTA='\033[1;35m'

display_gg() {
  printf "%b___________________________________________________%b\n" "$WHITE" "$RESET_COLOR"
  printf "\n"
  printf "               %b-----> Mission Completed ! <----%b\n" "$CYAN" "$RESET_COLOR"
  printf "\n"
  printf "%b___________________________________________________%b\n" "$WHITE" "$RESET_COLOR"
}

fun_header() {
  printf "%b  __      __        ______%b\n" "$BOLD_RED" "$RESET_COLOR"
  printf "%b  \\\\ \\    / /        |  ____|%b\n" "$BOLD_YELLOW" "$RESET_COLOR"
  printf "%b   \\\\ \\  / / __  ___| |__ _ __ ___  ___    ___  ___%b\n" "$BOLD_GREEN" "$RESET_COLOR"
  printf "%b    \\\\ \\/ / '_ \\/ __|  __| '__/ _ \\/ _ \\ / _ \\/ __|%b\n" "$BOLD_CYAN" "$RESET_COLOR"
  printf "%b     \\\\  /| |_) \\__ \\ |  | | |  __/  __/|  __/\\__ \\%b\n" "$BOLD_BLUE" "$RESET_COLOR"
  printf "%b      \\/ | .__/|___/_|  |_|  \\___|\\___(_)___||___/%b\n" "$BOLD_MAGENTA" "$RESET_COLOR"
  printf "%b         | |%b\n" "$BOLD_WHITE" "$RESET_COLOR"
  printf "%b         |_|%b\n" "$BOLD_YELLOW" "$RESET_COLOR"
  printf "%b___________________________________________________%b\n" "$BOLD_GREEN" "$RESET_COLOR"
  printf "            %b-----> Fun System Resources <----%b\n" "$BOLD_CYAN" "$RESET_COLOR"
  printf "%b                 Powered by %bNOUR%b\n" "$BOLD_RED" "$BOLD_WHITE" "$RESET_COLOR"
}

fun_resources() {
  # Use default values if commands fail or files don't exist
  CPU_MODEL=$(grep -m1 '^model name' /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ *//g' || echo "N/A")
  CPU_CORES=$(grep -c '^processor' /proc/cpuinfo || echo "N/A")

  # Get RAM info (in MB) using awk for better parsing
  TOTAL_RAM=$(awk '/MemTotal:/ {printf "%.0f", $2/1024}' /proc/meminfo || echo "N/A")
  FREE_RAM=$(awk '/MemFree:/ {printf "%.0f", $2/1024}' /proc/meminfo || echo "N/A")
  AVAIL_RAM=$(awk '/MemAvailable:/ {printf "%.0f", $2/1024}' /proc/meminfo || echo "$FREE_RAM") # Fallback to Free if Available isn't present
  USED_RAM="N/A"
  if [ "$TOTAL_RAM" != "N/A" ] && [ "$AVAIL_RAM" != "N/A" ]; then
      USED_RAM=$((TOTAL_RAM - AVAIL_RAM))
  fi


  # Get disk usage for the root directory
  DISK_INFO=$(df -h / | awk 'NR==2 {print $3 " used / " $2 " total (" $5 " used)"}' || echo "N/A")

  # Get system uptime using /proc/uptime for better compatibility
  UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime || echo 0)
  UPTIME_HOURS=$((UPTIME_SECONDS / 3600))
  UPTIME_MINUTES=$(((UPTIME_SECONDS % 3600) / 60))
  UPTIME=$(printf "%d hours, %d minutes" "$UPTIME_HOURS" "$UPTIME_MINUTES")

  printf "%b CPU Model -> %b%s%b\n" "$BOLD_MAGENTA" "$YELLOW" "$CPU_MODEL" "$RESET_COLOR"
  printf "%b CPU Cores -> %b%s%b\n" "$BOLD_CYAN" "$GREEN" "$CPU_CORES" "$RESET_COLOR"
  printf "%b RAM Total -> %b%s MB%b\n" "$BOLD_BLUE" "$RED" "$TOTAL_RAM" "$RESET_COLOR"
  printf "%b RAM Used  -> %b%s MB%b\n" "$BOLD_YELLOW" "$MAGENTA" "$USED_RAM" "$RESET_COLOR" # Note: This is Total - Available
  printf "%b RAM Avail -> %b%s MB%b\n" "$BOLD_GREEN" "$CYAN" "$AVAIL_RAM" "$RESET_COLOR"
  printf "%b Disk Usage-> %b%s%b\n" "$BOLD_RED" "$BOLD_WHITE" "$DISK_INFO" "$RESET_COLOR"
  printf "%b Uptime    -> %b%s%b\n" "$BOLD_YELLOW" "$BOLD_GREEN" "$UPTIME" "$RESET_COLOR"
}

# --- Main Execution ---
clear
fun_header
fun_resources
display_gg

printf "\n>>> Starting proot environment...\n"

# Execute proot with the configured rootfs and bindings
# Note the use of double quotes around variables
"${ROOTFS_DIR}/usr/local/bin/proot" \
  --rootfs="${ROOTFS_DIR}" \
  -0 \
  -w /root \
  -b /dev \
  -b /sys \
  -b /proc \
  -b /etc/resolv.conf \
  --kill-on-exit

printf ">>> Proot environment exited.\n"

exit 0
