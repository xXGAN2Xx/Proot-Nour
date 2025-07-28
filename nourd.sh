#!/bin/sh

#############################
# Linux Installation #
#############################

# Define the root directory to /home/container.
# We can only write in /home/container and /tmp in the container.
ROOTFS_DIR=/home/container
# Define the directory for locally installed binaries
LOCAL_BIN_DIR="$HOME/.local/usr/bin"

max_retries=5
timeout=4

# Function to prepend a directory to PATH if it's not already there and the directory exists
prepend_to_path() {
    local dir_to_add="$1"
    # Ensure the directory exists before adding to PATH
    if [ -d "$dir_to_add" ]; then
        case ":${PATH}:" in
            *":${dir_to_add}:"*) :;; # Already present
            *) export PATH="${dir_to_add}:${PATH}" ;; # Prepend and export
        esac
    fi
}

# Ensure $LOCAL_BIN_DIR exists (it might not initially, dpkg -x will create structure within it)
mkdir -p "$LOCAL_BIN_DIR"
# Add $LOCAL_BIN_DIR to PATH. It will be populated by dpkg -x later.
# This makes any binaries extracted there available for the rest of the script.
prepend_to_path "$LOCAL_BIN_DIR"

# Detect the machine architecture.
ARCH=$(uname -m)

# Check machine architecture to make sure it is supported.
# If not, we exit with a non-zero status code.
if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT="amd64"
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT="arm64"
else
  printf "Unsupported CPU architecture: ${ARCH}\n" # Added newline for clarity
  exit 1
fi

