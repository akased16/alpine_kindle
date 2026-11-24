#!/usr/bin/env bash

# DEPENDENCIES
# qemu-arm-static is required to run arm software.
# On Ubuntu 22.04 / Arch / Fedora: install qemu-user-static
# On Ubuntu 24.04+: qemu-user-static is a virtual package provided by
#   qemu-user-binfmt; the static binary lives at
#   /usr/libexec/qemu-binfmt/arm-binfmt-P and is auto-detected below.
# This script assumes you run it on an X86_64 host.

# BASIC CONFIGURATION
REPO="http://dl-cdn.alpinelinux.org/alpine"
MNT="/mnt/alpine"
IMAGE="./alpine.ext3"
IMAGESIZE=1024 #Megabytes (1G，无桌面后空间充裕)

ALPINESETUP="source /etc/profile
echo kindle > /etc/hostname
echo \"nameserver 8.8.8.8\" > /etc/resolv.conf
mkdir -p /run/dbus
apk update
apk upgrade
cat /etc/alpine-release

# --- X / input / 基础工具 ---
apk add xorg-server-xephyr xwininfo xdotool xinput dbus-x11 sudo bash nano git

# --- 最小窗口管理器 (Chromium 最大化 + onboard 浮动必需) ---
apk add jwm

# --- 字体 + locale (中文显示 + Latin UI) ---
apk add musl-locales font-droid-nonlatin font-dejavu
localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 2>/dev/null || true

# --- 中文输入法 (IBus + libpinyin, v3.20 community) ---
apk add ibus ibus-libpinyin ibus-gtk3 ibus-lang

# --- 虚拟键盘 + 浏览器 ---
apk add onboard chromium

adduser alpine -D
echo -e \"alpine\nalpine\" | passwd alpine
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers
addgroup sudo
addgroup alpine sudo

# --- 输入法环境变量 ---
cat > /etc/profile.d/ibus.sh <<'EOF'
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
EOF

# --- 为 alpine 用户写入极简 jwm 配置 ---
su alpine -c \"mkdir -p ~/.jwm
cat > ~/.jwmrc <<'JWMRC'
<JWM>
  <RootMenu onroot=\\\"3\\\">
    <Program label=\\\"Chromium\\\" icon=\\\"chromium\\\">chromium</Program>
    <Program label=\\\"Onboard\\\" icon=\\\"onboard\\\">onboard</Program>
    <Separator/>
    <Restart label=\\\"Restart JWM\\\" icon=\\\"restart\\\"/>
    <Exit label=\\\"Exit\\\" confirm=\\\"true\\\"/>
  </RootMenu>
  <Tray x=\\\"0\\\" y=\\\"-1\\\" height=\\\"28\\\">
    <TaskList maxwidth=\\\"800\\\"/>
    <Clock format=\\\"%H:%M\\\"/>
  </Tray>
</JWM>
JWMRC
cd ~
git init
git remote add origin https://github.com/schuhumi/alpine_kindle_dotfiles
git pull origin master
git reset --hard origin/master
dconf load /org/onboard/ < ~/.config/org_onboard.dconf.dump 2>/dev/null || true\"

echo '# Default settings for chromium. This file is sourced by /bin/sh from
# the chromium launcher.

# Options to pass to chromium.
mouseid=\"\$(env DISPLAY=:1 xinput list --id-only \"Xephyr virtual mouse\")\"
CHROMIUM_FLAGS='\''--force-device-scale-factor=2 --touch-devices='\''\$mouseid'\'' --pull-to-refresh=1 --disable-smooth-scrolling --enable-low-end-device-mode --disable-login-animations --disable-modal-animations --wm-window-animations-disabled --start-maximized --user-agent=Mozilla%2F5.0%20%28Linux%3B%20Android%2014%3B%20Pixel%208%29%20AppleWebKit%2F537.36%20%28KHTML%2C%20like%20Gecko%29%20Chrome%2F131.0.6778.108%20Mobile%20Safari%2F537.36'\''' > /etc/chromium/chromium.conf
mkdir -p /usr/share/chromium/extensions
# Install uBlock Origin
echo '{
	\"external_update_url\": \"https://clients2.google.com/service/update2/crx\"
}' > /usr/share/chromium/extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm.json

echo \"You're now dropped into an interactive shell in Alpine, feel free to explore and type exit to leave.\"
sh"


# ENSURE ROOT
[ "$(whoami)" != "root" ] && echo "This script needs to be run as root" && exec sudo -- "$0" "$@"


# ENSURE QEMU-ARM-STATIC (兼容 Ubuntu 24.04+)
# Ubuntu 24.04 把 qemu-user-static 改成虚拟包，由 qemu-user-binfmt 提供。
# qemu-user-binfmt 不提供 /usr/bin/qemu-arm-static，但附带静态二进制
# /usr/libexec/qemu-binfmt/arm-binfmt-P，功能等价，自动检测并复用。
QEMU_ARM_STATIC="$(command -v qemu-arm-static 2>/dev/null || true)"

if [ -z "$QEMU_ARM_STATIC" ] && [ -x /usr/libexec/qemu-binfmt/arm-binfmt-P ]; then
    QEMU_ARM_STATIC=/usr/libexec/qemu-binfmt/arm-binfmt-P
fi

if [ -z "$QEMU_ARM_STATIC" ]; then
    echo "qemu-arm-static not found, attempting to install..."
    if command -v apt-get &>/dev/null; then
        apt-get update
        # 优先尝试 qemu-user-static（Ubuntu 22.04 / Debian）
        # 失败则退回 qemu-user-binfmt（Ubuntu 24.04+）
        apt-get install -y qemu-user-static 2>/dev/null \
            || apt-get install -y qemu-user-binfmt 2>/dev/null \
            || apt-get install -y qemu-user
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm qemu-user-static-binfmt qemu-user-static 2>/dev/null \
            || pacman -S --noconfirm qemu-user-static
    elif command -v dnf &>/dev/null; then
        dnf install -y qemu-user-static
    fi

    QEMU_ARM_STATIC="$(command -v qemu-arm-static 2>/dev/null || true)"
    if [ -z "$QEMU_ARM_STATIC" ] && [ -x /usr/libexec/qemu-binfmt/arm-binfmt-P ]; then
        QEMU_ARM_STATIC=/usr/libexec/qemu-binfmt/arm-binfmt-P
    fi
fi

if [ -z "$QEMU_ARM_STATIC" ]; then
    echo "ERROR: qemu-arm-static not available."
    echo "On Ubuntu 24.04+: sudo apt install qemu-user-binfmt"
    echo "On Ubuntu 22.04 : sudo apt install qemu-user-static"
    exit 1
fi
echo "Using QEMU ARM static binary: $QEMU_ARM_STATIC"


# GETTING APK-TOOLS-STATIC (v3.20)
echo "Determining version of apk-tools-static"
curl "$REPO/v3.20/main/armhf/APKINDEX.tar.gz" --output /tmp/APKINDEX.tar.gz
tar -xzf /tmp/APKINDEX.tar.gz -C /tmp
APKVER="$(cut -d':' -f2 <<<"$(grep -A 5 "P:apk-tools-static" /tmp/APKINDEX | grep "V:")")"
rm /tmp/APKINDEX /tmp/APKINDEX.tar.gz /tmp/DESCRIPTION
echo "Version of apk-tools-static is: $APKVER"
echo "Downloading apk-tools-static"
curl "$REPO/v3.20/main/armv7/apk-tools-static-$APKVER.apk" --output "/tmp/apk-tools-static.apk"
tar -xzf "/tmp/apk-tools-static.apk" -C /tmp


# CREATING IMAGE FILE
echo "Creating image file"
dd if=/dev/zero of="$IMAGE" bs=1M count=$IMAGESIZE
mkfs.ext3 "$IMAGE"
tune2fs -i 0 -c 0 "$IMAGE"


# MOUNTING IMAGE
echo "Mounting image"
mkdir -p "$MNT"
mount -o loop -t ext3 "$IMAGE" "$MNT"


# BOOTSTRAPPING ALPINE (v3.20)
echo "Bootstrapping Alpine v3.20"
"$QEMU_ARM_STATIC" /tmp/sbin/apk.static -X "$REPO/v3.20/main" -U --allow-untrusted --root "$MNT" --initdb add alpine-base


# COMPLETE IMAGE MOUNTING FOR CHROOT
mkdir -p "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/etc/apk" "$MNT/usr/bin"
mount /dev/ "$MNT/dev/" --bind
mount -t proc none "$MNT/proc"
mount -o bind /sys "$MNT/sys"


# CONFIGURE ALPINE (仅 main + community)
cp /etc/resolv.conf "$MNT/etc/resolv.conf"
cat > "$MNT/etc/apk/repositories" <<EOF
$REPO/v3.20/main
$REPO/v3.20/community
EOF

# 用 heredoc 写入 startgui.sh
cat > "$MNT/startgui.sh" <<'STARTGUI_EOF'
#!/bin/sh
chmod a+w /dev/shm

SIZE=$(xwininfo -root -display :0 | egrep "geometry" | cut -d " "  -f4)
env DISPLAY=:0 Xephyr :1 -title "L:D_N:application_ID:xephyr" -ac -br -screen $SIZE -cc 4 -reset -terminate &
sleep 3

# 以 alpine 用户身份，在同一 session bus 中启动 ibus + jwm + onboard + chromium
su alpine -c "export DISPLAY=:1 GTK_IM_MODULE=ibus QT_IM_MODULE=ibus XMODIFIERS=@im=ibus LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8; exec dbus-run-session -- sh -c 'ibus-daemon -drx; jwm & sleep 1; onboard & chromium'"

killall Xephyr 2>/dev/null
STARTGUI_EOF
chmod +x "$MNT/startgui.sh"


# CHROOT
# 复制静态模拟器，并统一重命名为 qemu-arm-static（chroot 内命令名不变）
cp "$QEMU_ARM_STATIC" "$MNT/usr/bin/qemu-arm-static"
chmod +x "$MNT/usr/bin/qemu-arm-static"
echo "Chrooting into Alpine"
chroot "$MNT" qemu-arm-static /bin/sh -c "$ALPINESETUP"
rm "$MNT/usr/bin/qemu-arm-static"


# UNMOUNT IMAGE & CLEANUP
sync
kill "$(lsof +f -t "$MNT")" 2>/dev/null || true
echo "Unmounting image"
umount "$MNT/sys"
umount "$MNT/proc"
umount -lf "$MNT/dev"
umount "$MNT"
while [[ $(mount | grep "$MNT") ]]
do
	echo "Alpine is still mounted, please wait.."
	sleep 3
	umount "$MNT" 2>/dev/null || true
done
echo "Alpine unmounted"

echo "Cleaning up"
rm -f /tmp/apk-tools-static.apk
rm -rf /tmp/sbin
