#!/bin/sh

ROOTFS_DIR=./nour
export PATH=$PATH:~/.local/usr/bin
max_retries=50
timeout=1
ARCH=$(uname -m)

if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT=amd64
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT=arm64
elif [ "$ARCH" = "armv7l" ]; then
  ARCH_ALT=armhf
else
  printf "Unsupported CPU architecture: ${ARCH}\n"
  exit 1
fi

# Create nour directory if it doesn't exist
mkdir -p $ROOTFS_DIR

if [ ! -e $ROOTFS_DIR/.installed ]; then
  echo "#######################################################################################"
  echo "#"
  echo "#                                      NOUR INSTALLER"
  echo "#"
  echo "#######################################################################################"

  install_ubuntu=YES
fi

case $install_ubuntu in
  [yY][eE][sS])
    wget --tries=$max_retries --timeout=$timeout -O rootfs.tar.xz https://raw.githubusercontent.com/EXALAB/Anlinux-Resources/refs/heads/master/Rootfs/Ubuntu/amd64/ubuntu-rootfs-amd64.tar.xz
    apt download xz-utils
    deb_file=$(ls xz-utils_*.deb)
    dpkg -x "$deb_file" ~/.local/
    rm "$deb_file"
    export PATH=~/.local/usr/bin:$PATH
    
    # Extract to nour directory
    tar -xJf rootfs.tar.xz -C $ROOTFS_DIR
    ;;
  *)
    echo "Skipping Ubuntu installation."
    ;;
esac

if [ ! -e $ROOTFS_DIR/.installed ]; then
  mkdir -p $ROOTFS_DIR/usr/local/bin
  wget --tries=$max_retries --timeout=$timeout -O $ROOTFS_DIR/usr/local/bin/proot "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"

  while [ ! -s "$ROOTFS_DIR/usr/local/bin/proot" ]; do
    rm -rf $ROOTFS_DIR/usr/local/bin/proot
    wget --tries=$max_retries --timeout=$timeout -O $ROOTFS_DIR/usr/local/bin/proot "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"

    if [ -s "$ROOTFS_DIR/usr/local/bin/proot" ]; then
      chmod +x $ROOTFS_DIR/usr/local/bin/proot
      break
    fi

    chmod +x $ROOTFS_DIR/usr/local/bin/proot
    sleep 1
  done
  chmod +x $ROOTFS_DIR/usr/local/bin/proot
fi

if [ ! -e $ROOTFS_DIR/.installed ]; then
  rm -rf rootfs.tar.xz
  touch $ROOTFS_DIR/.installed
fi

# Make all files in nour directory executable
chmod -R +x $ROOTFS_DIR

CYAN='\e[0;36m'
WHITE='\e[0;37m'
RESET_COLOR='\e[0m'
BOLD_RED='\e[1;31m'
BOLD_YELLOW='\e[1;33m'
BOLD_GREEN='\e[1;32m'
BOLD_CYAN='\e[1;36m'
BOLD_BLUE='\e[1;34m'
BOLD_MAGENTA='\e[1;35m'
BOLD_WHITE='\e[1;37m'
YELLOW='\e[0;33m'
GREEN='\e[0;32m'
RED='\e[0;31m'
MAGENTA='\e[0;35m'

display_gg() {
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
  echo -e ""
  echo -e "           ${CYAN}-----> Mission Completed ! <----${RESET_COLOR}"
  echo -e ""
  echo -e "${WHITE}___________________________________________________${RESET_COLOR}"
}

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
  echo -e "${BOLD_RED}            Powered by ${BOLD_WHITE}NOUR${RESET_COLOR}"
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

clear
fun_header
fun_resources
display_gg

# Start proot in the nour directory
"${ROOTFS_DIR}/usr/local/bin/proot" \
  --rootfs="${ROOTFS_DIR}" \
  -0 \
  -w /root \
  -b /:/ \
  --kill-on-exit
