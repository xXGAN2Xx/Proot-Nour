#!/bin/bash
# --- Installation and Setup Script ---
# This script is designed to automatically detect and work on Debian-based,
# RHEL-based (Amazon Linux), and Alpine Linux systems.

# --- Constants and Configuration ---

# Set HOME if it's not already set.
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

# Dependency flag path
DEP_FLAG="${HOME}/.dependencies_installed_v2"

# Ensure local binaries are prioritized in PATH.
# We set this once here, covering all potential locations.
export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"

# --- Functions ---

# Function to print an error message and exit.
error_exit() {
    echo -e "\n${BR}${1}${NC}" >&2
    exit 1
}

# Function to install base dependencies if they are not present.
install_dependencies() {
    echo -e "${BY}First time setup: Installing base packages, Bash, Python, and PRoot...${NC}"

    mkdir -p "${HOME}/.local/bin" "${HOME}/.local/usr/bin" "${HOME}/usr/local/bin" || error_exit "Failed to create required directories."

    # --- Debian-based System Logic (apt) ---
    if [ "$PKG_MANAGER" = "apt" ]; then
        local apt_pkgs_to_download=(curl bash ca-certificates xz-utils python3-minimal)
        echo -e "${Y}Downloading required .deb packages...${NC}"
        apt download "${apt_pkgs_to_download[@]}" || error_exit "Failed to download .deb packages. Please check network and apt sources."

        shopt -s nullglob # Prevent errors if no .deb files match
        local deb_files=("$PWD"/*.deb)
        [[ ${#deb_files[@]} -eq 0 ]] && error_exit "No .deb files found to extract."

        for deb_file in "${deb_files[@]}"; do
            echo -e "${GR}Unpacking $(basename "$deb_file") → ${HOME}/.local/${NC}"
            dpkg -x "$deb_file" "${HOME}/.local/" || error_exit "Failed to extract $deb_file"
            rm "$deb_file"
        done

    # --- RHEL-based System Logic (yum) ---
    elif [ "$PKG_MANAGER" = "yum" ]; then
        if ! command -v yumdownloader >/dev/null; then
            echo -e "${Y}yumdownloader not found. It is required to download packages.${NC}"
            echo -e "${Y}You may need to install it first: ${BGR}sudo yum install yum-utils${NC}"
            error_exit "Dependency 'yum-utils' is not installed."
        fi

        local yum_pkgs_to_download=(curl bash ca-certificates xz python3)
        echo -e "${Y}Downloading required .rpm packages...${NC}"
        yumdownloader "${yum_pkgs_to_download[@]}" || error_exit "Failed to download .rpm packages. Please check network and yum repositories."
        
        shopt -s nullglob
        local rpm_files=("$PWD"/*.rpm)
        [[ ${#rpm_files[@]} -eq 0 ]] && error_exit "No .rpm files found to extract."

        for rpm_file in "${rpm_files[@]}"; do
            echo -e "${GR}Unpacking $(basename "$rpm_file") → ${HOME}/.local/${NC}"
            rpm2cpio "$rpm_file" | cpio -idm --directory="${HOME}/.local/" || error_exit "Failed to extract $rpm_file"
            rm "$rpm_file"
        done

    # --- Alpine Linux Logic (apk) ---
    elif [ "$PKG_MANAGER" = "apk" ]; then
        local apk_pkgs_to_add=(curl bash ca-certificates xz python3)
        echo -e "${Y}Installing required .apk packages into local directory...${NC}"
        # --root installs packages to a different root directory.
        # --initdb creates the APK database if it doesn't exist.
        # --no-cache avoids using the system-level cache, which may require root.
        apk add --root "${HOME}/.local" --initdb --no-cache "${apk_pkgs_to_add[@]}" || error_exit "Failed to install packages with apk."
    fi

    # Verify that our local xz is now available
    if ! command -v xz >/dev/null; then
        echo -e "${Y}Warning: xz not found in PATH after package extraction.${NC}" >&2
    else
        echo -e "${BGR}Local xz is available at: $(command -v xz)${NC}"
    fi

    # Install PRoot (common for all distros)
    echo -e "${Y}Installing PRoot...${NC}"
    local proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    local proot_dest="${HOME}/usr/local/bin/proot"
    curl -Ls "$proot_url" -o "$proot_dest" || error_exit "Failed to download PRoot."
    chmod +x "$proot_dest" || error_exit "Failed to make PRoot executable."

    echo -e "${BGR}PRoot installed successfully.${NC}"
    touch "$DEP_FLAG"
}

# Function to update scripts and tools from remote sources.
update_scripts() {
    echo -e "${BY}Checking for script and tool updates...${NC}"

    declare -A scripts_to_manage=(
        ["common.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/common.sh"
        ["entrypoint.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/entrypoint.sh"
        ["helper.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/helper.sh"
        ["install.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/install.sh"
        ["run.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/run.sh"
        ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
    )

    local pids=()
    for dest_path_suffix in "${!scripts_to_manage[@]}"; do
        (
            local url="${scripts_to_manage[$dest_path_suffix]}"
            local local_file="${HOME}/${dest_path_suffix}"
            local temp_file="${local_file}.new"
            
            mkdir -p "$(dirname "$local_file")"

            echo -e "${Y}Checking ${dest_path_suffix}...${NC}"
            if curl -sSLf --connect-timeout 15 --retry 3 -o "$temp_file" "$url"; then
                if [[ ! -f "$local_file" ]] || ! cmp -s "$local_file" "$temp_file"; then
                    if mv "$temp_file" "$local_file" && chmod +x "$local_file"; then
                        echo -e "${BGR}Updated ${dest_path_suffix}.${NC}"
                    else
                        echo -e "${BR}Update failed for ${dest_path_suffix} (mv/chmod error).${NC}" >&2
                        rm -f "$temp_file"
                    fi
                else
                    rm "$temp_file"
                    echo -e "${GR}${dest_path_suffix} is up to date.${NC}"
                fi
            else
                rm -f "$temp_file"
                echo -e "${BR}Download failed for ${dest_path_suffix}. Using local version if available.${NC}" >&2
            fi
        ) &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    echo -e "${BGR}Script update check complete.${NC}"
}


# --- Main Execution ---

cd "${HOME}" || exit 1

# --- Automatic Distribution Detection ---
PKG_MANAGER=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" = "alpine" ]]; then
        PKG_MANAGER="apk"
        echo -e "${BGR}Alpine Linux detected. Using apk.${NC}"
    elif [[ "$ID" = "amzn" || "$ID_LIKE" == *"rhel"* || "$ID_LIKE" == *"fedora"* || "$ID_LIKE" == *"centos"* ]]; then
        PKG_MANAGER="yum"
        echo -e "${BGR}RHEL-based system (Amazon Linux/CentOS/Fedora) detected. Using yum.${NC}"
    elif [[ "$ID" = "debian" || "$ID_LIKE" == *"debian"* || -f /etc/debian_version ]]; then
        PKG_MANAGER="apt"
        echo -e "${BGR}Debian-based system detected. Using apt.${NC}"
    fi
fi

if [ -z "$PKG_MANAGER" ]; then
    cat /etc/*-release 2>/dev/null
    error_exit "Unsupported operating system. This script supports Debian, RHEL/Amazon, and Alpine."
fi

# Architecture detection
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_ALT="amd64";;
  aarch64) ARCH_ALT="arm64";;
  riscv64) ARCH_ALT="riscv64";;
  *) error_exit "Unsupported architecture: $ARCH";;
esac

# Install dependencies if they are not already present
if [[ ! -f "$DEP_FLAG" ]]; then
    install_dependencies
else
    echo -e "${GR}Base packages, Python, and PRoot are already installed. Skipping dependency installation.${NC}"
fi

# Update all scripts.
update_scripts

# Execute entrypoint script
ENTRYPOINT_SCRIPT="${HOME}/entrypoint.sh"
if [[ -f "$ENTRYPOINT_SCRIPT" ]]; then
    echo -e "${BGR}Executing ${ENTRYPOINT_SCRIPT##*/}...${NC}"
    
    if command -v xz >/dev/null; then
        echo -e "${GR}Using xz from: $(command -v xz)${NC}"
    else
        echo -e "${Y}Warning: xz not found in PATH${NC}"
    fi
    
    chmod +x "$ENTRYPOINT_SCRIPT"
    exec bash "./${ENTRYPOINT_SCRIPT##*/}"
else
    error_exit "Error: ${ENTRYPOINT_SCRIPT} not found and could not be downloaded! Cannot proceed."
fi

echo -e "\nInstallation complete! For help, type 'help'"
