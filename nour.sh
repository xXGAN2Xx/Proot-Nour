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
    curl -O http://ftp.de.debian.org/debian/pool/main/x/xz-utils/xz-utils_5.4.1-1_${ARCH_ALT}.deb
    deb_file=$(ls xz-utils_*.deb)
    dpkg -x "$deb_file" ~/.local/
    rm "$deb_file"
    export PATH=~/.local/usr/bin:$PATH

################################
# installing script            #
################################

# --- Color Codes ---
# Using readonly to prevent accidental changes.
readonly PURPLE='\033[0;35m'
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# --- Configuration ---
readonly ROOTFS_DIR="/home/container"
readonly BASE_URL="https://images.linuxcontainers.org/images"
readonly SCRIPT_NAME="$0"

# Add to PATH
export PATH="$PATH:/root/.local/usr/bin"

# Define the number of distributions
readonly num_distros=20

# --- Functions ---

# Error handling function
error_exit() {
    printf "${RED}Error:${NC} %s\n" "$1" 1>&2
    exit 1
}

# Logger function
log() {
    local level="$1"
    local message="$2"
    local color_name="$3"
    local color="$NC"

    case "$color_name" in
        "PURPLE") color="$PURPLE" ;;
        "RED") color="$RED" ;;
        "GREEN") color="$GREEN" ;;
        "YELLOW") color="$YELLOW" ;;
        "BLUE") color="$BLUE" ;;
    esac

    printf "%s[%s]${NC} %s\n" "$color" "$level" "$message"
}

# Detect the machine architecture.
detect_architecture() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        riscv64) echo "riscv64" ;;
        *) error_exit "Unsupported CPU architecture: $arch" ;;
    esac
}

# Verify network connectivity
check_network() {
    if ! curl -s --head "$BASE_URL" >/dev/null; then
        error_exit "Unable to connect to '$BASE_URL'. Please check your internet connection."
    fi
}

# Function to cleanup temporary files
cleanup() {
    log "INFO" "Cleaning up temporary files..." "BLUE"
    rm -f "${ROOTFS_DIR}/rootfs.tar.xz"
    rm -rf /tmp/sbin
}

# Function to install a specific distro from linuxcontainers.org
install() {
    local distro_name="$1"
    local pretty_name="$2"
    local is_custom="${3:-false}"
    local url_path=""
    local image_names=""
    local count=1
    local num_versions
    local version
    local selected_version

    log "INFO" "Preparing to install $pretty_name..." "GREEN"

    if [ "$is_custom" = "true" ]; then
        url_path="$BASE_URL/$distro_name/current/$ARCH_ALT/"
    else
        url_path="$BASE_URL/$distro_name/"
    fi

    image_names=$(curl -s "$url_path" | grep 'href="' | grep -o '"[^/"]*/"' | tr -d '"/' | grep -v '^\.\.$') ||
        error_exit "Failed to fetch available versions for $pretty_name."

    # Display available versions
    echo "$image_names" | while read -r line; do
        if [ -n "$line" ]; then
            printf "* [${GREEN}%d${NC}] %s (%s)\n" "$count" "$pretty_name" "$line"
            count=$((count + 1))
        fi
    done
    printf "* [${YELLOW}0${NC}] Go Back\n\n"

    num_versions=$(echo "$image_names" | wc -l)

    # Version selection with validation
    while true; do
        printf "${YELLOW}Enter the desired version (0-%d): ${NC}" "$num_versions"
        read -r version
        echo # Add a newline for better formatting

        case "$version" in
            0) exec "$SCRIPT_NAME" ;;
            '' | *[!0-9]*)
                log "ERROR" "Invalid input. Please enter a number." "RED"
                continue
                ;;
        esac

        if [ "$version" -ge 1 ] && [ "$version" -le "$num_versions" ]; then
            break
        else
            log "ERROR" "Invalid selection. Please choose a number between 0 and $num_versions." "RED"
        fi
    done

    selected_version=$(echo "$image_names" | sed -n "${version}p")
    log "INFO" "Selected version: $selected_version" "GREEN"

    download_and_extract_rootfs "$distro_name" "$selected_version" "$is_custom"
}

# Function to install custom distribution from a direct URL
install_custom() {
    local pretty_name="$1"
    local url="$2"
    local file_name

    log "INFO" "Installing $pretty_name from custom URL..." "GREEN"
    mkdir -p "${ROOTFS_DIR}"
    file_name=$(basename "${url}")

    log "INFO" "Downloading $pretty_name rootfs..." "BLUE"
    if ! curl -Ls "${url}" -o "${ROOTFS_DIR}/$file_name"; then
        error_exit "Failed to download $pretty_name rootfs."
    fi

    log "INFO" "Extracting $pretty_name rootfs..." "BLUE"
    if ! tar -xf "${ROOTFS_DIR}/$file_name" -C "${ROOTFS_DIR}"; then
        error_exit "Failed to extract $pretty_name rootfs."
    fi

    mkdir -p "${ROOTFS_DIR}/home/container/"
    rm -f "${ROOTFS_DIR}/$file_name" # Cleanup downloaded archive
}

