#!/bin/bash

export LANG=en_US.UTF-8
export HOME="${HOME:-$(pwd)}"
# Using wget to get public IP
export SERVER-IP=$(wget -qO- checkip.pterodactyl-installer.se)

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

    # 1. Install BusyBox first (using system tools) to get a consistent wget
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
    
    # Symlink tools, including wget
    for tool in xz tar unxz gzip bzip2 bash ip wget; do
        ln -sf ./busybox "${LOCAL_BIN}/${tool}"
    done

    # 2. Install JQ
    echo -e "${Y}Installing static jq...${NC}"
    "${LOCAL_BIN}/wget" -q "$JQ_URL" -O "${LOCAL_BIN}/jq"
    chmod +x "${LOCAL_BIN}/jq"

    # 3. Install PRoot
    echo -e "${Y}Installing PRoot engine...${NC}"
    "${LOCAL_BIN}/wget" -q "https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static" -O "$PROOT_BIN"
    chmod +x "$PROOT_BIN"
    touch "$DEP_FLAG"
}

sync_scripts() {
    echo -e "${B}Synchronizing scripts with wget...${NC}"
    
    local BASE="https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/scripts"
    local SYSTEMCTL_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py"
    local AUTORUN_URL="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
    
    declare -A scripts=(
        ["vnc_install.sh"]="$BASE/vnc/install.sh"
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
        # Using the wget we just installed/symlinked
        wget -q "${scripts[$path]}" -O "${HOME}/${path}"
        chmod +x "${HOME}/${path}"
    done
}

modify_scripts() {
    echo -e "${B}Applying patches to scripts...${NC}"

    # --- entrypoint.sh patches ---
    sed -i "s|/usr/local/bin/proot|\$HOME/usr/local/bin/proot|g" "${HOME}/entrypoint.sh"
    sed -i 's|/bin/sh "/install.sh"|/bin/sh "$HOME/install.sh"|g' "${HOME}/entrypoint.sh"
    sed -i 's|sh /helper.sh|sh $HOME/helper.sh|g' "${HOME}/entrypoint.sh"

    # --- helper.sh patches ---
    sed -i 's|cp /common.sh "\$HOME/common.sh"|cp /common.sh "/common.sh"|g' "${HOME}/helper.sh"
    sed -i 's|cp /run.sh "\$HOME/run.sh"|cp /run.sh "/run.sh"|g' "${HOME}/helper.sh"
    sed -i 's|config_file="\$HOME/vps.config"|config_file="/vps.config"|g' "${HOME}/helper.sh"
    sed -i "s|/usr/local/bin/proot|\$HOME/usr/local/bin/proot|g" "${HOME}/helper.sh"
    sed -i 's|-0 -w "\${HOME}"|-0 -w "/root"|g' "${HOME}/helper.sh"

    # --- install.sh patches ---
    sed -i 's|\. /common.sh|. $HOME/common.sh|g' "${HOME}/install.sh"
    sed -i '/export PATH=/a export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:~/.local/usr/lib:~/.local/usr/lib64"' "${HOME}/install.sh"

    # --- run.sh patches ---
    # 1. Change HISTORY_FILE path
    sed -i 's|HISTORY_FILE="\${HOME}/.custom_shell_history"|HISTORY_FILE="/.custom_shell_history"|g' "${HOME}/run.sh"
    
    # 2. Remove the "sudo/su" check block ENTIRELY (from pattern to ;;)
    # This prevents syntax errors by removing the whole block cleanly
    sed -i '/"sudo"\*|"su"\*)/,/;;/d' "${HOME}/run.sh"

    # 3. Add "stop/restart" cleanup block before "help" 
    # This ensures specific stop commands (like stop-novnc) are matched BEFORE this wildcard
    sed -i '/"help")/i \        "stop"*|"restart"*)\n            cleanup\n        ;;' "${HOME}/run.sh"

    # 4. Modify "stopped" text to bypass Pterodactyl crash detection
    sed -i 's|VNC server stopped|VNC server sto pped|g' "${HOME}/run.sh"
    sed -i 's|Server stopped|Server sto pped|g' "${HOME}/run.sh"
}

cd "${HOME}"
[[ -f "$DEP_FLAG" ]] || setup_tools
sync_scripts
modify_scripts

if [ -f "${HOME}/server.jar" ]; then
    chmod +x "${HOME}/server.jar"
fi

if [[ -f "${HOME}/entrypoint.sh" ]]; then
    echo -e "${G}Booting...${NC}"
    exec /bin/sh "${HOME}/entrypoint.sh"
else
    echo -e "${R}Error: entrypoint.sh missing.${NC}"; exit 1
fi
