#!/usr/bin/env bash

# DEPENDENCIES
# qemu-user-static is required to run arm software using the "qemu-arm-static" command
# (assumes you run this on an X86_64 host). Install it via your package manager.

# BASIC CONFIGURATION
REPO="http://dl-cdn.alpinelinux.org/alpine"
MNT="/mnt/alpine"
IMAGE="./alpine.ext3"
IMAGESIZE=1536 #Megabytes (1.5G)

ALPINESETUP="source /etc/profile
echo kindle > /etc/hostname
echo \"nameserver 8.8.8.8\" > /etc/resolv.conf
mkdir -p /run/dbus
apk update
apk upgrade
cat /etc/alpine-release

# --- X / input / base tools ---
apk add xorg-server-xephyr xwininfo xdotool xinput dbus-x11 sudo bash nano git

# --- theme engines ---
apk add desktop-file-utils gtk-engines gtk-murrine-engine gnome-themes-extra consolekit

# --- LXQt core (v3.20 community; lxqt-desktop depends on openbox) ---
apk add lxqt-desktop lxqt-core lxqt-panel lxqt-admin lxqt-config \
        lxqt-notificationd lxqt-powermanagement lxqt-themes
# 注销/重启/关机需要 elogind + polkit-elogind
apk add elogind polkit-elogind

# --- 中文字体 + locale ---
# font-droid-nonlatin (main仓库, ~6MiB) 提供轻量中文显示
apk add musl-locales font-droid-nonlatin
localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 2>/dev/null || true

# --- 中文输入法 (IBus + libpinyin, v3.20 community) ---
apk add ibus ibus-libpinyin ibus-gtk3 ibus-lang

# --- virtual keyboard + browser ---
apk add onboard chromium

adduser alpine -D
echo -e \"alpine\nalpine\" | passwd alpine
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers
addgroup sudo
addgroup alpine sudo

# --- 输入法环境变量 (全局兜底) ---
cat > /etc/profile.d/ibus.sh <<'EOF'
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
EOF

su alpine -c \"cd ~
git init
git remote add origin https://github.com/schuhumi/alpine_kindle_dotfiles
git pull origin master
git reset --hard origin/master
dconf load /org/mate/ < ~/.config/org_mate.dconf.dump 2>/dev/null || true
dconf load /org/onboard/ < ~/.config/org_onboard.dconf.dump 2>/dev/null || true\"

echo '# Default settings for chromium. This file is sourced by /bin/sh from
# the chromium launcher.

# Options to pass to chromium.
mouseid=\"\$(env DISPLAY=:1 xinput list --id-only \"Xephyr virtual mouse\")\"
CHROMIUM_FLAGS='\''--force-device-scale-factor=2 --touch-devices='\''\$mouseid'\'' --pull-to-refresh=1 --disable-smooth-scrolling --enable-low-end-device-mode --disable-login-animations --disable-modal-animations --wm-window-animations-disabled --start-maximized --user-agent=Mozilla%2F5.0%20%28Linux%3B%20Android%207.0%3B%20SM-G930V%20Build%2FNRD90M%29%20AppleWebKit%2F537.36%20%28KHTML%2C%20like%20Gecko%29%20Chrome%2F59.0.3071.125%20Mobile%20Safari%2F537.36'\''' > /etc/chromium/chromium.conf
mkdir -p /usr/share/chromium/extensions
# Install uBlock Origin
echo '{
	\"external_update_url\": \"https://clients2.google.com/service/update2/crx\"
}' > /usr/share/chromium/extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm.json

echo \"You're now dropped into an interactive shell in Alpine, feel free to explore and type exit to leave.\"
sh"

STARTGUI='#!/bin/sh
chmod a+w /dev/shm

SIZE=$(xwininfo -root -display :0 | egrep "geometry" | cut -d " "  -f4)
env DISPLAY=:0 Xephyr :1 -title "L:D_N:application_ID:xephyr" -ac -br -screen $SIZE -cc 4 -reset -terminate &
sleep 3

# 以 alpine 用户身份，在同一个 session bus 中启动 ibus 和 LXQt
su alpine -c "export DISPLAY=:1 GTK_IM_MODULE=ibus QT_IM_MODULE=ibus XMODIFIERS=@im=ibus LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8; exec dbus-run-session -- sh -c 'ibus-daemon -drx; lxqt-session'"

killall Xephyr 2>/dev/null'


# ENSURE ROOT
[ "$(whoami)" != "root" ] && echo "This script needs to be run as root" && exec sudo -- "$0" "$@"


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
qemu-arm-static /tmp/sbin/apk.static -X "$REPO/v3.20/main" -U --allow-untrusted --root "$MNT" --initdb add alpine-base


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
echo "$STARTGUI" > "$MNT/startgui.sh"
chmod +x "$MNT/startgui.sh"


# CHROOT
cp "$(which qemu-arm-static)" "$MNT/usr/bin/"
echo "Chrooting into Alpine"
chroot /mnt/alpine/ qemu-arm-static /bin/sh -c "$ALPINESETUP"
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
