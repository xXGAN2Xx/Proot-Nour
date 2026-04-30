#!/bin/bash

export LANG=en_US.UTF-8
export HOME="/home/container"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; NC='\033[0m'

LOCAL_BIN="${HOME}/.local/bin"
PROOT_BIN="${HOME}/usr/local/bin/proot"
SYSTEMCTL_BIN="${HOME}/usr/local/bin/systemctl"
DEP_FLAG="${HOME}/.deps"

export PATH="${LOCAL_BIN}:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"
mkdir -p "$LOCAL_BIN" "${HOME}/usr/local/bin"

setup_tools() {
    echo -e "${B}Checking system architecture...${NC}"
    ARCH=$(uname -m)
    
    case "$ARCH" in
        x86_64|amd64)  
            BBOX_URL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
            JQ_URL="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64"
            ;;
        i*86)
            BBOX_URL="https://busybox.net/downloads/binaries/1.35.0-i686-linux-musl/busybox"
            JQ_URL="https://github.com/jqlang/jq/releases/latest/download/jq-linux-i386"
            ;;
        *) 
            echo -e "${R}Error: Unsupported architecture: $ARCH${NC}" >&2
            exit 1 
            ;;
    esac

    echo -e "${Y}Installing BusyBox 1.35.0...${NC}"
    if command -v wget >/dev/null 2>&1; then
        wget -q "$BBOX_URL" -O "${LOCAL_BIN}/busybox"
    elif command -v curl >/dev/null 2>&1; then
        curl -sSL "$BBOX_URL" -o "${LOCAL_BIN}/busybox"
    else
        echo -e "${R}Error: Neither wget nor curl found to download initial tools.${NC}"
        exit 1
    fi
    chmod +x "${LOCAL_BIN}/busybox"
    
    for tool in xz tar unxz gzip bzip2 bash ip wget; do
        ln -sf ./busybox "${LOCAL_BIN}/${tool}"
    done

    echo -e "${Y}Installing static jq...${NC}"
    "${LOCAL_BIN}/wget" -q "$JQ_URL" -O "${LOCAL_BIN}/jq"
    chmod +x "${LOCAL_BIN}/jq"

    touch "$DEP_FLAG"
}

check_proot() {
    if [ ! -f "$PROOT_BIN" ]; then
        echo -e "${Y}PRoot not found. Downloading PRoot engine...${NC}"
        local ARCH=$(uname -m)
        wget -q "https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static" -O "$PROOT_BIN"
        chmod +x "$PROOT_BIN"
    else
        echo -e "${G}PRoot is already downloaded and ready.${NC}"
    fi
}

check_systemctl() {
    if [ ! -f "$SYSTEMCTL_BIN" ]; then
        echo -e "${Y}systemctl not found. Downloading systemctl replacement...${NC}"
        wget -q "https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py" -O "$SYSTEMCTL_BIN"
        chmod +x "$SYSTEMCTL_BIN"
    else
        echo -e "${G}systemctl is already downloaded and ready.${NC}"
    fi
}

sync_scripts() {
    echo -e "${B}Synchronizing scripts with wget...${NC}"
    
    local BASE="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts"
    
    declare -A scripts=(
        ["common.sh"]="$BASE/common.sh"
        ["entrypoint.sh"]="$BASE/entrypoint.sh"
        ["install.sh"]="$BASE/install.sh"
        ["run.sh"]="$BASE/run.sh"
        ["autorun.sh"]="$BASE/autorun.sh"
        ["vnc_install.sh"]="$BASE/vnc/install.sh"
    )

    for path in "${!scripts[@]}"; do
        mkdir -p "$(dirname "${HOME}/${path}")"
        wget -q "${scripts[$path]}" -O "${HOME}/${path}"
        chmod +x "${HOME}/${path}"
    done
}

cd "${HOME}"
[[ -f "$DEP_FLAG" ]] || setup_tools

# Check for proot and systemctl every time the script runs
check_proot
check_systemctl

sync_scripts

if [ -f "${HOME}/server.jar" ]; then
    chmod +x "${HOME}/server.jar"
fi

if [[ -f "${HOME}/entrypoint.sh" ]]; then
    echo -e "${G}Booting...${NC}"
    export server_ip=$(wget -qO- api.ipify.org)
    # Detect if seccomp is blocked and disable it if so
    if ! $HOME/usr/local/bin/proot --version >/dev/null 2>&1; then
        export PROOT_NO_SECCOMP=1
    fi
    exec /bin/sh "${HOME}/entrypoint.sh"
else
    echo -e "${R}Error: entrypoint.sh missing.${NC}"; exit 1
fi
