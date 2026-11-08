#!/usr/bin/env bash
set -euo pipefail
ulimit -s unlimited
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
source soc/tools/xpm_verilator.sh
verilator "${XPM_ARGS[@]}" --binary --timing --assert -Wno-fatal -j 4 --output-split 0 --output-split-cfuncs 0 --top-module tb_axi_fabric --Mdir /var/tmp/oryukdo-published/gen3_clean_bosio_drcperf_fabric_unsplit soc/bosio/or_bo_axi_pkg.sv soc/bosio/or_bo_cdc_mailbox.sv soc/bosio/or_bo_xpm_mailbox.sv soc/bosio/or_bo_axi_cdc.sv soc/bosio/or_bo_axi_fabric.sv soc/bosio/gen3_bosio_status.sv soc/tests/axi_ram_model.sv soc/tests/axi_lite_test_slave.sv soc/tests/tb_axi_fabric.sv >soc/reports/fabric_build.log 2>&1
for seed in 1 7 23; do
 /var/tmp/oryukdo-published/gen3_clean_bosio_drcperf_fabric_unsplit/Vtb_axi_fabric +seed=$seed | tee soc/reports/fabric_seed$seed.log
done