# Function to get the latest Chimera Linux URL
get_chimera_linux() {
    local base_url="https://repo.chimera-linux.org/live/latest/"
    local latest_file

    latest_file=$(curl -s "$base_url" | grep -o "chimera-linux-$ARCH-ROOTFS-[0-9]\{8\}-bootstrap\.tar\.gz" | sort -V | tail -n 1) ||
        error_exit "Failed to fetch Chimera Linux version list."

    if [ -n "$latest_file" ]; then
        echo "${base_url}${latest_file}"
    else
        error_exit "No suitable Chimera Linux version found for architecture '$ARCH'."
    fi
}

# Function to install openSUSE Linux based on version
install_opensuse_linux() {
    local opensuse_version url

    printf "Select openSUSE version:\n"
    printf "* [${GREEN}1${NC}] openSUSE Leap\n"
    printf "* [${GREEN}2${NC}] openSUSE Tumbleweed\n"
    printf "* [${YELLOW}0${NC}] Go Back\n\n"

    while true; do
        printf "${YELLOW}Enter your choice (0-2): ${NC}"
        read -r opensuse_version
        echo

        case "$opensuse_version" in
            0) exec "$SCRIPT_NAME" ;;
            1)
                log "INFO" "Selected version: openSUSE Leap" "GREEN"
                case "$ARCH" in
                    aarch64 | x86_64)
                        url="https://download.opensuse.org/distribution/openSUSE-current/appliances/opensuse-leap-dnf-image.${ARCH}-lxc-dnf.tar.xz"
                        install_custom "openSUSE Leap" "$url"
                        ;;
                    *) error_exit "openSUSE Leap is not available for the '$ARCH' architecture." ;;
                esac
                break
                ;;
            2)
                log "INFO" "Selected version: openSUSE Tumbleweed" "GREEN"
                if [ "$ARCH" = "x86_64" ]; then
                    install_custom "openSUSE Tumbleweed" "https://download.opensuse.org/tumbleweed/appliances/opensuse-tumbleweed-dnf-image.x86_64-lxc-dnf.tar.xz"
                else
                    error_exit "openSUSE Tumbleweed is currently only available for the 'x86_64' architecture."
                fi
                break
                ;;
            *) log "ERROR" "Invalid selection. Please try again." "RED" ;;
        esac
    done
}

# Function to download and extract rootfs from linuxcontainers.org
download_and_extract_rootfs() {
    local distro_name="$1"
    local version="$2"
    local is_custom="$3"
    local arch_url url latest_version

    if [ "$is_custom" = "true" ]; then
        arch_url="${BASE_URL}/${distro_name}/current/"
        url="${BASE_URL}/${distro_name}/current/${ARCH_ALT}/${version}/"
    else
        arch_url="${BASE_URL}/${distro_name}/${version}/"
        url="${BASE_URL}/${distro_name}/${version}/${ARCH_ALT}/default/"
    fi

    # Check if the distro supports $ARCH_ALT
    if ! curl -s "$arch_url" | grep -q "$ARCH_ALT"; then
        error_exit "This distribution does not support the '$ARCH_ALT' architecture."
    fi

    latest_version=$(curl -s "$url" | grep 'href="' | grep -o '"[^/"]*/"' | tr -d '"' | sort -r | head -n 1) ||
        error_exit "Failed to determine the latest available image version."

    log "INFO" "Downloading rootfs..." "BLUE"
    mkdir -p "${ROOTFS_DIR}"
    if ! curl -Ls "${url}${latest_version}/rootfs.tar.xz" -o "${ROOTFS_DIR}/rootfs.tar.xz"; then
        error_exit "Failed to download rootfs."
    fi

    log "INFO" "Extracting rootfs..." "BLUE"
    if ! tar -xf "${ROOTFS_DIR}/rootfs.tar.xz" -C "${ROOTFS_DIR}"; then
        error_exit "Failed to extract rootfs."
    fi

    mkdir -p "${ROOTFS_DIR}/home/container/"
}

