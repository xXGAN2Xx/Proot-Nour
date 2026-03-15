#!/bin/bash

export LANG=en_US.UTF-8
export HOME="${HOME:-$(pwd)}"
export server_ip=$(wget -qO- checkip.pterodactyl-installer.se 2>/dev/null || curl -s checkip.pterodactyl-installer.se)

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; NC='\033[0m'

LOCAL_BIN="${HOME}/.local/bin"
PROOT_BIN="${HOME}/usr/local/bin/proot"
DEP_FLAG="${HOME}/.deps"
BASE_URL="https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/scripts"
CA_DIR="${HOME}/.local/etc/ssl/certs"
CA_BUNDLE="${CA_DIR}/ca-certificates.crt"

export PATH="${LOCAL_BIN}:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"
export SSL_CERT_FILE="$CA_BUNDLE"
export CURL_CA_BUNDLE="$CA_BUNDLE"
export WGET_CA_BUNDLE="$CA_BUNDLE"

mkdir -p "$LOCAL_BIN" "${HOME}/usr/local/bin"

# Unified download helper — removes duplicated wget/curl logic throughout
download() {
    local url="$1" dest="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$dest"
    elif command -v curl >/dev/null 2>&1; then
        curl -sSL "$url" -o "$dest"
    else
        echo -e "${R}Error: Neither wget nor curl available.${NC}" >&2
        exit 1
    fi
}

setup_tools() {
    echo -e "${B}Checking system architecture...${NC}"
    local arch bbox_url jq_url proot_arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            bbox_url="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
            jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64"
            proot_arch="x86_64"
            ;;
        aarch64)
            bbox_url="https://busybox.net/downloads/binaries/1.35.0-armv8l-linux-musl/busybox"
            jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-arm64"
            proot_arch="aarch64"
            ;;
        *)
            echo -e "${R}Unsupported architecture: $arch${NC}" >&2
            exit 1
            ;;
    esac

    echo -e "${Y}Installing BusyBox 1.35.0...${NC}"
    download "$bbox_url" "${LOCAL_BIN}/busybox"
    chmod +x "${LOCAL_BIN}/busybox"
    for tool in xz tar unxz gzip bzip2 bash ip wget; do
        ln -sf ./busybox "${LOCAL_BIN}/${tool}"
    done

    echo -e "${Y}Installing static jq...${NC}"
    download "$jq_url" "${LOCAL_BIN}/jq"
    chmod +x "${LOCAL_BIN}/jq"

    echo -e "${Y}Installing PRoot engine...${NC}"
    download "https://github.com/ysdragon/proot-static/releases/latest/download/proot-${proot_arch}-static" "$PROOT_BIN"
    chmod +x "$PROOT_BIN"

    echo -e "${Y}Installing CA certificates...${NC}"
    mkdir -p "$CA_DIR"
    download "https://curl.se/ca/cacert.pem" "$CA_BUNDLE"

    touch "$DEP_FLAG"
}

sync_scripts() {
    echo -e "${B}Synchronizing scripts...${NC}"

    # BASE_URL is now a global constant, no need to redeclare it here
    local -A scripts=(
        ["vnc_install.sh"]="$BASE_URL/vnc/install.sh"
        ["common.sh"]="$BASE_URL/common.sh"
        ["entrypoint.sh"]="$BASE_URL/entrypoint.sh"
        ["helper.sh"]="$BASE_URL/helper.sh"
        ["install.sh"]="$BASE_URL/install.sh"
        ["run.sh"]="$BASE_URL/run.sh"
        ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py"
        ["autorun.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
    )

    local dest
    for rel_path in "${!scripts[@]}"; do
        dest="${HOME}/${rel_path}"
        mkdir -p "$(dirname "$dest")"
        download "${scripts[$rel_path]}" "$dest"
        chmod +x "$dest"
    done
}

modify_scripts() {
    echo -e "${B}Applying patches...${NC}"

    # Group all sed expressions per file into a single call — fewer subprocesses
    sed -i \
        -e "s|/usr/local/bin/proot|\$HOME/usr/local/bin/proot|g" \
        -e 's|/bin/sh "/install.sh"|/bin/sh "$HOME/install.sh"|g' \
        -e 's|sh /helper.sh|sh $HOME/helper.sh|g' \
        "${HOME}/entrypoint.sh"

    sed -i \
        -e 's|cp /common.sh "\$HOME/common.sh"|cp /common.sh "/common.sh"|g' \
        -e 's|cp /run.sh "\$HOME/run.sh"|cp /run.sh "/run.sh"|g' \
        -e 's|config_file="\$HOME/vps.config"|config_file="/vps.config"|g' \
        -e "s|/usr/local/bin/proot|\$HOME/usr/local/bin/proot|g" \
        -e 's|-0 -w "\${HOME}"|-0 -w "/root"|g' \
        "${HOME}/helper.sh"

    sed -i \
        -e 's|\. /common.sh|. $HOME/common.sh|g' \
        -e '/export PATH=/a export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:~/.local/usr/lib:~/.local/usr/lib64"' \
        "${HOME}/install.sh"

    # Removed redundant [[ -f run.sh ]] guard — file was just downloaded
    sed -i \
        -e 's|HISTORY_FILE="\${HOME}/.custom_shell_history"|HISTORY_FILE="/.custom_shell_history"|g' \
        -e '/"sudo"\*|"su"\*)/,/;;/d' \
        -e '/"help")/i \        "stop"*|"restart"*)\n            cleanup\n        ;;' \
        -e 's|VNC server stopped|VNC server sto pped|g' \
        -e 's|Server stopped|Server sto pped|g' \
        -e "s|<server-ip>|\${server_ip}|g" \
        -e '/TUNNEL_LOG="\/tmp\/cloudflared.log"/a \    > "$TUNNEL_LOG"' \
        -e 's|cloudflared tunnel --url|cloudflared tunnel --protocol http2 --url|' \
        -e 's#sleep 5#PID=$!; i=0; while [ $i -lt 60 ]; do kill -0 $PID 2>/dev/null || break; if grep -q "https://.*trycloudflare.com" "$TUNNEL_LOG"; then break; fi; sleep 1; i=$((i+1)); done#' \
        -e '/Check $TUNNEL_LOG for the URL/a \        cat "$TUNNEL_LOG"' \
        "${HOME}/run.sh"

    sed -i "s|<server-ip>|\${server_ip}|g" "${HOME}/vnc_install.sh"
}

# ── Main ──────────────────────────────────────────────────────────────────────
cd "$HOME"
[[ -f "$DEP_FLAG" ]] || setup_tools
sync_scripts
modify_scripts

[[ -f "${HOME}/server.jar" ]] && chmod +x "${HOME}/server.jar"

if [[ -f "${HOME}/entrypoint.sh" ]]; then
    echo -e "${G}Booting...${NC}"
    exec /bin/sh "${HOME}/entrypoint.sh"
else
    echo -e "${R}Error: entrypoint.sh missing.${NC}" >&2
    exit 1
fi
