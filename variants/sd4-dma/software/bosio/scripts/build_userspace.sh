#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.."; pwd)
out=${1:-/var/tmp/oryukdo-bosio-userspace}
mkdir -p "$out"
cc=${RV32_CC:?RV32_CC must name the RV32 ILP32 musl compiler wrapper}
"$cc" -Os -static -Wall -Wextra -Werror -o "$out/bosioctl" "$root/software/bosio/tools/bosioctl.c"
riscv64-linux-gnu-readelf -h "$out/bosioctl" | tee "$out/elf.txt"
riscv64-linux-gnu-readelf -A "$out/bosioctl" | tee "$out/attributes.txt"
echo 'PASS bosioctl RV32 ILP32 static build'
