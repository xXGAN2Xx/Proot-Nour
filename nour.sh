#!/bin/bash
# Shebang: Specifies that this script should be run with the Bash interpreter.

# --- Initial User Greeting and Environment Setup ---
echo "Installation complete! For help, type 'help'"

# Set a standard locale to prevent errors with commands that are sensitive to language settings.
LANG=en_US.UTF-8

# Fetch the public IP address of the server and export it so that other scripts
# called by this one can access it as an environment variable.
export PUBLIC_IP=$(curl -s ifconfig.me)

# Ensure the HOME variable is set. If it's not already defined in the environment,
# default it to the current working directory. This improves script portability.
HOME="${HOME:-$(pwd)}"

# Set the Debian frontend to non-interactive to prevent `apt` commands from
# hanging by asking the user for input during automated installations.
export DEBIAN_FRONTEND=noninteractive

# --- Color Codes for Formatted Output ---
# These variables define ANSI escape codes to add color to the script's output,
# making it easier to read and distinguish between informational messages,
# warnings, and errors.
R='\033[0;31m'   # Red
GR='\033[0;32m'  # Green
Y='\033[0;33m'   # Yellow
P='\033[0;35m'   # Purple
NC='\033[0m'     # No Color (resets to default)

BR='\033[1;31m'  # Bold Red
BGR='\033[1;32m' # Bold Green
BY='\033[1;33m'  # Bold Yellow

# --- Lock File and PATH Configuration ---
# This "flag file" is used to check if the initial, time-consuming dependency
# installation has already been completed. Its existence signals to skip that step.
DEP_FLAG="${HOME}/.dependencies_installed_v2"

# Prepend our custom, local bin directories to the system's PATH.
# This is crucial because it ensures that any tools we install locally (like bash,
# curl, proot) are found and used *before* any system-wide versions.
export PATH="${HOME}/.local/bin:${HOME}/.local/usr/bin:${HOME}/usr/local/bin:${PATH}"

# --- Helper Functions ---

# A standardized function to print an error message in bold red and exit the script.
# This ensures a consistent and clear way to handle fatal errors.
error_exit() {
    # >&2 redirects the output to standard error.
    echo -e "${BR}${1}${NC}" >&2
    exit 1
}

# Detects the system's package manager to determine the Linux distribution family.
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

# This function performs a rootless, local installation of essential packages.
# It downloads .deb files and manually extracts them into a local directory,
# avoiding the need for `sudo` and not affecting the host system.
install_dependencies() {
    echo -e "${BY}First time setup: Installing base packages, Bash, Python, and PRoot...${NC}"

    # Create the target directories for our local installation.
    mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin" || error_exit "Failed to create required directories."

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    # This special installation logic is designed for Debian-based systems.
    if [ "$pkg_manager" = "apt" ]; then
        # --- Local APT Cache and Database ---
        # Define a local directory to act as apt's cache and state directory.
        # This is the core trick that allows us to use apt-get without root.
        local apt_dir="${HOME}/.local/apt"
        local dpkg_status_file="${apt_dir}/dpkg/status"
        
        # Create the necessary directory structure that apt expects.
        mkdir -p "${apt_dir}/lists/partial" "${apt_dir}/archives/partial" "${apt_dir}/dpkg/updates"
        touch "$dpkg_status_file"

        # Define a set of options to force apt-get to use our local directories
        # instead of the system-wide ones (like /var/lib/apt).
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
        apt-get "${apt_opts[@]}" update || error_exit "Local apt update failed. Cannot proceed."
        
        # --- Download and Extract Packages ---
        # Define the list of essential packages needed for the environment.
        local apt_pkgs_to_download=(bash curl ca-certificates iproute2 xz-utils shadow python3-minimal)
        echo -e "${Y}Downloading required .deb packages...${NC}"
        # Use `apt-get download` which only fetches the .deb files, it doesn't try to install them.
        apt-get "${apt_opts[@]}" download "${apt_pkgs_to_download[@]}" || error_exit "Failed to download .deb packages."

        # Use nullglob to prevent errors if no .deb files are found.
        shopt -s nullglob
        local deb_files=("$PWD"/*.deb)
        # Check if any .deb files were actually downloaded.
        [[ ${#deb_files[@]} -eq 0 ]] && error_exit "No .deb files found to extract."

        # Loop through each downloaded .deb file and manually extract it.
        for deb_file in "${deb_files[@]}"; do
            echo -e "${GR}Unpacking $(basename "$deb_file") → ${HOME}/.local/${NC}"
            # `dpkg -x` extracts the file contents to the specified directory.
            dpkg -x "$deb_file" "${HOME}/.local/" || error_exit "Failed to extract $deb_file"
            rm "$deb_file" # Clean up the downloaded archive.
        done

    else
        echo -e "${Y}Skipping apt package download on a non-Debian based system (${pkg_manager}).${NC}"
    fi

    # --- Install PRoot ---
    echo -e "${Y}Installing PRoot...${NC}"
    # Download a statically-compiled binary of PRoot. Static binaries are ideal
    # because they have no external dependencies and run on most systems.
    local proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
    local proot_dest="${HOME}/usr/local/bin/proot"
    curl -Ls "$proot_url" -o "$proot_dest" || error_exit "Failed to download PRoot."
    # Make the downloaded PRoot binary executable.
    chmod +x "$proot_dest" || error_exit "Failed to make PRoot executable."

    echo -e "${BGR}PRoot installed successfully.${NC}"
    # Create the flag file to indicate that this entire function has completed successfully.
    touch "$DEP_FLAG"
}

# This function checks for updates to all essential scripts and tools.
# It downloads them in parallel to speed up the process.
update_scripts() {
    echo -e "${BY}Checking for script and tool updates...${NC}"

    # Use an associative array to cleanly map destination file paths to their download URLs.
    declare -A scripts_to_manage=(
        ["common.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/common.sh"
        ["entrypoint.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/entrypoint.sh"
        ["helper.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/helper.sh"
        ["install.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/install.sh"
        ["run.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Pterodactyl-VPS-Egg-Nour/refs/heads/main/scripts/run.sh"
        ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/master/files/docker/systemctl3.py"
        ["autorun.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/autorun.sh"
        ["server.jar"]="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/server.jar"
    )

    local pids=()
    # Loop through each file defined in the array.
    for dest_path_suffix in "${!scripts_to_manage[@]}"; do
        # The `(...) &` syntax runs the entire block in a background subshell for parallel execution.
        (
            local url="${scripts_to_manage[$dest_path_suffix]}"
            local local_file="${HOME}/${dest_path_suffix}"
            local temp_file="${local_file}.new"
            
            mkdir -p "$(dirname "$local_file")"

            echo -e "${Y}Checking ${dest_path_suffix}...${NC}"
            # Download the new version to a temporary file. If curl fails, the block exits.
            if curl -sSLf --connect-timeout 15 --retry 3 -o "$temp_file" "$url"; then
                # Only update if the local file doesn't exist or if its content is different.
                # `cmp -s` is a silent, efficient way to compare two files.
                if [[ ! -f "$local_file" ]] || ! cmp -s "$local_file" "$temp_file"; then
                    # Atomically replace the old file with the new one and make it executable.
                    if mv "$temp_file" "$local_file" && chmod +x "$local_file"; then
                        echo -e "${BGR}Updated ${dest_path_suffix}.${NC}"
                    else
                        echo -e "${BR}Update failed for ${dest_path_suffix} (mv/chmod error).${NC}" >&2
                        rm -f "$temp_file"
                    fi
                else
                    # The files are the same, so just clean up the temporary file.
                    rm "$temp_file"
                    echo -e "${GR}${dest_path_suffix} is up to date.${NC}"
                fi
            else
                # Download failed, clean up and print a warning.
                rm -f "$temp_file"
                echo -e "${BR}Download failed for ${dest_path_suffix}. Using local version if available.${NC}" >&2
            fi
        ) &
        # Store the process ID (PID) of the background job.
        pids+=($!)
    done

    # Wait for all background download jobs to complete before continuing.
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    echo -e "${BGR}Script update check complete.${NC}"
}


# --- Main Script Execution ---

# Change to the HOME directory to ensure all relative paths are correct.
cd "${HOME}" || error_exit "Could not change to HOME directory: ${HOME}"

# Determine the system's architecture for downloading the correct binaries.
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_ALT="amd64";;
  aarch64) ARCH_ALT="arm64";;
  riscv64) ARCH_ALT="riscv64";;
  *) error_exit "Unsupported architecture: $ARCH";;
esac

# Check if this is a Debian-based system, as the local installer depends on it.
if [[ ! -f /etc/debian_version ]]; then
    cat /etc/*-release
    echo -e "${Y}This is not a Debian-based system. apt commands will be skipped.${NC}"
else
    echo -e "${GR}This is a Debian-based system. Continuing...${NC}"
fi

# Check if the dependency flag file exists. If not, run the one-time installation.
if [[ ! -f "$DEP_FLAG" ]]; then
    install_dependencies
else
    echo -e "${GR}Base packages, Python, and PRoot are already installed. Skipping dependency installation.${NC}"
fi

# Always check for script updates on every run.
update_scripts

# --- Execute the Entrypoint ---
ENTRYPOINT_SCRIPT="${HOME}/entrypoint.sh"
if [[ -f "$ENTRYPOINT_SCRIPT" ]]; then
    echo -e "${BGR}Executing ${ENTRYPOINT_SCRIPT##*/}...${NC}"
    chmod +x "$ENTRYPOINT_SCRIPT"
    # `exec` replaces the current shell process with the entrypoint script.
    # This is an efficient way to chain scripts without creating a nested process.
    exec sh "./${ENTRYPOINT_SCRIPT##*/}"
else
    error_exit "Error: ${ENTRYPOINT_SCRIPT} not found and could not be downloaded! Cannot proceed."
fi
