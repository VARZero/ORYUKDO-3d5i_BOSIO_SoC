#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
source soc/tools/xpm_verilator.sh
verilator "${XPM_ARGS[@]}" --binary --timing --assert -Wno-fatal -j 4 --output-split 0 --output-split-cfuncs 0 -DKFB_VIDEO_720P --top-module tb_kfb_video --Mdir /var/tmp/oryukdo-published/kfb_video_720p soc/board/kfb_video_fifo.sv soc/board/kfb_video.sv soc/board/kfb_native_arbiter.sv soc/tests/kfb_native_ram_model.sv soc/tests/tb_kfb_video.sv >soc/reports/video_720p_build.log 2>&1
/var/tmp/oryukdo-published/kfb_video_720p/Vtb_kfb_video +seed=1 | tee soc/reports/video_720p.log
