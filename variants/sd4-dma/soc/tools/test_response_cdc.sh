#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_response_cdc --Mdir /var/tmp/oryukdo-published/gen3_clean_response_cdc soc/bosio/or_bo_cdc_mailbox.sv soc/tests/tb_response_cdc.sv >soc/reports/response_cdc_build.log 2>&1
for seed in 1 7 23; do
 /var/tmp/oryukdo-published/gen3_clean_response_cdc/Vtb_response_cdc +seed=$seed | tee soc/reports/response_cdc_seed$seed.log
done
