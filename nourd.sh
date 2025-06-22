#!/bin/sh

#############################
# Linux Installation #
#############################

# Define the root directory to /home/container.
# We can only write in /home/container and /tmp in the container.
ROOTFS_DIR=/home/container

case ":$PATH:" in
  *":$LOCAL_BIN_PATH:"*)
    ;; # Already in PATH, do nothing.
  *)
    export PATH="$LOCAL_BIN_PATH:$PATH"
    ;;
esac


max_retries=50
timeout=3


# Detect the machine architecture.
ARCH=$(uname -m)

# Check machine architecture to make sure it is supported.
# If not, we exit with a non-zero status code.
if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT="amd64"
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT="arm64"
else
  printf "Unsupported CPU architecture: ${ARCH}"
  exit 1
fi

# Download & decompress the Linux root file system if not already installed.

if [ ! -e $ROOTFS_DIR/.installed ]; then
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

read -p "Enter OS (0-3): " input

case $input in

    0)
    wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
    "https://github.com/termux/proot-distro/releases/download/v4.7.0/debian-bullseye-${ARCH}-pd-v4.7.0.tar.xz"
    apt download xz-utils
    deb_file=$(find $ROOTFS_DIR -name "*.deb" -type f)
    dpkg -x $deb_file ~/.local/
    rm "$deb_file"
    
    tar -xJf /tmp/rootfs.tar.xz -C $ROOTFS_DIR --strip-components=1;;

    1)
    wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
    "https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-${ARCH}-pd-v4.18.0.tar.xz"
    apt download xz-utils
    deb_file=$(find $ROOTFS_DIR -name "*.deb" -type f)
    dpkg -x $deb_file ~/.local/
    rm "$deb_file"
    tar -xJf /tmp/rootfs.tar.xz -C $ROOTFS_DIR --strip-components=1;;

    2)
    wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.gz \
    "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/${ARCH}/alpine-minirootfs-3.22.0-${ARCH}.tar.gz"

    tar -xf /tmp/rootfs.tar.gz -C $ROOTFS_DIR;;

    *) # Added this default case
    echo "Invalid option or no input provided. Exiting."
    exit 1
    ;;
esac

fi

################################
# Package Installation & Setup #
################################

# Download static APK-Tools temporarily because minirootfs does not come with APK pre-installed.
if [ ! -e $ROOTFS_DIR/.installed ]; then
    # Download the packages from their sources
    mkdir -p $ROOTFS_DIR/usr/local/bin

    wget --tries=$max_retries --timeout=$timeout -O $ROOTFS_DIR/usr/local/bin/proot "https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"

  while [ ! -s "$ROOTFS_DIR/usr/local/bin/proot" ]; do
      rm -f $ROOTFS_DIR/usr/local/bin/proot
      wget --tries=$max_retries --timeout=$timeout -O $ROOTFS_DIR/usr/local/bin/proot "https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
  
      if [ -s "$ROOTFS_DIR/usr/local/bin/proot" ]; then
          # Make PRoot executable.
          chmod 755 $ROOTFS_DIR/usr/local/bin/proot
          break  # Exit the loop since the file is not empty
      fi
  done
  
  chmod 755 $ROOTFS_DIR/usr/local/bin/proot

fi

