#!/bin/bash
echo "Installation complete! For help, type 'help'"

# --- Constants and Configuration ---
HOME="${HOME:-$(pwd)}"
export DEBIAN_FRONTEND=noninteractive

# Colors
R='\033[0;31m'; GR='\033[0;32m'; Y='\033[0;33m'; P='\033[0;35m'; NC='\033[0m'
BR='\033[1;31m'; BGR='\033[1;32m'; BY='\033[1;33m'

# Dependency flag path
DEP_FLAG="${HOME}/.dependencies_installed_v3"

# Ensure local binaries are prioritized
export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"

# --- Functions ---
error_exit() { echo -e "${BR}${1}${NC}" >&2; exit 1; }

# Generic extractor
extract_pkg() {
    local file="$1"
    case "$file" in
        *.deb) dpkg -x "$file" "${HOME}/.local/" ;;
        *.apk) tar -xzf "$file" -C "${HOME}/.local/" ;;
        *.rpm) rpm2cpio "$file" | cpio -idmv -D "${HOME}/.local/" ;;
        *) echo -e "${Y}Unknown package format: $file${NC}" ;;
    esac
    rm -f "$file"
}

install_dependencies() {
    echo -e "${BY}First time setup: Installing base packages (bash, python, proot)...${NC}"
    mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin"

    local pkgs=(curl bash ca-certificates xz-utils python3-minimal)

    if [[ -f /etc/debian_version ]]; then
        echo -e "${GR}Debian-based detected (apt).${NC}"
        apt download "${pkgs[@]}" || error_exit "apt download failed."
        for f in ./*.deb; do extract_pkg "$f"; done

    elif grep -qi "alpine" /etc/*-release; then
        echo -e "${GR}Alpine detected (apk).${NC}"
        for pkg in "${pkgs[@]}"; do
            apk fetch "$pkg" || error_exit "apk fetch $pkg failed."
        done
        for f in ./*.apk; do extract_pkg "$f"; done

    elif grep -qiE "centos|fedora|rhel" /etc/*-release; then
        echo -e "${GR}RHEL/Fedora detected (yum/dnf).${NC}"
        for pkg in "${pkgs[@]}"; do
            yumdownloader "$pkg" || dnf download "$pkg" || error_exit "yum/dnf failed for $pkg"
        done
        for f in ./*.rpm; do extract_pkg "$f"; done

    else
        cat /etc/*-release
        error_exit "Unsupported distro (not Debian/Alpine/RHEL)."
    fi

    # Verify xz
    if ! command -v xz >/dev/null; then
        echo -e "${Y}Warning: xz not found in PATH after extraction.${NC}"
    else
        echo -e "${BGR}xz available at: $(command -v xz)${NC}"
    fi

    # Install PRoot
    echo -e "${Y}Installing PRoot...${NC}"
    local ARCH=$(uname -m)
    case "$ARCH" in
      x86_64) ARCH_ALT="amd64";;
      aarch64) ARCH_ALT="arm64";;
      riscv64) ARCH_ALT="riscv64";;
      *) error_exit "Unsupported architecture: $ARCH";;
    esac
    local proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    local proot_dest="${HOME}/usr/local/bin/proot"
    curl -Ls "$proot_url" -o "$proot_dest" || error_exit "Failed to download PRoot."
    chmod +x "$proot_dest"

    echo -e "${BGR}Dependencies + PRoot installed successfully.${NC}"
    touch "$DEP_FLAG"
}

update_scripts() {
    echo -e "${BY}Checking for script updates...${NC}"
    declare -A scripts=(
        ["common.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/common.sh"
        ["entrypoint.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/entrypoint.sh"
        ["helper.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/helper.sh"
        ["install.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/install.sh"
        ["run.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/run.sh"
        ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
    )
    for dest in "${!scripts[@]}"; do
        local url="${scripts[$dest]}"
        local local_file="${HOME}/${dest}"
        mkdir -p "$(dirname "$local_file")"
        curl -sSLf -o "${local_file}.new" "$url" && mv "${local_file}.new" "$local_file" && chmod +x "$local_file"
    done
    echo -e "${BGR}Script update check complete.${NC}"
}

# --- Main Execution ---
cd "${HOME}"

if [[ ! -f "$DEP_FLAG" ]]; then
    install_dependencies
else
    echo -e "${GR}Dependencies already installed. Skipping.${NC}"
fi

update_scripts

ENTRYPOINT_SCRIPT="${HOME}/entrypoint.sh"
if [[ -f "$ENTRYPOINT_SCRIPT" ]]; then
    chmod +x "$ENTRYPOINT_SCRIPT"
    exec bash "./${ENTRYPOINT_SCRIPT##*/}"
else
    error_exit "entrypoint.sh missing!"
fi
