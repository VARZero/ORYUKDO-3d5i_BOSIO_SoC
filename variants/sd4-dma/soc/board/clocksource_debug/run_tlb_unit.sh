#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")"; pwd)
root=$(cd "$here/../../.."; pwd)
out=${KFB_TLB_UNIT_OUT:-/var/tmp/oryukdo-published/kfb-clocksource-tlb/unit}
mkdir -p "$out"
verilator --cc --exe --build -j 4 --assert -Wno-fatal \
  --top-module rv32_sv32 --Mdir "$out/model" \
  "$root/soc/rtl/rv32_sv32.sv" "$here/test_tlb.cpp" \
  >"$out/build.log" 2>&1
"$out/model/Vrv32_sv32" | tee "$out/result.log"
