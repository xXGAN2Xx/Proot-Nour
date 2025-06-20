#!/bin/bash
# --- Configuration ---
HOME=/home/container
DEBIAN_FRONTEND=noninteractive
# --- Colors (Consolidated) ---
RED='\033[0;31m'; BOLD_RED='\033[1;31m'
GREEN='\033[0;32m'; BOLD_GREEN='\033[1;32m'
YELLOW='\033[0;33m'; BOLD_YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'
# --- Architecture Check ---
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_ALT="amd64" ;;
  aarch64) ARCH_ALT="arm64" ;;
  riscv64) ARCH_ALT="riscv64" ;;
  *)
    echo -e "${BOLD_RED}Unsupported CPU architecture: $ARCH${NC}" >&2
    exit 1
    ;;
esac

# --- Dependency Installation & Initial Setup ---
if [ ! -f "${HOME}/.installed" ]; then
  echo -e "${BOLD_YELLOW}First time setup: Installing pkgs...${NC}"
  apt update && apt download xz-utils bash curl ca-certificates iproute2 bzip2 sudo
  find "$HOME" -name '*.deb' -type f | while IFS= read -r deb; do
    echo "Unpacking $deb → ~/.local/"
    dpkg -x "$deb" ~/.local/
    echo "Removing $deb"
    rm -f "$deb"
  done

  # Install PRoot binary
  mkdir -p ${HOME}/usr/local/bin
  proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"
  echo -e "${BOLD_YELLOW}Downloading proot for $ARCH...${NC}"
  curl -Ls "$proot_url" -o ${HOME}/usr/local/bin/proot
  chmod +x ${HOME}/usr/local/bin/proot

  # Mark initial setup done
  touch "${HOME}/.installed"
fi

# --- Update helper scripts if changed ---
# URLs of scripts to fetch
urls=(
  "https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/entrypoint.sh"
  "https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/helper.sh"
  "https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/install.sh"
  "https://raw.githubusercontent.com/xXGAN2Xx/proot-me/refs/heads/main/run.sh"
)

echo -e "${BOLD_YELLOW}Checking for updates to helper scripts...${NC}"
for url in "${urls[@]}"; do
  filename="$(basename "$url")"
  localpath="${HOME}/$filename"

  if [ -f "$localpath" ]; then
    echo "- Checking $filename for updates..."
    if curl -z "$localpath" -sS -o "$localpath" "$url"; then
      echo -e "  ${GREEN}$filename updated.${NC}"
    else
      echo -e "  ${YELLOW}$filename already up to date.${NC}"
    fi
  else
    echo "- Downloading new script $filename..."
    curl -sS -o "$localpath" "$url" && echo -e "  ${GREEN}$filename downloaded.${NC}"
  fi
done

# --- Execute the entrypoint ---
bash "$HOME/entrypoint.sh"
