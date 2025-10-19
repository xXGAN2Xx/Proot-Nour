#!/bin/bash
echo "Installation complete! For help, type 'help'"
LANG=en_US.UTF-8
export PUBLIC_IP=$(curl -s ifconfig.me)
HOME="${HOME:-$(pwd)}"
export DEBIAN_FRONTEND=noninteractive

R='\033[0;31m'
GR='\033[0;32m'
Y='\033[0;33m'
P='\033[0;35m'
NC='\033[0m'

BR='\033[1;31m'
BGR='\033[1;32m'
BY='\033[1;33m'

DEP_FLAG="${HOME}/.dependencies_installed_v2"

export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"

error_exit() {
    echo -e "${BR}${1}${NC}" >&2
    exit 1
}

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
}

install_dependencies() {
    echo -e "${BY}First time setup: Installing base packages, Bash, Python, and PRoot...${NC}"

    mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin" || error_exit "Failed to create required directories."

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    if [ "$pkg_manager" = "apt" ]; then
        local apt_dir="${HOME}/.local/apt"
        local dpkg_status_file="${apt_dir}/dpkg/status"
        
        mkdir -p "${apt_dir}/lists/partial" "${apt_dir}/archives/partial" "${apt_dir}/dpkg/updates"
        
        touch "$dpkg_status_file"

        local apt_opts=(
            "-o" "Dir::State=${apt_dir}"
            "-o" "Dir::State::status=${dpkg_status_file}"
            "-o" "Dir::Cache=${apt_dir}"
            "-o" "Dir::Etc::sourcelist=/etc/apt/sources.list"
            "-o" "Dir::Etc::sourceparts=/etc/apt/sources.list.d"
            "-o" "APT::Update::Post-Invoke-Success=" 
            "-o" "APT::Update::Post-Invoke="
        )

        echo -e "${Y}Updating apt package lists locally...${NC}"
        if ! apt-get "${apt_opts[@]}" update; then
            error_exit "Local apt update failed. This is a critical step, cannot proceed."
        fi

        local apt_pkgs_to_download=(bash curl ca-certificates iproute2 xz-utils jq)
        echo -e "${Y}Downloading required .deb packages...${NC}"
        apt-get "${apt_opts[@]}" download "${apt_pkgs_to_download[@]}" || error_exit "Failed to download .deb packages. Please check network and apt sources."

        shopt -s nullglob
        local deb_files=("$PWD"/*.deb)
        [[ ${#deb_files[@]} -eq 0 ]] && error_exit "No .deb files found to extract."

        for deb_file in "${deb_files[@]}"; do
            echo -e "${GR}Unpacking $(basename "$deb_file") → ${HOME}/.local/${NC}"
            dpkg -x "$deb_file" "${HOME}/.local/" || error_exit "Failed to extract $deb_file"
            rm "$deb_file"
        done

        if ! command -v xz >/dev/null; then
            echo -e "${Y}Warning: xz not found in PATH after package extraction.${NC}" >&2
        else
            echo -e "${BGR}Local xz is available at: $(command -v xz)${NC}"
        fi
    else
        echo -e "${Y}Skipping apt package download on a non-Debian based system (${pkg_manager}).${NC}"
    fi

    echo -e "${Y}Installing PRoot...${NC}"
    local proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    local proot_dest="${HOME}/usr/local/bin/proot"
    curl -Ls "$proot_url" -o "$proot_dest" || error_exit "Failed to download PRoot."
    chmod +x "$proot_dest" || error_exit "Failed to make PRoot executable."

    echo -e "${BGR}PRoot installed successfully.${NC}"
    touch "$DEP_FLAG"
}

update_scripts() {
    echo -e "${BY}Checking for script and tool updates...${NC}"

    declare -A scripts_to_manage=(
        ["common.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/common.sh"
        ["entrypoint.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/entrypoint.sh"
        ["helper.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/helper.sh"
        ["install.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/install.sh"
        ["run.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/run.sh"
        ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py"
        ["autorun.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
    )

    local pids=()
    for dest_path_suffix in "${!scripts_to_manage[@]}"; do
        (
            local url="${scripts_to_manage[$dest_path_suffix]}"
            local local_file="${HOME}/${dest_path_suffix}"
            local temp_file="${local_file}.new"
            
            mkdir -p "$(dirname "$local_file")"

            echo -e "${Y}Checking ${dest_path_suffix}...${NC}"
            if curl -sSLf --connect-timeout 15 --retry 3 -o "$temp_file" "$url"; then
                if [[ ! -f "$local_file" ]] || ! cmp -s "$local_file" "$temp_file"; then
                    if mv "$temp_file" "$local_file" && chmod +x "$local_file"; then
                        echo -e "${BGR}Updated ${dest_path_suffix}.${NC}"
                    else
                        echo -e "${BR}Update failed for ${dest_path_suffix} (mv/chmod error).${NC}" >&2
                        rm -f "$temp_file"
                    fi
                else
                    rm "$temp_file"
                    echo -e "${GR}${dest_path_suffix} is up to date.${NC}"
                fi
            else
                rm -f "$temp_file"
                echo -e "${BR}Download failed for ${dest_path_suffix}. Using local version if available.${NC}" >&2
            fi
        ) &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    echo -e "${BGR}Script update check complete.${NC}"
}

cd "${HOME}"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_ALT="amd64";;
  aarch64) ARCH_ALT="arm64";;
  riscv64) ARCH_ALT="riscv64";;
  *) error_exit "Unsupported architecture: $ARCH";;
esac

if [[ ! -f /etc/debian_version ]]; then
    cat /etc/*-release
    echo -e "${Y}This is not a Debian-based system. apt commands will be skipped.${NC}"
else
    echo -e "${GR}This is a Debian-based system. Continuing...${NC}"
fi

if [[ ! -f "$DEP_FLAG" ]]; then
    install_dependencies
else
    echo -e "${GR}Base packages, Python, and PRoot are already installed. Skipping dependency installation.${NC}"
fi

update_scripts

ENTRYPOINT_SCRIPT="${HOME}/entrypoint.sh"
if [[ -f "$ENTRYPOINT_SCRIPT" ]]; then
    echo -e "${BGR}Executing ${ENTRYPOINT_SCRIPT##*/}...${NC}"
    
    if command -v xz >/dev/null; then
        echo -e "${GR}Using xz from: $(command -v xz)${NC}"
    else
        echo -e "${Y}Warning: xz not found in PATH${NC}"
    fi
    
    chmod +x "$ENTRYPOINT_SCRIPT"
    exec sh "./${ENTRYPOINT_SCRIPT##*/}"
else
    error_exit "Error: ${ENTRYPOINT_SCRIPT} not found and could not be downloaded! Cannot proceed."
fi
