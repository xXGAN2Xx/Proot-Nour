#!/bin/sh

#############################
# Linux Installation #
#############################

# Define the root directory to /home/container.
# We can only write in /home/container and /tmp in the container.
ROOTFS_DIR=/home/container

# Add ~/.local/usr/bin to PATH if needed (though proot usually handles its own environment)
export PATH=$PATH:~/.local/usr/bin

# Network settings for wget
max_retries=50
timeout=3 # Increased timeout slightly for potentially larger downloads


# --- Detect Architecture ---
ARCH=$(uname -m)
echo "Detected architecture: $ARCH" # Added for clarity

# Check machine architecture
if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT="amd64"
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT="arm64"
else
  printf "Unsupported CPU architecture: ${ARCH}\n"
  exit 1
fi
echo "Using alternative architecture name: $ARCH_ALT" # Added for clarity

# --- Download & Decompress Root File System ---
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    echo "#######################################################################################"
    echo "#"
    echo "#                                 Nour PteroVM"
    echo "#"
    echo "#######################################################################################"
    echo ""
    echo "* [0] Ubuntu (Jammy 22.04)"
    echo "* [1] Alpine (Edge - Check URL if issues arise)"
    echo ""

    # Ensure input is read correctly
    input=""
    while [ "$input" != "0" ] && [ "$input" != "1" ]; do
        read -p "Enter OS choice (0 for Ubuntu, 1 for Alpine): " input
        case "$input" in
            0|1) break;;
            *) echo "Invalid input. Please enter 0 or 1.";;
        esac
    done

    echo "Selected OS: $input" # Added for clarity

    # Define URLs based on selection
    if [ "$input" = "0" ]; then
        # Ubuntu URL
        ROOTFS_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/jammy/release/ubuntu-base-22.04.5-base-${ARCH_ALT}.tar.gz"
    else
        # FIX: Corrected Alpine URL to use ${ARCH_ALT} in the filename
        # NOTE: This specific Anlinux URL/version might change or become outdated. Check repository if download fails.
        # Using a slightly different source which might be more reliably structured:
        # Check https://alpinelinux.org/downloads/ for official mini rootfs if needed.
        # Using the original source structure but correcting the filename:
        ROOTFS_URL="https://raw.githubusercontent.com/EXALAB/Anlinux-Resources/master/Rootfs/Alpine/${ARCH_ALT}/alpine-minirootfs-latest-${ARCH_ALT}.tar.gz"
        # Fallback / Alternative example (might need version adjustment):
        # ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/${ARCH}/alpine-minirootfs-3.19.1-${ARCH}.tar.gz"
    fi

    echo "Downloading RootFS from: $ROOTFS_URL"
    # Download rootfs
    wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.gz "$ROOTFS_URL"

    # FIX: Add check after wget
    if [ $? -ne 0 ]; then
        echo "Error downloading rootfs. Please check the URL and network connection."
        exit 1
    fi

    echo "Extracting RootFS..."
    # Extract rootfs
    tar -xf /tmp/rootfs.tar.gz -C "$ROOTFS_DIR" --strip-components=1

    # FIX: Add check after tar
    if [ $? -ne 0 ]; then
        echo "Error extracting rootfs. The archive might be corrupted or incomplete."
        rm -f /tmp/rootfs.tar.gz # Clean up failed download
        exit 1
    fi

    echo "RootFS downloaded and extracted."

    # --- Download proot ---
    echo "Downloading proot..."
    # Create directory for proot
    mkdir -p "$ROOTFS_DIR/usr/local/bin"

    PROOT_URL="https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
    PROOT_DEST="$ROOTFS_DIR/usr/local/bin/proot"

    # Download proot with retry loop
    download_attempts=0
    while [ ! -s "$PROOT_DEST" ]; do
        if [ $download_attempts -gt 0 ]; then
            echo "Retrying proot download (attempt $((download_attempts + 1)))..."
            sleep 1 # Wait before retrying
        fi
        # Remove potentially empty/corrupt file before retrying
        rm -f "$PROOT_DEST"
        wget --tries=3 --timeout=$timeout -O "$PROOT_DEST" "$PROOT_URL" # Reduced tries per loop iteration

        # Check if download succeeded in this attempt (wget exit code)
        if [ $? -ne 0 ]; then
            echo "Warning: wget failed to download proot on this attempt."
        fi

        download_attempts=$((download_attempts + 1))
        if [ $download_attempts -ge $max_retries ]; then
             echo "Error: Failed to download proot after $max_retries attempts."
             exit 1
        fi

        # Check if file exists and has size > 0 AFTER trying to download
         if [ -s "$PROOT_DEST" ]; then
             echo "Proot downloaded successfully."
             break # Exit the loop since the file exists and is not empty
         fi
    done

    # FIX: Moved chmod +x AFTER the loop confirms successful download
    echo "Making proot executable..."
    chmod +x "$PROOT_DEST"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to make proot executable."
        exit 1
    fi

    # --- Final Setup Steps ---
    echo "Configuring DNS..."
    # Add DNS Resolver nameservers to resolv.conf.
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"

    echo "Cleaning up temporary files..."
    # FIX: Corrected cleanup command for the downloaded tarball
    rm -f /tmp/rootfs.tar.gz

    echo "Marking installation as complete..."
    # Create .installed to later check whether the OS is installed.
    touch "$ROOTFS_DIR/.installed"

    echo "Installation complete."