# Download & decompress the Linux root file system if not already installed.
if [ ! -e "$ROOTFS_DIR/.installed" ]; then # Quoted variable
    echo "INFO: Attempting to install wget locally..."
    # Assuming 'apt' and 'dpkg' are available in the base environment.
    # 'apt download' typically downloads to the current working directory.
    # Given script constraints, CWD is likely $ROOTFS_DIR.
    apt download wget
    
    # Find the downloaded wget .deb file more specifically
    # (Assumes GNU find for -print -quit; use `... -print | head -n1` for broader compatibility if needed)
    deb_file_wget=$(find "$ROOTFS_DIR" -maxdepth 1 -name "wget_*.deb" -type f -print -quit)

    if [ -n "$deb_file_wget" ]; then
        echo "INFO: Extracting wget from $deb_file_wget to $HOME/.local/"
        dpkg -x "$deb_file_wget" "$HOME/.local/" # Extracts to $HOME/.local/usr/bin etc.
        rm "$deb_file_wget"
        # wget should now be available from $LOCAL_BIN_DIR, which was added to PATH earlier.
        if ! command -v wget >/dev/null 2>&1; then
            echo "WARN: wget installed to $LOCAL_BIN_DIR but still not found in PATH. Check installation."
        else
            echo "INFO: Custom wget is now available in PATH."
        fi
    else
        echo "WARN: wget .deb file not found after 'apt download'."
        if command -v wget >/dev/null 2>&1; then
            echo "INFO: Using system-provided wget."
        else
            echo "ERROR: wget is not available. Cannot proceed with downloads."
            exit 1
        fi
    fi

    echo "#######################################################################################"
    echo "#"
    echo "#                                  VPSFREE.ES PteroVM"
    echo "#"
    echo "#                           Copyright (C) 2022 - 2023, VPSFREE.ES"
    echo "#"
    echo "#"
    echo "#######################################################################################"
    echo ""
    echo "* [0] Debian"
    echo "* [1] Ubuntu"
    echo "* [2] Alpine"

    read -p "Enter OS (0-2): " input # Corrected range

    case $input in
        0) # Debian
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
        "https://github.com/termux/proot-distro/releases/download/v4.7.0/debian-bullseye-${ARCH}-pd-v4.7.0.tar.xz"
        
        echo "INFO: Attempting to install xz-utils locally for .tar.xz decompression..."
        apt download xz-utils
        deb_file_xz=$(find "$ROOTFS_DIR" -maxdepth 1 -name "xz-utils_*.deb" -type f -print -quit)
        if [ -n "$deb_file_xz" ]; then
            echo "INFO: Extracting xz-utils from $deb_file_xz to $HOME/.local/"
            dpkg -x "$deb_file_xz" "$HOME/.local/"
            rm "$deb_file_xz"
            # xz command should now be available from $LOCAL_BIN_DIR for tar.
             if ! command -v xz >/dev/null 2>&1 && [ -e "$LOCAL_BIN_DIR/xz" ]; then
                echo "WARN: xz installed to $LOCAL_BIN_DIR but still not found in PATH. Check installation."
            else
                echo "INFO: Custom xz-utils (for xz) is now available in PATH."
            fi
        else
            echo "WARN: xz-utils .deb file not found after 'apt download'."
            if ! command -v xz >/dev/null 2>&1; then
                 echo "WARN: xz command not found. Tar extraction for .xz may fail if tar relies on external xz."
            else
                 echo "INFO: Using system-provided xz."
            fi
        fi
        tar -xJf /tmp/rootfs.tar.xz -C "$ROOTFS_DIR" --strip-components=1;;

        1) # Ubuntu
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
        "https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-${ARCH}-pd-v4.18.0.tar.xz"

        echo "INFO: Attempting to install xz-utils locally for .tar.xz decompression..."
        apt download xz-utils
        deb_file_xz=$(find "$ROOTFS_DIR" -maxdepth 1 -name "xz-utils_*.deb" -type f -print -quit)
        if [ -n "$deb_file_xz" ]; then
            echo "INFO: Extracting xz-utils from $deb_file_xz to $HOME/.local/"
            dpkg -x "$deb_file_xz" "$HOME/.local/"
            rm "$deb_file_xz"
            if ! command -v xz >/dev/null 2>&1 && [ -e "$LOCAL_BIN_DIR/xz" ]; then
                echo "WARN: xz installed to $LOCAL_BIN_DIR but still not found in PATH. Check installation."
            else
                echo "INFO: Custom xz-utils (for xz) is now available in PATH."
            fi
        else
            echo "WARN: xz-utils .deb file not found after 'apt download'."
            if ! command -v xz >/dev/null 2>&1; then
                 echo "WARN: xz command not found. Tar extraction for .xz may fail if tar relies on external xz."
            else
                 echo "INFO: Using system-provided xz."
            fi
        fi
        tar -xJf /tmp/rootfs.tar.xz -C "$ROOTFS_DIR" --strip-components=1;;

        2) # Alpine
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.gz \
        "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/${ARCH}/alpine-minirootfs-3.22.0-${ARCH}.tar.gz"
        # System tar should handle .gz; xz-utils not typically needed for this.
        tar -xf /tmp/rootfs.tar.gz -C "$ROOTFS_DIR";;

        *)
        echo "Invalid option or no input provided. Exiting."
        exit 1
        ;;
    esac
fi

################################
# Package Installation & Setup #
################################

# Download static proot
if [ ! -e "$ROOTFS_DIR/.installed" ]; then # Quoted variable
    mkdir -p "$ROOTFS_DIR/usr/local/bin"

    echo "INFO: Downloading proot static binary..."
    # Ensure proot is downloaded successfully and is not empty
    # Original script had a while loop here, which is good for retrying flaky downloads.
    # Keeping the while loop logic for proot download.
    proot_path="$ROOTFS_DIR/usr/local/bin/proot"
    proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    
    current_try=0
    max_download_retries=3 # Define max retries for proot download specifically if needed

    while [ ! -s "$proot_path" ]; do
        current_try=$((current_try + 1))
        if [ "$current_try" -gt "$max_download_retries" ]; then
            echo "ERROR: Failed to download proot after $max_download_retries attempts. Exiting."
            exit 1
        fi
        echo "INFO: Attempt $current_try to download proot..."
        rm -f "$proot_path" # Remove potentially empty or partial file
        wget --tries=$max_retries --timeout=$timeout -O "$proot_path" "$proot_url"
        
        if [ -s "$proot_path" ]; then
            echo "INFO: proot downloaded successfully."
            break
        else
            echo "WARN: proot download failed or file is empty. Retrying..."
            sleep 2 # Wait a bit before retrying
        fi
    done
  
  chmod 755 "$proot_path"
