#!/bin/bash

# Debian in Pterodactyl using PRoot Installer
# Author: ChatGPT

set -e

# === CONFIGURATION ===
DEBIAN_VERSION="bookworm"  # You can change to bullseye or others
ARCH="amd64"
DEBIAN_TARBALL_URL="https://cdimage.debian.org/cdimage/release/current/${ARCH}/iso-cd/debian-${DEBIAN_VERSION}-amd64-netinst.iso"

# === Set working directories ===
WORK_DIR="$HOME/debian"
ROOTFS_DIR="${WORK_DIR}/rootfs"
PROOT_URL="https://github.com/proot-me/proot-static-build/releases/latest/download/proot-x86_64"

# === Create directories if not exist ===
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# === Download PRoot ===
if [ ! -f "proot" ]; then
    echo "Downloading PRoot..."
    wget -O proot "$PROOT_URL"
    chmod +x proot
else
    echo "PRoot already downloaded."
fi

# === Download Debian RootFS ===
if [ ! -d "$ROOTFS_DIR" ]; then
    echo "Downloading Debian root filesystem..."

    # Use prebuilt Debian rootfs from trusted source (like udroid or techroid mirror)
    ROOTFS_URL="https://raw.githubusercontent.com/EXALAB/AnLinux-Resources/master/Rootfs/Debian/${ARCH}/debian-rootfs.tar.gz"
    
    wget -O debian-rootfs.tar.gz "$ROOTFS_URL"
    mkdir -p "$ROOTFS_DIR"
    echo "Extracting Debian rootfs (this might take a while)..."
    tar -xzf debian-rootfs.tar.gz -C "$ROOTFS_DIR"
    rm debian-rootfs.tar.gz
else
    echo "Debian rootfs already exists."
fi

# === Create Launch Script ===
LAUNCHER="$WORK_DIR/start-debian.sh"

cat > "$LAUNCHER" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"

# Fix symlink problem in some containers
unset LD_PRELOAD

# Start Debian with PRoot
./proot \\
  -0 \\
  -r rootfs \\
  -b /dev \\
  -b /proc \\
  -b /sys \\
  -b /etc/resolv.conf \\
  -w /root \\
  /bin/bash --login
EOF

chmod +x "$LAUNCHER"

echo -e "\n✅ Installation complete."
echo "👉 To start Debian, run: $LAUNCHER"
