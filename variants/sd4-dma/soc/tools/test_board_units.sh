#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
source soc/tools/xpm_verilator.sh
verilator --binary --timing --assert -Wno-fatal -j 6 --output-split 0 --output-split-cfuncs 0 --top-module tb_kfb_memory --Mdir /var/tmp/oryukdo-published/kfb_native_test_unsplit soc/bosio/or_bo_axi_pkg.sv soc/board/kfb_axi_mig.sv soc/board/kfb_native_arbiter.sv soc/tests/kfb_native_ram_model.sv soc/tests/tb_kfb_memory.sv >soc/reports/native_build.log 2>&1
for seed in 1 7 23; do /var/tmp/oryukdo-published/kfb_native_test_unsplit/Vtb_kfb_memory +seed=$seed | tee soc/reports/native_seed$seed.log; done
verilator "${XPM_ARGS[@]}" --binary --timing --assert -Wno-fatal -j 6 --output-split 0 --output-split-cfuncs 0 --top-module tb_kfb_video --Mdir /var/tmp/oryukdo-published/kfb_video_test soc/board/kfb_video_fifo.sv soc/board/kfb_video.sv soc/board/kfb_native_arbiter.sv soc/tests/kfb_native_ram_model.sv soc/tests/tb_kfb_video.sv >soc/reports/video_build.log 2>&1
for seed in 1 7 23; do /var/tmp/oryukdo-published/kfb_video_test/Vtb_kfb_video +seed=$seed | tee soc/reports/video_seed$seed.log; done
