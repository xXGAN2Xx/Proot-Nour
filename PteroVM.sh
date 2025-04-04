#!/bin/sh

# Exit immediately if a command exits with a non-zero status.
set -e

#############################
# Configuration & Variables #
#############################

# Define the root directory. We assume write access here and in /tmp.
ROOTFS_DIR="/home/container"
# Local directory for binaries (like xz)
LOCAL_BIN_DIR="$HOME/.local/usr/bin"
# Ensure local bin directory exists and is in PATH
mkdir -p "$LOCAL_BIN_DIR"
export PATH="$LOCAL_BIN_DIR:$PATH"

# Download settings
max_retries=5
timeout=15 # Increased timeout slightly

#############################
# Environment Setup         #
#############################

# Detect the machine architecture.
ARCH=$(uname -m)

# Check machine architecture.
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ]; then
  echo "Error: Unsupported CPU architecture: ${ARCH}" >&2
  exit 1
fi

# --- Initial Installation Steps (only if not already installed) ---
if [ ! -f "$ROOTFS_DIR/.installed" ]; then

  echo "#######################################################################################"
  echo "# Nour PteroVM Installer                                                              #"
  echo "#######################################################################################"
  echo ""
  echo "* [0] Ubuntu Noble"
  echo "* [1] Alpine Latest"
  echo ""

  # --- Choose OS ---
  distro_url=""
  while [ -z "$distro_url" ]; do
    read -p "Select OS to install (0 or 1): " input
    case $input in
      0)
        distro_url="https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-${ARCH}-pd-v4.18.0.tar.xz"
        echo "Selected Ubuntu."
        ;;
      1)
        distro_url="https://github.com/termux/proot-distro/releases/download/v4.21.0/alpine-${ARCH}-pd-v4.21.0.tar.xz"
        echo "Selected Alpine."
        ;;
      *)
        echo "Invalid input. Please enter 0 or 1."
        ;;
    esac
  done

  echo "Preparing installation directory: $ROOTFS_DIR"
  # Ensure the rootfs directory exists and is empty (or handle existing files if needed)
  mkdir -p "$ROOTFS_DIR"
  # Consider cleaning $ROOTFS_DIR if a previous attempt failed?
  # rm -rf "${ROOTFS_DIR:?}"/* # Uncomment with caution if you want to ensure it's clean

  # --- Dependency Handling: xz-utils ---
  # Check if tar can already handle xz ('J' option) or if xz command exists
  if ! tar --help | grep -q -- '--xz' && ! command -v xz > /dev/null 2>&1; then
    echo "xz command not found. Attempting to download and extract it locally..."

    # Check if apt and dpkg are available
    if ! command -v apt > /dev/null 2>&1 || ! command -v dpkg > /dev/null 2>&1; then
       echo "Error: 'apt' or 'dpkg' command not found. Cannot fetch xz-utils." >&2
       echo "Please ask the host administrator to install 'xz-utils' globally." >&2
       exit 1
    fi

    echo "Downloading xz-utils package..."
    # Use a temporary directory for download
    TMP_DEB_DIR=$(mktemp -d)
    if apt download --no-cache --allow-unauthenticated -o Debug::NoLocking=1 -o Dir::Cache::archives="$TMP_DEB_DIR" xz-utils; then
      # Find the downloaded .deb file (should be only one)
      deb_file=$(find "$TMP_DEB_DIR" -maxdepth 1 -name 'xz-utils_*.deb' -print -quit)

      if [ -n "$deb_file" ] && [ -f "$deb_file" ]; then
        echo "Extracting xz binary from $deb_file..."
        # Extract only the necessary parts to the local bin directory
        dpkg -x "$deb_file" "$HOME/.local" # Extracts usr/bin/xz into $HOME/.local/usr/bin
        if [ -x "$LOCAL_BIN_DIR/xz" ]; then
           echo "xz binary successfully extracted to $LOCAL_BIN_DIR"
           # Add to PATH immediately if not already done (belt-and-suspenders)
           export PATH="$LOCAL_BIN_DIR:$PATH"
        else
           echo "Error: Failed to extract xz binary." >&2
           rm -rf "$TMP_DEB_DIR" # Clean up temp dir
           exit 1
        fi
      else
        echo "Error: Failed to download or find the xz-utils .deb file." >&2
        rm -rf "$TMP_DEB_DIR" # Clean up temp dir
        exit 1
      fi
      # Clean up the downloaded deb and temp dir
      rm -rf "$TMP_DEB_DIR"
      echo "Cleaned up downloaded package."
    else
        echo "Error: 'apt download xz-utils' failed." >&2
        rm -rf "$TMP_DEB_DIR" # Clean up temp dir
        exit 1
    fi
  else
      echo "xz support detected. Proceeding..."
  fi # End of xz dependency check

  # --- Download and Extract RootFS ---
  echo "Downloading RootFS from $distro_url..."
  wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz "$distro_url"

  echo "Extracting RootFS into $ROOTFS_DIR..."
  # Use 'tar' with 'xz'. The 'J' flag relies on 'xz' being in PATH or tar having built-in support.
  if tar -xJvf /tmp/rootfs.tar.xz -C "$ROOTFS_DIR" --strip-components=1; then
     echo "RootFS extracted successfully."
  else
     echo "Error: Failed to extract RootFS. Check /tmp/rootfs.tar.xz and permissions." >&2
     rm -f /tmp/rootfs.tar.xz # Clean up partial download
     exit 1
  fi
  rm -f /tmp/rootfs.tar.xz # Clean up archive

  # --- Download proot binary ---
  PROOT_BIN_PATH="$ROOTFS_DIR/usr/local/bin/proot"
  PROOT_URL="https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot" # Consider a more official source if possible

  echo "Downloading proot binary..."
  mkdir -p "$ROOTFS_DIR/usr/local/bin"

  retries=0
  while [ ! -s "$PROOT_BIN_PATH" ] && [ "$retries" -lt "$max_retries" ]; do
    echo "Attempting download (Try $(($retries + 1))/$max_retries)..."
    wget --tries=1 --timeout=$timeout -O "$PROOT_BIN_PATH" "$PROOT_URL" || true # Prevent wget error from stopping the script, check size instead
    if [ -s "$PROOT_BIN_PATH" ]; then
      echo "proot downloaded successfully."
      chmod +x "$PROOT_BIN_PATH"
      break
    fi
    retries=$(($retries + 1))
    echo "Download failed or file is empty. Retrying in 2 seconds..."
    rm -f "$PROOT_BIN_PATH" # Remove empty file before retry
    sleep 2
  done

  if [ ! -s "$PROOT_BIN_PATH" ]; then
    echo "Error: Failed to download proot after $max_retries attempts." >&2
    exit 1
  fi

  # --- Post-Installation Setup ---
  echo "Performing post-installation setup..."
  # Add DNS Resolvers
  printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "$ROOTFS_DIR/etc/resolv.conf"

  # Mark installation as complete
  touch "$ROOTFS_DIR/.installed"
  echo "Installation complete."

