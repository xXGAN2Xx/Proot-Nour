#!/bin/bash

export LANG=en_US.UTF-8
export HOME="${HOME:-$(pwd)}"
export PUBLIC_IP=$(curl --silent -L checkip.pterodactyl-installer.se)

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; NC='\033[0m'

LOCAL_BIN="${HOME}/.local/bin"
PROOT_BIN="${HOME}/usr/local/bin/proot"
DEP_FLAG="${HOME}/.deps"

export PATH="${LOCAL_BIN}:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"
mkdir -p "$LOCAL_BIN" "${HOME}/usr/local/bin"

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

    echo -e "${Y}Installing BusyBox 1.35.0 (Core Tools)...${NC}"
    curl -Ls "$BBOX_URL" -o "${LOCAL_BIN}/busybox"
    chmod +x "${LOCAL_BIN}/busybox"
    
    for tool in xz tar unxz gzip bzip2 bash wget curl ip; do
        ln -sf ./busybox "${LOCAL_BIN}/${tool}"
    done

    echo -e "${Y}Installing static jq...${NC}"
    curl -Ls "$JQ_URL" -o "${LOCAL_BIN}/jq"
    chmod +x "${LOCAL_BIN}/jq"

    echo -e "${Y}Installing PRoot engine...${NC}"
    curl -Ls "https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static" -o "$PROOT_BIN"
    chmod +x "$PROOT_BIN"
    
    echo -e "${Y}Configuring SSL certificates...${NC}"
    mkdir -p "${HOME}/etc/ssl/certs"
    curl -Ls https://curl.se/ca/cacert.pem -o "${HOME}/etc/ssl/certs/ca-certificates.crt"

    touch "$DEP_FLAG"
}

sync_scripts() {
    echo -e "${B}Synchronizing control scripts from GitHub...${NC}"
    
    local BASE="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts"
    local SYSTEMCTL_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py"
    local AUTORUN_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
    
    declare -A scripts=(
        ["common.sh"]="$BASE/common.sh"
        ["entrypoint.sh"]="$BASE/entrypoint.sh"
        ["helper.sh"]="$BASE/helper.sh"
        ["install.sh"]="$BASE/install.sh"
        ["run.sh"]="$BASE/run.sh"
        ["usr/local/bin/systemctl"]="$SYSTEMCTL_URL"
        ["autorun.sh"]="$AUTORUN_URL"
    )

    for path in "${!scripts[@]}"; do
        mkdir -p "$(dirname "${HOME}/${path}")"
        curl -sSLf "${scripts[$path]}" -o "${HOME}/${path}"
        chmod +x "${HOME}/${path}"
    done

    if [ -f "${HOME}/entrypoint.sh" ]; then
        sed -i "2i export PATH=\"$PATH\"" "${HOME}/entrypoint.sh"
        sed -i 's|--rootfs="/"|--rootfs="/" -b /etc/resolv.conf -b /dev -b /proc -b /sys -b /tmp -b '"$HOME"':'"$HOME"'|g' "${HOME}/entrypoint.sh"
    fi

    if [ -f "${HOME}/install.sh" ]; then
        sed -i 's/tar -xf/tar --overwrite -o --no-same-permissions -xf/g' "${HOME}/install.sh"
        sed -i "2i export PATH=\"$LOCAL_BIN:\$PATH\"" "${HOME}/install.sh"
    fi
}

apply_guest_configs() {
    echo -e "${B}Optimizing Guest OS environment...${NC}"
    
    mkdir -p "${HOME}/etc/apt/apt.conf.d"
    echo 'APT::Sandbox::User "root";' > "${HOME}/etc/apt/apt.conf.d/99proot"
    
    if [ -f "${HOME}/etc/apt/sources.list" ]; then
        sed -i 's/questing/noble/g' "${HOME}/etc/apt/sources.list"
    fi
}

cd "${HOME}"

[[ -f "$DEP_FLAG" ]] || setup_tools

sync_scripts
apply_guest_configs

if [ -f "${HOME}/server.jar" ]; then
    chmod +x "${HOME}/server.jar"
fi

if [[ -f "${HOME}/entrypoint.sh" ]]; then
    echo -e "${G}Booting environment...${NC}"
    exec /bin/sh "${HOME}/entrypoint.sh"
else
    echo -e "${R}Critical Error: entrypoint.sh not found.${NC}"
    exit 1
fi
