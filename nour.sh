#!/bin/bash

# Configuration
export LANG=en_US.UTF-8
export PUBLIC_IP=$(curl --silent -L checkip.pterodactyl-installer.se)
export HOME="${HOME:-$(pwd)}"

# Simple color codes (removed unused ones)
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
NC='\033[0m'

DEP_FLAG="${HOME}/.dependencies_installed_v2"
export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"

# Detect architecture once
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|aarch64|riscv64) ;;
  *) echo -e "${R}Unsupported architecture: $ARCH${NC}" >&2; exit 1;;
esac

# Set library path
export LD_LIBRARY_PATH="${HOME}/.local/usr/lib/${ARCH}-linux-gnu:${HOME}/.local/usr/lib:${HOME}/.local/lib:${LD_LIBRARY_PATH:-}"

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

install_dependencies() {
    echo -e "${Y}First time setup: Installing base packages and PRoot...${NC}"

    mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin"

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    if [ "$pkg_manager" = "apt" ]; then
        local apt_dir="${HOME}/.local/apt"
        
        mkdir -p "${apt_dir}/lists/partial" "${apt_dir}/archives/partial" "${apt_dir}/dpkg/updates"
        touch "${apt_dir}/dpkg/status"

        local apt_opts=(
            "-o" "Dir::State=${apt_dir}"
            "-o" "Dir::State::status=${apt_dir}/dpkg/status"
            "-o" "Dir::Cache=${apt_dir}"
        )

        echo -e "${Y}Updating apt package lists...${NC}"
        apt-get "${apt_opts[@]}" update 2>/dev/null || echo -e "${Y}Warning: apt update had issues${NC}"

        # Core packages only (removed ca-certificates, iproute2 as they don't work well unpacked)
        # libjq1 and libonig5 are jq dependencies
        local packages=(bash jq libjq1 libonig5 curl xz-utils)
        
        echo -e "${Y}Downloading packages...${NC}"
        cd "${HOME}/.local"
        apt-get "${apt_opts[@]}" download "${packages[@]}" 2>/dev/null || true

        # Extract all .deb files
        shopt -s nullglob
        local deb_files=(*.deb)
        shopt -u nullglob
        
        if [[ ${#deb_files[@]} -gt 0 ]]; then
            for deb_file in "${deb_files[@]}"; do
                echo -e "${G}Unpacking $(basename "$deb_file")${NC}"
                dpkg -x "$deb_file" .
                rm "$deb_file"
            done
        else
            echo -e "${Y}Warning: No .deb files found${NC}"
        fi
        
        cd "${HOME}"
    fi

    # Install PRoot
    echo -e "${Y}Installing PRoot...${NC}"
    local proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    curl -Ls "$proot_url" -o "${HOME}/usr/local/bin/proot"
    chmod +x "${HOME}/usr/local/bin/proot"

    echo -e "${G}Dependencies installed successfully${NC}"
    touch "$DEP_FLAG"
}

update_scripts() {
    echo -e "${Y}Updating scripts...${NC}"

    declare -A scripts=(
        ["common.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/common.sh"
        ["entrypoint.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/entrypoint.sh"
        ["helper.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/helper.sh"
        ["install.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/install.sh"
        ["run.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/run.sh"
        ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py"
        ["autorun.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
    )

    for path in "${!scripts[@]}"; do
        local url="${scripts[$path]}"
        local file="${HOME}/${path}"
        local temp="${file}.tmp"
        
        mkdir -p "$(dirname "$file")"

        if curl -sSLf --connect-timeout 10 --retry 2 -o "$temp" "$url" 2>/dev/null; then
            if [[ ! -f "$file" ]] || ! cmp -s "$file" "$temp"; then
                mv "$temp" "$file"
                chmod +x "$file"
                echo -e "${G}Updated ${path}${NC}"
            else
                rm "$temp"
            fi
        else
            rm -f "$temp"
            [[ -f "$file" ]] || echo -e "${R}Warning: Failed to download ${path}${NC}"
        fi
    done
}

# Main execution
cd "${HOME}"

[[ -f "$DEP_FLAG" ]] || install_dependencies
update_scripts

# Installation complete
echo -e "${G}Installation complete! For help, type 'help'${NC}"

# Execute entrypoint
if [[ -f "${HOME}/entrypoint.sh" ]]; then
    echo -e "${G}Starting entrypoint...${NC}"
    chmod +x "${HOME}/entrypoint.sh"
    exec "${HOME}/entrypoint.sh"
else
    echo -e "${R}Error: entrypoint.sh not found${NC}" >&2
    exit 1
fi
