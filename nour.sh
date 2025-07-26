#!/bin/bash
HOME=/home/container; DEBIAN_FRONTEND=noninteractive
R='\033[0;31m'; GR='\033[0;32m'; Y='\033[0;33m'; P='\033[0;35m'; NC='\033[0m' # Standard Colors
BR='\033[1;31m'; BGR='\033[1;32m'; BY='\033[1;33m' # Bold Colors

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_ALT="amd64";;
  aarch64) ARCH_ALT="arm64";;
  riscv64) ARCH_ALT="riscv64";;
  *) echo -e "${BR}Unsupported architecture: $ARCH${NC}" >&2; exit 1;;
esac
export PATH="${HOME}/.local/bin:${HOME}/usr/local/bin:${PATH}" # Ensure local binaries are in PATH

DEP_FLAG="${HOME}/.dependencies_installed_v2" # Changed flag name in case python3 was missed before
if [ ! -f "$DEP_FLAG" ]; then
  echo -e "${BY}First time setup: Installing base packages, Python, and PRoot...${NC}"
  mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin"
  # Added python3-minimal for systemctl.py
  apt_pkgs_to_download=(xz-utils bash curl ca-certificates iproute2 bzip2 sudo python3-minimal)
  echo -e "${Y}Downloading required .deb packages (including python3-minimal)...${NC}"
  if ! yum install "${apt_pkgs_to_download[@]}"; then
    echo -e "${BR}Failed to download .deb packages. Please check network and apt sources.${NC}"; exit 1;
  fi
  
  find "$PWD" -maxdepth 1 -name '*.deb' -type f -print0 | while IFS= read -r -d $'\0' deb_file; do
    echo -e "${GR}Unpacking $deb_file → ${HOME}/.local/${NC}" && dpkg -x "$deb_file" "${HOME}/.local/" && rm "$deb_file"
  done
  
  echo -e "${Y}Installing PRoot...${NC}"
  proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
  if ! (curl -Ls "$proot_url" -o "${HOME}/usr/local/bin/proot" && chmod +x "${HOME}/usr/local/bin/proot"); then
    echo -e "${BR}Failed to download or install PRoot.${NC}"; exit 1;
  fi
  echo -e "${BGR}PRoot installed successfully.${NC}"
  touch "$DEP_FLAG"
else
  echo -e "${GR}Base packages, Python, and PRoot already installed. Skipping dependency installation.${NC}"
fi

echo -e "${BY}Checking for script and tool updates...${NC}"
declare -A scripts_to_manage=(
  ["entrypoint.sh"]="https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/entrypoint.sh"
  ["helper.sh"]="https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/helper.sh"
  ["install.sh"]="https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/install.sh"
  ["run.sh"]="https://raw.githubusercontent.com/ysdragon/Pterodactyl-VPS-Egg/refs/heads/main/run.sh"
  ["usr/local/bin/systemctl"]="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
)
for dest_path_suffix in "${!scripts_to_manage[@]}"; do
  url="${scripts_to_manage[$dest_path_suffix]}"
  local_file="${HOME}/${dest_path_suffix}"
  temp_file="${local_file}.new"
  
  # Ensure target directory exists (e.g., for usr/local/bin/systemctl)
  mkdir -p "$(dirname "$local_file")"

  echo -n -e "${Y}Checking ${dest_path_suffix}... ${NC}"
  if curl -sSLf --connect-timeout 15 --retry 3 -o "$temp_file" "$url"; then
    if [ ! -f "$local_file" ] || ! cmp -s "$local_file" "$temp_file"; then
      if mv "$temp_file" "$local_file" && chmod +x "$local_file"; then
        echo -e "${BGR}Updated.${NC}"
      else
        echo -e "${BR}Update failed (mv/chmod error).${NC}"
        [ -f "$temp_file" ] && rm "$temp_file" # Clean up temp file if mv failed
      fi
    else
      rm "$temp_file" # No changes, remove temp file
      echo -e "${GR}Up to date.${NC}"
    fi
  else
    # Ensure temp file is removed if download failed or partially downloaded
    [ -f "$temp_file" ] && rm "$temp_file"
    echo -e "${BR}Download failed. Will try to use local version of ${dest_path_suffix} if available.${NC}"
  fi
done

ENTRYPOINT_SCRIPT="${HOME}/entrypoint.sh"
if [ -f "$ENTRYPOINT_SCRIPT" ]; then
  echo -e "${BGR}Executing ${ENTRYPOINT_SCRIPT##*/}...${NC}"
  cd "${HOME}" && chmod +x "$ENTRYPOINT_SCRIPT" && exec bash "./${ENTRYPOINT_SCRIPT##*/}" || exit 1
else
  echo -e "${BR}Error: ${ENTRYPOINT_SCRIPT} not found and could not be downloaded! Cannot proceed.${NC}"; exit 1
fi
