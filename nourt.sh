#!/bin/bash

# System Configuration
user_passwd="$(echo "$HOSTNAME" | sed 's+-.*++g')"
debug=false
proot="https://proot.gitlab.io/proot/bin/proot"
alpine_hostname="lemem"
# Auto-detect architecture
get_arch() {
  case "$(uname -m)" in
    x86_64) echo "x86_64" ;;
    aarch64) echo "aarch64" ;;
    *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac
}

# Get latest Alpine version for detected architecture
get_latest_alpine_version() {
  curl -s "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/$(get_arch)/" | \
    grep -oP 'alpine-minirootfs-\K[0-9]+\.[0-9]+\.[0-9]+(?=-'"$(get_arch)"')' | \
    sort -V | tail -n1
}

arch="$(get_arch)"
alpine_version="$(get_latest_alpine_version)"
mirror_alpine="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/$arch/alpine-minirootfs-$alpine_version-$arch.tar.gz"

# if on pterodactyl, set install path accordingly
if "$debug"; then 
  install_path="$HOME/alpine_subsystem"
elif [ -n "$SERVER_PORT" ]; then 
  install_path="$HOME/"
else
  install_path="./testing-arena"
fi

d.stat() { echo -ne "\033[1;37m==> \033[1;34m$@\033[0m\n"; }
die() {
  echo -ne "\n\033[41m               \033[1;37mA FATAL ERROR HAS OCCURED               \033[0m\n"
  sleep 5
  exit 1
}

# <dbgsym:bootstrap>
check_link="curl --output /dev/null --silent --head --fail"
bootstrap_system() {

  _CHECKPOINT=$PWD

  d.stat "Initializing the Alpine rootfs image..."
  curl -L "$mirror_alpine" -o a.tar.gz && tar -xf a.tar.gz || die
  rm -rf a.tar.gz

  d.stat "Downloading a Docker Daemon..."
  curl -L "$proot" -o alpine || die
  chmod +x alpine

  d.stat "Bootstrapping system..."
  touch etc/{passwd,shadow,groups}

  # coppy files
  cp /etc/resolv.conf "$install_path/etc/resolv.conf" -v
  cp /etc/hosts "$install_path/etc/hosts" -v
  cp /etc/localtime "$install_path/etc/localtime" -v
  cp /etc/passwd "$install_path"/etc/passwd -v
  cp /etc/group "$install_path"/etc/group -v
  cp /etc/nsswitch.conf "$install_path"/etc/nsswitch.conf -v
  mkdir -p "$install_path/home/container/shared"
  echo "$alpine_hostname" >"$install_path"/etc/hostname

  d.stat "Downloading will took 5-15 minutes.."
./alpine -r . -b /dev -b /sys -b /proc -b /tmp \
  --kill-on-exit -w /home/container /bin/sh -c "apk update && apk add bash xorg-server git virtiofsd python3 virtiofsd py3-pip py3-numpy \
    xinit xvfb fakeroot qemu qemu-img qemu-system-x86_64 \
  virtualgl mesa-dri-gallium \
  --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
  --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
  --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main; \
  git clone https://github.com/h3l2f/noVNC1 && \
  cd noVNC1 && \
  ln -s /usr/bin/fakeroot /usr/bin/sudo && \
  pip install websockify --break-system-packages && \
  wget -O  windows10.qcow2 https://cdn.bosd.io.vn/tiny10-x64.qcow2 && \
  wget https://cdn.bosd.io.vn/OVMF.fd && \
  echo 'change vnc password' > /home/container/qemu_cmd.txt && \
  echo '$user_passwd' > /home/container/vnc_raw_passwd.txt && \
  cat /home/container/vnc_raw_passwd.txt >> /home/container/qemu_cmd.txt" || die

cat >"$install_path/home/container/.bashrc" <<EOF
    echo " 🛑 wm shutdown or exiting error try exit or restart "

EOF

}
# </dbgsym:bootstrap>
DOCKER_RUN="env - \
  HOME=$install_path/home/container $install_path/alpine --kill-on-exit -r $install_path -b /dev -b /proc -b /sys -b /tmp \
  -b $install_path:$install_path -w $install_path/home/container /bin/bash -c"
run_system() {
  if [ -f $HOME/.do-not-start ]; then
    rm -rf $HOME/.do-not-start
    cp /etc/resolv.conf "$install_path/etc/resolv.conf" -v
    $DOCKER_RUN /bin/sh
    exit
  fi
  # Starting NoVNC
  d.stat "Starting noVNC server..."
  $install_path/alpine --kill-on-exit -r $install_path -b /dev -b /proc -b /sys -b /tmp -w "/home/container/noVNC1" /bin/sh -c "./utils/novnc_proxy --vnc localhost:5901 --listen 0.0.0.0:$SERVER_PORT" &>/dev/null &
  
  d.stat "Your server is now available at \033[1;32mhttp://$(curl --silent -L checkip.pterodactyl-installer.se):$SERVER_PORT"
  d.stat "your vnc password: $user_passwd nerver share it to anyone"
  # start qemu vm
  d.stat "starting windows 11..."
  d.stat "password: admin"
  $DOCKER_RUN "qemu-system-x86_64 -device qemu-xhci -device usb-tablet -device usb-kbd -cpu EPYC-Milan,+sse,+sse2,+sse4.1,+sse4.2,hv-relaxed -smp sockets=1,cores=$(nproc --all),threads=1 -overcommit mem-lock=off -m "$VM_MEMORY",slots=2 -drive file=fat:rw:/home/container/shared,format=raw,if=virtio,index=1 -drive file=windows10.qcow2,aio=native,cache.direct=on,if=virtio -device virtio-gpu-pci,xres=1366,yres=768 -device virtio-net-pci,netdev=n0 -netdev user,id=n0,hostfwd=tcp::"$OTHER_PORT"-:8080 -boot c -drive file=OVMF.fd,format=raw,readonly=on,if=pflash -device virtio-balloon-pci -device virtio-serial-pci -device virtio-rng-pci -display vnc=0.0.0.1:1,password -monitor stdio < qemu_cmd.txt"                         
  
  $DOCKER_RUN bash
}

cd "$install_path" || {
  mkdir -p "$install_path"
  cd "$install_path"
}

[ -d "bin" ] && run_system || bootstrap_system
