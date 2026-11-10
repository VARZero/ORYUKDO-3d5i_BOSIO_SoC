#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.."; pwd)
cd "$root"
mkdir -p validation
base=(soc/bosio/or_bo_axi_pkg.sv soc/bosio/gen3_axil_regs.sv)
storage=(soc/bosio/or_storage_dma.sv soc/bosio/or_sd_native.sv soc/bosio/or_sd_storage.sv)
verilator --cc --exe --build -j 4 --assert --top-module or_sd_native -GTIMEOUT_CYCLES=200000 \
 --Mdir /var/tmp/oryukdo-sd4-native soc/bosio/or_sd_native.sv "$PWD/soc/tests/test_sd_native.cpp" > validation/native_build.log 2>&1
/var/tmp/oryukdo-sd4-native/Vor_sd_native | tee validation/native_test.log
/var/tmp/oryukdo-sd4-native/Vor_sd_native 2 | tee validation/native_delayed_input_test.log
for test in dma plic irq; do
 case "$test" in
 dma) files=("${base[@]}" soc/bosio/or_storage_dma.sv soc/bosio/or_bo_axi_fabric.sv soc/tests/axi_ram_model.sv);;
 plic) files=("${base[@]}" soc/bosio/or_storage_plic.sv);;
 irq) files=(soc/rtl/rv32_pkg.sv soc/rtl/rv32_machine_csrs.sv);;
 esac
 verilator --binary --timing --assert -j 4 -Wno-TIMESCALEMOD --top-module "tb_storage_$test" \
 --Mdir "/var/tmp/oryukdo-sd4-$test-test" "${files[@]}" "soc/tests/tb_storage_$test.sv" > "validation/${test}_build.log" 2>&1
 for seed in 1 7 23; do
  "/var/tmp/oryukdo-sd4-$test-test/Vtb_storage_$test" +seed=$seed +verilator+seed+$seed > "validation/${test}_seed${seed}.log" 2>&1
 done
 cat "validation/${test}_seed1.log"
done
verilator --cc --exe --build -j 4 -Wno-TIMESCALEMOD --assert --top-module tb_sd_storage \
 --Mdir /var/tmp/oryukdo-sd4-storage-test "${base[@]}" "${storage[@]}" soc/board/sd_boot.sv \
 soc/tests/axi_ram_model.sv soc/tests/tb_sd_storage.sv "$PWD/soc/tests/test_sd_storage.cpp" > validation/storage_build.log 2>&1
/var/tmp/oryukdo-sd4-storage-test/Vtb_sd_storage | tee validation/storage_test.log
for mode in header oversize payload-crc card-crc ddr; do
 /var/tmp/oryukdo-sd4-storage-test/Vtb_sd_storage "$mode" | tee "validation/boot_reject_$mode.log"
done
bash soc/tools/lint.sh | tee validation/soc_lint_summary.log
echo 'PASS storage regression; full CPU Linux boot and board timing are separate checks'
