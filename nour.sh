#!/bin/sh
# --- Configuration ---
HOME=/home/container
ROOTFS_DIR="$HOME"
# --- Colors (Consolidated) ---
RED='\033[0;31m'; BOLD_RED='\033[1;31m'
GREEN='\033[0;32m'; BOLD_GREEN='\033[1;32m'
YELLOW='\033[0;33m'; BOLD_YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

# --- Architecture Check ---
ARCH=$(uname -m)
case "$(uname -m)" in
  x86_64)  ARCH_ALT="amd64" ;;
  aarch64) ARCH_ALT="arm64" ;;
  riscv64) ARCH_ALT="riscv64" ;;
  *)
    echo -e "${BOLD_RED}Unsupported CPU architecture: $(uname -m)${NC}" >&2
    exit 1
    ;;
esac

# --- Dependency Installation ---
if [ ! -f "${ROOTFS_DIR}/.installed" ]; then
  echo -e "${BOLD_YELLOW}First time setup: Installing xz-utils...${NC}"
  # Use a temporary file for the download to ensure clean, safe handling.
  DEB_FILE=$(mktemp --suffix=.deb)
  trap 'rm -f "$DEB_FILE"' EXIT # Ensure temp file is deleted even on script error

  XZ_URL="http://ftp.de.debian.org/debian/pool/main/x/xz-utils/xz-utils_5.2.5-2.1~deb11u1_${ARCH_ALT}.deb"
  
  if curl -Lfo "$DEB_FILE" "$XZ_URL"; then
    dpkg -x "$DEB_FILE" "$ROOTFS_DIR/.local/"
    echo -e "${BOLD_GREEN}Installation complete.${NC}"
  else
    echo -e "${BOLD_RED}Failed to download xz-utils.${NC}" >&2
    exit 1
  fi
################################
# installing script            #
################################
# Define color codes
PURPLE=$(printf '\033[0;35m')
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[0;33m')
NC=$(printf '\033[0m')

# Configuration variables
readonly ROOTFS_DIR="/home/container"
readonly BASE_URL="https://images.linuxcontainers.org/images"

# Add to PATH
export PATH="$PATH:$HOME/.local/usr/bin"

# Get the total number of distributions
num_distros=20

# Error handling function
error_exit() {
    printf "${RED}Error: %s${NC}\n" "$1" >&2
    exit 1
}

# Logger function
log() {
    level="$1"
    message="$2"
    color_name="$3"

    case "$color_name" in
        PURPLE) color="$PURPLE" ;;
        RED) color="$RED" ;;
        GREEN) color="$GREEN" ;;
        YELLOW) color="$YELLOW" ;;
        *) color="$NC" ;;
    esac

    printf "%s[%s]%s %s\n" "$color" "$level" "$NC" "$message"
}

# Detect the machine architecture.
ARCH=$(uname -m)

# Detect architecture
detect_architecture() {
    case "$ARCH" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        riscv64) echo "riscv64" ;;
        *) error_exit "Unsupported CPU architecture: $ARCH" ;;
    esac
}

# Verify network connectivity
check_network() {
    if ! curl -s --head "$BASE_URL" >/dev/null; then
        error_exit "Unable to connect to $BASE_URL. Please check your internet connection."
    fi
}

# Function to cleanup temporary files
cleanup() {
    log "INFO" "Cleaning up temporary files..." "YELLOW"
    rm -f "$ROOTFS_DIR/rootfs.tar.xz"
    rm -rf /tmp/sbin
}

# Function to install a specific distro
install() {
    distro_name="$1"
    pretty_name="$2"
    is_custom="$3"
    if [ -z "$is_custom" ]; then
        is_custom="false"
    fi

    log "INFO" "Preparing to install $pretty_name..." "GREEN"

    if [ "$is_custom" = "true" ]; then
        url_path="$BASE_URL/$distro_name/current/$ARCH_ALT/"
    else
        url_path="$BASE_URL/$distro_name/"
    fi

    image_names=$(curl -s "$url_path" | grep 'href="' | grep -o '"[^/"]*/"' | tr -d '"/' | grep -v '^\.\.$') ||
    error_exit "Failed to fetch available versions for $pretty_name"

    log "INFO" "Available versions for $pretty_name:" "GREEN"
    i=1
    echo "$image_names" | while read -r line; do
        printf "* [%d] %s\n" "$i" "$line"
        i=$((i + 1))
    done
    printf "* [0] Go Back\n"

    num_versions=$(echo "$image_names" | wc -l)

    while true; do
        printf "${YELLOW}Enter the desired version (0-%d): ${NC}\n" "$num_versions"
        read -r version
        if [ "$version" = "0" ]; then
            exec "$0"
        fi
        if [ "$version" -ge 1 ] && [ "$version" -le "$num_versions" ]; then
            break
        fi
        log "ERROR" "Invalid selection. Please try again." "RED"
    done

    selected_version=$(echo "$image_names" | sed -n "${version}p")
    log "INFO" "Selected version: $selected_version" "GREEN"

    download_and_extract_rootfs "$distro_name" "$selected_version" "$is_custom"
}

# Function to install custom distribution from URL
install_custom() {
    pretty_name="$1"
    url="$2"

    log "INFO" "Installing $pretty_name..." "GREEN"
    mkdir -p "$ROOTFS_DIR"

    file_name=$(basename "${url}")

    if ! curl -Ls "${url}" -o "$ROOTFS_DIR/$file_name"; then
        error_exit "Failed to download $pretty_name rootfs"
    fi

    if ! tar -xf "$ROOTFS_DIR/$file_name" -C "$ROOTFS_DIR"; then
        error_exit "Failed to extract $pretty_name rootfs"
    fi

    mkdir -p "$ROOTFS_DIR/home/container/"
    rm -f "$ROOTFS_DIR/$file_name"
}

# Function to get Chimera Linux URL
get_chimera_linux() {
    base_url="https://repo.chimera-linux.org/live/latest/"
    latest_file=$(curl -s "$base_url" | grep -o "chimera-linux-$ARCH-ROOTFS-[0-9]\{8\}-bootstrap\.tar\.gz" | sort -V | tail -n 1) ||
    error_exit "Failed to fetch Chimera Linux version"

    if [ -n "$latest_file" ]; then
        date=$(echo "$latest_file" | grep -o '[0-9]\{8\}')
        echo "${base_url}chimera-linux-$ARCH-ROOTFS-$date-bootstrap.tar.gz"
    else
        error_exit "No suitable Chimera Linux version found"
    fi
}

# Function to install openSUSE Linux based on version
install_opensuse_linux() {
    printf "Select openSUSE version:\n"
    printf "* [1] openSUSE Leap\n"
    printf "* [2] openSUSE Tumbleweed\n"
    printf "* [0] Go Back\n"

    while true; do
        printf "${YELLOW}Enter your choice (0-2): ${NC}\n"
        read -r opensuse_version
        case "$opensuse_version" in
            0) exec "$0" ;;
            1)
                log "INFO" "Selected version: openSUSE Leap" "GREEN"
                case "$ARCH" in
                    aarch64|x86_64)
                        url="https://download.opensuse.org/distribution/openSUSE-current/appliances/opensuse-leap-dnf-image.${ARCH}-lxc-dnf.tar.xz"
                        install_custom "openSUSE Leap" "$url"
                        ;;
                    *) error_exit "openSUSE Leap is not available for ${ARCH} architecture" ;;
                esac
                break
                ;;
            2)
                log "INFO" "Selected version: openSUSE Tumbleweed" "GREEN"
                if [ "$ARCH" = "x86_64" ]; then
                    install_custom "openSUSE Tumbleweed" "https://download.opensuse.org/tumbleweed/appliances/opensuse-tumbleweed-dnf-image.x86_64-lxc-dnf.tar.xz"
                else
                    error_exit "openSUSE Tumbleweed is not available for ${ARCH} architecture"
                fi
                break
                ;;
            *) log "ERROR" "Invalid selection. Please try again." "RED" ;;
        esac
    done
}

