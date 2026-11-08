#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")"; pwd)
out=${1:-/var/tmp/oryukdo-published/kfb-bosio-sd-test}
mkdir -p "$out" "$here/logs"
cd "$here"
python3 make_sd.py "$out/image" > "$here/logs/image.log"
verilator --lint-only --top-module sd_boot sd_boot.sv sd_reader.sv > "$here/logs/lint.log" 2>&1
verilator --cc --exe --build -j 4 -O3 --top-module sd_boot --Mdir "$out/obj" \
    sd_boot.sv sd_reader.sv "$here/test_sd.cpp" > "$here/logs/verilator-build.log" 2>&1
: > "$here/logs/loader.log"
for mode in no-card sdsc header oversize sector-crc ddr payload-crc good; do
    extra=()
    if [[ "$mode" == good ]]; then extra+=("$out/loaded-ddr.hex"); fi
    "$out/obj/Vsd_boot" "$out/image/ORYUKDO-Gen3-BOSIO-KFB-1GiB-BusyBox.img" "$here/../../software/firmware/fw_jump.bin" \
        "$here/../../software/firmware/Image" "$out/image/gen3.dtb" "$mode" "${extra[@]}" | tee -a "$here/logs/loader.log"
done
