#!/bin/sh

#############################
# Fun and Interactive Linux Installation #
#############################

# Define the root directory to /home/container.
ROOTFS_DIR=/home/runner/vpsfreepterovm

export PATH=$PATH:~/.local/usr/bin

max_retries=50
timeout=3

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
RESET_COLOR='\e[0m'  # Reset text color

# Detect the machine architecture
ARCH=$(uname -m)

# Supported architectures check
if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT="amd64"
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT="arm64"
else
  echo -e "${BOLD_RED}Oops! Unsupported CPU architecture: ${ARCH}. Maybe time for an upgrade?${RESET_COLOR}"
  exit 1
fi

# Check if the root filesystem is already installed
if [ -e $ROOTFS_DIR/.installed ]; then
  echo -e "${GREEN}The system is already installed. Skipping installation steps.${RESET_COLOR}"
else
  # Fun OS options (displayed only if installation is not done)
  fun_os_choices() {
    echo -e "${BOLD_BLUE}#######################################################################################"
    echo -e "${BOLD_BLUE}#"
    echo -e "${BOLD_BLUE}#                                  Welcome to the TRHACKNON PteroVM Installer!"
    echo -e "${BOLD_BLUE}#"
    echo -e "${BOLD_BLUE}#                           Sit back and let us handle the boring stuff!"
    echo -e "${BOLD_BLUE}#######################################################################################${RESET_COLOR}"
    echo ""
    echo -e "${CYAN}Choose your flavor of Linux: "
    echo -e "  ${BOLD_GREEN}[0] Debian${RESET_COLOR} - Classic, stable, like your favorite pair of old jeans."
    echo -e "  ${BOLD_GREEN}[1] Ubuntu${RESET_COLOR} - Friendly and everywhere, like a nice warm coffee!"
    echo -e "  ${BOLD_GREEN}[2] Alpine${RESET_COLOR} - Lightweight and efficient, for the minimalist in you."
    echo -e "  ${BOLD_GREEN}[3] Fedora${RESET_COLOR} - Cutting-edge and sleek, for the trendsetters."
    echo ""
    read -p "Enter OS (0-3): " input
  }

  # Main installation function
  install_rootfs() {
    case $input in
      0)
        echo -e "${YELLOW}Debian it is! A solid choice. Let's get to work!${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
        "https://github.com/termux/proot-distro/releases/download/v4.7.0/debian-bullseye-${ARCH}-pd-v4.7.0.tar.xz"
        apt download xz-utils
        ;;
      1)
        echo -e "${YELLOW}Ubuntu, a user-friendly choice. You'll be up and running in no time!${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.gz \
        "https://github.com/termux/proot-distro/releases/download/v4.11.0/ubuntu-jammy-${ARCH}-pd-v4.11.0.tar.xz"
        ;;
      2)
        echo -e "${YELLOW}Alpine it is! Small, fast, and efficient, just like you!${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.gz \
        "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-${ARCH}.tar.gz"
        ;;
      3)
        echo -e "${YELLOW}Fedora, living on the edge. Bold choice!${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
        "https://github.com/termux/proot-distro/releases/download/v4.11.0/ubuntu-noble-${ARCH}-pd-v4.11.0.tar.xz"
        ;;
      *)
        echo -e "${RED}Invalid choice! Let's stick with Debian.${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
        "https://github.com/termux/proot-distro/releases/download/v4.7.0/debian-bullseye-${ARCH}-pd-v4.7.0.tar.xz"
        ;;
    esac

    echo -e "${YELLOW}Extracting the root filesystem...${RESET_COLOR}"
    tar -xf /tmp/rootfs.tar.* -C $ROOTFS_DIR --strip-components=1

    # Creating .installed file after successful installation
    touch $ROOTFS_DIR/.installed
    echo -e "${GREEN}Root filesystem installed successfully and .installed file created!${RESET_COLOR}"
  }

  # Run the OS choice and installation if not installed
  fun_os_choices
  install_rootfs
fi

# Fun header
fun_header() {
  echo -e "${BOLD_RED}  __      __        ______"
  echo -e "${BOLD_YELLOW}  \\ \\    / /       |  ____|"
  echo -e "${BOLD_GREEN}   \\ \\  / / __  ___| |__ _ __ ___  ___   ___  ___"
  echo -e "${BOLD_CYAN}    \\ \\/ / '_ \\/ __|  __| '__/ _ \\/ _ \\ / _ \\/ __|"
  echo -e "${BOLD_BLUE}     \\  /| |_) \\__ \\ |  | | |  __/  __/|  __/\\__ \\"
  echo -e "${BOLD_MAGENTA}      \\/ | .__/|___/_|  |_|  \\___|\\___(_)___||___/"
  echo -e "${BOLD_WHITE}         | |"
  echo -e "${BOLD_YELLOW}         |_|"
  echo -e "${BOLD_GREEN}___________________________________________________"
  echo -e "          ${BOLD_CYAN}-----> Fun System Resources <----${RESET_COLOR}"
  echo -e "${BOLD_RED}            Powered by ${BOLD_WHITE}TRHACKNON${RESET_COLOR}"
}

# Fun system resources display
fun_resources() {
  # Get CPU info
  CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ //g')
  CPU_CORES=$(grep -c 'processor' /proc/cpuinfo)

  # Get RAM info (in MB)
  TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
  USED_RAM=$(free -m | awk '/Mem:/ {print $3}')
  FREE_RAM=$(free -m | awk '/Mem:/ {print $4}')

  # Get disk usage (in human-readable form)
  DISK_USAGE=$(df -h / | awk 'NR==2 {print $3 " used out of " $2}')

  # Get system uptime (replacing 'uptime -p' for compatibility)
  UPTIME=$(awk '{print int($1/3600)" hours, "int($1%3600/60)" minutes"}' /proc/uptime)

  echo -e "${BOLD_MAGENTA} CPU Model -> ${YELLOW}$CPU_MODEL${RESET_COLOR}"
  echo -e "${BOLD_CYAN} CPU Cores -> ${GREEN}$CPU_CORES${RESET_COLOR}"
  echo -e "${BOLD_BLUE} RAM Total -> ${RED}$TOTAL_RAM MB${RESET_COLOR}"
  echo -e "${BOLD_YELLOW} RAM Used -> ${MAGENTA}$USED_RAM MB${RESET_COLOR}"
  echo -e "${BOLD_GREEN} RAM Free -> ${CYAN}$FREE_RAM MB${RESET_COLOR}"
  echo -e "${BOLD_RED} Disk Usage -> ${BOLD_WHITE}$DISK_USAGE${RESET_COLOR}"
  echo -e "${BOLD_YELLOW} Uptime -> ${BOLD_GREEN}$UPTIME${RESET_COLOR}"
}

# Footer to wrap up
fun_footer() {
  echo -e "${BOLD_GREEN}___________________________________________________${RESET_COLOR}"
  echo -e ""
  echo -e "${BOLD_MAGENTA}     -----> Your VPS is now live and kicking! <----${RESET_COLOR}"
  echo -e "${BOLD_BLUE} Time to get your hands dirty and unleash the power of Linux!${RESET_COLOR}"
  echo -e "${BOLD_RED}               Script crafted by ${BOLD_WHITE}TRHACKNON${RESET_COLOR}"
}

# Main script
clear

fun_header
fun_resources
fun_footer

###########################
# Start PRoot environment #
###########################
$ROOTFS_DIR/usr/local/bin/proot --rootfs="${ROOTFS_DIR}" -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit
