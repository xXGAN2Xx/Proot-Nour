#!/bin/sh

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
elif [ "$ARCH" = "riscv64" ]; then
  ARCH_ALT="riscv64"
else
  printf "Unsupported CPU architecture: ${ARCH}"
  exit 1
fi

# Download & decompress the Linux root file system if not already installed.

if [ ! -e ${ROOTFS_DIR}/.installed ]; then
    curl -O https://archive.ubuntu.com/ubuntu/pool/main/x/xz-utils/xz-utils_5.6.1+really5.4.5-1ubuntu0.2_${ARCH_ALT}.deb
    deb_file=$(ls xz-utils_*.deb)
    dpkg -x "$deb_file" ~/.local/
    rm "$deb_file"
    export PATH=~/.local/usr/bin:$PATH

################################
# installing script            #
################################



#!/bin/sh

# Define color codes
PURPLE='\033[0;35m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Configuration variables
readonly ROOTFS_DIR="/home/container"
readonly BASE_URL="https://images.linuxcontainers.org/images"

# Add to PATH
export PATH="$PATH:/root/.local/usr/bin"

# Define the number of distributions
num_distros=20

# Error handling function
error_exit() {
    printf "${RED}Error: %s${NC}\n" "$1" 1>&2
    exit 1
}

# Logger function
log() {
    level="$1"
    message="$2"
    color_name="$3"
    color=""

    case "$color_name" in
        "PURPLE") color="$PURPLE";;
        "RED") color="$RED";;
        "GREEN") color="$GREEN";;
        "YELLOW") color="$YELLOW";;
        *) color="$NC";;
    esac

    if [ -z "$color" ]; then
        color="$NC"
    fi

    printf "%s[%s]%s %s\n" "$color" "$level" "$NC" "$message"
}

# Detect the machine architecture.
ARCH=$(uname -m)

# Detect architecture
detect_architecture() {
    case "$ARCH" in
        x86_64)
            echo "amd64"
        ;;
        aarch64)
            echo "arm64"
        ;;
        riscv64)
            echo "riscv64"
        ;;
        *)
            error_exit "Unsupported CPU architecture: $ARCH"
        ;;
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
    is_custom="${3:-false}"

    log "INFO" "Preparing to install $pretty_name..." "GREEN"

    url_path=""
    image_names=""

    if [ "$is_custom" = "true" ]; then
        url_path="$BASE_URL/$distro_name/current/$ARCH_ALT/"
    else
        url_path="$BASE_URL/$distro_name/"
    fi

    # Fetch available versions with error handling
    image_names=$(curl -s "$url_path" | grep 'href="' | grep -o '"[^/"]*/"' | tr -d '"/' | grep -v '^\.\.$') ||
    error_exit "Failed to fetch available versions for $pretty_name"

    # Display available versions
    count=1
    echo "$image_names" | while read -r line; do
        if [ -n "$line" ]; then
            printf "* [%d] %s (%s)\n" "$count" "$pretty_name" "$line"
            count=$((count + 1))
        fi
    done
    printf "* [0] Go Back\n"

    num_versions=$(echo "$image_names" | wc -l)

    # Version selection with validation
    version=""
    while true; do
        printf "${YELLOW}Enter the desired version (0-%d): ${NC}\n" "$num_versions"
        read -r version
        case "$version" in
            0)
                exec "$0"
            ;;
            ''|*[!0-9]*)
                log "ERROR" "Invalid selection. Please try again." "RED"
                continue
            ;;
        esac

        if [ "$version" -ge 1 ] && [ "$version" -le "$num_versions" ]; then
            break
        else
            log "ERROR" "Invalid selection. Please try again." "RED"
        fi
    done

    selected_version=$(echo "$image_names" | sed -n "${version}p")
    log "INFO" "Selected version: $selected_version" "GREEN"

    # Download and extract rootfs
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

    # Cleanup downloaded archive
    rm -f "$ROOTFS_DIR/$file_name"
}

# Function to get Chimera Linux URL
get_chimera_linux() {
    base_url="https://repo.chimera-linux.org/live/latest/"
    latest_file=""

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

    opensuse_version=""
    while true; do
        printf "${YELLOW}Enter your choice (0-2): ${NC}\n"
        read -r opensuse_version
        case "$opensuse_version" in
            0)
                exec "$0"
            ;;
            1)
                log "INFO" "Selected version: openSUSE Leap" "GREEN"
                url=""
                case "$ARCH" in
                    aarch64|x86_64)
                        url="https://download.opensuse.org/distribution/openSUSE-current/appliances/opensuse-leap-dnf-image.${ARCH}-lxc-dnf.tar.xz"
                        install_custom "openSUSE Leap" "$url"
                    ;;
                    *)
                        error_exit "openSUSE Leap is not available for ${ARCH} architecture"
                    ;;
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
            *)
                log "ERROR" "Invalid selection. Please try again." "RED"
            ;;
        esac
    done
}

# Function to download and extract rootfs
download_and_extract_rootfs() {
    distro_name="$1"
    version="$2"
    is_custom="$3"

    arch_url=""
    url=""
    if [ "$is_custom" = "true" ]; then
        arch_url="${BASE_URL}/${distro_name}/current/"
        url="${BASE_URL}/${distro_name}/current/${ARCH_ALT}/${version}/"
    else
        arch_url="${BASE_URL}/${distro_name}/${version}/"
        url="${BASE_URL}/${distro_name}/${version}/${ARCH_ALT}/default/"
    fi

    # Check if the distro support $ARCH_ALT
    if ! curl -s "$arch_url" | grep -q "$ARCH_ALT"; then
        error_exit "This distro doesn't support $ARCH_ALT. Exiting...."
        cleanup
        exit 1
    fi

    # Get latest version
    latest_version=""
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

# Main menu display
display_menu() {
    printf "\033c"
    printf "${GREEN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                           ${PURPLE} Pterodactyl VPS EGG ${GREEN}                             ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                          ${RED}© 2021 - %s ${PURPLE}@ysdragon${GREEN}                            ┃${NC}\n" "$(date +%Y)"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
    printf "\n${YELLOW}Please choose your favorite distro:${NC}\n\n"

    # Display all distributions
    printf "* [1] Debian\n"
    printf "* [2] Ubuntu\n"
    printf "* [3] Void Linux\n"
    printf "* [4] Alpine Linux\n"
    printf "* [5] CentOS\n"
    printf "* [6] Rocky Linux\n"
    printf "* [7] Fedora\n"
    printf "* [8] AlmaLinux\n"
    printf "* [9] Slackware Linux\n"
    printf "* [10] Kali Linux\n"
    printf "* [11] openSUSE\n"
    printf "* [12] Gentoo Linux\n"
    printf "* [13] Arch Linux\n"
    printf "* [14] Devuan Linux\n"
    printf "* [15] Chimera Linux\n"
    printf "* [16] Oracle Linux\n"
    printf "* [17] Amazon Linux\n"
    printf "* [18] Plamo Linux\n"
    printf "* [19] Linux Mint\n"
    printf "* [20] Alt Linux\n"

    printf "\n${YELLOW}Enter the desired distro (1-%d): ${NC}\n" "$num_distros"
}

# Initial setup
ARCH_ALT=$(detect_architecture)
check_network

# Display menu and get selection
display_menu

# Handle user selection and installation
read -r selection

case "$selection" in
    1)
        install "debian" "Debian"
    ;;
    2)
        install "ubuntu" "Ubuntu"
    ;;
    3)
        install "voidlinux" "Void Linux" "true"
    ;;
    4)
        install "alpine" "Alpine Linux"
    ;;
    5)
        install "centos" "CentOS"
    ;;
    6)
        install "rockylinux" "Rocky Linux"
    ;;
    7)
        install "fedora" "Fedora"
    ;;
    8)
        install "almalinux" "Alma Linux"
    ;;
    9)
        install "slackware" "Slackware"
    ;;
    10)
        install "kali" "Kali Linux"
    ;;
    11)
        install_opensuse_linux
    ;;
    12)
        install "gentoo" "Gentoo Linux" "true"
    ;;
    13)
        install "archlinux" "Arch Linux"
        post_install_config "archlinux"
    ;;
    14)
        install "devuan" "Devuan Linux"
    ;;
    15)
        chimera_url=$(get_chimera_linux)
        install_custom "Chimera Linux" "$chimera_url"
    ;;
    16)
        install "oracle" "Oracle Linux"
    ;;
    17)
        install "amazonlinux" "Amazon Linux"
    ;;
    18)
        install "plamo" "Plamo Linux"
    ;;
    19)
        install "mint" "Linux Mint"
    ;;
    20)
        install "alt" "Alt Linux"
    ;;
    *)
        error_exit "Invalid selection (1-${num_distros})"
    ;;
esac

# Copy run.sh script to ROOTFS_DIR and make it executable
cp /run.sh "$ROOTFS_DIR/run.sh"
chmod +x "$ROOTFS_DIR/run.sh"

# Trap for cleanup on script exit
trap cleanup EXIT





trap cleanup EXIT
log "INFO" "Installation process completed successfully." "GREEN"

fi
################################
# Package Installation & Setup #
################################

# Download static APK-Tools temporarily because minirootfs does not come with APK pre-installed.
if [ ! -e ${ROOTFS_DIR}/.installed ]; then
    # Download the packages from their sources
    mkdir ${ROOTFS_DIR}/usr/local/bin -p

      curl -L --retry "$max_retries" --max-time "$timeout" -o "${ROOTFS_DIR}/usr/local/bin/proot" "https://github.com/xXGAN2Xx/proot-nour/raw/refs/heads/main/proot-${ARCH}-static"

  while [ ! -s "${ROOTFS_DIR}/usr/local/bin/proot" ]; do
      rm ${ROOTFS_DIR}/usr/local/bin/proot -rf
      curl -L --retry "$max_retries" --max-time "$timeout" -o "${ROOTFS_DIR}/usr/local/bin/proot" "https://github.com/xXGAN2Xx/proot-nour/raw/refs/heads/main/proot-${ARCH}-static"
  
      if [ -s "${ROOTFS_DIR}/usr/local/bin/proot" ]; then
          # Make PRoot executable.
          chmod +x ${ROOTFS_DIR}/usr/local/bin/proot
          break  # Exit the loop since the file is not empty
      fi
      
      chmod +x ${ROOTFS_DIR}/usr/local/bin/proot
      sleep 1  # Add a delay before retrying to avoid hammering the server
  done
  
  chmod +x ${ROOTFS_DIR}/usr/local/bin/proot
  chmod +x ${ROOTFS_DIR}
fi

# Clean-up after installation complete & finish up.
if [ ! -e ${ROOTFS_DIR}/.installed ]; then
    # Add DNS Resolver nameservers to resolv.conf.
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1" > ${ROOTFS_DIR}/etc/resolv.conf
    # Wipe the files we downloaded into /tmp previously.
    rm -rf /tmp/rootfs.tar.xz /tmp/sbin
    # Create .installed to later check whether Alpine is installed.
    touch ${ROOTFS_DIR}/.installed
    ${ROOTFS_DIR}/usr/local/bin/proot -R "${ROOTFS_DIR}" -c "curl -o /bin/systemctl https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
    ${ROOTFS_DIR}/usr/local/bin/proot -R "${ROOTFS_DIR}" -c "chmod +x /bin/systemctl"
fi

###########################
# make run code #
###########################
# Create the script file
if [ ! -e ${ROOTFS_DIR}/run.sh ]; then
cat > run.sh << 'EOF'
#!/bin/sh

# Color definitions
BLACK='\e[0;30m'
BOLD_BLACK='\e[1;30m'
BOLD_RED='\e[1;31m'
BOLD_GREEN='\e[1;32m'
BOLD_YELLOW='\e[1;33m'
BLUE='\e[0;34m'
BOLD_BLUE='\e[1;34m'
MAGENTA='\e[0;35m'
BOLD_MAGENTA='\e[1;35m'
CYAN='\e[0;36m'
BOLD_CYAN='\e[1;36m'
WHITE='\e[0;37m'
BOLD_WHITE='\e[1;37m'
RESET_COLOR='\e[0m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Function to print initial banner
print_banner() {
    printf "\033c"
    printf "${GREEN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                           ${PURPLE} Pterodactyl VPS nour ${GREEN}                            ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                          ${RED}© 2025 - $(date +%Y) ${PURPLE}@xXGAN2Xx${GREEN}                            ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃ INSTALLER OS -> ${RED} $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)${NC}\n"
    printf "${GREEN}┃ CPU -> ${YELLOW} $(cat /proc/cpuinfo | grep 'model name' | cut -d':' -f2- | sed 's/^ *//;s/  \+/ /g' | head -n 1)${NC}\n"
    printf "${GREEN}┃ RAM -> ${BOLD_GREEN}${SERVER_MEMORY}MB${NC}\n"
    printf "${GREEN}┃ PRIMARY PORT -> ${BOLD_GREEN}${SERVER_PORT}${NC}\n"
    printf "${GREEN}┃ EXTRA PORTS -> ${BOLD_GREEN}${P_SERVER_ALLOCATION_LIMIT}${NC}\n"
    printf "${GREEN}┃ LOCATION -> ${BOLD_GREEN}${P_SERVER_LOCATION}${NC}\n"
    printf "${GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
}

# Function to print a beautiful help message
print_help_message() {
    printf "${PURPLE}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${PURPLE}┃                                                                             ┃${NC}\n"
    printf "${PURPLE}┃                          ${GREEN}✦ Available Commands ✦${PURPLE}                             ┃${NC}\n"
    printf "${PURPLE}┃                                                                             ┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}clear, cls${GREEN}         ❯  Clear the screen                                  ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}exit${GREEN}               ❯  Shutdown the server                               ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}history${GREEN}            ❯  Show command history                              ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}reinstall${GREEN}          ❯  Reinstall the server                              ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}install-ssh${GREEN}        ❯  Install our custom SSH server                     ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}help${GREEN}               ❯  Display this help message                         ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃                                                                             ┃${NC}\n"
    printf "${PURPLE}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
}

# Configuration
HOSTNAME="MyVPS"
HISTORY_FILE="${HOME}/.custom_shell_history"
MAX_HISTORY=1000

# Check if not installed
if [ ! -e "/.installed" ]; then
    # Check if rootfs.tar.xz or rootfs.tar.gz exists and remove them if they do
    if [ -f "/rootfs.tar.xz" ]; then
        rm -f "/rootfs.tar.xz"
    fi
    
    if [ -f "/rootfs.tar.gz" ]; then
        rm -f "/rootfs.tar.gz"
    fi
    
    # Wipe the files we downloaded into /tmp previously
    rm -rf /tmp/sbin
    
    # Mark as installed.
    touch "/.installed"
fi

# Check if the autorun script exists
if [ ! -e "/autorun.sh" ]; then
    touch /autorun.sh
    chmod +x /autorun.sh
fi

printf "\033c"
printf "${GREEN}Starting..${NC}\n"
sleep 1
printf "\033c"

# Logger function
log() {
    level=$1
    message=$2
    color=$3
    
    if [ -z "$color" ]; then
        color=${NC}
    fi
    
    printf "${color}[$level]${NC} $message\n"
}

# Function to handle cleanup on exit
cleanup() {
    log "INFO" "Session ended. Goodbye!" "$GREEN"
    exit 0
}

# Function to detect the machine architecture
detect_architecture() {
    # Detect the machine architecture.
    ARCH=$(uname -m)

    # Detect architecture and return the corresponding value
    case "$ARCH" in
        x86_64)
            echo "amd64"
        ;;
        aarch64)
            echo "arm64"
        ;;
        riscv64)
            echo "riscv64"
        ;;
        *)
            log "ERROR" "Unsupported CPU architecture: $ARCH" "$RED"
        ;;
    esac
}

# Function to get formatted directory
get_formatted_dir() {
    current_dir="$PWD"
    case "$current_dir" in
        "$HOME"*)
            printf "~${current_dir#$HOME}"
        ;;
        *)
            printf "$current_dir"
        ;;
    esac
}

print_instructions() {
    log "INFO" "Type 'help' to view a list of available custom commands." "$YELLOW"
}

# Function to print prompt
print_prompt() {
    user="$1"
    printf "\n${GREEN}${user}@${HOSTNAME}${NC}:${RED}$(get_formatted_dir)${NC}# "
}

# Function to save command to history
save_to_history() {
    cmd="$1"
    if [ -n "$cmd" ] && [ "$cmd" != "exit" ]; then
        printf "$cmd\n" >> "$HISTORY_FILE"
        # Keep only last MAX_HISTORY lines
        if [ -f "$HISTORY_FILE" ]; then
            tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "$HISTORY_FILE.tmp"
            mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
        fi
    fi
}

# Function reinstall the OS
reinstall() {
    # Source the /etc/os-release file to get OS information
    . /etc/os-release

    printf "${YELLOW}Are you sure you want to reinstall the OS? This will wipe all data. (yes/no): ${NC}"
    read -r confirmation
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Reinstallation cancelled." "$YELLOW"
        return
    fi
    
    log "INFO" "Proceeding with reinstallation..." "$GREEN"
    if [ "$ID" = "alpine" ] || [ "$ID" = "chimera" ]; then
        rm -rf / > /dev/null 2>&1
    else
        rm -rf --no-preserve-root / > /dev/null 2>&1
    fi
}

# Function to install wget
install_wget() {
    distro=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    
    case "$distro" in
        "debian"|"ubuntu"|"devuan"|"linuxmint"|"kali")
            apt-get update -qq && apt-get install -y -qq wget > /dev/null 2>&1
        ;;
        "void")
            xbps-install -Syu -q wget > /dev/null 2>&1
        ;;
        "centos"|"fedora"|"rocky"|"almalinux"|"openEuler"|"amzn"|"ol")
            yum install -y -q wget > /dev/null 2>&1
        ;;
        "opensuse"|"opensuse-tumbleweed"|"opensuse-leap")
            zypper install -y -q wget > /dev/null 2>&1
        ;;
        "alpine"|"chimera")
            apk add --no-scripts -q wget > /dev/null 2>&1
        ;;
        "gentoo")
            emerge --sync -q && emerge -q wget > /dev/null 2>&1
        ;;
        "arch")
            pacman -Syu --noconfirm --quiet wget > /dev/null 2>&1
        ;;
        "slackware")
            yes | slackpkg install wget > /dev/null 2>&1
        ;;
        *)
            log "ERROR" "Unsupported distribution: $distro" "$RED"
            return 1
        ;;
    esac
}

# Function to install SSH from the repository
install_ssh() {
    # Check if SSH is already installed
    if [ -f "/usr/local/bin/ssh" ]; then
        log "ERROR" "SSH is already installed." "$RED"
        return 1
    fi

    # Install wget if not found
    if ! command -v wget &> /dev/null; then
        log "INFO" "Installing wget." "$YELLOW"
        install_wget
    fi
    
    log "INFO" "Installing SSH." "$YELLOW"
    
    # Determine the architecture
    arch=$(detect_architecture)
    
    # URL to download the SSH binary
    url="https://github.com/ysdragon/ssh/releases/latest/download/ssh-$arch"
    
    # Download the SSH binary
    wget -q -O /usr/local/bin/ssh "$url" || {
        log "ERROR" "Failed to download SSH." "$RED"
        return 1
    }
    
    # Make the binary executable
    chmod +x /usr/local/bin/ssh || {
        log "ERROR" "Failed to make ssh executable." "$RED"
        return 1
    }    

    log "SUCCESS" "SSH installed successfully." "$GREEN"
}

# Function to handle command execution
execute_command() {
    cmd="$1"
    user="$2"
    
    # Save command to history
    save_to_history "$cmd"
    
    # Handle special commands
    case "$cmd" in
        "clear"|"cls")
            print_banner
            print_prompt "$user"
            return 0
        ;;
        "exit")
            cleanup
        ;;
        "history")
            if [ -f "$HISTORY_FILE" ]; then
                cat "$HISTORY_FILE"
            fi
            print_prompt "$user"
            return 0
        ;;
        "reinstall")
            log "INFO" "Reinstalling...." "$GREEN"
            reinstall
            exit 2
        ;;
        "sudo"*|"su"*)
            log "ERROR" "You are already running as root." "$RED"
            print_prompt "$user"
            return 0
        ;;
        "install-ssh")
            install_ssh
            print_prompt "$user"
            return 0
        ;;
        "help")
            print_help_message
            print_prompt "$user"
            return 0
        ;;
        *)
            eval "$cmd"
            print_prompt "$user"
            return 0
        ;;
    esac
}

# Function to run command prompt for a specific user
run_prompt() {
    user="$1"
    read -r cmd
    
    execute_command "$cmd" "$user"
    print_prompt "$user"
}

# Create history file if it doesn't exist
touch "$HISTORY_FILE"

# Set up trap for clean exit
trap cleanup INT TERM

# Print the initial banner
print_banner

# Print the initial instructions
print_instructions

# Print initial command
printf "${GREEN}root@${HOSTNAME}${NC}:${RED}$(get_formatted_dir)${NC}#\n"

# Execute autorun.sh
sh "/autorun.sh"

# Main command loop
while true; do
    run_prompt "user"
done

EOF

# Make the file executable
chmod +x run.sh

echo "The run.sh file has been created successfully!"
fi
###########################
# Start PRoot environment #
###########################

# This command starts PRoot and binds several important directories
# from the host file system to our special root file system.
cd /home/container
MODIFIED_STARTUP=$(eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g'))

rm -rf ${ROOTFS_DIR}/rootfs.tar.xz /tmp/*
# Make internal Docker IP address available to processes.
export INTERNAL_IP=$(ip route get 1 | awk '{print $NF;exit}')

    ${ROOTFS_DIR}/usr/local/bin/proot \
    -S "${ROOTFS_DIR}" \
    -w "/root" \
    --kill-on-exit \
    /bin/sh "${ROOTFS_DIR}/run.sh" || exit 1
