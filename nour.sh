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

DEP_FLAG="${HOME}/.dependencies_installed"
if [ ! -f "$DEP_FLAG" ]; then
  echo -e "${BY}First time setup: Installing base packages and PRoot...${NC}"
  mkdir -p "${HOME}/.local/bin" "${HOME}/usr/local/bin"
  apt_pkgs_to_download=(xz-utils bash curl ca-certificates iproute2 bzip2 sudo)
  echo -e "${Y}Downloading required .deb packages...${NC}"
  apt download "${apt_pkgs_to_download[@]}" || { echo -e "${BR}Failed to download .deb packages.${NC}"; exit 1; }
  
  find "$PWD" -maxdepth 1 -name '*.deb' -type f -print0 | while IFS= read -r -d $'\0' deb_file; do
    echo -e "${GR}Unpacking $deb_file → ${HOME}/.local/${NC}" && dpkg -x "$deb_file" "${HOME}/.local/" && rm "$deb_file"
  done
  
  echo -e "${Y}Installing PRoot...${NC}"
  proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
  curl -Ls "$proot_url" -o "${HOME}/usr/local/bin/proot" && chmod +x "${HOME}/usr/local/bin/proot" && echo -e "${BGR}PRoot installed successfully.${NC}" || \
    { echo -e "${BR}Failed to download or install PRoot.${NC}"; exit 1; }
  touch "$DEP_FLAG"
else
  echo -e "${GR}Base packages and PRoot already installed. Skipping dependency installation.${NC}"
fi

echo -e "${BY}Checking for script updates...${NC}"
declare -A scripts_to_manage=(
  ["entrypoint.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/entrypoint.sh"
  ["helper.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/helper.sh"
  ["install.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/install.sh"
  ["run.sh"]="https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/run.sh"
)
for filename in "${!scripts_to_manage[@]}"; do
  url="${scripts_to_manage[$filename]}"; local_file="${HOME}/${filename}"; temp_file="${local_file}.new"
  echo -n -e "${Y}Checking ${filename}... ${NC}" # -n keeps cursor on same line
  if curl -sSLf --connect-timeout 10 --retry 3 -o "$temp_file" "$url"; then
    if [ ! -f "$local_file" ] || ! cmp -s "$local_file" "$temp_file"; then
      mv "$temp_file" "$local_file" && chmod +x "$local_file"
      echo -e "${BGR}Updated.${NC}"
    else
      rm "$temp_file"
      echo -e "${GR}Up to date.${NC}"
    fi
  else
    # Ensure temp file is removed if download failed or partially downloaded
    [ -f "$temp_file" ] && rm "$temp_file"
    echo -e "${BR}Download failed. Will try to use local version if available.${NC}"
  fi
done

ENTRYPOINT_SCRIPT="${HOME}/entrypoint.sh"
if [ -f "$ENTRYPOINT_SCRIPT" ]; then
  echo -e "${BGR}Executing ${ENTRYPOINT_SCRIPT##*/}...${NC}"
  cd "${HOME}" && chmod +x "$ENTRYPOINT_SCRIPT" && exec bash "./${ENTRYPOINT_SCRIPT##*/}" || exit 1
else
  echo -e "${BR}Error: ${ENTRYPOINT_SCRIPT} not found and could not be downloaded! Cannot proceed.${NC}"; exit 1
fi
