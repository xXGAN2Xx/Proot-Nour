#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipes will fail if any command in the pipe fails.
set -o pipefail

# --- Configuration & Logging ---

# Set HOME with proper checks
HOME="${HOME:-$(pwd)}"
export DEBIAN_FRONTEND=noninteractive

# Standard Colors
R='\033[0;31m'
GR='\033[0;32m'
Y='\033[0;33m'
P='\033[0;35m'
NC='\033[0m'

# Bold Colors
BR='\033[1;31m'
BGR='\033[1;32m'
BY='\033[1;33m'

# --- Helper Functions ---
# Encapsulate logging to make the main script cleaner
log_info() { echo -e "${GR}$*${NC}"; }
log_info_bold() { echo -e "${BGR}$*${NC}"; }
log_warn() { echo -e "${Y}$*${NC}"; }
log_warn_bold() { echo -e "${BY}$*${NC}"; }
log_error() { echo -e "${BR}$*${NC}" >&2; }

# --- Architecture and System Setup ---
setup_environment() {
    log_info "Detecting architecture and system type..."
    local ARCH
    ARCH=$(uname -m)
    case "$ARCH" in
      x86_64) export ARCH_ALT="amd64" ;;
      aarch64) export ARCH_ALT="arm64" ;;
      riscv64) export ARCH_ALT="riscv64" ;;
      *)
        log_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
    esac

    if [[ ! -f /etc/debian_version ]]; then
        log_error "This is not a Debian-based system. Exiting."
        exit 1
    fi
    log_info "Debian-based system and supported architecture ($ARCH) detected."

    # --- PATH SETUP ---
    # CONSOLIDATED: Set path once, adding user-local directories first.
    # We will add more specific paths later if dependencies are installed.
    export PATH="${HOME}/.local/bin:${HOME}/usr/local/bin:${PATH}"
}

# --- Dependency Management ---
install_dependencies() {
    log_warn_bold "First time setup: Installing base packages, Python, and PRoot..."

    mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin"

    # Download required packages
    local apt_pkgs_to_download=(curl ca-certificates xz-utils python3-minimal)
    log_warn "Downloading required .deb packages..."
    apt download "${apt_pkgs_to_download[@]}"

    # Extract packages
    shopt -s nullglob
    local deb_files=("$PWD"/*.deb)
    if [[ ${#deb_files[@]} -eq 0 ]]; then
        log_error "No .deb files found to extract."
        exit 1
    fi

    log_info "Unpacking .deb files into ${HOME}/.local/"
    for deb_file in "${deb_files[@]}"; do
        dpkg -x "$deb_file" "${HOME}/.local/"
        rm "$deb_file"
    done

    # IMPORTANT: Update PATH again after extraction to find binaries like xz
    export PATH="${HOME}/.local/usr/bin:${PATH}"

    # Verify xz installation
    if command -v xz >/dev/null; then
        log_info_bold "Local xz installed at: $(command -v xz)"
        chmod +x "$(command -v xz)" 2>/dev/null || true
    else
        log_error "Warning: xz not found after package extraction"
    fi

    # Install PRoot
    log_warn "Installing PRoot..."
    local proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH_ALT}-static"
    local proot_dest="${HOME}/usr/local/bin/proot"
    curl -Ls "$proot_url" -o "$proot_dest"
    chmod +x "$proot_dest"

    log_info_bold "PRoot installed successfully."
}

# --- Script Update Management ---
update_scripts_and_tools() {
    log_warn_bold "Checking for script and tool updates..."

    declare -A scripts_to_manage=(
        ["common.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/common.sh"
        ["entrypoint.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/entrypoint.sh"
        ["helper.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/helper.sh"
        ["install.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/install.sh"
        ["run.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/run.sh"
        ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
    )

    # --- PERFORMANCE IMPROVEMENT: PARALLEL DOWNLOADS ---
    # We start all download processes in the background, then wait for them all to finish.
    # This is much faster than downloading one by one.

    local download_pids=()
    for dest_path_suffix in "${!scripts_to_manage[@]}"; do
        ( # Start a subshell for each download process
            local url="${scripts_to_manage[$dest_path_suffix]}"
            local local_file="${HOME}/${dest_path_suffix}"
            local temp_file="${local_file}.new"

            mkdir -p "$(dirname "$local_file")"

            echo -n -e "${Y}Checking ${dest_path_suffix}... ${NC}"

            if curl -sSLf --connect-timeout 15 --retry 3 -o "$temp_file" "$url"; then
                # Check for changes and update if necessary
                if [[ ! -f "$local_file" ]] || ! cmp -s "$local_file" "$temp_file"; then
                    if mv "$temp_file" "$local_file" && chmod +x "$local_file"; then
                        echo -e "${BGR}Updated.${NC}"
                    else
                        echo -e "${BR}Update failed (mv/chmod error).${NC}" >&2
                        [[ -f "$temp_file" ]] && rm "$temp_file"
                    fi
                else
                    rm "$temp_file"
                    echo -e "${GR}Up to date.${NC}"
                fi
            else
                [[ -f "$temp_file" ]] && rm "$temp_file"
                echo -e "${BR}Download failed. Using local copy if available.${NC}" >&2
            fi
        ) & # The '&' runs the subshell in the background
        download_pids+=($!) # Store the process ID of the background job
    done

    # Wait for all background download processes to complete
    log_info "Waiting for all downloads to complete..."
    for pid in "${download_pids[@]}"; do
        wait "$pid"
    done
    log_info_bold "All script checks are complete."
}


# --- Main Execution Logic ---
main() {
    setup_environment

    local DEP_FLAG="${HOME}/.dependencies_installed_v2"
    if [[ ! -f "$DEP_FLAG" ]]; then
        install_dependencies
        touch "$DEP_FLAG"
        log_info "Dependency installation complete. Flag created at ${DEP_FLAG}"
    else
        log_info "Dependencies already installed. Skipping."
    fi

    update_scripts_and_tools

    local ENTRYPOINT_SCRIPT="${HOME}/entrypoint.sh"
    if [[ ! -f "$ENTRYPOINT_SCRIPT" ]]; then
        log_error "Error: ${ENTRYPOINT_SCRIPT} not found! Cannot proceed."
        exit 1
    fi

    log_info_bold "Executing ${ENTRYPOINT_SCRIPT##*/}..."

    if command -v xz >/dev/null; then
        log_info "Using xz from: $(command -v xz)"
    else
        log_warn "Warning: xz not found in PATH"
    fi

    cd "${HOME}"
    # The exec command replaces the current shell with the new process
    exec bash "./${ENTRYPOINT_SCRIPT##*/}"
}

# Run the main function
main "$@"
