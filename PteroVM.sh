#!/bin/bash
# ======================================================
# Advanced PRoot Environment Setup for Pterodactyl Panel
# Version: 3.0 - Enhanced Edition
# Copyright (C) 2024, RecodeStudios.Cloud
# ======================================================

# Strict error handling
set -eo pipefail  # Exit on error and pipe failures
trap 'handle_error $? $LINENO' ERR  # Custom error handler

# Configuration variables
ROOTFS_DIR="$(pwd)"
CACHE_DIR="${ROOTFS_DIR}/.cache"
export PATH="$PATH:${HOME}/.local/usr/bin"
LOG_FILE="${ROOTFS_DIR}/installation.log"
CONFIG_FILE="${ROOTFS_DIR}/.config"

# Default settings
DEFAULT_MAX_RETRIES=50
DEFAULT_TIMEOUT=8
DEFAULT_UBUNTU_VERSION="focal"
DEFAULT_PROOT_VERSION="latest"
DEFAULT_DNS_SERVERS="1.1.1.1,1.0.0.1"

# URLs
PROOT_URL="https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/refs/heads/main/proot"
UBUNTU_BASE_URL="https://partner-images.canonical.com/core"

# Terminal colors
BOLD='\e[1m'
CYAN='\e[0;36m'
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
RED='\e[0;31m'
BLUE='\e[0;34m'
WHITE='\e[0;37m'
RESET='\e[0m'

# ====================== FUNCTIONS ======================

# Function to handle errors
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_message "ERROR" "Script failed at line ${line_number} with exit code ${exit_code}"
    echo -e "${RED}${BOLD}Installation failed! Check the log file for details: ${LOG_FILE}${RESET}"
    exit $exit_code
}

# Function to load configuration
load_config() {
    # Create default config if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" <<EOF
MAX_RETRIES=$DEFAULT_MAX_RETRIES
TIMEOUT=$DEFAULT_TIMEOUT
UBUNTU_VERSION=$DEFAULT_UBUNTU_VERSION
PROOT_VERSION=$DEFAULT_PROOT_VERSION
DNS_SERVERS=$DEFAULT_DNS_SERVERS
EOF
        log_message "INFO" "Created default configuration file"
    fi
    
    # Load configuration
    source "$CONFIG_FILE"
    
    # Set defaults for any missing values
    MAX_RETRIES=${MAX_RETRIES:-$DEFAULT_MAX_RETRIES}
    TIMEOUT=${TIMEOUT:-$DEFAULT_TIMEOUT}
    UBUNTU_VERSION=${UBUNTU_VERSION:-$DEFAULT_UBUNTU_VERSION}
    PROOT_VERSION=${PROOT_VERSION:-$DEFAULT_PROOT_VERSION}
    DNS_SERVERS=${DNS_SERVERS:-$DEFAULT_DNS_SERVERS}
    
    log_message "INFO" "Configuration loaded successfully"
}

# Function to save configuration
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" <<EOF
MAX_RETRIES=$MAX_RETRIES
TIMEOUT=$TIMEOUT
UBUNTU_VERSION=$UBUNTU_VERSION
PROOT_VERSION=$PROOT_VERSION
DNS_SERVERS=$DNS_SERVERS
EOF
    log_message "INFO" "Configuration saved successfully"
}

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local color="$WHITE"
    
    case "$level" in
        "INFO") color="$WHITE" ;;
        "SUCCESS") color="$GREEN" ;;
        "WARNING") color="$YELLOW" ;;
        "ERROR") color="$RED" ;;
        "DEBUG") color="$BLUE" ;;
    esac
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Log to console and file
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}${RESET}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >> "$LOG_FILE"
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in wget tar grep awk sed; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "ERROR" "Missing dependencies: ${missing_deps[*]}"
        echo -e "${RED}Please install the following packages: ${missing_deps[*]}${RESET}"
        exit 1
    fi
    
    log_message "SUCCESS" "All dependencies are installed"
}

# Function to detect system architecture
detect_architecture() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_ALT="amd64" ;;
        aarch64) ARCH_ALT="arm64" ;;
        armv7l|armv7) ARCH_ALT="armhf" ;;
        ppc64le) ARCH_ALT="ppc64el" ;;
        riscv64) ARCH_ALT="riscv64" ;;
        s390x)   ARCH_ALT="s390x" ;;
        *)
            log_message "ERROR" "Unsupported CPU architecture: ${ARCH}"
            exit 1
            ;;
    esac
    
    log_message "INFO" "Detected architecture: ${ARCH} (${ARCH_ALT})"
}

# Function to download a file with retries
download_with_retry() {
    local url="$1"
    local output_file="$2"
    local description="${3:-file}"
    local success=false
    local wget_args=()
    
    # Create cache directory if it doesn't exist
    mkdir -p "$CACHE_DIR"
    
    # Skip download if file exists in cache and we're not forced to redownload
    if [ -f "${CACHE_DIR}/$(basename "$output_file")" ] && [ -s "${CACHE_DIR}/$(basename "$output_file")" ] && [ "$FORCE_DOWNLOAD" != "true" ]; then
        log_message "INFO" "Using cached ${description} from ${CACHE_DIR}/$(basename "$output_file")"
        cp "${CACHE_DIR}/$(basename "$output_file")" "$output_file"
        return 0
    fi
    
    # Display progress bar only if connected to a terminal
    if [ -t 1 ]; then
        wget_args+=("--show-progress")
    else
        wget_args+=("-q")
    fi
    
    log_message "INFO" "Downloading ${description} from ${url}"
    
    for attempt in $(seq 1 $MAX_RETRIES); do
        log_message "DEBUG" "Download attempt $attempt/$MAX_RETRIES"
        
        if wget --tries=3 --timeout=$TIMEOUT --no-hsts "${wget_args[@]}" -O "$output_file" "$url"; then
            if [ -s "$output_file" ]; then
                log_message "SUCCESS" "Downloaded ${description} successfully"
                
                # Cache the download
                cp "$output_file" "${CACHE_DIR}/$(basename "$output_file")"
                
                success=true
                break
            else
                log_message "WARNING" "Downloaded ${description} is empty"
                rm -f "$output_file"
            fi
        else
            log_message "WARNING" "Failed to download ${description}"
            rm -f "$output_file"
        fi
        
        # Progressive backoff
        sleep_time=$((attempt < 10 ? attempt : 10))
        log_message "DEBUG" "Waiting ${sleep_time} seconds before retrying..."
        sleep $sleep_time
    done
    
    if [ "$success" != "true" ]; then
        log_message "ERROR" "Failed to download ${description} after $MAX_RETRIES attempts"
        return 1
    fi
    
    return 0
}

# Function to check available space
check_available_space() {
    local required_space_kb=500000  # ~500 MB
    local available_space_kb
    
    available_space_kb=$(df -k "$ROOTFS_DIR" | awk 'NR==2 {print $4}')
    
    if [ "$available_space_kb" -lt "$required_space_kb" ]; then
        log_message "WARNING" "Low disk space: ${available_space_kb}KB available, ${required_space_kb}KB recommended"
        
        read -p "Continue anyway? (y/N): " -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_message "INFO" "Installation aborted by user due to low disk space"
            exit 0
        fi
    else
        log_message "INFO" "Sufficient disk space available: ${available_space_kb}KB"
    fi
}

# Function to install Ubuntu rootfs
install_ubuntu_rootfs() {
    local ubuntu_url="${UBUNTU_BASE_URL}/${UBUNTU_VERSION}/current/ubuntu-${UBUNTU_VERSION}-core-cloudimg-${ARCH_ALT}-root.tar.gz"
    local tempfile="/tmp/rootfs.tar.gz"
    
    log_message "INFO" "Installing Ubuntu ${UBUNTU_VERSION} rootfs"
    
    if download_with_retry "$ubuntu_url" "$tempfile" "Ubuntu rootfs"; then
        log_message "INFO" "Extracting Ubuntu rootfs to $ROOTFS_DIR"
        
        # Create a backup of existing files if directory is not empty
        if [ "$(ls -A "$ROOTFS_DIR" 2>/dev/null | grep -v "^\." 2>/dev/null)" ]; then
            local backup_dir="${ROOTFS_DIR}.backup.$(date +%Y%m%d%H%M%S)"
            log_message "INFO" "Creating backup of existing files to $backup_dir"
            mkdir -p "$backup_dir"
            
            find "$ROOTFS_DIR" -maxdepth 1 -not -name ".*" -exec cp -r {} "$backup_dir/" \;
        fi
        
        # Extract with progress indication if running in terminal
        if [ -t 1 ]; then
            tar -xvf "$tempfile" -C "$ROOTFS_DIR" | grep -v '/$' | awk 'NR % 100 == 0 { print "Extracted " NR " files..." }'
        else
            tar -xf "$tempfile" -C "$ROOTFS_DIR"
        fi
        
        if [ $? -eq 0 ]; then
            log_message "SUCCESS" "Ubuntu rootfs extracted successfully"
        else
            log_message "ERROR" "Failed to extract Ubuntu rootfs"
            rm -f "$tempfile"
            return 1
        fi
        
        rm -f "$tempfile"
        return 0
    else
        return 1
    fi
}

# Function to install proot
install_proot() {
    log_message "INFO" "Installing proot binary"
    
    mkdir -p "$ROOTFS_DIR/usr/local/bin"
    
    if download_with_retry "$PROOT_URL" "$ROOTFS_DIR/usr/local/bin/proot" "proot binary"; then
        chmod +x "$ROOTFS_DIR/usr/local/bin/proot"
        log_message "SUCCESS" "Proot binary installed successfully"
        return 0
    else
        return 1
    fi
}

# Function to setup rootfs environment
setup_rootfs_environment() {
    log_message "INFO" "Setting up rootfs environment"
    
    # Set up DNS servers
    IFS=',' read -ra DNS_LIST <<< "$DNS_SERVERS"
    local resolv_conf="${ROOTFS_DIR}/etc/resolv.conf"
    
    > "$resolv_conf"  # Clear the file
    for dns in "${DNS_LIST[@]}"; do
        echo "nameserver $dns" >> "$resolv_conf"
    done
    
    # Set up hostname
    if [ -f "/etc/hostname" ]; then
        cp "/etc/hostname" "${ROOTFS_DIR}/etc/hostname"
    else
        echo "proot-container" > "${ROOTFS_DIR}/etc/hostname"
    fi
    
    # Create essential directories
    mkdir -p "${ROOTFS_DIR}/root"
    mkdir -p "${ROOTFS_DIR}/tmp"
    chmod 1777 "${ROOTFS_DIR}/tmp"
    
    # Create a simple startup script inside the container
    cat > "${ROOTFS_DIR}/root/.profile.d/01-welcome.sh" <<EOF
#!/bin/bash
echo "Welcome to PRoot Ubuntu Environment!"
echo "This environment was set up by NOUR Installer"
echo "Copyright (C) 2024, RecodeStudios.Cloud"
EOF
    chmod +x "${ROOTFS_DIR}/root/.profile.d/01-welcome.sh"
    
    # Mark as installed
    touch "$ROOTFS_DIR/.installed"
    log_message "SUCCESS" "Rootfs environment setup completed"
}

# Function to display completion message
display_completion() {
    cat <<EOF

${WHITE}___________________________________________________${RESET}

           ${CYAN}${BOLD}-----> Mission Completed ! <----${RESET}

${GREEN}${BOLD} Ubuntu rootfs and proot have been successfully set up!${RESET}
${WHITE} You are about to enter the proot environment.${RESET}
${BLUE} Installation Log: ${LOG_FILE}${RESET}
${YELLOW} Use 'exit' to return to the host system.${RESET}

${WHITE}___________________________________________________${RESET}

EOF
}

# Function to display help
display_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help            Display this help message
  -f, --force           Force reinstallation even if already installed
  -v, --version VER     Specify Ubuntu version (default: ${DEFAULT_UBUNTU_VERSION})
  -t, --timeout SEC     Set download timeout in seconds (default: ${DEFAULT_TIMEOUT})
  -r, --retries NUM     Set maximum retry attempts (default: ${DEFAULT_MAX_RETRIES})
  -d, --dns SERVERS     Set DNS servers, comma-separated (default: ${DEFAULT_DNS_SERVERS})
  -c, --clean           Clean cache before installation
  -s, --skip-deps       Skip dependency checking
  --no-color            Disable colored output

Examples:
  $0 --version jammy    # Install Ubuntu 22.04 (Jammy)
  $0 --force            # Force reinstallation
  $0 --dns 8.8.8.8,8.8.4.4  # Use Google DNS servers

EOF
    exit 0
}

# Function to parse command line arguments
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                display_help
                ;;
            -f|--force)
                FORCE_INSTALL=true
                FORCE_DOWNLOAD=true
                ;;
            -v|--version)
                UBUNTU_VERSION="$2"
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift
                ;;
            -r|--retries)
                MAX_RETRIES="$2"
                shift
                ;;
            -d|--dns)
                DNS_SERVERS="$2"
                shift
                ;;
            -c|--clean)
                rm -rf "$CACHE_DIR"
                log_message "INFO" "Cache cleaned"
                ;;
            -s|--skip-deps)
                SKIP_DEPS_CHECK=true
                ;;
            --no-color)
                # Disable colors
                BOLD=''
                CYAN=''
                GREEN=''
                YELLOW=''
                RED=''
                BLUE=''
                WHITE=''
                RESET=''
                ;;
            *)
                log_message "WARNING" "Unknown option: $1"
                ;;
        esac
        shift
    done
}

# Function to start the proot environment
start_proot_environment() {
    log_message "INFO" "Starting proot environment"
    
    # List of directories to bind mount
    local bind_mounts=(
        "/dev"
        "/proc"
        "/sys"
        "/etc/resolv.conf:/etc/resolv.conf"
        "/tmp:/tmp"
        "$ROOTFS_DIR/.installed:/root/.installed"
        "$LOG_FILE:/root/installation.log"
    )
    
    # Add optional bind mounts
    if [ -d "/sdcard" ]; then
        bind_mounts+=("/sdcard:/sdcard")
    fi
    
    # Convert bind_mounts array to proot arguments
    local bind_args=()
    for mount in "${bind_mounts[@]}"; do
        bind_args+=("-b" "$mount")
    done
    
    # Create command with all arguments
    exec "$ROOTFS_DIR/usr/local/bin/proot" \
        --rootfs="${ROOTFS_DIR}" \
        --link2symlink \
        -0 \
        -w "/root" \
        "${bind_args[@]}" \
        --kill-on-exit
}

# Function for the main installation process
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Load configuration
    load_config
    
    # Initialize log file
    > "$LOG_FILE"
    log_message "INFO" "Starting PRoot environment setup"
    
    # Check dependencies
    if [ "$SKIP_DEPS_CHECK" != "true" ]; then
        check_dependencies
    fi
    
    # Detect architecture
    detect_architecture
    
    # Check if already installed and not forced to reinstall
    if [ -e "$ROOTFS_DIR/.installed" ] && [ "$FORCE_INSTALL" != "true" ]; then
        log_message "INFO" "PRoot environment already installed"
        display_completion
        start_proot_environment
        exit 0
    fi
    
    # Display banner
    echo "#######################################################################################"
    echo "#"
    echo "#                                      NOUR INSTALLER"
    echo "#"
    echo "#                           Copyright (C) 2024, RecodeStudios.Cloud"
    echo "#"
    echo "#######################################################################################"
    
    # Check available space
    check_available_space
    
    # Prompt for installation if not already confirmed
    if [ -z "$install_ubuntu" ]; then
        read -p "Do you want to install Ubuntu rootfs? (yes/no): " install_ubuntu
    fi
    
    case $install_ubuntu in
        [yY][eE][sS]|[yY])
            # Install Ubuntu rootfs
            if ! install_ubuntu_rootfs; then
                log_message "ERROR" "Failed to install Ubuntu rootfs"
                exit 1
            fi
            ;;
        *)
            log_message "INFO" "Skipping Ubuntu rootfs installation"
            ;;
    esac
    
    # Install proot
    if ! install_proot; then
        log_message "ERROR" "Failed to install proot"
        exit 1
    fi
    
    # Setup environment
    setup_rootfs_environment
    
    # Save configuration
    save_config
    
    # Display completion message
    clear
    display_completion
    
    # Start proot environment
    start_proot_environment
}

# Create necessary directories
mkdir -p "$CACHE_DIR"

# Run main function with all arguments
main "$@"
