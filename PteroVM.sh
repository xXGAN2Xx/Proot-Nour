#!/bin/bash

# Download a minimal Ubuntu root filesystem (e.g., from Ubuntu base)
wget http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.4-base-amd64.tar.gz

# Extract the root filesystem
tar -xzf ubuntu-base-22.04.4-base-amd64.tar.gz

# Create necessary directories
sudo mkdir -p ubuntu/dev ubuntu/proc ubuntu/sys ubuntu/run

# Mount necessary filesystems
sudo mount --bind /dev ubuntu/dev
sudo mount --bind /proc ubuntu/proc
sudo mount --bind /sys ubuntu/sys
sudo mount --bind /run ubuntu/run

# Chroot into the Ubuntu environment
sudo chroot ubuntu /bin/bash

# Inside the chroot, you can perform basic setup (e.g., install packages)
# Example: apt update && apt install -y vim

# To exit the chroot, type 'exit'

# Unmount the filesystems when done
sudo umount ubuntu/dev
sudo umount ubuntu/proc
sudo umount ubuntu/sys
sudo umount ubuntu/run
