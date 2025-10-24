#!/bin/bash
# Non-interactive Ubuntu remote desktop installer for PRoot
# Supports XRDP or noVNC (choose one with MODE)
# Usage examples:
#   MODE=xrdp DESKTOP=xfce4 PORT=3389 bash install-remote.sh
#   MODE=novnc DESKTOP=lxde NOVNC_PORT=6080 bash install-remote.sh

set -e

# --- Configurable defaults ---
MODE="${MODE:-novnc}"              # xrdp | novnc
DESKTOP="${DESKTOP:-lxde}"       # lxde | lxqt | xfce4
PORT="${PORT:-$SERVER_PORT}"              # XRDP port
NOVNC_PORT="${NOVNC_PORT:-$SERVER_PORT}"  # noVNC web port

echo "======================================="
echo " Ubuntu Remote Desktop Installer (PRoot)"
echo " Mode: $MODE"
echo " Desktop: $DESKTOP"
[[ "$MODE" == "xrdp" ]] && echo " XRDP Port: $PORT"
[[ "$MODE" == "novnc" ]] && echo " noVNC Port: $NOVNC_PORT"
echo "======================================="

export DEBIAN_FRONTEND=noninteractive

# --- Update packages ---
apt update -y || apt-get update -y
apt install -y sudo curl git dbus-x11 xterm tigervnc-standalone-server

# --- Install desktop environment ---
case "$DESKTOP" in
  lxde)
    apt install -y lxde-core lxde-common
    SESSION_CMD="startlxde"
    ;;
  lxqt)
    apt install -y lxqt-core openbox
    SESSION_CMD="startlxqt"
    ;;
  xfce4)
    apt install -y xfce4 xfce4-goodies
    SESSION_CMD="startxfce4"
    ;;
  *)
    echo "Invalid desktop option: $DESKTOP"
    exit 1
    ;;
esac

# --- Configure user X session ---
mkdir -p ~/.xsession.d
cat > ~/.xsession <<EOF
#!/bin/bash
export DESKTOP_SESSION=$DESKTOP
export LANG=en_US.UTF-8
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
export DISPLAY=:10
if ! pgrep -x dbus-daemon >/dev/null; then
    dbus-daemon --system --fork
fi
$SESSION_CMD
EOF
chmod +x ~/.xsession

# --- Fix D-Bus path for PRoot ---
mkdir -p /var/run/dbus
dbus-daemon --system --fork || true

# --- XRDP mode ---
if [[ "$MODE" == "xrdp" ]]; then
    echo "[*] Installing XRDP..."
    apt install -y xrdp
    sed -i "s/^port=.*/port=$PORT/" /etc/xrdp/xrdp.ini || echo "port=$PORT" >> /etc/xrdp/xrdp.ini
    echo "[*] Starting XRDP..."
    pkill xrdp || true
    pkill xrdp-sesman || true
    /usr/sbin/xrdp-sesman &
    /usr/sbin/xrdp -nodaemon &
fi

# --- noVNC mode ---
if [[ "$MODE" == "novnc" ]]; then
    echo "[*] Installing noVNC..."
    if [ ! -d /opt/noVNC ]; then
        git clone https://github.com/novnc/noVNC.git /opt/noVNC
        git clone https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify
    fi

    echo "[*] Starting VNC server..."
    vncserver :10 -geometry 1280x720 -depth 24 || true

    echo "[*] Starting noVNC on port $NOVNC_PORT..."
    cd /opt/noVNC
    ./utils/novnc_proxy --vnc localhost:5910 --listen $NOVNC_PORT &
fi

# --- Add autostart to ~/.bashrc ---
if ! grep -q "xrdp" ~/.bashrc; then
    cat >> ~/.bashrc <<EOF

# Auto-start XRDP or noVNC
dbus-daemon --system --fork || true
if [[ "\$MODE" == "xrdp" ]]; then
    /usr/sbin/xrdp-sesman &
    /usr/sbin/xrdp -nodaemon &
elif [[ "\$MODE" == "novnc" ]]; then
    vncserver :10 -geometry 1280x720 -depth 24 || true
    cd /opt/noVNC && ./utils/novnc_proxy --vnc localhost:5910 --listen $NOVNC_PORT &
fi
EOF
fi

echo
echo "======================================="
echo "✅ Installation Complete!"
echo " Mode: $MODE"
echo " Desktop: $DESKTOP"
[[ "$MODE" == "xrdp" ]] && echo " XRDP running on port: $PORT"
[[ "$MODE" == "novnc" ]] && echo " noVNC running at: http://localhost:$NOVNC_PORT"
echo "======================================="
