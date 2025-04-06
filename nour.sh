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

if [ ! -e $ROOTFS_DIR/.installed ]; then
    curl -O https://archive.ubuntu.com/ubuntu/pool/main/x/xz-utils/xz-utils_5.6.1+really5.4.5-1ubuntu0.2_${ARCH_ALT}.deb
    deb_file=$(ls xz-utils_*.deb)
    dpkg -x "$deb_file" ~/.local/
    rm "$deb_file"
    export PATH=~/.local/usr/bin:$PATH

################################
# installing script            #
################################
# Define color codes (using standard variables)
CLR_PURPLE='\033[0;35m'
CLR_RED='\033[0;31m'
CLR_GREEN='\033[0;32m'
CLR_YELLOW='\033[0;33m'
CLR_NC='\033[0m' # No Color

# Configuration variables
readonly ROOTFS_DIR="/home/container"
readonly BASE_URL="https://images.linuxcontainers.org/images"

# Add to PATH
export PATH="$PATH:~/.local/usr/bin"

# Define the *number* of distributions available in the main case statement
# Update this number if you add/remove entries in the main case statement below!
readonly num_distros=20

# Error handling function
error_exit() {
    # Use standard echo or printf for portability
    printf "${CLR_RED}Error: %s${CLR_NC}\n" "$1" >&2
    exit 1
}

# Logger function
log() {
    _level="$1"
    _message="$2"
    _color_code="$3" # e.g., "RED", "GREEN"
    _color=""

    case "$_color_code" in
        PURPLE) _color="$CLR_PURPLE" ;;
        RED)    _color="$CLR_RED" ;;
        GREEN)  _color="$CLR_GREEN" ;;
        YELLOW) _color="$CLR_YELLOW" ;;
        *)      _color="$CLR_NC" ;; # Default to No Color
    esac

    # Use standard printf
    printf "%b[%s]%b %s\n" "$_color" "$_level" "$CLR_NC" "$_message"
}

# Detect the machine architecture.
ARCH=$(uname -m)

# Detect architecture (renamed variable to avoid potential conflict)
detect_architecture() {
    case "$ARCH" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        riscv64) echo "riscv64" ;;
        *) error_exit "Unsupported CPU architecture: $ARCH" ;;
    esac
}

# Verify network connectivity
check_network() {
    # Using curl exit status check which is portable
    if ! curl -s --head "$BASE_URL" >/dev/null; then
        error_exit "Unable to connect to $BASE_URL. Please check your internet connection."
    fi
}

# Function to cleanup temporary files
cleanup() {
    log "INFO" "Cleaning up temporary files..." "YELLOW"
    rm -f "$ROOTFS_DIR/rootfs.tar.xz"
    rm -rf /tmp/sbin # Ensure this directory is expected/safe to remove
}

# Function to install a specific distro
# Usage: install <distro_api_name> <pretty_name> [is_custom_flag]
install() {
    _distro_name="$1"
    _pretty_name="$2"
    # Handle optional argument portably
    if [ -n "$3" ]; then
        _is_custom="$3"
    else
        _is_custom="false"
    fi

    log "INFO" "Preparing to install $_pretty_name..." "GREEN"

    _url_path=""
    _image_names=""

    if [ "$_is_custom" = "true" ]; then
        _url_path="$BASE_URL/$_distro_name/current/$ARCH_ALT/"
    else
        _url_path="$BASE_URL/$_distro_name/"
    fi

    # Fetch available versions with error handling
    # Using portable command substitution and grep/tr
    _image_names=$(curl -s "$_url_path" | grep 'href="' | grep -o '"[^/"]*/"' | tr -d '"/' | grep -v '^\.\.$')

    if [ $? -ne 0 ] || [ -z "$_image_names" ]; then
        error_exit "Failed to fetch available versions for $_pretty_name"
    fi

    log "INFO" "Available versions for $_pretty_name:" "GREEN"
    # Display available versions using nl for numbering
    echo "$_image_names" | nl -w 1 -s '] '

    # Count number of versions using wc -l
    _num_versions=$(echo "$_image_names" | wc -l)

    # Version selection with validation
    _version_choice=""
    while true; do
        printf "${CLR_YELLOW}Enter the desired version number (1-%s): ${CLR_NC}" "$_num_versions"
        read -r _version_choice # Use read -r for robustness

        # Validate input is a number within range using case and test
        _valid_num=0
        case "$_version_choice" in
            *[!0-9]*) ;; # Contains non-digits
            '') ;;       # Empty
            *) # Contains only digits, check range
                if [ "$_version_choice" -ge 1 ] && [ "$_version_choice" -le "$_num_versions" ]; then
                   _valid_num=1
                fi
                ;;
        esac

        if [ "$_valid_num" -eq 1 ]; then
            break
        fi
        log "ERROR" "Invalid selection. Please enter a number between 1 and $_num_versions." "RED"
    done

    # Get the selected version name using sed (more portable than array indexing)
    _selected_version=$(echo "$_image_names" | sed -n "${_version_choice}p")

    log "INFO" "Selected version: $_selected_version" "GREEN"

    # Download and extract rootfs
    download_and_extract_rootfs "$_distro_name" "$_selected_version" "$_is_custom"
}

