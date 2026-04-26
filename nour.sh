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
            CURL_URL="https://github.com/moparisthebest/static-curl/releases/latest/download/curl-amd64"
            ;;
        aarch64) 
            BBOX_URL="https://busybox.net/downloads/binaries/1.35.0-armv8l-linux-musl/busybox"
            JQ_URL="https://github.com/jqlang/jq/releases/latest/download/jq-linux-arm64"
            CURL_URL="https://github.com/moparisthebest/static-curl/releases/latest/download/curl-aarch64"
            ;;
        *) echo -e "${R}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
    esac

    echo -e "${Y}Installing BusyBox 1.35.0...${NC}"
    if command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate "$BBOX_URL" -O "${LOCAL_BIN}/busybox"
    elif command -v curl >/dev/null 2>&1; then
        curl -sSL -k "$BBOX_URL" -o "${LOCAL_BIN}/busybox"
    else
        echo -e "${R}Error: Neither wget nor curl found to download initial tools.${NC}"
        exit 1
    fi
    chmod +x "${LOCAL_BIN}/busybox"
    
    # Symlink busybox tools (wget is included here)
    for tool in xz tar unxz gzip bzip2 bash ip wget; do
        ln -sf ./busybox "${LOCAL_BIN}/${tool}"
    done

    echo -e "${Y}Installing static curl...${NC}"
    "${LOCAL_BIN}/wget" -q --no-check-certificate "$CURL_URL" -O "${LOCAL_BIN}/curl"
    chmod +x "${LOCAL_BIN}/curl"

    echo -e "${Y}Installing ca-certificates...${NC}"
    mkdir -p "${HOME}/.local/etc/ssl/certs"
    "${LOCAL_BIN}/curl" -sSL -k "https://curl.se/ca/cacert.pem" -o "$SSL_CERT_FILE"
    
    # Configure wget to use the downloaded certificates automatically
    echo "ca_certificate = $SSL_CERT_FILE" > "$WGETRC"

    echo -e "${Y}Installing static jq...${NC}"
    "${LOCAL_BIN}/curl" -sSL "$JQ_URL" -o "${LOCAL_BIN}/jq"
    chmod +x "${LOCAL_BIN}/jq"

    echo -e "${Y}Installing PRoot engine...${NC}"
    "${LOCAL_BIN}/curl" -sSL "https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static" -o "$PROOT_BIN"
    chmod +x "$PROOT_BIN"
    
    touch "$DEP_FLAG"
}

sync_scripts() {
    echo -e "${B}Synchronizing scripts with curl...${NC}"
    
    local BASE="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts"
    local SYSTEMCTL_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py"
    
    declare -A scripts=(["common.sh"]="$BASE/common.sh"
        ["entrypoint.sh"]="$BASE/entrypoint.sh"
        ["helper.sh"]="$BASE/helper.sh"
        ["install.sh"]="$BASE/install.sh"
        ["run.sh"]="$BASE/run.sh"["autorun.sh"]="$BASE/autorun.sh"["usr/local/bin/systemctl"]="$SYSTEMCTL_URL"
        ["vnc_install.sh"]="$BASE/vnc/install.sh"
    )

    for path in "${!scripts[@]}"; do
        mkdir -p "$(dirname "${HOME}/${path}")"
        # Now using our newly installed static curl with working ca-certificates!
        curl -sSL "${scripts[$path]}" -o "${HOME}/${path}"
        chmod +x "${HOME}/${path}"
    done
}

cd "${HOME}"

# 1. Install tools first (which provides 'wget', 'curl', and 'ca-certificates')
[[ -f "$DEP_FLAG" ]] || setup_tools

# 2. Now it is safe to use curl to fetch the IP
export server_ip=$(curl -sSL checkip.pterodactyl-installer.se)

# 3. Continue with the rest of the script
sync_scripts

if [ -f "${HOME}/server.jar" ]; then
    chmod +x "${HOME}/server.jar"
fi

if [[ -f "${HOME}/entrypoint.sh" ]]; then
    echo -e "${G}Booting...${NC}"
    exec /bin/sh "${HOME}/entrypoint.sh"
else
    echo -e "${R}Error: entrypoint.sh missing.${NC}"; exit 1
fi
