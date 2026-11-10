#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p soc/reports
verilator --version >soc/reports/verilator_version.log
source soc/tools/xpm_verilator.sh
verilator "${XPM_ARGS[@]}" --lint-only --no-timing --unroll-count 512 --assert -Wno-fatal --top-module gen3_bosio_soc -f soc/bosio_sources.f >soc/reports/lint.log 2>&1
if grep -E '%(Error|Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT))' soc/reports/lint.log; then exit 1; fi
printf 'PASS lint: no errors, latches, multiple drivers or combinational loops\n'
