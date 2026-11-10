#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
out=${1:-/var/tmp/oryukdo-published/kfb-coldboot-bridge}
mkdir -p "$out"
for mode in baseline fixed; do
  rtl=soc/bosio/or_bo_cpu_axi.sv
  if [[ "$mode" == baseline ]]; then rtl=soc/board/coldboot/baseline/or_bo_cpu_axi.sv; fi
  verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_cpu_axi_independent \
    --Mdir "$out/$mode" soc/bosio/or_bo_axi_pkg.sv "$rtl" soc/tests/axi_ram_model.sv \
    soc/tests/tb_cpu_axi_independent.sv >"$out/${mode}_build.log" 2>&1
  if [[ "$mode" == baseline ]]; then
    if "$out/$mode/Vtb_cpu_axi_independent" >"$out/baseline_failure.log" 2>&1; then
      echo 'FAIL: expected baseline deadlock did not reproduce'; exit 1
    fi
    grep -q INDEPENDENT_RESPONSE_DEADLOCK "$out/baseline_failure.log"
    echo 'PASS reproduced original bridge deadlock'
  else
    for seed in 1 7 23; do
      "$out/$mode/Vtb_cpu_axi_independent" +seed=$seed | tee "$out/fixed_seed$seed.log"
    done
  fi
done
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_fetch_bridge \
  --Mdir "$out/fetch" soc/bosio/or_bo_axi_pkg.sv soc/bosio/or_bo_cpu_axi.sv \
  soc/tests/tb_fetch_bridge.sv >"$out/fetch_build.log" 2>&1
for seed in 1 7 23; do
  "$out/fetch/Vtb_fetch_bridge" +seed=$seed | tee "$out/fetch_seed$seed.log"
done
