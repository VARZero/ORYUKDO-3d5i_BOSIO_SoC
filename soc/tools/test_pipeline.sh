#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_pipeline_math --Mdir /var/tmp/oryukdo-published/gen3_clean_math soc/rtl/gen3_mul33_pipe.sv soc/vendor/projection/bosio_projector_mul_mul_8ns_25ns_32_4_1.v soc/tests/tb_pipeline_math.sv >soc/reports/math_build.log 2>&1
for seed in 1 7 23;do /var/tmp/oryukdo-published/gen3_clean_math/Vtb_pipeline_math +seed=$seed | tee soc/reports/math_seed$seed.log;done
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_pose_equivalence --Mdir /var/tmp/oryukdo-published/gen3_clean_pose soc/rtl/gen3_mul33_pipe.sv soc/tests/baseline_sensor_pose.v soc/vendor/output/bosio_v2_sensor_pose.v soc/tests/tb_pose_equivalence.sv >soc/reports/pose_build.log 2>&1
/var/tmp/oryukdo-published/gen3_clean_pose/Vtb_pose_equivalence | tee soc/reports/pose_equivalence.log
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_muldiv_equivalence --Mdir /var/tmp/oryukdo-published/gen3_clean_md soc/rtl/rv32_pkg.sv soc/rtl/gen3_mul33_pipe.sv soc/rtl/rv32_muldiv.sv soc/tests/baseline_muldiv.sv soc/tests/tb_muldiv_equivalence.sv >soc/reports/md_build.log 2>&1
for seed in 1 7 23;do /var/tmp/oryukdo-published/gen3_clean_md/Vtb_muldiv_equivalence +seed=$seed | tee soc/reports/md_seed$seed.log;done
verilator --binary --timing --assert -Wno-fatal -j 4 --top-module tb_projector_banks --Mdir /var/tmp/oryukdo-published/gen3_clean_banks soc/vendor/output/bosio_v2_projector.v soc/tests/tb_projector_banks.sv >soc/reports/banks_build.log 2>&1
/var/tmp/oryukdo-published/gen3_clean_banks/Vtb_projector_banks | tee soc/reports/projector_banks.log