fi # End of initial installation block

################################
# Information Display          #
################################

# Define color variables (keep as is)
BLACK='\e[0;30m'; BOLD_BLACK='\e[1;30m'; RED='\e[0;31m'; BOLD_RED='\e[1;31m';
GREEN='\e[0;32m'; BOLD_GREEN='\e[1;32m'; YELLOW='\e[0;33m'; BOLD_YELLOW='\e[1;33m';
BLUE='\e[0;34m'; BOLD_BLUE='\e[1;34m'; MAGENTA='\e[0;35m'; BOLD_MAGENTA='\e[1;35m';
CYAN='\e[0;36m'; BOLD_CYAN='\e[1;36m'; WHITE='\e[0;37m'; BOLD_WHITE='\e[1;37m';
RESET_COLOR='\e[0m'

display_header() {
    echo -e "${BOLD_MAGENTA} __      __        ______"
    echo -e "${BOLD_MAGENTA} \\ \\    / /        |  ____|"
    echo -e "${BOLD_MAGENTA}  \\ \\  / / __  ___ | |__ _ __ ___  ___    ___  ___"
    echo -e "${BOLD_MAGENTA}   \\ \\/ / '_ \\/ __||  __| '__/ _ \\/ _ \\ / _ \\/ __|"
    echo -e "${BOLD_MAGENTA}    \\  /| |_) \\__ \\| |  | | |  __/  __/|  __/\__ \\"
    echo -e "${BOLD_MAGENTA}     \\/ | .__/|___/_|  |_|  \\___|\\___(_)___||___/"
    echo -e "${BOLD_MAGENTA}         | |"
    echo -e "${BOLD_MAGENTA}         |_|"
    echo -e "${BOLD_MAGENTA}___________________________________________________"
    echo -e "           ${YELLOW}-----> System Resources <----${RESET_COLOR}"
    echo -e ""
}