# Clean-up after installation complete & finish up.
if [ ! -e $ROOTFS_DIR/.installed ]; then
    # Add DNS Resolver nameservers to resolv.conf.
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1" > ${ROOTFS_DIR}/etc/resolv.conf
    # Wipe the files we downloaded into /tmp previously.
    rm -rf /tmp/*
    # Create .installed to later check whether Alpine is installed.
    touch $ROOTFS_DIR/.installed
fi

###################################################
# systemctl.py (systemctl replacement) Setup      #
###################################################
SYSTEMCTL_PY_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
SYSTEMCTL_PY_INSTALL_DIR="$ROOTFS_DIR/usr/local/bin"
SYSTEMCTL_PY_INSTALL_PATH="$SYSTEMCTL_PY_INSTALL_DIR/systemctl" # Installs as 'systemctl'

echo "" # Newline for cleaner output
echo "INFO: Checking for systemctl.py (systemctl replacement) updates..."

# Ensure target directory exists within the ROOTFS
mkdir -p "$SYSTEMCTL_PY_INSTALL_DIR"

# Get latest version from remote
# Suppress wget progress (q) and output to stdout (O-), redirect stderr to /dev/null (2>/dev/null)
LATEST_VERSION_OUTPUT=$(wget -qO- "$SYSTEMCTL_PY_URL" 2>/dev/null | grep "__version__ =" | head -n1 | cut -d'"' -f2)

if [ -z "$LATEST_VERSION_OUTPUT" ]; then
    echo "WARN: Could not fetch the latest version of systemctl.py. Skipping update check."
else
    echo "INFO: Latest available systemctl.py version from remote: $LATEST_VERSION_OUTPUT"
    CURRENT_VERSION_OUTPUT=""
    if [ -f "$SYSTEMCTL_PY_INSTALL_PATH" ]; then
        CURRENT_VERSION_OUTPUT=$(grep "__version__ =" "$SYSTEMCTL_PY_INSTALL_PATH" | head -n1 | cut -d'"' -f2)
        if [ -z "$CURRENT_VERSION_OUTPUT" ]; then
             echo "INFO: Installed systemctl.py found, but version could not be determined (possibly corrupted or old version)."
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
        
        TEMP_SYSTEMCTL_PY="/tmp/systemctl.py.download" # Use a distinct name in /tmp
        wget --tries=$max_retries --timeout=$timeout -O "$TEMP_SYSTEMCTL_PY" "$SYSTEMCTL_PY_URL"
        
        if [ $? -eq 0 ] && [ -s "$TEMP_SYSTEMCTL_PY" ]; then
            # Basic sanity check for the downloaded file
            if grep -q "__version__ =" "$TEMP_SYSTEMCTL_PY"; then
                mv "$TEMP_SYSTEMCTL_PY" "$SYSTEMCTL_PY_INSTALL_PATH"
                chmod 755 "$SYSTEMCTL_PY_INSTALL_PATH"
                echo "INFO: systemctl.py has been successfully installed/updated to version $LATEST_VERSION_OUTPUT."
                echo "IMPORTANT: To use the 'systemctl' command, 'python3' must be installed in the selected OS."
                echo "           (e.g., 'apt update && apt install python3' for Debian/Ubuntu, or 'apk add python3' for Alpine)"
            else
                echo "ERROR: Downloaded systemctl.py appears to be corrupted. Aborting installation/update."
                rm -f "$TEMP_SYSTEMCTL_PY"
            fi
        else
            echo "ERROR: Failed to download systemctl.py. Please check your network or the URL: $SYSTEMCTL_PY_URL"
            if [ -f "$TEMP_SYSTEMCTL_PY" ]; then # Clean up temp file if download failed but file exists
                rm -f "$TEMP_SYSTEMCTL_PY"
            fi
        fi
    else
        echo "INFO: systemctl.py is already up to date (version $CURRENT_VERSION_OUTPUT)."
    fi
fi
echo "" # Newline for cleaner output
###################################################
# End systemctl.py Setup                          #
###################################################


# Print some useful information to the terminal before entering PRoot.
# This is to introduce the user with the various Alpine Linux commands.
# Define color variables
BLACK='\e[0;30m'
BOLD_BLACK='\e[1;30m'
RED='\e[0;31m'
BOLD_RED='\e[1;31m'
GREEN='\e[0;32m'
BOLD_GREEN='\e[1;32m'
YELLOW='\e[0;33m'
BOLD_YELLOW='\e[1;33m'
BLUE='\e[0;34m'
BOLD_BLUE='\e[1;34m'
MAGENTA='\e[0;35m'
BOLD_MAGENTA='\e[1;35m'
CYAN='\e[0;36m'
BOLD_CYAN='\e[1;36m'
WHITE='\e[0;37m'
BOLD_WHITE='\e[1;37m'

# Reset text color
RESET_COLOR='\e[0m'


# Function to display the header
display_header() {
    echo -e "${BOLD_MAGENTA} __      __        ______"
    echo -e "${BOLD_MAGENTA} \ \    / /       |  ____|"
    echo -e "${BOLD_MAGENTA}  \ \  / / __  ___| |__ _ __ ___  ___   ___  ___"
    echo -e "${BOLD_MAGENTA}   \ \/ / '_ \/ __|  __| '__/ _ \/ _ \ / _ \/ __|"
    echo -e "${BOLD_MAGENTA}    \  /| |_) \__ \ |  | | |  __/  __/|  __/\__ \\"
    echo -e "${BOLD_MAGENTA}     \/ | .__/|___/_|  |_|  \___|\___(_)___||___/"
    echo -e "${BOLD_MAGENTA}        | |"
    echo -e "${BOLD_MAGENTA}        |_|"
    echo -e "${BOLD_MAGENTA}___________________________________________________"
    echo -e "           ${YELLOW}-----> System Resources <----${RESET_COLOR}"
    echo -e "Done (s)! For help, type "help" change this text"
}

# Function to display system resources
display_resources() {
    echo -e " INSTALLER OS -> ${RED} $(cat $ROOTFS_DIR/etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2) ${RESET_COLOR}"
    echo -e " CPU -> ${YELLOW} $(cat /proc/cpuinfo | grep 'model name' | cut -d':' -f2- | sed 's/^ *//;s/  \+/ /g' | head -n 1) ${RESET_COLOR}"
    echo -e " RAM -> ${BOLD_GREEN}${SERVER_MEMORY}MB${RESET_COLOR}"
    echo -e " PRIMARY PORT -> ${BOLD_GREEN}${SERVER_PORT}${RESET_COLOR}"
    echo -e " EXTRA PORTS -> ${BOLD_GREEN}${P_SERVER_ALLOCATION_LIMIT}${RESET_COLOR}"
    echo -e " SERVER UUID -> ${BOLD_GREEN}${P_SERVER_UUID}${RESET_COLOR}"
    echo -e " LOCATION -> ${BOLD_GREEN}${P_SERVER_LOCATION}${RESET_COLOR}"
}

display_footer() {
	echo -e "${BOLD_MAGENTA}___________________________________________________${RESET_COLOR}"
	echo -e ""
    echo -e "           ${YELLOW}-----> VPS HAS STARTED <----${RESET_COLOR}"
}

# Main script execution
display_header
display_resources
display_footer


###########################
# Start PRoot environment #
###########################

# This command starts PRoot and binds several important directories
# from the host file system to our special root file system.
$ROOTFS_DIR/usr/local/bin/proot --rootfs="${ROOTFS_DIR}" -0 -l -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit
