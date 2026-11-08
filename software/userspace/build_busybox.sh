#!/usr/bin/env bash
set -euo pipefail
export SOURCE_DATE_EPOCH=1794009600 KCONFIG_NOTIMESTAMP=1
out=${1:-/var/tmp/oryukdo-published/kfb-linux-1g}
mkdir -p "$out"; cd "$out"
cc=riscv64-linux-gnu-gcc
flags="-march=rv32ima_zicsr_zifencei -mabi=ilp32"
libgcc=$(riscv64-unknown-elf-gcc -march=rv32ima -mabi=ilp32 -print-libgcc-file-name)
fetch() {
    local url=$1 file=$2 sum=$3
    [[ -f "$file" ]] || curl -fLsS --retry 3 "$url" -o "$file"
    echo "$sum  $file" | sha256sum -c -
}
fetch https://musl.libc.org/releases/musl-1.2.5.tar.gz musl.tar.gz a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
fetch https://busybox.net/downloads/busybox-1.37.0.tar.bz2 busybox.tar.bz2 3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4
if [[ ! -e "$out/sysroot/lib/libc.a" ]]; then
tar xf musl.tar.gz
mkdir -p musl-build
(cd musl-build && CC="$cc $flags" AR=riscv64-linux-gnu-ar RANLIB=riscv64-linux-gnu-ranlib LIBCC="$libgcc" \
    ../musl-1.2.5/configure --target=riscv32-linux-musl --prefix="$out/sysroot" --disable-shared --enable-wrapper=gcc && make -j8 && make install)
fi
tar xf busybox.tar.bz2
# Use target Linux UAPI headers alongside musl without mixing glibc headers.
for name in linux asm asm-generic mtd; do ln -sfn "/usr/riscv64-linux-gnu/include/$name" "$out/sysroot/include/$name"; done
mkdir -p tool
python3 - "$out/sysroot/lib/musl-gcc.specs" "$libgcc" <<'PY'
import re,sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text().replace("libgcc.a%s %:if-exists(libgcc_eh.a%s)",sys.argv[2])
s=s.replace(" crtbeginS.o%s","").replace("crtendS.o%s ","").replace("-dynamic-linker ","-m elf32lriscv -dynamic-linker ")
p.with_name("rv32.specs").write_text(s)
PY
cat >tool/rv32-gcc <<EOF
#!/bin/sh
exec $cc $flags -no-pie -specs=$out/sysroot/lib/rv32.specs "\$@"
EOF
chmod +x tool/rv32-gcc
for util in ar as nm ld objcopy objdump ranlib strip; do ln -sfn "$(command -v riscv64-linux-gnu-$util)" tool/rv32-$util; done
cd busybox-1.37.0
make allnoconfig </dev/null
python3 - <<'PY'
from pathlib import Path
p=Path(".config")
s=p.read_text()
for k in """LFS STATIC ASH FEATURE_SH_MATH FEATURE_SH_MATH_64 ASH_HELP SH_IS_ASH ASH_JOB_CONTROL ASH_ALIAS ASH_ECHO ASH_PRINTF ASH_TEST ASH_GETOPTS ASH_CMDCMD FEATURE_SH_STANDALONE FEATURE_PREFER_APPLETS FEATURE_EDITING FEATURE_TAB_COMPLETION CAT ECHO LS PWD UNAME FREE HEAD GREP MOUNT MOUNTPOINT MKDIR SLEEP PS ENV TRUE FALSE TEST PRINTF DMESG CLEAR TTY STTY SETSID SYNC DATE WC CP MV RM TOUCH""".split():
    s=s.replace(f"# CONFIG_{k} is not set",f"CONFIG_{k}=y")
s=s.replace("CONFIG_SH_IS_NONE=y","# CONFIG_SH_IS_NONE is not set")
p.write_text(s.replace("CONFIG_FEATURE_EDITING_MAX_LEN=0","CONFIG_FEATURE_EDITING_MAX_LEN=512").replace("CONFIG_FEATURE_EDITING_HISTORY=0","CONFIG_FEATURE_EDITING_HISTORY=16").replace("CONFIG_FEATURE_COPYBUF_KB=0","CONFIG_FEATURE_COPYBUF_KB=4"))
PY
make oldconfig < <(yes "") >/dev/null
make -j8 CROSS_COMPILE="$out/tool/rv32-" CONFIG_EXTRA_CFLAGS="-Os" busybox
riscv64-linux-gnu-strip -o "$out/busybox" busybox
file "$out/busybox"
riscv64-linux-gnu-readelf -A "$out/busybox"
