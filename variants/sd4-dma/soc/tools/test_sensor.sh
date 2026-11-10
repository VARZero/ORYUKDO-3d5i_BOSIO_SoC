#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_sensor_link --Mdir /var/tmp/oryukdo-published/gen3_clean_bosio_sensor soc/vendor/sensor/*.v soc/vendor/output/bosio_out_sensor_rx.v soc/tests/tb_sensor_link.sv >soc/reports/sensor_build.log 2>&1
/var/tmp/oryukdo-published/gen3_clean_bosio_sensor/Vtb_sensor_link | tee soc/reports/sensor_link.log