# Function to download and extract rootfs
download_and_extract_rootfs() {
    distro_name="$1"
    version="$2"
    is_custom="$3"

    if [ "$is_custom" = "true" ]; then
        arch_url="${BASE_URL}/${distro_name}/current/"
        url="${BASE_URL}/${distro_name}/current/${ARCH_ALT}/${version}/"
    else
        arch_url="${BASE_URL}/${distro_name}/${version}/"
        url="${BASE_URL}/${distro_name}/${version}/${ARCH_ALT}/default/"
    fi

    if ! curl -s "$arch_url" | grep -q "$ARCH_ALT"; then
        error_exit "This distro doesn't support $ARCH_ALT. Exiting...."
    fi

    latest_version=$(curl -s "$url" | grep 'href="' | grep -o '"[^/"]*/"' | tr -d '"' | sort -r | head -n 1) ||
    error_exit "Failed to determine latest version"

    log "INFO" "Downloading rootfs..." "GREEN"
    mkdir -p "$ROOTFS_DIR"

    if ! curl -Ls "${url}${latest_version}/rootfs.tar.xz" -o "$ROOTFS_DIR/rootfs.tar.xz"; then
        error_exit "Failed to download rootfs"
    fi

    log "INFO" "Extracting rootfs..." "GREEN"
    if ! tar -xf "$ROOTFS_DIR/rootfs.tar.xz" -C "$ROOTFS_DIR"; then
        error_exit "Failed to extract rootfs"
    fi

    mkdir -p "$ROOTFS_DIR/home/container/"
}

# Function to handle post-install configuration for specific distros
post_install_config() {
    distro="$1"
    case "$distro" in
        "archlinux")
            log "INFO" "Configuring Arch Linux specific settings..." "GREEN"
            sed -i '/^#RootDir/s/^#//' "$ROOTFS_DIR/etc/pacman.conf"
            sed -i 's|/var/lib/pacman/|/var/lib/pacman|' "$ROOTFS_DIR/etc/pacman.conf"
            sed -i '/^#DBPath/s/^#//' "$ROOTFS_DIR/etc/pacman.conf"
        ;;
    esac
}

# Function to get distribution name by index
get_distro_name() {
    case "$1" in
        1) echo "Debian" ;;
        2) echo "Ubuntu" ;;
        3) echo "Void Linux" ;;
        4) echo "Alpine Linux" ;;
        5) echo "CentOS" ;;
        6) echo "Rocky Linux" ;;
        7) echo "Fedora" ;;
        8) echo "AlmaLinux" ;;
        9) echo "Slackware Linux" ;;
        10) echo "Kali Linux" ;;
        11) echo "openSUSE" ;;
        12) echo "Gentoo Linux" ;;
        13) echo "Arch Linux" ;;
        14) echo "Devuan Linux" ;;
        15) echo "Chimera Linux" ;;
        16) echo "Oracle Linux" ;;
        17) echo "Amazon Linux" ;;
        18) echo "Plamo Linux" ;;
        19) echo "Linux Mint" ;;
        20) echo "Alt Linux" ;;
    esac
}

# Main menu display
display_menu() {
    printf '\033c'
    printf "${GREEN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                           ${PURPLE} Pterodactyl VPS EGG ${GREEN}                             ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                          ${RED}© 2021 - $(date +%%Y) ${PURPLE}@ysdragon${GREEN}                            ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
    printf "\n${YELLOW}Please choose your favorite distro:${NC}\n\n"

    i=1
    while [ "$i" -le "$num_distros" ]; do
        distro_name=$(get_distro_name "$i")
        printf "* [%d] %s\n" "$i" "$distro_name"
        i=$((i + 1))
    done

    printf "\n${YELLOW}Enter the desired distro (1-%d): ${NC}\n" "$num_distros"
}

# Initial setup
ARCH_ALT=$(detect_architecture)
check_network

# Display menu and get selection
display_menu

printf "" # Prompt on a new line
read -r selection

