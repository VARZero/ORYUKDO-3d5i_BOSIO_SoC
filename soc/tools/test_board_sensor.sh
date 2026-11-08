#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
source soc/tools/xpm_verilator.sh
verilator "${XPM_ARGS[@]}" -DKFB_INPUT_CDC --binary --timing --assert -Wno-fatal -j 4 --output-split 0 --output-split-cfuncs 0 --top-module tb_sensor_link --Mdir /var/tmp/oryukdo-published/gen3_kfb_sensor soc/vendor/sensor/*.v soc/vendor/output/bosio_out_sensor_rx.v soc/tests/tb_sensor_link.sv >soc/reports/board_sensor_build.log 2>&1
/var/tmp/oryukdo-published/gen3_kfb_sensor/Vtb_sensor_link | tee soc/reports/board_sensor.log
