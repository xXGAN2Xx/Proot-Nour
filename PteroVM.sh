#!/bin/bash

#========================================
# Auto KVM Environment Setup + VM Creator
#========================================

set -e

# ------------ CONFIG ------------
VM_NAME="myvm-auto"
RAM_MB=2048
VCPUS=2
DISK_SIZE_GB=20
ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso"
ISO_DIR="/var/lib/libvirt/boot"
ISO_NAME="$(basename $ISO_URL)"
ISO_PATH="${ISO_DIR}/${ISO_NAME}"
DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
OS_VARIANT="ubuntu22.04"
NETWORK_BRIDGE="default"
# ------------ END CONFIG ------------

echo "[*] Updating and installing KVM and dependencies..."

sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager virtinst osinfo-bin

echo "[*] Enabling and starting libvirtd service..."
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

echo "[*] Adding user '${USER}' to libvirt and kvm groups..."
sudo usermod -aG libvirt "$USER"
sudo usermod -aG kvm "$USER"

echo "[*] Creating ISO directory if not exists..."
sudo mkdir -p "$ISO_DIR"

if [ ! -f "$ISO_PATH" ]; then
    echo "[*] Downloading ISO from $ISO_URL..."
    sudo wget -O "$ISO_PATH" "$ISO_URL"
else
    echo "[*] ISO already exists at $ISO_PATH"
fi

echo "[*] Creating VM disk image..."
sudo qemu-img create -f qcow2 "$DISK_PATH" "${DISK_SIZE_GB}G"

echo "[*] Starting VM installation..."

sudo virt-install \
  --name="${VM_NAME}" \
  --ram="${RAM_MB}" \
  --vcpus="${VCPUS}" \
  --os-variant="${OS_VARIANT}" \
  --hvm \
  --cdrom="${ISO_PATH}" \
  --network network="${NETWORK_BRIDGE}" \
  --graphics vnc \
  --disk path="${DISK_PATH}",format=qcow2 \
  --noautoconsole

echo ""
echo "[+] VM '${VM_NAME}' installation started."
echo "[!] You may need to log out and back in for group permissions to apply."
echo "[*] Connect using: sudo virt-viewer --connect qemu:///system ${VM_NAME}, or use VNC."