case "$selection" in
    1) install "debian" "Debian" ;;
    2) install "ubuntu" "Ubuntu" ;;
    3) install "voidlinux" "Void Linux" "true" ;;
    4) install "alpine" "Alpine Linux" ;;
    5) install "centos" "CentOS" ;;
    6) install "rockylinux" "Rocky Linux" ;;
    7) install "fedora" "Fedora" ;;
    8) install "almalinux" "Alma Linux" ;;
    9) install "slackware" "Slackware" ;;
    10) install "kali" "Kali Linux" ;;
    11) install_opensuse_linux ;;
    12) install "gentoo" "Gentoo Linux" "true" ;;
    13)
        install "archlinux" "Arch Linux"
        post_install_config "archlinux"
        ;;
    14) install "devuan" "Devuan Linux" ;;
    15)
        chimera_url=$(get_chimera_linux)
        install_custom "Chimera Linux" "$chimera_url"
        ;;
    16) install "oracle" "Oracle Linux" ;;
    17) install "amazonlinux" "Amazon Linux" ;;
    18) install "plamo" "Plamo Linux" ;;
    19) install "mint" "Linux Mint" ;;
    20) install "alt" "Alt Linux" ;;
    *) error_exit "Invalid selection (1-$num_distros)" ;;
esac
# Trap for cleanup on script exit
trap cleanup EXIT
fi
################################
# Package Installation & Setup #
################################
if [ ! -e ${ROOTFS_DIR}/.installed ]; then
PROOT_BINARY="${ROOTFS_DIR}/usr/local/bin/proot"
PROOT_URL="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"

# Create target directory.
mkdir -p "$(dirname "$PROOT_BINARY")"

# Download proot, retrying until the command succeeds and the file is not empty.
until curl -L --fail -o "$PROOT_BINARY" "$PROOT_URL" && [ -s "$PROOT_BINARY" ]; do
    echo "Download failed or file is empty. Retrying in 1 seconds..." >&1
    sleep 1
done
fi

# Clean-up after installation complete & finish up.
if [ ! -e ${ROOTFS_DIR}/.installed ]; then
chmod +x "${ROOTFS_DIR}/usr/local/bin/proot"
rm -rf /tmp/rootfs.tar.xz /tmp/sbin
touch "${ROOTFS_DIR}/.installed"
fi

# Function to print initial banner
print_banner() {
    printf "\033c"
    printf "${GREEN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                           ${PURPLE}Done (s)! For help, type "help" change this text${GREEN}                            ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                          ${RED}© 2025 - $(date +%Y) ${PURPLE}@xXGAN2Xx${GREEN}                            ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃ INSTALLER OS -> ${RED} $(cat ${ROOTFS_DIR}/etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)${NC}\n"
    printf "${GREEN}┃ CPU -> ${YELLOW} $(cat /proc/cpuinfo | grep 'model name' | cut -d':' -f2- | sed 's/^ *//;s/  \+/ /g' | head -n 1)${NC}\n"
    printf "${GREEN}┃ RAM -> ${BOLD_GREEN}${SERVER_MEMORY}MB${NC}\n"
    printf "${GREEN}┃ PRIMARY PORT -> ${BOLD_GREEN}${SERVER_PORT}${NC}\n"
    printf "${GREEN}┃ EXTRA PORTS -> ${BOLD_GREEN}${P_SERVER_ALLOCATION_LIMIT}${NC}\n"
    printf "${GREEN}┃ LOCATION -> ${BOLD_GREEN}${P_SERVER_LOCATION}${NC}\n"
    printf "${GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
}
###########################
# Start PRoot environment #
###########################
cd /home/container
export INTERNAL_IP=$(ip route get 1 | awk '{print $NF;exit}')
rm -rf ${ROOTFS_DIR}/rootfs.tar.xz /tmp/*
print_banner
# Execute PRoot environment
    ${ROOTFS_DIR}/usr/local/bin/proot \
    --rootfs="${ROOTFS_DIR}" \
    -0 -w "/root" \
    -b /dev -b /sys -b /proc -b /etc/resolv.conf \
    --kill-on-exit 
