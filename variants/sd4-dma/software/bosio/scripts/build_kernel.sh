#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.."; pwd)
original=${1:?사용법: build_kernel.sh Linux원본소스 별도출력경로 RV32-bosioctl}
out=${2:?별도출력경로 필요}
tool=${3:?RV32 bosioctl 실행파일 경로 필요}
tool=$(realpath "$tool")
mkdir -p "$out"
out=$(cd "$out"; pwd)
if [[ ! -d "$out/linux" ]]; then cp -a --reflink=auto "$original" "$out/linux"; fi
src="$out/linux"
dest="$src/drivers/misc/oryukdo-bosio"
mkdir -p "$dest" "$out/kernel" "$root/software/bosio/reports"
cp -a "$root/software/bosio/driver" "$root/software/bosio/common" "$root/software/bosio/include" "$dest/"
printf 'obj-y += driver/\n' >"$dest/Makefile"
grep -q '^obj-y += oryukdo-bosio/' "$src/drivers/misc/Makefile" || printf '\nobj-y += oryukdo-bosio/\n' >>"$src/drivers/misc/Makefile"
cp "$root/software/linux/config" "$out/kernel/.config"
cp "$root/software/linux/initramfs.original.list" "$out/root.list"
sed -i "s|/var/tmp/kfb-linux-1g/|$root/software/firmware/|g" "$out/root.list"
printf 'file /bin/bosioctl %s 0755 0 0\n' "$tool" >>"$out/root.list"
"$src/scripts/config" --file "$out/kernel/.config" --set-str INITRAMFS_SOURCE "$out/root.list"
export KBUILD_BUILD_TIMESTAMP='2026-11-08 00:00:00 UTC' KBUILD_BUILD_USER=oryukdo KBUILD_BUILD_HOST=kfb KBUILD_BUILD_VERSION=1
make -C "$src" O="$out/kernel" ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- olddefconfig >"$out/config.log" 2>&1
make -C "$src" O="$out/kernel" ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j4 Image >"$out/kernel.log" 2>&1
cp "$out/kernel.log" "$root/software/bosio/reports/kernel_build.log"
riscv64-linux-gnu-nm "$out/kernel/vmlinux" | grep -E ' (bosio_probe|bosio_ioctl|bo_run|bo_present)$' | tee "$root/software/bosio/reports/kernel_symbols.log"
echo 'PASS Linux RV32 Image built with BOSIO built-in driver'
mkdir -p "$out/firmware"
cp "$out/kernel/arch/riscv/boot/Image" "$out/firmware/Image"
cp "$root/software/firmware/fw_jump.bin" "$out/firmware/"
cp "$root/software/bosio/gen3-bosio.dts" "$out/firmware/gen3.dts"
python3 "$root/soc/board/make_sd.py" "$out/sd" --firmware "$out/firmware" >"$out/sd_build.log"
python3 "$root/soc/board/verify_image.py" "$out/sd/ORYUKDO-Gen3-BOSIO-KFB-1GiB-BusyBox.img" "$out/firmware" "$out/sd/gen3.dtb" | tee "$root/software/bosio/reports/sd_verify.log"
