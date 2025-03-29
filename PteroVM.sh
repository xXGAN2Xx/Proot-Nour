#!/bin/bash

# Set variables
DEBIAN_VERSION="bullseye"
ARCH="amd64"
MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
ROOTFS_URL="https://mirrors.tuna.tsinghua.edu.cn/debian/dists/${DEBIAN_VERSION}/main/installer-${ARCH}/current/images/netboot/debian-installer/${ARCH}/initrd.gz"
DEBIAN_TARBALL="debian-rootfs.tar.gz"
DEBIAN_DIR="debian-fs"
PROOT_BIN="proot"

# Download and install proot if not present
if [ ! -f "./proot" ]; then
    echo "[*] Downloading proot..."
    wget https://github.com/proot-me/proot/releases/download/v5.3.0/proot-x86_64 -O proot
    chmod +x proot
fi

# Download Debian rootfs if not already downloaded
if [ ! -d "$DEBIAN_DIR" ]; then
    echo "[*] Downloading Debian rootfs..."
    wget ${MIRROR}/pool/main/d/debootstrap/debootstrap_1.0.123_all.deb -O debootstrap.deb
    mkdir -p "$DEBIAN_DIR"
    echo "[*] Extracting Debian rootfs..."
    wget "https://mirrors.tuna.tsinghua.edu.cn/lug/debian-rootfs/${DEBIAN_VERSION}-${ARCH}.tar.gz" -O "$DEBIAN_TARBALL"
    tar -xzf "$DEBIAN_TARBALL" -C "$DEBIAN_DIR"
fi

# Create launch script
cat > start-debian.sh <<- EOM
#!/bin/bash
cd \$(dirname \$0)
unset LD_PRELOAD
./proot -0 -r $DEBIAN_DIR -b /dev -b /proc -b /sys -b /etc/resolv.conf:/etc/resolv.conf -w /root /bin/bash --login
EOM

chmod +x start-debian.sh

echo "[*] Setup complete. Run ./start-debian.sh to enter Debian environment."
