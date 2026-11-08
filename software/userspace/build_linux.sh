#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")"; pwd)
out=${1:-/var/tmp/oryukdo-published/kfb-linux-1g}
src=${LINUX_SRC:-$HOME/or_bo_linux/linux-6.12}
cc="$out/tool/rv32-gcc"
for p in init ddrcheck; do "$cc" -Os -static -s -o "$out/$p" "$here/$p.c"; done
cat >"$out/root.list" <<EOF
dir /bin 0755 0 0
dir /dev 0755 0 0
dir /proc 0555 0 0
dir /sys 0555 0 0
dir /tmp 01777 0 0
nod /dev/console 0600 0 0 c 5 1
file /init $out/init 0755 0 0
file /bin/busybox $out/busybox 0755 0 0
file /bin/ddrcheck $out/ddrcheck 0755 0 0
EOF
for app in ash sh cat ls echo pwd uname free head grep mount mkdir sleep ps env true false test printf dmesg tty stty setsid sync date wc cp mv rm touch; do
    printf 'slink /bin/%s busybox 0777 0 0\n' "$app" >>"$out/root.list"
done
mkdir -p "$out/kernel"
make_k() { make --no-print-directory -C "$src" ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- O="$out/kernel" "$@"; }
KCONFIG_ALLCONFIG="$here/../linux_userspace_miniconfig" make_k allnoconfig
cfg=("$src/scripts/config" --file "$out/kernel/.config")
"${cfg[@]}" --set-str INITRAMFS_SOURCE "$out/root.list" --set-str LOCALVERSION "-oryukdo-kfb" \
    -e BINFMT_SCRIPT -e MULTIUSER -e FUTEX -e POSIX_TIMERS -e PROC_PAGE_MONITOR -e TTY -e DEVTMPFS -e UNIX98_PTYS \
    -e EPOLL -e SIGNALFD -e EVENTFD -e PRINTK -e IKCONFIG -e IKCONFIG_PROC
make_k olddefconfig
export KBUILD_BUILD_TIMESTAMP="2026-11-07 00:00:00 UTC" KBUILD_BUILD_USER=oryukdo KBUILD_BUILD_HOST=kfb KBUILD_BUILD_VERSION=1
make_k -j10 Image
cp "$out/kernel/arch/riscv/boot/Image" "$out/Image"
cp "$out/kernel/.config" "$here/config-linux"
cp "$out/busybox-1.37.0/.config" "$here/config-busybox"
