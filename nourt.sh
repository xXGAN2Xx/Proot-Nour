#!/bin/bash

# Configuration
export LANG=en_US.UTF-8
# Use insecure curl initially for IP check to avoid certificate issues before setup
export PUBLIC_IP=$(curl --insecure --silent -L checkip.pterodactyl-installer.se 2>/dev/null || echo "127.0.0.1")
export HOME="${HOME:-$(pwd)}"

# Color codes
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
NC='\033[0m'

DEP_FLAG="${HOME}/.dependencies_installed_v6"
export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"
# Set temp library path, but allow system libraries to take precedence
export LD_LIBRARY_PATH="${HOME}/.local/usr/lib:${HOME}/.local/usr/lib/${ARCH}-linux-gnu:${HOME}/.local/lib:${LD_LIBRARY_PATH:-}"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) DEB_ARCH="amd64" ;;
  aarch64) DEB_ARCH="arm64" ;;
  *) echo -e "${R}Unsupported architecture: $ARCH${NC}" >&2; exit 1 ;;
esac

install_dependencies() {
    echo -e "${Y}First time setup: Installing base packages...${NC}"
    
    # Setup directories
    mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin" "${HOME}/.local/tmp" "${HOME}/.local/ssl"
    
    # 1. SETUP CERTIFICATE BUNDLE
    # Download a fresh bundle to ensure we don't rely on broken container paths
    if [ ! -f "${HOME}/.local/ssl/cert.pem" ]; then
        echo -e "${Y}Setting up SSL certificates...${NC}"
        if command -v curl >/dev/null; then
            curl --insecure -L -o "${HOME}/.local/ssl/cert.pem" "https://curl.se/ca/cacert.pem" 2>/dev/null
        else
            wget --no-check-certificate -q -O "${HOME}/.local/ssl/cert.pem" "https://curl.se/ca/cacert.pem" 2>/dev/null
        fi
    fi
    
    # Use if download succeeded
    if [[ -f "${HOME}/.local/ssl/cert.pem" ]]; then
        export SSL_CERT_FILE="${HOME}/.local/ssl/cert.pem"
    fi

    # 2. ATTEMPT APT-GET (Sandboxed)
    USE_MANUAL="false"
    cd "${HOME}/.local"
    
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "${Y}Attempting sandboxed apt-get download...${NC}"
        
        # Setup pure local APT config
        mkdir -p apt/state/lists/partial apt/state/status apt/cache/archives/partial apt/etc apt/log
        touch apt/state/status
        
        cat <<EOF > apt/etc/apt.conf
Dir "${HOME}/.local/apt";
Dir::State "state";
Dir::State::status "state/status";
Dir::Cache "cache";
Dir::Etc "etc";
Dir::Etc::SourceList "etc/sources.list";
Dir::Etc::SourceParts "/dev/null";
Dir::Etc::Preferences "/dev/null";
Dir::Log "log";
Dir::Log::Terminal "/dev/null";
APT::Get::Download-Only "true";
APT::Install-Recommends "false";
Acquire::Languages "none";
EOF
        # Try to detect OS for sources.list, default to bookworm
        if [ -f /etc/os-release ]; then . /etc/os-release; fi
        OS_CODENAME="${VERSION_CODENAME:-bookworm}"
        
        echo "deb [trusted=yes] http://ftp.us.debian.org/debian ${OS_CODENAME} main" > apt/etc/sources.list
        export APT_CONFIG="${HOME}/.local/apt/etc/apt.conf"

        # Attempt update and download
        if apt-get update -o Dir::Log::Terminal="/dev/null" >/dev/null 2>&1; then
            local packages=(bash jq libjq1 libonig5 curl libcurl4 xz-utils iproute2 wget)
            if apt-get install --download-only -y "${packages[@]}" >/dev/null 2>&1; then
                echo -e "${G}APT download successful!${NC}"
                mv apt/cache/archives/*.deb . 2>/dev/null
            else
                echo -e "${Y}APT download failed. Switching to manual...${NC}"
                USE_MANUAL="true"
            fi
        else
             echo -e "${Y}APT update failed. Switching to manual...${NC}"
             USE_MANUAL="true"
        fi
    else
        echo -e "${Y}apt-get not found. Switching to manual...${NC}"
        USE_MANUAL="true"
    fi

    # 3. MANUAL FALLBACK (Dynamic Search)
    if [ "$USE_MANUAL" = "true" ]; then
        echo -e "${Y}Detecting OS and searching for packages...${NC}"
        cd "${HOME}/.local/tmp"

        # Detect OS
        if [ -f /etc/os-release ]; then
            . /etc/os-release
        else
            ID="debian"
            VERSION_CODENAME="bookworm"
        fi
        
        # Fallbacks if detection yields empty strings
        : "${ID:=debian}"
        : "${VERSION_CODENAME:=bookworm}"

        echo -e "${Y}Detected System: $ID ($VERSION_CODENAME)${NC}"

        # Packages to download
        PACKAGES=(bash jq libjq1 libonig5 curl libcurl4 xz-utils wget)

        # Helper function to find download URL
        get_deb_url() {
            local pkg="$1"
            local search_url=""
            
            if [[ "$ID" == "ubuntu" ]]; then
                search_url="https://packages.ubuntu.com/${VERSION_CODENAME}/${DEB_ARCH}/${pkg}/download"
            else
                # Default to Debian for others
                search_url="https://packages.debian.org/${VERSION_CODENAME}/${DEB_ARCH}/${pkg}/download"
            fi

            local page_content=""
            if command -v curl >/dev/null; then
                page_content=$(curl -sL --connect-timeout 10 "$search_url" 2>/dev/null)
            else
                page_content=$(wget -qO- --timeout=10 "$search_url" 2>/dev/null)
            fi

            # Extract the first valid http/https .deb link
            # We look for href="http...deb" and take the first one (usually a valid mirror)
            echo "$page_content" | grep -oE 'href="http[s]?://[^"]+\.deb"' | head -n1 | cut -d'"' -f2
        }

        # Download loop
        DL_CMD="wget -q -N"
        if ! command -v wget >/dev/null; then
            if command -v curl >/dev/null; then DL_CMD="curl -L -O -s"; else echo "No download tool found"; exit 1; fi
        fi

        for pkg in "${PACKAGES[@]}"; do
            echo -n "Searching for $pkg... "
            url=$(get_deb_url "$pkg")
            
            if [ -n "$url" ]; then
                echo "Found: $(basename "$url")"
                $DL_CMD "$url" || echo -e "${R}Failed to download $pkg${NC}"
            else
                echo -e "${R}Not found for $ID $VERSION_CODENAME${NC}"
            fi
        done
        
        mv *.deb "${HOME}/.local/" 2>/dev/null
        cd "${HOME}/.local"
    fi

    # Unpack
    echo -e "${Y}Unpacking packages...${NC}"
    shopt -s nullglob
    local deb_files=(*.deb)
    shopt -u nullglob

    if [[ ${#deb_files[@]} -gt 0 ]]; then
        for deb_file in "${deb_files[@]}"; do
            dpkg -x "$deb_file" . >/dev/null 2>&1
            rm -f "$deb_file"
        done
        echo -e "${G}Packages unpacked.${NC}"
    else
        echo -e "${R}Warning: No packages found to unpack.${NC}"
    fi

    # Cleanup
    rm -rf "${HOME}/.local/apt" "${HOME}/.local/tmp"
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
    
    touch "$DEP_FLAG"
}

update_scripts() {
    echo -e "${Y}Updating scripts...${NC}"
    
    # Use the cert bundle if we downloaded it
    if [[ -f "${HOME}/.local/ssl/cert.pem" ]]; then
        export SSL_CERT_FILE="${HOME}/.local/ssl/cert.pem"
    else
        unset SSL_CERT_FILE
    fi

    declare -A scripts=(
        ["common.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/main/scripts/common.sh"
        ["entrypoint.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/main/scripts/entrypoint.sh"
        ["helper.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/main/scripts/helper.sh"
        ["install.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/main/scripts/install.sh"
        ["run.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/main/scripts/run.sh"
        ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
        ["autorun.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/main/autorun.sh"
    )

    for path in "${!scripts[@]}"; do
        local url="${scripts[$path]}"
        local file="${HOME}/${path}"
        local temp="${file}.tmp"
        
        mkdir -p "$(dirname "$file")"
        
        # Download logic with retry
        local SUCCESS=false
        if command -v curl >/dev/null; then
             curl -sSLf --connect-timeout 10 --retry 2 -o "$temp" "$url" && SUCCESS=true
        elif command -v wget >/dev/null; then
             wget -q -O "$temp" "$url" && SUCCESS=true
        fi

        if [ "$SUCCESS" = "true" ] && [ -s "$temp" ]; then
            mv "$temp" "$file"
            chmod +x "$file"
            echo -e "${G}Updated ${path}${NC}"
        else
            rm -f "$temp"
            if [ ! -f "$file" ]; then
                echo -e "${R}Failed to download ${path}${NC}"
            fi
        fi
    done
}

# Main execution
cd "${HOME}"
[[ -f "$DEP_FLAG" ]] || install_dependencies
update_scripts

echo -e "${G}Installation complete!${NC}"

if [[ -f "${HOME}/entrypoint.sh" ]]; then
    chmod +x "${HOME}/entrypoint.sh"
    exec "${HOME}/entrypoint.sh"
else
    echo -e "${R}Error: entrypoint.sh not found. Download failed.${NC}" >&2
    exit 1
fi
