#!/usr/bin/env bash
set -euo pipefail
ulimit -s unlimited
cd "$(dirname "$0")/../../.."
out=${1:-/var/tmp/oryukdo-published/kfb-coldboot-v1}
mkdir -p "$out" soc/reports/coldboot
here="$PWD/soc/board/coldboot"
source soc/tools/xpm_verilator.sh
verilator --cc --build -j 6 -O3 --top-module sd_boot --Mdir "$out/sd" \
  soc/board/sd_boot.sv soc/board/sd_reader.sv >"$out/build_sd.log" 2>&1
verilator "${XPM_ARGS[@]}" --cc --exe --build -j 6 -O3 --threads "${KFB_SIM_THREADS:-4}" --assert --unroll-count 512 --no-timing \
  -Wno-fatal -Wno-TIMESCALEMOD --top-module tb_kfb_coldboot --Mdir "$out/runtime" \
  -CFLAGS "-O3 -march=native -std=c++20 -I$out/sd" -LDFLAGS "$out/sd/Vsd_boot__ALL.a" \
  -f soc/bosio_sources.f soc/board/kfb_axi_mig.sv soc/board/kfb_native_arbiter.sv \
  soc/board/kfb_video_fifo.sv soc/board/kfb_video.sv "$here/tb_kfb_coldboot.sv" "$here/run.cpp" \
  >"$out/build_runtime.log" 2>&1
"$out/runtime/Vtb_kfb_coldboot" "${KFB_SD_IMAGE:-artifacts/ORYUKDO-KFB-clocksource-trace-v2.img}" \
  "${KFB_MAX_CPU_CYCLES:-100000000000}" \
  2>&1 | tee "$out/coldboot.log"
python3 "$here/check_result.py" "$out/coldboot.log" --output "$out/accepted"
