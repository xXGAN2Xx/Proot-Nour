#!/bin/sh

ROOTFS_DIR=/home/container
export PUBLIC_IP=$(curl -s ifconfig.me)

download_file() {
    local url="$1"
    local dest="$2"
    echo "INFO: Downloading $url to $dest..."
    if command -v wget >/dev/null 2>&1; then
        wget --tries=5 --timeout=20 -qO "$dest" "$url"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 5 --connect-timeout 20 -o "$dest" "$url"
    else
        echo "ERROR: Neither wget nor curl is available. Cannot download required files."
        exit 1
    fi

    if [ $? -ne 0 ]; then
        echo "ERROR: Download failed for $url."
        exit 1
    fi
}

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        echo "INFO: Detected x86_64 (64-bit) architecture."
        ;;
    aarch64)
        echo "INFO: Detected aarch64 (64-bit) architecture."
        ;;
    arm | armv7l | armv8l)
        ARCH="arm"
        echo "INFO: Detected arm (32-bit) architecture."
        ;;
    i686 | i386)
        ARCH="i686"
        echo "INFO: Detected i686 (32-bit) architecture."
        ;;
    *)
        printf "Unsupported CPU architecture: %s\n" "$ARCH"
        exit 1
        ;;
esac

if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    echo "#######################################################################################"
    echo "#"
    echo "#                                  Nour PteroVM"
    echo "#"
    echo "#######################################################################################"
    echo ""
    echo "INFO: Auto-selecting Debian (no user input required)..."

    ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v4.26.0/debian-trixie-${ARCH}-pd-v4.26.0.tar.xz"
    download_file "$ROOTFS_URL" "/tmp/rootfs.tar.xz"

    echo "INFO: Extracting rootfs..."
    tar -xJf /tmp/rootfs.tar.xz -C "$ROOTFS_DIR" --strip-components=1
fi

if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    mkdir -p "$ROOTFS_DIR/usr/local/bin"
    echo "INFO: Downloading proot static binary..."
    proot_path="$ROOTFS_DIR/usr/local/bin/proot"
    proot_url="https://github.com/ysdragon/proot-static/releases/latest/download/proot-${ARCH}-static"

    download_file "$proot_url" "$proot_path"
    chmod +x "$proot_path"
fi

if [ ! -e "$ROOTFS_DIR/.installed" ]; then
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > "${ROOTFS_DIR}/etc/resolv.conf"
    rm -rf /tmp/*
    touch "$ROOTFS_DIR/.installed"
fi

SYSTEMCTL_PY_URL="https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py"
SYSTEMCTL_PY_INSTALL_DIR="$ROOTFS_DIR/usr/local/bin"
SYSTEMCTL_PY_INSTALL_PATH="$SYSTEMCTL_PY_INSTALL_DIR/systemctl"
SYSTEMCTL_PY_TEMP_PATH="/tmp/systemctl.py"

echo "INFO: Checking for systemctl.py..."
mkdir -p "$SYSTEMCTL_PY_INSTALL_DIR"

download_file "$SYSTEMCTL_PY_URL" "$SYSTEMCTL_PY_TEMP_PATH"

if [ -s "$SYSTEMCTL_PY_TEMP_PATH" ]; then
    LATEST_VERSION=$(grep "__version__ =" "$SYSTEMCTL_PY_TEMP_PATH" | head -n1 | cut -d'"' -f2)

    if [ -n "$LATEST_VERSION" ]; then
        if [ ! -f "$SYSTEMCTL_PY_INSTALL_PATH" ] || ! grep -q "$LATEST_VERSION" "$SYSTEMCTL_PY_INSTALL_PATH"; then
            echo "INFO: Installing/updating systemctl.py to version $LATEST_VERSION"
            mv "$SYSTEMCTL_PY_TEMP_PATH" "$SYSTEMCTL_PY_INSTALL_PATH"
            chmod 755 "$SYSTEMCTL_PY_INSTALL_PATH"
        else
            echo "INFO: systemctl.py is already up to date."
            rm "$SYSTEMCTL_PY_TEMP_PATH"
        fi
    else
        echo "WARN: Could not determine latest version of systemctl.py."
        rm "$SYSTEMCTL_PY_TEMP_PATH"
    fi
else
    echo "WARN: Could not download systemctl.py to check for updates."
fi
echo ""

GREEN='\e[0;32m'; RED='\e[0;31m'; YELLOW='\e[0;33m'; MAGENTA='\e[0;35m'; RESET='\e[0m'

display_header() {
    cat << EOF
${MAGENTA} __      __        ______
 \\ \\    / /       |  ____|
  \\ \\  / / __  ___| |__ _ __ ___  ___
   \\ \\/ / '_ \\/ __|  __| '__/ _ \\/ _ \\
    \\  /| |_) \\__ \\ |  | | |  __/  __/
     \\/ | .__/|___/_|  |_|  \\___\\___|
        | |
        |_|${RESET}
___________________________________________________
           ${YELLOW}-----> System Resources <----${RESET}
Installation complete! For help, type 'help'
EOF
}

display_resources() {
    local os_pretty_name="N/A"
    [ -f "$ROOTFS_DIR/etc/os-release" ] && os_pretty_name=$(grep "PRETTY_NAME" "$ROOTFS_DIR/etc/os-release" | cut -d'"' -f2)
    local cpu_model="N/A"
    [ -f "/proc/cpuinfo" ] && cpu_model=$(grep 'model name' /proc/cpuinfo | head -n 1 | cut -d':' -f2-)
    echo -e " INSTALLED OS -> ${RED}${os_pretty_name}${RESET}"
    echo -e " CPU -> ${YELLOW}${cpu_model}${RESET}"
    echo -e " RAM -> ${GREEN}${SERVER_MEMORY:-N/A}MB${RESET}"
    echo -e " PRIMARY PORT -> ${GREEN}${SERVER_PORT}${RESET}"
    echo -e " PRIMARY IP   -> ${GREEN}${PUBLIC_IP}${RESET}"
}

display_footer() {
    echo -e "___________________________________________________${RESET}"
    echo -e "           ${YELLOW}-----> VPS HAS STARTED <----${RESET}"
}

display_header
display_resources
display_footer

echo "INFO: Creating sing-box startup script..."
cat << EOF > "${ROOTFS_DIR}/root/startup.sh"
#!/bin/bash

echo "--- [Sing-Box Startup Script Inside PRoot] ---"

echo "Updating package lists and installing dependencies ..."
# Ensure python3 is installed for the systemctl replacement, even though we bypass it for starting
apt-get update > /dev/null 2>&1
apt-get install -y curl openssl tmate screen python3 > /dev/null 2>&1

if ! command -v sing-box &> /dev/null; then
    echo "Installing sing-box for the first time..."
    # The installer will likely try to interact with systemd and fail, which is okay.
    # We only need it to place the binary in /usr/local/bin/
    curl -fsSL https://sing-box.app/install.sh | sh
else
    echo "sing-box is already installed."
fi

SERVER_PORT=${SERVER_PORT}
echo "sing-box will use port: $SERVER_PORT"

mkdir -p /etc/sing-box

echo "Creating/Updating sing-box configuration file..."
cat << EOT > /etc/sing-box/config.json
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": \${SERVER_PORT},
      "tcp_fast_open": true,
      "users": [
        {
          "name": "nour",
          "uuid": "bf000d23-0752-40b4-affe-68f7707a9661"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/key.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ],
  "route": {}
}
EOT

if [ ! -f /etc/sing-box/cert.pem ] || [ ! -f /etc/sing-box/key.pem ]; then
    echo "Generating new self-signed TLS certificate..."
    openssl req -x509 -newkey rsa:4096 -keyout /etc/sing-box/key.pem \
    -out /etc/sing-box/cert.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=FakeOrg/OU=FakeUnit/CN=fake.local" \
    -addext "subjectAltName=DNS:playstation.net,DNS:localhost,IP:127.0.0.1"
else
    echo "Certificate and key already exist."
fi

echo "--- Starting sing-box service... ---"
echo "vless://bf000d23-0752-40b4-affe-68f7707a9661@${PUBLIC_IP}:${SERVER_PORT}?encryption=none&security=tls&sni=playstation.net&alpn=h3&allowInsecure=1&type=tcp&headerType=none#nour-vless"

/usr/local/bin/sing-box run -c /etc/sing-box/config.json &

echo "sing-box started in the background."

EOF

chmod +x "${ROOTFS_DIR}/root/startup.sh"
"$ROOTFS_DIR/usr/local/bin/proot" --rootfs="${ROOTFS_DIR}" -0 -n -w "/root" \
    -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
    /bin/bash -lc 'export DEBIAN_FRONTEND=noninteractive; \
    sh startup.sh && exec tmate -F'