display_resources() {
    # Attempt to get host OS info, fallback if fails
    HOST_OS=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2 || echo "N/A")
    echo -e " HOST OS -> ${RED}${HOST_OS}${RESET_COLOR}"
    # Attempt to get CPU info, fallback if fails
    CPU_INFO=$(grep 'model name' /proc/cpuinfo | head -n 1 | cut -d':' -f2- | sed 's/^ *//;s/  \+/ /g' || echo "N/A")
    echo -e " CPU -> ${YELLOW}${CPU_INFO}${RESET_COLOR}"
    # Display Pterodactyl environment variables (ensure they are passed to the container)
    echo -e " RAM -> ${BOLD_GREEN}${SERVER_MEMORY:-N/A}MB${RESET_COLOR}"
    echo -e " PRIMARY PORT -> ${BOLD_GREEN}${SERVER_PORT:-N/A}${RESET_COLOR}"
    echo -e " EXTRA PORTS -> ${BOLD_GREEN}${P_SERVER_ALLOCATION_LIMIT:-N/A}${RESET_COLOR}"
    echo -e " SERVER UUID -> ${BOLD_GREEN}${P_SERVER_UUID:-N/A}${RESET_COLOR}"
    echo -e " LOCATION -> ${BOLD_GREEN}${P_SERVER_LOCATION:-N/A}${RESET_COLOR}"
}

display_footer() {
    echo -e "${BOLD_MAGENTA}___________________________________________________${RESET_COLOR}"
    echo -e ""
    echo -e "           ${YELLOW}-----> VPS HAS STARTED <----${RESET_COLOR}"
}

# Main script execution for display
clear
display_header
display_resources
display_footer
echo ""
echo "Starting proot environment..."
echo "Executing: $ROOTFS_DIR/usr/local/bin/proot --rootfs=\"${ROOTFS_DIR}\" -0 -w /root -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit"
echo ""

###########################
# Start PRoot environment #
###########################

# Get the proot binary path again (safer in case script logic changes)
PROOT_BIN="$ROOTFS_DIR/usr/local/bin/proot"

# Check if proot binary is executable
if [ ! -x "$PROOT_BIN" ]; then
  echo "Error: Proot binary not found or not executable at $PROOT_BIN" >&2
  # Attempt to fix permissions if it exists but isn't executable
  if [ -f "$PROOT_BIN" ]; then
    echo "Attempting to make proot executable..."
    chmod +x "$PROOT_BIN"
    # Check again
    if [ ! -x "$PROOT_BIN" ]; then
       echo "Failed to make proot executable. Check file system permissions." >&2
       exit 1
    fi
  else
    exit 1 # Exit if file doesn't exist
  fi
fi


# Execute proot. Using exec replaces the current shell process with proot,
# which is often desired for the main process in a container.
exec "$PROOT_BIN" --rootfs="$ROOTFS_DIR" \
    -0 \
    -w "/root" \
    -b /dev \
    -b /sys \
    -b /proc \
    -b /etc/resolv.conf \
    --kill-on-exit
