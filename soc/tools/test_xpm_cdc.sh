#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
source soc/tools/xpm_verilator.sh
for mode in bundled soc_reset queued queued_soc_reset; do
 top=tb_${mode}_cdc
 verilator "${XPM_ARGS[@]}" --binary --timing --assert -Wno-fatal -j 4 --top-module "$top" --Mdir /var/tmp/oryukdo-published/gen3_clean_drcperf_${mode} soc/bosio/or_bo_axi_pkg.sv soc/bosio/or_bo_cdc_mailbox.sv soc/bosio/or_bo_xpm_mailbox.sv soc/tests/reviewed_cpu_reset.sv soc/tests/tb_xpm_cdc.sv >soc/reports/xpm_${mode}_build.log 2>&1
 for seed in 1 7 23; do
  /var/tmp/oryukdo-published/gen3_clean_drcperf_${mode}/V${top} +seed=$seed | tee soc/reports/xpm_${mode}_seed$seed.log
 done
done