# Function to install custom distribution from URL
# Usage: install_custom <pretty_name> <url>
install_custom() {
    _pretty_name="$1"
    _url="$2"

    log "INFO" "Installing $_pretty_name..." "GREEN"

    mkdir -p "$ROOTFS_DIR" || error_exit "Failed to create $ROOTFS_DIR"

    # Use portable basename
    _file_name=$(basename "${_url}")

    log "INFO" "Downloading $_file_name..." "YELLOW"
    if ! curl -Ls "${_url}" -o "/tmp/$_file_name"; then
        error_exit "Failed to download $_pretty_name rootfs from $_url"
    fi

    log "INFO" "Extracting $_file_name..." "YELLOW"
    if ! tar -xf "/tmp/$_file_name" -C "$ROOTFS_DIR"; then
        # Attempt cleanup even on failure
        rm -f "/tmp/$_file_name"
        error_exit "Failed to extract $_pretty_name rootfs"
    fi

    mkdir -p "$ROOTFS_DIR/home/container/" || log "WARN" "Could not create $ROOTFS_DIR/home/container/" "YELLOW" # Log warning instead of erroring

    # Cleanup downloaded archive
    log "INFO" "Cleaning up downloaded archive..." "YELLOW"
    rm -f "/tmp/$_file_name"
}

# Function to get Chimera Linux URL
get_chimera_linux() {
    _base_url="https://repo.chimera-linux.org/live/latest/"
    _latest_file=""

    # Use portable grep/sort/tail to find the latest file based on name pattern
    # NOTE: This relies on lexicographical sort if sort -V isn't available.
    # It assumes filenames with later dates sort higher lexicographically.
    _latest_file=$(curl -s "$_base_url" | grep -o "chimera-linux-$ARCH-ROOTFS-[0-9]\{8\}-bootstrap\.tar\.gz" | sort | tail -n 1)

    if [ $? -ne 0 ] || [ -z "$_latest_file" ]; then
        error_exit "Failed to fetch or find Chimera Linux version"
    fi

    echo "${_base_url}${_latest_file}"
}


# Function to download and extract rootfs
# Usage: download_and_extract_rootfs <distro_name> <version> <is_custom>
download_and_extract_rootfs() {
    _distro_name="$1"
    _version="$2"
    _is_custom="$3"

    _arch_check_url=""
    _download_base_url=""

    if [ "$_is_custom" = "true" ]; then
        _arch_check_url="${BASE_URL}/${_distro_name}/current/"
        _download_base_url="${BASE_URL}/${_distro_name}/current/${ARCH_ALT}/${_version}/"
    else
        _arch_check_url="${BASE_URL}/${_distro_name}/${_version}/"
        _download_base_url="${BASE_URL}/${_distro_name}/${_version}/${ARCH_ALT}/default/"
    fi

    # Check if the distro support $ARCH_ALT using grep exit status
    log "INFO" "Checking architecture support for $ARCH_ALT at $_arch_check_url..." "YELLOW"
    if ! curl -s "$_arch_check_url" | grep -q "$ARCH_ALT"; then
        error_exit "This distro version doesn't appear to support $ARCH_ALT. Exiting...."
        # No need for cleanup/exit here, error_exit handles exit
    fi

    # Get latest build timestamp/version string within the selected version directory
    # Use sort -r (reverse) and head -n 1 for latest, assuming standard naming
    log "INFO" "Determining latest build timestamp at $_download_base_url..." "YELLOW"
    _latest_build=$(curl -s "$_download_base_url" | grep 'href="' | grep -o '"[^/"]*/"' | tr -d '"' | grep -v '^\.\.$' | sort -r | head -n 1)

    if [ $? -ne 0 ] || [ -z "$_latest_build" ]; then
        error_exit "Failed to determine latest build timestamp/version"
    fi
    log "INFO" "Using latest build: $_latest_build" "GREEN"

    _download_url="${_download_base_url}${_latest_build}rootfs.tar.xz"

    log "INFO" "Downloading rootfs from $_download_url..." "GREEN"
    mkdir -p "$ROOTFS_DIR" || error_exit "Failed to create $ROOTFS_DIR"

    if ! curl -Ls "$_download_url" -o "$/tmp/rootfs.tar.xz"; then
        error_exit "Failed to download rootfs"
    fi

    log "INFO" "Extracting rootfs..." "GREEN"
    if ! tar -xf "/tmp/rootfs.tar.xz" -C "$ROOTFS_DIR"; then
        # Attempt cleanup even on extraction failure
        rm -f "$/tmp/rootfs.tar.xz"
        error_exit "Failed to extract rootfs"
    fi

    mkdir -p "$ROOTFS_DIR/home/container/" || log "WARN" "Could not create $ROOTFS_DIR/home/container/" "YELLOW" # Log warning

    # Cleanup handled by trap or can be done explicitly here if needed before success
    # rm -f "$ROOTFS_DIR/rootfs.tar.xz" # Can move cleanup here or rely on trap
}

