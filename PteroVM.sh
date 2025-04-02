#!/bin/sh

ROOTFS_DIR=nour
export PATH=$PATH:~/.local/usr/bin
max_retries=50
timeout=1
ARCH=$(uname -m)

# Detect architecture
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

# Create nour directory if not exists
mkdir -p "$ROOTFS_DIR"

# Check if already installed
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  echo "#######################################################################################"
  echo "#"
  echo "#                                      NOUR INSTALLER"
  echo "#"
  echo "#######################################################################################"

  install_ubuntu=YES
fi

# Download and extract Ubuntu rootfs
case $install_ubuntu in
  [yY][eE][sS])
    echo "[*] Downloading Ubuntu rootfs..."
    wget --tries=$max_retries --timeout=$timeout -O rootfs.tar.xz "https://raw.githubusercontent.com/EXALAB/Anlinux-Resources/refs/heads/master/Rootfs/Ubuntu/${ARCH_ALT}/ubuntu-rootfs-${ARCH_ALT}.tar.xz"

    echo "[*] Installing xz-utils locally..."
    apt download xz-utils
    deb_file=$(ls xz-utils_*.deb)
    dpkg -x "$deb_file" ~/.local/
    rm "$deb_file"
    export PATH=~/.local/usr/bin:$PATH

    echo "[*] Extracting rootfs to $ROOTFS_DIR..."
    tar -xJf rootfs.tar.xz -C "$ROOTFS_DIR"
    ;;
  *)
    echo "Skipping Ubuntu installation."
    ;;
esac

# Download proot binary
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  mkdir -p "$ROOTFS_DIR/usr/local/bin"
  echo "[*] Downloading proot binary..."
  wget --tries=$max_retries --timeout=$timeout -O "$ROOTFS_DIR/usr/local/bin/proot" "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"

  while [ ! -s "$ROOTFS_DIR/usr/local/bin/proot" ]; do
    echo "[!] proot download failed, retrying..."
    rm -f "$ROOTFS_DIR/usr/local/bin/proot"
    wget --tries=$max_retries --timeout=$timeout -O "$ROOTFS_DIR/usr/local/bin/proot" "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
    sleep 1
  done

  chmod +x "$ROOTFS_DIR/usr/local/bin/proot"
fi

# Mark as installed
if [ ! -e "$ROOTFS_DIR/.installed" ]; then
  rm -f rootfs.tar.xz
  touch "$ROOTFS_DIR/.installed"
fi

# Set permissions
chmod -R +x "$ROOTFS_DIR"

# Colors
CYAN='\e[0;36m'
WHITE='\e[0;37m'
RESET_COLOR='\e[0m'

# Display success message
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
  CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ //g')
  CPU_CORES=$(grep -c 'processor' /proc/cpuinfo)
  TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
  USED_RAM=$(free -m | awk '/Mem:/ {print $3}')
  FREE_RAM=$(free -m | awk '/Mem:/ {print $4}')
  DISK_USAGE=$(df -h / | awk 'NR==2 {print $3 " used out of " $2}')
  UPTIME=$(awk '{print int($1/3600)" hours, "int($1%3600/60)" minutes"}' /proc/uptime)

  echo -e "${BOLD_MAGENTA} CPU Model -> ${YELLOW}$CPU_MODEL${RESET_COLOR}"
  echo -e "${BOLD_CYAN} CPU Cores -> ${GREEN}$CPU_CORES${RESET_COLOR}"
  echo -e "${BOLD_BLUE} RAM Total -> ${RED}$TOTAL_RAM MB${RESET_COLOR}"
  echo -e "${BOLD_YELLOW} RAM Used -> ${MAGENTA}$USED_RAM MB${RESET_COLOR}"
  echo -e "${BOLD_GREEN} RAM Free -> ${CYAN}$FREE_RAM MB${RESET_COLOR}"
  echo -e "${BOLD_RED} Disk Usage -> ${BOLD_WHITE}$DISK_USAGE${RESET_COLOR}"
  echo -e "${BOLD_YELLOW} Uptime -> ${BOLD_GREEN}$UPTIME${RESET_COLOR}"
}

# Run display
clear
fun_header
fun_resources
display_gg

# Start proot
echo "[*] Starting proot in $ROOTFS_DIR..."
"$ROOTFS_DIR/usr/local/bin/proot" \
  --rootfs="$ROOTFS_DIR" \
  -0 \
  -w /root \
  -b /:/ \
  --kill-on-exit
