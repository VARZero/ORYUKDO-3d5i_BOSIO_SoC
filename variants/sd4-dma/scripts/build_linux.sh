#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.."; pwd)
src=${1:?사용법: build_linux.sh Linux소스경로 출력경로}
out=${2:?출력경로 필요}
mkdir -p "$out"
out=$(cd "$out"; pwd)
src=$(cd "$src"; pwd)
fw="$root/software/firmware"
mkdir -p "$out/kernel" "$out/firmware"
cp "$root/software/linux/config" "$out/kernel/.config"
# 현재 빌드에서 확인된 initramfs 실행 파일. 전체 userspace 재빌드는 별도 설명 참조.
cat >"$out/root.list" <<EOF
dir /bin 0755 0 0
dir /dev 0755 0 0
dir /proc 0555 0 0
dir /sys 0555 0 0
dir /tmp 01777 0 0
nod /dev/console 0600 0 0 c 5 1
file /init $fw/init 0755 0 0
file /bin/busybox $fw/busybox 0755 0 0
file /bin/ddrcheck $fw/ddrcheck 0755 0 0
EOF
for app in ash sh cat ls echo pwd uname free head grep mount mkdir sleep ps env true false test printf dmesg tty stty setsid sync date wc cp mv rm touch; do
    printf 'slink /bin/%s busybox 0777 0 0\n' "$app" >>"$out/root.list"
done
"$src/scripts/config" --file "$out/kernel/.config" --set-str INITRAMFS_SOURCE "$out/root.list"
export KBUILD_BUILD_TIMESTAMP='2026-11-07 00:00:00 UTC'
export KBUILD_BUILD_USER=oryukdo KBUILD_BUILD_HOST=kfb KBUILD_BUILD_VERSION=1
make -C "$src" O="$out/kernel" ARCH=riscv CROSS_COMPILE="${CROSS_COMPILE:-riscv64-linux-gnu-}" olddefconfig
make -C "$src" O="$out/kernel" ARCH=riscv CROSS_COMPILE="${CROSS_COMPILE:-riscv64-linux-gnu-}" -j"${JOBS:-4}" Image
cp "$out/kernel/arch/riscv/boot/Image" "$out/firmware/Image"
cp "$fw/fw_jump.bin" "$fw/gen3.dts" "$out/firmware/"
python3 "$root/soc/board/make_sd.py" "$out/sd" --firmware "$out/firmware"
python3 "$root/soc/board/verify_image.py" "$out/sd/ORYUKDO-Gen3-BOSIO-KFB-1GiB-BusyBox.img" "$out/firmware" "$out/sd/gen3.dtb"
