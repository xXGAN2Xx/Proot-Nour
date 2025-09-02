install_dependencies() {
    echo -e "${BY}First time setup: Installing base packages (bash, python, proot)...${NC}"
    mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin"

    local pkgs=(curl bash ca-certificates xz python3)

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
        echo -e "${GR}RHEL/Fedora detected (rpm).${NC}"
        local baseurl="https://mirrors.edge.kernel.org/fedora/releases/40/Everything/$(uname -m)/os/Packages"
        for pkg in "${pkgs[@]}"; do
            echo -e "${Y}Fetching $pkg...${NC}"
            # Try first letter directory (Fedora repo layout)
            firstchar=$(echo "$pkg" | cut -c1)
            url="$baseurl/${firstchar}/${pkg}-*.rpm"
            # Use curl with globbing
            curl -Ls --remote-name-all "$url" || error_exit "Failed to fetch $pkg"
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
