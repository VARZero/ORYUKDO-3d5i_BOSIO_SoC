#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")"; pwd)
project=$(cd "$here/../.."; pwd)
out=${1:-/var/tmp/oryukdo-sd4-linux}
mkdir -p "$out"
if [[ ! -e "$out/linux/Makefile" ]]; then
 cp -aL --reflink=auto /var/tmp/oryukdo-boayo-boottrace-v1/linux "$out/linux"
fi
src="$out/linux"
# Reject inherited external source links before any modification.
if [[ -n "$(find "$src" -type l -lname '/*' -print -quit)" ]]; then
 echo 'Source tree contains symlinks; materialize an independent copy first.' >&2
 exit 1
fi
cp "$here/oryukdo_sd.c" "$src/drivers/mmc/host/oryukdo_sd.c"
cp "$here/oryukdo_dma.c" "$src/drivers/dma/oryukdo_dma.c"
if ! grep -q 'CONFIG_MMC_ORYUKDO' "$src/drivers/mmc/host/Makefile"; then
 printf '\nobj-$(CONFIG_MMC_ORYUKDO) += oryukdo_sd.o\n' >> "$src/drivers/mmc/host/Makefile"
 printf '\nconfig MMC_ORYUKDO\n\tbool "ORYUKDO native SD host"\n\tdepends on MMC && RISCV\n' >> "$src/drivers/mmc/host/Kconfig"
fi
if ! grep -q 'CONFIG_ORYUKDO_DMA' "$src/drivers/dma/Makefile"; then
 printf '\nobj-$(CONFIG_ORYUKDO_DMA) += oryukdo_dma.o\n' >> "$src/drivers/dma/Makefile"
 printf '\nconfig ORYUKDO_DMA\n\tbool "ORYUKDO copy/fill DMA"\n\tdepends on RISCV\n\tselect DMA_ENGINE\n\tselect DMA_VIRTUAL_CHANNELS\n' >> "$src/drivers/dma/Kconfig"
fi
if [[ ! -d "$out/root" ]]; then
 cp -a /var/tmp/oryukdo-boayo-native-v2-final/root "$out/root"
fi
mkdir -p "$out/root/data" "$out/kernel" "$out/firmware" "$out/data-root"
# Preserve the known v2 executable and BusyBox. This task changes storage only.
python3 "$here/prepare_root.py" "$out/root"
python3 "$project/../bosio-linux-sw/software/boayo/root_list.py" "$out/root" > "$out/root.list"
cp /var/tmp/oryukdo-boayo-native-v2-final/kernel/.config "$out/kernel/.config"
cfg=("$src/scripts/config" --file "$out/kernel/.config")
"${cfg[@]}" --set-str INITRAMFS_SOURCE "$out/root.list" --set-str LOCALVERSION '-oryukdo-sd4-dma1'
"${cfg[@]}" --enable BLOCK --enable MMC --enable MMC_BLOCK --enable MMC_ORYUKDO --enable SIFIVE_PLIC \
 --enable DMADEVICES --enable ORYUKDO_DMA --enable EXT4_FS --enable MSDOS_PARTITION \
 --disable INITRAMFS_COMPRESSION_GZIP --enable INITRAMFS_COMPRESSION_NONE
export KBUILD_BUILD_TIMESTAMP='2026-11-09 00:00:00 UTC' KBUILD_BUILD_USER=oryukdo KBUILD_BUILD_HOST=kfb
make -C "$src" O="$out/kernel" ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- olddefconfig > "$out/config.log" 2>&1
make -C "$src" O="$out/kernel" ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j6 Image > "$out/kernel.log" 2>&1
cp "$out/kernel/arch/riscv/boot/Image" "$out/firmware/Image"
cp "$project/software/firmware/fw_jump.bin" "$out/firmware/"
cp "$project/software/bosio/gen3-bosio.dts" "$out/firmware/gen3.dts"
printf 'ORYUKDO SD4 DMA persistent data partition\n' > "$out/data-root/README.txt"
python3 "$here/make_image.py" "$out/image" --firmware "$out/firmware" --data-root "$out/data-root" > "$out/image.log" 2>&1
echo 'PASS kernel and raw boot + ext4 image built; board validation pending'
