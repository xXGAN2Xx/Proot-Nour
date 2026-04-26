#!/bin/bash

export LANG=en_US.UTF-8
export HOME="${HOME:-$(pwd)}"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; NC='\033[0m'

LOCAL_BIN="${HOME}/.local/bin"
PROOT_BIN="${HOME}/usr/local/bin/proot"
DEP_FLAG="${HOME}/.deps"

export PATH="${LOCAL_BIN}:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"
mkdir -p "$LOCAL_BIN" "${HOME}/usr/local/bin"

# Set environment variables for SSL certificates so tools can find them
export SSL_CERT_FILE="${HOME}/.local/etc/ssl/certs/ca-certificates.crt"
export CURL_CA_BUNDLE="${HOME}/.local/etc/ssl/certs/ca-certificates.crt"
export WGETRC="${HOME}/.wgetrc"

setup_tools() {
    echo -e "${B}Checking system architecture...${NC}"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  
            BBOX_URL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
            JQ_URL="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64"
            ;;
        aarch64) 
            BBOX_URL="https://busybox.net/downloads/binaries/1.35.0-armv8l-linux-musl/busybox"
            JQ_URL="https://github.com/jqlang/jq/releases/latest/download/jq-linux-arm64"
            ;;
        *) echo -e "${R}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
    esac

    echo -e "${Y}Installing ca-certificates...${NC}"
    mkdir -p "${HOME}/.local/etc/ssl/certs"
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -k "https://curl.se/ca/cacert.pem" -o "$SSL_CERT_FILE"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate "https://curl.se/ca/cacert.pem" -O "$SSL_CERT_FILE"
    else
        echo -e "${R}Error: Neither wget nor curl found to download ca-certificates.${NC}"
        exit 1
    fi
    
    # Configure wget to use the downloaded certificates
    echo "ca_certificate = $SSL_CERT_FILE" > "$WGETRC"

    echo -e "${Y}Installing BusyBox 1.35.0...${NC}"
    if command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate "$BBOX_URL" -O "${LOCAL_BIN}/busybox"
    elif command -v curl >/dev/null 2>&1; then
        curl -sSL -k "$BBOX_URL" -o "${LOCAL_BIN}/busybox"
    fi
    chmod +x "${LOCAL_BIN}/busybox"
    
    for tool in xz tar unxz gzip bzip2 bash ip wget; do
        ln -sf ./busybox "${LOCAL_BIN}/${tool}"
    done

    echo -e "${Y}Installing static jq...${NC}"
    "${LOCAL_BIN}/wget" -q "$JQ_URL" -O "${LOCAL_BIN}/jq"
    chmod +x "${LOCAL_BIN}/jq"

    echo -e "${Y}Installing PRoot engine...${NC}"
    "${LOCAL_BIN}/wget" -q "https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static" -O "$PROOT_BIN"
    chmod +x "$PROOT_BIN"
    touch "$DEP_FLAG"
}

sync_scripts() {
    echo -e "${B}Synchronizing scripts with wget...${NC}"
    
    # Reverted to the original working BASE URL
    local BASE="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts"
    local SYSTEMCTL_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py"
    
    # Fixed the array formatting so URLs don't merge
    declare -A scripts=(
        ["common.sh"]="$BASE/common.sh"
        ["entrypoint.sh"]="$BASE/entrypoint.sh"["helper.sh"]="$BASE/helper.sh"
        ["install.sh"]="$BASE/install.sh"
        ["run.sh"]="$BASE/run.sh"
        ["autorun.sh"]="$BASE/autorun.sh"
        ["usr/local/bin/systemctl"]="$SYSTEMCTL_URL"
        ["vnc_install.sh"]="$BASE/vnc/install.sh"
    )

    for path in "${!scripts[@]}"; do
        mkdir -p "$(dirname "${HOME}/${path}")"
        wget -q "${scripts[$path]}" -O "${HOME}/${path}"
        chmod +x "${HOME}/${path}"
    done
}

cd "${HOME}"

# 1. Install tools first (which provides 'wget' if it's missing)
[[ -f "$DEP_FLAG" ]] || setup_tools

# 2. Now it is safe to use wget to fetch the IP
export server_ip=$(wget -qO- checkip.pterodactyl-installer.se)

# 3. Continue with the rest of the script
sync_scripts

# 4. Fixed syntax error (added the required space after 'if')
if[ -f "${HOME}/server.jar" ]; then
    chmod +x "${HOME}/server.jar"
fi

if [[ -f "${HOME}/entrypoint.sh" ]]; then
    echo -e "${G}Booting...${NC}"
    exec /bin/sh "${HOME}/entrypoint.sh"
else
    echo -e "${R}Error: entrypoint.sh missing.${NC}"; exit 1
fi