else
    echo "Linux environment already installed. Skipping installation."
fi

################################
# Display Information          #
################################

# Define color variables
# (Color definitions remain the same)
BLACK='\e[0;30m'
BOLD_BLACK='\e[1;30m'
# ... (rest of color codes) ...
MAGENTA='\e[0;35m'
BOLD_MAGENTA='\e[1;35m'
YELLOW='\e[0;33m'
BOLD_GREEN='\e[1;32m'
RED='\e[0;31m'
RESET_COLOR='\e[0m'


# Function to display the header
display_header() {
    echo -e "${BOLD_MAGENTA} __      __         ______"
    echo -e "${BOLD_MAGENTA} \ \    / /        |  ____|"
    echo -e "${BOLD_MAGENTA}  \ \  / / __  ___ | |__ _ __ ___  ___    ___  ___"
    echo -e "${BOLD_MAGENTA}   \ \/ / '_ \/ __||  __| '__/ _ \/ _ \ / _ \/ __|"
    echo -e "${BOLD_MAGENTA}    \  /| |_) \__ \| |  | | |  __/  __/|  __/\__ \\"
    echo -e "${BOLD_MAGENTA}     \/ | .__/|___/_|  |_|  \___|\___(_)___||___/"
    echo -e "${BOLD_MAGENTA}        | |"
    echo -e "${BOLD_MAGENTA}        |_|"
    echo -e "${BOLD_MAGENTA}___________________________________________________"
    echo -e "           ${YELLOW}-----> System Resources <----${RESET_COLOR}"
    echo -e ""
}

# Function to display system resources
display_resources() {
    # Attempt to get host OS info if possible (might not work in all containers)
    if [ -f /etc/os-release ]; then
        echo -e " HOST OS -> ${RED}$(grep "PRETTY_NAME" /etc/os-release | cut -d'"' -f2)${RESET_COLOR}"
    fi
    # Check if proot environment OS info is available (if already installed)
    if [ -f "$ROOTFS_DIR/etc/os-release" ]; then
        echo -e " GUEST OS -> ${BOLD_GREEN}$(grep "PRETTY_NAME" "$ROOTFS_DIR/etc/os-release" | cut -d'"' -f2)${RESET_COLOR}"
    fi
    echo -e ""
    # Display CPU info (best effort)
    if [ -f /proc/cpuinfo ]; then
        echo -e " CPU -> ${YELLOW}$(grep 'model name' /proc/cpuinfo | head -n 1 | cut -d':' -f2- | sed 's/^ *//')${RESET_COLOR}"
    fi
    # Use Pterodactyl environment variables if available
    echo -e " RAM -> ${BOLD_GREEN}${SERVER_MEMORY:-N/A}MB${RESET_COLOR}"
    echo -e " DISK -> ${BOLD_GREEN}${SERVER_DISK:-N/A}MB${RESET_COLOR}" # Added Disk
    echo -e " PRIMARY PORT -> ${BOLD_GREEN}${SERVER_PORT:-N/A}${RESET_COLOR}"
    # Correct variable for allocation limits (usually P_ALLOCATION_LIMIT)
    echo -e " EXTRA PORTS COUNT -> ${BOLD_GREEN}${P_ALLOCATION_LIMIT:-N/A}${RESET_COLOR}"
    echo -e " SERVER UUID -> ${BOLD_GREEN}${P_SERVER_UUID:-N/A}${RESET_COLOR}"
    echo -e " LOCATION -> ${BOLD_GREEN}${P_SERVER_LOCATION:-N/A}${RESET_COLOR}"
}

# Function for the footer
display_footer() {
    echo -e "${BOLD_MAGENTA}___________________________________________________${RESET_COLOR}"
    echo -e ""
    echo -e "           ${YELLOW}-----> STARTING VIRTUAL ENVIRONMENT <----${RESET_COLOR}"
    echo -e ""
}

# --- Main script execution ---
clear
display_header
display_resources
display_footer

###########################
# Start PRoot environment #
###########################

PROOT_BINARY="$ROOTFS_DIR/usr/local/bin/proot"

# Check if proot binary exists before trying to execute
if [ ! -x "$PROOT_BINARY" ]; then
    echo "Error: proot binary not found or not executable at $PROOT_BINARY"
    # Attempt to re-run installation steps (optional, could just exit)
    # echo "Attempting to reinstall..."
    # rm -f "$ROOTFS_DIR/.installed"
    # exec "$0" "$@" # Re-run the script
    exit 1
fi

# This command starts PRoot and binds several important directories
# from the host file system to our special root file system.
echo "Launching PRoot environment..."
exec "$PROOT_BINARY" \
    --rootfs="${ROOTFS_DIR}" \
    -0 \
    -w "/root" \
    -b /dev \
    -b /sys \
    -b /proc \
    -b /etc/resolv.conf:/etc/resolv.conf \
    -b /etc/hosts:/etc/hosts \
    -b /tmp \
    -b /home/container:/host \
    --kill-on-exit \
    /bin/sh -c "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && /bin/sh"

# Note: The exec command replaces the current shell process with proot.
# Commands after exec will not run unless proot fails immediately.
echo "Proot finished or failed to start."
exit 1 # Exit with error if exec fails
