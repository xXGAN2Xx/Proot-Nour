#!/bin/bash
# ==================================================================
# PRoot Environment Controller for Pterodactyl Panel
# Version: 4.0 - Enterprise Edition
# Copyright (C) 2024, RecodeStudios.Cloud
# 
# Advanced containerization solution for Pterodactyl Panel with
# multi-distribution support, health monitoring, and auto-recovery
# ==================================================================

# Strict error handling and runtime protection
set -eo pipefail
trap 'handle_error $? $LINENO $BASH_COMMAND' ERR
trap cleanup EXIT INT TERM

# ====================== GLOBAL VARIABLES ======================

# Core paths
ROOTFS_DIR="$(pwd)"
CACHE_DIR="${ROOTFS_DIR}/.cache"
CONFIG_DIR="${ROOTFS_DIR}/.config"
BACKUP_DIR="${ROOTFS_DIR}/.backups"
PLUGIN_DIR="${ROOTFS_DIR}/.plugins"
LOG_DIR="${ROOTFS_DIR}/.logs"

# Files
CONFIG_FILE="${CONFIG_DIR}/settings.conf"
LOG_FILE="${LOG_DIR}/proot-installer.log"
STATUS_FILE="${CONFIG_DIR}/status.json"
LOCK_FILE="/tmp/proot-installer.lock"

# Environment variables
export PATH="$PATH:${HOME}/.local/usr/bin:${ROOTFS_DIR}/usr/local/bin"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Default settings
declare -A DEFAULTS=(
    ["MAX_RETRIES"]="50"
    ["TIMEOUT"]="10"
    ["DISTRO"]="ubuntu"
    ["DISTRO_VERSION"]="focal"
    ["PROOT_VERSION"]="latest"
    ["DNS_SERVERS"]="1.1.1.1,1.0.0.1"
    ["MEMORY_LIMIT"]="0"  # 0 = no limit
    ["AUTO_UPDATE"]="false"
    ["HEALTH_CHECK_INTERVAL"]="3600"
    ["ADVANCED_NETWORKING"]="false"
    ["ENABLE_X11"]="false"
    ["LOCALE"]="en_US.UTF-8"
    ["TIMEZONE"]="UTC"
    ["USER_PACKAGES"]=""
    ["BIND_MOUNTS"]="/dev,/proc,/sys,/tmp"
    ["COMPRESSION_LEVEL"]="6"
)

# Repository URLs
declare -A REPO_URLS=(
    ["ubuntu"]="https://partner-images.canonical.com/core"
    ["debian"]="https://deb.debian.org/debian/dists"
    ["alpine"]="https://dl-cdn.alpinelinux.org/alpine"
    ["arch"]="https://archive.archlinux.org/iso"
    ["fedora"]="https://dl.fedoraproject.org/pub/fedora/linux/releases"
    ["opensuse"]="https://download.opensuse.org/repositories/openSUSE"
)

# Terminal colors with fallback to no colors when not in a terminal
if [ -t 1 ]; then
    BOLD='\e[1m'
    UNDERLINE='\e[4m'
    CYAN='\e[0;36m'
    GREEN='\e[0;32m'
    YELLOW='\e[0;33m'
    RED='\e[0;31m'
    BLUE='\e[0;34m'
    MAGENTA='\e[0;35m'
    WHITE='\e[0;37m'
    RESET='\e[0m'
else
    BOLD=''
    UNDERLINE=''
    CYAN=''
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    MAGENTA=''
    WHITE=''
    RESET=''
fi

# Runtime variables (initialized in main)
DISTRO=""
DISTRO_VERSION=""
ARCH=""
ARCH_ALT=""
VERSION_INFO=""
START_TIME=""
FORCE_INSTALL="false"
FORCE_DOWNLOAD="false"
SKIP_DEPS_CHECK="false"
VERBOSE="false"
QUIET="false"
DRY_RUN="false"
BENCHMARK="false"
MONITOR_MODE="false"
INTERACTIVE="true"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_FULL_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"

# ====================== UTILITY FUNCTIONS ======================

