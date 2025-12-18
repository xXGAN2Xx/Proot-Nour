#!/bin/bash

# Configuration
export LANG=en_US.UTF-8
export PUBLIC_IP=$(curl --silent -L checkip.pterodactyl-installer.se 2>/dev/null || echo "127.0.0.1")
export HOME="${HOME:-$(pwd)}"

# Color codes
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
NC='\033[0m'

DEP_FLAG="${HOME}/.dependencies_installed_v2"
export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) DEB_ARCH="amd64" ;;
  aarch64) DEB_ARCH="arm64" ;;
  *) echo -e "${R}Unsupported architecture: $ARCH${NC}" >&2; exit 1 ;;
esac

export LD_LIBRARY_PATH="${HOME}/.local/usr/lib:${HOME}/.local/usr/lib/${ARCH}-linux-gnu:${HOME}/.local/lib:${LD_LIBRARY_PATH:-}"

install_dependencies() {
    echo -e "${Y}First time setup: Installing base packages and PRoot...${NC}"
    mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin" "${HOME}/.local/tmp"
    cd "${HOME}/.local"

    # 1. ATTEMPT APT-GET DOWNLOAD
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "${Y}Attempting download via apt-get...${NC}"
        
        # Setup local apt directories
        local apt_dir="${HOME}/.local/apt"
        mkdir -p "${apt_dir}/lists/partial" "${apt_dir}/archives/partial" "${apt_dir}/dpkg/updates"
        touch "${apt_dir}/dpkg/status"

        local apt_opts=(
            "-o" "Dir::State=${apt_dir}"
            "-o" "Dir::State::status=${apt_dir}/dpkg/status"
            "-o" "Dir::Cache=${apt_dir}"
            "-o" "Dir::Etc::SourceList=/dev/null"
            "-o" "Dir::Etc::SourceParts=/dev/null"
        )
        
        # Determine sources based on Debian release or default to bookworm
        # We manually add a source line to ensure we have a repo to download from
        echo "deb [trusted=yes] http://ftp.us.debian.org/debian bookworm main" > "${apt_dir}/sources.list"
        apt_opts+=("-o" "Dir::Etc::SourceList=${apt_dir}/sources.list")

        if apt-get "${apt_opts[@]}" update >/dev/null 2>&1; then
            local packages=(bash jq libjq1 libonig5 curl libcurl4 xz-utils ca-certificates iproute2 wget)
            if apt-get "${apt_opts[@]}" download "${packages[@]}" >/dev/null 2>&1; then
                echo -e "${G}Successfully downloaded packages via apt-get.${NC}"
                USE_MANUAL="false"
            else
                echo -e "${R}apt-get download failed.${NC}"
                USE_MANUAL="true"
            fi
        else
            echo -e "${R}apt-get update failed.${NC}"
            USE_MANUAL="true"
        fi
    else
        USE_MANUAL="true"
    fi

    # 2. FALLBACK TO MANUAL DOWNLOAD
    if [ "$USE_MANUAL" = "true" ]; then
        echo -e "${Y}Switching to manual download (wget)...${NC}"
        cd "${HOME}/.local/tmp" # Download to temp first

        MIRROR="http://ftp.us.debian.org/debian/pool/main"
        
        # UPDATED VERSIONS (Debian Bookworm Stable - Late 2025)
        if [ "$DEB_ARCH" = "amd64" ]; then
            DEB_URLS=(
                "$MIRROR/b/bash/bash_5.2.15-2+b9_amd64.deb"
                "$MIRROR/j/jq/jq_1.6-2.1+deb12u1_amd64.deb"
                "$MIRROR/j/jq/libjq1_1.6-2.1+deb12u1_amd64.deb"
                "$MIRROR/libo/libonig/libonig5_6.9.8-1_amd64.deb"
                "$MIRROR/c/curl/curl_7.88.1-10+deb12u14_amd64.deb"
                "$MIRROR/c/curl/libcurl4_7.88.1-10+deb12u14_amd64.deb"
                "$MIRROR/x/xz-utils/xz-utils_5.4.1-1_amd64.deb"
                "$MIRROR/c/ca-certificates/ca-certificates_20230311+deb12u1_all.deb"
                "$MIRROR/w/wget/wget_1.21.3-1+deb12u1_amd64.deb"
                "$MIRROR/i/iproute2/iproute2_6.1.0-3_amd64.deb"
            )
        elif [ "$DEB_ARCH" = "arm64" ]; then
            DEB_URLS=(
                "$MIRROR/b/bash/bash_5.2.15-2+b7_arm64.deb"
                "$MIRROR/j/jq/jq_1.6-2.1+deb12u1_arm64.deb"
                "$MIRROR/j/jq/libjq1_1.6-2.1+deb12u1_arm64.deb"
                "$MIRROR/libo/libonig/libonig5_6.9.8-1_arm64.deb"
                "$MIRROR/c/curl/curl_7.88.1-10+deb12u14_arm64.deb"
                "$MIRROR/c/curl/libcurl4_7.88.1-10+deb12u14_arm64.deb"
                "$MIRROR/x/xz-utils/xz-utils_5.4.1-1_arm64.deb"
                "$MIRROR/c/ca-certificates/ca-certificates_20230311+deb12u1_all.deb"
                "$MIRROR/w/wget/wget_1.21.3-1+deb12u1_arm64.deb"
                "$MIRROR/i/iproute2/iproute2_6.1.0-3_arm64.deb"
            )
        fi

        # Download tool check
        DL_CMD="wget -q -N"
        if ! command -v wget >/dev/null; then
            if command -v curl >/dev/null; then DL_CMD="curl -L -O -s"; else echo "No download tool found"; exit 1; fi
        fi

        for url in "${DEB_URLS[@]}"; do
            echo -e "${Y}Downloading $(basename "$url")...${NC}"
            $DL_CMD "$url" || echo -e "${R}Failed to download $(basename "$url")${NC}"
        done
        
        # Move downloaded debs to .local for unpacking
        mv *.deb "${HOME}/.local/" 2>/dev/null
        cd "${HOME}/.local"
    fi

    # 3. UNPACK DEBS
    echo -e "${Y}Unpacking packages...${NC}"
    shopt -s nullglob
    local deb_files=(*.deb)
    shopt -u nullglob

    if [[ ${#deb_files[@]} -gt 0 ]]; then
        for deb_file in "${deb_files[@]}"; do
            echo -e "${G}Unpacking $deb_file${NC}"
            dpkg -x "$deb_file" .
            rm "$deb_file"
        done
    else
        echo -e "${R}Warning: No .deb files found to unpack.${NC}"
    fi

    # Setup CA Certs
    if [ -d "${HOME}/.local/usr/share/ca-certificates" ]; then
        export SSL_CERT_FILE="${HOME}/.local/usr/share/ca-certificates/ca-certificates.crt"
    fi

    cd "${HOME}"
    
    # 4. INSTALL PROOT
    echo -e "${Y}Installing PRoot...${NC}"
    local proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    if command -v curl >/dev/null; then
        curl -Ls "$proot_url" -o "${HOME}/usr/local/bin/proot"
    else
        wget -qO "${HOME}/usr/local/bin/proot" "$proot_url"
    fi
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
        
        if command -v curl >/dev/null; then
             curl -sSLf --connect-timeout 10 --retry 2 -o "$temp" "$url" 2>/dev/null
        else
             wget -q -O "$temp" "$url"
        fi

        if [[ -f "$temp" ]]; then
            mv "$temp" "$file"
            chmod +x "$file"
            echo -e "${G}Updated ${path}${NC}"
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

echo -e "${G}Installation complete!${NC}"

if [[ -f "${HOME}/entrypoint.sh" ]]; then
    echo -e "${G}Starting entrypoint...${NC}"
    chmod +x "${HOME}/entrypoint.sh"
    exec "${HOME}/entrypoint.sh"
else
    echo -e "${R}Error: entrypoint.sh not found${NC}" >&2
    exit 1
fi
