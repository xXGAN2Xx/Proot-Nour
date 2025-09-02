#!/bin/bash
echo "Installation complete! For help, type 'help'"

# --- Constants and Configuration ---

# Set HOME if it's not already set.
HOME="${HOME:-$(pwd)}"
export DEBIAN_FRONTEND=noninteractive

# Standard Colors
R='\033[0;31m'
GR='\033[0;32m'
Y='\033[0;33m'
P='\033[0;35m'
NC='\033[0m'

# Bold Colors
BR='\033[1;31m'
BGR='\033[1;32m'
BY='\033[1;33m'

# Dependency flag path
DEP_FLAG="${HOME}/.dependencies_installed_v2"

# Ensure local binaries are prioritized in PATH.
# We set this once here, covering all potential locations.
export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"

# --- Functions ---

# Function to print an error message and exit.
error_exit() {
    echo -e "${BR}${1}${NC}" >&2
    exit 1
}

# Function to install base dependencies for Debian-based systems (apt).
install_dependencies_apt() {
    echo -e "${BY}First time setup for Debian: Installing base packages...${NC}"
    mkdir -p "${HOME}/.local" || error_exit "Failed to create required directories."

    local pkgs_to_download=(curl bash ca-certificates xz-utils python3-minimal)
    echo -e "${Y}Downloading required .deb packages...${NC}"
    apt-get download "${pkgs_to_download[@]}" || error_exit "Failed to download .deb packages. Please check network and apt sources."

    shopt -s nullglob
    for deb_file in ./*.deb; do
        echo -e "${GR}Unpacking $(basename "$deb_file") → ${HOME}/.local/${NC}"
        dpkg -x "$deb_file" "${HOME}/.local/" || error_exit "Failed to extract $deb_file"
        rm "$deb_file"
    done
}

# Function to install base dependencies for Alpine-based systems (apk).
install_dependencies_apk() {
    echo -e "${BY}First time setup for Alpine: Installing base packages...${NC}"
    mkdir -p "${HOME}/.local" || error_exit "Failed to create required directories."

    local pkgs_to_download=(curl bash ca-certificates xz python3)
    echo -e "${Y}Downloading required .apk packages...${NC}"
    apk fetch --force-non-root "${pkgs_to_download[@]}" || error_exit "Failed to download .apk packages."

    shopt -s nullglob
    for apk_file in ./*.apk; do
        echo -e "${GR}Unpacking $(basename "$apk_file") → ${HOME}/.local/${NC}"
        tar -xzf "$apk_file" -C "${HOME}/.local/" || error_exit "Failed to extract $apk_file"
        rm "$apk_file"
    done
}

# Bootstrap yum-utils if yumdownloader is not found.
bootstrap_yum_utils() {
    echo -e "${Y}yumdownloader not found. Attempting to bootstrap it...${NC}"
    
    command -v python3 >/dev/null || error_exit "Python3 is required to bootstrap yumdownloader, but it's not installed."
    command -v curl >/dev/null || error_exit "curl is required to bootstrap yumdownloader, but it's not installed."

    echo -e "${Y}Finding URL for yum-utils RPM...${NC}"
    # Use an embedded Python script to parse repo files and find the direct URL for yum-utils
    local yum_utils_url
    yum_utils_url=$(python3 <<'EOF'
import configparser
import gzip
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET

def find_repo_files():
    repo_paths = ['/etc/yum.repos.d', '/etc/yum/']
    for path in repo_paths:
        if os.path.isdir(path):
            return [os.path.join(path, f) for f in os.listdir(path) if f.endswith('.repo')]
    return []

def get_baseurl(repo_file):
    config = configparser.ConfigParser()
    config.read(repo_file)
    for section in config.sections():
        if config.getboolean(section, 'enabled', fallback=False):
            baseurl = config.get(section, 'baseurl', fallback=None)
            if baseurl:
                # Replace variables like $releasever, $basearch
                baseurl = re.sub(r'\$releasever', os.popen('rpm -E %{rhel}').read().strip(), baseurl)
                baseurl = re.sub(r'\$basearch', os.popen('uname -m').read().strip(), baseurl)
                return baseurl
    return None

def find_package_url(baseurl, package_name='yum-utils'):
    try:
        repomd_url = os.path.join(baseurl, 'repodata/repomd.xml')
        with urllib.request.urlopen(repomd_url, timeout=10) as response:
            repomd_xml = response.read()

        root = ET.fromstring(repomd_xml)
        ns = {'repo': 'http://linux.duke.edu/metadata/repo'}
        primary_location = root.find("repo:data[@type='primary']/repo:location", ns).get('href')
        
        primary_url = os.path.join(baseurl, primary_location)
        with urllib.request.urlopen(primary_url, timeout=30) as response:
            with gzip.GzipFile(fileobj=response) as decompressed:
                primary_xml = decompressed.read()

        primary_root = ET.fromstring(primary_xml)
        pkg_ns = {'common': 'http://linux.duke.edu/metadata/common'}
        package = primary_root.find(f"common:package[common:name='{package_name}']", pkg_ns)
        if package is not None:
            location = package.find('common:location', pkg_ns).get('href')
            return os.path.join(baseurl, location)
    except Exception:
        return None
    return None

repo_files = find_repo_files()
for repo in repo_files:
    url = get_baseurl(repo)
    if url:
        pkg_url = find_package_url(url)
        if pkg_url:
            print(pkg_url)
            sys.exit(0)
sys.exit(1)
EOF
)

    if [[ -z "$yum_utils_url" ]]; then
        error_exit "Failed to automatically find a download URL for the yum-utils package."
    fi

    echo -e "${GR}Found yum-utils URL: ${yum_utils_url}${NC}"
    local rpm_file="yum-utils-bootstrap.rpm"
    curl -Ls "$yum_utils_url" -o "$rpm_file" || error_exit "Failed to download yum-utils RPM."

    echo -e "${GR}Unpacking yum-utils → ${HOME}/.local/${NC}"
    (cd "${HOME}/.local" && rpm2cpio "../${rpm_file}" | cpio -idm --no-absolute-filenames) || error_exit "Failed to extract yum-utils RPM."
    rm "$rpm_file"

    # Verify that yumdownloader is now in the path
    if ! command -v yumdownloader >/dev/null; then
        error_exit "Successfully extracted yum-utils, but yumdownloader is still not in the PATH. Please check for installation errors."
    fi
    echo -e "${BGR}yumdownloader has been successfully bootstrapped.${NC}"
}


# Function to install base dependencies for Red Hat-based systems (yum).
install_dependencies_yum() {
    echo -e "${BY}First time setup for Red Hat family: Installing base packages...${NC}"
    mkdir -p "${HOME}/.local" || error_exit "Failed to create required directories."

    # Check for required tools, and bootstrap yumdownloader if it's missing
    for tool in rpm2cpio cpio; do
        command -v "$tool" >/dev/null || error_exit "$tool is not installed. Cannot proceed."
    done
    if ! command -v yumdownloader >/dev/null; then
        bootstrap_yum_utils
    fi

    local pkgs_to_download=(curl bash ca-certificates xz python3)
    echo -e "${Y}Downloading required .rpm packages...${NC}"
    yumdownloader --destdir=. "${pkgs_to_download[@]}" || error_exit "Failed to download .rpm packages."

    shopt -s nullglob
    for rpm_file in ./*.rpm; do
        echo -e "${GR}Unpacking $(basename "$rpm_file") → ${HOME}/.local/${NC}"
        (cd "${HOME}/.local" && rpm2cpio "../${rpm_file}" | cpio -idm --no-absolute-filenames) || error_exit "Failed to extract $rpm_file"
        rm "$rpm_file"
    done
}


# Function to install base dependencies if they are not present.
install_dependencies() {
    echo -e "${BY}First time setup: Installing base packages, Bash, Python, and PRoot...${NC}"
    
    mkdir -p "${HOME}/usr/local/bin" || error_exit "Failed to create required directories."

    case "$PKG_MANAGER" in
        apt) install_dependencies_apt ;;
        apk) install_dependencies_apk ;;
        yum) install_dependencies_yum ;;
        *) error_exit "Internal error: No installer for PKG_MANAGER='$PKG_MANAGER'" ;;
    esac

    # Verify that our local xz is now available
    if ! command -v xz >/dev/null; then
        echo -e "${Y}Warning: xz not found in PATH after package extraction.${NC}" >&2
    else
        echo -e "${BGR}Local xz is available at: $(command -v xz)${NC}"
    fi

    # Install PRoot
    echo -e "${Y}Installing PRoot...${NC}"
    local proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    local proot_dest="${HOME}/usr/local/bin/proot"
    curl -Ls "$proot_url" -o "$proot_dest" || error_exit "Failed to download PRoot."
    chmod +x "$proot_dest" || error_exit "Failed to make PRoot executable."

    echo -e "${BGR}PRoot installed successfully.${NC}"
    touch "$DEP_FLAG"
}

# Function to update scripts and tools from remote sources.
update_scripts() {
    echo -e "${BY}Checking for script and tool updates...${NC}"

    declare -A scripts_to_manage=(
        ["common.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/common.sh"
        ["entrypoint.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/entrypoint.sh"
        ["helper.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/helper.sh"
        ["install.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/install.sh"
        ["run.sh"]="https://github.com/xXGAN2Xx/Pterodactyl-VPS-Egg/raw/main/scripts/run.sh"
        ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
    )

    local pids=()
    for dest_path_suffix in "${!scripts_to_manage[@]}"; do
        # Run each download/update check in the background
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
        pids+=($!) # Store the process ID of the background job
    done

    # Wait for all background download jobs to finish
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    echo -e "${BGR}Script update check complete.${NC}"
}


# --- Main Execution ---

# Move to the HOME directory for predictable relative paths
cd "${HOME}"

# Architecture detection
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_ALT="amd64";;
  aarch64) ARCH_ALT="arm64";;
  riscv64) ARCH_ALT="riscv64";;
  *) error_exit "Unsupported architecture: $ARCH";;
esac

# --- OS/Package Manager Detection ---
# Source os-release to get distribution info, if it exists
if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
fi

if [ -f /etc/debian_version ]; then
    PKG_MANAGER="apt"
    echo -e "${GR}Debian-based system detected. Using apt.${NC}"
elif [ -f /etc/alpine-release ]; then
    PKG_MANAGER="apk"
    echo -e "${GR}Alpine-based system detected. Using apk.${NC}"
# Check for RHEL/CentOS/Fedora family, including Amazon Linux, by checking for specific files or os-release variables
elif [ -f /etc/redhat-release ] || [[ "${ID_LIKE}" == *"rhel"* ]] || [[ "${ID_LIKE}" == *"centos"* ]] || [[ "${ID}" == "amzn" ]]; then
    PKG_MANAGER="yum"
    echo -e "${GR}Red Hat-based system (like CentOS/RHEL/Amazon Linux) detected. Using yum.${NC}"
else
    cat /etc/*-release >&2
    error_exit "Unsupported Linux distribution."
fi


# Install dependencies if the flag file doesn't exist.
if [[ ! -f "$DEP_FLAG" ]]; then
    install_dependencies
else
    echo -e "${GR}Base packages, Python, and PRoot are already installed. Skipping dependency installation.${NC}"
fi

# Update all scripts.
update_scripts

# Execute entrypoint script
ENTRYPOINT_SCRIPT="${HOME}/entrypoint.sh"
if [[ -f "$ENTRYPOINT_SCRIPT" ]]; then
    echo -e "${BGR}Executing ${ENTRYPOINT_SCRIPT##*/}...${NC}"
    
    if command -v xz >/dev/null; then
        echo -e "${GR}Using xz from: $(command -v xz)${NC}"
    else
        echo -e "${Y}Warning: xz not found in PATH${NC}"
    fi
    
    chmod +x "$ENTRYPOINT_SCRIPT"
    # Use exec to replace the current shell process with the new one.
    exec bash "./${ENTRYPOINT_SCRIPT##*/}"
else
    error_exit "Error: ${ENTRYPOINT_SCRIPT} not found and could not be downloaded! Cannot proceed."
fi
