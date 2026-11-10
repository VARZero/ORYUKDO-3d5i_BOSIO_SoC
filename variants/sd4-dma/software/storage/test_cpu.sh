#!/usr/bin/env bash
set -euo pipefail
ulimit -s unlimited
cd "$(dirname "$0")/../.."
mkdir -p validation
flags=();prefix=cpu_storage;build=/var/tmp/oryukdo-sd4-cpu-test
backend=(soc/tests/axi_ram_model.sv)
if [[ "${KFB_NATIVE_BACKEND:-0}" == 1 ]]; then
 flags=(-DKFB_NATIVE_BACKEND);prefix=cpu_storage_native;build=/var/tmp/oryukdo-sd4-cpu-native-test
 backend=(soc/board/kfb_axi_mig.sv soc/board/kfb_native_arbiter.sv soc/tests/kfb_native_ram_model.sv soc/tests/kfb_axi_ram_model.sv)
fi
riscv64-unknown-elf-gcc "${flags[@]}" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -O2 -ffreestanding -fno-builtin -fno-pic -msmall-data-limit=0 -mno-relax -nostdlib -nostartfiles -Wl,--no-relax -T soc/firmware/link.ld soc/firmware/start.S soc/tests/cpu_storage.c -o "validation/$prefix.elf"
riscv64-unknown-elf-objcopy -O binary "validation/$prefix.elf" "validation/$prefix.bin"
python3 - "$prefix" <<'PY'
from pathlib import Path
import sys
p='validation/'+sys.argv[1]
b=Path(p+'.bin').read_bytes();b+=b'\0'*(-len(b)%4)
Path(p+'.hex').write_text(''.join(f'{int.from_bytes(b[i:i+4],"little"):08x}\n' for i in range(0,len(b),4)))
PY
source soc/tools/xpm_verilator.sh
verilator "${XPM_ARGS[@]}" "${flags[@]}" --cc --exe --build "$PWD/soc/tests/sim_cpu_storage.cpp" --unroll-count 512 --no-timing --assert -j 4 -Wno-fatal -Wno-TIMESCALEMOD --top-module tb_cpu_storage --Mdir "$build" -f soc/bosio_sources.f "${backend[@]}" soc/tests/tb_cpu_storage.sv > "validation/${prefix}_build.log" 2>&1
for seed in 1 7 23; do
 "$build/Vtb_cpu_storage" +image="validation/$prefix.hex" +seed=$seed > "validation/${prefix}_seed${seed}.log" 2>&1
 cat "validation/${prefix}_seed${seed}.log"
done
