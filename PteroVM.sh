#!/bin/sh

# Use current directory as base, which should be writable
ROOTFS_DIR="./vpsroot"

# Define color variables
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
BLUE='\e[0;34m'
MAGENTA='\e[0;35m'
CYAN='\e[0;36m'
RESET_COLOR='\e[0m'

# Detect the machine architecture
ARCH=$(uname -m)

echo -e "${BLUE}Starting installation with architecture: ${ARCH}${RESET_COLOR}"
echo -e "${YELLOW}Using $ROOTFS_DIR as installation directory${RESET_COLOR}"

# Try to create the directory
mkdir -p "$ROOTFS_DIR" 2>/dev/null || {
  echo -e "${RED}Cannot create directory $ROOTFS_DIR${RESET_COLOR}"
  echo -e "${YELLOW}Trying alternate locations...${RESET_COLOR}"
  
  # Try alternate locations if first one fails
  for alt_dir in "./rootfs" "/tmp/rootfs" "$HOME/rootfs" "$PWD/rootfs"; do
    echo -e "${YELLOW}Trying $alt_dir...${RESET_COLOR}"
    if mkdir -p "$alt_dir" 2>/dev/null; then
      ROOTFS_DIR="$alt_dir"
      echo -e "${GREEN}Successfully created $ROOTFS_DIR${RESET_COLOR}"
      break
    fi
  done
}

# Check if we found a writable directory
if [ ! -d "$ROOTFS_DIR" ]; then
  echo -e "${RED}Failed to find a writable directory. Cannot continue.${RESET_COLOR}"
  echo -e "${YELLOW}Please provide a writable path manually:${RESET_COLOR}"
  read -p "Enter a writable path: " ROOTFS_DIR
  mkdir -p "$ROOTFS_DIR" 2>/dev/null || {
    echo -e "${RED}Still cannot create directory. Exiting.${RESET_COLOR}"
    exit 1
  }
fi

# Simple system info display
echo -e "${CYAN}System Information:${RESET_COLOR}"
echo -e "${MAGENTA}Architecture: ${YELLOW}$(uname -m)${RESET_COLOR}"
echo -e "${MAGENTA}Kernel: ${YELLOW}$(uname -r)${RESET_COLOR}"
echo -e "${MAGENTA}Installation directory: ${YELLOW}$ROOTFS_DIR${RESET_COLOR}"

# Check for working directory permissions
touch "$ROOTFS_DIR/test_file" 2>/dev/null && {
  echo -e "${GREEN}Write permissions confirmed in $ROOTFS_DIR${RESET_COLOR}"
  rm "$ROOTFS_DIR/test_file"
} || {
  echo -e "${RED}Cannot write to $ROOTFS_DIR${RESET_COLOR}"
  exit 1
}

# Function to download a small test file to check connectivity
test_download() {
  echo -e "${YELLOW}Testing download capability...${RESET_COLOR}"
  if command -v curl >/dev/null 2>&1; then
    curl -s -o "$ROOTFS_DIR/test_download" "https://raw.githubusercontent.com/proot-me/proot/master/README.md" && {
      echo -e "${GREEN}Download test successful using curl${RESET_COLOR}"
      rm "$ROOTFS_DIR/test_download"
      return 0
    }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$ROOTFS_DIR/test_download" "https://raw.githubusercontent.com/proot-me/proot/master/README.md" && {
      echo -e "${GREEN}Download test successful using wget${RESET_COLOR}"
      rm "$ROOTFS_DIR/test_download"
      return 0
    }
  else
    echo -e "${RED}Neither curl nor wget found. Cannot download files.${RESET_COLOR}"
    return 1
  fi
  
  echo -e "${RED}Download test failed. Check network connection.${RESET_COLOR}"
  return 1
}

# Test download capability
test_download || {
  echo -e "${RED}Failed to verify download capability. Installation may fail.${RESET_COLOR}"
  echo -e "${YELLOW}Press Enter to continue anyway or Ctrl+C to abort...${RESET_COLOR}"
  read dummy
}

echo -e "${GREEN}Script completed diagnostic phase.${RESET_COLOR}"
echo -e "${CYAN}To continue with installation, run the script again with the following path:${RESET_COLOR}"
echo -e "${YELLOW}ROOTFS_DIR=\"$ROOTFS_DIR\" ./your_script_name.sh${RESET_COLOR}"
