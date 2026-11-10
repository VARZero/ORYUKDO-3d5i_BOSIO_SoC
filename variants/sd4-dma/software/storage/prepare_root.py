from pathlib import Path
import os,sys
root=Path(sys.argv[1])
# The existing init remains the console supervisor; mount /data first in a
# small shell wrapper. A missing/unmountable card still permits a repair shell.
if not (root/'init.console').exists():
    (root/'init').rename(root/'init.console')
(root/'init').write_text('''#!/bin/sh
/bin/busybox mount -t devtmpfs devtmpfs /dev
/bin/busybox mkdir -p /data
n=0
while [ ! -b /dev/mmcblk0p2 ] && [ "$n" -lt 20 ]; do
 /bin/busybox sleep 1
 n=$((n+1))
done
if /bin/busybox mount -t ext4 -o noatime /dev/mmcblk0p2 /data; then
 echo "ORYUKDO: SD ext4 /data mounted"
else
 echo "ORYUKDO: /data unavailable; storage repair required"
fi
exec /init.console
''')
os.chmod(root/'init',0o755)
(root/'etc/oryukdo-image').write_text('ORYUKDO-SD4-DMA-v1 / BusyBox and BoAYO native-v2 preserved / hardware untested\n')
(root/'bin/storage-check').write_text('''#!/bin/sh
set -eu
grep -q ' /data ext4 ' /proc/mounts
testfile=/data/oryukdo-storage-check.$$
trap 'rm -f "$testfile"' EXIT
dd if=/dev/urandom of="$testfile" bs=4096 count=64
before=$(sha256sum "$testfile")
sync
echo 3 > /proc/sys/vm/drop_caches
after=$(sha256sum "$testfile")
test "$before" = "$after"
echo "PASS SD ext4 write/read after cache drop: $after"
''')
os.chmod(root/'bin/storage-check',0o755)
for name in ('dd','sha256sum','sync','rm','grep'):
    link=root/'bin'/name
    if not link.exists() and not link.is_symlink():
        link.symlink_to('busybox')
