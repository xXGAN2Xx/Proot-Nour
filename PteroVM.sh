#!/bin/sh

#############################
# Fun and Interactive Linux Installation #
#############################

# Define the root directory in a location that should be writable
# Using /tmp which is typically writable in most environments
ROOTFS_DIR=/tmp/vpsfreepterovm

# Create the directory if it doesn't exist
mkdir -p $ROOTFS_DIR

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
    echo "$input"
  }

  # Main installation function
  install_rootfs() {
    local os_choice=$1
    
    case $os_choice in
      0)
        echo -e "${YELLOW}Debian it is! A solid choice. Let's get to work!${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
        "https://github.com/termux/proot-distro/releases/download/v4.7.0/debian-bullseye-${ARCH}-pd-v4.7.0.tar.xz" || {
          echo -e "${RED}Failed to download Debian rootfs. Check your network connection.${RESET_COLOR}"
          return 1
        }
        command -v apt-get >/dev/null && { apt-get update && apt-get install -y xz-utils; } || true
        ;;
      1)
        echo -e "${YELLOW}Ubuntu, a user-friendly choice. You'll be up and running in no time!${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
        "https://github.com/termux/proot-distro/releases/download/v4.11.0/ubuntu-jammy-${ARCH}-pd-v4.11.0.tar.xz" || {
          echo -e "${RED}Failed to download Ubuntu rootfs. Check your network connection.${RESET_COLOR}"
          return 1
        }
        command -v apt-get >/dev/null && { apt-get update && apt-get install -y xz-utils; } || true
        ;;
      2)
        echo -e "${YELLOW}Alpine it is! Small, fast, and efficient, just like you!${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.gz \
        "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-${ARCH}.tar.gz" || {
          echo -e "${RED}Failed to download Alpine rootfs. Check your network connection.${RESET_COLOR}"
          return 1
        }
        ;;
      3)
        echo -e "${YELLOW}Fedora, living on the edge. Bold choice!${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
        "https://github.com/termux/proot-distro/releases/download/v4.11.0/ubuntu-noble-${ARCH}-pd-v4.11.0.tar.xz" || {
          echo -e "${RED}Failed to download Fedora rootfs. Check your network connection.${RESET_COLOR}"
          return 1
        }
        command -v apt-get >/dev/null && { apt-get update && apt-get install -y xz-utils; } || true
        ;;
      *)
        echo -e "${RED}Invalid choice! Let's stick with Debian.${RESET_COLOR}"
        wget --tries=$max_retries --timeout=$timeout -O /tmp/rootfs.tar.xz \
        "https://github.com/termux/proot-distro/releases/download/v4.7.0/debian-bullseye-${ARCH}-pd-v4.7.0.tar.xz" || {
          echo -e "${RED}Failed to download Debian rootfs. Check your network connection.${RESET_COLOR}"
          return 1
        }
        command -v apt-get >/dev/null && { apt-get update && apt-get install -y xz-utils; } || true
        ;;
    esac

    echo -e "${YELLOW}Extracting the root filesystem...${RESET_COLOR}"
    if [[ "$os_choice" == "2" ]]; then
      tar -xf /tmp/rootfs.tar.gz -C $ROOTFS_DIR || {
        echo -e "${RED}Failed to extract root filesystem.${RESET_COLOR}"
        return 1
      }
    else
      tar -xf /tmp/rootfs.tar.xz -C $ROOTFS_DIR --strip-components=1 || {
        echo -e "${RED}Failed to extract root filesystem.${RESET_COLOR}"
        return 1
      }
    fi

    # Creating .installed file after successful installation
    touch $ROOTFS_DIR/.installed
    echo -e "${GREEN}Root filesystem installed successfully and .installed file created!${RESET_COLOR}"
    return 0
  }

  # Run the OS choice and installation if not installed
  input=$(fun_os_choices)
  install_rootfs "$input" || {
    echo -e "${BOLD_RED}Installation failed. Please check error messages above.${RESET_COLOR}"
    exit 1
  }
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
  CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d ':' -f 2 | sed 's/^ //g' || echo "Unknown CPU")
  CPU_CORES=$(grep -c 'processor' /proc/cpuinfo 2>/dev/null || echo "Unknown")

  # Get RAM info (in MB)
  TOTAL_RAM=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo "Unknown")
  USED_RAM=$(free -m 2>/dev/null | awk '/Mem:/ {print $3}' || echo "Unknown")
  FREE_RAM=$(free -m 2>/dev/null | awk '/Mem:/ {print $4}' || echo "Unknown")

  # Get disk usage (in human-readable form)
  DISK_USAGE=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " used out of " $2}' || echo "Unknown")

  # Get system uptime (replacing 'uptime -p' for compatibility)
  UPTIME=$(awk '{print int($1/3600)" hours, "int($1%3600/60)" minutes"}' /proc/uptime 2>/dev/null || echo "Unknown")

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

# Check if proot exists, if not try to install it
PROOT_PATH=""

# Try to find an existing proot
for path in "$ROOTFS_DIR/usr/local/bin/proot" "$ROOTFS_DIR/usr/bin/proot" "$(which proot 2>/dev/null)"; do
  if [ -f "$path" ] && [ -x "$path" ]; then
    PROOT_PATH="$path"
    break
  fi
done

# If proot not found, try to install it
if [ -z "$PROOT_PATH" ]; then
  echo -e "${YELLOW}Proot not found. Attempting to install...${RESET_COLOR}"
  
  # Try to install with apt-get if available
  if command -v apt-get >/dev/null; then
    apt-get update && apt-get install -y proot
    if command -v proot >/dev/null; then
      PROOT_PATH="$(which proot)"
      # Create directory if it doesn't exist and copy proot to rootfs
      mkdir -p "$ROOTFS_DIR/usr/local/bin/"
      cp "$PROOT_PATH" "$ROOTFS_DIR/usr/local/bin/proot"
      chmod +x "$ROOTFS_DIR/usr/local/bin/proot"
      PROOT_PATH="$ROOTFS_DIR/usr/local/bin/proot"
    fi
  fi
  
  # If still not found, try downloading a statically compiled version
  if [ -z "$PROOT_PATH" ]; then
    echo -e "${YELLOW}Downloading precompiled proot...${RESET_COLOR}"
    mkdir -p "$ROOTFS_DIR/usr/local/bin/"
    wget -q -O "$ROOTFS_DIR/usr/local/bin/proot" \
      "https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-${ARCH_ALT}-static" || {
      echo -e "${RED}Failed to download proot. Cannot continue.${RESET_COLOR}"
      exit 1
    }
    chmod +x "$ROOTFS_DIR/usr/local/bin/proot"
    PROOT_PATH="$ROOTFS_DIR/usr/local/bin/proot"
  fi
fi

# Final check if proot is available
if [ -z "$PROOT_PATH" ] || [ ! -x "$PROOT_PATH" ]; then
  echo -e "${BOLD_RED}Error: proot not found and could not be installed. Cannot start the environment.${RESET_COLOR}"
  exit 1
fi

echo -e "${GREEN}Starting PRoot environment using: $PROOT_PATH${RESET_COLOR}"

# Start proot environment
$PROOT_PATH --rootfs="${ROOTFS_DIR}" -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit
