#!/usr/bin/env bash

# DEPENDENCIES
# This script is intended to run on a GitHub Actions runner after
# docker/setup-qemu-action@v4 has been executed, which registers
# binfmt_misc handlers for ARM. No qemu-arm-static binary is needed.
# On a local x86_64 host without binfmt_misc, install qemu-user-binfmt
# and ensure binfmt_misc is mounted, or run inside an ARM container.

# BASIC CONFIGURATION
REPO="http://dl-cdn.alpinelinux.org/alpine"
MNT="/mnt/alpine"
IMAGE="./alpine.ext3"
IMAGESIZE=1024 #Megabytes

ALPINESETUP="source /etc/profile
echo kindle > /etc/hostname
echo \"nameserver 8.8.8.8\" > /etc/resolv.conf
mkdir -p /run/dbus
apk update
apk upgrade
cat /etc/alpine-release

apk add xorg-server-xephyr xwininfo xdotool xinput dbus-x11 sudo bash nano git
apk add jwm
apk add musl-locales font-droid-nonlatin font-dejavu
localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 2>/dev/null || true
apk add ibus ibus-libpinyin ibus-gtk3 ibus-lang
apk add onboard chromium

adduser alpine -D
echo -e \"alpine\nalpine\" | passwd alpine
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers
addgroup sudo
addgroup alpine sudo

cat > /etc/profile.d/ibus.sh <<'EOF'
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
EOF

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
echo '{
	\"external_update_url\": \"https://clients2.google.com/service/update2/crx\"
}' > /usr/share/chromium/extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm.json

echo \"You're now dropped into an interactive shell in Alpine, feel free to explore and type exit to leave.\"
sh"


# ENSURE ROOT
[ "$(whoami)" != "root" ] && echo "This script needs to be run as root" && exec sudo -- "$0" "$@"


# VERIFY BINFMT_MISC FOR ARM
# setup-qemu-action should have registered the ARM handler.
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-arm ] || \
   ! grep -q enabled /proc/sys/fs/binfmt_misc/qemu-arm; then
    echo "ERROR: ARM binfmt_misc handler is not enabled." >&2
    echo "Make sure docker/setup-qemu-action ran before this script," >&2
    echo "or install qemu-user-binfmt and mount binfmt_misc." >&2
    exit 1
fi
echo "ARM binfmt_misc handler is active."


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
# binfmt_misc transparently emulates the ARM apk.static binary.
echo "Bootstrapping Alpine v3.20"
/tmp/sbin/apk.static -X "$REPO/v3.20/main" -U --allow-untrusted --root "$MNT" --initdb add alpine-base


# COMPLETE IMAGE MOUNTING FOR CHROOT
mkdir -p "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/etc/apk" "$MNT/usr/bin"
mount /dev/ "$MNT/dev/" --bind
mount -t proc none "$MNT/proc"
mount -o bind /sys "$MNT/sys"


# CONFIGURE ALPINE (main + community)
cp /etc/resolv.conf "$MNT/etc/resolv.conf"
cat > "$MNT/etc/apk/repositories" <<EOF
$REPO/v3.20/main
$REPO/v3.20/community
EOF

# 写入 startgui.sh
cat > "$MNT/startgui.sh" <<'STARTGUI_EOF'
#!/bin/sh
chmod a+w /dev/shm

SIZE=$(xwininfo -root -display :0 | egrep "geometry" | cut -d " "  -f4)
env DISPLAY=:0 Xephyr :1 -title "L:D_N:application_ID:xephyr" -ac -br -screen $SIZE -cc 4 -reset -terminate &
sleep 3

su alpine -c "export DISPLAY=:1 GTK_IM_MODULE=ibus QT_IM_MODULE=ibus XMODIFIERS=@im=ibus LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8; exec dbus-run-session -- sh -c 'ibus-daemon -drx; jwm & sleep 1; onboard & chromium'"

killall Xephyr 2>/dev/null
STARTGUI_EOF
chmod +x "$MNT/startgui.sh"


# CHROOT
# binfmt_misc 同样作用于 chroot 内的 ARM 二进制，无需复制 qemu-arm-static。
echo "Chrooting into Alpine"
chroot "$MNT" /bin/sh -c "$ALPINESETUP"


# UNMOUNT IMAGE & CLEANUP
sync
kill "$(lsof +f -t "$MNT")" 2>/dev/null || true
echo "Unmounting image"
umount "$MNT/sys"
umount "$MNT/proc"
umount -lf "$MNT/dev"
umount "$MNT"
while [[ $(mount | grep "$MNT")" ]]
do
    echo "Alpine is still mounted, please wait.."
    sleep 3
    umount "$MNT" 2>/dev/null || true
done
echo "Alpine unmounted"

echo "Cleaning up"
rm -f /tmp/apk-tools-static.apk
rm -rf /tmp/sbin
