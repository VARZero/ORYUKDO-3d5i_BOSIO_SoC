#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.."; pwd)
out=${1:-/var/tmp/oryukdo-bosio-engine-test}
mkdir -p "$out" "$root/software/bosio/reports"
gcc -std=c11 -Wall -Wextra -Werror -g -fsanitize=address,undefined \
 "$root/software/bosio/common/bosio_engine.c" "$root/software/bosio/tests/test_engine.c" -o "$out/test_engine"
"$out/test_engine" | tee "$root/software/bosio/reports/engine.log"