# Function to handle post-install configuration for specific distros
# Usage: post_install_config <distro_api_name>
post_install_config() {
    _distro="$1"

    case "$_distro" in
        "archlinux")
            log "INFO" "Configuring Arch Linux specific settings..." "GREEN"
            # Check if files exist before modifying
            if [ -f "$ROOTFS_DIR/etc/pacman.conf" ]; then
                 # Using simple sed commands, should be portable
                 sed -i -e '/^#RootDir/s/^#//' \
                        -e 's|/var/lib/pacman/|/var/lib/pacman|' \
                        -e '/^#DBPath/s/^#//' "$ROOTFS_DIR/etc/pacman.conf" || log "WARN" "Failed to modify pacman.conf" "YELLOW"
            else
                 log "WARN" "$ROOTFS_DIR/etc/pacman.conf not found for post-install config." "YELLOW"
            fi
            ;;
         # Add other distro-specific configs here if needed
         # "debian")
         #    log "INFO" "Running Debian post-install..." "GREEN"
         #    ;;
    esac
}

# Main menu display
display_menu() {
    # Clear screen (less portable than tput clear, but often works)
    printf "\033c"
    # Use standard printf for the box
    printf "${CLR_GREEN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${CLR_NC}\n"
    printf "${CLR_GREEN}┃                                                                             ┃${CLR_NC}\n"
    printf "${CLR_GREEN}┃                      ${CLR_PURPLE} Pterodactyl VPS Nour ${CLR_GREEN}                      ┃${CLR_NC}\n"
    printf "${CLR_GREEN}┃                                                                             ┃${CLR_NC}\n"
    # Use portable date command format
    _current_year=$(date +%Y)
    printf "${CLR_GREEN}┃                 ${CLR_RED}© 2025 - %s ${CLR_PURPLE}@xXGAN2Xx${CLR_GREEN}                 ┃${CLR_NC}\n" "$_current_year"
    printf "${CLR_GREEN}┃                                                                             ┃${CLR_NC}\n"
    printf "${CLR_GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${CLR_NC}\n"
    printf "\n${CLR_YELLOW}Please choose your favorite distro:${CLR_NC}\n\n"

    # Display all distributions by iterating and using a case statement
    _i=1
    while [ "$_i" -le "$num_distros" ]; do
        _distro_display_name=""
        case "$_i" in
             1) _distro_display_name="Debian" ;;
             2) _distro_display_name="Ubuntu" ;;
             3) _distro_display_name="Void Linux" ;; # Flag handled in main selection case
             4) _distro_display_name="Alpine Linux" ;;
             5) _distro_display_name="CentOS" ;;
             6) _distro_display_name="Rocky Linux" ;;
             7) _distro_display_name="Fedora" ;;
             8) _distro_display_name="AlmaLinux" ;;
             9) _distro_display_name="Slackware Linux" ;;
            10) _distro_display_name="Kali Linux" ;;
            11) _distro_display_name="openSUSE" ;;
            12) _distro_display_name="Gentoo Linux" ;; # Flag handled in main selection case
            13) _distro_display_name="Arch Linux" ;;
            14) _distro_display_name="Devuan Linux" ;;
            15) _distro_display_name="Chimera Linux" ;; # Custom handled in main selection case
            16) _distro_display_name="Oracle Linux" ;;
            17) _distro_display_name="Amazon Linux" ;;
            18) _distro_display_name="Plamo Linux" ;;
            19) _distro_display_name="Linux Mint" ;;
            20) _distro_display_name="Alt Linux" ;;
        esac
        # Use standard printf for menu items
        printf "* [%s] %s\n" "$_i" "$_distro_display_name"
        _i=$((_i + 1)) # Portable arithmetic
    done

    printf "\n${CLR_YELLOW}Enter the desired distro number (1-%s): ${CLR_NC}" "$num_distros"
    # Reading input is handled after calling display_menu
}

# === Main Script Logic ===

# Trap for cleanup on script exit (SIGINT: Ctrl+C, SIGTERM: kill, EXIT: normal exit or error)
# Using signal names is more portable than numbers
trap cleanup INT TERM EXIT

# Initial setup
ARCH_ALT=$(detect_architecture)
log "INFO" "Detected architecture: $ARCH -> $ARCH_ALT" "GREEN"
log "INFO" "Checking network connectivity..." "YELLOW"
check_network
log "INFO" "Network check successful." "GREEN"

# Display menu
display_menu

# Handle user selection and installation
# Use standard read without -p
read -r selection

case "$selection" in
    1)  install "debian" "Debian" ;;
    2)  install "ubuntu" "Ubuntu" ;;
    3)  install "voidlinux" "Void Linux" "true" ;;
    4)  install "alpine" "Alpine Linux" ;;
    5)  install "centos" "CentOS" ;;
    6)  install "rockylinux" "Rocky Linux" ;;
    7)  install "fedora" "Fedora" ;;
    8)  install "almalinux" "Alma Linux" ;;
    9)  install "slackware" "Slackware" ;;
    10) install "kali" "Kali Linux" ;;
    11) install "opensuse" "openSUSE" ;;
    12) install "gentoo" "Gentoo Linux" "true" ;;
    13) install "archlinux" "Arch Linux" && post_install_config "archlinux" ;; # Chain post-install
    14) install "devuan" "Devuan Linux" ;;
    15) chimera_url=$(get_chimera_linux) && install_custom "Chimera Linux" "$chimera_url" ;; # Chain custom install
    16) install "oracle" "Oracle Linux" ;;
    17) install "amazonlinux" "Amazon Linux" ;;
    18) install "plamo" "Plamo Linux" ;;
    19) install "mint" "Linux Mint" ;;
    20) install "alt" "Alt Linux" ;;
     *) error_exit "Invalid selection. Please enter a number between 1 and $num_distros." ;;
esac
fi
################################
# Package Installation & Setup #
################################

# Download static APK-Tools temporarily because minirootfs does not come with APK pre-installed.
if [ ! -e $ROOTFS_DIR/.installed ]; then
    # Download the packages from their sources
    mkdir $ROOTFS_DIR/usr/local/bin -p

    wget --tries=$max_retries --timeout=$timeout -O $ROOTFS_DIR/usr/local/bin/proot "https://github.com/ysdragon/proot-static/releases/download/v5.4.0/proot-${ARCH}-static"

  while [ ! -s "$ROOTFS_DIR/usr/local/bin/proot" ]; do
      rm $ROOTFS_DIR/usr/local/bin/proot -rf
      wget --tries=$max_retries --timeout=$timeout -O $ROOTFS_DIR/usr/local/bin/proot "https://github.com/ysdragon/proot-static/releases/download/v5.4.0/proot-${ARCH}-static"
  
      if [ -s "$ROOTFS_DIR/usr/local/bin/proot" ]; then
          # Make PRoot executable.
          chmod +x $ROOTFS_DIR/usr/local/bin/proot
          break  # Exit the loop since the file is not empty
      fi
      
      chmod +x $ROOTFS_DIR/usr/local/bin/proot
      sleep 1  # Add a delay before retrying to avoid hammering the server
  done
  
  chmod +x $ROOTFS_DIR/usr/local/bin/proot
  chmod +x $ROOTFS_DIR
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

display_header
display_resources
display_footer


###########################
# Start PRoot environment #
###########################

# This command starts PRoot and binds several important directories
# from the host file system to our special root file system.
cd /home/container
MODIFIED_STARTUP=$(eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g'))

# Make internal Docker IP address available to processes.
export INTERNAL_IP=$(ip route get 1 | awk '{print $NF;exit}')

    $ROOTFS_DIR/usr/local/bin/proot \
    --rootfs="/" \
    -0 -w "/root" \
    -b /dev -b /sys -b /proc -b /etc/resolv.conf \
    --kill-on-exit \
    /bin/sh "$ROOTFS_DIR/run.sh"
