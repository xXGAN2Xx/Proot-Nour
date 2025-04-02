#!/bin/bash

# 1. Check for proot
if ! command -v proot &> /dev/null; then
  echo "proot is not installed. Attempting to download..."
  # Download proot statically compiled. You may need to change the download link, if this one is broken.
  wget https://github.com/proot-me/proot/releases/download/v5.1.1/proot-x86_64 -O proot
  chmod +x proot
  if [ $? -ne 0 ]; then
    echo "Failed to download proot. Please install it manually or find a working download link."
    exit 1
  fi
fi

# 2. Check for debootstrap or a rootfs
if ! command -v debootstrap &> /dev/null; then
  echo "debootstrap is not installed. Attempting to download ubuntu rootfs..."
  # Download a pre-built minimal Ubuntu rootfs.
  wget https://cloud-images.ubuntu.com/minimal/daily/current/focal-minimal-cloudimg-amd64-rootfs.tar.xz -O ubuntu_rootfs.tar.xz
  if [ $? -ne 0 ]; then
    echo "Failed to download ubuntu rootfs. Please install debootstrap manually or find a working download link for a rootfs."
    exit 1
  fi
  mkdir ubuntu_rootfs
  tar -xvf ubuntu_rootfs.tar.xz -C ubuntu_rootfs
else
  echo "debootstrap found, creating minimal ubuntu rootfs"
  mkdir ubuntu_rootfs
  debootstrap focal ubuntu_rootfs
fi

# 3. Run proot with the Ubuntu rootfs
./proot -q qemu-x86_64 -b /dev -b /proc -b /sys -w /root -r ubuntu_rootfs /bin/bash

echo "Exiting proot."
