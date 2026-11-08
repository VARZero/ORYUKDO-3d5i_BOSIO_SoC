#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_serial --Mdir /var/tmp/oryukdo-published/gen3_clean_bosio_io_serial soc/bosio/or_bo_axi_pkg.sv soc/rtl/uart8250_poll.sv soc/bosio/gen3_axil_regs.sv soc/bosio/gen3_axi_spi.sv soc/bosio/gen3_axi_i2c.sv soc/tests/tb_serial.sv >soc/reports/serial_build.log 2>&1
/var/tmp/oryukdo-published/gen3_clean_bosio_io_serial/Vtb_serial | tee soc/reports/serial.log
