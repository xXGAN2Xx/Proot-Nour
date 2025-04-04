#!/bin/sh
# Exit immediately if a command exits with a non-zero status.
set -e
#############################
# Linux Installation #
#############################

# Define the root directory to /home/container.
# We can only write in /home/container and /tmp in the container.
ROOTFS_DIR=/home/container

export PATH=$PATH:~/.local/usr/bin


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
echo "#                                  Nour PteroVM"
echo "#"
echo "#######################################################################################"
echo ""
echo "* [0] Ubuntu"
echo "* [1] Alpine"

read -p "Enter OS (0-1): " input

case $input in

    0)
    wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
    "https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-${ARCH}-pd-v4.18.0.tar.xz"
    apt download xz-utils
    deb_file=$(ls xz-utils_*.deb)
    dpkg -x "$deb_file" ~/.local/
    rm "$deb_file"
    export PATH=~/.local/usr/bin:$PATH
    tar -xJvf /tmp/rootfs.tar.xz -C $ROOTFS_DIR --strip-components=1;;

    1)
    wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
    "https://github.com/termux/proot-distro/releases/download/v4.21.0/alpine-${ARCH}-pd-v4.21.0.tar.xz"
    apt download xz-utils
    deb_file=$(ls xz-utils_*.deb)
    dpkg -x "$deb_file" ~/.local/
    rm "$deb_file"
    export PATH=~/.local/usr/bin:$PATH
    tar -xJvf /tmp/rootfs.tar.xz -C $ROOTFS_DIR --strip-components=1;;

esac

fi

################################
# Package Installation & Setup #
################################

# Download static APK-Tools temporarily because minirootfs does not come with APK pre-installed.
if [ ! -e $ROOTFS_DIR/.installed ]; then
    # Download the packages from their sources
    mkdir $ROOTFS_DIR/usr/local/bin -p

    wget --tries=$max_retries --timeout=$timeout -O $ROOTFS_DIR/usr/local/bin/proot "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"

  while [ ! -s "$ROOTFS_DIR/usr/local/bin/proot" ]; do
      rm $ROOTFS_DIR/usr/local/bin/proot -rf
      wget --tries=$max_retries --timeout=$timeout -O $ROOTFS_DIR/usr/local/bin/proot "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
  
      if [ -s "$ROOTFS_DIR/usr/local/bin/proot" ]; then
          # Make PRoot executable.
          chmod +x $ROOTFS_DIR/usr/local/bin/proot
          break  # Exit the loop since the file is not empty
      fi
      
      chmod +x $ROOTFS_DIR/usr/local/bin/proot
      sleep 1  # Add a delay before retrying to avoid hammering the server
  done
  
  chmod +x $ROOTFS_DIR/usr/local/bin/proot

fi

# Clean-up after installation complete & finish up.
if [ ! -e $ROOTFS_DIR/.installed ]; then
    # Add DNS Resolver nameservers to resolv.conf.
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1" > ${ROOTFS_DIR}/etc/resolv.conf
    # Wipe the files we downloaded into /tmp previously.
    rm -rf /tmp/rootfs.tar.xz /tmp/sbin
    # Create .installed to later check whether Alpine is installed.
    touch $ROOTFS_DIR/.installed
fi

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
    echo -e ""
}

# Function to display system resources
display_resources() {
	echo -e " INSTALLER OS -> ${RED} $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2) ${RESET_COLOR}"
	echo -e ""
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
clear

display_header
display_resources
display_footer


###########################
# Start PRoot environment #
###########################

# This command starts PRoot and binds several important directories
# from the host file system to our special root file system.
$ROOTFS_DIR/usr/local/bin/proot --rootfs="${ROOTFS_DIR}" -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit
