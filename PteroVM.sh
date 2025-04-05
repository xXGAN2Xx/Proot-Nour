#!/bin/sh
ROOTFS_DIR=/home/container
export PATH=$PATH:~/.local/usr/bin
ARCH=$(uname -m)
mkdir -p ${ROOTFS_DIR}/usr/local/bin
proot_url="https://github.com/ysdragon/proot-static/releases/download/v5.4.0/proot-${ARCH}-static"
curl -Ls "$proot_url" -o ${ROOTFS_DIR}/usr/local/bin/proot
chmod +x ${ROOTFS_DIR}/usr/local/bin/proot
exec ./entrypoint.sh
