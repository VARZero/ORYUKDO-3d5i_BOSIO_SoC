#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_fetch_bridge --Mdir /var/tmp/oryukdo-published/gen3_clean_fetch_bridge soc/bosio/or_bo_axi_pkg.sv soc/bosio/or_bo_cpu_axi.sv soc/tests/tb_fetch_bridge.sv >soc/reports/fetch_build.log 2>&1
for seed in 1 7 23; do /var/tmp/oryukdo-published/gen3_clean_fetch_bridge/Vtb_fetch_bridge +seed=$seed | tee soc/reports/fetch_seed$seed.log; done
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_ram_reset --Mdir /var/tmp/oryukdo-published/gen3_clean_ram_reset soc/vendor/output/bosio_out_fifo.v soc/vendor/output/varzero_cache_line.v soc/tests/tb_ram_reset.sv >soc/reports/ram_reset_build.log 2>&1
/var/tmp/oryukdo-published/gen3_clean_ram_reset/Vtb_ram_reset | tee soc/reports/ram_reset.log
