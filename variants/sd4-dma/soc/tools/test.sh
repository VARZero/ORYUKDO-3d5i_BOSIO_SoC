#!/usr/bin/env bash
set -euo pipefail
ulimit -s unlimited
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
for scene in uniform patterned; do
 suffix=""; flags=()
 if [[ "$scene" == patterned ]]; then suffix="_patterned"; flags=(-DPATTERN_SCENE=1); fi
 riscv64-unknown-elf-gcc "${flags[@]}" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -O2 -ffreestanding -fno-builtin -fno-pic -msmall-data-limit=0 -mno-relax -nostdlib -nostartfiles -Wl,--no-relax -T soc/firmware/link.ld soc/firmware/start.S soc/firmware/main.c -o "soc/reports/probe${suffix}.elf"
 riscv64-unknown-elf-objcopy -O binary "soc/reports/probe${suffix}.elf" "soc/reports/probe${suffix}.bin"
 python3 - "$suffix" <<'PY'
from pathlib import Path
import sys
stem='soc/reports/probe'+sys.argv[1]
b=Path(stem+'.bin').read_bytes(); b+=b'\0'*(-len(b)%4)
Path(stem+'.hex').write_text(''.join(f'{int.from_bytes(b[i:i+4],"little"):08x}\n' for i in range(0,len(b),4)))
PY
done
source soc/tools/xpm_verilator.sh
backend=(soc/tests/axi_ram_model.sv)
backend_flags=()
prefix=""
build_dir=/var/tmp/oryukdo-published/gen3_kfb_bosio_baseline
if [[ "${KFB_NATIVE_BACKEND:-0}" == 1 ]]; then
 backend=(soc/board/kfb_axi_mig.sv soc/board/kfb_native_arbiter.sv soc/tests/kfb_native_ram_model.sv soc/tests/kfb_axi_ram_model.sv)
 backend_flags=(-DKFB_NATIVE_BACKEND)
 prefix="native_"
 build_dir=/var/tmp/oryukdo-published/gen3_kfb_bosio_native
fi
build_dir=${KFB_BUILD_DIR:-$build_dir}
verilator "${XPM_ARGS[@]}" "${backend_flags[@]}" --cc --exe --build "$PWD/soc/tests/sim.cpp" --unroll-count 512 --no-timing --assert -j 6 -Wno-fatal -Wno-TIMESCALEMOD --top-module tb_gen3_bosio --Mdir "$build_dir" -f soc/bosio_sources.f "${backend[@]}" soc/tests/tb_gen3_bosio.sv >"soc/reports/${prefix}verilator_build.log" 2>&1
for scene in uniform patterned; do
 suffix=""; flags=()
 if [[ "$scene" == patterned ]]; then suffix="_patterned"; flags=(+pattern_scene); fi
 for seed in 1 7 23; do
  "$build_dir"/Vtb_gen3_bosio +image="soc/reports/probe${suffix}.hex" +seed=$seed +operand_check +render_check "${flags[@]}" | tee "soc/reports/${prefix}integration${suffix}_seed$seed.log"
 done
done