# Function to initialize the environment
initialize_environment() {
    # Create necessary directories
    mkdir -p "$CACHE_DIR" "$CONFIG_DIR" "$BACKUP_DIR" "$PLUGIN_DIR" "$LOG_DIR"
    
    # Initialize status file
    if [ ! -f "$STATUS_FILE" ]; then
        echo '{
            "status": "not_installed",
            "last_update": null,
            "version": null,
            "distro": null,
            "arch": null,
            "health": null,
            "uptime": 0,
            "installed_packages": []
        }' > "$STATUS_FILE"
    fi
    
    # Set up lock file to prevent concurrent execution
    if [ -f "$LOCK_FILE" ]; then
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log_message "ERROR" "Another instance is already running (PID: $pid)"
            exit 1
        fi
    fi
    echo $$ > "$LOCK_FILE"
    
    # Record start time for benchmarking
    START_TIME=$(date +%s)
    
    # Set interactive mode based on terminal detection
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        INTERACTIVE="false"
    fi
}

# Function to handle errors
handle_error() {
    local exit_code=$1
    local line_number=$2
    local command=$3
    
    if [ "$DRY_RUN" = "true" ]; then
        log_message "WARNING" "Would have failed at line ${line_number} with command: ${command}"
        return 0
    fi
    
    log_message "ERROR" "Script failed at line ${line_number} with exit code ${exit_code}"
    log_message "ERROR" "Failed command: ${command}"
    
    # Generate diagnostic information
    generate_diagnostics
    
    if [ "$INTERACTIVE" = "true" ]; then
        echo -e "\n${RED}${BOLD}Installation failed!${RESET}"
        echo -e "${YELLOW}Diagnostic information has been saved to: ${LOG_DIR}/diagnostics.log${RESET}"
        
        # Offer recovery options
        echo -e "\n${BOLD}Recovery options:${RESET}"
        echo -e "  ${BOLD}1)${RESET} Retry installation"
        echo -e "  ${BOLD}2)${RESET} Clean cache and retry"
        echo -e "  ${BOLD}3)${RESET} Restore from backup (if available)"
        echo -e "  ${BOLD}4)${RESET} Exit"
        
        read -p "Select an option (1-4): " recovery_option
        case $recovery_option in
            1) log_message "INFO" "Retrying installation"; main retry;;
            2) log_message "INFO" "Cleaning cache and retrying"; rm -rf "$CACHE_DIR"; main retry;;
            3) restore_from_backup; exit $?;;
            *) log_message "INFO" "Exiting"; exit $exit_code;;
        esac
    else
        exit $exit_code
    fi
}

# Function to clean up on exit
cleanup() {
    log_message "DEBUG" "Performing cleanup tasks"
    
    # Remove lock file
    rm -f "$LOCK_FILE"
    
    # Calculate and log execution time
    if [ -n "$START_TIME" ]; then
        local end_time=$(date +%s)
        local duration=$((end_time - START_TIME))
        log_message "DEBUG" "Script execution time: ${duration} seconds"
        
        if [ "$BENCHMARK" = "true" ]; then
            echo -e "\n${BOLD}Benchmark Results:${RESET}"
            echo -e "  Total execution time: ${duration} seconds"
            echo -e "  Log file size: $(du -h "$LOG_FILE" | cut -f1) bytes"
            echo -e "  Cache size: $(du -sh "$CACHE_DIR" | cut -f1)"
        fi
    fi
}

# Function to generate diagnostics
generate_diagnostics() {
    local diag_file="${LOG_DIR}/diagnostics.log"
    
    {
        echo "=== DIAGNOSTIC REPORT ==="
        echo "Date: $(date)"
        echo "Script version: 4.0 Enterprise Edition"
        echo "Command: $0 $ORIGINAL_ARGS"
        echo ""
        
        echo "=== SYSTEM INFORMATION ==="
        echo "Kernel: $(uname -a)"
        echo "Architecture: $ARCH ($ARCH_ALT)"
        echo "Memory: $(free -h | grep Mem | awk '{print $2" total, "$4" available"}')"
        echo "Disk space: $(df -h "$ROOTFS_DIR" | awk 'NR==2 {print $2" total, "$4" available"}')"
        echo ""
        
        echo "=== CONFIGURATION ==="
        cat "$CONFIG_FILE" 2>/dev/null || echo "Config file not found"
        echo ""
        
        echo "=== ENVIRONMENT VARIABLES ==="
        env | sort
        echo ""
        
        echo "=== LAST 20 LOG ENTRIES ==="
        tail -n 20 "$LOG_FILE" 2>/dev/null || echo "Log file not available"
        echo ""
        
        echo "=== INSTALLED PACKAGES ==="
        if [ -f "${CONFIG_DIR}/packages.list" ]; then
            cat "${CONFIG_DIR}/packages.list"
        else
            echo "No package list found"
        fi
        echo ""
        
        echo "=== NETWORK CONNECTIVITY ==="
        ping -c 3 8.8.8.8 2>&1 || echo "Cannot ping 8.8.8.8"
        echo ""
        
        echo "=== FILE PERMISSIONS ==="
        ls -la "$ROOTFS_DIR" | head -n 20
        echo ""
    } > "$diag_file"
    
    log_message "INFO" "Diagnostics saved to $diag_file"
}

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local color=""
    local timestamp=""
    
    # Skip debug messages unless verbose mode is enabled
    if [ "$level" = "DEBUG" ] && [ "$VERBOSE" != "true" ]; then
        return 0
    fi
    
    # Skip all messages in quiet mode except errors
    if [ "$QUIET" = "true" ] && [ "$level" != "ERROR" ]; then
        return 0
    fi
    
    # Set color based on message level
    case "$level" in
        "INFO")    color="$WHITE" ;;
        "SUCCESS") color="$GREEN" ;;
        "WARNING") color="$YELLOW" ;;
        "ERROR")   color="$RED" ;;
        "DEBUG")   color="$BLUE" ;;
        *)         color="$WHITE" ;;
    esac
    
    # Format timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Print to console if not in quiet mode
    if [ "$QUIET" != "true" ] || [ "$level" = "ERROR" ]; then
        echo -e "${color}[${timestamp}] [${level}] ${message}${RESET}"
    fi
    
    # Always log to file
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
    
    # Rotate log if it gets too large (> 5MB)
    if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 5242880 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        log_message "DEBUG" "Log file rotated due to size"
    fi
}

# ====================== CONFIGURATION FUNCTIONS ======================

# Function to load configuration
load_config() {
    # Create default config if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        
        # Build config file from defaults
        for key in "${!DEFAULTS[@]}"; do
            echo "${key}=${DEFAULTS[$key]}" >> "$CONFIG_FILE"
        done
        
        log_message "INFO" "Created default configuration file"
    fi
    
    # Load configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        log_message "DEBUG" "Configuration loaded from $CONFIG_FILE"
    else
        log_message "WARNING" "Configuration file not found, using defaults"
    fi
    
    # Set any unset variables to defaults
    for key in "${!DEFAULTS[@]}"; do
        if [ -z "${!key+x}" ]; then
            declare -g "$key"="${DEFAULTS[$key]}"
        fi
    done
    
    # Set distribution variables
    DISTRO="${DISTRO:-${DEFAULTS[DISTRO]}}"
    DISTRO_VERSION="${DISTRO_VERSION:-${DEFAULTS[DISTRO_VERSION]}}"
    
    log_message "DEBUG" "Configuration loaded: DISTRO=$DISTRO, VERSION=$DISTRO_VERSION"
    
    # Validate configuration
    validate_config
}

# Function to validate configuration
validate_config() {
    local errors=0
    
    # Check for required configurations
    if [ -z "$DISTRO" ]; then
        log_message "ERROR" "DISTRO is not set in configuration"
        errors=$((errors + 1))
    fi
    
    if [ -z "$DISTRO_VERSION" ]; then
        log_message "ERROR" "DISTRO_VERSION is not set in configuration"
        errors=$((errors + 1))
    fi
    
    # Validate repository URLs
    if [ -z "${REPO_URLS[$DISTRO]}" ]; then
        log_message "ERROR" "Unknown distribution: $DISTRO"
        log_message "INFO" "Supported distributions: ${!REPO_URLS[*]}"
        errors=$((errors + 1))
    fi
    
    # Validate numeric values
    if ! [[ "$MAX_RETRIES" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "MAX_RETRIES must be a positive number"
        errors=$((errors + 1))
    fi
    
    if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "TIMEOUT must be a positive number"
        errors=$((errors + 1))
    fi
    
    # Return error if validation failed
    if [ "$errors" -gt 0 ]; then
        log_message "ERROR" "Configuration validation failed with $errors errors"
        return 1
    fi
    
    log_message "DEBUG" "Configuration validation passed"
    return 0
}

# Function to save configuration
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    # Save current configuration
    {
        for key in "${!DEFAULTS[@]}"; do
            echo "${key}=${!key}"
        done
    } > "$CONFIG_FILE"
    
    # Update status file
    update_status
    
    log_message "DEBUG" "Configuration saved to $CONFIG_FILE"
}

# Function to update status information
update_status() {
    local status="installed"
    if [ ! -e "$ROOTFS_DIR/.installed" ]; then
        status="not_installed"
    fi
    
    # Create basic JSON structure
    local json_data=$(cat <<EOF
{
    "status": "$status",
    "last_update": "$(date -Iseconds)",
    "version": "$VERSION_INFO",
    "distro": "$DISTRO-$DISTRO_VERSION",
    "arch": "$ARCH",
    "health": "unknown",
    "uptime": 0,
    "installed_packages": []
}
EOF
)
    
    # Write JSON to status file
    echo "$json_data" > "$STATUS_FILE"
    log_message "DEBUG" "Status updated: $status"
}

# ====================== SYSTEM CHECK FUNCTIONS ======================

# Function to check dependencies
check_dependencies() {
    log_message "INFO" "Checking dependencies"
    
    local required_commands=("wget" "tar" "grep" "awk" "sed" "mktemp" "find" "xz" "gzip")
    local missing_deps=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Optional dependencies
    local optional_commands=("curl" "jq" "pv" "pigz" "zstd")
    local missing_optional=()
    
    for cmd in "${optional_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_optional+=("$cmd")
        fi
    done
    
    # Report missing dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        
        if [ "$INTERACTIVE" = "true" ]; then
            echo -e "\n${RED}${BOLD}Missing required dependencies:${RESET} ${missing_deps[*]}"
            echo -e "${YELLOW}Please install these packages and try again.${RESET}"
            
            # Suggest installation commands for different distributions
            echo -e "\n${BOLD}Installation commands:${RESET}"
            echo -e "  For Debian/Ubuntu: ${CYAN}sudo apt-get install ${missing_deps[*]}${RESET}"
            echo -e "  For Fedora/RHEL:   ${CYAN}sudo dnf install ${missing_deps[*]}${RESET}"
            echo -e "  For Alpine:        ${CYAN}apk add ${missing_deps[*]}${RESET}"
            echo -e "  For Arch Linux:    ${CYAN}sudo pacman -S ${missing_deps[*]}${RESET}"
        fi
        
        return 1
    fi
    
    # Report missing optional dependencies
    if [ ${#missing_optional[@]} -gt 0 ]; then
        log_message "WARNING" "Missing optional dependencies: ${missing_optional[*]}"
        if [ "$VERBOSE" = "true" ]; then
            echo -e "\n${YELLOW}Missing optional dependencies:${RESET} ${missing_optional[*]}"
            echo -e "${WHITE}These packages provide additional features but are not required.${RESET}"
        fi
    fi
    
    log_message "SUCCESS" "All required dependencies are installed"
    return 0
}

# Function to detect system architecture
detect_architecture() {
    ARCH=$(uname -m)
    
    case "$ARCH" in
        x86_64)
            ARCH_ALT="amd64"
            VERSION_INFO="x86_64/amd64 64-bit"
            ;;
        aarch64)
            ARCH_ALT="arm64"
            VERSION_INFO="ARM 64-bit"
            ;;
        armv7l|armv7)
            ARCH_ALT="armhf"
            VERSION_INFO="ARM 32-bit (hard float)"
            ;;
        ppc64le)
            ARCH_ALT="ppc64el"
            VERSION_INFO="PowerPC 64-bit (little endian)"
            ;;
        riscv64)
            ARCH_ALT="riscv64"
            VERSION_INFO="RISC-V 64-bit"
            ;;
        s390x)
            ARCH_ALT="s390x"
            VERSION_INFO="IBM Z Architecture 64-bit"
            ;;
        i686|i386)
            ARCH_ALT="i386"
            VERSION_INFO="x86 32-bit"
            ;;
        *)
            log_message "ERROR" "Unsupported CPU architecture: ${ARCH}"
            echo -e "${RED}${BOLD}Unsupported CPU architecture: ${ARCH}${RESET}"
            echo -e "${YELLOW}This script supports: x86_64, aarch64, armv7l, ppc64le, riscv64, s390x, i686${RESET}"
            exit 1
            ;;
    esac
    
    log_message "INFO" "Detected architecture: ${ARCH} (${ARCH_ALT})"
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${BLUE}Detected architecture:${RESET} ${BOLD}${ARCH}${RESET} (${ARCH_ALT})"
    fi
}

# Function to check available space
check_available_space() {
    local required_space_kb=1000000  # ~1 GB
    local available_space_kb
    
    available_space_kb=$(df -k "$ROOTFS_DIR" | awk 'NR==2 {print $4}')
    
    if [ "$available_space_kb" -lt "$required_space_kb" ]; then
        log_message "WARNING" "Low disk space: ${available_space_kb}KB available, ${required_space_kb}KB recommended"
        
        if [ "$INTERACTIVE" = "true" ] && [ "$FORCE_INSTALL" != "true" ]; then
            echo -e "\n${YELLOW}${BOLD}Warning: Low disk space!${RESET}"
            echo -e "Available: $(numfmt --to=iec-i --suffix=B ${available_space_kb}K)"
            echo -e "Recommended: $(numfmt --to=iec-i --suffix=B ${required_space_kb}K)"
            
            read -p "Continue anyway? (y/N): " -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log_message "INFO" "Installation aborted by user due to low disk space"
                exit 0
            fi
        fi
    else
        log_message "INFO" "Sufficient disk space available: $(numfmt --to=iec-i --suffix=B ${available_space_kb}K)"
    fi
}

# Function to check network connectivity
check_network() {
    log_message "INFO" "Checking network connectivity"
    
    # Try multiple hosts to account for possible firewall rules
    local test_hosts=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    local connected=false
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
            connected=true
            log_message "DEBUG" "Network connectivity confirmed via $host"
            break
        fi
    done
    
    if [ "$connected" != "true" ]; then
        log_message "WARNING" "Network connectivity check failed"
        
        if [ "$INTERACTIVE" = "true" ] && [ "$FORCE_INSTALL" != "true" ]; then
            echo -e "\n${YELLOW}${BOLD}Warning: Network connectivity issues detected!${RESET}"
            echo -e "The script may fail to download required files."
            
            read -p "Continue anyway? (y/N): " -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log_message "INFO" "Installation aborted by user due to network issues"
                exit 0
            fi
        fi
    else
        log_message "SUCCESS" "Network connectivity confirmed"
    fi
}

# ====================== DOWNLOAD AND INSTALLATION FUNCTIONS ======================

# Function to download a file with retries and progress indication
download_with_retry() {
    local url="$1"
    local output_file="$2"
    local description="${3:-file}"
    local cache_key="${4:-$(basename "$url")}"
    local success=false
    local wget_args=()
    
    # Check if operation is allowed in dry run mode
    if [ "$DRY_RUN" = "true" ]; then
        log_message "INFO" "[DRY RUN] Would download $description from $url"
        return 0
    fi
    
    # Create cache directory
    mkdir -p "$CACHE_DIR"
    
    # Use cached version if available and not forced to redownload
    if [ -f "${CACHE_DIR}/${cache_key}" ] && [ -s "${CACHE_DIR}/${cache_key}" ] && [ "$FORCE_DOWNLOAD" != "true" ]; then
        log_message "INFO" "Using cached ${description}"
        cp "${CACHE_DIR}/${cache_key}" "$output_file"
        return 0
    fi
    
    # Configure wget arguments
    if [ -t 1 ] && [ "$QUIET" != "true" ]; then
        wget_args+=("--progress=bar:force")
        if [ "$VERBOSE" != "true" ]; then
            wget_args+=("--show-progress")
        fi
    else
        wget_args+=("-q")
    fi
    
    # Add timeout and retry options
    wget_args+=(
        "--timeout=$TIMEOUT"
        "--tries=3"
        "--no-hsts"
        "--no-check-certificate"  # Often needed in containerized environments
    )
    
    log_message "INFO" "Downloading ${description} from ${url}"
    
    # Temporary file for downloading
    local temp_file=$(mktemp)
    
    for attempt in $(seq 1 $MAX_RETRIES); do
        log_message "DEBUG" "Download attempt $attempt/$MAX_RETRIES"
        
        # Progress indicator prefix for interactive mode
        if [ "$INTERACTIVE" = "true" ] && [ "$QUIET" != "true" ]; then
            echo -e "${WHITE}[${attempt}/${MAX_RETRIES}] Downloading ${description}...${RESET}"
        fi
        
        # Try with wget first
        if wget "${wget_args[@]}" -O "$temp_file" "$url"; then
            if [ -s "$temp_file" ]; then
                log_message "SUCCESS" "Downloaded ${description} successfully"
                mv "$temp_file" "$output_file"
                
                # Cache the download
                cp "$output_file" "${CACHE_DIR}/${cache_key}"
                
                success=true
                break
            else
                log_message "WARNING" "Downloaded ${description} is empty"
                rm -f "$temp_file"
            fi
        else
            log_message "WARNING" "Failed to download ${description} with wget"
            rm -f "$temp_file"
            
            # Try with curl as a fallback if available
            if command -v curl >/dev/null 2>&1; then
                log_message "DEBUG" "Retrying with curl"
                if curl -L --retry 3 --retry-delay 2 -o "$temp_file" -s "$url"; then
                    if [ -s "$temp_file" ]; then
                        log_message "SUCCESS" "Downloaded ${description} with curl"
                        mv "$temp_file" "$output_file"
                        
                        # Cache the download
                        cp "$output_file" "${CACHE_DIR}/${cache_key}"
                        
                        success=true
                        break
                    fi
                fi
                rm -f "$temp_file"
            fi
        fi
        
        # Calculate backoff time (exponential with jitter)
        local max_backoff=$((attempt < 10 ? attempt * 2 : 20))
        local jitter=$(( (RANDOM % 1000) / 1000 ))
        local backoff=$(bc -l <<< "scale=1; ${max_backoff} + ${jitter}" 2>/dev/null || echo "$max_backoff")
        
        log_message "DEBUG" "Waiting ${backoff} seconds before retrying..."
        sleep "$backoff"
    done
    
    # Clean up
    rm -f "$temp_file"
    
    if [ "$success" != "true" ]; then
        log_message "ERROR" "Failed to download ${description} after $MAX_RETRIES attempts"
        return 1
    fi
    
    return 0
}

# Function to create a rootfs backup
create_backup() {
    if [ "$DRY_RUN" = "true" ]; then
        log_message "INFO" "[DRY RUN] Would create rootfs backup"
        return 0
    fi
    
    # Skip if there's nothing to backup
    if [ ! -e "$ROOTFS_DIR/.installed" ]; then
        log_message "DEBUG" "No existing installation to backup"
        return 0
    fi
    
    log_message "INFO" "Creating rootfs backup"
    
    # Generate backup filename
    local timestamp=$(date +%Y%m%d%H%M%S)
    local backup_file="${BACKUP_DIR}/rootfs-${DISTRO}-${DISTRO_VERSION}-${timestamp}.tar.gz"
    
    # Ensure backup directory exists
    mkdir -p "$BACKUP_DIR"
    
    # Create the backup archive
    log_message "INFO" "Creating backup archive at ${backup_file}"
    
    # Use tar with compression
    if command -v pigz >/dev/null 2>&1; then
        # Use pigz for parallel compression if available
        tar --exclude="./dev" --exclude="./proc" --exclude="./sys" --exclude="./tmp" \
            --exclude="./.cache" --exclude="./.backups" -I "pigz -${COMPRESSION_LEVEL}" \
            -cf "$backup_file" -C "$ROOTFS_DIR" .
    else
        # Fall back to gzip
        tar --exclude="./dev" --exclude="./proc" --exclude="./sys" --exclude="./tmp" \
            --exclude="./.cache" --exclude="./.backups" -z \
            -cf "$backup_file" -C "$ROOTFS_DIR" .
    fi
    
    # Check if backup was successful
    if [ $? -eq 0 ] && [ -f "$backup_file" ]; then
        log_message "SUCCESS" "Backup created successfully"
        
        # Cleanup old backups (keep only last 3)
        find "$BACKUP_DIR" -type f -name "rootfs-*.tar.gz" | sort | head -n -3 | xargs -r rm
        
        return 0
    else
        log_message "ERROR" "Failed to create backup"
        return 1
    fi
}

# Function to restore from backup
restore_from_backup() {
    # List available backups
    local backups=($(find "$BACKUP_DIR" -type f -name "rootfs-*.tar.gz" | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        log_message "ERROR" "No backups found to restore"
        echo -e "${RED}No backups found.${RESET}"
        return 1
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        log_message "INFO" "[DRY RUN] Would restore from backup"
        return 0
    fi
    
    echo -e "\n${BOLD}Available backups:${RESET}"
    
    for i in "${!backups[@]}"; do
        local backup_size=$(du -h "${backups[$i]}" | cut -f1)
        local backup_date=$(date -r "${backups[$i]}" "+%Y-%m-%d %H:%M:%S")
        echo -e "  ${BOLD}$((i+1))${RESET}) $(basename "${backups[$i]}") (${backup_size}, ${backup_date})"
    done
    
    # Ask which backup to restore
    local selection
    read -p "Select a backup to restore (1-${#backups[@]}, or 0
