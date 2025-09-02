#!/bin/bash
# --- Installation and Setup Script ---
# This script is designed to automatically detect and work on Debian-based,
# RHEL-based (Amazon Linux), and Alpine Linux systems. It includes a
# robust fallback for non-root users on minimal RHEL-based systems.

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
export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/.local/sbin:${HOME}/.local/usr/sbin:${HOME}/usr/local/bin:${PATH}"

# --- Functions ---

# Function to print an error message and exit.
error_exit() {
    echo -e "\n${BR}${1}${NC}" >&2
    exit 1
}

# Function to install base dependencies if they are not present.
install_dependencies() {
    echo -e "${BY}First time setup: Installing base packages, Bash, Python, and PRoot...${NC}"

    mkdir -p "${HOME}/.local/bin" "${HOME}/.local/usr/bin" "${HOME}/usr/local/bin" || error_exit "Failed to create required directories."

    # --- Debian-based System Logic (apt) ---
    if [ "$PKG_MANAGER" = "apt" ]; then
        local apt_pkgs_to_download=(curl bash ca-certificates xz-utils python3-minimal)
        echo -e "${Y}Downloading required .deb packages...${NC}"
        apt download "${apt_pkgs_to_download[@]}" || error_exit "Failed to download .deb packages. Please check network and apt sources."

        shopt -s nullglob # Prevent errors if no .deb files match
        local deb_files=("$PWD"/*.deb)
        [[ ${#deb_files[@]} -eq 0 ]] && error_exit "No .deb files found to extract."

        for deb_file in "${deb_files[@]}"; do
            echo -e "${GR}Unpacking $(basename "$deb_file") → ${HOME}/.local/${NC}"
            dpkg -x "$deb_file" "${HOME}/.local/" || error_exit "Failed to extract $deb_file"
            rm "$deb_file"
        done

    # --- RHEL-based System Logic (yum) ---
    elif [ "$PKG_MANAGER" = "yum" ]; {
        # PREFERRED METHOD: Use yumdownloader if available
        if command -v yumdownloader >/dev/null; then
            local yum_pkgs_to_download=(curl bash ca-certificates xz python3)
            echo -e "${Y}Downloading required .rpm packages with yumdownloader...${NC}"
            yumdownloader "${yum_pkgs_to_download[@]}" || error_exit "Failed to download .rpm packages. Please check network and yum repositories."
            
            shopt -s nullglob
            local rpm_files=("$PWD"/*.rpm)
            [[ ${#rpm_files[@]} -eq 0 ]] && error_exit "No .rpm files found to extract."

            for rpm_file in "${rpm_files[@]}";
