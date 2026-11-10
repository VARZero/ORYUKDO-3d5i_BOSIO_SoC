#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.."; pwd)
out=${1:-/var/tmp/oryukdo-bosio-driver-rtl}
mkdir -p "$out" "$root/software/bosio/reports"
cd "$root"
python3 - "$out/sources.f" <<'PY'
from pathlib import Path
import sys
names=['soc/bosio/or_bo_axi_pkg.sv','soc/bosio/or_bo_axi_fabric.sv','soc/bosio/or_bo_bosio_axi.sv','soc/rtl/gen3_mul33_pipe.sv']
names += [n for n in Path('soc/bosio_sources.f').read_text().splitlines() if n.startswith('soc/vendor/')]
names += ['software/bosio/tests/bo_driver_ram.sv','software/bosio/tests/tb_bosio_driver.sv']
Path(sys.argv[1]).write_text('\n'.join(names)+'\n')
PY
gcc -std=c11 -Wall -Wextra -Werror -O2 -c software/bosio/common/bosio_engine.c -o "$out/engine.o"
verilator --cc --exe --build --assert --no-timing --unroll-count 512 -j 4 -O3 -Wno-fatal --top-module tb_bosio_driver \
  --Mdir "$out/model" -CFLAGS '-O2 -std=c++17' -LDFLAGS "$out/engine.o" \
  -f "$out/sources.f" "$root/software/bosio/tests/test_rtl.cpp" >"$out/build.log" 2>&1
for seed in 1 7 23; do
 "$out/model/Vtb_bosio_driver" "$seed" +seed="$seed" | tee "$root/software/bosio/reports/rtl_seed${seed}.log"
done