# Function to handle post-install configuration for specific distros
post_install_config() {
    local distro="$1"

    case "$distro" in
        "archlinux")
            log "INFO" "Applying Arch Linux specific configurations..." "BLUE"
            sed -i '/^#RootDir/s/^#//' "${ROOTFS_DIR}/etc/pacman.conf"
            sed -i 's|/var/lib/pacman/|/var/lib/pacman|' "${ROOTFS_DIR}/etc/pacman.conf"
            sed -i '/^#DBPath/s/^#//' "${ROOTFS_DIR}/etc/pacman.conf"
            ;;
    esac
}

# Main menu display
display_menu() {
    printf "\033c" # Clear screen
    printf "${GREEN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃%27s${PURPLE}%s${GREEN}%27s┃${NC}\n" "" "Pterodactyl VPS EGG" ""
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃%26s${RED}%s${BLUE}%s${GREEN}%25s┃${NC}\n" "" "© 2021-$(date +%Y) " "@ysdragon" ""
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
    printf "\n${YELLOW}Please choose your favorite distro:${NC}\n\n"

    printf " * [${GREEN}1${NC}] Debian\n"
    printf " * [${GREEN}2${NC}] Ubuntu\n"
    printf " * [${GREEN}3${NC}] Void Linux\n"
    printf " * [${GREEN}4${NC}] Alpine Linux\n"
    printf " * [${GREEN}5${NC}] CentOS\n"
    printf " * [${GREEN}6${NC}] Rocky Linux\n"
    printf " * [${GREEN}7${NC}] Fedora\n"
    printf " * [${GREEN}8${NC}] AlmaLinux\n"
    printf " * [${GREEN}9${NC}] Slackware\n"
    printf " * [${GREEN}10${NC}] Kali Linux\n"
    printf " * [${GREEN}11${NC}] openSUSE\n"
    printf " * [${GREEN}12${NC}] Gentoo\n"
    printf " * [${GREEN}13${NC}] Arch Linux\n"
    printf " * [${GREEN}14${NC}] Devuan\n"
    printf " * [${GREEN}15${NC}] Chimera Linux\n"
    printf " * [${GREEN}16${NC}] Oracle Linux\n"
    printf " * [${GREEN}17${NC}] Amazon Linux\n"
    printf " * [${GREEN}18${NC}] Plamo Linux\n"
    printf " * [${GREEN}19${NC}] Linux Mint\n"
    printf " * [${GREEN}20${NC}] Alt Linux\n"

    printf "\n${YELLOW}Enter the desired distro number (1-%d): ${NC}" "$num_distros"
}

# --- Main Script Execution ---

# Trap for cleanup on script exit
trap cleanup EXIT

# Initial setup
readonly ARCH=$(uname -m)
readonly ARCH_ALT=$(detect_architecture)
check_network

# Display menu and get selection
display_menu
read -r selection
echo

# Handle user selection and installation
case "$selection" in
    1) install "debian" "Debian" ;;
    2) install "ubuntu" "Ubuntu" ;;
    3) install "voidlinux" "Void Linux" "true" ;;
    4) install "alpine" "Alpine Linux" ;;
    5) install "centos" "CentOS" ;;
    6) install "rockylinux" "Rocky Linux" ;;
    7) install "fedora" "Fedora" ;;
    8) install "almalinux" "AlmaLinux" ;;
    9) install "slackware" "Slackware" ;;
    10) install "kali" "Kali Linux" ;;
    11) install_opensuse_linux ;;
    12) install "gentoo" "Gentoo" "true" ;;
    13)
        install "archlinux" "Arch Linux"
        post_install_config "archlinux"
        ;;
    14) install "devuan" "Devuan" ;;
    15)
        chimera_url=$(get_chimera_linux)
        install_custom "Chimera Linux" "$chimera_url"
        ;;
    16) install "oracle" "Oracle Linux" ;;
    17) install "amazonlinux" "Amazon Linux" ;;
    18) install "plamo" "Plamo Linux" ;;
    19) install "mint" "Linux Mint" ;;
    20) install "alt" "Alt Linux" ;;
    *) error_exit "Invalid selection. Please run the script again and choose a number between 1 and ${num_distros}." ;;
esac
log "SUCCESS" "Installation complete! The temporary rootfs archive has been removed." "GREEN"
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
    # Wipe the files we downloaded into /tmp previously.
    rm -rf /tmp/rootfs.tar.xz /tmp/sbin
    # Create .installed to later check whether Alpine is installed.
    touch ${ROOTFS_DIR}/.installed
	# Add DNS Resolver nameservers to resolv.conf.
	printf '%s\n' "nameserver 1.1.1.1" "nameserver 1.0.0.1" > ${ROOTFS_DIR}/etc/resolv.conf
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

${ROOTFS_DIR}/usr/local/bin/proot -S "${ROOTFS_DIR}" -w "/root" --kill-on-exit /bin/sh "${ROOTFS_DIR}/run.sh" || exit 1
