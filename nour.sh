#!/bin/bash

echo "Done (s)! For help, type help"
echo "$(pwd)"

# Set HOME and DEBIAN_FRONTEND with proper checks
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

# Architecture detection with error handling
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_ALT="amd64";;
  aarch64) ARCH_ALT="arm64";;
  riscv64) ARCH_ALT="riscv64";;
  *) 
    echo -e "${BR}Unsupported architecture: $ARCH${NC}" >&2
    exit 1
    ;;
esac

# Check for Debian-based system
if [[ ! -f /etc/debian_version ]]; then
    echo -e "${BR}This is not a Debian-based system. Exiting.${NC}" >&2
    exit 1
fi
echo -e "${GR}This is a Debian-based system. Continuing...${NC}"

DEP_FLAG="${HOME}/.dependencies_installed_v2"

# Ensure local binaries are prioritized in PATH (put them first)
export PATH="${HOME}/.local/bin:${HOME}/usr/local/bin:${PATH}"

# Check if we need to install dependencies
# Only skip installation if our local xz exists and works
LOCAL_XZ="${HOME}/.local/bin/xz"
if [[ -f "$LOCAL_XZ" ]] && [[ -x "$LOCAL_XZ" ]]; then
    echo -e "${BGR}Found local xz installation.${NC}"
    if [[ ! -f "$DEP_FLAG" ]]; then
        echo -e "${Y}Local dependencies appear to be installed. Creating flag.${NC}"
        touch "$DEP_FLAG"
    fi
fi

# Install dependencies if needed
if [[ ! -f "$DEP_FLAG" ]]; then
    echo -e "${BY}First time setup: Installing base packages, Python, and PRoot...${NC}"
    
    # Create directories with error handling
    if ! mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin"; then
        echo -e "${BR}Failed to create required directories.${NC}" >&2
        exit 1
    fi
    
    # Download required packages
    apt_pkgs_to_download=(curl ca-certificates xz-utils python3-minimal)
    echo -e "${Y}Downloading required .deb packages (including xz-utils and python3-minimal)...${NC}"
    
    if ! apt download "${apt_pkgs_to_download[@]}"; then
        echo -e "${BR}Failed to download .deb packages. Please check network and apt sources.${NC}" >&2
        exit 1
    fi
    
    # Extract packages with proper error handling
    shopt -s nullglob  # Handle case where no .deb files exist
    deb_files=("$PWD"/*.deb)
    
    if [[ ${#deb_files[@]} -eq 0 ]]; then
        echo -e "${BR}No .deb files found to extract.${NC}" >&2
        exit 1
    fi
    
    for deb_file in "${deb_files[@]}"; do
        if [[ -f "$deb_file" ]]; then
            echo -e "${GR}Unpacking $(basename "$deb_file") → ${HOME}/.local/${NC}"
            if ! dpkg -x "$deb_file" "${HOME}/.local/"; then
                echo -e "${BR}Failed to extract $deb_file${NC}" >&2
                exit 1
            fi
            rm "$deb_file"
        fi
    done
    
    # After extraction, update PATH to ensure our local binaries are found first
    export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"
    
    # Verify that xz was installed correctly
    LOCAL_XZ="${HOME}/.local/bin/xz"
    if [[ ! -f "$LOCAL_XZ" ]]; then
        # Sometimes xz might be in a different location after extraction
        if [[ -f "${HOME}/.local/usr/bin/xz" ]]; then
            LOCAL_XZ="${HOME}/.local/usr/bin/xz"
            echo -e "${Y}Found xz at ${LOCAL_XZ}${NC}"
        else
            echo -e "${BR}Warning: xz not found after package extraction${NC}" >&2
        fi
    fi
    
    if [[ -f "$LOCAL_XZ" ]]; then
        echo -e "${BGR}Local xz installed at: $LOCAL_XZ${NC}"
        # Make sure it's executable
        chmod +x "$LOCAL_XZ" 2>/dev/null || true
    fi
    
    # Install PRoot
    echo -e "${Y}Installing PRoot...${NC}"
    proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    
    if ! curl -Ls "$proot_url" -o "${HOME}/usr/local/bin/proot"; then
        echo -e "${BR}Failed to download PRoot.${NC}" >&2
        exit 1
    fi
    
    if ! chmod +x "${HOME}/usr/local/bin/proot"; then
        echo -e "${BR}Failed to make PRoot executable.${NC}" >&2
        exit 1
    fi
    
    echo -e "${BGR}PRoot installed successfully.${NC}"
    touch "$DEP_FLAG"
else
    echo -e "${GR}Base packages, Python, and PRoot already installed or assumed present. Skipping dependency installation.${NC}"
fi

# Update scripts and tools
echo -e "${BY}Checking for script and tool updates...${NC}"

# Use associative array properly
declare -A scripts_to_manage=(
    ["common.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/raw/main/scripts/common.sh"
    ["entrypoint.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/raw/main/scripts/entrypoint.sh"
    ["helper.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/raw/main/scripts/helper.sh"
    ["install.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/raw/main/scripts/install.sh"
    ["run.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/raw/main/scripts/run.sh"
    ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
)

for dest_path_suffix in "${!scripts_to_manage[@]}"; do
    url="${scripts_to_manage[$dest_path_suffix]}"
    local_file="${HOME}/${dest_path_suffix}"
    temp_file="${local_file}.new"
    
    # Ensure target directory exists
    local_dir=$(dirname "$local_file")
    if ! mkdir -p "$local_dir"; then
        echo -e "${BR}Failed to create directory: $local_dir${NC}" >&2
        continue
    fi

    echo -n -e "${Y}Checking ${dest_path_suffix}... ${NC}"
    
    if curl -sSLf --connect-timeout 15 --retry 3 -o "$temp_file" "$url"; then
        # Check if file needs updating
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
        # Clean up temp file on download failure
        [[ -f "$temp_file" ]] && rm "$temp_file"
        echo -e "${BR}Download failed. Will try to use local version of ${dest_path_suffix} if available.${NC}" >&2
    fi
done

# Execute entrypoint script
ENTRYPOINT_SCRIPT="${HOME}/entrypoint.sh"
if [[ -f "$ENTRYPOINT_SCRIPT" ]]; then
    echo -e "${BGR}Executing ${ENTRYPOINT_SCRIPT##*/}...${NC}"
    
    # Ensure our local binaries are prioritized before executing
    export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"
    
    # Show which xz will be used
    if command -v xz >/dev/null 2>&1; then
        XZ_PATH=$(command -v xz)
        echo -e "${GR}Using xz from: ${XZ_PATH}${NC}"
    else
        echo -e "${Y}Warning: xz not found in PATH${NC}"
    fi
    
    cd "${HOME}"
    chmod +x "$ENTRYPOINT_SCRIPT"
    exec bash "./${ENTRYPOINT_SCRIPT##*/}"
else
    echo -e "${BR}Error: ${ENTRYPOINT_SCRIPT} not found and could not be downloaded! Cannot proceed.${NC}" >&2
    exit 1
fi