fi

# Clean-up after installation complete & finish up.
if [ ! -e "$ROOTFS_DIR/.installed" ]; then # Quoted variable
    # Add DNS Resolver nameservers to resolv.conf.
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1" > "${ROOTFS_DIR}/etc/resolv.conf"
    # Wipe the files we downloaded into /tmp previously.
    rm -rf /tmp/*
    # Create .installed to later check whether OS is installed.
    touch "$ROOTFS_DIR/.installed" # Quoted variable
fi

###################################################
# systemctl.py (systemctl replacement) Setup      #
###################################################
SYSTEMCTL_PY_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
SYSTEMCTL_PY_INSTALL_DIR="$ROOTFS_DIR/usr/local/bin"
SYSTEMCTL_PY_INSTALL_PATH="$SYSTEMCTL_PY_INSTALL_DIR/systemctl" # Installs as 'systemctl'

echo "" 
echo "INFO: Checking for systemctl.py (systemctl replacement) updates..."

mkdir -p "$SYSTEMCTL_PY_INSTALL_DIR"

LATEST_VERSION_OUTPUT=$(wget -qO- "$SYSTEMCTL_PY_URL" 2>/dev/null | grep "__version__ =" | head -n1 | cut -d'"' -f2)

if [ -z "$LATEST_VERSION_OUTPUT" ]; then
    echo "WARN: Could not fetch the latest version of systemctl.py. Skipping update check."
else
    echo "INFO: Latest available systemctl.py version from remote: $LATEST_VERSION_OUTPUT"
    CURRENT_VERSION_OUTPUT=""
    if [ -f "$SYSTEMCTL_PY_INSTALL_PATH" ]; then
        CURRENT_VERSION_OUTPUT=$(grep "__version__ =" "$SYSTEMCTL_PY_INSTALL_PATH" | head -n1 | cut -d'"' -f2)
        if [ -z "$CURRENT_VERSION_OUTPUT" ]; then
             echo "INFO: Installed systemctl.py found, but version could not be determined."
        else
             echo "INFO: Currently installed systemctl.py version: $CURRENT_VERSION_OUTPUT"
        fi
    else
        echo "INFO: systemctl.py is not currently installed."
    fi

    if [ "$LATEST_VERSION_OUTPUT" != "$CURRENT_VERSION_OUTPUT" ] || [ ! -f "$SYSTEMCTL_PY_INSTALL_PATH" ]; then
        if [ ! -f "$SYSTEMCTL_PY_INSTALL_PATH" ]; then
            echo "INFO: Downloading and installing systemctl.py version $LATEST_VERSION_OUTPUT..."
        else
            echo "INFO: Updating systemctl.py from $CURRENT_VERSION_OUTPUT to $LATEST_VERSION_OUTPUT..."
        fi
        
        TEMP_SYSTEMCTL_PY="/tmp/systemctl.py.download"
        wget --tries=$max_retries --timeout=$timeout -O "$TEMP_SYSTEMCTL_PY" "$SYSTEMCTL_PY_URL"
        
        if [ $? -eq 0 ] && [ -s "$TEMP_SYSTEMCTL_PY" ]; then
            if grep -q "__version__ =" "$TEMP_SYSTEMCTL_PY"; then
                mv "$TEMP_SYSTEMCTL_PY" "$SYSTEMCTL_PY_INSTALL_PATH"
                chmod 755 "$SYSTEMCTL_PY_INSTALL_PATH"
                echo "INFO: systemctl.py has been successfully installed/updated to version $LATEST_VERSION_OUTPUT."
                echo "IMPORTANT: To use 'systemctl', 'python3' must be installed in the selected OS."
            else
                echo "ERROR: Downloaded systemctl.py appears to be corrupted. Aborting."
                rm -f "$TEMP_SYSTEMCTL_PY"
            fi
        else
            echo "ERROR: Failed to download systemctl.py. Check network or URL: $SYSTEMCTL_PY_URL"
            rm -f "$TEMP_SYSTEMCTL_PY" 2>/dev/null # Clean up temp file if it exists
        fi
    else
        echo "INFO: systemctl.py is already up to date (version $CURRENT_VERSION_OUTPUT)."
    fi
fi
echo "" 
###################################################
# End systemctl.py Setup                          #
###################################################


# Print some useful information
BLACK='\e[0;30m'; BOLD_BLACK='\e[1;30m'; RED='\e[0;31m'; BOLD_RED='\e[1;31m'
GREEN='\e[0;32m'; BOLD_GREEN='\e[1;32m'; YELLOW='\e[0;33m'; BOLD_YELLOW='\e[1;33m'
BLUE='\e[0;34m'; BOLD_BLUE='\e[1;34m'; MAGENTA='\e[0;35m'; BOLD_MAGENTA='\e[1;35m'
CYAN='\e[0;36m'; BOLD_CYAN='\e[1;36m'; WHITE='\e[0;37m'; BOLD_WHITE='\e[1;37m'
RESET_COLOR='\e[0m'

display_header() {
    echo -e "${BOLD_MAGENTA} __      __        ______"
    # ... (rest of display_header, display_resources, display_footer) ...
    echo -e "${BOLD_MAGENTA} \ \    / /       |  ____|"
    echo -e "${BOLD_MAGENTA}  \ \  / / __  ___| |__ _ __ ___  ___   ___  ___"
    echo -e "${BOLD_MAGENTA}   \ \/ / '_ \/ __|  __| '__/ _ \/ _ \ / _ \/ __|"
    echo -e "${BOLD_MAGENTA}    \  /| |_) \__ \ |  | | |  __/  __/|  __/\__ \\"
    echo -e "${BOLD_MAGENTA}     \/ | .__/|___/_|  |_|  \___|\___(_)___||___/"
    echo -e "${BOLD_MAGENTA}        | |"
    echo -e "${BOLD_MAGENTA}        |_|"
    echo -e "${BOLD_MAGENTA}___________________________________________________"
    echo -e "           ${YELLOW}-----> System Resources <----${RESET_COLOR}"
    echo -e "Done (s)! For help, type "help" change this text" # Consider updating this message
}

display_resources() {
    local os_pretty_name="N/A"
    if [ -f "$ROOTFS_DIR/etc/os-release" ]; then
        os_pretty_name=$(cat "$ROOTFS_DIR/etc/os-release" | grep "PRETTY_NAME" | cut -d'"' -f2)
    fi
    local cpu_model="N/A"
    if [ -f "/proc/cpuinfo" ]; then
        cpu_model=$(cat /proc/cpuinfo | grep 'model name' | cut -d':' -f2- | sed 's/^ *//;s/  \+/ /g' | head -n 1)
    fi
    echo -e " INSTALLED OS -> ${RED}${os_pretty_name}${RESET_COLOR}"
    echo -e " CPU -> ${YELLOW}${cpu_model}${RESET_COLOR}"
    echo -e " RAM -> ${BOLD_GREEN}${SERVER_MEMORY:-N/A}MB${RESET_COLOR}" # Added default for SERVER_MEMORY
    echo -e " PRIMARY PORT -> ${BOLD_GREEN}${SERVER_PORT:-N/A}${RESET_COLOR}" # Added default
    echo -e " EXTRA PORTS -> ${BOLD_GREEN}${P_SERVER_ALLOCATION_LIMIT:-N/A}${RESET_COLOR}" # Added default
    echo -e " SERVER UUID -> ${BOLD_GREEN}${P_SERVER_UUID:-N/A}${RESET_COLOR}" # Added default
    echo -e " LOCATION -> ${BOLD_GREEN}${P_SERVER_LOCATION:-N/A}${RESET_COLOR}" # Added default
}

display_footer() {
	echo -e "${BOLD_MAGENTA}___________________________________________________${RESET_COLOR}"
	echo -e ""
    echo -e "           ${YELLOW}-----> VPS HAS STARTED <----${RESET_COLOR}"
}

display_header
display_resources
display_footer

###########################
# Start PRoot environment #
###########################

# This command starts PRoot and binds several important directories
# from the host file system to our special root file system.
"$ROOTFS_DIR/usr/local/bin/proot" --rootfs="${ROOTFS_DIR}" -0 -n -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit
