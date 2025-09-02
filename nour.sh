#!/bin/bash
echo "Installation complete! For help, type 'help'"

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
    echo -e "${BR}${1}${NC}" >&2
    exit 1
}

# Function to detect the package manager
detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
}

# Function to install base dependencies if they are not present.
install_dependencies() {
    echo -e "${BY}First time setup: Installing base packages, Bash, Python, and PRoot...${NC}"

    mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin" || error_exit "Failed to create required directories."

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    if [ "$pkg_manager" = "apt" ]; then
        # Download required packages
        local apt_pkgs_to_download=(curl bash ca-certificates xz-utils python3-minimal)
        echo -e "${Y}Downloading required .deb packages...${NC}"
        apt download "${apt_pkgs_to_download[@]}" || error_exit "Failed to download .deb packages. Please check network and apt sources."

        # Extract packages
        shopt -s nullglob # Prevent errors if no .deb files match
        local deb_files=("$PWD"/*.deb)
        [[ ${#deb_files[@]} -eq 0 ]] && error_exit "No .deb files found to extract."

        for deb_file in "${deb_files[@]}"; do
            echo -e "${GR}Unpacking $(basename "$deb_file") → ${HOME}/.local/${NC}"
            dpkg -x "$deb_file" "${HOME}/.local/" || error_exit "Failed to extract $deb_file"
            rm "$deb_file"
        done

        # Verify that our local xz is now available
        if ! command -v xz >/dev/null; then
            echo -e "${Y}Warning: xz not found in PATH after package extraction.${NC}" >&2
        else
            echo -e "${BGR}Local xz is available at: $(command -v xz)${NC}"
        fi
    else
        echo -e "${Y}Skipping apt package download on a non-Debian based system (${pkg_manager}).${NC}"
    fi


    # Install PRoot
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
        # Run each download/update check in the background
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
        pids+=($!) # Store the process ID of the background job
    done

    # Wait for all background download jobs to finish
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    echo -e "${BGR}Script update check complete.${NC}"
}


# --- Main Execution ---

# Move to the HOME directory for predictable relative paths
cd "${HOME}"

# Architecture detection
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_ALT="amd64";;
  aarch64) ARCH_ALT="arm64";;
  riscv64) ARCH_ALT="riscv64";;
  *) error_exit "Unsupported architecture: $ARCH";;
esac

# Check for Debian-based system
if [[ ! -f /etc/debian_version ]]; then
    cat /etc/*-release
    echo -e "${Y}This is not a Debian-based system. apt commands will be skipped.${NC}"
else
    echo -e "${GR}This is a Debian-based system. Continuing...${NC}"
fi


# Install dependencies if the flag file doesn't exist.
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
    # Use exec to replace the current shell process with the new one.
    exec bash "./${ENTRYPOINT_SCRIPT##*/}"
else
    error_exit "Error: ${ENTRYPOINT_SCRIPT} not found and could not be downloaded! Cannot proceed."
fi
