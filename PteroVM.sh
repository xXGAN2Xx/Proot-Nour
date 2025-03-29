#!/bin/bash

# Filename: install_debian.sh
# Purpose: Download and install Debian rootfs using proot in unprivileged environments (e.g., Pterodactyl panel)

set -e

# Config
ARCH=$(uname -m)
ROOTFS_URL=""
ROOTFS_TAR="debian-rootfs.tar.xz"
INSTALL_DIR="$HOME/debian-fs"
BIN_DIR="$HOME/bin"

# Ensure a bin directory is on PATH
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

# Select architecture
case "$ARCH" in
    x86_64)
        ROOTFS_URL="https://cdimage.debian.org/cdimage/archive/11.7.0/amd64/iso-cd/debian-11.7.0-amd64-netinst.iso"
        ;;
    aarch64 | arm64)
        ROOTFS_URL="https://raw.githubusercontent.com/AndronixApp/AndronixOrigin/master/Rootfs/arm64/debian-rootfs-arm64.tar.xz"
        ;;
    armv7l)
        ROOTFS_URL="https://raw.githubusercontent.com/AndronixApp/AndronixOrigin/master/Rootfs/armhf/debian-rootfs-armhf.tar.xz"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Download proot binary if not present
if ! command -v proot &>/dev/null; then
    echo "[+] Downloading proot..."
    PROOT_BIN="proot"
    wget https://github.com/proot-me/proot-static-build/releases/latest/download/proot-x86_64 -O "$BIN_DIR/$PROOT_BIN"
    chmod +x "$BIN_DIR/$PROOT_BIN"
fi

# Download rootfs
if [ ! -f "$ROOTFS_TAR" ]; then
    echo "[+] Downloading Debian rootfs..."
    wget "$ROOTFS_URL" -O "$ROOTFS_TAR"
fi

# Extract rootfs
if [ ! -d "$INSTALL_DIR" ]; then
    echo "[+] Extracting Debian filesystem..."
    mkdir -p "$INSTALL_DIR"
    tar -xJf "$ROOTFS_TAR" -C "$INSTALL_DIR"
fi

# Create launcher script
echo "[+] Creating launch script..."

cat > "$HOME/start-debian.sh" <<- EOM
#!/bin/bash
unset LD_PRELOAD
COMMAND="proot \\
    --link2symlink \\
    -0 \\
    -r $INSTALL_DIR \\
    -b /dev \\
    -b /proc \\
    -b /sys \\
    -b \$HOME \\
    -w /root \\
    /bin/bash --login"
exec \$COMMAND
EOM

chmod +x "$HOME/start-debian.sh"

echo ""
echo "✅ Debian rootfs installed successfully!"
echo "➡️  Run it using: ./start-debian.sh"
